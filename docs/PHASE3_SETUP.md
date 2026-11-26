
# Phase 3 — Attendance pilot
Apply 20261126000500_attendance.sql once after 00400. Adds attendance_records and attendance_revisions (14 business tables total). No existing data changed.
Run supabase/tests/attendance.sql on isolated test project (rollback). Then download development-v2 and open v2/ as before. No new credentials.
## Workflow
1. Confirm Phase 2 schedule for department/period. Open ลงเวลาจริง, select day not in future and department, load.
2. All eligible employees shown including off/unplanned; assigned employees with historical eligibility discrepancies also visible for review. New records require latest confirmed plan; existing rows keep original plan snapshot. A new confirmed schedule never overwrites saved actuals.
3. Enter actual paper-card time HH:MM, next-day flag, aggregate breaks; enter normal minutes reviewed by manager. Suggested 480 minutes is a convenience, not law or payroll policy. OT minutes are the residual. Work interval must be completed and no longer than 24h; no overlap across actual days for same employment.
4. Non-work types off/leave/holiday/absent have zero work minutes; required notes for exceptions or unplanned work. No paid-leave or day-credit inference.
5. Save draft, verify (owner/manager), approve (owner). Verified records must be reopened before editing; manager may reopen verified, owner only approved. Reason required. Every revision is recorded; optimistic revision prevents stale saves. No browser direct writes.
6. Test Manager cannot approve; Owner approves and reopen retains history. Use synthetic data only. Schedule versioning tested in SQL; latest confirmed version used when opening new actuals.
## Known limits / decisions
- One continuous interval minus total breaks per employment/day. Split sessions/missing punches remain manual exceptions; do not fabricate time. No device integration, paid leave, holidays premium, payroll, period close, bulk entry or Excel import yet.
- Date eligibility based on work date (overnight may cross employment end date); only same employment overlap guarded. Rehire boundary / multiple sessions / cross-period policy to review before payroll.
- Staff can see attendance revision notes; restrict sensitive personal info. Audit snapshots contain attendance data, not identity documents. Historical schedule snapshot immutable; rebase workflow deferred.
- Both roles can verify, owner can approve their own verified record in pilot. Confirm separation-of-duties policy before production.
- No payroll lock yet: reopening approved records will need integration with payroll closed periods in Phase 5. No production data.
- Attendance view remains list based for efficient daily verification; calendar UX backlog #5 remains deferred.
- Browser regression of Phase 1/2/3 and direct API/RLS tests still required.
