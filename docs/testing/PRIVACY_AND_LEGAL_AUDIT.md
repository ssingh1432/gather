# Privacy & Legal Compliance Audit (Nepal)

Engineering checklist, **not legal advice**. Have a Nepali lawyer confirm the current text and applicability of: Electronic Transactions Act 2063, Privacy Act 2075, the MOCIT social-media directive, and any Social Media Bill that has passed since this was written.

## Privacy
| Item | Evidence | Status |
|---|---|---|
| Consent recorded with version + timestamp at signup | mig. 020, `consent_records` | verify on staging |
| Policy version bump re-prompts consent | `data_privacy_screen.dart`, `kPrivacyPolicyVersion` | verify |
| Policy/Terms hosted | eiquoab.xyz/privacy-policy, /terms | verify live + Nepali translation |
| Data export (JSON, signed 7-day link) | `data-export` | test |
| Account deletion, 14-day grace, purge | mig. 015/019 | test purge on staging |
| Privacy controls: profile visibility, online/last seen, search visibility, block, mute, restrict | mig. 009, 024 | test each |
| Data retention schedule documented | MAINTENANCE.md (draft) | **needs legal decision** |
| Data minimisation / third-party processors listed (Supabase, Resend, FCM, eSewa, Google, AdMob) | — | **add to policy** |
| Cross-border transfer disclosure (servers outside Nepal) | — | **needs legal review** |
| Children / age gate and Child Safety policy | Phase 5/7 | verify wording and age rules |
## Legal workflow
| Item | Evidence | Status |
|---|---|---|
| Complaint / grievance intake | `file_complaint_screen`, `legal_complaints` | test end-to-end |
| Abuse + illegal content reporting | 14 report categories | test |
| Content removal + user appeal | `submit_appeal`, moderation actions | test |
| Legal / police data requests with audit trail | `legal_data_requests`, admin legal dashboard | test; define who may approve |
| Grievance officer contact and response SLA published | — | **needs owner + wording** |
| Local representative / registration with authorities if required for social platforms | — | **needs legal confirmation** |
| Copyright notice workflow (DMCA-style) | generic report category `copyright` | **gap: no dedicated counter-notice flow** |
| Pluggable frameworks | `legal_frameworks` table | ok |
| Audit logging | `admin_audit_log`, `security_events`, `moderation_actions` | ok |
## Findings to action before launch
1. Dedicated copyright notice/counter-notice flow.
2. Published retention schedule and processor list.
3. Grievance officer details + SLA on the site and in-app.
4. Confirm registration/representation obligations for Nepal.
5. Malware/CSAM scanning plus a reporting path to authorities for child-abuse material.
