# BRO push notification infrastructure

## Android and iOS: corrected FCM registration

The previous implementation registered a Firebase **Installation ID** and sent it to FCM HTTP v1 as `message.fid`. That is not a registration token and cannot deliver messages reliably.

Current implementation:

- `FirebaseMessaging.instance.getToken()` obtains the real FCM registration token.
- `onTokenRefresh` keeps the stored token current.
- `Supa.savePushToken(token, platform)` stores it in `public.push_tokens` keyed by `(user_id, device_id)`, where `device_id` is a random install identifier in secure storage. This prevents duplicate registrations and account cross-talk.
- Logout/account switch removes only the current install's token and calls `deleteToken()`.
- The `push-new-message` Edge Function now selects `token` and sends FCM HTTP v1 `message.token`, removing invalid tokens on `UNREGISTERED`.
- Notifications remain generic: no sender, message plaintext or ciphertext in the payload.

Deployed: migration `20261121000000_signal_identity_and_push.sql` and Edge Function `push-new-message` to the linked BRO project `dbfgyehzgrmsajpwydps`.

## Web push: partial implementation

Implemented now:

- `web/service-worker.js` handles `push`, displays a generic notification and handles `notificationclick` by focusing an existing BRO tab and posting a `bro-navigate` message or opening `#/conversations`.

Outstanding before web push can be enabled in production:

1. Add an explicit "Enable browser notifications" action in Settings that calls `Notification.requestPermission()` only after user interaction.
2. Provision a VAPID key pair. The private key must remain server-side; only the public key may reach the browser.
3. Implement subscription creation in Dart (`PushManager.subscribe`) and store `(user_id, endpoint, p256dh, auth)` in `public.web_push_subscriptions` via RLS-protected client writes.
4. Add a server-side sender using Web Push encryption with the VAPID private key, with authorization, idempotency via `notification_deliveries`, expiry cleanup and invalid-subscription removal.
5. Add navigation handling for `bro-navigate` in the Flutter app so notification clicks open the correct conversation after authentication and membership validation until then.

Until these are complete, BRO web must not advertise push notifications.

## Infrastructure dependencies and blockers

- Firebase service account with FCM Admin permission must remain configured as `FIREBASE_SERVICE_ACCOUNT_B64` in Supabase Edge Function secrets. It was configured previously; no secret value is stored in the repository.
- Web push VAPID key pair is not provisioned. This is the exact blocker for end-to-end browser push delivery.
- Browser support varies: Safari/iOS web push requires a compatible browser version and a properly configured web app identity. Unsupported browsers fall back to in-app notifications only.

## Test coverage

- All 92 project tests pass, including new fail-closed E2EE and call state-machine tests.
- Platform delivery (FCM background/terminated/cold-start routing, permission denial, multiple devices, invalid tokens) requires physical devices and is documented as a manual test matrix, not claimed as executed here.
