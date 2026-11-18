# Production Launch Checklist

## Blockers
- [ ] Migrations 127 and 128 reviewed and applied (127 is drift-only; 128 hardening) and advisors re-run
- [ ] Auth: leaked-password protection ON; anonymous sign-ins OFF unless needed; decide policy for `page_post_view_events`
- [ ] Malware/CSAM scan hook wired to a real scanner, and a child-abuse reporting path defined
- [ ] Legal review of Terms, Privacy Policy, retention schedule, grievance officer, Nepal registration obligations
- [ ] Security headers on Nginx; HTTPS verified (SSL Labs A)
- [ ] All secrets rotated; no PAT/token still valid from development sessions
- [ ] `SUPABASE_ACCESS_TOKEN` set in GitHub so migrations auto-apply
## Infrastructure
- [ ] Supabase plan sized for load test results; backups/PITR enabled; restore tested
- [ ] Cron jobs present and succeeding; Database Webhook for notifications enabled
- [ ] Auth: email confirm ON, MFA ON, Google provider and redirect URLs configured, rate limits reviewed
- [ ] Resend domain verified (SPF/DKIM/DMARC); FCM configured; eSewa **production** credentials (`ESEWA_ENV`)
- [ ] Monitoring and alerts: CI failures, function errors, DB CPU/connections, storage, uptime check
## Quality gates
- [ ] CI green; migration lint 0 errors; security checklist done; privacy/legal audit items closed or accepted
- [ ] Load test targets met; accessibility pass; Web + Android + iOS smoke
## Smoke test (after every deploy)
Sign up → confirm email → login → post with image → like/comment → report → moderator action → appeal → export data → request deletion (staging) → DM send/receive → notification push → admin dashboard loads → legal complaint submit.
## Launch day
Announce window; on-call named; rollback = previous web build + forward fix migration; moderation staffed.
