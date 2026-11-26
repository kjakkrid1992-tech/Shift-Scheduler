-- Phase 5B.2: pilot finalization; apply once after 00800.
begin;
create table public.payroll_closures (
 period_start date primary key references public.pay_periods(start_date) on delete restrict,
 period_end date not null,
 approved_by uuid not null references public.user_profiles(user_id),
 approved_at timestamptz not null default now(),
 approval_note text not null check(length(btrim(approval_note)) between 1 and 2000)
);
create table public.payroll_final (
 id uuid primary key default gen_random_uuid(),
 period_start date not null references public.payroll_closures(period_start) on delete restrict,
 employment_id uuid not null references public.employment_records(id) on delete restrict,
 draft_id uuid not null unique references public.payroll_drafts(id) on delete restrict,
 draft_revision integer not null,
 snapshot jsonb not null check(jsonb_typeof(snapshot)='object'),
 net_satang bigint not null check(net_satang>=0),
 deduction_evidence text not null default '',
 paid_date date,
 payment_method text check(payment_method in ('cash','transfer','none')),
 payment_reference text check(length(payment_reference)<=300),
 paid_by uuid references public.user_profiles(user_id),
 paid_at timestamptz,
 unique(period_start,employment_id),
 check((paid_date is null and payment_method is null and payment_reference is null and paid_by is null and paid_at is null) or
 (paid_date is not null and payment_method is not null and payment_reference is not null and paid_by is not null and paid_at is not null)),
 check(payment_method is null or (net_satang=0 and payment_method='none') or (net_satang>0 and payment_method in ('cash','transfer')))
);
create table public.payroll_advance_allocations (
 final_id uuid not null references public.payroll_final(id) on delete restrict,
 advance_id uuid not null references public.cash_advances(id) on delete restrict,
 amount_satang bigint not null check(amount_satang>0),
 primary key(final_id,advance_id)
);
create index payroll_alloc_advance_idx on public.payroll_advance_allocations(advance_id);
do $$
declare tbl text;
begin
 foreach tbl in array array['payroll_closures','payroll_final','payroll_advance_allocations'] loop
  execute format('alter table public.%I enable row level security',tbl);
  execute format('revoke all on table public.%I from public,anon,authenticated',tbl);
  execute format('grant select on table public.%I to authenticated',tbl);
  execute format('create policy staff_read on public.%I for select to authenticated using ((select staff_private.staff_role()) in (''owner'',''manager''))',tbl);
 end loop;
