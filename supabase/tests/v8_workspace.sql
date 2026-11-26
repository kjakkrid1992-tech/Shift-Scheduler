-- V8 end-to-end: no historical schedule; atomic multi-staff attendance and payroll; rollback always.
begin;
do $$
declare o uuid;m uuid;d uuid;
begin
 select user_id into o from public.user_profiles where role='owner' and active limit 1;
 select user_id into m from public.user_profiles where role='manager' and active limit 1;
 select id into d from public.departments where active limit 1;
 if o is null or m is null or d is null then raise exception 'Missing synthetic roles';end if;
 if exists(select 1 from public.payroll_closures where period_start>='2007-01-26') or exists(select 1 from public.pay_periods where start_date='2007-01-26') or exists(select 1 from public.employment_records where start_date<='2007-02-25' and coalesce(end_date,'infinity'::date)>='2007-01-26') then raise exception 'Test period occupied; isolated DB required';end if;
 perform set_config('staff_test.owner',o::text,true);perform set_config('staff_test.manager',m::text,true);perform set_config('staff_test.dept',d::text,true);
 if has_function_privilege('anon','public.save_attendance_period(date,uuid,text,jsonb)','EXECUTE') or has_function_privilege('anon','public.save_payroll_period_drafts(date,jsonb)','EXECUTE') then raise exception 'Unexpected anonymous RPC access';end if;
