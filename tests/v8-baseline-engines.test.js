const test=require('node:test');
test("RC2 regression on actual V8: advance-engine",()=>{

const assert=require('node:assert/strict'),E=require('../v8/advance-engine.js');
assert.equal(E.parseAmount('500.01'),50001);
assert.equal(E.parseAmount('0.01'),1);
assert.equal(E.parseAmount('1000000.00'),100000000);
assert.equal(E.parseAmount('125.5'),12550);
for(const x of ['0','-1','1.001','1e3','NaN','1,000','1000000.01',''])assert.throws(()=>E.parseAmount(x));
assert.equal(E.periodMonth('2026-11-25'),'2026-11');
assert.equal(E.periodMonth('2026-11-26'),'2026-12');
assert.equal(E.periodMonth('2026-12-26'),'2027-01');
assert.deepEqual(E.totals([{status:'paid',amount_satang:50001},{status:'paid',amount_satang:100},{status:'voided',amount_satang:50000},{status:'approved',amount_satang:20000}]),{draft:0,approved:20000,paid:50101,cancelled:0,voided:50000});
assert.deepEqual(E.actions('draft','manager'),['edit','cancel']);
assert.deepEqual(E.actions('approved','manager'),['pay']);
assert.deepEqual(E.actions('paid','owner'),['void']);
assert.deepEqual(E.actions('paid','manager'),[]);
assert.deepEqual(E.actions('draft','outsider'),[]);
console.log('PASS: exact satang, bounds, period rollover, status totals and role actions');

});

test("RC2 regression on actual V8: attendance-engine",()=>{

const assert=require('node:assert/strict'),E=require('../v8/attendance-engine.js');
assert.deepEqual(E.calculate('06:30','21:00',false,120,480),{elapsed:870,work:750,normal:480,ot:270});
assert.deepEqual(E.calculate('06:30','15:30',false,60,480),{elapsed:540,work:480,normal:480,ot:0});
assert.deepEqual(E.calculate('22:00','06:00',true,60,420),{elapsed:480,work:420,normal:420,ot:0});
for(const args of [['22:00','06:00',false,0,0],['06:30','21:00',true,0,0],['24:00','07:00',false,0,0],['06:30','15:30',false,540,0],['06:30','15:30',false,60,481],['06:30','15:30',false,-1,0],['06:30','15:30',false,0.5,0]])assert.throws(()=>E.calculate(...args));
assert.equal(E.duration(750),'12 ชม. 30 นาที');
assert.equal(E.netMinutes('06:30','21:00',false,120),750);
console.log('PASS: single shift, full-day combined shift, overnight, invalid inputs, normal/OT split');

const slot={planned_start:'2026-11-26T06:30:00+07:00',planned_end:'2026-11-26T15:30:00+07:00',planned_break_minutes:60,planned_minutes:480};
assert.deepEqual(E.planDefaults([slot],'2026-11-26',Date.parse('2026-11-26T16:00:00+07:00')),{start:'06:30',end:'15:30',overnight:false,breakM:60,normalM:480,work:480,completed:true});
assert.equal(E.planDefaults([slot],'2026-11-26',Date.parse('2026-11-26T10:00:00+07:00')).completed,false);
assert.equal(E.planDefaults([slot,slot],'2026-11-26'),null);
assert.equal(E.planDefaults([],'2026-11-26'),null);
assert.equal(E.planDefaults([{...slot,planned_minutes:240}],'2026-11-26'),null);
assert.equal(E.completed('2026-11-26','15:30',false,Date.parse('2026-11-26T10:00:00+07:00')),false);
assert.equal(E.completed('2026-11-26','06:00',true,Date.parse('2026-11-27T06:00:00+07:00')),true);
console.log('PASS: planned shift prefill, future exit guard, multi-shift guard');

});

