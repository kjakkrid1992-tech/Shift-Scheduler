-- Phase 6A: historical archive only; no live payroll mutations.
begin;
create table public.legacy_import_batches(
 id uuid primary key default gen_random_uuid(),
 source_sha256 text not null check(source_sha256 ~ '^[a-f0-9]{64}$'),
 imported_by uuid not null references public.user_profiles(user_id),
 imported_at timestamptz not null default now(),
 selected_count integer not null check(selected_count between 1 and 300),
 inserted_count integer not null default 0 check(inserted_count between 0 and selected_count)
);
create table public.legacy_payslips(
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.legacy_import_batches(id),
 source_sheet text not null check(length(source_sheet) between 1 and 100),
 source_row integer not null check(source_row between 1 and 1048576),
 content_fingerprint text not null unique,
 source_record jsonb not null,
 income_satang bigint not null,
 deduction_satang bigint not null,
 net_satang bigint not null check(net_satang=income_satang-deduction_satang),
 employee_id uuid references public.employees(id) on delete restrict,
 link_revision integer not null default 0,
 unique(source_sheet,source_row)
);
create table public.legacy_identity_links(
 id bigint generated always as identity primary key,
 slip_id uuid not null references public.legacy_payslips(id),
 revision integer not null,
 previous_employee_id uuid references public.employees(id) on delete restrict,
 employee_id uuid references public.employees(id) on delete restrict,
 actor_id uuid not null references public.user_profiles(user_id),
 reason text not null check(length(btrim(reason)) between 1 and 1000),
 created_at timestamptz not null default now(),
 unique(slip_id,revision)
);
do $$
declare tbl text;
begin
 foreach tbl in array array['legacy_import_batches','legacy_payslips','legacy_identity_links'] loop
  execute format('alter table public.%I enable row level security',tbl);
  execute format('revoke all on table public.%I from public,anon,authenticated',tbl);
  execute format('grant select on table public.%I to authenticated',tbl);
  execute format('create policy owner_read on public.%I for select to authenticated using ((select staff_private.staff_role()) = ''owner'')',tbl);
 end loop;
end $$;
create function staff_private.validate_legacy_record(r jsonb) returns text
language plpgsql immutable set search_path='' as $$
declare l jsonb; k text; income bigint:=0; deductions bigint:=0; a bigint;
begin
 if jsonb_typeof(r) is distinct from 'object' or (select count(*) from jsonb_object_keys(r))<>10 then raise exception 'Invalid legacy record fields';end if;
 foreach k in array array['sheet','period_label','recorded_date','source_name','position'] loop
  if jsonb_typeof(r->k) is distinct from 'string' or length(r->>k)>500 then raise exception 'Invalid legacy text field: %',k;end if;
 end loop;
 if length(btrim(r->>'sheet')) not between 1 and 100 or length(btrim(r->>'period_label'))=0 then raise exception 'Source sheet and period label required';end if;
 if jsonb_typeof(r->'row') is distinct from 'number' or (r->>'row') !~ '^[0-9]+$' or (r->>'row')::numeric not between 1 and 1048576 then raise exception 'Invalid source row';end if;
 foreach k in array array['income_satang','deduction_satang','net_satang'] loop
  if jsonb_typeof(r->k) is distinct from 'number' or (r->>k) !~ '^-?[0-9]+$' or abs((r->>k)::numeric)>1000000000 then raise exception 'Invalid legacy total: %',k;end if;
 end loop;
 if jsonb_typeof(r->'lines') is distinct from 'array' or jsonb_array_length(r->'lines')>60 then raise exception 'Invalid legacy lines';end if;
 for l in select value from jsonb_array_elements(r->'lines') loop
  if jsonb_typeof(l) is distinct from 'object' or (select count(*) from jsonb_object_keys(l))<>3 or jsonb_typeof(l->'label') is distinct from 'string' or length(btrim(l->>'label')) not between 1 and 500 or coalesce(l->>'side','') not in ('income','deduction') or jsonb_typeof(l->'amount_satang') is distinct from 'number' or (l->>'amount_satang') !~ '^-?[0-9]+$' or abs((l->>'amount_satang')::numeric)>1000000000 then raise exception 'Invalid legacy line';end if;
  a:=(l->>'amount_satang')::bigint;
  if l->>'side'='income' then income:=income+a;else deductions:=deductions+a;end if;
 end loop;
 if income<>(r->>'income_satang')::bigint or deductions<>(r->>'deduction_satang')::bigint or income-deductions<>(r->>'net_satang')::bigint then raise exception 'Legacy totals do not reconcile';end if;
 return md5((r-'sheet'-'row')::text);
