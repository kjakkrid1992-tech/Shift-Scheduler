
(function(root){
'use strict';
function minutes(t){if(!/^([01][0-9]|2[0-3]):[0-5][0-9]$/.test(t||''))throw Error('กรอกเวลา HH:MM เช่น 06:30');return Number(t.slice(0,2))*60+Number(t.slice(3))}
function calculate(start,end,overnight,breakM,normalM){
 const total=minutes(end)+(overnight?1440:0)-minutes(start);
 if(total<=0||total>1440)throw Error('เวลาออกต้องหลังเวลาเข้า และไม่เกิน 24 ชั่วโมง');
 if(!Number.isInteger(breakM)||breakM<0||breakM>=total)throw Error('เวลาพักไม่ถูกต้อง');
 const net=total-breakM;
 if(!Number.isInteger(normalM)||normalM<0||normalM>net)throw Error('นาทีปกติต้องอยู่ระหว่าง 0 ถึงเวลาทำงานสุทธิ');
 return {elapsed:total,work:net,normal:normalM,ot:net-normalM}
}
function netMinutes(start,end,overnight,breakM){return calculate(start,end,overnight,breakM,0).work}
function duration(m){return Math.floor(m/60)+' ชม. '+String(m%60).padStart(2,'0')+' นาที'}
function bangkokTime(t){return new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Bangkok',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).format(new Date(t))}
function bangkokDate(t){const p=Object.fromEntries(new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Bangkok',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date(t)).map(x=>[x.type,x.value]));return p.year+'-'+p.month+'-'+p.day}
function planDefaults(slots,day,now=Date.now()){
 // Only one complete slot can be copied without guessing breaks or combining overlaps.
 if(slots.length!==1)return null;
 const r=slots[0],a=Date.parse(r.planned_start),b=Date.parse(r.planned_end),rest=Number(r.planned_break_minutes),planned=Number(r.planned_minutes);
 if(!Number.isFinite(a)||!Number.isFinite(b)||b<=a||bangkokDate(a)!==day||!Number.isInteger(rest)||rest<0||!Number.isInteger(planned)||planned<=0||a%60000!==0||b%60000!==0)return null;
 const start=bangkokTime(a),end=bangkokTime(b),overnight=bangkokDate(b)!==day;
 try{const work=netMinutes(start,end,overnight,rest);if(work!==planned)return null;return {start,end,overnight,breakM:rest,normalM:Math.min(work,480),work,completed:b<=now}}catch{return null}
}
function completed(day,end,overnight,now=Date.now()){
 minutes(end);const ts=Date.parse(day+'T'+end+':00+07:00')+(overnight?86400000:0);
 return Number.isFinite(ts)&&ts<=now
}
const api={calculate,netMinutes,duration,planDefaults,completed};
if(typeof module==='object'&&module.exports)module.exports=api;else root.AttendanceEngine=Object.freeze(api)
})(globalThis);
