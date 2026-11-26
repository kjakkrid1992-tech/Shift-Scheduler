
const assert=require('node:assert/strict'),E=require('../v2/payroll-engine.js');
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
