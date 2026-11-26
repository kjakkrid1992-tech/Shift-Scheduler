-- Synthetic test, rollback all changes.
begin;
do $$
declare o uuid;m uuid;
begin
 select user_id into o from public.user_profiles where role='owner' and active limit 1;
 select user_id into m from public.user_profiles where role='manager' and active limit 1;
 if o is null or m is null then raise exception 'Need owner and manager';end if;
 perform set_config('staff_test.owner',o::text,true);perform set_config('staff_test.manager',m::text,true);
 if has_table_privilege('authenticated','public.legacy_staff_reviews','INSERT') or has_table_privilege('authenticated','public.legacy_staff_reviews','UPDATE') or has_table_privilege('anon','public.legacy_staff_reviews','SELECT') then raise exception 'FAIL direct privileges';end if;
end $$;
set local role authenticated;
do $$
declare sh text:='TEST-'||gen_random_uuid()::text; rec jsonb; ids jsonb; emp uuid; a uuid; b uuid; c uuid; before_count integer; code text:='TEST-'||left(gen_random_uuid()::text,8);
begin
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.owner'),true);
 rec:=jsonb_build_object('sheet',sh,'row',1,'period_label',sh,'recorded_date','','source_name',sh,'position','Test','income_satang',10000,'deduction_satang',0,'net_satang',10000,'lines','[{"side":"income","label":"Test income","amount_satang":10000}]'::jsonb);
 perform public.import_legacy_payroll(repeat('b',64),jsonb_build_array(rec,jsonb_set(jsonb_set(rec,'{row}','2'),'{period_label}',to_jsonb(sh||'-2'))));
 select jsonb_agg(jsonb_build_object('id',id,'revision',link_revision)) into ids from public.legacy_payslips where source_sheet=sh;
 emp:=public.review_legacy_identity(ids,null,jsonb_build_object('code',code,'first',sh,'last','Synthetic'),'Synthetic verified identity');
 if (select count(*) from public.legacy_payslips where source_sheet=sh and employee_id=emp and link_revision=1)<>2 or exists(select 1 from public.employment_records where employee_id=emp) then raise exception 'FAIL identity only';end if;
 if (select count(*) from public.legacy_identity_links where employee_id=emp)<>2 then raise exception 'FAIL audit';end if;
 perform public.import_legacy_payroll(repeat('b',64),jsonb_build_array(jsonb_set(jsonb_set(rec,'{row}','3'),'{period_label}',to_jsonb(sh||'-3')),jsonb_set(jsonb_set(rec,'{row}','4'),'{source_name}','""')));
 select jsonb_agg(jsonb_build_object('id',id,'revision',link_revision)) into ids from public.legacy_payslips where source_sheet=sh and source_row=3;
 perform public.review_legacy_identity(ids,emp,null,'Synthetic existing match');
 if not exists(select 1 from public.legacy_payslips where source_sheet=sh and source_row=3 and employee_id=emp) then raise exception 'FAIL existing match';end if;
 select jsonb_agg(jsonb_build_object('id',id,'revision',link_revision)) into ids from public.legacy_payslips where source_sheet=sh and source_row=4;
 begin
  perform public.review_legacy_identity(ids,emp,null,'Unnamed');raise exception 'FAIL unnamed group';
 exception when raise_exception then if sqlerrm<>'Unnamed slip requires individual review' then raise;end if;end;
 select jsonb_agg(jsonb_build_object('id',id,'revision',0)) into ids from public.legacy_payslips where source_sheet=sh and source_row=1;
 begin
  perform public.review_legacy_identity(ids,emp,null,'Synthetic repeat');raise exception 'FAIL stale';
 exception when raise_exception then if sqlerrm not like 'STALE_LEGACY_LINK:%' then raise;end if;end;
 a:=public.save_legacy_staff_review(emp,'Test','daily','2001-01-01',null,330,50,'2001-01-01','Synthetic evidence');
 b:=public.save_legacy_staff_review(emp,'Test','daily','2001-01-01',null,360,70,'2001-01-02','Synthetic correction',a);
 if not exists(select 1 from public.legacy_staff_reviews where id=b and supersedes=a and base_rate=360) or not exists(select 1 from public.legacy_staff_reviews where id=a and base_rate=330) then raise exception 'FAIL history';end if;
 begin
  perform public.save_legacy_staff_review(emp,'Test','daily',null,null,330,null,null,'Missing date');raise exception 'FAIL rate date';
 exception when check_violation then null;end;
 begin
  perform public.save_legacy_staff_review(emp,'Test','daily',null,null,null,null,null,'Stale',a);raise exception 'FAIL stale correction';
 exception when raise_exception then if sqlerrm not like 'STALE_LEGACY_REVIEW:%' then raise;end if;end;
 if exists(select 1 from public.employment_records where employee_id=emp) then raise exception 'FAIL live employment changed';end if;
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.manager'),true);
 if exists(select 1 from public.legacy_staff_reviews) then raise exception 'FAIL manager read';end if;
 begin
  perform public.review_legacy_identity(ids,emp,null,'Denied');raise exception 'FAIL manager link';
 exception when insufficient_privilege then null;end;
 begin
  perform public.save_legacy_staff_review(emp,'Test',null,null,null,null,null,null,'Denied');raise exception 'FAIL manager write';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
select 'PASS: reviewed identity bulk link, audit, historical evidence and access' as result;
rollback;
