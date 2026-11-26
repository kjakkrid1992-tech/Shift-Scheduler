# Version 8.0 Alpha — isolated development
Baseline RC2 a530f53b20612902e1ef5199aa8e4711404bfec9 (same tree as pilot-7.9-rc2). Do not modify main or development-v2.
M00: inventory and inspect existing engines/SQL/CI; measured Excel baseline outstanding.
M01: upstream Tabulator and SlickGrid MIT/clipboard/range docs reviewed; comparative browser POC and benchmark outstanding. Native worksheet uses explicit transactional paste to preserve permissions and manual normal minutes; no GPL code copied.
M02: preserve RC2 app shell, improve only after complete workflow.
M03: no fabricated historical schedule, actual worksheet paste, keyboard Enter, undo paste, all employees in department, atomic batch. Migration 01500 only on disposable DB until restore rehearsal and acceptance.
M04–M09: keep RC2 scheduler, roster, advance, payroll, close, archive; validate and refine with regression, not yet accepted.
M10: SQL/JS/browser test, verified payroll policy, historical reconciliation and real user timing required.
M11: production cutover blocked until actual rates/dates, lawful OT/deductions/tax/social security, backup/restore and parallel payroll approved. No production credentials or real data in Git.
Open v8/index.html via Live Server only with a dedicated sandbox project; v8/config.js intentionally blank. Do not copy v2 production config. V8 SQL migration additive behavior (nullable plan reference; existing attendance snapshots unchanged). Reverting frontend alone does not roll back DB schema. Never drop actual unscheduled rows; restore rehearsal or forward-compatible fix before live migration.
Sources: https://github.com/tabulator-tables/tabulator ; https://www.tabulator.info/docs/6.x/clipboard/ ; https://github.com/6pac/SlickGrid ; https://github.com/frappe/hrms ; https://github.com/horilla/horilla-hr
