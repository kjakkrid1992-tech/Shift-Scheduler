
const assert=require('node:assert/strict'),E=require('../v2/advance-engine.js');
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
