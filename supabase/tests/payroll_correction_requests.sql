-- Synthetic fixture on isolated pilot only; rollback.
begin;
do $$
declare o uuid;m uuid;d uuid;e uuid;j uuid;fd uuid;fk uuid;
begin
 select user_id into o from public.user_profiles where role='owner' and active limit 1;
 select user_id into m from public.user_profiles where role='manager' and active limit 1;
 select id into d from public.departments where active limit 1;
 if o is null or m is null or d is null then raise exception 'Need owner, manager and department';end if;
 if exists(select 1 from public.pay_periods where start_date='2006-01-26') then raise exception 'Test period occupied';end if;
 perform set_config('request.jwt.claim.sub',o::text,true);
 e:=public.create_staff('EMP-CORRECT-SQL','Synthetic','Correction','','',d,'Test','daily','2006-01-26','active');
 select id into j from public.employment_records where employee_id=e;
 perform staff_private.advance_period('2006-01-26');
 insert into public.payroll_drafts(employment_id,period_start,source_snapshot,base_satang,ot_satang,other_income_satang,advance_deduction_satang,other_deduction_satang,review_note,updated_by) values(j,'2006-01-26','{}',100000,0,0,0,0,'Synthetic fixture',o) returning id into fd;
 insert into public.payroll_closures(period_start,period_end,approved_by,approval_note) values('2006-01-26','2006-02-25',o,'Synthetic fixture');
 insert into public.payroll_final(period_start,employment_id,draft_id,draft_revision,snapshot,net_satang) values('2006-01-26',j,fd,1,'{}',100000) returning id into fk;
 perform set_config('staff_test.owner',o::text,true);perform set_config('staff_test.manager',m::text,true);perform set_config('staff_test.final',fk::text,true);
 if has_table_privilege('authenticated','public.payroll_correction_requests','UPDATE') or has_table_privilege('anon','public.payroll_correction_requests','SELECT') then raise exception 'FAIL grants';end if;
end $$;
set local role authenticated;
do $$
declare fk uuid:=current_setting('staff_test.final')::uuid;a uuid;b uuid;
begin
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.manager'),true);
 a:=public.request_payroll_correction(fk,'income','Synthetic missing income',10000);
 b:=public.request_payroll_correction(fk,'income','Synthetic missing income',10000);
 if a is distinct from b then raise exception 'FAIL retry';end if;
 begin
  perform public.review_payroll_correction(a,'needs_adjustment','Denied');raise exception 'FAIL manager review';
 exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.owner'),true);
 perform public.review_payroll_correction(a,'needs_adjustment','Synthetic evidence');
 if not exists(select 1 from public.payroll_correction_requests where id=a and status='needs_adjustment' and reviewed_by=auth.uid()) then raise exception 'FAIL decision';end if;
 if not exists(select 1 from public.payroll_final where id=fk and net_satang=100000 and paid_at is null) then raise exception 'FAIL final mutated';end if;
 begin
  perform public.review_payroll_correction(a,'dismissed','Retry');raise exception 'FAIL repeated review';
 exception when raise_exception then if sqlerrm not like 'STALE_CORRECTION:%' then raise;end if;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000099',true);
 if exists(select 1 from public.payroll_correction_requests) then raise exception 'FAIL outsider read';end if;
end $$;
reset role;
select 'PASS: correction request, review roles, retry and immutable final' as result;
rollback;
