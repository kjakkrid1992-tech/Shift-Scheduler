-- Phase 3: apply after the Phase 2 alias fix. No existing records are modified.
begin;
create table public.attendance_records (
 id uuid primary key default gen_random_uuid(),
 period_id uuid not null references public.pay_periods(id) on delete restrict,
 department_id uuid not null references public.departments(id) on delete restrict,
 employment_id uuid not null references public.employment_records(id) on delete restrict,
 schedule_id uuid not null references public.shift_schedules(id) on delete restrict,
 work_date date not null,
 planned_snapshot jsonb not null check(jsonb_typeof(planned_snapshot)='array'),
 attendance_type text not null check(attendance_type in ('work','off','leave','holiday','absent')),
 actual_start timestamptz,
 actual_end timestamptz,
 break_minutes integer not null default 0 check(break_minutes>=0),
 work_minutes integer not null default 0 check(work_minutes between 0 and 1440),
 normal_minutes integer not null default 0 check(normal_minutes>=0),
 ot_minutes integer not null default 0 check(ot_minutes>=0),
 note text not null default '' check(length(note)<=1000),
 source text not null default 'paper' check(source='paper'),
 status text not null default 'draft' check(status in ('draft','verified','approved')),
 revision integer not null default 1 check(revision>0),
 created_by uuid not null references public.user_profiles(user_id),
 updated_by uuid not null references public.user_profiles(user_id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 verified_by uuid references public.user_profiles(user_id),
 verified_at timestamptz,
 approved_by uuid references public.user_profiles(user_id),
 approved_at timestamptz,
 unique(employment_id,work_date),
 check(normal_minutes+ot_minutes=work_minutes),
 check((status in ('verified','approved'))=(verified_by is not null and verified_at is not null)),
 check((status='approved')=(approved_by is not null and approved_at is not null)),
 check((attendance_type='work' and actual_start is not null and actual_end is not null
   and actual_end>actual_start and work_minutes>0
   and extract(epoch from actual_end-actual_start)/60=work_minutes+break_minutes)
   or (attendance_type<>'work' and actual_start is null and actual_end is null
   and break_minutes=0 and work_minutes=0))
);
create index attendance_period_dept_idx on public.attendance_records(period_id,department_id,work_date);
create table public.attendance_revisions (
 id bigint generated always as identity primary key,
 attendance_id uuid not null references public.attendance_records(id) on delete restrict,
 revision integer not null check(revision>0),
 action text not null check(action in ('create','edit','verify','approve','reopen')),
 actor_id uuid not null references public.user_profiles(user_id),
 reason text not null default '' check(length(reason)<=1000),
 snapshot jsonb not null check(jsonb_typeof(snapshot)='object'),
 created_at timestamptz not null default now(),
 unique(attendance_id,revision)
);
do $$
declare tbl text;
begin
 foreach tbl in array array['attendance_records','attendance_revisions'] loop
  execute format('alter table public.%I enable row level security',tbl);
  execute format('revoke all on table public.%I from public,anon,authenticated',tbl);
  execute format('grant select on table public.%I to authenticated',tbl);
  execute format('create policy staff_read on public.%I for select to authenticated using ((select staff_private.staff_role()) in (''owner'',''manager''))',tbl);
 end loop;
end $$;
-- A daily record is anchored to the confirmed plan selected on first save.
-- The actual time is a single continuous interval minus aggregate breaks; never sum overlapping planned slots.
create function public.save_attendance(p_employment uuid,p_date date,p_schedule uuid,p_revision integer,
 p_type text,p_start time,p_end time,p_overnight boolean,p_break integer,p_normal integer,p_note text)
returns uuid language plpgsql security definer set search_path='' as $$
declare job public.employment_records%rowtype; rec public.attendance_records%rowtype;
 plan public.shift_schedules%rowtype; period public.pay_periods%rowtype; snap jsonb;
 actual_in timestamptz; actual_out timestamptz; elapsed integer; net integer; actor uuid:=auth.uid(); is_new boolean;
begin
 if coalesce(staff_private.staff_role(),'') not in ('owner','manager') then raise exception using errcode='42501',message='Staff access required'; end if;
 if p_date is null or p_date>(now() at time zone 'Asia/Bangkok')::date then raise exception 'Attendance date is in the future or missing'; end if;
 if p_type is null or p_type not in ('work','off','leave','holiday','absent') then raise exception 'Invalid attendance type'; end if;
 if p_note is null or length(p_note)>1000 then raise exception 'Invalid note'; end if;
 -- Parent lock serializes daily records, adjacent overnight overlaps and employment closure.
 select * into job from public.employment_records where id=p_employment for update;
 if not found or p_date<job.start_date or (job.end_date is not null and p_date>job.end_date) then raise exception 'Employment not eligible for date'; end if;
 select * into period from public.pay_periods where p_date between start_date and end_date;
 if not found then raise exception 'Pay period not found'; end if;
 select * into rec from public.attendance_records where employment_id=job.id and work_date=p_date for update;
 is_new:=not found;
 if is_new then
  if p_revision is distinct from 0 then raise exception 'STALE_ATTENDANCE: reload'; end if;
  select * into plan from public.shift_schedules where period_id=period.id and department_id=job.department_id and status='confirmed' order by version desc limit 1;
  if not found then raise exception 'Confirmed schedule required'; end if;
  if plan.id is distinct from p_schedule then raise exception 'STALE_PLAN: reload latest confirmed schedule'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('assignment_id',a.id,'shift_name',a.shift_name,'planned_start',a.planned_start,'planned_end',a.planned_end,'planned_break_minutes',a.planned_break_minutes,'planned_minutes',a.planned_minutes) order by a.planned_start,a.id),'[]'::jsonb)
  into snap from public.shift_assignments a where a.schedule_id=plan.id and a.employment_id=job.id and a.work_date=p_date;
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
create function public.transition_attendance(p_id uuid,p_revision integer,p_action text,p_reason text default '')
returns integer language plpgsql security definer set search_path='' as $$
declare rec public.attendance_records%rowtype; job public.employment_records%rowtype; actor uuid:=auth.uid(); staffrole text:=staff_private.staff_role(); jid uuid;
begin
 if coalesce(staffrole,'') not in ('owner','manager') then raise exception using errcode='42501',message='Staff access required'; end if;
 if p_action is null or p_action not in ('verify','approve','reopen') or p_reason is null or length(p_reason)>1000 then raise exception 'Invalid action or reason'; end if;
 select employment_id into jid from public.attendance_records where id=p_id;
 if not found then raise exception 'Attendance not found'; end if;
 select * into job from public.employment_records where id=jid for update;
 select * into rec from public.attendance_records where id=p_id for update;
 if not found then raise exception 'Attendance not found'; end if;
 if rec.revision is distinct from p_revision then raise exception 'STALE_ATTENDANCE: reload'; end if;
 if p_action in ('verify','approve') and (rec.work_date<job.start_date or (job.end_date is not null and rec.work_date>job.end_date)) then raise exception 'Employment no longer eligible; resolve employment discrepancy'; end if;
 if p_action='verify' and rec.status='draft' then
  update public.attendance_records set status='verified',verified_by=actor,verified_at=now(),revision=revision+1,updated_by=actor,updated_at=now() where id=p_id returning * into rec;
 elsif p_action='approve' and rec.status='verified' then
  if staffrole<>'owner' then raise exception using errcode='42501',message='Only owner can approve attendance'; end if;
  update public.attendance_records set status='approved',approved_by=actor,approved_at=now(),revision=revision+1,updated_by=actor,updated_at=now() where id=p_id returning * into rec;
 elsif p_action='reopen' and rec.status in ('verified','approved') then
  if rec.status='approved' and staffrole<>'owner' then raise exception using errcode='42501',message='Only owner can reopen approved attendance'; end if;
  if length(btrim(p_reason))=0 then raise exception 'Reopen reason required'; end if;
  update public.attendance_records set status='draft',verified_by=null,verified_at=null,approved_by=null,approved_at=null,revision=revision+1,updated_by=actor,updated_at=now() where id=p_id returning * into rec;
 else raise exception 'Invalid attendance status transition'; end if;
 insert into public.attendance_revisions(attendance_id,revision,action,actor_id,reason,snapshot) values(rec.id,rec.revision,p_action,actor,btrim(p_reason),to_jsonb(rec));
 return rec.revision;
end $$;
revoke all on function public.save_attendance(uuid,date,uuid,integer,text,time,time,boolean,integer,integer,text) from public,anon,authenticated;
revoke all on function public.transition_attendance(uuid,integer,text,text) from public,anon,authenticated;
grant execute on function public.save_attendance(uuid,date,uuid,integer,text,time,time,boolean,integer,integer,text) to authenticated;
grant execute on function public.transition_attendance(uuid,integer,text,text) to authenticated;
commit;
