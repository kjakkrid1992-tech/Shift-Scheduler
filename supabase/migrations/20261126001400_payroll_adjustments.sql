-- Phase 7.6B. Separate net-cash adjustment register; no automatic payroll deduction.
begin;
create table public.payroll_adjustments (
 id uuid primary key default gen_random_uuid(),
 request_id uuid not null unique references public.payroll_correction_requests(id) on delete restrict,
 final_id uuid not null references public.payroll_final(id) on delete restrict,
 delta_satang bigint not null check(delta_satang between -1000000000 and 1000000000 and delta_satang<>0),
 approval_note text not null check(length(btrim(approval_note)) between 1 and 2000),
 approved_by uuid not null references public.user_profiles(user_id),
 approved_at timestamptz not null default now(),
 status text not null default 'approved' check(status in ('approved','settled','cancelled')),
 settled_date date,
 method text check(method in ('cash','transfer')),
 reference text,
 settled_by uuid references public.user_profiles(user_id),
 settled_at timestamptz,
 cancel_note text,
 cancelled_by uuid references public.user_profiles(user_id),
 cancelled_at timestamptz,
 check((status='settled' and settled_date is not null and method is not null and reference is not null and length(btrim(reference)) between 1 and 500 and settled_by is not null and settled_at is not null) or
 (status<>'settled' and settled_date is null and method is null and reference is null and settled_by is null and settled_at is null)),
 check((status='cancelled' and cancel_note is not null and length(btrim(cancel_note)) between 1 and 2000 and cancelled_by is not null and cancelled_at is not null) or
 (status<>'cancelled' and cancel_note is null and cancelled_by is null and cancelled_at is null))
);
create index payroll_adjustments_final_idx on public.payroll_adjustments(final_id);
create index payroll_adjustments_settled_idx on public.payroll_adjustments(settled_date) where status='settled';
alter table public.payroll_adjustments enable row level security;
revoke all on table public.payroll_adjustments from public,anon,authenticated;
grant select on table public.payroll_adjustments to authenticated;
create policy staff_read on public.payroll_adjustments for select to authenticated using ((select staff_private.staff_role()) in ('owner','manager'));
-- Only the owner can approve a separately reviewed correction after original salary payment.
-- Negative amounts are voluntary external returns, NEVER withholding from future pay.
create function public.approve_payroll_adjustment(p_request uuid,p_delta bigint,p_note text)
returns uuid language plpgsql security definer set search_path='' as $$
declare r public.payroll_correction_requests%rowtype; z public.payroll_final%rowtype; a public.payroll_adjustments%rowtype; reserved bigint;
begin
 if coalesce(staff_private.staff_role(),'')<>'owner' then raise exception using errcode='42501',message='Only owner can approve adjustment';end if;
 if p_delta is null or p_delta=0 or p_delta not between -1000000000 and 1000000000 or p_note is null or length(btrim(p_note)) not between 1 and 2000 then raise exception 'Invalid adjustment amount or evidence';end if;
 select * into r from public.payroll_correction_requests where id=p_request for update;
 if not found or r.status<>'needs_adjustment' then raise exception 'Reviewed correction required';end if;
 if r.category='payment' then raise exception 'Payment metadata correction requires separate reconciliation';end if;
 select * into z from public.payroll_final where id=r.final_id for update;
 if not found or z.paid_at is null then raise exception 'Original payroll must be recorded as paid first; reconcile unpaid errors separately';end if;
 select * into a from public.payroll_adjustments where request_id=r.id;
 if found then
  if a.status='approved' and a.delta_satang=p_delta and a.approval_note=btrim(p_note) then return a.id;end if;
  raise exception 'Adjustment already exists for request';
 end if;
 -- Reserve recoveries against original net only, independent of future payroll or advance allocations.
 if p_delta<0 then
  select coalesce(sum(-delta_satang),0) into reserved from public.payroll_adjustments where final_id=z.id and delta_satang<0 and status in ('approved','settled');
  if reserved-p_delta>z.net_satang then raise exception 'Return exceeds original net paid';end if;
 end if;
 insert into public.payroll_adjustments(request_id,final_id,delta_satang,approval_note,approved_by) values(r.id,z.id,p_delta,btrim(p_note),auth.uid()) returning * into a;
 return a.id;
