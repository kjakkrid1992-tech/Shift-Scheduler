-- V8 isolated candidate: allow actual attendance without fabricated historical schedules.
begin;
alter table public.attendance_records alter column schedule_id drop not null;
create or replace function public.save_attendance(p_employment uuid,p_date date,p_schedule uuid,p_revision integer,
 p_type text,p_start time,p_end time,p_overnight boolean,p_break integer,p_normal integer,p_note text)
returns uuid language plpgsql security definer set search_path='' as $$
declare job public.employment_records%rowtype; rec public.attendance_records%rowtype;
 plan public.shift_schedules%rowtype; period public.pay_periods%rowtype; snap jsonb;
 actual_in timestamptz; actual_out timestamptz; elapsed integer; net integer; actor uuid:=auth.uid(); is_new boolean; first_day date;
begin
 if coalesce(staff_private.staff_role(),'') not in ('owner','manager') then raise exception using errcode='42501',message='Staff access required'; end if;
 if p_date is null or p_date>(now() at time zone 'Asia/Bangkok')::date then raise exception 'Attendance date is in the future or missing'; end if;
 if p_type is null or p_type not in ('work','off','leave','holiday','absent') then raise exception 'Invalid attendance type'; end if;
 if p_note is null or length(p_note)>1000 then raise exception 'Invalid note'; end if;
 -- Serialize against concurrent confirmation; fail safely if a schedule is being changed.
 lock table public.shift_schedules, public.shift_assignments in share mode nowait;
 -- Parent lock serializes daily records, adjacent overnight overlaps and employment closure.
 select * into job from public.employment_records where id=p_employment for update;
 if not found or p_date<job.start_date or (job.end_date is not null and p_date>job.end_date) then raise exception 'Employment not eligible for date'; end if;
 select * into period from public.pay_periods where p_date between start_date and end_date;
 if not found then
  if p_schedule is not null then raise exception 'Pay period not found'; end if;
  first_day:=(date_trunc('month',p_date::timestamp)::date + 25);
  if p_date<first_day then first_day:=(first_day-interval '1 month')::date;end if;
  if first_day<'1900-01-26' or first_day>'2199-11-26' then raise exception 'Invalid attendance period';end if;
  insert into public.pay_periods(start_date,end_date) values(first_day,(first_day+interval '1 month'-interval '1 day')::date) on conflict(start_date) do nothing;
  select * into period from public.pay_periods where start_date=first_day;
 end if;
 select * into rec from public.attendance_records where employment_id=job.id and work_date=p_date for update;
 is_new:=not found;
 if is_new then
  if p_revision is distinct from 0 then raise exception 'STALE_ATTENDANCE: reload'; end if;
  select * into plan from public.shift_schedules where period_id=period.id and department_id=job.department_id and status='confirmed' order by version desc limit 1;
  if not found then
   if p_schedule is not null then raise exception 'Confirmed schedule required'; end if;
   snap:='[]'::jsonb;
  else
   if plan.id is distinct from p_schedule then raise exception 'STALE_PLAN: reload latest confirmed schedule'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('assignment_id',a.id,'shift_name',a.shift_name,'planned_start',a.planned_start,'planned_end',a.planned_end,'planned_break_minutes',a.planned_break_minutes,'planned_minutes',a.planned_minutes) order by a.planned_start,a.id),'[]'::jsonb)
  into snap from public.shift_assignments a where a.schedule_id=plan.id and a.employment_id=job.id and a.work_date=p_date;
  end if;
 else
  if rec.revision is distinct from p_revision then raise exception 'STALE_ATTENDANCE: reload'; end if;
  if rec.status<>'draft' then raise exception 'Attendance must be reopened before editing'; end if;
  if rec.schedule_id is distinct from p_schedule then raise exception 'Original plan snapshot is immutable'; end if;
  snap:=rec.planned_snapshot;
 end if;
 if p_type='work' then
  if p_start is null or p_end is null or p_overnight is null or p_break is null or p_normal is null or extract(second from p_start)<>0 or extract(second from p_end)<>0 or p_start>=time '24:00' or p_end>=time '24:00' then raise exception 'Enter actual HH:MM times and minutes'; end if;
  actual_in:=(p_date+p_start) at time zone 'Asia/Bangkok';
  actual_out:=((p_date+case when p_overnight then 1 else 0 end)+p_end) at time zone 'Asia/Bangkok';
  if actual_out<=actual_in or actual_out>now() or actual_out-actual_in>interval '24 hours' then raise exception 'Invalid actual work interval (maximum 24h, must be completed)'; end if;
  elapsed:=extract(epoch from actual_out-actual_in)::integer/60;
  net:=elapsed-p_break;
  if p_break<0 or net<=0 or p_normal<0 or p_normal>net then raise exception 'Invalid break or normal minutes'; end if;
  if exists(select 1 from public.attendance_records other_rec where other_rec.employment_id=job.id and other_rec.work_date<>p_date and other_rec.attendance_type='work' and tstzrange(other_rec.actual_start,other_rec.actual_end,'[)') && tstzrange(actual_in,actual_out,'[)')) then raise exception 'Actual attendance overlaps another day'; end if;
  if jsonb_array_length(snap)=0 and length(btrim(p_note))=0 then raise exception 'Unplanned work requires a note'; end if;
 else
  if p_start is not null or p_end is not null or coalesce(p_overnight,false) or p_break is distinct from 0 or p_normal is distinct from 0 then raise exception 'Non-work day must have no actual hours'; end if;
  if (jsonb_array_length(snap)>0 or p_type in ('leave','absent','holiday')) and length(btrim(p_note))=0 then raise exception 'Non-work exception requires a note'; end if;
  net:=0;
 end if;
 if is_new then
  insert into public.attendance_records(period_id,department_id,employment_id,schedule_id,work_date,planned_snapshot,attendance_type,actual_start,actual_end,break_minutes,work_minutes,normal_minutes,ot_minutes,note,created_by,updated_by)
  values(period.id,job.department_id,job.id,plan.id,p_date,snap,p_type,actual_in,actual_out,p_break,net,p_normal,net-p_normal,btrim(p_note),actor,actor) returning * into rec;
 else
  update public.attendance_records set attendance_type=p_type,actual_start=actual_in,actual_end=actual_out,break_minutes=p_break,work_minutes=net,normal_minutes=p_normal,ot_minutes=net-p_normal,note=btrim(p_note),revision=revision+1,updated_at=now(),updated_by=actor where id=rec.id returning * into rec;
 end if;
 insert into public.attendance_revisions(attendance_id,revision,action,actor_id,snapshot) values(rec.id,rec.revision,case when is_new then 'create' else 'edit' end,actor,to_jsonb(rec));
 return rec.id;
