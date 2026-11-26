
'use strict';
const $=id=>document.getElementById(id);
const {parseDate,displayDate,bangkokToday,ratesFor}=window.StaffDates;
const money=v=>Number(v).toLocaleString('th-TH',{minimumFractionDigits:0,maximumFractionDigits:2});
const payUnit={daily:'วัน',hourly:'ชม.',monthly:'เดือน'};
const statusNames={probation:'ทดลองงาน',active:'ปฏิบัติงาน',resigned:'ลาออก',terminated:'สิ้นสุดการจ้าง'};
const payNames={daily:'รายวัน',hourly:'รายชั่วโมง',monthly:'รายเดือน'};
let db, role=null, staff=[], departments=[], selected=null, editing=null, busy=false, epoch=0;
const current=e=>e && !e.end_date;
const latest=e=>[...(e.employment_records||[])].sort((a,b)=>b.start_date.localeCompare(a.start_date))[0];
const jobOn=(e,day)=>(e.employment_records||[]).find(j=>j.start_date<=day&&(!j.end_date||j.end_date>=day));
const text=(tag,value)=>{const el=document.createElement(tag);el.textContent=value??'';return el};
const msg=(value='',error=false)=>{$('message').textContent=value;$('message').classList.toggle('error',error)};
function unwrap(r){if(r.error)throw r.error;return r.data}
function errorMessage(e){return e?.code==='23505'?'รหัสพนักงานหรือวันที่เรทซ้ำ':e?.code==='23P01'?'ช่วงการจ้างซ้อนกับประวัติเดิม':e?.code==='42501'?'ไม่มีสิทธิ์ทำรายการ':e?.message||'เกิดข้อผิดพลาด'}
function hide(id,value=true){$(id).hidden=value}
function clearUI(){clearReports();$('managementReport').open=false;$('profileReport').open=false;window.LegacyPage.reset();$('tabLegacy').hidden=true;window.PayrollPage.reset();window.AdvancePage.reset();window.AttendancePage.reset();window.SchedulerPage.reset();role=null;staff=[];departments=[];selected=null;editing=null;for(const id of ['workspace','detail','editor','logout'])hide(id);$('staffRows').replaceChildren();$('detailBody').replaceChildren();$('detailTitle').textContent='';for(const id of ['staffForm','rateForm','endForm','rehireForm','loginForm'])$(id).reset()}
async function action(fn){if(busy)return;busy=true;const buttons=[...document.querySelectorAll('button')].filter(b=>!b.disabled);for(const b of buttons)b.disabled=true;try{await fn()}catch(e){msg(errorMessage(e),true)}finally{busy=false;for(const b of buttons)if(b.isConnected)b.disabled=false}}
function populateDepartments(){for(const id of ['staffForm','rehireForm']){const select=$(id).elements.department;select.replaceChildren();for(const d of departments.filter(d=>d.active)){const opt=new Option(d.name,d.id);select.add(opt)}}}
async function refresh(){const ticket=epoch;const [a,b]=await Promise.all([db.from('employees').select('id,employee_code,first_name,last_name,nickname,phone,employment_records(id,department_id,position,employment_type,start_date,end_date,status,compensation_history(id,base_rate,ot_rate,effective_from,pay_type))').order('employee_code'),db.from('departments').select('id,name,active').order('name')]);if(ticket!==epoch)return;staff=unwrap(a);departments=unwrap(b);populateDepartments();render();if(selected){if(staff.some(e=>e.id===selected))showDetail(selected);else hide('detail')}}
function render(){
  const today=bangkokToday(),q=$('search').value.toLowerCase().trim(),filter=$('filter').value,rows=$('staffRows');
  rows.replaceChildren();
  const open=staff.filter(e=>jobOn(e,today)),missing=open.filter(e=>!ratesFor(jobOn(e,today),today).current);
  $('total').textContent=staff.length;$('activeCount').textContent=open.length;$('formerCount').textContent=staff.filter(e=>!jobOn(e,today)&&latest(e)?.end_date&&latest(e).end_date<today).length;$('identityCount').textContent=staff.filter(e=>!latest(e)).length;
  $('rateWarning').hidden=!missing.length;
  $('rateWarning').textContent=missing.length?'พนักงานที่ยังไม่มีเรทค่าแรงที่มีผล ณ '+displayDate(today)+' จำนวน '+missing.length+' คน · ตรวจสอบก่อนคำนวณเงินเดือน':'';
  for(const e of staff){
    const live=jobOn(e,today),j=live||latest(e),isOpen=!!live,r=ratesFor(j,today);
    if(filter==='current'&&!isOpen||filter==='former'&&(!j?.end_date||j.end_date>=today||isOpen)||filter==='missing-rate'&&(!isOpen||r.current)||filter==='identity'&&!!j||filter==='future'&&(!j||isOpen||j.start_date<=today))continue;
    if(q&&![e.employee_code,e.first_name,e.last_name,e.nickname,j?.position].join(' ').toLowerCase().includes(q))continue;
    const tr=text('tr',''),name=text('td',e.employee_code+' · '+e.first_name+' '+e.last_name);
    if(e.nickname)name.append(text('small',e.nickname));
    const status=text('td',isOpen?'ปฏิบัติงาน / '+(statusNames[j.status]||j.status):j?.start_date>today?'ยังไม่เริ่มงาน':statusNames[j?.status]||'ทะเบียนบุคคล / ยังไม่มีการจ้าง');
    if(j&&j.start_date>today)status.append(text('small','เริ่มงาน '+displayDate(j.start_date)));
    const rate=text('td',isOpen&&j.start_date<=today&&r.current?money(r.current.base_rate)+' บาท/'+payUnit[j.employment_type]:isOpen&&!r.current?'ยังไม่มีเรท':'—');
    if(isOpen&&!r.current)rate.className='warning-text';
    if(isOpen&&r.future.length)rate.append(text('small','เรทถัดไป '+displayDate(r.future[0].effective_from)));
    tr.append(name,text('td',j?.position||'—'),text('td',payNames[j?.employment_type]||'—'),status,rate);
    const td=text('td',''),btn=text('button','ดูประวัติ');btn.onclick=()=>{hide('editor');editing=null;showDetail(e.id);$('detail').scrollIntoView({block:'start'})};td.append(btn);tr.append(td);rows.append(tr);
  }
  if(!rows.children.length){const tr=text('tr',''),td=text('td','ไม่พบข้อมูล');td.colSpan=6;tr.append(td);rows.append(tr)}
}
function showDetail(id){
  clearProfile();selected=id;const e=staff.find(x=>x.id===id);if(!e)return;
  const j=latest(e),d=$('detailBody'),today=bangkokToday();
  $('detailTitle').textContent=e.employee_code+' · '+e.first_name+' '+e.last_name;
  d.replaceChildren(text('p','ชื่อเล่น: '+(e.nickname||'—')+' · โทรศัพท์: '+(e.phone||'—')));
  const jobs=[...(e.employment_records||[])].sort((a,b)=>b.start_date.localeCompare(a.start_date));
  for(const job of jobs){
    const open=current(job),r=ratesFor(job,job.end_date||today),panel=text('article','');
    panel.className='job-card '+(open?'current-job':'past-job');
    const tag=text('span',open?(job.start_date>today?'การจ้างที่ยังไม่เริ่ม':'การจ้างปัจจุบัน'):'ประวัติการจ้างเดิม');tag.className='job-tag';
    panel.append(tag,text('h3',job.position+' · '+(statusNames[job.status]||job.status)),text('p',displayDate(job.start_date)+' ถึง '+(job.end_date?displayDate(job.end_date):'ไม่มีกำหนดสิ้นสุด')+' · '+payNames[job.employment_type]));
    if(open){
      const info=text('div',r.current&&job.start_date<=today?'เรทปัจจุบัน: '+money(r.current.base_rate)+' บาท/'+payUnit[job.employment_type]+' · OT '+money(r.current.ot_rate)+' บาท/ชม.':'ยังไม่มีเรทค่าแรงที่มีผล ณ วันนี้');
      info.className=r.current&&job.start_date<=today?'rate-summary':'notice';panel.append(info);
      if(r.future.length){const next=r.future[0];panel.append(text('p','เรทถัดไป: '+money(next.base_rate)+' บาท/'+payUnit[job.employment_type]+' · เริ่ม '+displayDate(next.effective_from)))}
    }
    const table=text('table',''),head=text('thead',''),hr=text('tr','');
    for(const h of ['วันที่มีผล','ค่าแรง (บาท/'+payUnit[job.employment_type]+')','OT/ชม.','สถานะเรท'])hr.append(text('th',h));head.append(hr);table.append(head);
    const body=text('tbody','');
    for(const rate of r.rates){
      const row=text('tr',''),label=open?(rate.effective_from>today?'ในอนาคต':r.current?.id===rate.id?'มีผลปัจจุบัน':'เรทเดิม'):'ประวัติ';
      row.append(text('td',displayDate(rate.effective_from)),text('td',money(rate.base_rate)),text('td',money(rate.ot_rate)),text('td',label));body.append(row)
    }
    if(!body.children.length){const row=text('tr',''),td=text('td','ยังไม่ได้กำหนดเรท');td.colSpan=4;row.append(td);body.append(row)}
    table.append(body);const wrap=text('div','');wrap.className='tablewrap';wrap.append(table);panel.append(wrap);d.append(panel);
  }
  hide('detail',false);hide('rehire',!!current(j));hide('rehireForm');hide('rateForm',!(role==='owner'&&current(j)));hide('endForm',!(role==='owner'&&current(j)));hide('activate',!(role==='owner'&&j?.status==='probation'));
  $('rateForm').reset();$('endForm').reset();$('rehireForm').reset();
  $('rateUnit').textContent='ค่าแรง (บาท/'+(payUnit[j?.employment_type]||'หน่วย')+')';
}
function edit(id=null){editing=id;const f=$('staffForm');f.reset();const e=staff.find(x=>x.id===id);$('editorTitle').textContent=e?'แก้ไขข้อมูลทั่วไป':'เพิ่มพนักงาน';f.elements.code.disabled=!!e;hide('employmentFields',!!e);for(const field of ['department','position','start'])f.elements[field].required=!e;if(e){f.elements.code.value=e.employee_code;f.elements.first.value=e.first_name;f.elements.last.value=e.last_name;f.elements.nickname.value=e.nickname;f.elements.phone.value=e.phone}hide('editor',false);$('editor').scrollIntoView({block:'start'})}
function vals(f){const v=Object.fromEntries(new FormData(f));for(const el of f.querySelectorAll('[data-date]')){if(el.required||(!el.closest('[hidden]')&&el.value.trim()))v[el.name]=parseDate(el.value)}return v}
function selectedJob(){const e=staff.find(x=>x.id===selected),j=e&&latest(e);if(!current(j))throw new Error('ไม่พบการจ้างที่ยังมีผล');return j}
async function startSession(session){const ticket=++epoch;clearUI();msg();if(!session){hide('login',false);return}hide('login');try{const p=unwrap(await db.from('user_profiles').select('display_name,role,active').eq('user_id',session.user.id).maybeSingle());if(ticket!==epoch)return;if(!p?.active||!['owner','manager'].includes(p.role)){msg('บัญชีนี้ยังไม่ได้รับสิทธิ์จากผู้ดูแล',true);hide('logout',false);return}role=p.role;$('profileLegacyLoad').hidden=role!=='owner';$('reportMonth').value=reportDefault();$('tabLegacy').hidden=role!=='owner';$('identity').textContent=p.display_name+' · '+(role==='owner'?'เจ้าของ':'ผู้จัดการ');await refresh();if(ticket!==epoch)return;$('filter').value=staff.some(e=>jobOn(e,bangkokToday()))?'current':'all';render();hide('workspace',false);hide('logout',false);window.SchedulerPage.staffTab()}catch(e){if(ticket===epoch){msg(errorMessage(e),true);hide('logout',false)}}}
function bind(id,fn){$(id).addEventListener('submit',e=>{e.preventDefault();action(()=>fn(e.currentTarget))})}
bind('loginForm',async f=>{const v=vals(f);const data=unwrap(await db.auth.signInWithPassword({email:v.email,password:v.password}));f.reset();await startSession(data.session)});
$('logout').onclick=()=>action(async()=>{if(window.SchedulerPage.isBusy()||window.AttendancePage.isBusy()||window.AdvancePage.isBusy()||window.PayrollPage.isBusy()||window.LegacyPage.isBusy())return;if((window.SchedulerPage.hasUnsaved()||window.AttendancePage.hasUnsaved()||window.AdvancePage.hasUnsaved()||window.PayrollPage.hasUnsaved()||window.LegacyPage.hasUnsaved())&&!confirm('มีข้อมูลที่ยังไม่ได้บันทึก ต้องการออกจากระบบหรือไม่?'))return;++epoch;clearUI();unwrap(await db.auth.signOut());hide('login',false);msg('ออกจากระบบแล้ว')});
$('search').oninput=render;$('filter').onchange=render;$('refresh').onclick=()=>action(async()=>{await refresh();msg('อัปเดตข้อมูลแล้ว')});
$('newStaff').onclick=()=>{selected=null;hide('detail');edit()};$('closeEditor').onclick=()=>{editing=null;hide('editor')};$('closeDetail').onclick=()=>{clearProfile();selected=null;hide('detail')};$('editStaff').onclick=()=>edit(selected);$('rehire').onclick=()=>hide('rehireForm',false);
bind('staffForm',async f=>{const v=vals(f);if(editing){unwrap(await db.from('employees').update({first_name:v.first.trim(),last_name:v.last.trim(),nickname:v.nickname.trim(),phone:v.phone.trim()}).eq('id',editing).select('id').single());}else{unwrap(await db.rpc('create_staff',{p_code:v.code,p_first:v.first,p_last:v.last,p_nickname:v.nickname,p_phone:v.phone,p_department:v.department,p_position:v.position,p_pay_type:v.pay_type,p_start:v.start,p_status:v.status}))}hide('editor');await refresh();msg('บันทึกทะเบียนพนักงานแล้ว')});
bind('rehireForm',async f=>{const v=vals(f);unwrap(await db.from('employment_records').insert({employee_id:selected,department_id:v.department,position:v.position.trim(),employment_type:v.pay_type,start_date:v.start,status:v.status}));await refresh();msg('เพิ่มประวัติการจ้างใหม่แล้ว')});
bind('rateForm',async f=>{if(role!=='owner')throw new Error('ไม่มีสิทธิ์');const j=selectedJob(),v=vals(f);if(v.date<j.start_date)throw new Error('วันที่มีผลต้องไม่ก่อนวันเริ่มงาน');const last=ratesFor(j,bangkokToday()).rates[0];if(last&&v.date<=last.effective_from)throw new Error('วันที่มีผลต้องหลังเรทล่าสุด '+displayDate(last.effective_from));if(!confirm('ยืนยันเรทใหม่ มีผล '+displayDate(v.date)+'? ประวัติเดิมจะคงอยู่'))return;unwrap(await db.from('compensation_history').insert({employment_id:j.id,pay_type:j.employment_type,base_rate:v.base,ot_rate:v.ot,effective_from:v.date}));await refresh();msg('เพิ่มประวัติเรทค่าแรงแล้ว')});
bind('endForm',async f=>{if(role!=='owner')throw new Error('ไม่มีสิทธิ์');const j=selectedJob(),v=vals(f);if(v.end<j.start_date)throw new Error('วันสิ้นสุดการจ้างต้องไม่ก่อนวันเริ่มงาน');if(v.end>bangkokToday())throw new Error('Phase 1 รองรับการสิ้นสุดการจ้างถึงวันนี้เท่านั้น');if(!confirm('ยืนยันสิ้นสุดการจ้างวันที่ '+displayDate(v.end)+'? ประวัติเดิมจะไม่ถูกลบ'))return;unwrap(await db.from('employment_records').update({status:v.status,end_date:v.end}).eq('id',j.id).select('id').single());await refresh();msg('บันทึกสิ้นสุดการจ้างแล้ว')});
$('activate').onclick=()=>action(async()=>{if(role!=='owner')throw new Error('ไม่มีสิทธิ์');const j=selectedJob();if(!confirm('ยืนยันผ่านทดลองงาน?'))return;unwrap(await db.from('employment_records').update({status:'active'}).eq('id',j.id).select('id').single());await refresh();msg('เปลี่ยนสถานะแล้ว')});
function reportDefault(){const iso=window.AdvanceEngine.periodMonth(bangkokToday());return iso.slice(5)+'/'+iso.slice(0,4)}
function clearProfile(){for(const id of ['profileResult','profileHistory','profileLegacy'])$(id).replaceChildren();$('profileMonth').value=reportDefault();$('profileReport').open=false}
function clearReports(){clearProfile();$('reportResult').replaceChildren();$('reportMonth').value='';$('profileLegacyLoad').hidden=true}
function reportMonth(id){const m=/^(\d{2})\/(\d{4})$/.exec($(id).value.trim());if(!m)throw Error('กรอกรอบเดือน MM/YYYY');const iso=m[2]+'-'+m[1];window.ShiftEngine.period(iso);return iso+'-01'}
function reportCard(box,label,val){const div=text('div','');div.append(text('span',label),text('strong',val));box.append(div)}
const sat=v=>window.AdvanceEngine.money(v);
async function report(id,target,employee=null){const ticket=epoch,month=reportMonth(id);$(target).replaceChildren();const [x,z]=await Promise.all([db.rpc('staff_period_report',{p_month:month,p_employee:employee}),db.rpc('payroll_adjustment_report',{p_month:month,p_employee:employee})]),d=unwrap(x),adj=unwrap(z);if(ticket!==epoch||employee&&selected!==employee)return;const box=$(target),grid=text('div','');grid.className='stats';
 for(const [label,val] of [['พนักงานปัจจุบัน (ณ วันนี้)',d.current_count],['บันทึก / วันที่ควรตรวจ',d.recorded_days+' / '+d.expected_days],['อนุมัติแล้ว',d.approved_days],['ปกติที่อนุมัติ (ชม.)',(Number(d.normal_minutes)/60).toFixed(2)],['OT ที่อนุมัติ (ชม.)',(Number(d.ot_minutes)/60).toFixed(2)],['เงินเบิกจ่ายในรอบ (บาท)',sat(d.advance_paid_period)],['เงินเบิกคงเหลือจากรายการถึงวันตัดข้อมูล (บาท)',sat(d.advance_balance_now_for_cutoff)],['สุทธิร่าง · '+d.draft_count+' รายการ',sat(d.draft_net)],['สุทธิปิดรอบ · '+d.final_count+' รายการ',sat(d.final_net)],['บันทึกจ่ายของรอบ · '+d.paid_count+' รายการ',sat(d.paid_net)]])reportCard(grid,label,val);
 box.append(text('p',displayDate(d.start)+' – '+displayDate(d.end)+' · ข้อมูลเวลาถึง '+displayDate(d.as_of)),grid,text('p','ยอดเงินเบิกคงเหลือใช้การจัดสรรล่าสุด ไม่ใช่ยอด ณ วันย้อนหลัง; ยอดจ่ายของรอบไม่ใช่ยอดตามวันที่โอน'));
 const y=text('div','');y.className='stats';for(const [label,val] of [['รายได้',d.ytd_gross],['หัก',d.ytd_deductions],['สุทธิ',d.ytd_net]])reportCard(y,label+' (บาท)',sat(val));box.append(text('h3','ยอดสะสมตามวันที่บันทึกจ่ายจริง ปี '+d.year+' · '+d.ytd_count+' รายการ'),y,text('p','เฉพาะ Payroll V2 ที่บันทึกจ่ายแล้วในปีที่เลือก ไม่รวม Excel เดิม ไม่รวมรายการปรับปรุงแยก ไม่ใช่ยอดยื่นภาษี'));const ag=text('div','');ag.className='stats';for(const [label,val] of [['รอบต้นฉบับ · รอจ่ายเพิ่ม',adj.pending_pay],['รอบต้นฉบับ · รอรับคืน',adj.pending_return],['จ่ายเพิ่มจริงในช่วงวันที่',adj.period_paid],['รับคืนจริงในช่วงวันที่',adj.period_returned],['จ่ายเพิ่มจริงสะสมรายปี',adj.ytd_paid],['รับคืนจริงสะสมรายปี',adj.ytd_returned]])reportCard(ag,label+' (บาท)',sat(val));box.append(text('h3','รายการปรับปรุงแยก · กระแสเงินสด'),ag,text('p','แยกจากยอดเงินเดือนและยอดภาษี ไม่ใช่การหักเงินเบิกหรือหักงวดถัดไป'))}
