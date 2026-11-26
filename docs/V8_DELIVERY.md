# V8 validation and handoff — tested candidate, not a production release

Branch: development-v8. RC2 remains unchanged on development-v2 and pilot-7.9-rc2.

## Verified before this documentation
- GitHub Actions run 45825253899: all JavaScript and SQL regression steps, Chromium workflow and isolated Tabulator POC passed.
- Chromium exercised 155 actual-attendance rows, paste/undo/invalid paste, network failure, Manager verification, Owner approval, five payroll drafts, close, five print slips, and payment recording against disposable PostgreSQL.
- Original historical workbook: 208 payslip blocks, 20 historical worksheets and three reference worksheets. All income/deduction/net totals reconcile at satang precision; 38 unnamed/group records remain unlinked. The local converter reproduced the prior review JSON records exactly. No real workbook, archive JSON or identity data committed or imported.
- Tabulator POC loads 155 Thai rows and edits a cell. Native worksheet retained for this candidate: permission-aware paste and transactional save are already tested. No Frappe/Horilla GPL code copied. Comparative user timing and locked-range paste on Tabulator remain unverified.

## Historical archive preparation (local only)
Install pinned dependencies: py -m pip install -r scripts/requirements-legacy.txt
Run: py scripts/prepare-legacy-payroll.py "C:\\private\\original.xlsx" "C:\\private\\legacy-review.json"
Output must be a new path outside Git. It is not a current-payroll import and does not infer employee identities or update compensation. The Owner archive preview is the existing import route. Missing cached formulas, inconsistent amounts, duplicate source records and unsupported formats fail closed.

## Release boundary
No production migration or deployment. Existing database read-only preflight: 27 public tables, all RLS enabled, no anon table access; 5 employee records, 5 employments, 5 rate records, 2 periods, 6 schedules, 4 attendance records and no closed payrolls. No actual employee records modified. V8 has a free local-only runtime and a public-key setup form. No additional hosted Supabase project or branch is required. See V8_FREE_SETUP.md. A hosted RC2 database still needs migration 01500 after recovery rehearsal and acceptance. Test browser uses real business RPCs in isolated PostgreSQL with synthetic role claims, not real Supabase Auth/PostgREST. Scheduler, staff, advance and archive modules retained from RC2 and covered by existing regression; full user workflow/timing and UI redesign not yet accepted. Actual wage/OT/leave/deduction/tax rules, confirmed employment data, full backup and restore, actual Supabase authentication and one parallel payroll remain required before live use. Do not apply migration to production solely because CI is green.
