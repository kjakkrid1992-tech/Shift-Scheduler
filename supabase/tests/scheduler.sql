
-- Isolated test project; no persistent records. Requires active Owner and Manager accounts.
begin;
do $$
declare o uuid; m uuid; d uuid;
begin
 select user_id into o from public.user_profiles where role='owner' and active order by user_id limit 1;
 select user_id into m from public.user_profiles where role='manager' and active order by user_id limit 1;
 select id into d from public.departments where active order by name limit 1;
 if o is null or m is null or d is null then raise exception 'Missing test prerequisites'; end if;
 if exists(select 1 from public.pay_periods where start_date='2098-01-26') then raise exception 'Test month occupied; use isolated project'; end if;
 perform set_config('staff_test.owner',o::text,true);perform set_config('staff_test.manager',m::text,true);perform set_config('staff_test.dept',d::text,true);
end $$;
set local role authenticated;
do $$
declare d uuid:=current_setting('staff_test.dept')::uuid; sid uuid; sid2 uuid; emp uuid; job uuid; payload jsonb; rev integer;
begin
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.owner'),true);
 emp:=public.create_staff('EMP-SQL-PHASE2','Synthetic','Test','','',d,'Test','daily','2098-01-26','active');
 select id into job from public.employment_records where employee_id=emp;
 sid:=public.open_shift_schedule(d,'2098-02-01',false);
 if (select count(*) from public.shift_assignments where schedule_id=sid and not is_extra)<> (select count(*) from public.shift_templates where active)*31 then raise exception 'Base slots missing'; end if;
 select jsonb_agg(jsonb_build_object('id',id,'work_date',work_date,'shift_template_id',shift_template_id,'employment_id',job,'planned_minutes',planned_minutes,'is_extra',is_extra,'is_locked',false)) into payload from public.shift_assignments where schedule_id=sid;
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.manager'),true);
 rev:=public.save_shift_schedule(sid,0,payload,'{}',false,false);
 if rev<>1 then raise exception 'Wrong revision'; end if;
 begin
  perform public.save_shift_schedule(sid,0,payload,'{}',false,false);
  raise exception 'FAIL stale write';
 exception when raise_exception then if sqlerrm not like 'STALE_SCHEDULE:%' then raise;end if;end;
 begin
  perform public.save_shift_schedule(sid,1,payload,jsonb_build_object(job::text,jsonb_build_object('off_days',jsonb_build_array(extract(dow from date '2098-01-26')::integer),'leave_dates','[]'::jsonb)),true,true);
  raise exception 'FAIL weekly off day allowed';
 exception when raise_exception then if sqlerrm<>'Assigned employee is unavailable' then raise;end if;end;
 begin
  perform public.save_shift_schedule(sid,1,payload,jsonb_build_object(job::text,jsonb_build_object('off_days','[]'::jsonb,'leave_dates',jsonb_build_array('2098-01-26'))),true,true);
  raise exception 'FAIL leave date allowed';
 exception when raise_exception then if sqlerrm<>'Assigned employee is unavailable' then raise;end if;end;
 rev:=public.save_shift_schedule(sid,1,payload,'{}',true,true);
 if rev<>2 or not exists(select 1 from public.shift_schedules where id=sid and status='confirmed') then raise exception 'Confirm failed';end if;
 begin
  perform public.save_shift_schedule(sid,2,payload,'{}',false,false);
  raise exception 'FAIL confirmed write';
 exception when raise_exception then if sqlerrm not like 'Confirmed schedule is immutable%' then raise;end if;end;
 sid2:=public.open_shift_schedule(d,'2098-02-01',true);
 if sid2=sid or not exists(select 1 from public.shift_schedules where id=sid2 and version=2 and status='draft') then raise exception 'Revision failed';end if;
 if (select count(*) from public.shift_assignments where schedule_id=sid2)<>(select count(*) from public.shift_assignments where schedule_id=sid) then raise exception 'Revision slots missing';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000099',true);
 if exists(select 1 from public.shift_schedules) then raise exception 'Unauthorized read';end if;
 begin
  perform public.open_shift_schedule(d,'2098-02-01',false);
  raise exception 'Unauthorized open';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
select 'PASS: schedule create, save, confirm, version, stale write and access guard' as result;
rollback;
