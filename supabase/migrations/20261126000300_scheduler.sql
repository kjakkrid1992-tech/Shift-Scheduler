
-- Phase 2: apply after both Foundation migrations. No legacy data is modified.
begin;
create table public.pay_periods (
 id uuid primary key default gen_random_uuid(),
 start_date date not null unique,
 end_date date not null unique,
 created_at timestamptz not null default now(),
 check(extract(day from start_date)=26 and extract(day from end_date)=25
   and end_date=(start_date+interval '1 month'-interval '1 day')::date)
);
create table public.shift_schedules (
 id uuid primary key default gen_random_uuid(),
 period_id uuid not null references public.pay_periods(id) on delete restrict,
 department_id uuid not null references public.departments(id) on delete restrict,
 version integer not null check(version>0),
 revision integer not null default 0 check(revision>=0),
 status text not null default 'draft' check(status in ('draft','confirmed')),
 preferences jsonb not null default '{}'::jsonb check(jsonb_typeof(preferences)='object'),
 created_by uuid not null references public.user_profiles(user_id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 confirmed_by uuid references public.user_profiles(user_id),
 confirmed_at timestamptz,
 unique(period_id,department_id,version),
 check((status='confirmed')=(confirmed_at is not null and confirmed_by is not null))
);
create unique index one_draft_per_department_period on public.shift_schedules(period_id,department_id) where status='draft';
create table public.shift_assignments (
 id uuid primary key default gen_random_uuid(),
 schedule_id uuid not null references public.shift_schedules(id) on delete restrict,
 work_date date not null,
 shift_template_id uuid not null references public.shift_templates(id) on delete restrict,
 shift_name text not null,
 planned_start timestamptz not null,
 planned_end timestamptz not null,
 planned_break_minutes integer not null check(planned_break_minutes>=0),
 planned_minutes integer not null check(planned_minutes>=0),
 employment_id uuid references public.employment_records(id) on delete restrict,
 is_extra boolean not null default false,
 is_locked boolean not null default false,
 check(planned_end>planned_start),
 check(planned_minutes+planned_break_minutes<=extract(epoch from planned_end-planned_start)/60)
);
create unique index unique_base_slot on public.shift_assignments(schedule_id,work_date,shift_template_id) where not is_extra;
create index assignments_schedule on public.shift_assignments(schedule_id,work_date);
create index assignments_employment on public.shift_assignments(employment_id,work_date);
do $$
declare t text;
begin
 foreach t in array array['pay_periods','shift_schedules','shift_assignments'] loop
   execute format('alter table public.%I enable row level security',t);
   execute format('revoke all on table public.%I from public, anon, authenticated',t);
   execute format('grant select on table public.%I to authenticated',t);
   execute format('create policy staff_read on public.%I for select to authenticated using ((select staff_private.staff_role()) in (''owner'',''manager''))',t);
 end loop;
end $$;
-- Writes only via the explicitly authorized RPCs. No direct insert/update/delete grants.
create function public.open_shift_schedule(p_department uuid,p_month date,p_revise boolean default false)
returns uuid language plpgsql security definer set search_path='' as $$
declare p public.pay_periods%rowtype; s public.shift_schedules%rowtype; sid uuid; first_day date; last_day date;
begin
 if coalesce(staff_private.staff_role(),'') not in ('owner','manager') then raise exception using errcode='42501',message='Staff access required'; end if;
 if p_month is null or extract(day from p_month)<>1 or p_month<'1900-02-01' or p_month>'2199-12-01' then raise exception 'Invalid month'; end if;
 if not exists(select 1 from public.departments where id=p_department and active) then raise exception 'Inactive or missing department'; end if;
 first_day:=(p_month-interval '1 month'+interval '25 days')::date;
 last_day:=p_month+24;
 insert into public.pay_periods(start_date,end_date) values(first_day,last_day) on conflict(start_date) do nothing;
 select * into p from public.pay_periods where start_date=first_day for update;
 select * into s from public.shift_schedules where period_id=p.id and department_id=p_department order by version desc limit 1;
 if found then
   if not p_revise then return s.id; end if;
   if s.status<>'confirmed' then raise exception 'A draft already exists; open the latest version'; end if;
   insert into public.shift_schedules(period_id,department_id,version,preferences,created_by)
   values(p.id,p_department,s.version+1,s.preferences,auth.uid()) returning id into sid;
   insert into public.shift_assignments(schedule_id,work_date,shift_template_id,shift_name,planned_start,planned_end,planned_break_minutes,planned_minutes,employment_id,is_extra,is_locked)
   select sid,work_date,shift_template_id,shift_name,planned_start,planned_end,planned_break_minutes,planned_minutes,employment_id,is_extra,is_locked
   from public.shift_assignments where schedule_id=s.id;
 else
   if p_revise then raise exception 'No confirmed schedule to revise'; end if;
   if not exists(select 1 from public.shift_templates where active) then raise exception 'No active shift templates'; end if;
   if (select count(*) from public.shift_templates where active)>10 then raise exception 'Pilot supports at most 10 active shift templates'; end if;
   insert into public.shift_schedules(period_id,department_id,version,created_by) values(p.id,p_department,1,auth.uid()) returning id into sid;
   insert into public.shift_assignments(schedule_id,work_date,shift_template_id,shift_name,planned_start,planned_end,planned_break_minutes,planned_minutes)
   select sid,d::date,t.id,t.name,(d::date+t.start_time) at time zone 'Asia/Bangkok',
     (d::date+t.end_time+case when t.end_time<t.start_time then interval '1 day' else interval '0 day' end) at time zone 'Asia/Bangkok',
     t.break_minutes,(extract(epoch from (t.end_time-t.start_time+case when t.end_time<t.start_time then interval '1 day' else interval '0 day' end))/60)::integer-t.break_minutes
   from generate_series(first_day::timestamp,last_day::timestamp,interval '1 day') d cross join public.shift_templates t where t.active;
 end if;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,changed_fields) values(auth.uid(),'INSERT','shift_schedules',sid,array['version']);
 return sid;
