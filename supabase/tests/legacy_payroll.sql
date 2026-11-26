-- Synthetic test, rollback all changes.
begin;
do $$
declare o uuid; m uuid; e uuid;
begin
 select user_id into o from public.user_profiles where role='owner' and active limit 1;
 select user_id into m from public.user_profiles where role='manager' and active limit 1;
 select id into e from public.employees limit 1;
 if o is null or m is null or e is null then raise exception 'Need active owner, manager and existing test employee';end if;
 perform set_config('staff_test.owner',o::text,true);perform set_config('staff_test.manager',m::text,true);perform set_config('staff_test.employee',e::text,true);
 if has_table_privilege('authenticated','public.legacy_payslips','INSERT') or has_table_privilege('authenticated','public.legacy_payslips','UPDATE') or has_table_privilege('anon','public.legacy_payslips','SELECT') then raise exception 'FAIL grants';end if;
end $$;
set local role authenticated;
do $$
declare rec jsonb; out jsonb; sid uuid; emp uuid:=current_setting('staff_test.employee')::uuid; sh text:='TEST-'||gen_random_uuid()::text; sha text:=repeat('a',64);
begin
 rec:=jsonb_build_object('sheet',sh,'row',1,'period_label','Synthetic','recorded_date','','source_name','','position','Test','income_satang',10000,'deduction_satang',1000,'net_satang',9000,'lines','[{"side":"income","label":"Test income","amount_satang":10000},{"side":"deduction","label":"Test deduction","amount_satang":1000}]'::jsonb);
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.owner'),true);
 out:=public.import_legacy_payroll(sha,jsonb_build_array(rec));
 if (out->>'inserted')::int is distinct from 1 then raise exception 'FAIL insert';end if;
 out:=public.import_legacy_payroll(sha,jsonb_build_array(rec));
 if (out->>'skipped')::int is distinct from 1 or (out->>'inserted')::int is distinct from 0 then raise exception 'FAIL retry';end if;
 select id into sid from public.legacy_payslips where source_sheet=sh and source_row=1 and net_satang=9000 and employee_id is null;
 if sid is null then raise exception 'FAIL archive';end if;
 begin
  perform public.import_legacy_payroll(sha,jsonb_build_array(jsonb_set(rec,'{source_name}','"Changed"')));
  raise exception 'FAIL source conflict';
 exception when raise_exception then if sqlerrm not like 'SOURCE_CONFLICT:%' then raise;end if;end;
 begin
  perform public.import_legacy_payroll(sha,jsonb_build_array(jsonb_set(rec,'{row}','2')));
  raise exception 'FAIL duplicate';
 exception when raise_exception then if sqlerrm not like 'POSSIBLE_DUPLICATE:%' then raise;end if;end;
 begin
  perform public.import_legacy_payroll(sha,jsonb_build_array(jsonb_set(rec,'{net_satang}','9001')));
  raise exception 'FAIL arithmetic';
 exception when raise_exception then if sqlerrm<>'Legacy totals do not reconcile' then raise;end if;end;
 perform public.link_legacy_identity(sid,0,emp,'Synthetic match');
 begin
  perform public.link_legacy_identity(sid,0,null,'Stale');
  raise exception 'FAIL stale';
 exception when raise_exception then if sqlerrm not like 'STALE_LEGACY_LINK:%' then raise;end if;end;
 perform public.link_legacy_identity(sid,1,null,'Synthetic unlink');
 if (select count(*) from public.legacy_identity_links where slip_id=sid)<>2 or not exists(select 1 from public.legacy_payslips where id=sid and employee_id is null and link_revision=2) then raise exception 'FAIL link history';end if;
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.manager'),true);
 if exists(select 1 from public.legacy_payslips) or exists(select 1 from public.legacy_import_batches) or exists(select 1 from public.legacy_identity_links) then raise exception 'FAIL manager read';end if;
 begin
  perform public.import_legacy_payroll(sha,jsonb_build_array(rec));
  raise exception 'FAIL manager import';
 exception when insufficient_privilege then null;end;
 begin
  perform public.link_legacy_identity(sid,2,emp,'Denied');
  raise exception 'FAIL manager link';
 exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000099',true);
 if exists(select 1 from public.legacy_payslips) then raise exception 'FAIL outsider read';end if;
end $$;
reset role;
select 'PASS: legacy archive, reconciliation, duplicate guard, identity history and access' as result;
rollback;
