-- Run after 00800 on pilot; no permanent changes.
begin;
do $$
declare owner_id uuid; dept_id uuid;
begin
 select user_id into owner_id from public.user_profiles where role='owner' and active limit 1;
 select id into dept_id from public.departments where active limit 1;
 if owner_id is null or dept_id is null then raise exception 'Missing test prerequisites'; end if;
 perform set_config('staff_test.owner',owner_id::text,true);perform set_config('staff_test.dept',dept_id::text,true);
 if has_table_privilege('authenticated','public.payroll_drafts','UPDATE') then raise exception 'FAIL grants'; end if;
end $$;
set local role authenticated;
do $$
declare emp_key uuid; job_key uuid; key_id uuid; src jsonb; vals jsonb; k jsonb;
begin
 perform set_config('request.jwt.claim.sub',current_setting('staff_test.owner'),true);
 emp_key:=public.create_staff('EMP-PAY-ITEMS-SQL','Synthetic','Items','','',current_setting('staff_test.dept')::uuid,'Test','daily','2003-01-26','active');
 select id into job_key from public.employment_records where employee_id=emp_key;
 src:=public.preview_payroll(job_key,'2003-02-01');
 vals:='{"base":800000,"ot":72000,"paid_leave":40000,"attendance_bonus":50000,"performance_bonus":0,"behavior_bonus":0,"other_income":0,"advance":0,"social_security":20000,"tax":1000,"other_deduction":0}'::jsonb;
 key_id:=public.save_payroll_items(job_key,'2003-02-01',0,src,vals,'Synthetic manual draft');
 if not exists(select 1 from public.payroll_drafts where id=key_id and net_satang=941000 and item_breakdown->'items'=vals and revision=1) then raise exception 'FAIL totals'; end if;
 if not exists(select 1 from public.payroll_draft_revisions where draft_id=key_id and revision=1 and snapshot->'item_breakdown'->'items'=vals) then raise exception 'FAIL history detail'; end if;
 begin
  perform public.save_payroll_items(job_key,'2003-02-01',1,src,vals-'tax','Synthetic');
  raise exception 'FAIL missing category';
 exception when raise_exception then if sqlerrm<>'Invalid payroll item set' then raise;end if;end;
 begin
  perform public.save_payroll_items(job_key,'2003-02-01',1,src,jsonb_set(vals,'{advance}','1'),'Synthetic');
  raise exception 'FAIL advance cap';
 exception when raise_exception then if sqlerrm<>'Advance deduction exceeds paid candidate total' then raise;end if;end;
 perform public.save_payroll_draft(job_key,'2003-02-01',1,src,100,0,0,0,0,'Legacy client');
 if not exists(select 1 from public.payroll_drafts where id=key_id and item_breakdown is null and revision=2) then raise exception 'FAIL legacy detail';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000099',true);
 begin
  perform public.save_payroll_items(job_key,'2003-02-01',2,src,vals,'Denied');
  raise exception 'FAIL access';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
-- Server subtotal independent fixture: full day plus combined shift, different effective rates, partial day.
do $$
declare k jsonb;
begin
 k:=staff_private.payroll_known_amounts('{"pay_type":"daily","days":[{"status":"approved","type":"work","rate_id":"00000000-0000-4000-8000-000000000001","base_rate":330,"ot_rate":50,"normal_minutes":480,"ot_minutes":90},{"status":"approved","type":"work","rate_id":"00000000-0000-4000-8000-000000000002","base_rate":360,"ot_rate":70,"normal_minutes":480,"ot_minutes":270},{"status":"approved","type":"work","rate_id":"00000000-0000-4000-8000-000000000002","base_rate":360,"ot_rate":70,"normal_minutes":240,"ot_minutes":0}]}'::jsonb);
 if (k->>'base')::bigint<>69000 or (k->>'ot')::bigint<>39000 or (k->>'base_manual_days')::integer<>1 then raise exception 'FAIL known subtotal';end if;
end $$;
select 'PASS: structured payroll items, known subtotals, history, legacy compatibility and access' as result;
rollback;
