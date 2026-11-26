
(function(){
'use strict';
const $=id=>document.getElementById(id),D=window.StaffDates,E=window.AttendanceEngine;
let db=null,role=null,plan=null,period=null,day=null,dept=null,jobs=[],records=[],slots=[],selected=null,busy=false,dirty=false,epoch=0;
const names={work:'ทำงานจริง',off:'หยุด',leave:'ลา',holiday:'วันหยุด',absent:'ขาดงาน'},statusNames={draft:'ร่าง',verified:'ตรวจแล้ว',approved:'อนุมัติแล้ว'},actionNames={create:'สร้าง',edit:'แก้ไข',verify:'ตรวจสอบ',approve:'อนุมัติ',reopen:'ตีกลับ'};
const n=(tag,value)=>{const el=document.createElement(tag);if(value!==undefined)el.textContent=value;return el};
const hide=(id,on=true)=>$(id).hidden=on;
const unwrap=r=>{if(r.error)throw r.error;return r.data};
const msg=(t='',bad=false)=>{$('attMessage').textContent=t;$('attMessage').className=t?(bad?'notice':'rate-summary'):''};
const form=$('attForm'),f=form.elements;
const existing=()=>records.find(r=>r.employment_id===selected);
const planFor=id=>slots.filter(r=>r.employment_id===id);
const jobLabel=j=>j.code+' · '+j.name;
const times=t=>t?new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Bangkok',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).format(new Date(t)):'';
const isoDay=t=>t?D.bangkokToday(new Date(t)):null;
function setTab(on){hide('attendanceView',!on);$('tabAttendance').classList.toggle('primary',on);$('tabAttendance').setAttribute('aria-pressed',String(on));if(on){hide('employeeView');hide('schedulerView');for(const id of ['tabStaff','tabSchedule']){$(id).classList.remove('primary');$(id).setAttribute('aria-pressed','false')}}}
function reset(){epoch++;db=null;role=null;plan=null;period=null;day=null;dept=null;jobs=[];records=[];slots=[];selected=null;dirty=false;busy=false;form.reset();$('attEditor').inert=false;for(const id of ['attRows','attHistoryRows','attDept'])$(id).replaceChildren();for(const id of ['attEmployee','attSnapshot','attStatus','attCalc','attTitle','attPlan'])$(id).textContent='';hide('attEditor');hide('attContent');msg();setTab(false)}
function canLeave(){return !dirty||confirm('มีข้อมูลเวลาจริงที่ยังไม่ได้บันทึก ต้องการละทิ้งหรือไม่?')}
function leave(){if($('attendanceView').hidden)return true;if(busy||!canLeave())return false;reset();return true}
function open(client,userRole,depts){db=client;role=userRole;$('attDept').replaceChildren();for(const d of depts)$('attDept').add(new Option(d.name,d.id));const preferred=depts.find(d=>d.active&&d.name==='หน้าร้าน');if(preferred)$('attDept').value=preferred.id;$('attDate').value=D.displayDate(D.bangkokToday());setTab(true);msg('เลือกวันที่และแผนก แล้วโหลดตารางที่ยืนยันแล้ว')}
async function run(fn){if(busy||!db)return;busy=true;const t=epoch;$('attEditor').inert=true;$('attContent').inert=true;for(const id of ['attLoad','attDate','attDept','tabStaff','tabSchedule','tabAttendance','logout'])$(id).disabled=true;try{await fn(t)}catch(e){if(t===epoch)msg(e.message||'เกิดข้อผิดพลาด',true)}finally{if(t===epoch){busy=false;$('attEditor').inert=false;$('attContent').inert=false;for(const id of ['attLoad','attDate','attDept','tabStaff','tabSchedule','tabAttendance','logout'])$(id).disabled=false}}}
async function load(t,keep=null){
 const d=keep&&day?day:D.parseDate($('attDate').value),dp=keep&&dept?dept:$('attDept').value;if(keep){$('attDate').value=D.displayDate(d);$('attDept').value=dp;}if(d>D.bangkokToday())throw Error('ยังไม่สามารถบันทึกวันในอนาคต');if(!dp)throw Error('เลือกแผนก');
 // Do not leave stale rows editable if load fails.
 hide('attContent');hide('attEditor');selected=null;dirty=false;plan=null;day=null;
 const pp=unwrap(await db.from('pay_periods').select('id,start_date,end_date').lte('start_date',d).gte('end_date',d).maybeSingle());if(t!==epoch)return;
 if(!pp){msg('ไม่พบรอบจัดกะสำหรับวันนี้',true);return}
 const pl=unwrap(await db.from('shift_schedules').select('id,version').eq('period_id',pp.id).eq('department_id',dp).eq('status','confirmed').order('version',{ascending:false}).limit(1).maybeSingle());if(t!==epoch)return;
 if(!pl){msg('ยังไม่มีตารางที่ยืนยันแล้ว กรุณายืนยันจากเมนูจัดตารางกะก่อน',true);return}
 const [a,b,c]=await Promise.all([
 db.from('employment_records').select('id,start_date,end_date,position,employees(employee_code,first_name,last_name,nickname)').eq('department_id',dp),
 db.from('shift_assignments').select('id,employment_id,shift_name,planned_start,planned_end,planned_minutes,planned_break_minutes').eq('schedule_id',pl.id).eq('work_date',d).order('planned_start'),
 db.from('attendance_records').select('*').eq('period_id',pp.id).eq('department_id',dp).eq('work_date',d)
 ]);if(t!==epoch)return;
 const all=unwrap(a),ss=unwrap(b),rr=unwrap(c);
 const needed=new Set([...ss,...rr].map(x=>x.employment_id));
 jobs=all.filter(j=>j.start_date<=d&&(!j.end_date||j.end_date>=d)||needed.has(j.id)).map(j=>({...j,code:j.employees?.employee_code||j.id,name:j.employees?.nickname||[j.employees?.first_name,j.employees?.last_name].filter(Boolean).join(' ')})).sort((a,b)=>a.code.localeCompare(b.code));
 plan=pl;period=pp;day=d;dept=dp;records=rr;slots=ss;hide('attContent',false);$('attTitle').textContent='วันที่ '+D.displayDate(day);$('attPlan').textContent='แผนล่าสุดที่ยืนยัน V'+plan.version+' · รอบ '+D.displayDate(period.start_date)+' – '+D.displayDate(period.end_date);
 render();msg('โหลดข้อมูลแล้ว');if(keep&&jobs.some(j=>j.id===keep))edit(keep)
}
function planText(rs){return rs.length?rs.map(r=>r.shift_name+' '+times(r.planned_start)+'–'+times(r.planned_end)).join(' / '):'ไม่มีแผนทำงาน'}
function render(){
 const body=$('attRows');body.replaceChildren();const filter=$('attFilter').value;
 $('attPlanned').textContent=jobs.filter(j=>planFor(j.id).length).length;$('attPending').textContent=jobs.filter(j=>!records.some(r=>r.employment_id===j.id)).length;$('attVerified').textContent=records.filter(r=>r.status==='verified').length;$('attApproved').textContent=records.filter(r=>r.status==='approved').length;
 for(const j of jobs){const r=records.find(x=>x.employment_id===j.id);if(filter!=='all'&&(filter==='pending'?!!r:r?.status!==filter))continue;
 const tr=n('tr'),p=n('td',jobLabel(j)),pl=n('td',planText(planFor(j.id))),actual=n('td',r?(r.attendance_type==='work'?E.duration(r.work_minutes):names[r.attendance_type]):'—'),st=n('td',r?statusNames[r.status]:'ยังไม่บันทึก'),td=n('td'),btn=n('button',r?'ดู / แก้ไข':'บันทึก');
 if(r&&r.schedule_id!==plan.id)st.append(n('small','อ้างอิงแผนเวอร์ชันก่อน'));btn.onclick=()=>{if(!busy&&canLeave())edit(j.id)};td.append(btn);tr.append(p,pl,actual,st,td);body.append(tr)
 }if(!body.children.length){const tr=n('tr'),td=n('td','ไม่พบรายการ');td.colSpan=5;tr.append(td);body.append(tr)}
}
function edit(id){selected=id;dirty=false;const j=jobs.find(x=>x.id===id),r=existing();form.reset();$('attHistoryRows').replaceChildren();$('attEmployee').textContent=jobLabel(j);$('attSnapshot').textContent='แผนที่ใช้อ้างอิง: '+planText(r?r.planned_snapshot:planFor(id))+(r&&r.schedule_id!==plan.id?' · แผนเดิม (ไม่เขียนทับ)':'');$('attStatus').textContent=r?statusNames[r.status]+' · Revision '+r.revision:'ยังไม่บันทึก · กรุณาตรวจบัตรลงเวลา';
 f.kind.value=r?.attendance_type||'work';f.start.value=times(r?.actual_start);f.end.value=times(r?.actual_end);f.overnight.checked=!!r?.actual_end&&isoDay(r.actual_end)!==r.work_date;f.break.value=String(r?.break_minutes||0);f.normal.value=String(r?.normal_minutes||0);f.note.value=r?.note||'';
 const can=!r||r.status==='draft';for(const el of Array.from(form.elements))el.disabled=!can;hide('attSave',!can);hide('attVerify',r?.status!=='draft');hide('attApprove',!(r?.status==='verified'&&role==='owner'));hide('attReopen',!r||r.status==='draft'||(r.status==='approved'&&role!=='owner'));hide('attHistory',!r);hide('attEditor',false);calc();$('attEditor').scrollIntoView({block:'start'})
}
function numeric(field){if(field.value.trim()==='')throw Error('กรอกจำนวนนาทีให้ครบ');return Number(field.value)}
function calc(){const work=f.kind.value==='work';hide('attTimes',!work);if(!work){$('attCalc').textContent='ไม่มีเวลาทำงานจริง';return}try{const c=E.calculate(f.start.value.trim(),f.end.value.trim(),f.overnight.checked,numeric(f.break),numeric(f.normal));$('attCalc').textContent='สุทธิ '+E.duration(c.work)+' · ปกติ '+E.duration(c.normal)+' · OT '+E.duration(c.ot)}catch(e){$('attCalc').textContent=e.message}}
form.addEventListener('input',()=>{dirty=true;calc()});
$('attSuggest').onclick=()=>{try{f.normal.value=String(Math.min(480,E.netMinutes(f.start.value.trim(),f.end.value.trim(),f.overnight.checked,numeric(f.break))));dirty=true;calc()}catch(e){msg(e.message,true)}};
$('attLoad').onclick=()=>run(async t=>{if(canLeave())await load(t)});
$('attFilter').onchange=render;
for(const id of ['attDate','attDept'])$(id).addEventListener('change',()=>{if(!day)return;if(!canLeave()){$('attDate').value=D.displayDate(day);$('attDept').value=dept;return}dirty=false;selected=null;day=null;hide('attContent');hide('attEditor');msg('กดโหลดข้อมูลประจำวันเพื่อเปิดวันที่เลือก')});
$('attClose').onclick=()=>{if(canLeave()){dirty=false;selected=null;hide('attEditor')}};
form.onsubmit=e=>{e.preventDefault();run(async t=>{if(!selected||!plan)throw Error('โหลดข้อมูลก่อน');const r=existing(),work=f.kind.value==='work',id=selected;if(work)E.calculate(f.start.value.trim(),f.end.value.trim(),f.overnight.checked,numeric(f.break),numeric(f.normal));
 unwrap(await db.rpc('save_attendance',{p_employment:id,p_date:day,p_schedule:r?.schedule_id||plan.id,p_revision:r?.revision||0,p_type:f.kind.value,p_start:work?f.start.value.trim():null,p_end:work?f.end.value.trim():null,p_overnight:work&&f.overnight.checked,p_break:work?numeric(f.break):0,p_normal:work?numeric(f.normal):0,p_note:f.note.value.trim()}));if(t!==epoch)return;dirty=false;await load(t,id);if(t===epoch)msg('บันทึกร่างแล้ว')})};
async function transition(t,action){const r=existing();if(!r)throw Error('ยังไม่ได้บันทึก');if(dirty)throw Error('บันทึกการเปลี่ยนแปลงก่อน');let reason='';if(action==='reopen'){const v=prompt('ระบุเหตุผลที่ต้องแก้ไข');if(v===null)return;reason=v.trim();if(!reason)throw Error('ต้องระบุเหตุผล')}else if(!confirm(action==='approve'?'อนุมัติเวลาจริงรายการนี้?':'ยืนยันว่าตรวจสอบกับบัตรลงเวลาแล้ว?'))return;
 const id=selected;unwrap(await db.rpc('transition_attendance',{p_id:r.id,p_revision:r.revision,p_action:action,p_reason:reason}));if(t!==epoch)return;await load(t,id);if(t===epoch)msg('ดำเนินการ '+actionNames[action]+' สำเร็จ')}
$('attVerify').onclick=()=>run(t=>transition(t,'verify'));$('attApprove').onclick=()=>run(t=>transition(t,'approve'));$('attReopen').onclick=()=>run(t=>transition(t,'reopen'));
$('attHistory').onclick=()=>run(async t=>{const r=existing();if(!r)return;const rr=unwrap(await db.from('attendance_revisions').select('revision,action,reason,created_at,snapshot').eq('attendance_id',r.id).order('revision',{ascending:false}));if(t!==epoch)return;const box=$('attHistoryRows');box.replaceChildren(n('h3','ประวัติการแก้ไข'));for(const x of rr){const p=n('div');p.className='job-card';const z=x.snapshot;p.append(n('strong','Rev '+x.revision+' · '+actionNames[x.action]),n('p',D.displayDate(isoDay(x.created_at))+' '+times(x.created_at)+' · '+names[z.attendance_type]+' · '+E.duration(z.work_minutes)),n('p','ปกติ '+E.duration(z.normal_minutes)+' / OT '+E.duration(z.ot_minutes)+' · '+statusNames[z.status]));if(z.actual_start)p.append(n('p',times(z.actual_start)+'–'+times(z.actual_end)+' · พัก '+z.break_minutes+' นาที'));if(z.note)p.append(n('p','หมายเหตุ: '+z.note));if(x.reason)p.append(n('p','เหตุผล: '+x.reason));box.append(p)}});
window.addEventListener('beforeunload',e=>{if(dirty){e.preventDefault();e.returnValue=''}});
window.AttendancePage={open,reset,leave,hasUnsaved:()=>dirty,isBusy:()=>busy};
})();
