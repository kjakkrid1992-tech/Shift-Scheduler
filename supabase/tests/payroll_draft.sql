-- Isolated pilot; rollback all synthetic data.
begin;
do $$
declare o uuid; m uuid; d uuid;
begin
 select user_id into o from public.user_profiles where role='owner' and active order by user_id limit 1;
 select user_id into m from public.user_profiles where role='manager' and active order by user_id limit 1;
 select id into d from public.departments where active order by name limit 1;
 if o is null or m is null or d is null then raise exception 'Missing test roles'; end if;
 if exists(select 1 from public.pay_periods where start_date='2002-01-26') then raise exception 'Test period occupied'; end if;
 perform set_config('staff_test.owner',o::text,true);perform set_config('staff_test.manager',m::text,true);perform set_config('staff_test.dept',d::text,true);
 if has_table_privilege('authenticated','public.payroll_drafts','INSERT') or has_table_privilege('authenticated','public.payroll_draft_revisions','UPDATE') or has_table_privilege('anon','public.payroll_drafts','SELECT') then raise exception 'FAIL direct grants';end if;
end $$;
set local role authenticated;
do $$
declare dept_key uuid:=current_setting('staff_test.dept')::uuid; emp_key uuid; job_key uuid; sid uuid; aid uuid; adv_key uuid:=gen_random_uuid(); draft_key uuid; payload jsonb; src jsonb; changed jsonb;
begin
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.owner'),true);
 emp_key:=public.create_staff('EMP-PAY-SQL','Synthetic','Payroll','','',dept_key,'Test','daily','2002-01-26','active');
 select id into job_key from public.employment_records where employee_id=emp_key;
 insert into public.compensation_history(employment_id,pay_type,base_rate,ot_rate,effective_from) values(job_key,'daily',330,50,'2002-01-26');
 insert into public.compensation_history(employment_id,pay_type,base_rate,ot_rate,effective_from) values(job_key,'daily',360,70,'2002-01-27');
 sid:=public.open_shift_schedule(dept_key,'2002-02-01',false);
 select jsonb_agg(jsonb_build_object('id',id,'work_date',work_date,'shift_template_id',shift_template_id,'employment_id',job_key,'planned_minutes',planned_minutes,'is_extra',is_extra,'is_locked',false)) into payload from public.shift_assignments where schedule_id=sid;
 perform public.save_shift_schedule(sid,0,payload,'{}',true,true);
 aid:=public.save_attendance(job_key,'2002-01-26',sid,0,'work','06:30','16:30',false,60,480,'Synthetic');
 perform public.transition_attendance(aid,1,'verify','');
 perform public.transition_attendance(aid,2,'approve','');
 perform public.save_cash_advance(adv_key,job_key,'2002-01-26',0,50000,'Synthetic');
 perform public.transition_cash_advance(adv_key,1,'approve');
 perform public.transition_cash_advance(adv_key,2,'pay','2002-01-26','cash','');
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.manager'),true);
 src:=public.preview_payroll(job_key,'2002-02-01');
 if jsonb_array_length(src->'days')<>31 or (src->>'paid_advance_satang')::bigint<>50000 or (src->'days'->0->>'status') is distinct from 'approved' or (src->'days'->0->>'base_rate')::numeric is distinct from 330 or (src->'days'->1->>'base_rate')::numeric is distinct from 360 then raise exception 'FAIL preview';end if;
 begin
  perform public.save_payroll_draft(job_key,'2002-02-01',0,src,33000,5000,0,50001,0,'Synthetic');
  raise exception 'FAIL deduction cap';
 exception when raise_exception then if sqlerrm<>'Advance deduction exceeds paid candidate total' then raise;end if;end;
 draft_key:=public.save_payroll_draft(job_key,'2002-02-01',0,src,33000,5000,0,0,0,'Synthetic draft');
 if not exists(select 1 from public.payroll_drafts where id=draft_key and net_satang=38000 and revision=1) then raise exception 'FAIL draft';end if;
 begin
  perform public.save_payroll_draft(job_key,'2002-02-01',0,src,33000,5000,0,0,0,'Stale');
  raise exception 'FAIL stale draft';
 exception when raise_exception then if sqlerrm not like 'STALE_PAYROLL_DRAFT:%' then raise;end if;end;
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.owner'),true);
 perform public.transition_attendance(aid,3,'reopen','Synthetic correction');
 changed:=public.preview_payroll(job_key,'2002-02-01');
 if changed=src then raise exception 'FAIL source detection';end if;
 begin
  perform public.save_payroll_draft(job_key,'2002-02-01',1,src,33000,5000,0,0,0,'Stale source');
  raise exception 'FAIL stale source';
 exception when raise_exception then if sqlerrm not like 'STALE_PAYROLL_SOURCE:%' then raise;end if;end;
 perform public.save_payroll_draft(job_key,'2002-02-01',1,changed,0,0,0,0,0,'Synthetic reviewed draft');
 if (select count(*) from public.payroll_draft_revisions where draft_id=draft_key)<>2 then raise exception 'FAIL history';end if;
 if not exists(select 1 from public.cash_advances where id=adv_key and status='paid') then raise exception 'FAIL source mutated';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000099',true);
 if exists(select 1 from public.payroll_drafts) or exists(select 1 from public.payroll_draft_revisions) then raise exception 'FAIL unauthorized read';end if;
 begin
  perform public.preview_payroll(job_key,'2002-02-01');
  raise exception 'FAIL unauthorized preview';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
select 'PASS: payroll preview, effective rates, paid advances, draft history, stale source and access' as result;
rollback;
