-- RC1 structural preflight. SELECT only; run after all migrations. No personal rows returned.
with expected(name) as (values
 ('user_profiles'),('departments'),('employees'),('employment_records'),('wage_rules'),('compensation_history'),('shift_templates'),('company_settings'),('audit_logs'),
 ('pay_periods'),('shift_schedules'),('shift_assignments'),('attendance_records'),('attendance_revisions'),('cash_advances'),('cash_advance_revisions'),
 ('payroll_drafts'),('payroll_draft_revisions'),('payroll_closures'),('payroll_final'),('payroll_advance_allocations'),
 ('legacy_import_batches'),('legacy_payslips'),('legacy_identity_links'),('legacy_staff_reviews'),('payroll_correction_requests'),('payroll_adjustments')
), inspected as (
 select e.name,c.oid,c.relrowsecurity from expected e left join pg_class c on c.oid=to_regclass('public.'||e.name)
)
select 'business tables expected' as check_name,count(*)::text as result from inspected
union all select 'missing tables',coalesce(string_agg(name,', '),'NONE') from inspected where oid is null
union all select 'RLS disabled',coalesce(string_agg(name,', '),'NONE') from inspected where oid is not null and not relrowsecurity
union all select 'anon table grants',coalesce(string_agg(name,', '),'NONE') from inspected where oid is not null and has_table_privilege('anon',oid,'SELECT,INSERT,UPDATE,DELETE')
union all select 'direct staff financial writes',coalesce(string_agg(name,', '),'NONE') from inspected where oid is not null and name in ('attendance_records','cash_advances','payroll_drafts','payroll_draft_revisions','payroll_closures','payroll_final','payroll_advance_allocations','legacy_payslips','legacy_staff_reviews','payroll_correction_requests','payroll_adjustments') and has_table_privilege('authenticated',oid,'INSERT,UPDATE,DELETE');
-- Catalog check of publicly callable security-definer functions in the business schema.
select p.proname as publicly_executable_security_definer
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.prosecdef and has_function_privilege('anon',p.oid,'EXECUTE')
order by p.proname;
-- Run this final SELECT only after structure passes. Counts only, no names.
select
 (select count(*) from public.user_profiles where role='owner' and active) as active_owners,
 (select count(*) from public.user_profiles where role='manager' and active) as active_managers,
 (select count(distinct employee_id) from public.employment_records where start_date<=(now() at time zone 'Asia/Bangkok')::date and coalesce(end_date,'infinity'::date)>=(now() at time zone 'Asia/Bangkok')::date) as current_employees,
 (select count(*) from public.legacy_payslips) as archived_slips,
 (select count(*) from public.legacy_payslips where employee_id is null) as unlinked_slips,
 (select count(*) from public.payroll_adjustments where status='approved') as pending_adjustments;
