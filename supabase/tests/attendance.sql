-- Run on pilot only. All synthetic data rolls back.
begin;
do $$
declare owner_id uuid; manager_id uuid; dept_id uuid;
begin
 select user_id into owner_id from public.user_profiles where role='owner' and active order by user_id limit 1;
 select user_id into manager_id from public.user_profiles where role='manager' and active order by user_id limit 1;
 select id into dept_id from public.departments where active order by name limit 1;
 if owner_id is null or manager_id is null or dept_id is null then raise exception 'Missing active test roles or department'; end if;
 if exists(select 1 from public.pay_periods where start_date='2001-01-26') then raise exception 'Test period occupied'; end if;
 perform set_config('staff_test.owner',owner_id::text,true);
 perform set_config('staff_test.manager',manager_id::text,true);
 perform set_config('staff_test.dept',dept_id::text,true);
 if has_table_privilege('authenticated','public.attendance_records','INSERT') or has_table_privilege('authenticated','public.attendance_revisions','UPDATE') or has_table_privilege('anon','public.attendance_records','SELECT') then raise exception 'Unexpected direct table privilege'; end if;
end $$;
set local role authenticated;
do $$
declare dept_id uuid:=current_setting('staff_test.dept')::uuid; employee_id_test uuid; job_id uuid; schedule_id_test uuid; attendance_id_test uuid; payload jsonb; rev integer;
begin
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.owner'),true);
 employee_id_test:=public.create_staff('EMP-ATT-SQL','Synthetic','Attendance','','',dept_id,'Test','daily','2001-01-26','active');
 select id into job_id from public.employment_records where employee_id=employee_id_test;
 schedule_id_test:=public.open_shift_schedule(dept_id,'2001-02-01',false);
 begin
  perform public.save_attendance(job_id,'2001-01-26',schedule_id_test,0,'work','06:30','21:00',false,120,480,'Test');
  raise exception 'FAIL attendance on draft plan';
 exception when raise_exception then if sqlerrm<>'Confirmed schedule required' then raise;end if;end;
 select jsonb_agg(jsonb_build_object('id',id,'work_date',work_date,'shift_template_id',shift_template_id,'employment_id',job_id,'planned_minutes',planned_minutes,'is_extra',is_extra,'is_locked',false)) into payload from public.shift_assignments where schedule_id=schedule_id_test;
 perform public.save_shift_schedule(schedule_id_test,0,payload,'{}',true,true);
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.manager'),true);
 attendance_id_test:=public.save_attendance(job_id,'2001-01-26',schedule_id_test,0,'work','06:30','21:00',false,120,480,'Synthetic combined shift');
 if not exists(select 1 from public.attendance_records where id=attendance_id_test and work_minutes=750 and normal_minutes=480 and ot_minutes=270 and revision=1) then raise exception 'FAIL actual minutes';end if;
 begin
  perform public.save_attendance(job_id,'2001-01-26',schedule_id_test,0,'work','06:30','21:00',false,120,480,'Test');
  raise exception 'FAIL stale save';
 exception when raise_exception then if sqlerrm not like 'STALE_ATTENDANCE:%' then raise;end if;end;
 rev:=public.transition_attendance(attendance_id_test,1,'verify','');
 if rev<>2 then raise exception 'FAIL verify';end if;
 begin
  perform public.transition_attendance(attendance_id_test,2,'approve','');
  raise exception 'FAIL manager approval';
 exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.owner'),true);
 rev:=public.transition_attendance(attendance_id_test,2,'approve','');
 if rev<>3 then raise exception 'FAIL approve';end if;
 begin
  perform public.save_attendance(job_id,'2001-01-26',schedule_id_test,3,'work','06:30','21:00',false,120,480,'Test');
  raise exception 'FAIL approved edit';
 exception when raise_exception then if sqlerrm<>'Attendance must be reopened before editing' then raise;end if;end;
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.manager'),true);
 begin
  perform public.transition_attendance(attendance_id_test,3,'reopen','Test');
  raise exception 'FAIL manager reopen approved';
 exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.owner'),true);
 rev:=public.transition_attendance(attendance_id_test,3,'reopen','Correct paper card');
 if rev<>4 then raise exception 'FAIL reopen';end if;
 perform public.save_attendance(job_id,'2001-01-26',schedule_id_test,4,'work','06:30','20:30',false,120,480,'Corrected test');
 if (select count(*) from public.attendance_revisions where attendance_id=attendance_id_test)<>5 then raise exception 'FAIL revision history';end if;
 if not exists(select 1 from public.attendance_revisions where attendance_id=attendance_id_test and revision=1 and snapshot->>'work_minutes'='750') then raise exception 'FAIL original snapshot';end if;
 perform public.save_attendance(job_id,'2001-01-27',schedule_id_test,0,'work','22:00','06:00',true,60,420,'Overnight test');
 begin
  perform public.save_attendance(job_id,'2001-01-28',schedule_id_test,0,'work','05:00','12:00',false,60,360,'Test overlap');
  raise exception 'FAIL actual overlap';
 exception when raise_exception then if sqlerrm<>'Actual attendance overlaps another day' then raise;end if;end;
 perform public.save_attendance(job_id,'2001-01-28',schedule_id_test,0,'leave',null,null,false,0,0,'Synthetic leave');
 if not exists(select 1 from public.attendance_records where employment_id=job_id and work_date='2001-01-28' and work_minutes=0 and attendance_type='leave') then raise exception 'FAIL non-work';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000099',true);
 if exists(select 1 from public.attendance_records) or exists(select 1 from public.attendance_revisions) then raise exception 'FAIL unauthorized read';end if;
 begin
  perform public.transition_attendance(attendance_id_test,5,'verify','');
  raise exception 'FAIL unauthorized transition';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
select 'PASS: attendance minutes, plan guard, roles, revision, overlap and leave' as result;
rollback;
