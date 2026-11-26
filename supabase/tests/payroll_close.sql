-- Isolated pilot only. All synthetic changes rollback. No real payments.
begin;
do $$
declare o uuid; m uuid; d uuid;
begin
 select user_id into o from public.user_profiles where role='owner' and active limit 1;
 select user_id into m from public.user_profiles where role='manager' and active limit 1;
 select id into d from public.departments where active limit 1;
 if o is null or m is null or d is null then raise exception 'Missing test prerequisites';end if;
 if exists(select 1 from public.payroll_closures where period_start>='2004-01-26')
 or exists(select 1 from public.employment_records where start_date<='2004-03-25' and coalesce(end_date,'infinity'::date)>='2004-01-26')
 or exists(select 1 from public.pay_periods where start_date in ('2004-01-26','2004-02-26')) then raise exception 'Synthetic periods occupied; use isolated pilot';end if;
 perform set_config('staff_test.owner',o::text,true);perform set_config('staff_test.manager',m::text,true);perform set_config('staff_test.dept',d::text,true);
 if has_table_privilege('authenticated','public.payroll_final','UPDATE') or has_table_privilege('authenticated','public.payroll_advance_allocations','INSERT') or has_table_privilege('anon','public.payroll_closures','SELECT') then raise exception 'FAIL direct privileges';end if;
end $$;
set local role authenticated;
do $$
declare job_key uuid; emp_key uuid; dept_key uuid:=current_setting('staff_test.dept')::uuid; sid uuid; aid uuid; first_aid uuid;
 adv_key uuid:=gen_random_uuid(); draft_key uuid; final_key uuid; src jsonb; vals jsonb; reviews jsonb; payload jsonb; day_row record; month_day date; i integer;
