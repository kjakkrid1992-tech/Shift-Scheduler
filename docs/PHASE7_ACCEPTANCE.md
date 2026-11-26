# Consolidated pilot acceptance — 7.6A
Install missing migrations only, in order: 01000 legacy archive, 01100 legacy staff, 01200 bulk attendance/reporting, 01300 correction requests. Earlier migrations already applied need not be repeated. Run corresponding SQL tests on an isolated pilot with owner/manager and synthetic data; each rolls back. Use latest ZIP and retain local config.js (publishable key only). Do not reset schema or commit personal records. Back up original Excel and test database before migration.
Browser acceptance:
- Owner/Manager login/logout and access denial. Verify actual employee roster, current/former employment dates, department, type and effective rates manually. No inferred dates or rates.
- Calendar: month 26–25, edit day, save, confirm, list and print.
- Attendance: completed single slots, historical off, manual combined shifts, bulk save/verify/owner approve, stale revisions and rollback.
- Cash advance: draft, approve, paid, cancellation and allocation carryover.
- Payroll: known rates and manual exceptions, item totals, close synthetic period, payment and final print. Correction requests: create, owner review, immutable original. Requests do not adjust or block payment.
- Excel: preview/import/retry, bulk name link, unresolved groups, owner-only archive, compare against source.
- Staff reports: approved normal/OT, draft/final/paid totals, YTD by actual paid date, legacy separated.
- Mobile, keyboard, two sessions, logout and console.
Production gates remain: confirmed roster and actual migration review, full UI acceptance, post-close financial adjustment ledger (not implemented), backup/restore drill, security and legal review, deployment/rollback plan, reconcile against existing payroll before use. No real payroll closure until these gates pass. No automatic backup configured. No real staff data committed or database updated by code deployment.
