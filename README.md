# Shift Scheduler + OT (v4) — Drag & Drop + Pay Slip (Thai)

**โฟกัส:** ร้านเล็ก/พนักงาน 2 คน + ผู้จัดการสำรอง, ใช้งานบนมือถือได้, ไม่มี Dependency ภายนอก (ไฟล์เดียวรันได้เลย)

## ฟีเจอร์หลัก
- ปฏิทินรายเดือนสไตล์ Homebase/When I Work
- **ลาก–วางกะ** Off / S1 / S2 / Full ลงชื่อ A/B/M ในแต่ละวัน
- **Emergency Off**: แตะชิปเพื่อให้ Off และผูกอีกคนเป็น Full อัตโนมัติ
- **Auto** แจกวันหยุดคนละ 4 วัน พร้อมผูก Full ให้อีกคน
- **Drawer รายวัน**: บันทึกหมายเหตุ, ปรับกะละเอียด
- **สรุปแบบไม่ใช้เงิน**: วันทำงาน/Off/S1/S2/Full, ชั่วโมงรวม, OT รวม, ความครอบคลุม
- **Pay Slip (อ้างอิง)**: สรุปเวลา + ช่องกรอก Allowance/Deduction + Export CSV/Print
- **บันทึก/โหลด** ด้วย `localStorage` บนเบราว์เซอร์

> หมายเหตุ: ตัวเลขด้านค่าจ้าง/OT ถูก “ซ่อนในโค้ด” เพื่อใช้คำนวณสลิปอ้างอิงเท่านั้น ไม่แสดงในหน้า UI ปกติ

## โครงสร้างไฟล์
```
.
├─ index.html          # แอปหลัก (ไฟล์เดียว)
├─ README.md
└─ LICENSE             # MIT License
```

## วิธีใช้งานแบบเร็ว
1. เปิดไฟล์ `index.html` ใน Chrome/Edge/Firefox/ Safari ได้ทันที
2. กด **Auto** เพื่อกระจายวันหยุดและตั้งกะเริ่มต้น
3. ลาก–วางจากแถบด้านบน (Off/S1/S2/Full) ไปยังชิปของ A/B/M
4. ใช้สวิตช์ **Emergency Off** เมื่อต้องการแทนกะฉุกเฉิน
5. ปุ่ม **Pay Slip** สำหรับตัวอย่างสลิป (Export CSV / Print)

## Deploy ขึ้น GitHub Pages
### วิธี A: หน้าเว็บ GUI
1. สร้าง repo ใหม่ใน GitHub (Public/Private ก็ได้)
2. อัปโหลดไฟล์ `index.html`, `README.md`, `LICENSE` เข้า repository
3. ไปที่ **Settings → Pages**  
   - **Source**: เลือก **Deploy from a branch**  
   - **Branch**: `main` / `/root` (โฟลเดอร์) → กด Save
4. รอสักครู่ แล้วเปิด URL:  
   `https://<USERNAME>.github.io/<REPO>/`

### วิธี B: Git CLI
```bash
git init
git add .
git commit -m "Add shift scheduler v4"
git branch -M main
git remote add origin https://github.com/<USERNAME>/<REPO>.git
git push -u origin main
# เปิด Settings → Pages ตั้งค่าเหมือนด้านบน
```

## ความเป็นส่วนตัว/ข้อมูล
- แอปนี้เก็บข้อมูลตารางบน **localStorage** ในเบราว์เซอร์ของผู้ใช้เท่านั้น (ไม่ส่งออกอัตโนมัติ)
- ถ้าเปิดบนหลายเครื่อง/หลายโดเมน ข้อมูลจะไม่แชร์กัน ต้องใช้ปุ่ม **Export CSV** เพื่อนำไปที่อื่น

## เบราว์เซอร์ที่รองรับ
- Chrome/Edge/Firefox ล่าสุด, iOS Safari 15+ / Android Chrome

## ปรับแต่ง
- เปลี่ยนชื่อ/ตำแหน่ง/กะ/ชั่วโมง Full ได้ในโค้ด (ส่วน CONFIG ด้านบน `<script>`)
- ถ้าต้องการแยก CSS/JS ออกเป็นไฟล์เฉพาะ ให้คัดย้ายสไตล์/สคริปต์จาก `index.html` ไปไว้ในโฟลเดอร์ `assets/`

---

© 2025 — Licensed under MIT (ดูไฟล์ LICENSE)