end $$;
set local role authenticated;
do $$
declare d uuid:=current_setting('staff_test.dept')::uuid; e uuid;j uuid;jobs uuid[]:='{}'; i integer; day date; rr jsonb:='[]'; verify_rows jsonb; item jsonb; batch jsonb:='[]'; reviews jsonb:='{}'; src jsonb; rec record; adv uuid:=gen_random_uuid(); good jsonb; bad jsonb; expected bigint; total bigint:=0; cap jsonb;
begin
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.owner'),true);
 cap:=public.v8_workspace_capabilities();if cap->>'version'<>'8' then raise exception 'FAIL capability';end if;
 for i in 1..5 loop
  e:=public.create_staff('EMP-V8-SQL-'||i,'Synthetic','V8-'||i,'','',d,'Test',case when i<=3 then 'daily' else 'monthly' end,'2007-01-26','active');
  select id into j from public.employment_records where employee_id=e;jobs:=array_append(jobs,j);
  insert into public.compensation_history(employment_id,pay_type,base_rate,ot_rate,effective_from) values(j,case when i<=3 then 'daily' else 'monthly' end,case when i<=3 then 330 else 10000 end,50,'2007-01-26');
  if i=1 then insert into public.compensation_history(employment_id,pay_type,base_rate,ot_rate,effective_from) values(j,'daily',360,70,'2007-02-01');end if;
  for day in select generate_series(date '2007-01-26',date '2007-02-25',interval '1 day')::date loop
   item:=case when day in ('2007-01-26','2007-02-01') then jsonb_build_object('p_schedule',null,'p_type','work','p_start','06:30','p_end','21:00','p_overnight',false,'p_break',120,'p_normal',480,'p_note','Synthetic paper card')
     else jsonb_build_object('p_schedule',null,'p_type','off','p_start',null,'p_end',null,'p_overnight',false,'p_break',0,'p_normal',0,'p_note','Reviewed synthetic off') end;
   rr:=rr||jsonb_build_array(jsonb_build_object('employment',j,'day',day,'revision',0,'save',true,'payload',item));
  end loop;
 end loop;
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.manager'),true);
 good:=rr->0;bad:=jsonb_set(rr->1,'{payload,p_type}','"invalid"');
 begin perform public.save_attendance_period('2007-02-01',d,'verify',jsonb_build_array(good,bad));raise exception 'FAIL accepted invalid batch';exception when raise_exception then if sqlerrm not like 'Worksheet %Invalid attendance type%' then raise;end if;end;
 if exists(select 1 from public.attendance_records where employment_id=any(jobs)) or exists(select 1 from public.pay_periods where start_date='2007-01-26') then raise exception 'FAIL atomic rollback';end if;
 if jsonb_array_length(public.save_attendance_period('2007-02-01',d,'verify',rr))<>155 then raise exception 'FAIL full worksheet';end if;
 if (select count(*) from public.attendance_records where employment_id=any(jobs) and schedule_id is null and planned_snapshot='[]'::jsonb and status='verified' and revision=2)<>155 then raise exception 'FAIL unscheduled records';end if;
 if exists(select 1 from public.shift_schedules s join public.pay_periods p on s.period_id=p.id where p.start_date='2007-01-26') then raise exception 'FAIL fabricated schedule';end if;
 select jsonb_agg(jsonb_build_object('employment',employment_id,'day',work_date,'revision',revision,'save',false)) into verify_rows from public.attendance_records where employment_id=any(jobs);
 begin perform public.save_attendance_period('2007-02-01',d,'approve',verify_rows);raise exception 'FAIL manager approval';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.owner'),true);
 if jsonb_array_length(public.save_attendance_period('2007-02-01',d,'approve',verify_rows))<>155 then raise exception 'FAIL approve full worksheet';end if;
 perform public.save_cash_advance(adv,jobs[1],'2007-02-02',0,10000,'Synthetic advance');
 perform public.transition_cash_advance(adv,1,'approve');perform public.transition_cash_advance(adv,2,'pay','2007-02-02','cash','');
 for i in 1..5 loop
  j:=jobs[i];src:=public.preview_payroll(j,'2007-02-01');
  if jsonb_array_length(src->'days')<>31 or (select count(*) from jsonb_array_elements(src->'days') x where x->>'status'='approved')<>31 then raise exception 'FAIL payroll source attendance';end if;
  -- Independent expected: daily #1 330+360 and 4.5h*50+4.5h*70; #2–3 2*330 and 9h*50. Monthly base explicitly reviewed, not inferred.
  item:=jsonb_build_object('base',case when i=1 then 69000 when i<=3 then 66000 else 1000000 end,'ot',case when i=1 then 54000 else 45000 end,'paid_leave',0,'attendance_bonus',0,'performance_bonus',0,'behavior_bonus',0,'other_income',0,'advance',case when i=1 then 10000 else 0 end,'social_security',0,'tax',0,'other_deduction',0);
  batch:=batch||jsonb_build_array(jsonb_build_object('employment',j,'revision',0,'source',src,'items',item,'note','Synthetic reviewed totals'));
 end loop;
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.manager'),true);
 begin perform public.save_payroll_period_drafts('2007-02-01',jsonb_build_array(batch->0,jsonb_set(batch->1,'{items,base}','-1')));raise exception 'FAIL invalid payroll batch';exception when raise_exception then if sqlerrm not like 'Payroll worksheet %Enter each reviewed item%' then raise;end if;end;
 if exists(select 1 from public.payroll_drafts where employment_id=any(jobs)) then raise exception 'FAIL payroll batch rollback';end if;
 if jsonb_array_length(public.save_payroll_period_drafts('2007-02-01',batch))<>5 then raise exception 'FAIL payroll batch';end if;
 for rec in select * from public.payroll_drafts where employment_id=any(jobs) loop
  reviews:=reviews||jsonb_build_object(rec.id::text,jsonb_build_object('revision',rec.revision,'evidence','Synthetic reviewed deduction'));total:=total+rec.net_satang;
 end loop;
 expected:=113000+2*111000+2*1045000;
 if total<>expected then raise exception 'FAIL net totals %, expected %',total,expected;end if;
 begin perform public.close_payroll('2007-02-01',reviews,'Synthetic review');raise exception 'FAIL manager close';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.owner'),true);
 perform public.close_payroll('2007-02-01',reviews,'Synthetic review');
 if (select sum(net_satang) from public.payroll_final where employment_id=any(jobs))<>expected then raise exception 'FAIL final totals';end if;
 for rec in select * from public.payroll_final where employment_id=any(jobs) loop perform public.record_payroll_payment(rec.id,'2007-02-26','cash','Synthetic only');end loop;
 if (select count(*) from public.payroll_final where employment_id=any(jobs) and paid_at is not null)<>5 then raise exception 'FAIL final payments';end if;
 begin perform public.transition_attendance((select id from public.attendance_records where employment_id=jobs[1] and work_date='2007-01-26'),3,'reopen','Synthetic');raise exception 'FAIL closed attendance mutation';exception when raise_exception then if sqlerrm not like 'PAYROLL_LOCKED:%' then raise;end if;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000099',true);
 begin perform public.save_attendance_period('2007-02-01',d,'verify',rr);raise exception 'FAIL unauthorized batch';exception when insufficient_privilege then null;end;
end $$;
reset role;
select 'PASS V8 155 unscheduled attendance rows, atomic batches, five payrolls, independent net total, close, payment and permissions' as result;
rollback;