end $$;
revoke all on function staff_private.validate_legacy_record(jsonb) from public,anon,authenticated;
create function public.import_legacy_payroll(p_sha text,p_records jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare batch uuid; r jsonb; fp text; existing public.legacy_payslips%rowtype; added integer:=0; skipped integer:=0;
begin
 if coalesce(staff_private.staff_role(),'')<>'owner' then raise exception using errcode='42501',message='Only owner can import legacy payroll';end if;
 if p_sha is null or p_sha !~ '^[a-f0-9]{64}$' or jsonb_typeof(p_records) is distinct from 'array' then raise exception 'Invalid import format';end if;
 if jsonb_array_length(p_records) not between 1 and 300 or octet_length(p_records::text)>1500000 then raise exception 'Import batch too large or empty';end if;
 lock table public.legacy_payslips in share row exclusive mode;
 insert into public.legacy_import_batches(source_sha256,imported_by,selected_count) values(p_sha,auth.uid(),jsonb_array_length(p_records)) returning id into batch;
 for r in select value from jsonb_array_elements(p_records) loop
  fp:=staff_private.validate_legacy_record(r);
  select * into existing from public.legacy_payslips where source_sheet=r->>'sheet' and source_row=(r->>'row')::integer;
  if found then
   if existing.source_record is distinct from r then raise exception 'SOURCE_CONFLICT: changed document at existing source location';end if;
   skipped:=skipped+1;continue;
  end if;
  if exists(select 1 from public.legacy_payslips where content_fingerprint=fp) then raise exception 'POSSIBLE_DUPLICATE: identical content at another source location';end if;
  insert into public.legacy_payslips(batch_id,source_sheet,source_row,content_fingerprint,source_record,income_satang,deduction_satang,net_satang)
   values(batch,r->>'sheet',(r->>'row')::integer,fp,r,(r->>'income_satang')::bigint,(r->>'deduction_satang')::bigint,(r->>'net_satang')::bigint);
  added:=added+1;
 end loop;
 update public.legacy_import_batches set inserted_count=added where id=batch;
 return jsonb_build_object('batch_id',batch,'inserted',added,'skipped',skipped);
end $$;
create function public.link_legacy_identity(p_id uuid,p_revision integer,p_employee uuid,p_reason text) returns integer
language plpgsql security definer set search_path='' as $$
declare rec public.legacy_payslips%rowtype;
begin
 if coalesce(staff_private.staff_role(),'')<>'owner' then raise exception using errcode='42501',message='Only owner can link legacy identity';end if;
 if p_reason is null or length(btrim(p_reason)) not between 1 and 1000 then raise exception 'Identity review reason required';end if;
 select * into rec from public.legacy_payslips where id=p_id for update;
 if not found or rec.link_revision is distinct from p_revision then raise exception 'STALE_LEGACY_LINK: reload';end if;
 if p_employee is not null and not exists(select 1 from public.employees where id=p_employee) then raise exception 'Employee not found';end if;
 if rec.employee_id is not distinct from p_employee then raise exception 'Identity unchanged';end if;
 update public.legacy_payslips set employee_id=p_employee,link_revision=link_revision+1 where id=p_id;
 insert into public.legacy_identity_links(slip_id,revision,previous_employee_id,employee_id,actor_id,reason) values(p_id,rec.link_revision+1,rec.employee_id,p_employee,auth.uid(),btrim(p_reason));
 return rec.link_revision+1;
end $$;
revoke all on function public.import_legacy_payroll(text,jsonb) from public,anon,authenticated;
revoke all on function public.link_legacy_identity(uuid,integer,uuid,text) from public,anon,authenticated;
grant execute on function public.import_legacy_payroll(text,jsonb) to authenticated;
grant execute on function public.link_legacy_identity(uuid,integer,uuid,text) to authenticated;
commit;
