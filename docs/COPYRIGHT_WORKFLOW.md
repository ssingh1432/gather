# Copyright notice & counter-notice workflow (migration 130)

Lifecycle: `submitted → under_review → content_removed | rejected`; after removal the accused author may file a counter-notice → `counter_notice_received → restored` (staff accept) or back to `content_removed` (staff reject). Claimants can `withdraw` while open.

| RPC | Who | Effect |
|---|---|---|
| `submit_copyright_notice(...)` | signed-in user | Needs target post or URL, good-faith + accuracy statements, signature. Max 5 notices / 24 h |
| `withdraw_copyright_notice(id)` | claimant | open notices only |
| `admin_resolve_copyright_notice(id, 'review'\|'remove'\|'reject', notes)` | admin / moderator | `remove` sets `posts.is_removed = true` |
| `submit_counter_notice(id, statement, consent, signature)` | accused author | only after removal; needs jurisdiction consent |
| `admin_resolve_counter_notice(id, restore, notes)` | admin / moderator | `restore` re-publishes the post |

Tables: `copyright_notices`, `copyright_counter_notices` (SELECT only for claimant, accused author, staff; all writes via RPC). Every step is written to `security_events`.

## Not built yet
- Flutter screens (submit notice, my notices, counter-notice form, staff queue). The RPCs are ready; UI needs a Flutter build environment.
- Notifications to the author on removal (add to `notification-dispatch`).
- Time limits (statutory windows) and repeat-infringer policy. Have counsel confirm what applies in Nepal, and publish the policy text.
- Rights holders without an account must email the designated contact; add the address to the Copyright Policy page.
