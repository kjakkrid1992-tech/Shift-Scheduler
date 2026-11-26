-- Phase 5B.1: structured reviewed drafts; requires 00700. No finalization or settlement.
begin;
alter table public.payroll_drafts add column item_breakdown jsonb
 check(item_breakdown is null or jsonb_typeof(item_breakdown)='object');
create or replace function public.save_payroll_draft(p_employment uuid,p_month date,p_revision integer,p_source jsonb,
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
  update public.payroll_drafts set item_breakdown=null,source_snapshot=source_now,base_satang=p_base,ot_satang=p_ot,other_income_satang=p_other_income,
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

-- Derive only supported amounts from the approved, server-generated snapshot.
create function staff_private.payroll_known_amounts(p_source jsonb)
returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object(
 'base',coalesce(sum(case when x.status='approved' and x.type='work' and x.rate_id is not null then
   case when p_source->>'pay_type'='daily' and x.normal_minutes=480 then round(x.base_rate*100)
        when p_source->>'pay_type'='hourly' then round(x.base_rate*100*x.normal_minutes/60)
        else 0 end else 0 end),0),
 'ot',coalesce(sum(case when x.status='approved' and x.type='work' and x.rate_id is not null
   then round(x.ot_rate*100*x.ot_minutes/60) else 0 end),0),
 'base_manual_days',count(*) filter(where x.status='approved' and
   (x.type in ('leave','holiday') or (x.type='work' and (x.rate_id is null or
   p_source->>'pay_type'='monthly' or (p_source->>'pay_type'='daily' and x.normal_minutes<>480))))),
 'ot_manual_days',count(*) filter(where x.status='approved' and x.type='work' and x.rate_id is null),
 'approved_work_days',count(*) filter(where x.status='approved' and x.type='work'))
 from jsonb_to_recordset(p_source->'days') as x(status text,type text,rate_id uuid,base_rate numeric,ot_rate numeric,normal_minutes integer,ot_minutes integer);
$$;
revoke all on function staff_private.payroll_known_amounts(jsonb) from public,anon,authenticated;
-- Fixed manual categories, zero is an explicit reviewed amount. Base/OT are reviewed totals,
-- not increments; known subtotals remain separate in the audit snapshot.
create function public.save_payroll_items(p_employment uuid,p_month date,p_revision integer,p_source jsonb,p_items jsonb,p_note text)
returns uuid language plpgsql security definer set search_path='' as $$
declare item record; v jsonb; known jsonb; key_id uuid; rec public.payroll_drafts%rowtype;
 base_amt bigint; ot_amt bigint; income_amt bigint; deduction_amt bigint; adv_amt bigint;
begin
 if coalesce(staff_private.staff_role(),'') not in ('owner','manager') then raise exception using errcode='42501',message='Staff access required'; end if;
 if jsonb_typeof(p_items) is distinct from 'object' or (select count(*) from jsonb_object_keys(p_items))<>11 then raise exception 'Invalid payroll item set'; end if;
 foreach v in array array[p_items->'base',p_items->'ot',p_items->'attendance_bonus',p_items->'performance_bonus',p_items->'behavior_bonus',p_items->'other_income',p_items->'advance',p_items->'social_security',p_items->'tax',p_items->'other_deduction',p_items->'paid_leave'] loop
  if jsonb_typeof(v) is distinct from 'number' or (v#>>'{}') !~ '^[0-9]+$' or (v#>>'{}')::numeric>1000000000 then raise exception 'Enter each reviewed item in integer satang'; end if;
 end loop;
 base_amt:=(p_items->>'base')::bigint;
 ot_amt:=(p_items->>'ot')::bigint;
 income_amt:=(p_items->>'attendance_bonus')::bigint+(p_items->>'performance_bonus')::bigint+(p_items->>'behavior_bonus')::bigint+(p_items->>'other_income')::bigint+(p_items->>'paid_leave')::bigint;
 adv_amt:=(p_items->>'advance')::bigint;
 deduction_amt:=(p_items->>'social_security')::bigint+(p_items->>'tax')::bigint+(p_items->>'other_deduction')::bigint;
 -- Existing RPC validates source freshness, revision, amount bounds, and paid advance cap.
 -- Same transaction: if any step fails, neither summary nor breakdown is written.
 key_id:=public.save_payroll_draft(p_employment,p_month,p_revision,p_source,base_amt,ot_amt,income_amt,adv_amt,deduction_amt,p_note);
 select * into rec from public.payroll_drafts where id=key_id for update;
 known:=staff_private.payroll_known_amounts(rec.source_snapshot);
 update public.payroll_drafts set item_breakdown=jsonb_build_object('version',1,'items',p_items,'known',known) where id=key_id returning * into rec;
 update public.payroll_draft_revisions set snapshot=to_jsonb(rec) where draft_id=key_id and revision=rec.revision;
 if not found then raise exception 'Payroll revision snapshot missing'; end if;
 return key_id;
end $$;
revoke all on function public.save_payroll_items(uuid,date,integer,jsonb,jsonb,text) from public,anon,authenticated;
grant execute on function public.save_payroll_items(uuid,date,integer,jsonb,jsonb,text) to authenticated;
commit;
