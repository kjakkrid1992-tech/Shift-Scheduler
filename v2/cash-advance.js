(function(){
'use strict';
const $=id=>document.getElementById(id),D=window.StaffDates,E=window.AdvanceEngine,S=window.ShiftEngine;
let db=null,role=null,depts=[],jobs=[],rows=[],range=null,dept='',selected=null,requestId=null,busy=false,dirty=false,epoch=0;
const status={draft:'ร่าง',approved:'อนุมัติ / รอจ่าย',paid:'จ่ายแล้ว',cancelled:'ยกเลิก',voided:'โมฆะ'},labels={create:'สร้าง',edit:'แก้ไข',approve:'อนุมัติ',pay:'บันทึกจ่าย',cancel:'ยกเลิก',void:'โมฆะ'};
const form=$('advForm'),f=form.elements,pay=$('advPayForm'),pf=pay.elements;
const hide=(id,on=true)=>$(id).hidden=on;
const n=(tag,value)=>{const e=document.createElement(tag);if(value!==undefined)e.textContent=value;return e};
const unwrap=r=>{if(r.error)throw r.error;return r.data};
const msg=(t='',bad=false)=>{$('advMessage').textContent=t;$('advMessage').className=t?(bad?'notice':'rate-summary'):'';$('advEditorMessage').hidden=!bad||$('advEditor').hidden;$('advEditorMessage').className='notice';$('advEditorMessage').textContent=bad?t:''};
const label=j=>j?j.code+' · '+j.name:'ไม่พบพนักงาน';
const jobFor=id=>jobs.find(j=>j.id===id);
const current=()=>rows.find(r=>r.id===selected);
const canLeave=()=>!dirty||confirm('มีข้อมูลเงินเบิกที่ยังไม่ได้บันทึก ต้องการละทิ้งหรือไม่?');
function setTab(on){hide('advanceView',!on);$('tabAdvance').classList.toggle('primary',on);$('tabAdvance').setAttribute('aria-pressed',String(on));if(on){for(const id of ['employeeView','schedulerView','attendanceView'])hide(id);for(const id of ['tabStaff','tabSchedule','tabAttendance']){$(id).classList.remove('primary');$(id).setAttribute('aria-pressed','false')}}}
function closeEditor(){dirty=false;selected=null;requestId=null;form.reset();pay.reset();hide('advEditor');hide('advPayForm');$('advHistoryRows').replaceChildren()}
function reset(){epoch++;db=null;role=null;depts=[];jobs=[];rows=[];range=null;dept='';busy=false;closeEditor();for(const id of ['advRows','advDept'])$(id).replaceChildren();hide('advContent');$('advanceView').inert=false;msg();setTab(false)}
function leave(){if($('advanceView').hidden)return true;if(busy||!canLeave())return false;reset();return true}
function monthText(iso){return iso.slice(5)+'/'+iso.slice(0,4)}
function getRange(){const m=/^(\d{2})\/(\d{4})$/.exec($('advMonth').value.trim());if(!m)throw Error('กรอกรอบเดือน MM/YYYY เช่น 12/2026');const month=m[2]+'-'+m[1];return {month,...S.period(month)}}
function explain(e){const m=e.message||'เกิดข้อผิดพลาด';if(m.includes('STALE_ADVANCE'))return 'รายการถูกเปลี่ยนแล้ว กรุณาโหลดข้อมูลใหม่';if(m.includes('Only owner'))return 'รายการนี้ทำได้เฉพาะเจ้าของ';if(m.includes('Invalid payment date'))return 'วันที่จ่ายต้องไม่ก่อนวันที่เบิก ไม่เกินวันนี้ และอยู่ในช่วงการจ้าง';if(m.includes('Payment method'))return 'กรุณาระบุหลักฐานอ้างอิงสำหรับการโอนเงิน';return m}
async function run(fn){if(busy||!db)return;busy=true;const t=epoch;$('advanceView').inert=true;for(const id of ['tabStaff','tabSchedule','tabAttendance','tabAdvance','tabPayroll','logout'])$(id).disabled=true;try{await fn(t)}catch(e){if(t===epoch)msg(explain(e),true)}finally{if(t===epoch){busy=false;$('advanceView').inert=false;for(const id of ['tabStaff','tabSchedule','tabAttendance','tabAdvance','tabPayroll','logout'])$(id).disabled=false}}}
function open(client,userRole,departments){db=client;role=userRole;depts=departments;$('advDept').replaceChildren(new Option('ทุกแผนก',''));for(const d of depts)$('advDept').add(new Option(d.name,d.id));$('advMonth').value=monthText(E.periodMonth(D.bangkokToday()));$('advFilter').value='all';$('advSearch').value='';setTab(true);run(t=>load(t))}
async function load(t,keep=null){
 const next=getRange(),dp=$('advDept').value;hide('advContent');closeEditor();range=null;rows=[];
 const [a,b]=await Promise.all([db.from('employment_records').select('id,department_id,start_date,end_date,employees(employee_code,first_name,last_name,nickname)').order('id'),db.from('pay_periods').select('id').eq('start_date',next.start).maybeSingle()]);if(t!==epoch)return;
 jobs=unwrap(a).map(j=>({...j,code:j.employees?.employee_code||j.id,name:j.employees?.nickname||[j.employees?.first_name,j.employees?.last_name].filter(Boolean).join(' ')})).sort((a,b)=>a.code.localeCompare(b.code));
 const pp=unwrap(b);let rr=[];
 if(pp){let q=db.from('cash_advances').select('*').eq('period_id',pp.id).order('request_date',{ascending:false}).order('id');if(dp)q=q.eq('department_id',dp);rr=unwrap(await q.limit(1000));if(t!==epoch)return;if(rr.length>=1000)throw Error('เกินขอบเขต 999 รายการของระบบทดลอง กรุณาเลือกแผนกให้แคบลง')}
 range=next;dept=dp;rows=rr;hide('advContent',false);$('advPeriod').textContent=D.displayDate(range.start)+' – '+D.displayDate(range.end);render();msg('โหลดข้อมูลแล้ว');if(keep&&rows.some(r=>r.id===keep))detail(keep)
}
function render(){if(!range)return;const sums=E.totals(rows);$('advDraft').textContent=E.money(sums.draft);$('advApproved').textContent=E.money(sums.approved);$('advPaid').textContent=E.money(sums.paid);const body=$('advRows');body.replaceChildren();const filter=$('advFilter').value,q=$('advSearch').value.trim().toLowerCase();
 for(const r of rows){const j=jobFor(r.employment_id);if(filter!=='all'&&r.status!==filter||q&&!label(j).toLowerCase().includes(q))continue;const tr=n('tr'),date=n('td',D.displayDate(r.request_date));if(r.paid_date)date.append(n('small','จ่าย '+D.displayDate(r.paid_date)));const amount=n('td',E.money(r.amount_satang)),td=n('td'),btn=n('button','ดู / ดำเนินการ');btn.onclick=()=>{if(!busy&&canLeave())detail(r.id)};td.append(btn);tr.append(date,n('td',label(j)),amount,n('td',status[r.status]),n('td',r.note),td);body.append(tr)}
 if(!body.children.length){const tr=n('tr'),td=n('td','ไม่พบรายการ');td.colSpan=6;tr.append(td);body.append(tr)}
}
function eligible(j,d){return j.start_date<=d&&(!j.end_date||j.end_date>=d)&&(!dept||j.department_id===dept)}
function populateEmployees(keep=''){let date;try{date=D.parseDate(f.date.value)}catch{}f.employee.replaceChildren(new Option('เลือกพนักงาน',''));if(date)for(const j of jobs.filter(j=>eligible(j,date)))f.employee.add(new Option(label(j),j.id));if([...f.employee.options].some(o=>o.value===keep))f.employee.value=keep}
function editor(r=null){if(!range){msg('โหลดรอบเดือนก่อน',true);return}closeEditor();selected=r?.id||null;requestId=r?.id||crypto.randomUUID();hide('advEditor',false);hide('advForm',false);hide('advDetail');$('advEditorTitle').textContent=r?'แก้ไขร่าง':'เพิ่มเงินเบิก';const today=D.bangkokToday();f.date.value=D.displayDate(r?.request_date||(today>=range.start&&today<=range.end?today:range.end));f.date.disabled=!!r;populateEmployees(r?.employment_id||'');if(r&&!f.employee.value){f.employee.add(new Option(label(jobFor(r.employment_id)),r.employment_id));f.employee.value=r.employment_id}f.employee.disabled=!!r;f.amount.value=r?(Number(r.amount_satang)/100).toFixed(2):'';f.note.value=r?.note||'';dirty=false;msg();$('advEditor').scrollIntoView({block:'start'});f.amount.focus()}
function detail(id){closeEditor();selected=id;const r=current();if(!r)return;hide('advEditor',false);hide('advForm');hide('advDetail',false);$('advEditorTitle').textContent=label(jobFor(r.employment_id));$('advDetailText').textContent=E.money(r.amount_satang)+' บาท · '+status[r.status]+' · เบิก '+D.displayDate(r.request_date)+(r.paid_date?' · จ่าย '+D.displayDate(r.paid_date)+' · '+(r.payment_method==='cash'?'เงินสด':'โอนเงิน')+' '+(r.payment_reference||''):'')+' · '+r.note+(r.close_reason?' · เหตุผล: '+r.close_reason:'');const allowed=E.actions(r.status,role);for(const [id,a] of [['advEdit','edit'],['advApprove','approve'],['advPay','pay'],['advCancel','cancel'],['advVoid','void']])hide(id,!allowed.includes(a));$('advEditor').scrollIntoView({block:'start'})}
$('advNew').onclick=()=>{if(!busy&&canLeave())editor()};
$('advClose').onclick=()=>{if(canLeave())closeEditor()};
$('advLoad').onclick=()=>run(t=>canLeave()?load(t):Promise.resolve());
$('advFilter').onchange=render;$('advSearch').oninput=render;
for(const id of ['advMonth','advDept'])$(id).onchange=()=>{if(!range)return;if(!canLeave()){$('advMonth').value=monthText(range.month);$('advDept').value=dept;return}closeEditor();range=null;rows=[];hide('advContent');msg('กดโหลดข้อมูลรอบเดือน')};
form.oninput=e=>{dirty=true;if(e.target===f.date)populateEmployees(f.employee.value)};
form.onsubmit=e=>{e.preventDefault();run(async t=>{if(!range||!requestId)throw Error('โหลดข้อมูลก่อน');const r=current(),d=D.parseDate(f.date.value);if(d<range.start||d>range.end||d>D.bangkokToday())throw Error('วันที่เบิกต้องอยู่ในรอบที่เลือกและไม่เกินวันนี้');const j=jobFor(f.employee.value);if(!j||!eligible(j,d))throw Error('เลือกพนักงานที่มีการจ้างในวันเบิก');const amount=E.parseAmount(f.amount.value),note=f.note.value.trim();if(!note)throw Error('ระบุรายละเอียดเงินเบิก');
 const id=unwrap(await db.rpc('save_cash_advance',{p_id:requestId,p_employment:j.id,p_date:d,p_revision:r?.revision||0,p_amount_satang:amount,p_note:note}));if(t!==epoch)return;dirty=false;await load(t,id);if(t===epoch)msg('บันทึกร่างเงินเบิกแล้ว')})};
$('advEdit').onclick=()=>{if(current()&&canLeave())editor(current())};
async function transition(t,action,extra={}){
 const r=current();if(!r)throw Error('ไม่พบรายการ');let reason='';
 if(action==='approve'){if(!confirm('อนุมัติเงินเบิก '+E.money(r.amount_satang)+' บาท? ยังไม่ถือว่าจ่ายเงินจริง'))return}
 if(action==='cancel'||action==='void'){if(action==='void'&&!confirm('ทำโมฆะเฉพาะรายการบันทึกการจ่ายผิดที่ไม่ได้จ่ายเงินจริง ห้ามใช้แทนการคืนเงิน ยืนยันหรือไม่?'))return;const v=prompt(action==='void'?'ระบุเหตุผลที่บันทึกจ่ายผิด':'ระบุเหตุผลที่ยกเลิก');if(v===null)return;reason=v.trim();if(!reason)throw Error('ต้องระบุเหตุผล')}
 const id=r.id;unwrap(await db.rpc('transition_cash_advance',{p_id:id,p_revision:r.revision,p_action:action,p_paid_date:null,p_method:null,p_reference:null,p_reason:reason,...extra}));if(t!==epoch)return;dirty=false;
 if(action==='pay')$('advMonth').value=monthText(E.periodMonth(extra.p_paid_date));await load(t,id);if(t===epoch)msg(action==='pay'?'บันทึกจ่ายจริงแล้ว · จัดเข้ารอบตามวันที่จ่าย':'ดำเนินการ '+labels[action]+' สำเร็จ')
}
$('advApprove').onclick=()=>run(t=>transition(t,'approve'));$('advCancel').onclick=()=>run(t=>transition(t,'cancel'));$('advVoid').onclick=()=>run(t=>transition(t,'void'));
function payHint(){try{const d=D.parseDate(pf.date.value);$('advPayPeriod').textContent='ยอดที่จะส่ง Payroll: รอบ '+monthText(E.periodMonth(d))}catch{$('advPayPeriod').textContent='กรุณากรอกวันที่จ่ายจริง'}}
$('advPay').onclick=()=>{if(!current())return;pay.reset();pf.date.value=D.displayDate(D.bangkokToday());hide('advPayForm',false);dirty=true;payHint();pf.date.focus()};
pay.oninput=()=>{dirty=true;payHint()};
pay.onsubmit=e=>{e.preventDefault();run(async t=>{const r=current(),d=D.parseDate(pf.date.value),reference=pf.reference.value.trim();if(!r||d<r.request_date||d>D.bangkokToday())throw Error('วันที่จ่ายต้องไม่ก่อนวันเบิกและไม่เกินวันนี้');if(pf.method.value==='transfer'&&!reference)throw Error('ระบุเลขอ้างอิงการโอน');if(!confirm('ยืนยันว่าได้จ่ายเงินจริง '+E.money(r.amount_satang)+' บาทให้พนักงานแล้ว? ระบบจะบันทึกเท่านั้น ไม่ได้โอนเงิน'))return;await transition(t,'pay',{p_paid_date:d,p_method:pf.method.value,p_reference:reference})})};
$('advHistory').onclick=()=>run(async t=>{const r=current();if(!r)return;const rr=unwrap(await db.from('cash_advance_revisions').select('revision,action,actor_id,reason,snapshot,created_at').eq('advance_id',r.id).order('revision',{ascending:false}));if(t!==epoch)return;const actors=[...new Set(rr.map(x=>x.actor_id))];let actorNames=new Map();if(actors.length){const ar=await db.from('user_profiles').select('user_id,display_name').in('user_id',actors);if(t!==epoch)return;if(!ar.error)actorNames=new Map(ar.data.map(x=>[x.user_id,x.display_name]))}const box=$('advHistoryRows');box.replaceChildren(n('h3','ประวัติรายการ'));for(const x of rr){const p=n('div');p.className='job-card';const z=x.snapshot;p.append(n('strong','Rev '+x.revision+' · '+labels[x.action]+' · '+E.money(z.amount_satang)+' บาท'),n('p',new Date(x.created_at).toLocaleString('th-TH',{timeZone:'Asia/Bangkok'})+' · '+(actorNames.get(x.actor_id)||x.actor_id)+' · '+status[z.status]),n('p',z.note));if(x.reason)p.append(n('p','เหตุผล: '+x.reason));box.append(p)}});
window.addEventListener('beforeunload',e=>{if(dirty){e.preventDefault();e.returnValue=''}});
window.AdvancePage={open,reset,leave,isBusy:()=>busy,hasUnsaved:()=>dirty};
})();
