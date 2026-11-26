-- Synthetic regression; rollback. Run in isolated pilot with active owner and manager.
begin;
do $$
declare o uuid;m uuid;d uuid;
begin
 select user_id into o from public.user_profiles where role='owner' and active limit 1;
 select user_id into m from public.user_profiles where role='manager' and active limit 1;
 select id into d from public.departments where active limit 1;
 if o is null or m is null or d is null then raise exception 'Need owner, manager and department';end if;
 if exists(select 1 from public.pay_periods where start_date='2005-01-26') then raise exception 'Test period occupied';end if;
 perform set_config('staff_test.owner',o::text,true);perform set_config('staff_test.manager',m::text,true);perform set_config('staff_test.dept',d::text,true);
end $$;
set local role authenticated;
do $$
declare dept_key uuid:=current_setting('staff_test.dept')::uuid; e1 uuid;e2 uuid;j1 uuid;j2 uuid;sid uuid;payload jsonb;rs jsonb;rr jsonb;a jsonb;b jsonb;out jsonb;
begin
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.owner'),true);
 e1:=public.create_staff('EMP-BULK-SQL-1','Synthetic','Bulk One','','',dept_key,'Test','daily','2005-01-26','active');
 e2:=public.create_staff('EMP-BULK-SQL-2','Synthetic','Bulk Two','','',dept_key,'Test','daily','2005-01-26','active');
 select id into j1 from public.employment_records where employee_id=e1;select id into j2 from public.employment_records where employee_id=e2;
 sid:=public.open_shift_schedule(dept_key,'2005-02-01',false);
 select jsonb_agg(jsonb_build_object('id',id,'work_date',work_date,'shift_template_id',shift_template_id,'employment_id',j1,'planned_minutes',planned_minutes,'is_extra',is_extra,'is_locked',false)) into payload from public.shift_assignments where schedule_id=sid;
 perform public.save_shift_schedule(sid,0,payload,'{}',true,true);
 a:=jsonb_build_object('employment_id',j1,'revision',0,'type','work','start','06:30','end','15:30','overnight',false,'break',60,'normal',480,'note','Synthetic');
 b:=jsonb_build_object('employment_id',j2,'revision',0,'type','off','start',null,'end',null,'overnight',false,'break',0,'normal',0,'note','');
 rs:=jsonb_build_array(a,b);
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.manager'),true);
 begin
  perform public.bulk_attendance('2005-01-26',dept_key,sid,'save_verify',jsonb_build_array(a,jsonb_set(b,'{normal}','1')));
  raise exception 'FAIL invalid batch';
 exception when raise_exception then if sqlerrm<>'Non-work day must have no actual hours' then raise;end if;end;
 if exists(select 1 from public.attendance_records where employment_id in (j1,j2)) then raise exception 'FAIL atomic rollback';end if;
 if public.bulk_attendance('2005-01-26',dept_key,sid,'save_verify',rs)<>2 then raise exception 'FAIL bulk count';end if;
 select jsonb_agg(jsonb_build_object('employment_id',employment_id,'id',id,'revision',revision)) into rr from public.attendance_records where employment_id in (j1,j2);
 begin
  perform public.bulk_attendance('2005-01-26',dept_key,sid,'approve',rr);raise exception 'FAIL manager approval';
 exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.owner'),true);
 perform public.bulk_attendance('2005-01-26',dept_key,sid,'approve',rr);
 out:=public.staff_period_report('2005-02-01',e1);
 if (out->>'approved_days')::int<>1 or (out->>'normal_minutes')::int<>480 or (out->>'expected_days')::int<>31 or (out->>'draft_count')::int<>0 then raise exception 'FAIL report totals';end if;
 begin
  perform public.bulk_attendance('2005-01-26',dept_key,sid,'approve',rr);raise exception 'FAIL stale approval';
 exception when raise_exception then if sqlerrm not like 'STALE_ATTENDANCE:%' then raise;end if;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000099',true);
 begin
  perform public.staff_period_report('2005-02-01',e1);raise exception 'FAIL outsider report';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
select 'PASS: bulk attendance atomicity, roles, revision and report totals' as result;
rollback;