end $$;
create function public.save_shift_schedule(p_schedule uuid,p_revision integer,p_rows jsonb,p_preferences jsonb,p_confirm boolean default false,p_ack_overlap boolean default false)
returns integer language plpgsql security definer set search_path='' as $$
declare s public.shift_schedules%rowtype; x record; e public.employment_records%rowtype; b public.shift_assignments%rowtype; pref record; new_revision integer;
begin
 if coalesce(staff_private.staff_role(),'') not in ('owner','manager') then raise exception using errcode='42501',message='Staff access required'; end if;
 select * into s from public.shift_schedules where id=p_schedule for update;
 if not found then raise exception 'Schedule not found'; end if;
 if s.status<>'draft' then raise exception 'Confirmed schedule is immutable; create a revision'; end if;
 p_confirm:=coalesce(p_confirm,false); p_ack_overlap:=coalesce(p_ack_overlap,false);
 if p_revision is distinct from s.revision then raise exception 'STALE_SCHEDULE: reload latest version'; end if;
 if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows)>500 then raise exception 'Invalid rows'; end if;
 if jsonb_typeof(p_preferences) is distinct from 'object' or octet_length(p_preferences::text)>100000 then raise exception 'Invalid preferences'; end if;
 -- Preferences are per version, keyed by employment id; off_days are weekday numbers (0 Sunday), leave_dates ISO dates.
 for pref in select key,value from jsonb_each(p_preferences) loop
   if not exists(select 1 from public.employment_records where id=pref.key::uuid and department_id=s.department_id) then raise exception 'Invalid preference employee'; end if;
   if jsonb_typeof(pref.value) is distinct from 'object' or jsonb_typeof(pref.value->'off_days') is distinct from 'array' or jsonb_typeof(pref.value->'leave_dates') is distinct from 'array' then raise exception 'Invalid preference format'; end if;
   if exists(select 1 from jsonb_array_elements_text(pref.value->'off_days') a(v) where v is null or v not in ('0','1','2','3','4','5','6')) then raise exception 'Invalid weekly off day'; end if;
   if exists(select 1 from jsonb_array_elements_text(pref.value->'leave_dates') a(v) where v is null or v !~ '^\d{4}-\d{2}-\d{2} or v::date not between (select start_date from public.pay_periods where id=s.period_id) and (select end_date from public.pay_periods where id=s.period_id)) then raise exception 'Invalid leave date'; end if;
 end loop;
 if exists(select 1 from jsonb_to_recordset(p_rows) as r(id uuid) group by id having count(*)>1) then raise exception 'Duplicate slot id'; end if;
 if exists(select 1 from public.shift_assignments a where a.schedule_id=s.id and not a.is_extra and not exists(select 1 from jsonb_to_recordset(p_rows) as r(id uuid) where r.id=a.id)) then raise exception 'Required shift missing'; end if;
 for x in select * from jsonb_to_recordset(p_rows) as r(id uuid,work_date date,shift_template_id uuid,employment_id uuid,is_extra boolean,is_locked boolean,planned_minutes integer) loop
   if x.id is null or x.work_date is null or x.shift_template_id is null or x.is_extra is null or x.is_locked is null or x.planned_minutes is null then raise exception 'Incomplete shift row'; end if;
   select * into b from public.shift_assignments where id=x.id and schedule_id=s.id;
   if found then
     if b.work_date<>x.work_date or b.shift_template_id<>x.shift_template_id or b.is_extra<>x.is_extra then raise exception 'Cannot change slot identity'; end if;
   else
     if not x.is_extra then raise exception 'Unknown base slot'; end if;
     select * into b from public.shift_assignments where schedule_id=s.id and work_date=x.work_date and shift_template_id=x.shift_template_id and not is_extra;
     if not found then raise exception 'Extra shift must match an existing base slot'; end if;
   end if;
   if x.planned_minutes<0 or x.planned_minutes+b.planned_break_minutes>extract(epoch from b.planned_end-b.planned_start)/60 then raise exception 'Invalid planned minutes'; end if;
   if x.employment_id is not null then
     -- Lock employment against concurrent closure while validating the shift.
     select * into e from public.employment_records where id=x.employment_id for share;
     if not found or e.department_id<>s.department_id or x.work_date<e.start_date or (e.end_date is not null and x.work_date>e.end_date) then raise exception 'Employment not eligible for shift date'; end if;
     if p_confirm and (
       exists(select 1 from jsonb_array_elements_text(coalesce(p_preferences->(x.employment_id::text)->'off_days','[]'::jsonb)) z(v) where z.v=extract(dow from x.work_date)::integer::text)
       or exists(select 1 from jsonb_array_elements_text(coalesce(p_preferences->(x.employment_id::text)->'leave_dates','[]'::jsonb)) z(v) where z.v=x.work_date::text)
     ) then raise exception 'Assigned employee is unavailable'; end if;
   elsif p_confirm and not x.is_extra then raise exception 'Required shift is empty'; end if;
   if p_confirm and x.employment_id is not null and x.planned_minutes=0 then raise exception 'Assigned shift has zero minutes'; end if;
   insert into public.shift_assignments(id,schedule_id,work_date,shift_template_id,shift_name,planned_start,planned_end,planned_break_minutes,planned_minutes,employment_id,is_extra,is_locked)
   values(x.id,s.id,x.work_date,x.shift_template_id,b.shift_name,b.planned_start,b.planned_end,b.planned_break_minutes,x.planned_minutes,x.employment_id,x.is_extra,x.is_locked)
   on conflict(id) do update set employment_id=excluded.employment_id,planned_minutes=excluded.planned_minutes,is_locked=excluded.is_locked
   where public.shift_assignments.schedule_id=s.id;
   if not found then raise exception 'Slot id belongs to another schedule'; end if;
 end loop;
 delete from public.shift_assignments a where a.schedule_id=s.id and a.is_extra and not exists(select 1 from jsonb_to_recordset(p_rows) as r(id uuid) where r.id=a.id);
 -- Same employee cannot occupy duplicate slots of the same shift. Different overlapping shifts require explicit acknowledgement.
 if exists(select 1 from public.shift_assignments a where a.schedule_id=s.id and a.employment_id is not null group by a.work_date,a.shift_template_id,a.employment_id having count(*)>1) then raise exception 'Duplicate employee in same shift'; end if;
 if p_confirm and not coalesce(p_ack_overlap,false) and exists(
   select 1 from public.shift_assignments a join public.shift_assignments b on a.schedule_id=b.schedule_id and a.id<b.id and a.employment_id=b.employment_id
   where a.schedule_id=s.id and tstzrange(a.planned_start,a.planned_end,'[)') && tstzrange(b.planned_start,b.planned_end,'[)')
 ) then raise exception 'Overlapping shifts require explicit acknowledgement'; end if;
 update public.shift_schedules set preferences=p_preferences,revision=revision+1,updated_at=now(),
   status=case when p_confirm then 'confirmed' else 'draft' end,
   confirmed_at=case when p_confirm then now() else null end,
   confirmed_by=case when p_confirm then auth.uid() else null end
 where id=s.id returning revision into new_revision;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,changed_fields)
 values(auth.uid(),'UPDATE','shift_schedules',s.id,case when p_confirm then array['assignments','preferences','status'] else array['assignments','preferences'] end);
 return new_revision;