end $$;
create function public.settle_payroll_adjustment(p_id uuid,p_date date,p_method text,p_reference text)
returns uuid language plpgsql security definer set search_path='' as $$
declare a public.payroll_adjustments%rowtype; z public.payroll_final%rowtype; fid uuid;
begin
 if coalesce(staff_private.staff_role(),'')<>'owner' then raise exception using errcode='42501',message='Only owner can record settlement';end if;
 select final_id into fid from public.payroll_adjustments where id=p_id;
 if not found then raise exception 'Adjustment not found';end if;
 select * into z from public.payroll_final where id=fid for update;
 select * into a from public.payroll_adjustments where id=p_id for update;
 if a.status<>'approved' then raise exception 'Adjustment is no longer awaiting settlement';end if;
 if p_date is null or p_date<z.paid_date or p_date>(now() at time zone 'Asia/Bangkok')::date or p_method is null or p_method not in ('cash','transfer') or p_reference is null or length(btrim(p_reference)) not between 1 and 500 then raise exception 'Invalid actual settlement evidence';end if;
 update public.payroll_adjustments set status='settled',settled_date=p_date,method=p_method,reference=btrim(p_reference),settled_by=auth.uid(),settled_at=now() where id=p_id;
 return p_id;
end $$;
create function public.cancel_payroll_adjustment(p_id uuid,p_note text)
returns uuid language plpgsql security definer set search_path='' as $$
declare a public.payroll_adjustments%rowtype; fid uuid;
begin
 if coalesce(staff_private.staff_role(),'')<>'owner' then raise exception using errcode='42501',message='Only owner can cancel adjustment';end if;
 if p_note is null or length(btrim(p_note)) not between 1 and 2000 then raise exception 'Cancellation evidence required';end if;
 select final_id into fid from public.payroll_adjustments where id=p_id;
 if not found then raise exception 'Adjustment not found';end if;
 perform 1 from public.payroll_final where id=fid for update;
 select * into a from public.payroll_adjustments where id=p_id for update;
 if a.status<>'approved' then raise exception 'Adjustment is no longer awaiting settlement';end if;
 update public.payroll_adjustments set status='cancelled',cancel_note=btrim(p_note),cancelled_by=auth.uid(),cancelled_at=now() where id=p_id;
 return p_id;
end $$;
create function public.payroll_adjustment_report(p_month date,p_employee uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare y date; last_day date; first_day date; cutoff date; result jsonb;
begin
 if coalesce(staff_private.staff_role(),'') not in ('owner','manager') then raise exception using errcode='42501',message='Staff access required';end if;
 if p_month is null or extract(day from p_month)<>1 or p_month<'1900-02-01' or p_month>'2199-12-01' then raise exception 'Invalid month';end if;
 y:=date_trunc('year',p_month::timestamp)::date; first_day:=(p_month-interval '1 month'+interval '25 days')::date; last_day:=p_month+24; cutoff:=least((y+interval '1 year'-interval '1 day')::date,(now() at time zone 'Asia/Bangkok')::date);
 select jsonb_build_object(
 'pending_pay',coalesce(sum(delta_satang) filter(where a.status='approved' and delta_satang>0 and z.period_start=first_day),0),
 'pending_return',coalesce(sum(-delta_satang) filter(where a.status='approved' and delta_satang<0 and z.period_start=first_day),0),
 'period_paid',coalesce(sum(delta_satang) filter(where a.status='settled' and delta_satang>0 and settled_date between first_day and last_day),0),
 'period_returned',coalesce(sum(-delta_satang) filter(where a.status='settled' and delta_satang<0 and settled_date between first_day and last_day),0),
 'ytd_paid',coalesce(sum(delta_satang) filter(where a.status='settled' and delta_satang>0 and settled_date between y and cutoff),0),
 'ytd_returned',coalesce(sum(-delta_satang) filter(where a.status='settled' and delta_satang<0 and settled_date between y and cutoff),0))
 into result from public.payroll_adjustments a join public.payroll_final z on z.id=a.final_id join public.employment_records j on j.id=z.employment_id where p_employee is null or j.employee_id=p_employee;
 return result;
end $$;
revoke all on function public.approve_payroll_adjustment(uuid,bigint,text),public.settle_payroll_adjustment(uuid,date,text,text),public.cancel_payroll_adjustment(uuid,text),public.payroll_adjustment_report(date,uuid) from public,anon,authenticated;
grant execute on function public.approve_payroll_adjustment(uuid,bigint,text),public.settle_payroll_adjustment(uuid,date,text,text),public.cancel_payroll_adjustment(uuid,text),public.payroll_adjustment_report(date,uuid) to authenticated;
commit;