end $$;

-- Atomic worksheet operation. Every row is authorized and revision-checked by the original RPCs.
create function public.save_attendance_period(p_month date,p_department uuid,p_mode text,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare x jsonb; z jsonb; rec public.attendance_records%rowtype; j uuid; d date; rev integer; rid uuid; do_save boolean; first_day date; last_day date; result jsonb:='[]'::jsonb;
begin
 if coalesce(staff_private.staff_role(),'') not in ('owner','manager') then raise exception using errcode='42501',message='Staff access required';end if;
 if p_mode='approve' and staff_private.staff_role()<>'owner' then raise exception using errcode='42501',message='Only owner can approve attendance';end if;
 if p_mode is null or p_mode not in ('save','verify','approve') or p_month is null or extract(day from p_month)<>1 or p_month<'1900-02-01' or p_month>'2199-12-01' or p_department is null or jsonb_typeof(p_rows) is distinct from 'array' then raise exception 'Invalid worksheet request';end if;
 if jsonb_array_length(p_rows) not between 1 and 200 or (select count(distinct (value->>'employment',value->>'day')) from jsonb_array_elements(p_rows))<>jsonb_array_length(p_rows) then raise exception 'Invalid or duplicate worksheet rows';end if;
 first_day:=(p_month-interval '1 month')::date+25;last_day:=p_month+24;
 lock table public.shift_schedules,public.shift_assignments in share mode nowait;
 for x in select value from jsonb_array_elements(p_rows) order by value->>'employment',value->>'day' loop
  j:=(x->>'employment')::uuid; d:=(x->>'day')::date;rev:=(x->>'revision')::integer;do_save:=(x->>'save')::boolean; z:=x->'payload';
  if j is null or d is null or d not between first_day and last_day or rev is null or rev<0 or do_save is null or not exists(select 1 from public.employment_records where id=j and department_id=p_department) then raise exception 'Invalid worksheet row';end if;
  begin
   if do_save then
    if p_mode='approve' or jsonb_typeof(z) is distinct from 'object' then raise exception 'Invalid worksheet save';end if;
    rid:=public.save_attendance(j,d,(z->>'p_schedule')::uuid,rev,z->>'p_type',(z->>'p_start')::time,(z->>'p_end')::time,(z->>'p_overnight')::boolean,(z->>'p_break')::integer,(z->>'p_normal')::integer,z->>'p_note');
    rev:=rev+1;
   else
    select * into rec from public.attendance_records where employment_id=j and work_date=d;
    if not found or rec.revision is distinct from rev then raise exception 'STALE_ATTENDANCE: reload';end if;
    rid:=rec.id;
    if p_mode='save' then raise exception 'No changes to save';end if;
   end if;
   if p_mode in ('verify','approve') then rev:=public.transition_attendance(rid,rev,p_mode,'');end if;
   select * into strict rec from public.attendance_records where id=rid;
   result:=result||jsonb_build_array(jsonb_build_object('employment',j,'day',d,'id',rid,'revision',rec.revision,'status',rec.status));
  exception when others then raise exception using errcode=sqlstate,message='Worksheet '||d::text||' / '||j::text||': '||sqlerrm;
  end;
 end loop;
 return result;
end $$;
revoke all on function public.save_attendance_period(date,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.save_attendance_period(date,uuid,text,jsonb) to authenticated;

-- Capability check prevents V8 UI from mutating a baseline-only backend.
create function public.v8_workspace_capabilities()
returns jsonb language plpgsql stable security invoker set search_path='' as $$
begin
 if coalesce(staff_private.staff_role(),'') not in ('owner','manager') then raise exception using errcode='42501',message='Staff access required';end if;
 return jsonb_build_object('version',8,'attendance_batch',true,'payroll_batch',true);
end $$;
revoke all on function public.v8_workspace_capabilities() from public,anon,authenticated;
grant execute on function public.v8_workspace_capabilities() to authenticated;
-- Transactional payroll draft worksheet; original save_payroll_items rechecks source and revision.
create function public.save_payroll_period_drafts(p_month date,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare x jsonb; j uuid; rid uuid; rev integer; result jsonb:='[]'::jsonb;
begin
 if coalesce(staff_private.staff_role(),'') not in ('owner','manager') then raise exception using errcode='42501',message='Staff access required';end if;
 if p_month is null or extract(day from p_month)<>1 or p_month<'1900-02-01' or p_month>'2199-12-01' or jsonb_typeof(p_rows) is distinct from 'array' then raise exception 'Invalid payroll worksheet';end if;
 if jsonb_array_length(p_rows) not between 1 and 50 or (select count(distinct value->>'employment') from jsonb_array_elements(p_rows))<>jsonb_array_length(p_rows) then raise exception 'Invalid or duplicate payroll worksheet rows';end if;
 for x in select value from jsonb_array_elements(p_rows) order by value->>'employment' loop
  j:=(x->>'employment')::uuid;rev:=(x->>'revision')::integer;
  if j is null or rev is null or rev<0 then raise exception 'Invalid payroll worksheet row';end if;
  begin
   rid:=public.save_payroll_items(j,p_month,rev,x->'source',x->'items',x->>'note');
   result:=result||jsonb_build_array(jsonb_build_object('employment',j,'id',rid,'revision',rev+1));
  exception when others then raise exception using errcode=sqlstate,message='Payroll worksheet '||j::text||': '||sqlerrm;
  end;
 end loop;
 return result;
end $$;
revoke all on function public.save_payroll_period_drafts(date,jsonb) from public,anon,authenticated;
grant execute on function public.save_payroll_period_drafts(date,jsonb) to authenticated;
commit;
