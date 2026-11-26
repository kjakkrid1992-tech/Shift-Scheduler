-- Phase 6B: reviewed identity and historical employment evidence, not live payroll.
begin;
create table public.legacy_staff_reviews (
 id uuid primary key default gen_random_uuid(),
 employee_id uuid not null references public.employees(id) on delete restrict,
 source_note text not null check(length(btrim(source_note)) between 1 and 1000),
 position text not null default '' check(length(position)<=200),
 employment_type text check(employment_type in ('monthly','daily','hourly')),
 start_date date,
 end_date date,
 base_rate numeric(12,2) check(base_rate>=0),
 ot_rate numeric(12,2) check(ot_rate>=0),
 rate_from date,
 reviewed_by uuid not null references public.user_profiles(user_id),
 reviewed_at timestamptz not null default now(),
 supersedes uuid unique references public.legacy_staff_reviews(id),
 check(start_date is null or end_date is null or end_date>=start_date),
 check((base_rate is null and ot_rate is null and rate_from is null) or
 ((base_rate is not null or ot_rate is not null) and rate_from is not null and employment_type is not null)),
 check(rate_from is null or ((start_date is null or rate_from>=start_date) and (end_date is null or rate_from<=end_date)))
);
alter table public.legacy_staff_reviews enable row level security;
revoke all on table public.legacy_staff_reviews from public,anon,authenticated;
grant select on table public.legacy_staff_reviews to authenticated;
create policy owner_read on public.legacy_staff_reviews for select to authenticated using ((select staff_private.staff_role())='owner');
-- Atomic explicit selection: never infer identity from a name or link an already linked slip.
-- New master identity is deliberately created with no live employment.
create function public.review_legacy_identity(p_slips jsonb,p_employee uuid,p_new jsonb,p_reason text)
returns uuid language plpgsql security definer set search_path='' as $$
declare item jsonb; rec public.legacy_payslips%rowtype; chosen uuid; code text; first_name_text text; last_name_text text;
begin
 if coalesce(staff_private.staff_role(),'')<>'owner' then raise exception using errcode='42501',message='Only owner can review legacy staff';end if;
 if jsonb_typeof(p_slips) is distinct from 'array' or p_reason is null or length(btrim(p_reason)) not between 1 and 1000 then raise exception 'Invalid review selection or evidence';end if;
 if jsonb_array_length(p_slips) not between 1 and 300 then raise exception 'Select 1–300 reviewed slips';end if;
 if (p_employee is null)=(p_new is null) then raise exception 'Choose existing employee or new identity';end if;
 if (select count(distinct x->>'id') from jsonb_array_elements(p_slips) x)<>jsonb_array_length(p_slips) then raise exception 'Duplicate slip selection';end if;
 -- Match payroll lock order (employees before legacy rows).
 if p_employee is not null then
  select id into chosen from public.employees where id=p_employee for update;
  if not found then raise exception 'Employee not found';end if;
 else
  if jsonb_typeof(p_new) is distinct from 'object' or (select count(*) from jsonb_object_keys(p_new))<>3 then raise exception 'Invalid new identity';end if;
  code:=upper(btrim(p_new->>'code'));first_name_text:=btrim(p_new->>'first');last_name_text:=btrim(p_new->>'last');
  if code is null or code !~ '^[A-Z0-9][A-Z0-9_-]{0,29}$' or first_name_text is null or length(first_name_text) not between 1 and 200 or last_name_text is null or length(last_name_text)>200 then raise exception 'Invalid employee code or name';end if;
  lock table public.employees in share row exclusive mode;
  if exists(select 1 from public.employees e where lower(regexp_replace(btrim(e.first_name||' '||e.last_name),'[[:space:]]+',' ','g'))=lower(regexp_replace(btrim(first_name_text||' '||last_name_text),'[[:space:]]+',' ','g'))) then raise exception 'Possible duplicate employee name; review existing master';end if;
  insert into public.employees(employee_code,first_name,last_name) values(code,first_name_text,last_name_text) returning id into chosen;
 end if;
 for item in select value from jsonb_array_elements(p_slips) order by value->>'id' loop
  if jsonb_typeof(item) is distinct from 'object' or jsonb_typeof(item->'revision') is distinct from 'number' or (item->>'revision') !~ '^[0-9]+$' then raise exception 'Invalid slip revision';end if;
  select * into rec from public.legacy_payslips where id=(item->>'id')::uuid for update;
  if not found or rec.link_revision is distinct from (item->>'revision')::integer or rec.employee_id is not null then raise exception 'STALE_LEGACY_LINK: reload unlinked slips';end if;
  -- Group action excludes unnamed documents. Individual review remains available in 6A.
  if length(btrim(rec.source_record->>'source_name'))=0 then raise exception 'Unnamed slip requires individual review';end if;
  perform public.link_legacy_identity(rec.id,rec.link_revision,chosen,p_reason);
 end loop;
 return chosen;
end $$;
create function public.save_legacy_staff_review(p_employee uuid,p_position text,p_type text,p_start date,p_end date,p_base numeric,p_ot numeric,p_rate_from date,p_note text,p_supersedes uuid default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare new_id uuid; prior public.legacy_staff_reviews%rowtype;
begin
 if coalesce(staff_private.staff_role(),'')<>'owner' then raise exception using errcode='42501',message='Only owner can review legacy employment';end if;
 if p_note is null or length(btrim(p_note)) not between 1 and 1000 or p_position is null or length(p_position)>200 then raise exception 'Review evidence required';end if;
 if p_type is not null and p_type not in ('monthly','daily','hourly') then raise exception 'Invalid employment type';end if;
 if p_start is null and p_end is null and btrim(p_position)='' and p_type is null and p_base is null and p_ot is null then raise exception 'Enter at least one verified fact';end if;
 if greatest(p_start,p_end,p_rate_from)>(now() at time zone 'Asia/Bangkok')::date then raise exception 'Historical dates cannot be future';end if;
 if (p_base is not null and (p_base<0 or p_base>9999999999.99 or p_base<>round(p_base,2))) or (p_ot is not null and (p_ot<0 or p_ot>9999999999.99 or p_ot<>round(p_ot,2))) then raise exception 'Invalid rate precision';end if;
 perform 1 from public.employees where id=p_employee for update;
 if not found then raise exception 'Employee not found';end if;
 if p_supersedes is not null then
  select * into prior from public.legacy_staff_reviews where id=p_supersedes and employee_id=p_employee;
  if not found or exists(select 1 from public.legacy_staff_reviews where supersedes=p_supersedes) then raise exception 'STALE_LEGACY_REVIEW: reload';end if;
 end if;
 insert into public.legacy_staff_reviews(employee_id,source_note,position,employment_type,start_date,end_date,base_rate,ot_rate,rate_from,reviewed_by,supersedes)
 values(p_employee,btrim(p_note),btrim(p_position),p_type,p_start,p_end,p_base,p_ot,p_rate_from,auth.uid(),p_supersedes) returning id into new_id;
 return new_id;
end $$;
revoke all on function public.review_legacy_identity(jsonb,uuid,jsonb,text) from public,anon,authenticated;
revoke all on function public.save_legacy_staff_review(uuid,text,text,date,date,numeric,numeric,date,text,uuid) from public,anon,authenticated;
grant execute on function public.review_legacy_identity(jsonb,uuid,jsonb,text) to authenticated;
grant execute on function public.save_legacy_staff_review(uuid,text,text,date,date,numeric,numeric,date,text,uuid) to authenticated;
commit;