$('reportLoad').onclick=()=>action(()=>report('reportMonth','reportResult'));
$('profileLoad').onclick=()=>action(async()=>{if(!selected)return;await report('profileMonth','profileResult',selected)});
function historyTable(box,rows){box.replaceChildren();const table=text('table',''),h=text('tr','');for(const v of ['รอบ / ต้นฉบับ','รายได้','หัก','สุทธิ','สถานะ'])h.append(text('th',v));const head=text('thead','');head.append(h);table.append(head);const body=text('tbody','');for(const r of rows){const tr=text('tr','');for(const v of r)tr.append(text('td',v));body.append(tr)}table.append(body);const wrap=text('div','');wrap.className='tablewrap';wrap.append(table);box.append(wrap);if(!rows.length)box.append(text('p','ไม่พบประวัติ'))}
$('profileHistoryLoad').onclick=()=>action(async()=>{const id=selected,t=epoch,e=staff.find(x=>x.id===id),ids=(e?.employment_records||[]).map(j=>j.id);if(!ids.length){historyTable($('profileHistory'),[]);return}const rows=unwrap(await db.from('payroll_final').select('period_start,net_satang,paid_date,paid_at,snapshot').in('employment_id',ids).order('period_start',{ascending:false}).limit(1000));if(t!==epoch||selected!==id)return;if(rows.length>=1000)throw Error('เกินขอบเขต 999 รายการ');historyTable($('profileHistory'),rows.map(z=>{const s=z.snapshot;return [displayDate(z.period_start),sat(Number(s.base_satang)+Number(s.ot_satang)+Number(s.other_income_satang)),sat(Number(s.advance_deduction_satang)+Number(s.other_deduction_satang)),sat(z.net_satang),z.paid_at?'จ่าย '+displayDate(z.paid_date):'อนุมัติ / รอจ่าย']}))});
$('profileLegacyLoad').onclick=()=>action(async()=>{if(role!=='owner'||!selected)return;const id=selected,t=epoch;const rows=unwrap(await db.from('legacy_payslips').select('source_sheet,source_row,source_record,income_satang,deduction_satang,net_satang').eq('employee_id',id).order('source_sheet').order('source_row').limit(1000));if(t!==epoch||selected!==id)return;if(rows.length>=1000)throw Error('เกินขอบเขต 999 รายการ');historyTable($('profileLegacy'),rows.map(z=>[z.source_record.period_label+' · '+z.source_sheet+' แถว '+z.source_row,sat(z.income_satang),sat(z.deduction_satang),sat(z.net_satang),'Excel เดิม · ไม่ยืนยันวันที่จ่าย']))});
async function init(){const c=window.STAFF_CONFIG||{};if(!/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/.test(c.url||'')||!/^sb_publishable_[A-Za-z0-9_-]+$/.test(c.publishableKey||'')||!window.supabase){hide('setup',false);return}db=window.supabase.createClient(c.url,c.publishableKey,{auth:{storageKey:'shift-scheduler-v8-auth',persistSession:false,detectSessionInUrl:false}});db.auth.onAuthStateChange((event)=>{if(event==='SIGNED_OUT'){++epoch;clearUI();hide('login',false)}});try{const data=unwrap(await db.auth.getSession());await startSession(data.session)}catch(e){msg(errorMessage(e),true);hide('login',false)}}
$('tabStaff').onclick=()=>{const wasLegacy=!$('legacyView').hidden;if(!window.LegacyPage.leave())return;if(!window.PayrollPage.leave()||!window.AdvancePage.leave()||!window.AttendancePage.leave())return;if(window.SchedulerPage.staffTab()&&wasLegacy)action(()=>refresh())};
$('tabSchedule').onclick=()=>{if(!window.LegacyPage.leave())return;if(!window.PayrollPage.leave()||!window.AdvancePage.leave()||!window.AttendancePage.leave())return;window.SchedulerPage.open(db,staff,departments)};
$('tabAttendance').onclick=()=>{if(!window.LegacyPage.leave())return;if(!$('attendanceView').hidden)return;if(!window.PayrollPage.leave()||!window.AdvancePage.leave()||!window.SchedulerPage.staffTab())return;window.AttendancePage.open(db,role,departments)};
$('tabAdvance').onclick=()=>{if(!window.LegacyPage.leave())return;if(!$('advanceView').hidden||!window.PayrollPage.leave()||!window.AttendancePage.leave()||!window.SchedulerPage.staffTab())return;window.AdvancePage.open(db,role,departments)};
$('tabPayroll').onclick=()=>{if(!window.LegacyPage.leave())return;if(!$('payrollView').hidden||!window.AdvancePage.leave()||!window.AttendancePage.leave()||!window.SchedulerPage.staffTab())return;window.PayrollPage.open(db,role)};
$('tabLegacy').onclick=()=>{if(role!=='owner'||!$('legacyView').hidden||!window.PayrollPage.leave()||!window.AdvancePage.leave()||!window.AttendancePage.leave()||!window.SchedulerPage.staffTab())return;window.LegacyPage.open(db)};
init();