test("RC2 regression on actual V8: attendance-period-engine",()=>{
const assert=require('node:assert/strict');
const P=require('../v8/attendance-period-engine.js');
const now=Date.parse('2026-11-26T12:00:00+07:00');
assert.equal(P.periodMonth('2026-11-25'),'2026-11');
assert.equal(P.periodMonth('2026-11-26'),'2026-12');
assert.equal(P.periodMonth('2026-12-26'),'2027-01');
assert.equal(P.monthInput('11/2026'),'2026-11');
assert.throws(()=>P.monthInput('13/2026'));
assert.deepEqual(P.preset('double'),{kind:'work',start:'06:30',end:'21:00',overnight:false,breakM:120,normalM:480});
const r={...P.preset('morning'),day:'2026-11-25',employment:'e',schedule:'s',revision:0,status:'new',planCount:1,note:''};
assert.equal(P.payload(r,now).p_normal,480);
assert.equal(P.payload(r,now).p_break,60);
assert.throws(()=>P.payload({...r,day:'2026-11-26'},now));
assert.throws(()=>P.payload({...r,day:'2026-11-27'},now));
assert.throws(()=>P.payload({...r,planCount:0},now));
assert.throws(()=>P.payload({...r,kind:'off'},now));
assert.equal(P.payload({...r,kind:'off',planCount:0},now).p_start,null);
assert.throws(()=>P.payload({...r,kind:'leave',planCount:0},now));
assert.throws(()=>P.payload({...r,normalM:''},now));
assert.deepEqual(P.action(r,'verify'),['save','verify']);
assert.deepEqual(P.action({...r,status:'draft',dirty:false},'verify'),['verify']);
assert.deepEqual(P.action({...r,status:'draft',dirty:true},'verify'),['save','verify']);
assert.deepEqual(P.action({...r,status:'verified',dirty:false},'approve'),['approve']);
assert.throws(()=>P.action({...r,status:'approved'},'save'));
assert.throws(()=>P.action(r,'approve'));
const slot={planned_start:'2026-11-25T06:30:00+07:00',planned_end:'2026-11-25T15:30:00+07:00',planned_break_minutes:60,planned_minutes:480};
assert.equal(P.fromPlan([slot],'2026-11-25',now).start,'06:30');
assert.equal(P.fromPlan([slot,slot],'2026-11-25',now),null);
assert.equal(P.fromPlan([slot],'2026-11-25',Date.parse('2026-11-25T12:00:00+07:00')),null);
console.log('PASS period attendance worksheet rules');

});

test("RC2 regression on actual V8: calendar-engine",()=>{
const assert=require('node:assert/strict'),C=require('../v8/calendar-engine.js');
let w=C.weeks({start:'2026-11-26',end:'2026-12-25'});
assert.equal(w.length,5);assert.equal(w[0][3],'2026-11-26');assert.equal(w[4][4],'2026-12-25');assert.equal(w.flat().filter(Boolean).length,30);
w=C.weeks({start:'2028-02-26',end:'2028-03-25'});assert.equal(w.flat().filter(Boolean).length,29);assert.ok(w.flat().includes('2028-02-29'));
w=C.weeks({start:'2026-12-26',end:'2027-01-25'});assert.equal(w.flat().filter(Boolean).length,31);assert.equal(w.flat().filter(Boolean)[30],'2027-01-25');
assert.throws(()=>C.weeks({start:'2026-02-30',end:'2026-03-25'}));
assert.throws(()=>C.weeks({start:'2026-01-01',end:'2026-02-02'}));
const a={id:'a',work_date:'2026-11-26',planned_start:'2026-11-26T06:30:00+07:00'},b={id:'b',work_date:a.work_date,planned_start:'2026-11-26T12:00:00+07:00'};
assert.deepEqual(C.slotGroups([b,a]).get(a.work_date),[a,b]);assert.equal(C.personColor(null),0);assert.equal(C.personColor('employee'),C.personColor('employee'));assert.ok(C.personColor('employee')>=1&&C.personColor('employee')<=8);
console.log('PASS: period calendar, leap day, year boundary, sorting and stable colors');
});

test("RC2 regression on actual V8: payroll-engine",()=>{

const assert=require('node:assert/strict'),E=require('../v8/payroll-engine.js');
const row={attendance_id:'a',status:'approved',type:'work',rate_id:'r',base_rate:330,ot_rate:50,normal_minutes:480,ot_minutes:90};
assert.equal(E.parseAmount('500.01'),50001);
assert.equal(E.parseAmount('0'),0);
for(const v of ['','-1','1.001','1e3','10000000.01'])assert.throws(()=>E.parseAmount(v));
assert.equal(E.summarize({pay_type:'daily',days:[row]}).base,33000);
assert.equal(E.summarize({pay_type:'daily',days:[row]}).ot,7500);
assert.equal(E.summarize({pay_type:'daily',days:[{...row,normal_minutes:210}]}).base,null);
assert.equal(E.summarize({pay_type:'hourly',days:[{...row,base_rate:60,normal_minutes:210}]}).base,21000);
assert.equal(E.summarize({pay_type:'monthly',days:[row]}).base,null);
assert.equal(E.summarize({pay_type:'daily',days:[{...row,rate_id:null}]}).ot,null);
assert.equal(E.summarize({pay_type:'daily',days:[{date:'2026-11-26'}]}).missing,1);
assert.equal(E.summarize({pay_type:'daily',days:[{...row,status:'draft'}]}).unapproved,1);
assert.equal(E.net({base:33000,ot:7500,otherIncome:100,advance:10000,otherDeduction:100}),30500);
assert.equal(E.canonical({b:2,a:1}),E.canonical({a:1,b:2}));
console.log('PASS: provisional daily/hourly/OT, missing sources, exact satang and draft net');

const known=E.knownAmounts({pay_type:'daily',days:[row,{...row,base_rate:360,ot_rate:70,ot_minutes:270},{...row,normal_minutes:240,ot_minutes:0},{...row,status:'draft'},{status:'approved',type:'leave'}]});
assert.equal(known.base,69000);
assert.equal(known.ot,39000);
assert.equal(known.baseManualDays,2);
assert.equal(known.workDays,3);
assert.equal(E.knownAmounts({pay_type:'monthly',days:[row]}).base,0);
assert.equal(E.knownAmounts({pay_type:'hourly',days:[{...row,base_rate:60,normal_minutes:210}]}).base,21000);
const items=Object.fromEntries(E.keys.map(k=>[k,0]));Object.assign(items,{base:800000,ot:72000,attendance_bonus:50000,advance:100000,social_security:20000,tax:1000,paid_leave:40000});
assert.equal(E.net(E.aggregate(items)),841000);
assert.throws(()=>E.aggregate({...items,tax:-1}));
console.log('PASS: mixed effective rates, exceptions, manual categories');

});

