# Gather — Moderator Guide

## Report categories
spam, fake_account, harassment, hate_speech, violence, terrorism, child_abuse, adult_content, copyright, scam, impersonation, self_harm, drugs, other.

## Triage priority
1. **Immediate:** child_abuse, terrorism, credible violence, self_harm — remove/hide first, escalate to an admin, preserve evidence (`add_evidence`), follow the Child Safety Policy.
2. **High:** harassment, hate_speech, scam, impersonation.
3. **Normal:** spam, adult_content, drugs, copyright, fake_account, other.

## Actions (all audited)
| Action | RPC | Use |
|---|---|---|
| Warning | `issue_warning` | First minor violation |
| Strike | `add_strike(target, report, note, severity)` | Confirmed violation; auto-escalates |
| Suspension | `suspend_user` | Temporary; auto-lifted by `lift_expired_suspensions` |
| Ban | `ban_user` | Severe/repeat; reversible via `reinstate_user` |
| Notes | `add_moderator_note` | Internal context for other moderators |
| Evidence | `add_evidence` | Screenshots/links, stored in the evidence bucket |

### Strike escalation (automatic)
3 strikes -> 3-day suspension; 5 strikes -> 14-day suspension; 7+ strikes -> permanent ban. Severity adds multiple strikes at once.

## Appeals
Users submit via `submit_appeal`; a **different** moderator/admin should review with `review_appeal`. Uphold or reverse with a written reason; reversal should reinstate the user and note it.

## Keyword filters & media queue
Manage with `add_keyword_filter` / `remove_keyword_filter`. Flagged media appears in the media moderation queue; record decisions with `record_media_moderation_result`.

## Good practice
- Decide on content, not on who the user is. Write a note for every action.
- Don't action your own friends/conflicts; hand off.
- Watch for coordinated mass reporting — one reporter or group should not drive a ban without review.
- Keep evidence; don't copy illegal content outside the platform.
