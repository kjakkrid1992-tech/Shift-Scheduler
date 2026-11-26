
(function(){
'use strict';
const $=id=>document.getElementById(id), E=window.ShiftEngine, D=window.StaffDates;
let db=null,jobs=[],depts=[],s=null,rows=[],prefs={},versions=[],dirty=false,busy=false,token=0,range=null,dept=null,chosen=new Set();
const node=(tag,value)=>{const e=document.createElement(tag);if(value!==undefined)e.textContent=value;return e};
const hide=(id,value=true)=>$(id).hidden=value;
const unwrap=r=>{if(r.error)throw r.error;return r.data};
const notify=(t='',bad=false)=>{$('scheduleMessage').textContent=t;$('scheduleMessage').className=t?(bad?'notice':'rate-summary'):''};
const label=j=>j.code+' · '+j.name+(j.position?' ('+j.position+')':'');
const editable=()=>s?.status==='draft'&&!busy;
const relevant=j=>j.department_id===dept&&range&&j.start_date<=range.end&&(!j.end_date||j.end_date>=range.start);
const scope=()=>jobs.filter(relevant);
const mark=()=>{dirty=true;$('scheduleState').textContent='ร่าง · ยังไม่ได้บันทึก'};
function leaveOK(){return !dirty||confirm('มีตารางที่ยังไม่ได้บันทึก ต้องการละทิ้งการแก้ไขหรือไม่?')}
function setTab(staff){hide('employeeView',!staff);hide('schedulerView',staff);for(const [id,on] of [['tabStaff',staff],['tabSchedule',!staff]]){$(id).classList.toggle('primary',on);$(id).setAttribute('aria-pressed',String(on))}}
function staffTab(){if(busy||!leaveOK())return false;dirty=false;setTab(true);s=null;rows=[];hide('scheduleContent');notify();return true}
function reset(){$('scheduleContent').inert=false;token++;db=null;jobs=[];depts=[];s=null;rows=[];prefs={};versions=[];dirty=false;busy=false;range=null;dept=null;chosen.clear();for(const id of ['scheduleRows','schedulePrefs','scheduleTotals','scheduleWarnings','scheduleVersions','scheduleFocus','scheduleDept'])$(id).replaceChildren();$('scheduleTitle').textContent='';$('scheduleState').textContent='';hide('scheduleContent');notify();setTab(true)}
function getMonth(){const m=/^(\d{2})\/(\d{4})$/.exec($('scheduleMonth').value.trim());if(!m)throw Error('กรอกรอบเดือน MM/YYYY เช่น 12/2026');const iso=m[2]+'-'+m[1];return {month:iso+'-01',...E.period(iso)}}
function syncJobs(staff){jobs=staff.flatMap(e=>(e.employment_records||[]).map(j=>({...j,employee_id:e.id,code:e.employee_code,name:e.nickname||[e.first_name,e.last_name].filter(Boolean).join(' ')})))}
async function open(client,staff,departments){
 if(busy)return;if(!$('schedulerView').hidden)return;
 db=client;syncJobs(staff);depts=departments;
 const select=$('scheduleDept');select.replaceChildren();
 for(const d of depts.filter(x=>x.active))select.add(new Option(d.name,d.id));
 const preferred=depts.find(d=>d.name==='หน้าร้าน'&&d.active);if(preferred)select.value=preferred.id;
 const today=D.bangkokToday(),d=Number(today.slice(8)),next=d>=26?new Date(Date.UTC(Number(today.slice(0,4)),Number(today.slice(5,7)),1)).toISOString().slice(0,7):today.slice(0,7);
 $('scheduleMonth').value=next.slice(5)+'/'+next.slice(0,4);setTab(false);hide('scheduleContent');notify('เลือกรอบเดือนและแผนก แล้วกดเปิดตาราง');
}
async function run(fn){if(busy||!db)return;busy=true;const t=token;setBusy(true);try{await fn(t)}catch(e){if(t===token)notify(e.message||'เกิดข้อผิดพลาด',true)}finally{if(t===token){busy=false;setBusy(false)}}}
function setBusy(on){$('scheduleContent').inert=on;for(const id of ['scheduleReload','scheduleOpen','scheduleVersions','scheduleMonth','scheduleDept','scheduleSave','scheduleConfirm','scheduleRevise','scheduleAuto','scheduleClear','tabStaff','tabSchedule','tabAttendance','tabAdvance','logout'])$(id).disabled=on; if(!on)renderControls()}
function renderControls(){const draft=s?.status==='draft';hide('scheduleControls',!draft);hide('scheduleSave',!draft);hide('scheduleConfirm',!draft);hide('scheduleRevise',!(s?.status==='confirmed'&&versions[0]?.id===s.id));$('scheduleVersions').disabled=!versions.length;}
async function loadVersions(t){
 const q=unwrap(await db.from('pay_periods').select('id').eq('start_date',range.start).maybeSingle());if(t!==token)return;
 versions=q?unwrap(await db.from('shift_schedules').select('id,version,status,revision').eq('period_id',q.id).eq('department_id',dept).order('version',{ascending:false})):[];
 if(t!==token)return;const sel=$('scheduleVersions');sel.replaceChildren();for(const v of versions)sel.add(new Option('V'+v.version+' · '+(v.status==='confirmed'?'ยืนยันแล้ว':'ร่าง'),v.id));sel.disabled=!versions.length;
}
async function loadId(id,t){
 const [a,b]=await Promise.all([db.from('shift_schedules').select('id,version,revision,status,preferences,department_id,confirmed_at,updated_at').eq('id',id).single(),db.from('shift_assignments').select('*').eq('schedule_id',id).order('work_date').order('planned_start')]);if(t!==token)return;
 const ns=unwrap(a),nr=unwrap(b);if(ns.department_id!==dept)throw Error('ตารางไม่ตรงแผนก');
 s=ns;rows=nr.sort(E.sortRows);prefs=structuredClone(s.preferences||{});for(const p of Object.values(prefs))p.off_days=p.off_days.map(Number);dirty=false;chosen=new Set(scope().map(j=>j.id));$('scheduleVersions').value=id;
 $('scheduleTitle').textContent=D.displayDate(range.start)+' – '+D.displayDate(range.end)+' · V'+s.version;
 $('scheduleState').textContent=s.status==='confirmed'?'ยืนยันแล้ว · อ่านอย่างเดียว':'ร่าง · บันทึกแล้ว';
 hide('scheduleContent',false);renderPrefs();renderFocus();renderRows();notify('โหลดตารางจากฐานข้อมูลแล้ว');
}
async function openPeriod(t,create){if(!leaveOK())return;const p=getMonth(),d=$('scheduleDept').value;if(!d)throw Error('กรุณาเลือกแผนก');
 range=p;dept=d;dirty=false;s=null;rows=[];hide('scheduleContent');await loadVersions(t);if(t!==token)return;
 if(!versions.length&&!create){notify('ยังไม่มีตารางสำหรับรอบนี้ กดเปิดตาราง / สร้างร่าง');return}
 const id=versions[0]?.id||unwrap(await db.rpc('open_shift_schedule',{p_department:dept,p_month:p.month,p_revise:false}));if(t!==token)return;
 if(!versions.length)await loadVersions(t);if(t!==token)return;await loadId(id,t)
}
function renderFocus(){const sel=$('scheduleFocus'),old=sel.value;sel.replaceChildren(new Option('ทุกคน',''));for(const j of scope())sel.add(new Option(label(j),j.id));sel.value=[...sel.options].some(o=>o.value===old)?old:''}
function renderPrefs(){
 const wrap=$('schedulePrefs');wrap.replaceChildren();if(s?.status!=='draft')return;
 if(!scope().length){wrap.append(node('p','ไม่พบพนักงานในแผนกและช่วงเวลานี้'));return}
 for(const j of scope()){
  const raw=prefs[j.id]||{off_days:[],leave_dates:[]},p={off_days:raw.off_days.map(Number),leave_dates:raw.leave_dates},card=node('div');card.className='pref-card';
  const l=node('label'),c=node('input');c.type='checkbox';c.checked=chosen.has(j.id);c.onchange=()=>{if(c.checked)chosen.add(j.id);else chosen.delete(j.id)};l.append(c,document.createTextNode(' '+label(j)+' · ใช้จัดอัตโนมัติ'));card.append(l);
  const days=node('div');days.className='weekdays';['อา.','จ.','อ.','พ.','พฤ.','ศ.','ส.'].forEach((name,i)=>{const lab=node('label'),ck=node('input');ck.type='checkbox';ck.checked=p.off_days.includes(i);ck.onchange=()=>{const v=prefs[j.id]||{off_days:[],leave_dates:[]};v.off_days=ck.checked?[...new Set([...v.off_days,i])]:v.off_days.filter(n=>n!==i);prefs[j.id]=v;mark();renderSummary()};lab.append(ck,document.createTextNode(name));days.append(lab)});card.append(node('small','วันหยุดประจำ'),days);
  const leave=node('input');leave.placeholder='เช่น 28/11/2026, 05/12/2026';leave.value=p.leave_dates.map(D.displayDate).join(', ');
  const save=node('button','ใช้วันลา');save.type='button';save.onclick=()=>{try{const dates=leave.value.trim()?leave.value.split(',').map(v=>D.parseDate(v.trim())):[];if(dates.some(d=>d<range.start||d>range.end))throw Error('วันลาต้องอยู่ในรอบนี้');const v=prefs[j.id]||{off_days:[],leave_dates:[]};v.leave_dates=[...new Set(dates)].sort();prefs[j.id]=v;mark();renderSummary();notify('บันทึกวันลาในร่างแล้ว')}catch(e){notify(e.message,true)}};
  const ll=node('label','วันลา (DD/MM/YYYY ค.ศ. คั่นด้วย ,)');ll.append(leave);card.append(ll,save);wrap.append(card)
 }
}
function time(t){return new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Bangkok',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).format(new Date(t))}
function renderRows(){
 const body=$('scheduleRows');body.replaceChildren();const focus=$('scheduleFocus').value,byId=new Map(jobs.map(j=>[j.id,j]));
 let prev='';for(const r of rows.sort(E.sortRows)){
  const tr=node('tr');if(prev!==r.work_date)tr.classList.add('day-start');prev=r.work_date;if(focus&&r.employment_id!==focus)tr.classList.add('dimmed');
  const date=node('td',D.displayDate(r.work_date)),shift=node('td',r.shift_name+(r.is_extra?' · เสริม':''));shift.append(node('small',time(r.planned_start)+'–'+time(r.planned_end)));
  const person=node('td'),hours=node('td'),actions=node('td');const can=s.status==='draft';
  if(can){
   const sel=node('select');sel.setAttribute('aria-label','พนักงาน '+r.shift_name+' '+r.work_date);sel.add(new Option('— ว่าง —',''));
   for(const j of scope().filter(j=>E.eligible(j,r.work_date)))sel.add(new Option(label(j)+(E.unavailable(prefs,j.id,r.work_date)?' · หยุด/ลา':''),j.id));
   if(r.employment_id&&![...sel.options].some(o=>o.value===r.employment_id))sel.add(new Option((byId.get(r.employment_id)?label(byId.get(r.employment_id)):'ไม่พบพนักงาน')+' · ไม่ตรงช่วงจ้าง',r.employment_id));
   sel.value=r.employment_id||'';sel.disabled=r.is_locked;sel.onchange=()=>{r.employment_id=sel.value||null;mark();renderSummary();if(focus)renderRows()};person.append(sel);
   const inp=node('input');inp.type='number';inp.min='0';inp.max=String((Date.parse(r.planned_end)-Date.parse(r.planned_start))/3600000-r.planned_break_minutes/60);inp.step='0.25';inp.value=String(r.planned_minutes/60);inp.disabled=r.is_locked;inp.setAttribute('aria-label','ชั่วโมงตามแผน');inp.onchange=()=>{const n=Number(inp.value);if(!inp.value||!Number.isFinite(n)||n<0||n>Number(inp.max)||!Number.isInteger(n*60)){notify('ชั่วโมงไม่ถูกต้อง',true);inp.value=String(r.planned_minutes/60);return}r.planned_minutes=n*60;mark();renderSummary()};hours.append(inp);
   const lock=node('button',r.is_locked?'ปลดล็อก':'ล็อก');lock.onclick=()=>{r.is_locked=!r.is_locked;mark();renderRows()};actions.append(lock);
   const extra=node('button',r.is_extra?'ลบ':'เพิ่ม');extra.disabled=r.is_extra&&r.is_locked;extra.onclick=()=>{if(rows.length>=500&&!r.is_extra){notify('ตารางทดลองรองรับสูงสุด 500 กะ',true);return}if(r.is_extra){rows=rows.filter(x=>x.id!==r.id)}else{rows.push({...r,id:crypto.randomUUID(),is_extra:true,is_locked:false,employment_id:null})}mark();renderRows()};actions.append(extra)
  }else{person.textContent=r.employment_id?(byId.get(r.employment_id)?label(byId.get(r.employment_id)):'ไม่พบประวัติ'):'— ว่าง —';hours.textContent=String(r.planned_minutes/60);actions.textContent=r.is_locked?'ล็อก':''}
  tr.append(date,shift,person,hours,actions);body.append(tr)
 }renderSummary();renderControls()
}
function renderSummary(){
 const w=E.warnings(rows,jobs,prefs),box=$('scheduleWarnings');box.replaceChildren();const lines=[['กะหลักว่าง',w.empty],['กะที่ไม่ตรงวันทำงาน / วันลา / ชั่วโมงศูนย์',w.invalid.length],['กะซ้อนเวลา',w.overlap.length],['พักระหว่างกะน้อยกว่า 11 ชั่วโมง',w.rest.length],['ทำงานติดกันเกิน 6 วัน',w.fatigue.length],['กะที่ยังไม่มีเรทค่าแรง',w.missingRate.length]];
 for(const [name,n] of lines)if(n){const p=node('p',name+' '+n+' รายการ');p.className='warning-text';box.append(p)}
 if(!box.children.length)box.append(node('p','ไม่พบคำเตือนในรอบนี้'));
 const totals=$('scheduleTotals');totals.replaceChildren();const table=node('table'),head=node('tr');for(const v of ['พนักงาน','จำนวนกะ','ชม.ตามแผน','ค่าแรงประมาณการ*'])head.append(node('th',v));const thead=node('thead');thead.append(head);table.append(thead);const body=node('tbody');
 for(const j of scope()){const rs=rows.filter(r=>r.employment_id===j.id);if(!rs.length)continue;const costs=rs.map(r=>E.scoreCost(j,r)),overlaps=rs.some((r,i)=>rs.slice(i+1).some(a=>a.work_date===r.work_date));const sum=costs.some(c=>c===null)||overlaps?'—':costs.reduce((a,b)=>a+b,0).toLocaleString('th-TH',{maximumFractionDigits:2});const tr=node('tr');for(const v of [label(j),rs.length,rs.reduce((a,r)=>a+r.planned_minutes,0)/60,sum])tr.append(node('td',v));body.append(tr)}table.append(body);const wrap=node('div');wrap.className='tablewrap';wrap.append(table);totals.append(wrap,node('small','* ประมาณการเฉพาะกะเดี่ยวของรายวัน/รายชั่วโมง ไม่ใช่เงินเดือนจริง; ไม่รวม OT/กะควบ/เงินเดือนประจำ'))
}
async function persist(confirmIt,t){
 if(s?.status!=='draft')throw Error('ตารางนี้แก้ไขไม่ได้');
 const w=E.warnings(rows,jobs,prefs);let ack=false;
 if(confirmIt){if(w.empty||w.invalid.length)throw Error('แก้กะว่างหรือรายการไม่ถูกต้องก่อนยืนยัน');ack=!!w.overlap.length;if((ack||w.rest.length||w.fatigue.length)&&!confirm('พบกะซ้อน/เวลาพัก/วันทำงานต่อเนื่อง กรุณาตรวจสอบกับพนักงานแล้วเท่านั้น ยืนยันต่อหรือไม่?'))return;if(!confirm('ยืนยันตารางเวอร์ชันนี้? หลังยืนยันต้องสร้างเวอร์ชันใหม่หากแก้ไข'))return}
 const id=s.id,payload=rows.map(({id,work_date,shift_template_id,employment_id,is_extra,is_locked,planned_minutes})=>({id,work_date,shift_template_id,employment_id,is_extra,is_locked,planned_minutes}));
 const revision=unwrap(await db.rpc('save_shift_schedule',{p_schedule:id,p_revision:s.revision,p_rows:payload,p_preferences:prefs,p_confirm:confirmIt,p_ack_overlap:ack}));if(t!==token)return;
 s.revision=revision;if(confirmIt)s.status='confirmed';dirty=false;await loadVersions(t);if(t!==token)return;await loadId(id,t);if(t===token)notify(confirmIt?'ยืนยันตารางแล้ว':'บันทึกร่างแล้ว')
}
$('scheduleOpen').onclick=()=>run(t=>openPeriod(t,true));
$('scheduleReload').onclick=()=>run(async t=>{if(!leaveOK())return;const a=unwrap(await db.from('employees').select('id,employee_code,first_name,last_name,nickname,employment_records(id,department_id,position,employment_type,start_date,end_date,status,compensation_history(id,base_rate,ot_rate,effective_from,pay_type))'));if(t!==token)return;syncJobs(a);dirty=false;await openPeriod(t,false)});
$('scheduleVersions').onchange=()=>run(async t=>{if(!leaveOK()){$('scheduleVersions').value=s?.id||'';return}const id=$('scheduleVersions').value;await loadId(id,t)});
$('scheduleFocus').onchange=renderRows;
$('scheduleAuto').onclick=()=>{if(!editable())return;try{if(!confirm('จัดใหม่เฉพาะกะหลักที่ไม่ล็อก? กะเสริมจะคงเดิม'))return;const r=E.autoSchedule(rows,scope(),prefs,$('scheduleMode').value,[...chosen]);rows=r.rows;mark();renderRows();notify('จัดกะแล้ว · '+(r.metric==='estimated-pay'?'เกลี่ยรายได้ประมาณการ':r.metric==='minutes'?'เกลี่ยชั่วโมง (เรทไม่ครบหรือมีรายเดือน)':'หมุนเวียน')+' · กรุณาตรวจสอบกะว่าง')}catch(e){notify(e.message,true)}};
$('scheduleClear').onclick=()=>{if(!editable()||!confirm('ล้างเฉพาะกะหลักที่ไม่ล็อก?'))return;rows.forEach(r=>{if(!r.is_locked&&!r.is_extra)r.employment_id=null});mark();renderRows()};
$('scheduleSave').onclick=()=>run(t=>persist(false,t));$('scheduleConfirm').onclick=()=>run(t=>persist(true,t));
$('scheduleRevise').onclick=()=>run(async t=>{if(!confirm('สร้างร่างเวอร์ชันใหม่จากตารางล่าสุด? ตารางเดิมจะไม่ถูกแก้ไข'))return;const id=unwrap(await db.rpc('open_shift_schedule',{p_department:dept,p_month:range.month,p_revise:true}));if(t!==token)return;await loadVersions(t);if(t!==token)return;await loadId(id,t)});
$('schedulePrint').onclick=()=>{if(s){document.body.classList.add('printing-schedule');try{window.print()}finally{document.body.classList.remove('printing-schedule')}}};
window.addEventListener('beforeunload',e=>{if(dirty){e.preventDefault();e.returnValue=''}});
window.SchedulerPage={open,reset,staffTab,hasUnsaved:()=>dirty,isBusy:()=>busy};
})();
