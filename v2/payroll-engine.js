(function(root){
'use strict';
function parseAmount(value){const s=String(value??'').trim();if(!/^[0-9]{1,8}(?:\.[0-9]{1,2})?$/.test(s))throw Error('กรอกจำนวนบาทเป็นตัวเลข ทศนิยมไม่เกิน 2 ตำแหน่ง');const [a,b='']=s.split('.'),n=Number(a)*100+Number(b.padEnd(2,'0'));if(n>1000000000)throw Error('จำนวนเงินเกินขอบเขตระบบทดลอง');return n}
function summarize(source){
 const rows=source.days||[],approved=rows.filter(r=>r.status==='approved'),work=approved.filter(r=>r.type==='work'),missing=rows.filter(r=>!r.attendance_id).length,unapproved=rows.filter(r=>r.attendance_id&&r.status!=='approved').length,missingRate=work.filter(r=>!r.rate_id).length;
 // Suggestions only, round each day to satang; never infer paid leave or monthly proration.
 const rate=(r,k)=>parseAmount(r[k]);
 const ot=missingRate||!work.length?null:work.reduce((v,r)=>v+Math.round(rate(r,'ot_rate')*r.ot_minutes/60),0);
 let base=null;
 if(work.length&&!missingRate&&source.pay_type==='hourly')base=work.reduce((v,r)=>v+Math.round(rate(r,'base_rate')*r.normal_minutes/60),0);
 if(work.length&&!missingRate&&source.pay_type==='daily'&&work.every(r=>r.normal_minutes===480))base=work.reduce((v,r)=>v+rate(r,'base_rate'),0);
 return {missing,unapproved,missingRate,approved:approved.length,workDays:work.length,normal:work.reduce((v,r)=>v+r.normal_minutes,0),otMinutes:work.reduce((v,r)=>v+r.ot_minutes,0),base,ot,nonWork:approved.filter(r=>r.type!=='work').length}
}
function net(a){return a.base+a.ot+a.otherIncome-a.advance-a.otherDeduction}
function canonical(v){if(v===null||typeof v!=='object')return JSON.stringify(v);if(Array.isArray(v))return '['+v.map(canonical).join(',')+']';return '{'+Object.keys(v).sort().map(k=>JSON.stringify(k)+':'+canonical(v[k])).join(',')+'}'}
const itemLabels={base:'ค่าแรง / เงินเดือน (ไม่รวมค่าจ้างวันลา/วันหยุดที่แยกบรรทัด)',ot:'OT',paid_leave:'ค่าจ้างวันลา / วันหยุด (กรอกเอง หากยังไม่รวมในค่าแรง)',attendance_bonus:'เบี้ยขยัน',performance_bonus:'โบนัสปฏิบัติงาน',behavior_bonus:'โบนัสพฤติกรรม',other_income:'รายได้อื่น',advance:'เงินเบิกที่เสนอหัก',social_security:'ประกันสังคม',tax:'ภาษีหัก ณ ที่จ่าย',other_deduction:'รายการหักอื่น'};
const keys=Object.keys(itemLabels),incomeKeys=['paid_leave','attendance_bonus','performance_bonus','behavior_bonus','other_income'],deductionKeys=['social_security','tax','other_deduction'];
function knownAmounts(source){
 let base=0,ot=0,baseManualDays=0,otManualDays=0,workDays=0;
 for(const r of source.days||[]){if(r.status!=='approved')continue;
  if(['leave','holiday'].includes(r.type)){baseManualDays++;continue}
  if(r.type!=='work')continue;workDays++;
  if(!r.rate_id){baseManualDays++;otManualDays++;continue}
  ot+=Math.round(parseAmount(r.ot_rate)*r.ot_minutes/60);
  if(source.pay_type==='daily'&&r.normal_minutes===480)base+=parseAmount(r.base_rate);
  else if(source.pay_type==='hourly')base+=Math.round(parseAmount(r.base_rate)*r.normal_minutes/60);
  else baseManualDays++;
 }
 return {base,ot,baseManualDays,otManualDays,workDays}
}
function aggregate(items){for(const k of keys)if(!Number.isSafeInteger(items[k])||items[k]<0||items[k]>1000000000)throw Error('Invalid item '+k);const otherIncome=incomeKeys.reduce((a,k)=>a+items[k],0),otherDeduction=deductionKeys.reduce((a,k)=>a+items[k],0);return {base:items.base,ot:items.ot,otherIncome,advance:items.advance,otherDeduction}}
const api={parseAmount,summarize,net,canonical,knownAmounts,aggregate,itemLabels,keys,incomeKeys,deductionKeys};if(typeof module==='object'&&module.exports)module.exports=api;else root.PayrollEngine=Object.freeze(api)
})(globalThis);
