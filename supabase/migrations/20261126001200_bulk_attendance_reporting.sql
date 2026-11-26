-- Phase 7.2–7.5 pilot, after 01100. No data rewrite or new tables.
begin;
-- Explicitly reviewed rows only, all-or-nothing. Existing RPCs enforce source locks,
-- permissions, revisions, time validity and audit. Ordered by employment to reduce deadlocks.
create function public.bulk_attendance(p_date date,p_department uuid,p_schedule uuid,p_action text,p_rows jsonb)
returns integer language plpgsql security definer set search_path='' as $$
declare r jsonb; j uuid; rec public.attendance_records%rowtype; saved uuid; n integer:=0;
begin
 if coalesce(staff_private.staff_role(),'') not in ('owner','manager') then raise exception using errcode='42501',message='Staff access required';end if;
 if p_action is null or p_action not in ('save','save_verify','verify','approve') or p_date is null or p_department is null or p_schedule is null or jsonb_typeof(p_rows) is distinct from 'array' then raise exception 'Invalid bulk request';end if;
 if p_action='approve' and staff_private.staff_role()<>'owner' then raise exception using errcode='42501',message='Only owner can approve';end if;
 if jsonb_array_length(p_rows) not between 1 and 100 or (select count(distinct x->>'employment_id') from jsonb_array_elements(p_rows) x)<>jsonb_array_length(p_rows) then raise exception 'Invalid or duplicate bulk selection';end if;
 -- Serialize against schedule changes while allowing parallel ordinary reads.
 lock table public.shift_schedules,public.shift_assignments in share mode nowait;
 if not exists(select 1 from public.shift_schedules s join public.pay_periods p on p.id=s.period_id where s.id=p_schedule and s.department_id=p_department and s.status='confirmed' and p_date between p.start_date and p.end_date and not exists(select 1 from public.shift_schedules later where later.period_id=s.period_id and later.department_id=s.department_id and later.status='confirmed' and later.version>s.version)) then raise exception 'STALE_PLAN: reload';end if;
 for r in select value from jsonb_array_elements(p_rows) order by value->>'employment_id' loop
  j:=(r->>'employment_id')::uuid;
  if jsonb_typeof(r->'revision') is distinct from 'number' or (r->>'revision') !~ '^[0-9]+$' then raise exception 'Invalid bulk revision';end if;
  perform 1 from public.employment_records where id=j and department_id=p_department and start_date<=p_date and coalesce(end_date,'infinity'::date)>=p_date for update;
  if not found then raise exception 'Employment outside bulk scope';end if;
  if p_action in ('save','save_verify') then
   -- New records only; existing drafts can be edited with individual editor.
   if (r->>'revision')::integer<>0 then raise exception 'Bulk entry is for new records only';end if;
   saved:=public.save_attendance(j,p_date,p_schedule,0,r->>'type',(r->>'start')::time,(r->>'end')::time,(r->>'overnight')::boolean,(r->>'break')::integer,(r->>'normal')::integer,r->>'note');
   if p_action='save_verify' then perform public.transition_attendance(saved,1,'verify','');end if;
  else
   select * into rec from public.attendance_records where employment_id=j and work_date=p_date and department_id=p_department for update;
   if not found or rec.id is distinct from (r->>'id')::uuid then raise exception 'STALE_ATTENDANCE: reload';end if;
   perform public.transition_attendance(rec.id,(r->>'revision')::integer,p_action,'');
  end if;
  n:=n+1;
 end loop;
 return n;
end $$;
revoke all on function public.bulk_attendance(date,uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.bulk_attendance(date,uuid,uuid,text,jsonb) to authenticated;
-- Read-only reporting. All figures refer to the selected pay period except current headcount
-- and actual-payment YTD. Legacy records deliberately excluded from arithmetic.
create function public.staff_period_report(p_month date,p_employee uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare first_day date; last_day date; today date:=(now() at time zone 'Asia/Bangkok')::date; cutoff date; yr date; yr_end date; result jsonb;
begin
 if coalesce(staff_private.staff_role(),'') not in ('owner','manager') then raise exception using errcode='42501',message='Staff access required';end if;
 if p_month is null or extract(day from p_month)<>1 or p_month<'1900-02-01' or p_month>'2199-12-01' then raise exception 'Invalid report month';end if;
 if p_employee is not null and not exists(select 1 from public.employees where id=p_employee) then raise exception 'Employee not found';end if;
 first_day:=(p_month-interval '1 month'+interval '25 days')::date;last_day:=p_month+24;cutoff:=least(last_day,today);yr:=date_trunc('year',p_month::timestamp)::date;yr_end:=least((yr+interval '1 year'-interval '1 day')::date,today);
 with jobs as (select j.* from public.employment_records j where p_employee is null or j.employee_id=p_employee),
 attendance as (select a.* from public.attendance_records a join jobs j on j.id=a.employment_id where a.work_date between first_day and cutoff),
 finals as (select z.* from public.payroll_final z join jobs j on j.id=z.employment_id where z.period_start=first_day),
 drafts as (select d.* from public.payroll_drafts d join jobs j on j.id=d.employment_id where d.period_start=first_day and not exists(select 1 from finals z where z.draft_id=d.id)),
 advances as (select ca.*,coalesce((select sum(a.amount_satang) from public.payroll_advance_allocations a where a.advance_id=ca.id),0) as allocated from public.cash_advances ca join jobs j on j.id=ca.employment_id where ca.status='paid' and ca.paid_date<=cutoff),
 ytd as (select z.* from public.payroll_final z join jobs j on j.id=z.employment_id where z.paid_date between yr and yr_end and z.paid_at is not null)
 select jsonb_build_object('start',first_day,'end',last_day,'as_of',cutoff,'year',extract(year from yr),
  'current_count',(select count(distinct employee_id) from jobs where start_date<=today and coalesce(end_date,'infinity'::date)>=today),
  'expected_days',(select coalesce(sum(greatest(0,least(cutoff,coalesce(end_date,cutoff))-greatest(first_day,start_date)+1)),0) from jobs),
  'recorded_days',(select count(*) from attendance),'approved_days',(select count(*) from attendance where status='approved'),
  'normal_minutes',(select coalesce(sum(normal_minutes),0) from attendance where status='approved'),
  'ot_minutes',(select coalesce(sum(ot_minutes),0) from attendance where status='approved'),
  'advance_paid_period',(select coalesce(sum(amount_satang),0) from advances where paid_date>=first_day),
  'advance_balance_now_for_cutoff',(select coalesce(sum(amount_satang-allocated),0) from advances),
  'draft_count',(select count(*) from drafts),'draft_net',(select coalesce(sum(net_satang),0) from drafts),
  'final_count',(select count(*) from finals),'final_net',(select coalesce(sum(net_satang),0) from finals),
  'paid_count',(select count(*) from finals where paid_at is not null),'paid_net',(select coalesce(sum(net_satang),0) from finals where paid_at is not null),
  'ytd_count',(select count(*) from ytd),'ytd_gross',(select coalesce(sum((snapshot->>'base_satang')::bigint+(snapshot->>'ot_satang')::bigint+(snapshot->>'other_income_satang')::bigint),0) from ytd),
  'ytd_deductions',(select coalesce(sum((snapshot->>'advance_deduction_satang')::bigint+(snapshot->>'other_deduction_satang')::bigint),0) from ytd),
  'ytd_net',(select coalesce(sum(net_satang),0) from ytd)) into result;
 return result;
end $$;
revoke all on function public.staff_period_report(date,uuid) from public,anon,authenticated;
grant execute on function public.staff_period_report(date,uuid) to authenticated;
commit;
