-- Synthetic fixture on isolated pilot only; rollback.
begin;
do $$
declare o uuid;m uuid;d uuid;e uuid;j uuid;fd uuid;fk uuid;
begin
 select user_id into o from public.user_profiles where role='owner' and active limit 1;
 select user_id into m from public.user_profiles where role='manager' and active limit 1;
 select id into d from public.departments where active limit 1;
 if o is null or m is null or d is null then raise exception 'Need owner, manager and department';end if;
 if exists(select 1 from public.pay_periods where start_date='2007-01-26') then raise exception 'Test period occupied';end if;
 perform set_config('request.jwt.claim.sub',o::text,true);
 e:=public.create_staff('EMP-ADJUST-SQL','Synthetic','Correction','','',d,'Test','daily','2007-01-26','active');
 select id into j from public.employment_records where employee_id=e;
 perform staff_private.advance_period('2007-01-26');
 insert into public.payroll_drafts(employment_id,period_start,source_snapshot,base_satang,ot_satang,other_income_satang,advance_deduction_satang,other_deduction_satang,review_note,updated_by) values(j,'2007-01-26','{}',100000,0,0,0,0,'Synthetic fixture',o) returning id into fd;
 insert into public.payroll_closures(period_start,period_end,approved_by,approval_note) values('2007-01-26','2007-02-25',o,'Synthetic fixture');
 insert into public.payroll_final(period_start,employment_id,draft_id,draft_revision,snapshot,net_satang) values('2007-01-26',j,fd,1,'{}',100000) returning id into fk;
 perform set_config('staff_test.owner',o::text,true);perform set_config('staff_test.manager',m::text,true);perform set_config('staff_test.final',fk::text,true);
 if has_table_privilege('authenticated','public.payroll_adjustments','UPDATE') or has_table_privilege('anon','public.payroll_adjustments','SELECT') then raise exception 'FAIL grants';end if;
end $$;
set local role authenticated;
do $$
declare fk uuid:=current_setting('staff_test.final')::uuid;r uuid;r2 uuid;r3 uuid;a uuid;b uuid;report jsonb;
begin
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.owner'),true);
 r:=public.request_payroll_correction(fk,'income','Synthetic extra income',5000);
 perform public.review_payroll_correction(r,'needs_adjustment','Synthetic reviewed');
 begin
  perform public.approve_payroll_adjustment(r,5000,'Evidence');raise exception 'FAIL unpaid original';
 exception when raise_exception then if sqlerrm not like 'Original payroll must%' then raise;end if;end;
 perform public.record_payroll_payment(fk,'2007-02-25','transfer','TEST-ONLY');
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.manager'),true);
 begin
  perform public.approve_payroll_adjustment(r,5000,'Denied');raise exception 'FAIL manager approval';
 exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.owner'),true);
 a:=public.approve_payroll_adjustment(r,5000,'Evidence');
 if a is distinct from public.approve_payroll_adjustment(r,5000,'Evidence') then raise exception 'FAIL retry';end if;
 perform public.settle_payroll_adjustment(a,'2007-02-26','cash','TEST-EXTRA');
 begin
  perform public.settle_payroll_adjustment(a,'2007-02-26','cash','TEST-EXTRA');raise exception 'FAIL duplicate payment';
 exception when raise_exception then if sqlerrm<>'Adjustment is no longer awaiting settlement' then raise;end if;end;
 r2:=public.request_payroll_correction(fk,'deduction','Synthetic voluntary return',-30000);
 perform public.review_payroll_correction(r2,'needs_adjustment','Evidence');
 b:=public.approve_payroll_adjustment(r2,-30000,'Synthetic voluntary consent');
 r3:=public.request_payroll_correction(fk,'income','Synthetic second return',-80000);
 perform public.review_payroll_correction(r3,'needs_adjustment','Evidence');
 begin
  perform public.approve_payroll_adjustment(r3,-80000,'Evidence');raise exception 'FAIL return cap';
 exception when raise_exception then if sqlerrm<>'Return exceeds original net paid' then raise;end if;end;
 perform public.cancel_payroll_adjustment(b,'No return received');
 a:=public.approve_payroll_adjustment(r3,-80000,'Evidence');
 perform public.settle_payroll_adjustment(a,'2007-02-26','transfer','TEST-RETURN');
 report:=public.payroll_adjustment_report('2007-03-01',null);
 if (report->>'period_paid')::bigint<>5000 or (report->>'period_returned')::bigint<>80000 then raise exception 'FAIL report';end if;
 if not exists(select 1 from public.payroll_final where id=fk and net_satang=100000 and payment_reference='TEST-ONLY') then raise exception 'FAIL immutable original';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000099',true);
 if exists(select 1 from public.payroll_adjustments) then raise exception 'FAIL outsider read';end if;
end $$;
reset role;
select 'PASS: separate adjustments, original immutable, return cap, payment retry and reports' as result;
rollback;
