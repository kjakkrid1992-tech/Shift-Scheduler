-- Pilot test only. All synthetic data is rolled back.
begin;
do $$
declare owner_id uuid; manager_id uuid; dept_id uuid;
begin
 select user_id into owner_id from public.user_profiles where role='owner' and active order by user_id limit 1;
 select user_id into manager_id from public.user_profiles where role='manager' and active order by user_id limit 1;
 select id into dept_id from public.departments where active order by name limit 1;
 if owner_id is null or manager_id is null or dept_id is null then raise exception 'Missing test prerequisites'; end if;
 perform set_config('staff_test.owner',owner_id::text,true);
 perform set_config('staff_test.manager',manager_id::text,true);
 perform set_config('staff_test.dept',dept_id::text,true);
 if has_table_privilege('authenticated','public.cash_advances','INSERT') or has_table_privilege('authenticated','public.cash_advances','UPDATE') or has_table_privilege('authenticated','public.cash_advance_revisions','UPDATE') or has_table_privilege('anon','public.cash_advances','SELECT') then raise exception 'FAIL direct grants'; end if;
end $$;
set local role authenticated;
do $$
declare dept_key uuid:=current_setting('staff_test.dept')::uuid; employee_key uuid; job_key uuid; advance_key uuid:=gen_random_uuid(); cancelled_key uuid:=gen_random_uuid(); rev integer;
begin
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.owner'),true);
 employee_key:=public.create_staff('EMP-ADV-SQL','Synthetic','Advance','','',dept_key,'Test','daily','2001-01-01','active');
 select id into job_key from public.employment_records where employee_id=employee_key;
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.manager'),true);
 perform public.save_cash_advance(advance_key,job_key,'2001-01-25',0,50001,'Synthetic');
 perform public.save_cash_advance(advance_key,job_key,'2001-01-25',0,50001,'Synthetic');
 if (select count(*) from public.cash_advance_revisions where advance_id=advance_key)<>1 then raise exception 'FAIL duplicate create';end if;
 perform public.save_cash_advance(advance_key,job_key,'2001-01-25',1,60000,'Corrected');
 begin
  perform public.save_cash_advance(advance_key,job_key,'2001-01-25',1,70000,'Stale');
  raise exception 'FAIL stale edit';
 exception when raise_exception then if sqlerrm not like 'STALE_ADVANCE:%' then raise;end if;end;
 begin
  perform public.transition_cash_advance(advance_key,2,'approve');
  raise exception 'FAIL manager approval';
 exception when insufficient_privilege then null;end;
 begin
  perform public.transition_cash_advance(advance_key,2,'pay','2001-01-26','cash','');
  raise exception 'FAIL pay before approval';
 exception when raise_exception then if sqlerrm<>'Invalid advance status transition' then raise;end if;end;
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.owner'),true);
 rev:=public.transition_cash_advance(advance_key,2,'approve');
 if rev<>3 then raise exception 'FAIL approval';end if;
 begin
  perform public.save_cash_advance(advance_key,job_key,'2001-01-25',3,70000,'Bad edit');
  raise exception 'FAIL approved edit';
 exception when raise_exception then if sqlerrm<>'Only draft can be edited' then raise;end if;end;
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.manager'),true);
 begin
  perform public.transition_cash_advance(advance_key,3,'pay','2001-01-26','transfer','');
  raise exception 'FAIL transfer without reference';
 exception when raise_exception then if sqlerrm<>'Payment method or reference invalid' then raise;end if;end;
 rev:=public.transition_cash_advance(advance_key,3,'pay','2001-01-26','transfer','TEST-001');
 if rev<>4 or not exists(select 1 from public.cash_advances ca join public.pay_periods pp on pp.id=ca.period_id where ca.id=advance_key and ca.status='paid' and ca.amount_satang=60000 and pp.start_date='2001-01-26' and pp.end_date='2001-02-25') then raise exception 'FAIL payment period';end if;
 begin
  perform public.transition_cash_advance(advance_key,4,'void',null,null,null,'Test');
  raise exception 'FAIL manager void';
 exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.owner'),true);
 rev:=public.transition_cash_advance(advance_key,4,'void',null,null,null,'Synthetic payment never made');
 if rev<>5 or not exists(select 1 from public.cash_advances where id=advance_key and status='voided' and paid_date='2001-01-26') then raise exception 'FAIL void';end if;
 if (select count(*) from public.cash_advance_revisions where advance_id=advance_key)<>5 or not exists(select 1 from public.cash_advance_revisions where advance_id=advance_key and revision=1 and snapshot->>'amount_satang'='50001') then raise exception 'FAIL revision history';end if;
 perform public.save_cash_advance(cancelled_key,job_key,'2001-01-25',0,10000,'Synthetic cancellation');
 begin
  perform public.transition_cash_advance(cancelled_key,1,'cancel');
  raise exception 'FAIL empty cancel reason';
 exception when raise_exception then if sqlerrm<>'Cancellation reason required' then raise;end if;end;
 perform public.transition_cash_advance(cancelled_key,1,'cancel',null,null,null,'Synthetic');
 if exists(select 1 from public.cash_advances where employment_id=job_key and status='paid') then raise exception 'FAIL paid candidate exclusion';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000099',true);
 if exists(select 1 from public.cash_advances) or exists(select 1 from public.cash_advance_revisions) then raise exception 'FAIL unauthorized read';end if;
 begin
  perform public.transition_cash_advance(advance_key,5,'approve');
  raise exception 'FAIL unauthorized RPC';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
select 'PASS: advance draft, approval, payment period, retry, cancellation, void, roles and history' as result;
rollback;