test("RC2 regression on actual V8: schedule-engine",()=>{

const assert=require('node:assert/strict'),E=require('../v8/schedule-engine.js');
assert.deepEqual(E.period('2026-12'),{start:'2026-11-26',end:'2026-12-25'});
assert.deepEqual(E.period('2027-01'),{start:'2026-12-26',end:'2027-01-25'});
assert.equal(E.daysIn(E.period('2024-03')).length,29);
const jobs=['a','b','c'].map(id=>({id,employee_id:id,code:id,start_date:'2026-11-26',end_date:null,employment_type:'daily',compensation_history:[{effective_from:'2026-11-26',base_rate:350}]}));
const days=E.daysIn(E.period('2026-12'));
const rows=days.flatMap(d=>[0,1].map(i=>({id:d+'-'+i,work_date:d,planned_start:d+(i?'T05:00:00Z':'T00:00:00Z'),planned_end:d+(i?'T14:00:00Z':'T08:00:00Z'),planned_minutes:480,is_extra:false,is_locked:false,employment_id:null})));
rows[0].is_locked=true;rows[0].employment_id='a';
const prefs={b:{off_days:[],leave_dates:['2026-11-26']}};
const result=E.autoSchedule(rows,jobs,prefs,'3',['a','b','c']);
assert.equal(result.rows[0].employment_id,'a');
assert.notEqual(result.rows[1].employment_id,'b');
assert.equal(E.warnings(result.rows,jobs,prefs).overlap.length,0);
assert.equal(E.warnings(result.rows,jobs,prefs).rest.length,0);
assert.equal(E.warnings(result.rows,jobs,prefs).fatigue.length,0);
assert.equal(rows[1].employment_id,null);
const balance=E.autoSchedule(rows,jobs,{},'balance',['a','b','c']);
assert.equal(balance.metric,'estimated-pay');
assert.equal(E.autoSchedule(rows,[{...jobs[0],compensation_history:[]},...jobs.slice(1)],{},'balance',['a','b','c']).metric,'minutes');
assert.throws(()=>E.autoSchedule(rows,jobs,{},'2',['a']));
assert.equal(E.eligible({...jobs[0],end_date:'2026-11-27'},'2026-11-28'),false);
console.log('PASS: period, eligibility, locked shift, leave, overlap, rest, fatigue, rotation, balance fallback');

});

test("RC2 regression on actual V8: staff-dates",()=>{
const assert=require('node:assert/strict');
const {parseDate,displayDate,bangkokToday,ratesFor}=require('../v8/staff-dates.js');
assert.equal(parseDate('26/11/2026'),'2026-11-26');
assert.equal(parseDate('01/12/2026'),'2026-12-01');
assert.equal(parseDate('29/02/2024'),'2024-02-29');
for(const x of ['31/02/2026','29/02/2026','11/26/2026','26/11/2569','2026-11-26','1/1/2026',''])assert.throws(()=>parseDate(x));
assert.equal(displayDate('2026-01-11'),'11/01/2026');
assert.equal(bangkokToday(new Date('2026-11-25T17:00:00Z')),'2026-11-26');
const job={compensation_history:[{id:'future',effective_from:'2026-12-01'},{id:'old',effective_from:'2026-01-11'},{id:'now',effective_from:'2026-11-26'}]};
assert.equal(ratesFor(job,'2026-11-26').current.id,'now');
assert.equal(ratesFor(job,'2026-11-26').future[0].id,'future');
assert.equal(ratesFor(job,'2025-12-31').current,null);
assert.equal(ratesFor({},'2026-11-26').current,null);
assert.equal(job.compensation_history[1].id,'old');
console.log('PASS: dates, Bangkok timezone, rate selection, history preservation');

});