end $$;
create or replace function public.preview_payroll(p_employment uuid,p_month date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare first_day date; last_day date; cutoff date; job public.employment_records%rowtype; emp public.employees%rowtype;
 days jsonb; advances jsonb; paid_total bigint; dept_name text;
begin
 if coalesce(staff_private.staff_role(),'') not in ('owner','manager') then raise exception using errcode='42501',message='Staff access required'; end if;
 if p_month is null or extract(day from p_month)<>1 or p_month<'1900-02-01' or p_month>'2199-12-01' then raise exception 'Invalid payroll month'; end if;
 first_day:=(p_month-interval '1 month'+interval '25 days')::date;
 last_day:=p_month+24;
 cutoff:=least(last_day,(now() at time zone 'Asia/Bangkok')::date);
 select * into job from public.employment_records where id=p_employment;
 if not found or job.start_date>last_day or (job.end_date is not null and job.end_date<first_day) then raise exception 'Employment not in payroll period'; end if;
 select * into emp from public.employees where id=job.employee_id;
 select name into dept_name from public.departments where id=job.department_id;
 -- Include every elapsed eligible date, even with no attendance; missing is not zero pay.
 select coalesce(jsonb_agg(jsonb_build_object(
  'date',g.d::date,'attendance_id',ar.id,'attendance_revision',ar.revision,'status',ar.status,
  'type',ar.attendance_type,'work_minutes',ar.work_minutes,'normal_minutes',ar.normal_minutes,'ot_minutes',ar.ot_minutes,
  'rate_id',rate_at.id,'base_rate',rate_at.base_rate,'ot_rate',rate_at.ot_rate,'rate_from',rate_at.effective_from
 ) order by g.d),'[]'::jsonb) into days
 from generate_series(greatest(first_day,job.start_date)::timestamp,least(cutoff,coalesce(job.end_date,last_day))::timestamp,interval '1 day') g(d)
 left join public.attendance_records ar on ar.employment_id=job.id and ar.work_date=g.d::date
 left join lateral (select cr.id,cr.base_rate,cr.ot_rate,cr.effective_from from public.compensation_history cr
  where cr.employment_id=job.id and cr.effective_from<=g.d::date and cr.pay_type=job.employment_type
  order by cr.effective_from desc limit 1) rate_at on true;
 -- Available unpaid deduction balance, including earlier paid advances for the same employment.
 select coalesce(jsonb_agg(jsonb_build_object('id',ca.id,'revision',ca.revision,'date',ca.paid_date,'amount_satang',ca.amount_satang-used.total,'original_satang',ca.amount_satang) order by ca.paid_date,ca.id),'[]'::jsonb),
  coalesce(sum(ca.amount_satang-used.total),0)::bigint into advances,paid_total
 from public.cash_advances ca
 cross join lateral (select coalesce(sum(a.amount_satang),0)::bigint total from public.payroll_advance_allocations a where a.advance_id=ca.id) used
 where ca.employment_id=job.id and ca.status='paid' and ca.paid_date<=cutoff and ca.amount_satang>used.total;
 return jsonb_build_object('employment_id',job.id,'employee_code',emp.employee_code,'employee_name',btrim(emp.first_name||' '||emp.last_name),'department',dept_name,'position',job.position,'pay_type',job.employment_type,
 'period_start',first_day,'period_end',last_day,'as_of',cutoff,'days',days,'paid_advances',advances,'paid_advance_satang',paid_total,'policy','UNVERIFIED_DRAFT_ONLY');
end $$;

-- Source freeze applies at database level, including older browser clients.
create function staff_private.payroll_freeze() returns trigger
language plpgsql security definer set search_path='' as $$
declare j jsonb; k jsonb; d date; ending date; pid uuid; sid uuid; aid uuid; jid uuid;
begin
 -- The finalizer and source changes are designed for READ COMMITTED.
 if current_setting('transaction_isolation')<>'read committed' then raise exception 'Payroll source writes require read committed'; end if;
 if tg_op<>'INSERT' then j:=to_jsonb(old);end if;
 if tg_op<>'DELETE' then k:=to_jsonb(new);end if;
 if tg_table_name='employment_records' then
  -- New or changed employment must not change the closed roster or covered dates.
  if tg_op='INSERT' then
   if exists(select 1 from public.payroll_closures c where new.start_date<=c.period_end and coalesce(new.end_date,'infinity'::date)>=c.period_start) then raise exception 'PAYROLL_LOCKED: employment overlaps closed period';end if;
  elsif tg_op='DELETE' then
   if exists(select 1 from public.payroll_final z where z.employment_id=old.id) then raise exception 'PAYROLL_LOCKED: closed employment';end if;
  else
   if exists(select 1 from public.payroll_closures c where
    (old.start_date<=c.period_end and coalesce(old.end_date,'infinity'::date)>=c.period_start or new.start_date<=c.period_end and coalesce(new.end_date,'infinity'::date)>=c.period_start)
    and (old.employee_id is distinct from new.employee_id or old.department_id is distinct from new.department_id or old.position is distinct from new.position or old.employment_type is distinct from new.employment_type or
    greatest(old.start_date,c.period_start) is distinct from greatest(new.start_date,c.period_start) or least(coalesce(old.end_date,'infinity'::date),c.period_end) is distinct from least(coalesce(new.end_date,'infinity'::date),c.period_end))) then raise exception 'PAYROLL_LOCKED: employment dates or terms';end if;
  end if;
 elsif tg_table_name='compensation_history' then
  if exists(select 1 from public.payroll_final z join public.payroll_closures c using(period_start)
    where (z.employment_id=(j->>'employment_id')::uuid and (j->>'effective_from')::date<=c.period_end)
       or (z.employment_id=(k->>'employment_id')::uuid and (k->>'effective_from')::date<=c.period_end)) then raise exception 'PAYROLL_LOCKED: historical rate';end if;
 elsif tg_table_name='attendance_records' then
  if exists(select 1 from public.payroll_closures c where (j->>'work_date')::date between c.period_start and c.period_end or (k->>'work_date')::date between c.period_start and c.period_end) then raise exception 'PAYROLL_LOCKED: attendance';end if;
 elsif tg_table_name='cash_advances' then
  -- Allow an old unpaid request to be cancelled/paid in an open period, but never change a paid source used in closure.
  if exists(select 1 from public.payroll_advance_allocations a where a.advance_id=(j->>'id')::uuid)
    or exists(select 1 from public.payroll_closures c where
      (j->>'status' in ('paid','voided') and (j->>'paid_date')::date between c.period_start and c.period_end)
      or (k->>'status' in ('paid','voided') and (k->>'paid_date')::date between c.period_start and c.period_end)) then raise exception 'PAYROLL_LOCKED: paid advance';end if;
 elsif tg_table_name='payroll_drafts' then
  if exists(select 1 from public.payroll_closures c where c.period_start in ((j->>'period_start')::date,(k->>'period_start')::date)) then raise exception 'PAYROLL_LOCKED: draft';end if;
 elsif tg_table_name='shift_schedules' then
  if exists(select 1 from public.pay_periods p join public.payroll_closures c on c.period_start=p.start_date where p.id in ((j->>'period_id')::uuid,(k->>'period_id')::uuid)) then raise exception 'PAYROLL_LOCKED: schedule';end if;
 elsif tg_table_name='shift_assignments' then
  if exists(select 1 from public.shift_schedules ss join public.pay_periods p on p.id=ss.period_id join public.payroll_closures c on c.period_start=p.start_date where ss.id in ((j->>'schedule_id')::uuid,(k->>'schedule_id')::uuid)) then raise exception 'PAYROLL_LOCKED: shift';end if;
 end if;
 if tg_op='DELETE' then return old;end if;return new;
end $$;
revoke all on function staff_private.payroll_freeze() from public,anon,authenticated;
do $$
declare tbl text;
begin
 foreach tbl in array array['employment_records','compensation_history','attendance_records','cash_advances','payroll_drafts','shift_schedules','shift_assignments'] loop
  execute format('create trigger payroll_freeze before insert or update or delete on public.%I for each row execute function staff_private.payroll_freeze()',tbl);
 end loop;
end $$;
-- One atomic close for the whole company. Evidence is keyed by draft UUID.
-- NOWAIT prevents locking behind active source writers; retry after saving/reloading.
create function public.close_payroll(p_month date,p_reviews jsonb,p_note text)
returns date language plpgsql security definer set search_path='' as $$
declare first_day date; last_day date; job public.employment_records%rowtype; dr public.payroll_drafts%rowtype;
 src jsonb; r jsonb; remain bigint; take_amt bigint; final_key uuid; evidence text; cnt integer:=0;
begin
 if coalesce(staff_private.staff_role(),'')<>'owner' then raise exception using errcode='42501',message='Only owner can close payroll';end if;
 if current_setting('transaction_isolation')<>'read committed' then raise exception 'Payroll close requires read committed';end if;
 if p_month is null or extract(day from p_month)<>1 or p_month<'1900-02-01' or p_month>'2199-12-01' or jsonb_typeof(p_reviews) is distinct from 'object' or p_note is null or length(btrim(p_note)) not between 1 and 2000 then raise exception 'Invalid payroll close inputs';end if;
 first_day:=(p_month-interval '1 month'+interval '25 days')::date;last_day:=p_month+24;
 if last_day>=(now() at time zone 'Asia/Bangkok')::date then raise exception 'Payroll period has not ended';end if;
 lock table public.employees,public.departments,public.employment_records,public.compensation_history,public.pay_periods,public.shift_schedules,public.shift_assignments,public.attendance_records,public.cash_advances,public.payroll_drafts,public.payroll_closures,public.payroll_final,public.payroll_advance_allocations in share row exclusive mode nowait;
 if exists(select 1 from public.payroll_closures c where c.period_start>=first_day) then raise exception 'Payroll already closed or later period closed';end if;
 -- Validate all reviewed versions and sources before writing any closure/allocation.
 for job in select * from public.employment_records where start_date<=last_day and coalesce(end_date,'infinity'::date)>=first_day order by id loop
  cnt:=cnt+1;
  select * into dr from public.payroll_drafts where employment_id=job.id and period_start=first_day;
  if not found or dr.item_breakdown is null then raise exception 'Missing itemized draft for employment %',job.id;end if;
  if (p_reviews->(dr.id::text)->>'revision')::integer is distinct from dr.revision then raise exception 'STALE_PAYROLL_DRAFT: reload reviewed roster';end if;
  src:=public.preview_payroll(job.id,p_month);
  if src is distinct from dr.source_snapshot then raise exception 'STALE_PAYROLL_SOURCE: employment %',job.id;end if;
  if exists(select 1 from jsonb_array_elements(src->'days') x(v) where v->>'status' is distinct from 'approved') then raise exception 'Attendance incomplete or unapproved for employment %',job.id;end if;
  if dr.net_satang<0 then raise exception 'Negative net for employment %',job.id;end if;
  evidence:=coalesce(btrim(p_reviews->(dr.id::text)->>'evidence'),'');
  if length(evidence)>1000 or ((dr.advance_deduction_satang+dr.other_deduction_satang)>0 and length(evidence)=0) then raise exception 'Deduction review evidence required for employment %',job.id;end if;
  if dr.advance_deduction_satang>(src->>'paid_advance_satang')::bigint then raise exception 'Advance balance insufficient';end if;
 end loop;
 if cnt=0 or (select count(*) from jsonb_object_keys(p_reviews))<>cnt then raise exception 'Reviewed roster incomplete or empty';end if;
 perform staff_private.advance_period(first_day);
 insert into public.payroll_closures(period_start,period_end,approved_by,approval_note) values(first_day,last_day,auth.uid(),btrim(p_note));
 for dr in select d.* from public.payroll_drafts d join public.employment_records j on j.id=d.employment_id
   where d.period_start=first_day and j.start_date<=last_day and coalesce(j.end_date,'infinity'::date)>=first_day order by d.employment_id loop
  evidence:=coalesce(btrim(p_reviews->(dr.id::text)->>'evidence'),'');
  insert into public.payroll_final(period_start,employment_id,draft_id,draft_revision,snapshot,net_satang,deduction_evidence)
   values(first_day,dr.employment_id,dr.id,dr.revision,to_jsonb(dr),dr.net_satang,evidence) returning id into final_key;
  remain:=dr.advance_deduction_satang;
  for r in select value from jsonb_array_elements(dr.source_snapshot->'paid_advances') loop
   exit when remain=0;
   take_amt:=least(remain,(r->>'amount_satang')::bigint);
   if take_amt>0 then insert into public.payroll_advance_allocations(final_id,advance_id,amount_satang) values(final_key,(r->>'id')::uuid,take_amt);remain:=remain-take_amt;end if;
  end loop;
  if remain<>0 then raise exception 'Advance allocation incomplete';end if;
 end loop;
 return first_day;
end $$;
create function public.record_payroll_payment(p_id uuid,p_date date,p_method text,p_reference text)
returns uuid language plpgsql security definer set search_path='' as $$
declare z public.payroll_final%rowtype;
begin
 if coalesce(staff_private.staff_role(),'')<>'owner' then raise exception using errcode='42501',message='Only owner can record payroll payment';end if;
 select * into z from public.payroll_final where id=p_id for update;
 if not found then raise exception 'Final payroll not found';end if;
 if z.paid_at is not null then raise exception 'Payroll payment already recorded';end if;
 if p_date is null or p_date<z.period_start or p_date>(now() at time zone 'Asia/Bangkok')::date or p_method is null or p_reference is null or length(btrim(p_reference))>300
 or (z.net_satang=0 and p_method<>'none') or (z.net_satang>0 and p_method not in ('cash','transfer')) or (p_method='transfer' and length(btrim(p_reference))=0) then raise exception 'Invalid payroll payment details';end if;
 update public.payroll_final set paid_date=p_date,payment_method=p_method,payment_reference=btrim(p_reference),paid_by=auth.uid(),paid_at=now() where id=p_id;
 return p_id;
end $$;
revoke all on function public.close_payroll(date,jsonb,text) from public,anon,authenticated;
revoke all on function public.record_payroll_payment(uuid,date,text,text) from public,anon,authenticated;
grant execute on function public.close_payroll(date,jsonb,text) to authenticated;
grant execute on function public.record_payroll_payment(uuid,date,text,text) to authenticated;
commit;
