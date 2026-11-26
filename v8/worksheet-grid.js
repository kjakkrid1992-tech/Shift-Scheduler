(function(root){
'use strict';
const E=typeof module==='object'&&module.exports?require('./attendance-engine.js'):root.AttendanceEngine;
const fields=['kind','start','end','overnight','breakM','normalM','note'];
const kinds={work:'work','ทำงาน':'work','ทำงานจริง':'work',off:'off','หยุด':'off',leave:'leave','ลา':'leave',holiday:'holiday','วันหยุด':'holiday',absent:'absent','ขาดงาน':'absent'};
function parse(field,raw){
 const s=String(raw).trim();
 if(field==='kind'){if(!s)return '';if(!Object.prototype.hasOwnProperty.call(kinds,s))throw Error('ประเภทวันไม่ถูกต้อง: '+s);return kinds[s]}
 if(field==='start'||field==='end'){if(!s)return '';const m=/^(\d{1,2}):([0-5]\d)(?::00)?$/.exec(s);if(!m||+m[1]>23)throw Error('เวลาไม่ถูกต้อง: '+s);return m[1].padStart(2,'0')+':'+m[2]}
 if(field==='overnight'){if(['1','true','ใช่','ข้ามวัน'].includes(s.toLowerCase()))return true;if(['','0','false','ไม่'].includes(s.toLowerCase()))return false;throw Error('ข้ามวันต้องเป็น 1 หรือ 0')}
 if(field==='breakM'||field==='normalM'){if(!s)return '';if(!/^\d{1,4}$/.test(s)||Number(s)>1440)throw Error('จำนวนนาทีไม่ถูกต้อง: '+s);return Number(s)}
 if(field==='note'){if(s.length>1000)throw Error('หมายเหตุยาวเกิน 1,000 ตัวอักษร');return s}
 throw Error('ไม่รองรับคอลัมน์');
}
function stagePaste(rows,index,field,text,canEdit){
 if(typeof text!=='string'||!text.trim()||text.length>250000)throw Error('ไม่มีข้อมูลหรือข้อมูลยาวเกินขอบเขต');
 const start=fields.indexOf(field);if(start<0||!Number.isInteger(index)||index<0)throw Error('เลือกเซลล์ก่อนวาง');
 const lines=text.replace(/\r\n/g,'\n').replace(/\r/g,'\n').replace(/\n$/,'').split('\n');
 if(lines.length>200||index+lines.length>rows.length)throw Error('ข้อมูลเกินจำนวนแถวที่แสดง');
 return lines.map((line,i)=>{
  const row=rows[index+i],cells=line.split('\t');if(!canEdit(row))throw Error('แถว '+(i+1)+' ถูกล็อก');
  if(cells.length+start>fields.length)throw Error('ข้อมูลเกินคอลัมน์ที่แก้ไขได้');
  if(cells.some(c=>c.startsWith('"')&&c.endsWith('"')))throw Error('ไม่รองรับ Excel cell ที่มีอักขระพิเศษแบบ quoted; ใช้ข้อความธรรมดา');
  const patch={},next={...row};for(let k=0;k<cells.length;k++){const name=fields[start+k];patch[name]=parse(name,cells[k]);next[name]=patch[name]}
  if(!next.kind&&(next.start||next.end))patch.kind=next.kind='work';
  if(next.kind==='work'&&row.kind&&row.kind!=='work'){if(!('breakM' in patch))patch.breakM=next.breakM='';if(!('normalM' in patch))patch.normalM=next.normalM='';patch.manualNormal=false;next.manualNormal=false}
  if(next.kind!=='work'&&['start','end','overnight','breakM','normalM'].some(k=>Object.prototype.hasOwnProperty.call(patch,k)&&patch[k]!==''&&patch[k]!==0&&patch[k]!==false))throw Error('แถว '+(i+1)+' ไม่ใช่วันทำงาน');
  if(next.kind&&next.kind!=='work'){Object.assign(patch,{start:'',end:'',overnight:false,breakM:0,normalM:0,manualNormal:false})}
  else if(Object.prototype.hasOwnProperty.call(patch,'normalM'))patch.manualNormal=true;
  else if(!next.manualNormal&&['start','end','overnight','breakM'].some(k=>k in patch)){try{if(String(next.breakM).trim()!=='')patch.normalM=Math.min(480,E.netMinutes(next.start,next.end,!!next.overnight,Number(next.breakM)))}catch{patch.normalM=''}}
  return {row,patch};
 });
}
const api={fields,parse,stagePaste};if(typeof module==='object'&&module.exports)module.exports=api;else root.V8Worksheet=Object.freeze(api);
})(globalThis);