end $$;
revoke all on function public.open_shift_schedule(uuid,date,boolean) from public,anon,authenticated;
revoke all on function public.save_shift_schedule(uuid,integer,jsonb,jsonb,boolean,boolean) from public,anon,authenticated;
grant execute on function public.open_shift_schedule(uuid,date,boolean) to authenticated;
grant execute on function public.save_shift_schedule(uuid,integer,jsonb,jsonb,boolean,boolean) to authenticated;
commit;
 or v::date not between (select start_date from public.pay_periods where id=s.period_id) and (select end_date from public.pay_periods where id=s.period_id)) then raise exception 'Invalid leave date'; end if;
 end loop;
 if exists(select 1 from jsonb_to_recordset(p_rows) as r(id uuid) group by id having count(*)>1) then raise exception 'Duplicate slot id'; end if;
 if exists(select 1 from public.shift_assignments a where a.schedule_id=s.id and not a.is_extra and not exists(select 1 from jsonb_to_recordset(p_rows) as r(id uuid) where r.id=a.id)) then raise exception 'Required shift missing'; end if;
 for x in select * from jsonb_to_recordset(p_rows) as r(id uuid,work_date date,shift_template_id uuid,employment_id uuid,is_extra boolean,is_locked boolean,planned_minutes integer) loop
   if x.id is null or x.work_date is null or x.shift_template_id is null or x.is_extra is null or x.is_locked is null or x.planned_minutes is null then raise exception 'Incomplete shift row'; end if;
   select * into b from public.shift_assignments where id=x.id and schedule_id=s.id;
   if found then
     if b.work_date<>x.work_date or b.shift_template_id<>x.shift_template_id or b.is_extra<>x.is_extra then raise exception 'Cannot change slot identity'; end if;
   else
     if not x.is_extra then raise exception 'Unknown base slot'; end if;
     select * into b from public.shift_assignments where schedule_id=s.id and work_date=x.work_date and shift_template_id=x.shift_template_id and not is_extra;
     if not found then raise exception 'Extra shift must match an existing base slot'; end if;
   end if;
   if x.planned_minutes<0 or x.planned_minutes+b.planned_break_minutes>extract(epoch from b.planned_end-b.planned_start)/60 then raise exception 'Invalid planned minutes'; end if;
   if x.employment_id is not null then
     -- Lock employment against concurrent closure while validating the shift.
     select * into e from public.employment_records where id=x.employment_id for share;
     if not found or e.department_id<>s.department_id or x.work_date<e.start_date or (e.end_date is not null and x.work_date>e.end_date) then raise exception 'Employment not eligible for shift date'; end if;
     if p_confirm and (
       exists(select 1 from jsonb_array_elements_text(coalesce(p_preferences->(x.employment_id::text)->'off_days','[]'::jsonb)) z(v) where z.v=extract(dow from x.work_date)::integer::text)
       or exists(select 1 from jsonb_array_elements_text(coalesce(p_preferences->(x.employment_id::text)->'leave_dates','[]'::jsonb)) z(v) where z.v=x.work_date::text)
     ) then raise exception 'Assigned employee is unavailable'; end if;
   elsif p_confirm and not x.is_extra then raise exception 'Required shift is empty'; end if;
   if p_confirm and x.employment_id is not null and x.planned_minutes=0 then raise exception 'Assigned shift has zero minutes'; end if;
   insert into public.shift_assignments(id,schedule_id,work_date,shift_template_id,shift_name,planned_start,planned_end,planned_break_minutes,planned_minutes,employment_id,is_extra,is_locked)
   values(x.id,s.id,x.work_date,x.shift_template_id,b.shift_name,b.planned_start,b.planned_end,b.planned_break_minutes,x.planned_minutes,x.employment_id,x.is_extra,x.is_locked)
   on conflict(id) do update set employment_id=excluded.employment_id,planned_minutes=excluded.planned_minutes,is_locked=excluded.is_locked
   where public.shift_assignments.schedule_id=s.id;
   if not found then raise exception 'Slot id belongs to another schedule'; end if;
 end loop;
 delete from public.shift_assignments a where a.schedule_id=s.id and a.is_extra and not exists(select 1 from jsonb_to_recordset(p_rows) as r(id uuid) where r.id=a.id);
 -- Same employee cannot occupy duplicate slots of the same shift. Different overlapping shifts require explicit acknowledgement.
 if exists(select 1 from public.shift_assignments a where a.schedule_id=s.id and a.employment_id is not null group by a.work_date,a.shift_template_id,a.employment_id having count(*)>1) then raise exception 'Duplicate employee in same shift'; end if;
 if p_confirm and not coalesce(p_ack_overlap,false) and exists(
   select 1 from public.shift_assignments a join public.shift_assignments b on a.schedule_id=b.schedule_id and a.id<b.id and a.employment_id=b.employment_id
   where a.schedule_id=s.id and tstzrange(a.planned_start,a.planned_end,'[)') && tstzrange(b.planned_start,b.planned_end,'[)')
 ) then raise exception 'Overlapping shifts require explicit acknowledgement'; end if;
 update public.shift_schedules set preferences=p_preferences,revision=revision+1,updated_at=now(),
   status=case when p_confirm then 'confirmed' else 'draft' end,
   confirmed_at=case when p_confirm then now() else null end,
   confirmed_by=case when p_confirm then auth.uid() else null end
 where id=s.id returning revision into new_revision;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,changed_fields)
 values(auth.uid(),'UPDATE','shift_schedules',s.id,case when p_confirm then array['assignments','preferences','status'] else array['assignments','preferences'] end);
 return new_revision;
end $$;
revoke all on function public.open_shift_schedule(uuid,date,boolean) from public,anon,authenticated;
revoke all on function public.save_shift_schedule(uuid,integer,jsonb,jsonb,boolean,boolean) from public,anon,authenticated;
grant execute on function public.open_shift_schedule(uuid,date,boolean) to authenticated;
grant execute on function public.save_shift_schedule(uuid,integer,jsonb,jsonb,boolean,boolean) to authenticated;
commit;
