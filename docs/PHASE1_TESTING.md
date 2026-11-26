# Foundation pilot / Phase 1.1
## Verified in user pilot on 2026-11-26
- Owner login, employee insert/read/edit, compensation history, resignation, rehire.
- Manager UI hides owner-only actions.
- SQL foundation test completed; compensation_roles.sql returned PASS after role guard migration.
- Evidence: screenshots reported in project chat; not independently replayed against live database by developer.
## Phase 1.1 changes
- Text date fields require DD/MM/YYYY Gregorian; validated real calendar dates, stored ISO date; prior records not changed.
- Display date-only values DD/MM/YYYY; Bangkok today for effective rate.
- Separate current/previous employment; mark current/historical/future rates; missing effective rate warning and filter; show rate unit.
- Closing future employment via this UI is disallowed; database still permits future dates via authorized direct API; future employment lifecycle needs consistent server policy before production.
- No schema changes or new SQL required for Phase 1.1.
## Re-test with synthetic employee
1. Download latest development-v2, run local server; login Owner.
2. Date entry 26/11/2026 must display as 26/11/2026, not 11/01/2026. Reject 31/02/2026 and malformed input.
3. Existing historical records display unchanged dates (11/01/2026 and 12/01/2026 in pilot); do not alter or delete them.
4. Current rehired employee without a rate appears in missing-rate filter. Add 26/11/2026 rate and a later rate; confirm current/next labels as of Bangkok date. Owner only.
5. Manager sees history and warning but no wage/termination actions.
6. Confirm search, filter, edit, rehire and sign-out still work.
## Release gates
- Complete Phase 1.1 browser regression, direct API tests for all roles, concurrency, backup/restore, security/PDPA review before real data.
- Pilot test records must be excluded from future production imports and schedules. Plan dedicated production project or controlled cleanup with audit before go-live.
- No payroll, scheduling integration, data migration or deploy in this change.
