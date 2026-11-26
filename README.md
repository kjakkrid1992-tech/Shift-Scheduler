# Shift Scheduler

The legacy application remains at index.html. This branch adds Phase 1–5A pilot of V2 at v2/index.html; it is not deployed or production-ready.

See [Phase 1 setup and verification](docs/PHASE1_SETUP.md). Supabase project and Auth accounts must be configured separately. Do not commit employee records, payroll files or secret keys.

Scope: Employee master, employment history, compensation history, role-based access and audit metadata. Phase 2 adds shared schedules, versioned confirmation, and per-period availability. Phase 3 adds manual paper-card attendance, verification, owner approval and immutable revision history. Phase 4 adds cash advance requests, approval, actual payment recording and revision history. Phase 5A adds review-only payroll source snapshots, draft arithmetic and watermarked draft print; final payroll, actual deductions and migration are not implemented. See [Phase 2 setup and tests](docs/PHASE2_SETUP.md).

See [Phase 3 setup](docs/PHASE3_SETUP.md).

See [Phase 4 setup](docs/PHASE4_SETUP.md).

See [Phase 5A setup](docs/PHASE5_SETUP.md).

Phase 5B.1 structured drafts: [setup and boundaries](docs/PHASE5B_ITEMS.md).

Phase 5B.2 pilot: [close and payment setup](docs/PHASE5B_CLOSE.md).

Phase 6A historical archive: [setup](docs/PHASE6_SETUP.md).

Phase 6B reviewed staff migration: [setup](docs/PHASE6B_SETUP.md).

Phase 7.1: [calendar-first schedule pilot](docs/PHASE7_CALENDAR.md).

Phase 7.2–7.5: [bulk attendance and reporting pilot](docs/PHASE7_BULK_REPORT.md).

Phase 7.6B: separate post-payment cash adjustments (01400), see consolidated acceptance guide. No automatic withholding or modification of original payroll.
