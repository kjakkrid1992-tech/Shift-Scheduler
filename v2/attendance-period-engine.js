(function(root){
'use strict';
const E=typeof module==='object'&&module.exports?require('./attendance-engine.js'):root.AttendanceEngine;
const S=typeof module==='object'&&module.exports?require('./schedule-engine.js'):root.ShiftEngine;
function periodMonth(day){const [y,m,d]=day.split('-').map(Number);return new Date(Date.UTC(y,m-1+(d>=26?1:0),1)).toISOString().slice(0,7)}
function monthInput(raw){const m=/^(\d{2})\/(\d{4})$/.exec(String(raw||'').trim());if(!m)throw Error('กรอกรอบเดือน MM/YYYY (ค.ศ.)');const iso=m[2]+'-'+m[1];S.period(iso);return iso}
function preset(key){const p={morning:['06:30','15:30',60],afternoon:['12:00','21:00',60],double:['06:30','21:00',120]}[key];if(p)return {kind:'work',start:p[0],end:p[1],overnight:false,breakM:p[2],normalM:480};if(!['off','leave','holiday','absent'].includes(key))throw Error('เลือกประเภท');return {kind:key,start:'',end:'',overnight:false,breakM:0,normalM:0}}
function fromPlan(slots,day,now){const p=E.planDefaults(slots,day,now);return p?.completed?{kind:'work',start:p.start,end:p.end,overnight:p.overnight,breakM:p.breakM,normalM:p.normalM}:null}
function payload(r,now=Date.now()){
 if(!['work','off','leave','holiday','absent'].includes(r.kind))throw Error('เลือกประเภทวันก่อนบันทึก');
 const note=String(r.note||'').trim(),work=r.kind==='work';if(note.length>1000)throw Error('หมายเหตุเกิน 1,000 ตัวอักษร');
 if(r.day>new Date(now+7*3600000).toISOString().slice(0,10))throw Error('ยังไม่ถึงวันทำงาน');
 if((work&&!r.planCount||!work&&(r.planCount||r.kind!=='off'))&&!note)throw Error('ระบุหมายเหตุสำหรับรายการต่างจากแผน');
 if(work){if(String(r.breakM).trim()===''||String(r.normalM).trim()==='')throw Error('กรอกนาทีพักและปกติ');E.calculate(r.start,r.end,!!r.overnight,Number(r.breakM),Number(r.normalM));if(!E.completed(r.day,r.end,!!r.overnight,now))throw Error('ยังไม่ถึงเวลาออกงาน')}
 return {p_employment:r.employment,p_date:r.day,p_schedule:r.schedule,p_revision:r.revision||0,p_type:r.kind,p_start:work?r.start:null,p_end:work?r.end:null,p_overnight:work&&!!r.overnight,p_break:work?Number(r.breakM):0,p_normal:work?Number(r.normalM):0,p_note:note}
}
function action(r,mode){if(mode==='approve'){if(r.status!=='verified'||r.dirty)throw Error('เลือกเฉพาะวันที่ตรวจแล้ว');return ['approve']}if(r.status!=='new'&&r.status!=='draft')throw Error('วันที่อนุมัติ/ตรวจแล้วต้องตีกลับก่อน');if(mode==='save')return r.status==='new'||r.dirty?['save']:[];if(mode==='verify')return r.status==='new'||r.dirty?['save','verify']:['verify'];throw Error('Invalid action')}
const api={periodMonth,monthInput,preset,fromPlan,payload,action};
if(typeof module==='object'&&module.exports)module.exports=api;else root.AttendancePeriodEngine=Object.freeze(api);
})(globalThis);
