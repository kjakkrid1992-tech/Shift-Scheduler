/* Date-only values: Gregorian DD/MM/YYYY in UI, ISO in database. */
(function(root){
  'use strict';
  function parseDate(value){
    const m=/^(\d{2})\/(\d{2})\/(\d{4})$/.exec(String(value||'').trim());
    if(!m) throw new Error('กรุณากรอกวันที่ DD/MM/YYYY (ค.ศ.) เช่น 26/11/2026');
    const d=Number(m[1]),mo=Number(m[2]),y=Number(m[3]);
    if(y<1900||y>2199||mo<1||mo>12||d<1||d>new Date(Date.UTC(y,mo,0)).getUTCDate())
      throw new Error('วันที่ไม่ถูกต้อง กรุณาใช้ DD/MM/YYYY และปี ค.ศ. 1900–2199');
    return m[3]+'-'+m[2]+'-'+m[1];
  }
  function displayDate(iso){if(!iso)return '';const m=/^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);return m?m[3]+'/'+m[2]+'/'+m[1]:String(iso)}
  function bangkokToday(now=new Date()){
    const parts=new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Bangkok',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(now);
    const p=Object.fromEntries(parts.map(x=>[x.type,x.value]));return p.year+'-'+p.month+'-'+p.day;
  }
  function ratesFor(job,day){
    const rates=[...(job?.compensation_history||[])].sort((a,b)=>b.effective_from.localeCompare(a.effective_from));
    return {rates,current:rates.find(r=>r.effective_from<=day)||null,future:rates.filter(r=>r.effective_from>day).reverse()};
  }
  const api={parseDate,displayDate,bangkokToday,ratesFor};
  if(typeof module==='object'&&module.exports)module.exports=api;else root.StaffDates=Object.freeze(api);
})(globalThis);
