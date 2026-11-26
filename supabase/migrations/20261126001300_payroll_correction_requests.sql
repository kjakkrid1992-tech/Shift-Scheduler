-- Review only. Does not reopen or alter payroll.
begin;
create table public.payroll_correction_requests (
 id uuid primary key default gen_random_uuid(),
 final_id uuid not null references public.payroll_final(id) on delete restrict,
 category text not null check(category in ('attendance','rate','income','deduction','payment','other')),
 description text not null check(length(btrim(description)) between 1 and 2000),
 proposed_delta_satang bigint check(proposed_delta_satang between -1000000000 and 1000000000),
 status text not null default 'pending' check(status in ('pending','needs_adjustment','dismissed')),
 requested_by uuid not null references public.user_profiles(user_id),
 requested_at timestamptz not null default now(),
 reviewed_by uuid references public.user_profiles(user_id),
 reviewed_at timestamptz,
 review_note text,
 check((status='pending' and reviewed_by is null and reviewed_at is null and review_note is null) or
 (status<>'pending' and reviewed_by is not null and reviewed_at is not null and review_note is not null and length(btrim(review_note)) between 1 and 2000))
);
create index payroll_correction_final_idx on public.payroll_correction_requests(final_id,requested_at);
alter table public.payroll_correction_requests enable row level security;
revoke all on table public.payroll_correction_requests from public,anon,authenticated;
grant select on table public.payroll_correction_requests to authenticated;
create policy staff_read on public.payroll_correction_requests for select to authenticated using ((select staff_private.staff_role()) in ('owner','manager'));
create function public.request_payroll_correction(p_final uuid,p_category text,p_description text,p_delta bigint default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare k uuid;
begin
 if coalesce(staff_private.staff_role(),'') not in ('owner','manager') then raise exception using errcode='42501',message='Staff access required';end if;
 if p_category is null or p_category not in ('attendance','rate','income','deduction','payment','other') or p_description is null or length(btrim(p_description)) not between 1 and 2000 or (p_delta is not null and p_delta not between -1000000000 and 1000000000) then raise exception 'Invalid correction request';end if;
 perform 1 from public.payroll_final where id=p_final for update;
 if not found then raise exception 'Final payroll not found';end if;
 select id into k from public.payroll_correction_requests where final_id=p_final and category=p_category and description=btrim(p_description) and proposed_delta_satang is not distinct from p_delta and requested_by=auth.uid() and status='pending' order by requested_at limit 1;
 if found then return k;end if;
 insert into public.payroll_correction_requests(final_id,category,description,proposed_delta_satang,requested_by) values(p_final,p_category,btrim(p_description),p_delta,auth.uid()) returning id into k;
 return k;
end $$;
create function public.review_payroll_correction(p_id uuid,p_status text,p_note text)
returns uuid language plpgsql security definer set search_path='' as $$
declare r public.payroll_correction_requests%rowtype;
begin
 if coalesce(staff_private.staff_role(),'')<>'owner' then raise exception using errcode='42501',message='Only owner can review payroll correction';end if;
 if p_status is null or p_status not in ('needs_adjustment','dismissed') or p_note is null or length(btrim(p_note)) not between 1 and 2000 then raise exception 'Review decision and evidence required';end if;
 select * into r from public.payroll_correction_requests where id=p_id for update;
 if not found or r.status<>'pending' then raise exception 'STALE_CORRECTION: reload';end if;
 update public.payroll_correction_requests set status=p_status,reviewed_by=auth.uid(),reviewed_at=now(),review_note=btrim(p_note) where id=p_id;
 return p_id;
end $$;
revoke all on function public.request_payroll_correction(uuid,text,text,bigint) from public,anon,authenticated;
revoke all on function public.review_payroll_correction(uuid,text,text) from public,anon,authenticated;
grant execute on function public.request_payroll_correction(uuid,text,text,bigint) to authenticated;
grant execute on function public.review_payroll_correction(uuid,text,text) to authenticated;
commit;
