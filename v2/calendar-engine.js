(function(root){
'use strict';
function date(d){if(!/^\d{4}-\d{2}-\d{2}$/.test(d))throw Error('Invalid date');const t=new Date(d+'T00:00:00Z');if(!Number.isFinite(+t)||t.toISOString().slice(0,10)!==d)throw Error('Invalid date');return t}
function weeks(range){const start=date(range.start),end=date(range.end);const count=(end-start)/86400000+1;if(count<1||count>31)throw Error('Invalid payroll calendar range');const out=Array((start.getUTCDay()+6)%7).fill(null);for(let i=0;i<count;i++)out.push(new Date(+start+i*86400000).toISOString().slice(0,10));while(out.length%7)out.push(null);return Array.from({length:out.length/7},(_,i)=>out.slice(i*7,i*7+7))}
function slotGroups(rows){const result=new Map();for(const r of rows){if(!result.has(r.work_date))result.set(r.work_date,[]);result.get(r.work_date).push(r)}for(const list of result.values())list.sort((a,b)=>a.planned_start.localeCompare(b.planned_start)||a.id.localeCompare(b.id));return result}
function personColor(id){if(!id)return 0;let hash=0;for(const c of id)hash=(Math.imul(hash,31)+c.charCodeAt(0))>>>0;return 1+hash%8}
const api={weeks,slotGroups,personColor};if(typeof module==='object'&&module.exports)module.exports=api;else root.CalendarEngine=Object.freeze(api)
})(globalThis);
