
# Shift Scheduler V2 — Phase 1 Foundation

สถานะ: Phase 1 pilot เชื่อม Supabase และทดสอบ Owner/Manager บน test project แล้ว; ยังไม่ใช่ Production
Branch: development-v2. หน้าเดิม index.html และ LocalStorage เดิมไม่ถูกแก้ไข
หน้า V2: v2/index.html (แยกจาก production)

## ทำอะไรแล้ว
- Supabase/PostgreSQL migration 9 ตาราง: user_profiles, departments, employees, employment_records, compensation_history, wage_rules, shift_templates, company_settings, audit_logs.
- Auth email/password, ไม่มี sign-up ในแอป; ต้องปิด sign-up ที่ Supabase Dashboard ด้วย
- Employee master: เพิ่ม/ค้นหา/กรอง/แก้ข้อมูลทั่วไป; เก็บสถานะทดลองงาน/ทำงาน/ลาออก/จ้างใหม่
- Owner เพิ่มเรทใหม่และสิ้นสุดการจ้าง; Manager ดูประวัติและจัดการทะเบียน แต่เพิ่มเรท/ปิดการจ้างไม่ได้
- RLS + column grants, ไม่มี delete จาก browser, audit log ไม่เก็บค่า PII แบบซ้ำ, unique/exclusion constraints.
- เรทเก็บแบบ append-only; ใช้เรทล่าสุดที่ effective_from <= วันที่ทำงานในอนาคต.
- Settings, wage rules, shift templates มี schema เท่านั้น; ยังไม่มีหน้า Settings.
- ยังไม่รวมตารางกะจริง, attendance, payroll, bank details, Excel migration, backup automation; ไม่ใช้ข้อมูลจริง.

## Setup สำหรับเจ้าของ (ทดสอบบน project ใหม่ก่อน)
1. สร้าง project แยกใน https://supabase.com/dashboard ; เก็บ DB password ไว้เอง ไม่ส่งทางแชทหรือ GitHub.
2. ใน SQL Editor รันไฟล์ supabase/migrations/20261126000100_foundation.sql ครั้งเดียว (หรือผ่าน Supabase CLI migrations บน project ใหม่).
   จากนั้นรัน supabase/migrations/20261126000200_compensation_role_guard.sql ตามลำดับ (สำหรับฐานเดิมที่ติดตั้ง patch แล้วไม่ต้องรันซ้ำ).
3. เปิด Data API ให้ expose public schema (ห้าม expose staff_private).
4. Authentication: ปิด Allow new users to sign up; สร้างบัญชี Owner และ Manager ใน Authentication > Users โดยตั้ง password ผ่าน Dashboard โดยตรง; เปิด/ยืนยัน email ตามนโยบาย.
5. คัดลอก UUID จาก Authentication > Users แล้วรัน SQL นี้โดยแทนค่า placeholder ด้วย UUID จริงใน SQL Editor เท่านั้น:
```sql
insert into public.user_profiles(user_id,display_name,role)
values ('OWNER_UUID','Owner','owner'),('MANAGER_UUID','Manager','manager');
```
หากมีเจ้าของคนเดียวให้ insert แถวเดียวก่อน. การปิดสิทธิ์: update public.user_profiles set active=false where user_id='UUID'; ผ่าน SQL Editor. ห้ามใส่ UUID จริงหรือ email/password ใน repo.
6. ใน Project Settings / Connect คัดลอก Project URL (https://...supabase.co) และ **sb_publishable_...** key. กำหนดใน v2/config.js:
```js
window.STAFF_CONFIG = { url: "https://YOUR-PROJECT.supabase.co", publishableKey: "sb_publishable_YOUR_KEY" };
```
Publishable key เป็นคีย์ browser ที่ตั้งใจให้เปิดเผยได้เมื่อ RLS ถูกต้อง; ห้ามใช้ sb_secret_ หรือ service_role key. ตัวอย่างไฟล์ commit เป็นค่าว่าง.
7. ทดสอบโดย checkout branch แล้ว serve ด้วย python -m http.server 8000 ที่ repo root เปิด http://localhost:8000/v2/ ; ไม่เปิดด้วย file://. ยังไม่ merge main หรือเปลี่ยน GitHub Pages.
8. รัน supabase/tests/foundation.sql ใน SQL Editor ของ test project (transaction rollback). ต้องได้ผลผ่านทั้งหมดก่อนใช้ข้อมูลจริง. ทดสอบ UI ด้วย owner/manager และบัญชีที่ไม่มี profile ตาม checklist.
9. ก่อน production: ทดสอบ RLS ด้วย API จริงทุก role, pin/review SDK, ตั้ง MFA/การกู้บัญชี, backup/restore, review PDPA, deploy preview แบบแยก. ไม่มี credential สำหรับทดสอบ remote ในงานนี้.

## Manual acceptance
- owner และ manager login ได้; บัญชีที่ไม่มี active profile อ่าน employee API ไม่ได้.
- เพิ่ม EMP-TEST-001 ด้วยชื่อสมมติ + การจ้าง; รหัสซ้ำและช่วงจ้างซ้อนต้องถูกปฏิเสธ.
- owner เพิ่มเรทวันที่ต่างกัน 2 ครั้ง; history เดิมยังอยู่; manager ถูกปฏิเสธการเพิ่มแม้เรียก API โดยตรง.
- owner ปิดการจ้าง; ประวัติยังค้นได้; จ้างใหม่โดยใช้ employee_id เดิม; วันที่เริ่มใหม่ต้องไม่ทับวันสิ้นสุดเดิม.
- logout เคลียร์ข้อมูล UI; session ไม่ persist เมื่อ reload; หน้าเดิมไม่เปลี่ยน.
- ยังไม่ migrate Excel; ห้ามกรอกข้อมูลจริงบน test project.
- ตรวจสิทธิ์ทุก table และ audit log; ตรวจว่าการเปลี่ยนเรทพร้อมกันไม่สร้างวันที่ซ้ำ.
- ปัจจุบัน audit เก็บชื่อ field ที่เปลี่ยน ไม่เก็บ before/after value; ต้องพัฒนาเพิ่มก่อนใช้ production ตามนโยบาย.

## Decisions / known limits
Single company; owner/manager เห็นข้อมูลค่าแรงเพื่อทำงานตาม workflow. ยังไม่รองรับหลายแผนกแบบจำกัดสิทธิ์รายแผนก. ข้อมูลบัญชีธนาคารเลื่อนไป Phase Payroll เพื่อออกแบบสิทธิ์แยก. Department seed เป็นตัวอย่างให้เปลี่ยนใน SQL Editor. ค่าแรงไม่ seed เพราะต้องยืนยันตามนโยบาย/กฎหมาย. รอบ 26–25 และกะเช้า/บ่ายเป็น draft จากระบบเดิม ไม่ใช่กฎ payroll ที่อนุมัติแล้ว. ประวัติเรทเป็น append-only; กรณีแก้เรทที่ผิดหรือต้อง backfill ให้ใช้กระบวนการ correction ที่จะออกแบบใน payroll/migration phase. ห้ามแก้ประวัติด้วยมือใน production. การย้ายงาน/เปลี่ยนประเภทจ้างต้องเพิ่ม workflow ที่รักษาประวัติในเฟสถัดไป.

## References
- https://supabase.com/docs/guides/database/postgres/row-level-security
- https://supabase.com/docs/guides/getting-started/api-keys
- https://supabase.com/docs/guides/database/functions
