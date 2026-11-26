-- Run on the test project only, after the compensation role guard migration.
-- Requires active owner and manager profiles and synthetic EMP-TEST-001.
begin;
do $$
declare o uuid; m uuid;
begin
  select user_id into o from public.user_profiles where role='owner' and active order by user_id limit 1;
  select user_id into m from public.user_profiles where role='manager' and active order by user_id limit 1;
  if o is null or m is null then raise exception 'Missing active owner or manager'; end if;
  perform set_config('staff_test.owner',o::text,true);
  perform set_config('staff_test.manager',m::text,true);
end $$;
set local role authenticated;
do $$
declare job public.employment_records%rowtype; test_date date;
begin
  perform set_config('request.jwt.claim.sub',current_setting('staff_test.owner'),true);
  if staff_private.staff_role() is distinct from 'owner' then raise exception 'FAIL: owner role'; end if;
  select er.* into job from public.employment_records er
  join public.employees e on e.id=er.employee_id
  where e.employee_code='EMP-TEST-001' and er.end_date is null;
  if not found then raise exception 'Test employee not found'; end if;
  select greatest(job.start_date,coalesce(max(effective_from)+1,job.start_date))
    into test_date from public.compensation_history where employment_id=job.id;
  insert into public.compensation_history(employment_id,pay_type,base_rate,ot_rate,effective_from)
  values(job.id,job.employment_type,999,999,test_date);
  if not exists(select 1 from public.compensation_history where employment_id=job.id and effective_from=test_date and base_rate=999) then
    raise exception 'FAIL: owner insert not visible';
  end if;
  perform set_config('request.jwt.claim.sub',current_setting('staff_test.manager'),true);
  if staff_private.staff_role() is distinct from 'manager' then raise exception 'FAIL: manager role'; end if;
  if not exists(select 1 from public.employment_records where id=job.id) then raise exception 'FAIL: manager cannot read employment'; end if;
  begin
    insert into public.compensation_history(employment_id,pay_type,base_rate,ot_rate,effective_from)
    values(job.id,job.employment_type,999,999,test_date+1);
    raise exception 'FAIL: manager can add compensation';
  exception when insufficient_privilege then
    if sqlerrm <> 'Only an active owner can add compensation rates' then
      raise exception 'Unexpected denial: %',sqlerrm;
    end if;
  end;
end $$;
reset role;
select 'PASS: Owner can add rate; Manager cannot add rate' as result;
rollback;
