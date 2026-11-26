
(function(root){
'use strict';
const dayOfWeek=d=>new Date(d+'T00:00:00Z').getUTCDay();
const eligible=(j,d)=>!!j&&j.start_date<=d&&(!j.end_date||j.end_date>=d);
const unavailable=(prefs,id,d)=>{const p=prefs[id]||{};return (p.off_days||[]).includes(dayOfWeek(d))||(p.leave_dates||[]).includes(d)};
const period=month=>{if(!/^\d{4}-\d{2}$/.test(month))throw Error('Invalid month');const [y,m]=month.split('-').map(Number);if(y<1900||y>2199||m<1||m>12||y===1900&&m===1)throw Error('Invalid month');return {start:new Date(Date.UTC(y,m-2,26)).toISOString().slice(0,10),end:month+'-25'}};
const nextDay=d=>{const t=new Date(d+'T00:00:00Z');t.setUTCDate(t.getUTCDate()+1);return t.toISOString().slice(0,10)};
const daysIn=range=>{const out=[];for(let d=range.start;d<=range.end;d=nextDay(d))out.push(d);return out};
const sortRows=(a,b)=>a.work_date.localeCompare(b.work_date)||a.planned_start.localeCompare(b.planned_start)||Number(a.is_extra)-Number(b.is_extra)||a.id.localeCompare(b.id);
function rateAt(job,d){return [...(job?.compensation_history||[])].filter(r=>r.effective_from<=d).sort((a,b)=>b.effective_from.localeCompare(a.effective_from))[0]||null}
function scoreCost(job,row){const r=rateAt(job,row.work_date);if(!r||job.employment_type==='monthly')return null;return job.employment_type==='hourly'?Number(r.base_rate)*row.planned_minutes/60:Number(r.base_rate)*row.planned_minutes/480}
function overlap(a,b){return Date.parse(a.planned_start)<Date.parse(b.planned_end)&&Date.parse(b.planned_start)<Date.parse(a.planned_end)}
function warnings(rows,jobs,prefs){
 const byId=new Map(jobs.map(j=>[j.id,j])),byEmp=new Map(),out={empty:0,invalid:[],overlap:[],rest:[],fatigue:[],missingRate:[]};
 for(const r of rows){if(!r.employment_id){if(!r.is_extra)out.empty++;continue}const j=byId.get(r.employment_id);
 if(!eligible(j,r.work_date)||unavailable(prefs,r.employment_id,r.work_date)||r.planned_minutes===0)out.invalid.push(r.id);
 if(!rateAt(j,r.work_date))out.missingRate.push(r.id);
 const key=j?.employee_id||r.employment_id;if(!byEmp.has(key))byEmp.set(key,[]);byEmp.get(key).push(r)}
 for(const [key,rs] of byEmp){rs.sort(sortRows);let prev=null,streak=0,previousDay=null;
 for(let i=0;i<rs.length;i++){const r=rs[i];for(let k=0;k<i;k++)if(overlap(r,rs[k]))out.overlap.push([rs[k].id,r.id]);if(prev&&r.work_date!==prev.work_date&&(Date.parse(r.planned_start)-Date.parse(prev.planned_end))/3600000<11)out.rest.push(r.id);if(!prev||Date.parse(r.planned_end)>Date.parse(prev.planned_end))prev=r;
 if(r.work_date!==previousDay){streak=previousDay&&nextDay(previousDay)===r.work_date?streak+1:1;if(streak>6)out.fatigue.push(key+':'+r.work_date);previousDay=r.work_date}}
 }return out
}
function autoSchedule(rows,jobs,prefs,mode,selectedIds){
 const pool=jobs.filter(j=>selectedIds.includes(j.id)).sort((a,b)=>a.code.localeCompare(b.code)||a.id.localeCompare(b.id));
 if((mode==='2'&&pool.length!==2)||(mode==='3'&&pool.length!==3)||!pool.length)throw Error('เลือกพนักงานให้ตรงจำนวนของโหมด');
 const result=rows.map(r=>({...r})).sort(sortRows),byDay=new Map(),byId=new Map(jobs.map(j=>[j.id,j]));
 for(const r of result){if(!byDay.has(r.work_date))byDay.set(r.work_date,[]);byDay.get(r.work_date).push(r);if(!r.is_locked&&!r.is_extra)r.employment_id=null}
 // All locked/extra commitments count before selecting candidates; look ahead to future fixed shifts.
 const assigned=result.filter(r=>r.employment_id),counts=new Map(),money=new Map();
 const key=j=>j?.employee_id||j?.id;
 function account(r){const j=byId.get(r.employment_id);if(!j)return;const k=key(j);counts.set(k,(counts.get(k)||0)+r.planned_minutes);money.set(k,(money.get(k)||0)+(scoreCost(j,r)||0))}
 assigned.forEach(account);
 const allComparable=pool.every(j=>j.employment_type!=='monthly'&&[...byDay.keys()].filter(d=>eligible(j,d)).every(d=>rateAt(j,d)));
 function allowed(j,r){if(!eligible(j,r.work_date)||unavailable(prefs,j.id,r.work_date))return false;const k=key(j),rs=assigned.filter(a=>key(byId.get(a.employment_id))===k);
 if(rs.some(a=>a.work_date===r.work_date))return false;
 if(rs.some(a=>overlap(a,r)||Math.min(Math.abs(Date.parse(r.planned_start)-Date.parse(a.planned_end)),Math.abs(Date.parse(a.planned_start)-Date.parse(r.planned_end)))<11*3600000))return false;
 const ds=new Set(rs.map(a=>a.work_date));ds.add(r.work_date);let streak=1;let d=r.work_date;while(ds.has(d=new Date(Date.parse(d+'T00:00:00Z')-86400000).toISOString().slice(0,10)))streak++;d=r.work_date;while(ds.has(d=nextDay(d)))streak++;return streak<=6
 }
 let di=0;
 for(const [d,rs] of byDay){let si=0;for(const r of rs){if(r.is_extra)continue;const idx=si++;if(r.is_locked)continue;let candidates=pool.filter(j=>allowed(j,r));if(!candidates.length)continue;
 if(mode==='2'||mode==='3'){const preferred=pool[(di+idx)%pool.length];candidates.sort((a,b)=>Number(b.id===preferred.id)-Number(a.id===preferred.id)||(counts.get(key(a))||0)-(counts.get(key(b))||0))}
 else candidates.sort((a,b)=>((allComparable?money:counts).get(key(a))||0)-((allComparable?money:counts).get(key(b))||0)||a.code.localeCompare(b.code));
 r.employment_id=candidates[0].id;assigned.push(r);account(r);
 }di++}
 return {rows:result,metric:mode==='balance'?(allComparable?'estimated-pay':'minutes'):'rotation'}
}
const api={period,daysIn,eligible,unavailable,rateAt,warnings,autoSchedule,scoreCost,sortRows};
if(typeof module==='object'&&module.exports)module.exports=api;else root.ShiftEngine=Object.freeze(api);
})(globalThis);