begin
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.owner'),true);
 emp_key:=public.create_staff('EMP-CLOSE-SQL','Synthetic','Close','','',dept_key,'Test','daily','2004-01-26','active');
 select id into job_key from public.employment_records where employee_id=emp_key;
 insert into public.compensation_history(employment_id,pay_type,base_rate,ot_rate,effective_from) values(job_key,'daily',330,50,'2004-01-26');
 perform public.save_cash_advance(adv_key,job_key,'2004-01-26',0,100000,'Synthetic advance');
 perform public.transition_cash_advance(adv_key,1,'approve');
 perform public.transition_cash_advance(adv_key,2,'pay','2004-01-26','cash','');
 for i in 1..2 loop
  month_day:=case when i=1 then date '2004-02-01' else date '2004-03-01' end;
  sid:=public.open_shift_schedule(dept_key,month_day,false);
  select jsonb_agg(jsonb_build_object('id',id,'work_date',work_date,'shift_template_id',shift_template_id,'employment_id',job_key,'planned_minutes',planned_minutes,'is_extra',is_extra,'is_locked',false)) into payload from public.shift_assignments where schedule_id=sid;
  perform public.save_shift_schedule(sid,0,payload,'{}',true,true);
  src:=public.preview_payroll(job_key,month_day);
  if (src->>'paid_advance_satang')::bigint is distinct from (case when i=1 then 100000 else 60000 end)::bigint then raise exception 'FAIL residual balance';end if;
  vals:=jsonb_build_object('base',800000,'ot',0,'paid_leave',0,'attendance_bonus',0,'performance_bonus',0,'behavior_bonus',0,'other_income',0,'advance',case when i=1 then 40000 else 60000 end,'social_security',0,'tax',0,'other_deduction',0);
  if i=1 then
   draft_key:=public.save_payroll_items(job_key,month_day,0,src,vals,'Synthetic incomplete draft');
   reviews:=jsonb_build_object(draft_key::text,jsonb_build_object('revision',1,'evidence','Synthetic'));
   begin
    perform public.close_payroll(month_day,reviews,'Synthetic incomplete');
    raise exception 'FAIL incomplete attendance allowed';
   exception when raise_exception then if sqlerrm not like 'Attendance incomplete%' then raise;end if;end;
  end if;
  for day_row in select value->>'date' as d from jsonb_array_elements(src->'days') loop
   aid:=public.save_attendance(job_key,day_row.d::date,sid,0,'off',null,null,false,0,0,'Synthetic day reviewed');
   perform public.transition_attendance(aid,1,'verify','');
   perform public.transition_attendance(aid,2,'approve','');
   if i=1 and first_aid is null then first_aid:=aid;end if;
  end loop;
  if i=1 then
   begin
    perform public.close_payroll(month_day,reviews,'Synthetic stale source');
    raise exception 'FAIL stale source allowed';
   exception when raise_exception then if sqlerrm not like 'STALE_PAYROLL_SOURCE:%' then raise;end if;end;
  end if;
  src:=public.preview_payroll(job_key,month_day);
  draft_key:=public.save_payroll_items(job_key,month_day,case when i=1 then 1 else 0 end,src,vals,'Synthetic reviewed manual amounts');
  reviews:=jsonb_build_object(draft_key::text,jsonb_build_object('revision',case when i=1 then 2 else 1 end,'evidence','Synthetic deduction evidence'));
  perform set_config('request.jwt.claim.sub',current_setting('staff_test.manager'),true);
  begin
   perform public.close_payroll(month_day,reviews,'Synthetic');
   raise exception 'FAIL manager close';
  exception when insufficient_privilege then null;end;
  perform set_config('request.jwt.claim.sub',current_setting('staff_test.owner'),true);
  begin
   perform public.close_payroll(month_day,jsonb_set(reviews,array[draft_key::text,'evidence'],'""'::jsonb),'Synthetic');
   raise exception 'FAIL missing deduction evidence';
  exception when raise_exception then if sqlerrm not like 'Deduction review evidence required%' then raise;end if;end;
  perform public.close_payroll(month_day,reviews,'Synthetic reviewed all staff');
  select id into final_key from public.payroll_final where draft_id=draft_key;
  if final_key is null or not exists(select 1 from public.payroll_advance_allocations where final_id=final_key and advance_id=adv_key and amount_satang=case when i=1 then 40000 else 60000 end) then raise exception 'FAIL allocation';end if;
  if not exists(select 1 from public.payroll_final where id=final_key and net_satang=case when i=1 then 760000 else 740000 end and paid_at is null and snapshot->'item_breakdown'->'items'=vals) then raise exception 'FAIL final snapshot';end if;
  begin
   perform public.close_payroll(month_day,reviews,'Synthetic repeat');
   raise exception 'FAIL repeat close';
  exception when raise_exception then if sqlerrm<>'Payroll already closed or later period closed' then raise;end if;end;
  perform set_config('request.jwt.claim.sub',current_setting('staff_test.manager'),true);
  begin
   perform public.record_payroll_payment(final_key,month_day+24,'cash','');
   raise exception 'FAIL manager payment';
  exception when insufficient_privilege then null;end;
  perform set_config('request.jwt.claim.sub',current_setting('staff_test.owner'),true);
  perform public.record_payroll_payment(final_key,month_day+24,'transfer','TEST-ONLY');
  begin
   perform public.record_payroll_payment(final_key,month_day+24,'cash','');
   raise exception 'FAIL duplicate payment';
  exception when raise_exception then if sqlerrm<>'Payroll payment already recorded' then raise;end if;end;
  if not exists(select 1 from public.payroll_final where id=final_key and paid_date=month_day+24 and payment_reference='TEST-ONLY') then raise exception 'FAIL payment snapshot';end if;
 end loop;
 if (select sum(amount_satang) from public.payroll_advance_allocations where advance_id=adv_key)<>100000 then raise exception 'FAIL allocation total';end if;
 begin
  perform public.transition_attendance(first_aid,3,'reopen','Synthetic');
  raise exception 'FAIL closed attendance edit';
 exception when raise_exception then if sqlerrm not like 'PAYROLL_LOCKED:%' then raise;end if;end;
 begin
  perform public.transition_cash_advance(adv_key,3,'void',null,null,null,'Synthetic');
  raise exception 'FAIL allocated advance void';
 exception when raise_exception then if sqlerrm not like 'PAYROLL_LOCKED:%' then raise;end if;end;
 begin
  insert into public.compensation_history(employment_id,pay_type,base_rate,ot_rate,effective_from) values(job_key,'daily',360,70,'2004-02-01');
  raise exception 'FAIL retroactive rate';
 exception when raise_exception then if sqlerrm not like 'PAYROLL_LOCKED:%' then raise;end if;end;
 src:=public.preview_payroll(job_key,'2004-03-01');
 begin
  perform public.save_payroll_items(job_key,'2004-03-01',1,src,jsonb_set(vals,'{advance}','0'),'Synthetic');
  raise exception 'FAIL closed draft edit';
 exception when raise_exception then if sqlerrm not like 'PAYROLL_LOCKED:%' then raise;end if;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000099',true);
 if exists(select 1 from public.payroll_final) or exists(select 1 from public.payroll_advance_allocations) or exists(select 1 from public.payroll_closures) then raise exception 'FAIL unauthorized read';end if;
end $$;
reset role;
select 'PASS: payroll close, source lock, advance carryover, payment and access' as result;
rollback;
