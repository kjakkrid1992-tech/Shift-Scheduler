
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
const api={calculate,netMinutes,duration};
if(typeof module==='object'&&module.exports)module.exports=api;else root.AttendanceEngine=Object.freeze(api)
})(globalThis);
