# Phase A notification verification

Phase A proves the push pipeline and records what cannot be proven without devices. Automated tests cover the database and service worker; the matrix below covers FCM delivery.

## Already verified

- 2026-11-24, linked project: `bro_push_devices`, `bro_push_events`, `bro_push_deliveries` all have 0 rows. No production delivery has occurred.
- Vault secrets `push_webhook_url`, `push_webhook_secret` exist; Edge Function `push-new-message` is ACTIVE at version 5.
- `FIREBASE_SERVICE_ACCOUNT_B64`, `PUSH_WEBHOOK_SECRET`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` exist in Supabase secrets.
- Cron `bro-push-drain` is active at 10 seconds; `bro-push-retention` is active daily.
- `register_bro_push(uuid,uuid,text,text)` EXECUTE granted to `authenticated`; `claim_bro_push()` and `wake_bro_push()` granted only to `service_role`.
- `node supabase/tests/bro_calls_push.mjs` and `node --test supabase/tests/web_push_worker.test.mjs` pass.
- GitHub repo has no `FIREBASE_WEB_*` or `FIREBASE_WEB_VAPID_KEY` variables, so web push is disabled by configuration.

## Device matrix to run before claiming delivery

Use two real accounts on two devices. Record pass, fail, or not run in the result column. Do not mark a case passed from code inspection.

| # | Case | Steps | Expected | Result |
| --- | --- | --- | --- | --- |
| 1 | Registration | Sign in on device B, open Settings, tap "Enable notifications on this device" | Permission granted; one fresh `bro_push_devices` row for B's install | Not run |
| 2 | Preferences | Turn messages off, send from A to B, wait 30s | No notification; `bro_push_deliveries` has no new 'sent' message row for B | Not run |
| 3 | Foreground | With B in foreground, send from A | In-app snackbar only, no duplicate system notification | Not run |
| 4 | Background | Background B, send from A | Generic system notification with no sender or message text | Not run |
| 5 | Terminated | Force-stop B, send from A | Notification arrives after cold start; tapping opens the conversation | Not run |
| 6 | Tap routing | Tap the notification from case 4 or 5 | Opens the correct conversation after membership check, not a generic route | Not run |
| 7 | Multi-device | Register two installs for B, send from A | Each install gets one notification; no duplicate on either device | Not run |
| 8 | Account switch | Sign out of B, sign in as A | Old device row removed; A does not inherit B's token | Not run |
| 9 | Invalid token | Revoke FCM token or uninstall, then send from A | Invalid token removed on `UNREGISTERED`; other installs still receive | Not run |
| 10 | Muted call | Turn calls off, call B from A | No incoming-call notification; missed-call route still respects preference | Not run |

## Production queries

Run with `supabase db query --linked` and do not paste token values into issues or chat.

```sql
select platform, count(*) as devices,
       count(*) filter (where refreshed_at > now() - interval '45 days') as fresh
from public.bro_push_devices group by platform;

select status, count(*) from public.bro_push_deliveries group by status;

select kind, count(*) from public.bro_push_events
where expires_at > now() group by kind;
```

## Gate

- `flutter analyze --no-fatal-infos` clean.
- `flutter test` green.
- `node supabase/tests/bro_calls_push.mjs`, `scheduled_and_search.mjs`, `circle_invites.mjs` green.
- `node --test supabase/tests/web_push_worker.test.mjs` green.
- Release only after CI, signed APKs, and Pages are green on the tag.
