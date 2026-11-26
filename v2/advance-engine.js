(function(root){
'use strict';
function parseAmount(value){
 const s=String(value??'').trim();
 if(!/^[0-9]{1,7}(?:\.[0-9]{1,2})?$/.test(s))throw Error('กรอกจำนวนเงินเป็นบาท ทศนิยมไม่เกิน 2 ตำแหน่ง');
 const [whole,fraction='']=s.split('.');
 const cents=Number(whole)*100+Number(fraction.padEnd(2,'0'));
 if(cents<1||cents>100000000)throw Error('จำนวนเงินต้องอยู่ระหว่าง 0.01–1,000,000 บาท');
 return cents
}
function money(cents){return (Number(cents)/100).toLocaleString('th-TH',{minimumFractionDigits:2,maximumFractionDigits:2})}
function periodMonth(day){if(!/^\d{4}-\d{2}-\d{2}$/.test(day))throw Error('Invalid date');const [y,m,d]=day.split('-').map(Number);return d>=26?new Date(Date.UTC(y,m,1)).toISOString().slice(0,7):day.slice(0,7)}
function totals(rows){const out={draft:0,approved:0,paid:0,cancelled:0,voided:0};for(const r of rows){if(Object.hasOwn(out,r.status))out[r.status]+=Number(r.amount_satang)}return out}
function actions(status,role){if(!['owner','manager'].includes(role))return [];if(status==='draft')return role==='owner'?['edit','approve','cancel']:['edit','cancel'];if(status==='approved')return role==='owner'?['pay','cancel']:['pay'];if(status==='paid'&&role==='owner')return ['void'];return []}
const api={parseAmount,money,periodMonth,totals,actions};if(typeof module==='object'&&module.exports)module.exports=api;else root.AdvanceEngine=Object.freeze(api)
})(globalThis);
