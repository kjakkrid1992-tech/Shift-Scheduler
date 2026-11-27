# V8 FREE — วิธีเปิดใช้งานและตรวจสอบในเครื่อง
**ไม่มีการสร้าง Supabase Cloud project/branch ใหม่ และไม่รัน GitHub-hosted Actions ในสาย development-v8**

## เปิด V8 บนเครื่อง Windows
ติดตั้ง Node.js LTS, Supabase CLI (standalone executable รุ่นที่รองรับ db query --local) และ Docker-compatible runtime ที่รันอยู่บนเครื่องเท่านั้น เช่น Docker Engine บน WSL2 หรือ Docker Desktop หากมีสิทธิ์ใช้งานฟรีตามเงื่อนไขไลเซนส์ของคุณ ไม่ต้องซื้อบริการใด ๆ หากมีเครื่องมือครบแล้วให้เปิดไฟล์ START-V8-LOCAL.cmd หรือใช้:
```
node scripts/start-v8-local.cjs
```
หากพื้นที่ดิสก์หรือ RAM จำกัด ใช้ `node scripts/start-v8-local.cjs --core-only` หรือ `START-V8-LOCAL.cmd --core-only` จาก Command Prompt โหมดนี้เปิด PostgreSQL, Supabase Auth และ Data API สำหรับใช้งาน V8 โดยข้าม Studio และบริการเสริม หากต้องการสลับโหมด ให้ปิดเว็บด้วย Ctrl+C รัน `supabase stop` ในโฟลเดอร์ `local-v8-runtime` แล้วเปิดด้วยคำสั่งของโหมดที่ต้องการ ข้อมูล local จะยังอยู่

โปรแกรมสร้างพื้นที่ local-v8-runtime/ ที่ไม่เชื่อมกับ Cloud, ใช้ Migration ใน Git, ปิด public signup, สร้างบัญชีทดสอบ local Owner/Manager (รหัสผ่านสุ่มแสดงครั้งแรกใน Terminal เท่านั้น), ใช้ SDK ที่ติดตั้งในเครื่อง และเปิด http://127.0.0.1:5501/v8/ . ไม่มีการนำเข้าพนักงานจริงหรือเขียนข้อมูล Supabase เดิม ตัวเว็บโหมดนี้ไม่รับการเปลี่ยน URL เป็น Cloud แม้เบราว์เซอร์เคยเก็บค่าไว้
หากสร้าง local account แล้ว ให้ใช้รหัสเดิมครั้งถัดไป; ไม่รีเซ็ตรหัสผ่านหรือข้อมูลโดยอัตโนมัติ ใช้ Supabase Studio **local** สำหรับจัดการบัญชีถ้าจำเป็น หาก CLI/Docker ไม่ตรงข้อกำหนด สคริปต์หยุดโดยไม่เปลี่ยน Cloud อย่าเปิดพอร์ตฐานข้อมูล/Studio ออกอินเทอร์เน็ต ให้ใช้เฉพาะเครื่องตนเอง ปิดหรือจำกัด firewall inbound ตามคู่มือ local stack

## การตรวจสอบฟรี
```
node scripts/test-v8-local.cjs
node scripts/test-v8-local.cjs --full
```
คำสั่งแรกตรวจ JavaScript ทุกชุดและ syntax โดยไม่ต้องมีฐานข้อมูล คำสั่งที่สองใช้ Docker engine บนเครื่องสร้าง PostgreSQL ชั่วคราวที่ไม่เปิดพอร์ต ทดสอบ migration ทุกไฟล์, SQL suites, Python converter, Chromium (Chrome/Edge ที่ติดตั้งอยู่), แล้วลบเฉพาะ container ทดสอบนั้น ไม่ต้องใช้ GitHub Actions ไม่เชื่อม Supabase จริง ต้องมี Python 3 สำหรับ converter; npm/pip ใช้แพ็กเกจ open-source ตามเวอร์ชันที่กำหนด
เอกสาร workflow เดิมถูกเก็บไว้เป็นหลักฐานใน docs/previous-v8-ci.yml ไม่ใช่ workflow ที่ GitHub รันได้จาก branch นี้

## ใช้ Supabase Cloud โครงการเดิม
ไม่ต้องสร้าง Cloud project/branch ใหม่ หากโครงการเดิมอยู่ใน Free plan และไม่เกินโควตา ใช้ต่อได้หลังตรวจ migration, backup/restore และกระทบยอดจริง **V8 ยังไม่เปิดให้เขียนกับ RC2-only database**. เมื่อพร้อมและได้รับการตรวจรับจึงใช้ Migration 01500 ที่มีอยู่ (ห้าม reset/drop schema) แล้วเปิด v8/index.html ผ่าน Live Server; หน้าตั้งค่ารับ HTTPS URL และ publishable key เท่านั้น ไม่มี service-role/secret ในเว็บ
การสำรอง/กู้คืนและการยืนยันค่าแรง วันลา OT ภาษี ประกันสังคม ยังเป็นเงื่อนไขก่อนใช้งานเงินจริง
