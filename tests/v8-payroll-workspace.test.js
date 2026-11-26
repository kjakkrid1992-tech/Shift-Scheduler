const assert=require('node:assert/strict');const E=require('../v8/payroll-engine.js');
const source={pay_type:'daily',as_of:'2026-11-25',period_end:'2026-11-25',days:[{attendance_id:'a',status:'approved',type:'work',rate_id:'r',base_rate:330,ot_rate:50,normal_minutes:480,ot_minutes:270}]};
assert.deepEqual(E.completeSuggestions(source),{base:33000,ot:22500});
assert.deepEqual(E.completeSuggestions({...source,pay_type:'monthly'}),{ot:22500});
assert.deepEqual(E.completeSuggestions({...source,as_of:'2026-11-24'}),{});
assert.deepEqual(E.completeSuggestions({...source,days:[{type:'work'}]}),{});
assert.deepEqual(E.completeSuggestions({...source,days:[...source.days,{attendance_id:'b',status:'approved',type:'leave'}]}),{ot:22500});
console.log('PASS complete-only payroll suggestions');
