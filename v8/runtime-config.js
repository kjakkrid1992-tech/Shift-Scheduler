(function(root){
'use strict';
const storageKey='baanjergun-v8-public-config';
function anonKey(k){try{const parts=k.split('.');if(parts.length!==3||parts.some(x=>!/^[A-Za-z0-9_-]+$/.test(x)))return false;const b=parts[1].replace(/-/g,'+').replace(/_/g,'/');return JSON.parse(atob(b.padEnd(Math.ceil(b.length/4)*4,'='))).role==='anon'}catch{return false}}
function normalizeConfig(raw){
 if(!raw||typeof raw.url!=='string'||typeof raw.publishableKey!=='string')throw Error('ระบุ URL และ public key');
 const url=raw.url.trim().replace(/\/$/,''),key=raw.publishableKey.trim();
 const local=/^http:\/\/(?:127\.0\.0\.1|localhost):54321$/.test(url),hosted=/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(url);
 if(!local&&!hosted)throw Error('รองรับ Supabase local (127.0.0.1:54321) หรือ HTTPS Project URL เท่านั้น');
 if(!/^sb_publishable_[A-Za-z0-9_-]+$/.test(key)&&!(local&&anonKey(key)))throw Error('ใช้ publishable key เท่านั้น (local ใช้ anon JWT ได้) ห้ามใช้ secret/service_role');
 return {url,publishableKey:key,local};
}
function resolveConfig(storage,fallback){if(fallback?.localOnly===true){try{const c=normalizeConfig(fallback);return c.local?c:null}catch{return null}}let raw;try{raw=storage?.getItem(storageKey)}catch{}if(raw){try{return normalizeConfig(JSON.parse(raw))}catch{}}try{return normalizeConfig(fallback)}catch{return null}}
function saveConfig(storage,raw){const c=normalizeConfig(raw);storage.setItem(storageKey,JSON.stringify({url:c.url,publishableKey:c.publishableKey}));return c}
function validateBatchReply(result,expected,identity){
 if(!Array.isArray(result)||result.length!==expected.length)throw Error('ผลตอบกลับไม่ครบ — ตรวจข้อมูลที่เซิร์ฟเวอร์ก่อนส่งซ้ำ');
 const index=new Map();for(const z of result){if(!z||typeof z!=='object')throw Error('ผลตอบกลับผิดรูปแบบ');const k=identity(z);if(index.has(k)||typeof z.id!=='string'||!z.id||!Number.isSafeInteger(z.revision)||z.revision<1)throw Error('ผลตอบกลับผิดรูปแบบ — ตรวจข้อมูลที่เซิร์ฟเวอร์ก่อนส่งซ้ำ');index.set(k,z)}
 for(const e of expected){const z=index.get(identity(e));if(!z||z.revision!==e.revision||(e.status&&z.status!==e.status)||(e.id&&z.id!==e.id))throw Error('ผลตอบกลับไม่ตรงรายการ — ตรวจข้อมูลที่เซิร์ฟเวอร์ก่อนส่งซ้ำ')}
 return index
}
const api={storageKey,normalizeConfig,resolveConfig,saveConfig,validateBatchReply};
if(typeof module==='object'&&module.exports)module.exports=api;else root.V8Runtime=Object.freeze(api);
})(globalThis);
