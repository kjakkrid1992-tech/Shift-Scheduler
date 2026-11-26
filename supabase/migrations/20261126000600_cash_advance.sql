-- Phase 4 pilot: apply once after 00500. No existing records are changed.
begin;
create table public.cash_advances (
 id uuid primary key,
 employment_id uuid not null references public.employment_records(id) on delete restrict,
 department_id uuid not null references public.departments(id) on delete restrict,
 period_id uuid not null references public.pay_periods(id) on delete restrict,
 request_date date not null,
 amount_satang bigint not null check(amount_satang between 1 and 100000000),
 note text not null check(length(btrim(note)) between 1 and 1000),
 status text not null default 'draft' check(status in ('draft','approved','paid','cancelled','voided')),
 revision integer not null default 1 check(revision>0),
 created_by uuid not null references public.user_profiles(user_id),
 updated_by uuid not null references public.user_profiles(user_id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 approved_by uuid references public.user_profiles(user_id),
 approved_at timestamptz,
 paid_by uuid references public.user_profiles(user_id),
 paid_at timestamptz,
 paid_date date,
 payment_method text check(payment_method in ('cash','transfer')),
 payment_reference text check(length(payment_reference)<=300),
 closed_by uuid references public.user_profiles(user_id),
 closed_at timestamptz,
 close_reason text check(length(btrim(close_reason)) between 1 and 1000),
 check((approved_by is null)=(approved_at is null)),
 check(status not in ('approved','paid','voided') or approved_by is not null),
 check(status<>'draft' or approved_by is null),
 check((status in ('paid','voided'))=(paid_by is not null and paid_at is not null and paid_date is not null and payment_method is not null and payment_reference is not null)),
 check(paid_date is null or paid_date>=request_date),
 check((status in ('cancelled','voided'))=(closed_by is not null and closed_at is not null and close_reason is not null))
);
create index cash_advances_period_dept_idx on public.cash_advances(period_id,department_id,status);
create index cash_advances_employment_idx on public.cash_advances(employment_id,request_date);
create table public.cash_advance_revisions (
 id bigint generated always as identity primary key,
 advance_id uuid not null references public.cash_advances(id) on delete restrict,
 revision integer not null check(revision>0),
 action text not null check(action in ('create','edit','approve','pay','cancel','void')),
 actor_id uuid not null references public.user_profiles(user_id),
 reason text not null default '' check(length(reason)<=1000),
 snapshot jsonb not null check(jsonb_typeof(snapshot)='object'),
 created_at timestamptz not null default now(),
 unique(advance_id,revision)
);
do $$
declare tbl text;
begin
 foreach tbl in array array['cash_advances','cash_advance_revisions'] loop
  execute format('alter table public.%I enable row level security',tbl);
  execute format('revoke all on table public.%I from public,anon,authenticated',tbl);
  execute format('grant select on table public.%I to authenticated',tbl);
  execute format('create policy staff_read on public.%I for select to authenticated using ((select staff_private.staff_role()) in (''owner'',''manager''))',tbl);
 end loop;
end $$;
-- Advances do not depend on a schedule. The period follows the request date until actual payment.
create function staff_private.advance_period(p_date date)
returns uuid language plpgsql security definer set search_path='' as $$
declare first_day date; last_day date; period_key uuid;
begin
 if p_date is null or p_date<'1900-01-26' or p_date>'2199-12-25' then raise exception 'Invalid advance date'; end if;
 first_day:=(date_trunc('month',p_date::timestamp)+case when extract(day from p_date)>=26 then interval '0 month' else interval '-1 month' end+interval '25 days')::date;
 last_day:=(first_day+interval '1 month'-interval '1 day')::date;
 insert into public.pay_periods(start_date,end_date) values(first_day,last_day) on conflict(start_date) do nothing;
 select id into period_key from public.pay_periods where start_date=first_day;
 return period_key;
end $$;
revoke all on function staff_private.advance_period(date) from public,anon,authenticated;
-- The client supplies a stable UUID so retrying a request cannot create a second advance.
create function public.save_cash_advance(p_id uuid,p_employment uuid,p_date date,p_revision integer,p_amount_satang bigint,p_note text)
returns uuid language plpgsql security definer set search_path='' as $$
declare job public.employment_records%rowtype; rec public.cash_advances%rowtype; actor uuid:=auth.uid(); period_key uuid;
begin
 if coalesce(staff_private.staff_role(),'') not in ('owner','manager') then raise exception using errcode='42501',message='Staff access required'; end if;
 if p_id is null or p_employment is null or p_revision is null or p_revision<0 or p_amount_satang is null or p_amount_satang not between 1 and 100000000 or p_note is null or length(btrim(p_note)) not between 1 and 1000 then raise exception 'Invalid advance amount or note'; end if;
 if p_date is null or p_date>(now() at time zone 'Asia/Bangkok')::date then raise exception 'Invalid request date'; end if;
 select * into job from public.employment_records where id=p_employment for update;
 if not found or p_date<job.start_date or (job.end_date is not null and p_date>job.end_date) then raise exception 'Employment not eligible for advance date'; end if;
 select * into rec from public.cash_advances where id=p_id for update;
 if found then
  if rec.employment_id<>job.id or rec.request_date<>p_date then raise exception 'Advance identity cannot be changed'; end if;
  if p_revision=0 and rec.created_by=actor and rec.amount_satang=p_amount_satang and rec.note=btrim(p_note) then return rec.id; end if;
  if rec.revision is distinct from p_revision then raise exception 'STALE_ADVANCE: reload'; end if;
  if rec.status<>'draft' then raise exception 'Only draft can be edited'; end if;
  update public.cash_advances set amount_satang=p_amount_satang,note=btrim(p_note),revision=revision+1,updated_by=actor,updated_at=now() where id=p_id returning * into rec;
  insert into public.cash_advance_revisions(advance_id,revision,action,actor_id,snapshot) values(rec.id,rec.revision,'edit',actor,to_jsonb(rec));
 else
  if p_revision<>0 then raise exception 'STALE_ADVANCE: reload'; end if;
  period_key:=staff_private.advance_period(p_date);
  insert into public.cash_advances(id,employment_id,department_id,period_id,request_date,amount_satang,note,created_by,updated_by)
  values(p_id,job.id,job.department_id,period_key,p_date,p_amount_satang,btrim(p_note),actor,actor) returning * into rec;
  insert into public.cash_advance_revisions(advance_id,revision,action,actor_id,snapshot) values(rec.id,rec.revision,'create',actor,to_jsonb(rec));
 end if;
 return rec.id;
end $$;
create function public.transition_cash_advance(p_id uuid,p_revision integer,p_action text,p_paid_date date default null,p_method text default null,p_reference text default null,p_reason text default '')
returns integer language plpgsql security definer set search_path='' as $$
declare rec public.cash_advances%rowtype; job public.employment_records%rowtype; jid uuid; actor uuid:=auth.uid(); staffrole text:=staff_private.staff_role(); period_key uuid;
begin
 if coalesce(staffrole,'') not in ('owner','manager') then raise exception using errcode='42501',message='Staff access required'; end if;
 if p_action is null or p_action not in ('approve','pay','cancel','void') or p_reason is null or length(p_reason)>1000 then raise exception 'Invalid advance action'; end if;
 select employment_id into jid from public.cash_advances where id=p_id;
 if not found then raise exception 'Advance not found'; end if;
 select * into job from public.employment_records where id=jid for update;
 select * into rec from public.cash_advances where id=p_id for update;
 if not found then raise exception 'Advance not found'; end if;
 if rec.revision is distinct from p_revision then raise exception 'STALE_ADVANCE: reload'; end if;
 if p_action<>'pay' and (p_paid_date is not null or p_method is not null or p_reference is not null) then raise exception 'Payment fields only allowed for payment'; end if;
 if p_action='approve' and rec.status='draft' then
  if staffrole<>'owner' then raise exception using errcode='42501',message='Only owner can approve advance'; end if;
  if rec.request_date<job.start_date or (job.end_date is not null and rec.request_date>job.end_date) then raise exception 'Employment no longer eligible'; end if;
  update public.cash_advances set status='approved',approved_by=actor,approved_at=now(),revision=revision+1,updated_by=actor,updated_at=now() where id=p_id returning * into rec;
 elsif p_action='pay' and rec.status='approved' then
  if p_paid_date is null or p_paid_date<rec.request_date or p_paid_date>(now() at time zone 'Asia/Bangkok')::date or p_paid_date<job.start_date or (job.end_date is not null and p_paid_date>job.end_date) then raise exception 'Invalid payment date or employment'; end if;
  if p_method is null or p_method not in ('cash','transfer') or p_reference is null or length(btrim(p_reference))>300 or (p_method='transfer' and length(btrim(p_reference))=0) then raise exception 'Payment method or reference invalid'; end if;
  period_key:=staff_private.advance_period(p_paid_date);
  update public.cash_advances set status='paid',period_id=period_key,paid_date=p_paid_date,payment_method=p_method,payment_reference=btrim(p_reference),paid_by=actor,paid_at=now(),revision=revision+1,updated_by=actor,updated_at=now() where id=p_id returning * into rec;
 elsif p_action='cancel' and rec.status in ('draft','approved') then
  if rec.status='approved' and staffrole<>'owner' then raise exception using errcode='42501',message='Only owner can cancel approved advance'; end if;
  if length(btrim(p_reason))=0 then raise exception 'Cancellation reason required'; end if;
  update public.cash_advances set status='cancelled',closed_by=actor,closed_at=now(),close_reason=btrim(p_reason),revision=revision+1,updated_by=actor,updated_at=now() where id=p_id returning * into rec;
 elsif p_action='void' and rec.status='paid' then
  if staffrole<>'owner' then raise exception using errcode='42501',message='Only owner can void paid advance'; end if;
  if length(btrim(p_reason))=0 then raise exception 'Void reason required'; end if;
  -- Void only an erroneous payment record; actual repayments require a separate future ledger.
  update public.cash_advances set status='voided',closed_by=actor,closed_at=now(),close_reason=btrim(p_reason),revision=revision+1,updated_by=actor,updated_at=now() where id=p_id returning * into rec;
 else raise exception 'Invalid advance status transition'; end if;
 insert into public.cash_advance_revisions(advance_id,revision,action,actor_id,reason,snapshot) values(rec.id,rec.revision,p_action,actor,btrim(p_reason),to_jsonb(rec));
 return rec.revision;
end $$;
revoke all on function public.save_cash_advance(uuid,uuid,date,integer,bigint,text) from public,anon,authenticated;
revoke all on function public.transition_cash_advance(uuid,integer,text,date,text,text,text) from public,anon,authenticated;
grant execute on function public.save_cash_advance(uuid,uuid,date,integer,bigint,text) to authenticated;
grant execute on function public.transition_cash_advance(uuid,integer,text,date,text,text,text) to authenticated;
commit;
