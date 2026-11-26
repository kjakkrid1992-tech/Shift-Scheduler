
-- Run after migration on isolated test DB. All synthetic rows rolled back.
begin;
do $$
begin
  if (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('user_profiles','departments','employees','employment_records','wage_rules','compensation_history','shift_templates','company_settings','audit_logs') and c.relrowsecurity) <> 9 then
    raise exception 'Expected all 9 tables to enable RLS';
  end if;
  if has_table_privilege('anon','public.employees','SELECT') then raise exception 'Anon can read employees'; end if;
  if has_table_privilege('authenticated','public.employees','DELETE') then raise exception 'Browser can delete employees'; end if;
  if has_column_privilege('authenticated','public.compensation_history','base_rate','UPDATE') then raise exception 'Rate is mutable'; end if;
  if has_column_privilege('authenticated','public.user_profiles','role','UPDATE') then raise exception 'Privilege escalation'; end if;
end $$;
-- Unknown authenticated user cannot see records, nor create employees.
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000099',true);
do $$
begin
  if exists(select 1 from public.departments) then raise exception 'Unregistered user sees departments'; end if;
  begin
    insert into public.employees(employee_code,first_name) values ('EMP-TEST-DENY','Synthetic');
    raise exception 'Unregistered user insert succeeded';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
rollback;
-- Owner/manager positive and negative tests require real test Auth users.
-- Use the manual checklist in docs/PHASE1_SETUP.md; not executed by this script.
