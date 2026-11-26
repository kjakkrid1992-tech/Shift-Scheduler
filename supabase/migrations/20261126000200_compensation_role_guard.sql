-- Foundation follow-up: reject unauthorized wage changes before locking employment.
begin;
create or replace function staff_private.check_compensation() returns trigger
language plpgsql set search_path = '' as $$
declare e public.employment_records%rowtype; last_date date;
begin
  if staff_private.staff_role() is distinct from 'owner' then
    raise exception using errcode = '42501', message = 'Only an active owner can add compensation rates';
  end if;
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
commit;
