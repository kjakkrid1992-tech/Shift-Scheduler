
const assert=require('node:assert/strict'),E=require('../v2/attendance-engine.js');
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
