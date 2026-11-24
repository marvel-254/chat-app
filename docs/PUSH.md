# BRO push notification infrastructure

Verified against the linked project on 2026-11-24. No secret values are stored here.

## Runtime path

1. The client calls `FirebaseMessaging.instance.getToken()` (`lib/services/push_notifications.dart`). Token refresh re-registers automatically.
2. `register_bro_push(p_owner, p_device, p_token, p_platform)` writes the token to `public.bro_push_devices`, keyed by `(user_id, device_id)`. The device id is a random per-install id in secure storage. The RPC rejects a caller who is not the owner.
3. Logout and account switch delete only the current install's row and call `deleteToken()`.
4. Message and call triggers write opaque events to `public.bro_push_events`; no message text, sender name, or ciphertext is stored in the push queue.
5. `public.bro_eligible_push` applies notification preferences, blocks, sender exclusion, membership, call state and expiry.
6. `public.claim_bro_push()` leases at most 32 due devices per invocation, one delivery per `(kind, source, day, device)`.
7. The `push-new-message` Edge Function (ACTIVE, version 5) sends FCM HTTP v1 `message.token` and removes invalid tokens on `UNREGISTERED`. It requires `FIREBASE_SERVICE_ACCOUNT_B64`, `PUSH_WEBHOOK_SECRET`, `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`, all present as Supabase secrets.
8. `wake_bro_push` is scheduled every 10 seconds and invokes the function when work is queued. `bro-push-retention` prunes stale devices and expired events daily.

`public.push_tokens` and the `dispatch_message_push` trigger from `20261102030000_message_push_tokens.sql` are legacy Firebase Installation ID code. They are superseded and must not be used for new sends. The authoritative trigger is `bro_queue_push` in `20261120130000_push_delivery.sql`.

## Native platforms

Android and iOS use the committed `google-services.json` / `GoogleService-Info.plist`. `PushNotifications.configured` is true for those platforms, but `available` is true only after Firebase actually starts. Settings shows "Try again" when startup failed so the user is not invited to enable a push channel that cannot register.

## Web

`web/service-worker.js` registers Firebase Messaging compat when `push-config.js` contains a Firebase web config, displays a generic notification for background messages, and routes clicks only inside BRO's own scope. The Dart client then checks account, membership and call state before navigation.

Web push is currently **disabled by configuration**: the `FIREBASE_WEB_*` and `FIREBASE_WEB_VAPID_KEY` GitHub Actions variables are not set, so `scripts/web-push-config.mjs` writes a null config and `PushNotifications.configured` is false on web. Settings states that push is not configured. To enable it, set those public web values as repository variables (the VAPID key comes from the Firebase console; no private key is needed for FCM web) and verify delivery in a browser. Until then, do not advertise web notifications.

## Production state on 2026-11-24

- `bro_push_devices`: 0 rows. `bro_push_events`, `bro_push_deliveries`: 0 rows.
- Vault secrets `push_webhook_url` and `push_webhook_secret` exist.
- Cron jobs `bro-push-drain` (10 seconds) and `bro-push-retention` (daily) are active.
- `register_bro_push` is executable by `authenticated`; `claim_bro_push` and `wake_bro_push` only by `service_role`.

No device has registered, so FCM delivery has not been proven end to end in this project. Infrastructure and database rules are verified; platform delivery is not. See `docs/testing/phase-a-notifications.md` for the device matrix.

## Automated coverage

- `supabase/tests/bro_calls_push.mjs`: token ownership, claim permissions, preferences, blocked users, deduplication, and call/message event gating.
- `supabase/tests/web_push_worker.test.mjs`: service worker notification display, payload validation, expiry, and in-scope click routing.
- Both run in `.github/workflows/supabase.yml`.
