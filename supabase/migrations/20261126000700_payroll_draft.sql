-- Phase 5A: review-only payroll, pending verified company policies.
begin;
create table public.payroll_drafts (
 id uuid primary key default gen_random_uuid(),
 employment_id uuid not null references public.employment_records(id) on delete restrict,
 period_start date not null references public.pay_periods(start_date) on delete restrict,
 revision integer not null default 1 check(revision>0),
 source_snapshot jsonb not null check(jsonb_typeof(source_snapshot)='object'),
 base_satang bigint not null check(base_satang between 0 and 1000000000),
 ot_satang bigint not null check(ot_satang between 0 and 1000000000),
 other_income_satang bigint not null check(other_income_satang between 0 and 1000000000),
 advance_deduction_satang bigint not null check(advance_deduction_satang between 0 and 1000000000),
 other_deduction_satang bigint not null check(other_deduction_satang between 0 and 1000000000),
 net_satang bigint generated always as (base_satang+ot_satang+other_income_satang-advance_deduction_satang-other_deduction_satang) stored,
 review_note text not null check(length(btrim(review_note)) between 1 and 2000),
 updated_by uuid not null references public.user_profiles(user_id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(employment_id,period_start)
);
create table public.payroll_draft_revisions (
 id bigint generated always as identity primary key,
 draft_id uuid not null references public.payroll_drafts(id) on delete restrict,
 revision integer not null check(revision>0),
 actor_id uuid not null references public.user_profiles(user_id),
 snapshot jsonb not null check(jsonb_typeof(snapshot)='object'),
 created_at timestamptz not null default now(),
 unique(draft_id,revision)
);
do $$
declare tbl text;
begin
 foreach tbl in array array['payroll_drafts','payroll_draft_revisions'] loop
  execute format('alter table public.%I enable row level security',tbl);
  execute format('revoke all on table public.%I from public,anon,authenticated',tbl);
  execute format('grant select on table public.%I to authenticated',tbl);
  execute format('create policy staff_read on public.%I for select to authenticated using ((select staff_private.staff_role()) in (''owner'',''manager''))',tbl);
 end loop;
end $$;
-- Preview is read-only, uses each work date's effective rate, and never marks sources deducted.
create function public.preview_payroll(p_employment uuid,p_month date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare first_day date; last_day date; cutoff date; job public.employment_records%rowtype; emp public.employees%rowtype;
 days jsonb; advances jsonb; paid_total bigint; dept_name text;
begin
 if coalesce(staff_private.staff_role(),'') not in ('owner','manager') then raise exception using errcode='42501',message='Staff access required'; end if;
 if p_month is null or extract(day from p_month)<>1 or p_month<'1900-02-01' or p_month>'2199-12-01' then raise exception 'Invalid payroll month'; end if;
 first_day:=(p_month-interval '1 month'+interval '25 days')::date;
 last_day:=p_month+24;
 cutoff:=least(last_day,(now() at time zone 'Asia/Bangkok')::date);
 select * into job from public.employment_records where id=p_employment;
 if not found or job.start_date>last_day or (job.end_date is not null and job.end_date<first_day) then raise exception 'Employment not in payroll period'; end if;
 select * into emp from public.employees where id=job.employee_id;
 select name into dept_name from public.departments where id=job.department_id;
 -- Include every elapsed eligible date, even with no attendance; missing is not zero pay.
 select coalesce(jsonb_agg(jsonb_build_object(
  'date',g.d::date,'attendance_id',ar.id,'attendance_revision',ar.revision,'status',ar.status,
  'type',ar.attendance_type,'work_minutes',ar.work_minutes,'normal_minutes',ar.normal_minutes,'ot_minutes',ar.ot_minutes,
  'rate_id',rate_at.id,'base_rate',rate_at.base_rate,'ot_rate',rate_at.ot_rate,'rate_from',rate_at.effective_from
 ) order by g.d),'[]'::jsonb) into days
 from generate_series(greatest(first_day,job.start_date)::timestamp,least(cutoff,coalesce(job.end_date,last_day))::timestamp,interval '1 day') g(d)
 left join public.attendance_records ar on ar.employment_id=job.id and ar.work_date=g.d::date
 left join lateral (select cr.id,cr.base_rate,cr.ot_rate,cr.effective_from from public.compensation_history cr
  where cr.employment_id=job.id and cr.effective_from<=g.d::date and cr.pay_type=job.employment_type
  order by cr.effective_from desc limit 1) rate_at on true;
 select coalesce(jsonb_agg(jsonb_build_object('id',ca.id,'revision',ca.revision,'date',ca.paid_date,'amount_satang',ca.amount_satang) order by ca.paid_date,ca.id),'[]'::jsonb),
  coalesce(sum(ca.amount_satang),0)::bigint into advances,paid_total
 from public.cash_advances ca join public.pay_periods pp on pp.id=ca.period_id
 where ca.employment_id=job.id and pp.start_date=first_day and ca.status='paid';
 return jsonb_build_object('employment_id',job.id,'employee_code',emp.employee_code,'employee_name',btrim(emp.first_name||' '||emp.last_name),'department',dept_name,'position',job.position,'pay_type',job.employment_type,
 'period_start',first_day,'period_end',last_day,'as_of',cutoff,'days',days,'paid_advances',advances,'paid_advance_satang',paid_total,'policy','UNVERIFIED_DRAFT_ONLY');
end $$;
-- No finalization, payment, official payslip or source lock exists in this migration.
create function public.save_payroll_draft(p_employment uuid,p_month date,p_revision integer,p_source jsonb,
 p_base bigint,p_ot bigint,p_other_income bigint,p_advance bigint,p_other_deduction bigint,p_note text)
returns uuid language plpgsql security definer set search_path='' as $$
declare job public.employment_records%rowtype; rec public.payroll_drafts%rowtype; source_now jsonb; start_day date; actor uuid:=auth.uid();
begin
 if coalesce(staff_private.staff_role(),'') not in ('owner','manager') then raise exception using errcode='42501',message='Staff access required'; end if;
 if p_revision is null or p_revision<0 or p_source is null or p_note is null or length(btrim(p_note)) not between 1 and 2000 then raise exception 'Review note and source required'; end if;
 if exists(select 1 from unnest(array[p_base,p_ot,p_other_income,p_advance,p_other_deduction]) x(v) where v is null or v not between 0 and 1000000000) then raise exception 'Invalid draft amounts'; end if;
 -- Serialize with current attendance, rate and advance writes for this employment.
 select * into job from public.employment_records where id=p_employment for update;
 if not found then raise exception 'Employment not found'; end if;
 source_now:=public.preview_payroll(job.id,p_month);
 if source_now is distinct from p_source then raise exception 'STALE_PAYROLL_SOURCE: reload and review'; end if;
 if p_advance>(source_now->>'paid_advance_satang')::bigint then raise exception 'Advance deduction exceeds paid candidate total'; end if;
 start_day:=(source_now->>'period_start')::date;
 select * into rec from public.payroll_drafts where employment_id=job.id and period_start=start_day for update;
 if found then
  if rec.revision is distinct from p_revision then raise exception 'STALE_PAYROLL_DRAFT: reload and review'; end if;
  update public.payroll_drafts set source_snapshot=source_now,base_satang=p_base,ot_satang=p_ot,other_income_satang=p_other_income,
   advance_deduction_satang=p_advance,other_deduction_satang=p_other_deduction,review_note=btrim(p_note),
   revision=revision+1,updated_by=actor,updated_at=now() where id=rec.id returning * into rec;
 else
  if p_revision<>0 then raise exception 'STALE_PAYROLL_DRAFT: reload and review'; end if;
  perform staff_private.advance_period(start_day);
  insert into public.payroll_drafts(employment_id,period_start,source_snapshot,base_satang,ot_satang,other_income_satang,advance_deduction_satang,other_deduction_satang,review_note,updated_by)
   values(job.id,start_day,source_now,p_base,p_ot,p_other_income,p_advance,p_other_deduction,btrim(p_note),actor) returning * into rec;
 end if;
 insert into public.payroll_draft_revisions(draft_id,revision,actor_id,snapshot) values(rec.id,rec.revision,actor,to_jsonb(rec));
 return rec.id;
end $$;
revoke all on function public.preview_payroll(uuid,date) from public,anon,authenticated;
revoke all on function public.save_payroll_draft(uuid,date,integer,jsonb,bigint,bigint,bigint,bigint,bigint,text) from public,anon,authenticated;
grant execute on function public.preview_payroll(uuid,date) to authenticated;
grant execute on function public.save_payroll_draft(uuid,date,integer,jsonb,bigint,bigint,bigint,bigint,bigint,text) to authenticated;
commit;
