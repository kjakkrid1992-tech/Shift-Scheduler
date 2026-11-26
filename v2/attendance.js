
(function(){
'use strict';
const $=id=>document.getElementById(id),D=window.StaffDates,E=window.AttendanceEngine;
const M=window.AttendancePeriodPage;
let mode="month",db=null,role=null,plan=null,period=null,day=null,dept=null,jobs=[],records=[],slots=[],selected=null,busy=false,dirty=false,epoch=0,manualNormal=false,bulk=new Set();
const names={work:'ทำงานจริง',off:'หยุด',leave:'ลา',holiday:'วันหยุด',absent:'ขาดงาน'},statusNames={draft:'ร่าง',verified:'ตรวจแล้ว',approved:'อนุมัติแล้ว'},actionNames={create:'สร้าง',edit:'แก้ไข',verify:'ตรวจสอบ',approve:'อนุมัติ',reopen:'ตีกลับ'};
const n=(tag,value)=>{const el=document.createElement(tag);if(value!==undefined)el.textContent=value;return el};
const hide=(id,on=true)=>$(id).hidden=on;
const unwrap=r=>{if(r.error)throw r.error;return r.data};
const msg=(t='',bad=false)=>{$('attMessage').textContent=t;$('attMessage').className=t?(bad?'notice':'rate-summary'):'';const local=$('attEditorMessage');local.hidden=!bad||$('attEditor').hidden;local.textContent=local.hidden?'':t;local.className='notice'};
function explain(e){const m=e.message||'เกิดข้อผิดพลาด';if(m.includes('Invalid actual work interval'))return 'ยังไม่ถึงเวลาออกงาน หรือเวลาเข้า–ออกไม่ถูกต้อง กรุณาตรวจสอบเวลาแล้วบันทึกหลังจบกะ';if(m.includes('STALE_ATTENDANCE')||m.includes('STALE_PLAN'))return 'ข้อมูลถูกเปลี่ยนจากอีกเครื่อง กรุณาโหลดข้อมูลใหม่';if(m.includes('Unplanned work requires a note')||m.includes('Non-work exception requires a note'))return 'กรุณาระบุหมายเหตุสำหรับรายการที่ต่างจากแผน';return m}
const form=$('attForm'),f=form.elements;
const existing=()=>records.find(r=>r.employment_id===selected);
const planFor=id=>slots.filter(r=>r.employment_id===id);
const jobLabel=j=>j.code+' · '+j.name;
const times=t=>t?new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Bangkok',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).format(new Date(t)):'';
const isoDay=t=>t?D.bangkokToday(new Date(t)):null;
function setTab(on){hide('attendanceView',!on);$('tabAttendance').classList.toggle('primary',on);$('tabAttendance').setAttribute('aria-pressed',String(on));if(on){hide('employeeView');hide('schedulerView');for(const id of ['tabStaff','tabSchedule']){$(id).classList.remove('primary');$(id).setAttribute('aria-pressed','false')}}}
function reset(){M.reset();bulk.clear();$('attBulkCount').textContent='';epoch++;db=null;role=null;plan=null;period=null;day=null;dept=null;jobs=[];records=[];slots=[];selected=null;dirty=false;busy=false;form.reset();$('attEditor').inert=false;for(const id of ['attRows','attHistoryRows','attDept'])$(id).replaceChildren();for(const id of ['attEmployee','attSnapshot','attStatus','attCalc','attTitle','attPlan'])$(id).textContent='';hide('attEditor');hide('attContent');msg();setTab(false)}
function canLeave(){return !(dirty||bulk.size)||confirm('มีข้อมูลหรือการเลือกที่ยังไม่ได้บันทึก ต้องการละทิ้งหรือไม่?')}
function leave(){if($('attendanceView').hidden)return true;if(busy||M.isBusy()||!canLeave()||!M.canLeave())return false;reset();return true}
function open(client,userRole,depts){db=client;role=userRole;$('attDept').replaceChildren();for(const d of depts)$('attDept').add(new Option(d.name,d.id));const preferred=depts.find(d=>d.active&&d.name==='หน้าร้าน');if(preferred)$('attDept').value=preferred.id;$('attDate').value=D.displayDate(D.bangkokToday());setTab(true);M.open(client,userRole,depts);setMode('month');msg('เลือกวันที่และแผนก แล้วโหลดตารางที่ยืนยันแล้ว')}
function setMode(next){mode=next;hide('attDailyView',next!=='day');hide('attMonthView',next!=='month');for(const [id,key] of [['attMonthMode','month'],['attDayMode','day']]){$(id).classList.toggle('primary',next===key);$(id).setAttribute('aria-pressed',String(next===key))}}
$('attMonthMode').onclick=()=>{if(mode==='month'||busy||M.isBusy()||!canLeave())return;dirty=false;bulk.clear();selected=null;day=null;hide('attContent');hide('attEditor');setMode('month');M.invalidate()};
$('attDayMode').onclick=()=>{if(mode==='day'||busy||M.isBusy()||!M.canLeave())return;M.invalidate();setMode('day')};
async function run(fn){if(busy||!db)return;busy=true;const t=epoch;$('attEditor').inert=true;$('attContent').inert=true;for(const id of ['attLoad','attDate','attDept','tabStaff','tabSchedule','tabAttendance','tabAdvance','tabPayroll','tabLegacy','logout'])$(id).disabled=true;try{await fn(t)}catch(e){if(t===epoch)msg(explain(e),true)}finally{if(t===epoch){busy=false;$('attEditor').inert=false;$('attContent').inert=false;for(const id of ['attLoad','attDate','attDept','tabStaff','tabSchedule','tabAttendance','tabAdvance','tabPayroll','tabLegacy','logout'])$(id).disabled=false;bulkControls()}}}
async function load(t,keep=null){
 const d=keep&&day?day:D.parseDate($('attDate').value),dp=keep&&dept?dept:$('attDept').value;if(keep){$('attDate').value=D.displayDate(d);$('attDept').value=dp;}if(d>D.bangkokToday())throw Error('ยังไม่สามารถบันทึกวันในอนาคต');if(!dp)throw Error('เลือกแผนก');
 // Do not leave stale rows editable if load fails.
 hide('attContent');hide('attEditor');bulk.clear();selected=null;dirty=false;plan=null;day=null;
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
 const tr=n('tr'),pick=n('td'),p=n('td',jobLabel(j)),pl=n('td',planText(planFor(j.id))),actual=n('td',r?(r.attendance_type==='work'?E.duration(r.work_minutes):names[r.attendance_type]):'—'),st=n('td',r?statusNames[r.status]:'ยังไม่บันทึก'),td=n('td'),btn=n('button',r?'ดู / แก้ไข':'แก้เวลา / สถานะ');
 const candidate=bulkCandidate(j);if(candidate){const ck=n('input');ck.type='checkbox';ck.checked=bulk.has(j.id);ck.setAttribute('aria-label','เลือก '+jobLabel(j));ck.onchange=()=>{if(dirty){ck.checked=false;msg('บันทึกหรือปิดแบบฟอร์มรายบุคคลก่อน',true);return}if(ck.checked)bulk.add(j.id);else bulk.delete(j.id);bulkControls()};pick.append(ck);if(!r&&candidate.type==='off')pick.append(n('small','หยุดจริง'))}else pick.textContent='—';if(r&&r.schedule_id!==plan.id)st.append(n('small','อ้างอิงแผนเวอร์ชันก่อน'));btn.onclick=()=>{if(!busy&&canLeave())edit(j.id)};if(!r){const defaults=E.planDefaults(planFor(j.id),day);if(defaults){const quick=n('button','ตรงตามกะ');quick.className='primary';quick.disabled=!defaults.completed;if(!defaults.completed){quick.title='ใช้ได้หลังจบกะ';td.append(n('small','ยังไม่ถึงเวลาออกตามกะ'))}quick.onclick=()=>run(t=>quickSave(t,j.id));td.append(quick)}else if(!planFor(j.id).length){const off=n('button','หยุดจริง');off.onclick=()=>run(t=>quickOff(t,j.id));td.append(off)}}td.append(btn);tr.append(pick,p,pl,actual,st,td);body.append(tr)
 }if(!body.children.length){const tr=n('tr'),td=n('td','ไม่พบรายการ');td.colSpan=6;tr.append(td);body.append(tr)}bulkControls()
}
function bulkCandidate(j){
 if(!day||!plan||j.start_date>day||(j.end_date&&j.end_date<day))return null;
 const r=records.find(x=>x.employment_id===j.id);if(r){if(r.status==='draft'||r.status==='verified'&&role==='owner')return {employment_id:j.id,id:r.id,revision:r.revision,status:r.status};return null}
 const ss=planFor(j.id),p=E.planDefaults(ss,day);if(p&&p.completed)return {employment_id:j.id,revision:0,status:'new',type:'work',start:p.start,end:p.end,overnight:p.overnight,break:p.breakM,normal:p.normalM,note:''};
 if(!ss.length&&day<D.bangkokToday())return {employment_id:j.id,revision:0,status:'new',type:'off',start:null,end:null,overnight:false,break:0,normal:0,note:''};return null
}
function bulkRows(){return jobs.filter(j=>bulk.has(j.id)).map(bulkCandidate).filter(Boolean)}
function bulkControls(){const rs=bulkRows();$('attBulkCount').textContent='เลือก '+rs.length+' คน (รวมทุกตัวกรอง) · ใหม่ '+rs.filter(x=>x.status==='new').length+' · ร่าง '+rs.filter(x=>x.status==='draft').length+' · ตรวจแล้ว '+rs.filter(x=>x.status==='verified').length;
 const all=s=>rs.length>0&&rs.every(x=>x.status===s);$('attBulkSave').disabled=!all('new');$('attBulkSaveVerify').disabled=!all('new');$('attBulkVerify').disabled=!all('draft');$('attBulkApprove').disabled=!all('verified');hide('attBulkApprove',role!=='owner')}
$('attBulkSelect').onclick=()=>{if(dirty){msg('บันทึกหรือปิดแบบฟอร์มรายบุคคลก่อน',true);return}bulk.clear();for(const j of jobs){const c=bulkCandidate(j);if(c?.type==='work'&&c.status==='new')bulk.add(j.id)}render()};
$('attBulkClear').onclick=()=>{bulk.clear();render()};
async function submitBulk(t,action){if(dirty)throw Error('บันทึกแบบฟอร์มรายบุคคลก่อน');const rs=bulkRows(),expected=action==='approve'?'verified':action==='verify'?'draft':'new';if(!rs.length||rs.length!==bulk.size||rs.some(r=>r.status!==expected))throw Error('เลือกเฉพาะรายการสถานะเดียวกัน');const description=rs.map(r=>jobLabel(jobs.find(j=>j.id===r.employment_id))+(r.status==='new'?(r.type==='off'?' · หยุดจริง': ' · '+r.start+'–'+r.end+(r.overnight?' วันถัดไป':'')+' พัก '+r.break+' นาที ปกติ '+r.normal+' นาที'):'')).join('\n');if(!confirm('ยืนยันว่าตรวจข้อมูลจริงและชั่วโมงปกติ/OT แล้ว สำหรับ '+rs.length+' คน?\n'+description+'\nระบบจะบันทึกทั้งหมดหรือไม่บันทึกเลย'))return;
 const count=unwrap(await db.rpc('bulk_attendance',{p_date:day,p_department:dept,p_schedule:plan.id,p_action:action,p_rows:rs}));if(t!==epoch)return;bulk.clear();await load(t);if(t===epoch)msg('ดำเนินการสำเร็จ '+count+' รายการ')}
for(const [id,act] of [['attBulkSave','save'],['attBulkSaveVerify','save_verify'],['attBulkVerify','verify'],['attBulkApprove','approve']])$(id).onclick=()=>run(t=>submitBulk(t,act));
function edit(id){bulk.clear();render();selected=id;dirty=false;manualNormal=false;msg();const j=jobs.find(x=>x.id===id),r=existing();form.reset();$('attHistoryRows').replaceChildren();$('attEmployee').textContent=jobLabel(j);$('attSnapshot').textContent='แผนที่ใช้อ้างอิง: '+planText(r?r.planned_snapshot:planFor(id))+(r&&r.schedule_id!==plan.id?' · แผนเดิม (ไม่เขียนทับ)':'');$('attStatus').textContent=r?statusNames[r.status]+' · Revision '+r.revision:'ยังไม่บันทึก · กรุณาตรวจบัตรลงเวลา';
 f.kind.value=r?.attendance_type||'work';f.start.value=times(r?.actual_start);f.end.value=times(r?.actual_end);f.overnight.checked=!!r?.actual_end&&isoDay(r.actual_end)!==r.work_date;f.break.value=String(r?.break_minutes||0);f.normal.value=String(r?.normal_minutes||0);f.note.value=r?.note||'';
 const defaults=E.planDefaults(r?r.planned_snapshot:planFor(id),day);
 $('attPrefillHint').textContent='';
 if(!r&&defaults){fillPlan(defaults);$('attPrefillHint').textContent='ใส่เวลาจากกะให้แล้ว ตรวจสอบกับบัตรลงเวลาก่อนบันทึก'}
 else if(!r&&!planFor(id).length){f.kind.value='off';$('attPrefillHint').textContent='ไม่มีแผนทำงาน — ตรวจสอบว่าเป็นวันหยุดจริง หรือเปลี่ยนประเภทเป็นทำงาน/ลา'}
 else if(!r){$('attPrefillHint').textContent='มีกะหลายช่วงหรือชั่วโมงแผนต่างจากเวลา กรุณากรอกเวลาจริงและพักรวม ไม่คัดลอกโดยอัตโนมัติ'}
 if(r)manualNormal=true;
 const can=!r||r.status==='draft';for(const el of Array.from(form.elements))el.disabled=!can;hide('attSave',!can);hide('attSaveVerify',!can);hide('attCopyPlan',!defaults||!can);hide('attVerify',r?.status!=='draft');hide('attApprove',!(r?.status==='verified'&&role==='owner'));hide('attReopen',!r||r.status==='draft'||(r.status==='approved'&&role!=='owner'));hide('attHistory',!r);hide('attEditor',false);calc();$('attEditor').scrollIntoView({block:'start'})
}
function numeric(field){if(field.value.trim()==='')throw Error('กรอกจำนวนนาทีให้ครบ');return Number(field.value)}
function fillPlan(p){f.kind.value='work';f.start.value=p.start;f.end.value=p.end;f.overnight.checked=p.overnight;f.break.value=String(p.breakM);f.normal.value=String(p.normalM);manualNormal=false}
function suggestNormal(){try{f.normal.value=String(Math.min(480,E.netMinutes(f.start.value.trim(),f.end.value.trim(),f.overnight.checked,numeric(f.break))))}catch{}}
function calc(){const work=f.kind.value==='work';hide('attTimes',!work);if(!work){$('attCalc').textContent='ไม่มีเวลาทำงานจริง';return}try{const c=E.calculate(f.start.value.trim(),f.end.value.trim(),f.overnight.checked,numeric(f.break),numeric(f.normal));$('attCalc').textContent='สุทธิ '+E.duration(c.work)+' · ปกติ '+E.duration(c.normal)+' · OT '+E.duration(c.ot)+(E.completed(day,f.end.value.trim(),f.overnight.checked)?'':' · ยังไม่ถึงเวลาออกงาน จึงยังบันทึกไม่ได้')}catch(e){$('attCalc').textContent=e.message}}
form.addEventListener('input',e=>{dirty=true;if(e.target===f.normal)manualNormal=true;if(!manualNormal&&[f.start,f.end,f.break,f.overnight,f.kind].includes(e.target)&&f.kind.value==='work')suggestNormal();calc()});
$('attCopyPlan').onclick=()=>{const r=existing(),p=E.planDefaults(r?r.planned_snapshot:planFor(selected),day);if(p){fillPlan(p);dirty=true;calc()}};
$('attSuggest').onclick=()=>{try{f.normal.value=String(Math.min(480,E.netMinutes(f.start.value.trim(),f.end.value.trim(),f.overnight.checked,numeric(f.break))));manualNormal=false;dirty=true;calc()}catch(e){msg(e.message,true)}};
$('attLoad').onclick=()=>run(async t=>{if(canLeave())await load(t)});
$('attFilter').onchange=render;
for(const id of ['attDate','attDept'])$(id).addEventListener('change',()=>{if(!day)return;if(!canLeave()){$('attDate').value=D.displayDate(day);$('attDept').value=dept;return}dirty=false;bulk.clear();selected=null;day=null;hide('attContent');hide('attEditor');msg('กดโหลดข้อมูลประจำวันเพื่อเปิดวันที่เลือก')});
$('attClose').onclick=()=>{if(canLeave()){dirty=false;selected=null;hide('attEditor')}};
async function saveForm(t,verify){
 if(!selected||!plan)throw Error('โหลดข้อมูลก่อน');const r=existing(),work=f.kind.value==='work',id=selected;
 if(work){E.calculate(f.start.value.trim(),f.end.value.trim(),f.overnight.checked,numeric(f.break),numeric(f.normal));if(!E.completed(day,f.end.value.trim(),f.overnight.checked))throw Error('ยังไม่ถึงเวลาออกงาน กรุณาบันทึกหลังจบกะ หรือกรอกเวลาออกจริงที่เกิดขึ้นแล้ว')}
 if(verify&&!confirm('ยืนยันว่าข้อมูลตรงกับบัตรลงเวลา และตรวจชั่วโมงปกติ / OT แล้ว?'))return;
 const saved=unwrap(await db.rpc('save_attendance',{p_employment:id,p_date:day,p_schedule:r?.schedule_id||plan.id,p_revision:r?.revision||0,p_type:f.kind.value,p_start:work?f.start.value.trim():null,p_end:work?f.end.value.trim():null,p_overnight:work&&f.overnight.checked,p_break:work?numeric(f.break):0,p_normal:work?numeric(f.normal):0,p_note:f.note.value.trim()}));if(t!==epoch)return;dirty=false;
 if(verify){try{unwrap(await db.rpc('transition_attendance',{p_id:saved,p_revision:(r?.revision||0)+1,p_action:'verify',p_reason:''}))}catch(e){await load(t,id);if(t===epoch)msg('บันทึกร่างแล้ว แต่ยืนยันตรวจสอบไม่สำเร็จ: '+explain(e),true);return}}
 await load(t,id);if(t===epoch)msg(verify?'บันทึกและตรวจสอบแล้ว':'บันทึกร่างแล้ว')
}
async function quickSave(t,id){
 if(!canLeave())return;
 const p=E.planDefaults(planFor(id),day);if(!p||!p.completed)throw Error('กะยังไม่จบหรือไม่สามารถคัดลอกเวลาตามแผนได้');
 const j=jobs.find(x=>x.id===id);
 if(!confirm(jobLabel(j)+' — ตรวจบัตรแล้วว่าเข้า '+p.start+' ออก '+p.end+(p.overnight?' (วันถัดไป)':'')+' พัก '+p.breakM+' นาทีจริง? ปกติ '+E.duration(p.normalM)+' / OT '+E.duration(p.work-p.normalM)+' จะบันทึกเป็นร่าง'))return;
 unwrap(await db.rpc('save_attendance',{p_employment:id,p_date:day,p_schedule:plan.id,p_revision:0,p_type:'work',p_start:p.start,p_end:p.end,p_overnight:p.overnight,p_break:p.breakM,p_normal:p.normalM,p_note:''}));if(t!==epoch)return;dirty=false;await load(t);if(t===epoch)msg('บันทึกตรงตามกะเป็นร่างแล้ว · รอตรวจสอบ')
}
async function quickOff(t,id){
 if(!canLeave()||!confirm(jobLabel(jobs.find(x=>x.id===id))+' — ยืนยันจากข้อมูลจริงว่าไม่ได้ทำงานและเป็นวันหยุด ไม่ใช่วันลาหรือขาดงาน?'))return;
 if(planFor(id).length)throw Error('มีแผนทำงาน กรุณาระบุเหตุผลในแบบฟอร์ม');
 unwrap(await db.rpc('save_attendance',{p_employment:id,p_date:day,p_schedule:plan.id,p_revision:0,p_type:'off',p_start:null,p_end:null,p_overnight:false,p_break:0,p_normal:0,p_note:''}));if(t!==epoch)return;dirty=false;await load(t);if(t===epoch)msg('บันทึกวันหยุดเป็นร่างแล้ว')
}
form.onsubmit=e=>{e.preventDefault();run(t=>saveForm(t,false))};
$('attSaveVerify').onclick=()=>run(t=>saveForm(t,true));
async function transition(t,action){const r=existing();if(!r)throw Error('ยังไม่ได้บันทึก');if(dirty)throw Error('บันทึกการเปลี่ยนแปลงก่อน');let reason='';if(action==='reopen'){const v=prompt('ระบุเหตุผลที่ต้องแก้ไข');if(v===null)return;reason=v.trim();if(!reason)throw Error('ต้องระบุเหตุผล')}else if(!confirm(action==='approve'?'อนุมัติเวลาจริงรายการนี้?':'ยืนยันว่าตรวจสอบกับบัตรลงเวลาแล้ว?'))return;
 const id=selected;unwrap(await db.rpc('transition_attendance',{p_id:r.id,p_revision:r.revision,p_action:action,p_reason:reason}));if(t!==epoch)return;await load(t,id);if(t===epoch)msg('ดำเนินการ '+actionNames[action]+' สำเร็จ')}
$('attVerify').onclick=()=>run(t=>transition(t,'verify'));$('attApprove').onclick=()=>run(t=>transition(t,'approve'));$('attReopen').onclick=()=>run(t=>transition(t,'reopen'));
$('attHistory').onclick=()=>run(async t=>{const r=existing();if(!r)return;const rr=unwrap(await db.from('attendance_revisions').select('revision,action,reason,created_at,snapshot').eq('attendance_id',r.id).order('revision',{ascending:false}));if(t!==epoch)return;const box=$('attHistoryRows');box.replaceChildren(n('h3','ประวัติการแก้ไข'));for(const x of rr){const p=n('div');p.className='job-card';const z=x.snapshot;p.append(n('strong','Rev '+x.revision+' · '+actionNames[x.action]),n('p',D.displayDate(isoDay(x.created_at))+' '+times(x.created_at)+' · '+names[z.attendance_type]+' · '+E.duration(z.work_minutes)),n('p','ปกติ '+E.duration(z.normal_minutes)+' / OT '+E.duration(z.ot_minutes)+' · '+statusNames[z.status]));if(z.actual_start)p.append(n('p',times(z.actual_start)+'–'+times(z.actual_end)+' · พัก '+z.break_minutes+' นาที'));if(z.note)p.append(n('p','หมายเหตุ: '+z.note));if(x.reason)p.append(n('p','เหตุผล: '+x.reason));box.append(p)}});
window.addEventListener('beforeunload',e=>{if(dirty||bulk.size||M.hasUnsaved()||M.isBusy()||busy){e.preventDefault();e.returnValue=''}});
window.AttendancePage={open,reset,leave,hasUnsaved:()=>dirty||bulk.size>0||M.hasUnsaved(),isBusy:()=>busy||M.isBusy()};
})();
