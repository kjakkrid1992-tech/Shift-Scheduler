
-- Phase 1: apply once to a NEW dedicated Supabase project (postgres).
begin;
create extension if not exists btree_gist with schema extensions;
set local search_path = public, extensions, pg_catalog;
create schema if not exists staff_private;
revoke all on schema staff_private from public, anon, authenticated;
grant usage on schema staff_private to authenticated;

create table public.user_profiles (
  user_id uuid primary key references auth.users(id) on delete restrict,
  display_name text not null check(length(trim(display_name)) > 0),
  role text not null check(role in ('owner','manager')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create function staff_private.staff_role() returns text
language sql stable security definer set search_path = '' as $$
  select p.role from public.user_profiles p where p.user_id = auth.uid() and p.active
$$;
revoke all on function staff_private.staff_role() from public, anon, authenticated;
grant execute on function staff_private.staff_role() to authenticated;

create table public.departments (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check(length(trim(name)) > 0),
  active boolean not null default true
);
insert into public.departments(name) values ('ทั่วไป'),('หน้าร้าน'),('ที่พัก'),('บริหาร');
create table public.employees (
  id uuid primary key default gen_random_uuid(),
  employee_code text not null unique check(employee_code ~ '^[A-Z0-9][A-Z0-9_-]{0,29}$'),
  first_name text not null check(length(trim(first_name)) > 0),
  last_name text not null default '',
  nickname text not null default '',
  phone text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- No bank/account/ID-card data in this phase.
create table public.employment_records (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete restrict,
  department_id uuid not null references public.departments(id) on delete restrict,
  position text not null check(length(trim(position)) > 0),
  employment_type text not null check(employment_type in ('monthly','daily','hourly')),
  start_date date not null,
  probation_end_date date check(probation_end_date >= start_date),
  end_date date check(end_date >= start_date),
  status text not null default 'probation' check(status in ('probation','active','resigned','terminated')),
  created_at timestamptz not null default now(),
  check((status in ('resigned','terminated')) = (end_date is not null)),
  exclude using gist (employee_id with =, daterange(start_date,end_date,'[]') with &&)
);
create index employment_employee_idx on public.employment_records(employee_id);
create table public.wage_rules (
  id uuid primary key default gen_random_uuid(),
  position text not null, version integer not null check(version > 0),
  tenure_from_month integer not null check(tenure_from_month >= 0),
  tenure_to_month integer check(tenure_to_month > tenure_from_month),
  pay_type text not null check(pay_type in ('monthly','daily','hourly')),
  base_rate numeric(12,2) not null check(base_rate >= 0),
  ot_rate numeric(12,2) check(ot_rate >= 0),
  effective_from date not null, active boolean not null default false,
  unique(position,version,tenure_from_month)
);
-- No company wage rules are seeded until verified by owner.
create table public.compensation_history (
  id uuid primary key default gen_random_uuid(),
  employment_id uuid not null references public.employment_records(id) on delete restrict,
  pay_type text not null check(pay_type in ('monthly','daily','hourly')),
  base_rate numeric(12,2) not null check(base_rate >= 0),
  ot_rate numeric(12,2) not null check(ot_rate >= 0),
  effective_from date not null,
  wage_rule_id uuid references public.wage_rules(id) on delete restrict,
  approved_by uuid not null default auth.uid() references public.user_profiles(user_id) on delete restrict,
  created_at timestamptz not null default now(),
  unique(employment_id,effective_from)
);
-- effective_to is derived from next effective_from (exclusive), never overwritten.
create table public.shift_templates (
  id uuid primary key default gen_random_uuid(),
  name text not null unique, start_time time not null, end_time time not null,
  break_minutes integer not null check(break_minutes >= 0 and break_minutes < 1440),
  active boolean not null default true,
  check(start_time <> end_time),
  check(break_minutes < extract(epoch from
    (case when end_time > start_time then end_time-start_time else end_time-start_time+interval '1 day' end))/60)
);
insert into public.shift_templates(name,start_time,end_time,break_minutes)
values ('เช้า','06:30','15:30',60),('บ่าย','12:00','21:00',60);
create table public.company_settings (
  id uuid primary key default gen_random_uuid(),
  version integer not null unique check(version > 0),
  timezone text not null default 'Asia/Bangkok' check(timezone='Asia/Bangkok'),
  payroll_cutoff_day integer not null check(payroll_cutoff_day between 1 and 28),
  normal_minutes integer not null check(normal_minutes between 1 and 1440),
  effective_from date not null unique,
  approved boolean not null default false
);
-- Draft settings only, not a verified payroll policy.
insert into public.company_settings(version,payroll_cutoff_day,normal_minutes,effective_from)
values (1,25,480,'2026-11-26');

create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid,
  action text not null check(action in ('INSERT','UPDATE')),
  entity_type text not null,
  entity_id uuid not null,
  occurred_at timestamptz not null default now(),
  changed_fields text[] not null default '{}'
);
-- Log identifiers and field names, not private personal values. History rows carry prior rates.
create function staff_private.audit_change() returns trigger
language plpgsql security definer set search_path = '' as $$
declare keys text[]; row_id uuid;
begin
  row_id := coalesce((to_jsonb(new)->>'id')::uuid,(to_jsonb(new)->>'user_id')::uuid);
  if tg_op = 'UPDATE' then
    select coalesce(array_agg(k order by k),'{}'::text[]) into keys
    from jsonb_object_keys(to_jsonb(new)) as x(k)
    where to_jsonb(new)->k is distinct from to_jsonb(old)->k;
  else keys := '{}'; end if;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,changed_fields)
  values(auth.uid(),tg_op,tg_table_name,row_id,keys);
  return new;
end $$;
revoke all on function staff_private.audit_change() from public, anon, authenticated;

create function staff_private.touch_employee() returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at := now(); return new; end $$;
revoke all on function staff_private.touch_employee() from public, anon, authenticated;
create trigger employee_touch before update on public.employees for each row execute function staff_private.touch_employee();

create function staff_private.check_employment_change() returns trigger language plpgsql set search_path = '' as $$
begin
  if old.end_date is not null then raise exception 'Closed employment is immutable'; end if;
  if new.status not in ('active','resigned','terminated') or (new.status='active' and old.status <> 'probation') then
    raise exception 'Invalid employment status transition';
  end if;
  if new.end_date is not null and exists(select 1 from public.compensation_history c where c.employment_id=old.id and c.effective_from > new.end_date) then
    raise exception 'Future compensation exists after requested end date; contact administrator';
  end if;
  return new;
end $$;
revoke all on function staff_private.check_employment_change() from public, anon, authenticated;
create trigger employment_transition before update on public.employment_records for each row execute function staff_private.check_employment_change();

create function staff_private.check_compensation() returns trigger
language plpgsql set search_path = '' as $$
declare e public.employment_records%rowtype; last_date date;
begin
  -- Serialize wage changes and employment closure on the same parent row.
  select * into e from public.employment_records where id=new.employment_id for update;
  if not found or e.end_date is not null or new.effective_from < e.start_date or new.pay_type <> e.employment_type then
    raise exception 'Invalid employment, pay type or effective date';
  end if;
  select max(effective_from) into last_date from public.compensation_history where employment_id=new.employment_id;
  if last_date is not null and new.effective_from <= last_date then
    raise exception 'New rate must be later than the latest rate';
  end if;
  if new.approved_by is distinct from auth.uid() then raise exception 'Approver must be current user'; end if;
  return new;
end $$;
revoke all on function staff_private.check_compensation() from public, anon, authenticated;
create trigger compensation_validate before insert on public.compensation_history for each row execute function staff_private.check_compensation();

do $$
declare t text;
begin
  foreach t in array array['user_profiles','departments','employees','employment_records','wage_rules','compensation_history','shift_templates','company_settings','audit_logs'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on table public.%I from public, anon, authenticated',t);
    execute format('grant select on table public.%I to authenticated',t);
  end loop;
  foreach t in array array['user_profiles','departments','employees','employment_records','wage_rules','compensation_history','shift_templates','company_settings'] loop
    execute format('create trigger %I after insert or update on public.%I for each row execute function staff_private.audit_change()', 'audit_'||t,t);
  end loop;
  foreach t in array array['departments','employees','employment_records','wage_rules','compensation_history','shift_templates','company_settings'] loop
    execute format('create policy staff_read on public.%I for select to authenticated using ((select staff_private.staff_role()) in (''owner'',''manager''))',t);
  end loop;
end $$;
create policy profile_self on public.user_profiles for select to authenticated using(user_id=(select auth.uid()) and active);
create policy owner_audit on public.audit_logs for select to authenticated using((select staff_private.staff_role())='owner');

grant insert(employee_code,first_name,last_name,nickname,phone) on public.employees to authenticated;
grant update(first_name,last_name,nickname,phone) on public.employees to authenticated;
create policy staff_employee_insert on public.employees for insert to authenticated with check((select staff_private.staff_role()) in ('owner','manager'));
create policy staff_employee_update on public.employees for update to authenticated using((select staff_private.staff_role()) in ('owner','manager')) with check((select staff_private.staff_role()) in ('owner','manager'));

grant insert(employee_id,department_id,position,employment_type,start_date,probation_end_date,status) on public.employment_records to authenticated;
grant update(status,end_date) on public.employment_records to authenticated;
create policy staff_employment_insert on public.employment_records for insert to authenticated with check((select staff_private.staff_role()) in ('owner','manager') and status in ('probation','active') and end_date is null);
create policy owner_employment_update on public.employment_records for update to authenticated using((select staff_private.staff_role())='owner') with check((select staff_private.staff_role())='owner');
grant insert(employment_id,pay_type,base_rate,ot_rate,effective_from) on public.compensation_history to authenticated;
create policy owner_rate_insert on public.compensation_history for insert to authenticated with check((select staff_private.staff_role())='owner' and approved_by=(select auth.uid()));

-- Atomic employee + employment creation; executes as caller and respects RLS.
create function public.create_staff(p_code text,p_first text,p_last text,p_nickname text,p_phone text,p_department uuid,p_position text,p_pay_type text,p_start date,p_status text)
returns uuid language plpgsql security invoker set search_path = '' as $$
declare new_id uuid;
begin
  insert into public.employees(employee_code,first_name,last_name,nickname,phone)
  values(upper(trim(p_code)),trim(p_first),trim(p_last),trim(p_nickname),trim(p_phone)) returning id into new_id;
  insert into public.employment_records(employee_id,department_id,position,employment_type,start_date,status)
  values(new_id,p_department,trim(p_position),p_pay_type,p_start,p_status);
  return new_id;
end $$;
revoke all on function public.create_staff(text,text,text,text,text,uuid,text,text,date,text) from public, anon, authenticated;
grant execute on function public.create_staff(text,text,text,text,text,uuid,text,text,date,text) to authenticated;
commit;
