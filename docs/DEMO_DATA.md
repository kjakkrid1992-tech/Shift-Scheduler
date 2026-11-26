# Material 3 demo — no production access
Open v2/demo.html?role=manager or role=owner. Real app remains v2/index.html. Demo has no external SDK or config, CSP connect-src none. Fixed demo date 15 Dec 2026, 22:00 Bangkok. All people and transactions synthetic. State persists in sessionStorage within the same tab; switching role preserves saved data; reset restores seed. No actual payment. 
- 12/2026: current partial attendance (approved, verified, draft, missing), advances (paid, approved, draft), three draft payrolls.
- 11/2026: full attendance + drafts, ready to practice closing subject to deduction evidence; 10/2026: closed and paid slips and correction/adjustment example.
- 5 employee identities, 3 departments, plans for three periods, legacy slips and review notes.
Most basic CRUD and transitions are simulated locally. Mock does not implement full SQL/RLS or exact legal/financial behavior. Daily bulk attendance and legacy identity linking/import are simulated locally; imports restricted to synthetic sheets prefixed DEMO. Unimplemented commands return an explicit error. Use actual Supabase UAT separately. No production writes or schema changes.
