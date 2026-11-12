# BRO chat app handoff

This guide describes the app, its backend, local development, and release process. It is intended for the next developer who needs to operate or extend the current implementation.

## Architecture

- **Client:** Flutter 3.47.7. `lib/main.dart` contains the app routes and screens; `lib/services/supabase.dart` wraps authentication, profiles, conversations, messaging, and storage; `lib/services/push_notifications.dart` handles Firebase Messaging registration and received notifications; `lib/services/connection_monitor.dart` publishes a debounced online/offline signal from connectivity_plus; `lib/ui/states.dart` holds the shared empty/error/loading/offline widgets; `lib/screens/call_screen.dart` implements the call experience.
- **Authentication and data:** Supabase Auth, Postgres, and Realtime. User and conversation data are protected by row-level security and database functions/policies.
- **Object storage:** Avatars remain in Supabase Storage. Chat files and custom chat backgrounds use a private Cloudflare R2 bucket through a Cloudflare Worker. Supabase hosted Storage cannot be directly redirected to R2, so the Worker is the authenticated bridge.
- **Platforms:** Android, iOS, and Web. The repository’s automated release workflow builds Android APKs; Pages builds the web app.

## User-facing features

- Register and sign in with Supabase Auth; account settings edit the username/display name, password, and avatar.
- The conversation list can suggest/search existing profiles. Conversations display profile images and usernames.
- Direct messages use Supabase Postgres and Realtime. Attachments include images, videos, and documents.
- Settings offer built-in chat backgrounds and user-uploaded images.
- Voice and video calls use WebRTC for peer-to-peer media and private Supabase Realtime broadcasts for offer, answer, ICE, and call invitations. The recipient needs the conversation open to receive an incoming call. The current connection setup uses public STUN; networks that block direct peer connections need a TURN service configured in the call implementation for dependable production calls.
- Android message notifications use Firebase Cloud Messaging (FCM). The Flutter client registers a Firebase Installation ID for the signed-in user, and the `push_tokens` table stores those IDs. An insert trigger on `messages` calls the `push-new-message` Supabase Edge Function, which resolves the other conversation participant and sends the notification through FCM. Notification taps open that conversation; foreground notifications appear as an in-app banner.
- Firebase project `omix-systems-cd1af` already belonged to the Omix Systems account and had the related Omixsystems web app. The BRO Android (`com.omixsystems.pulsechat`) and iOS (`com.omixsystems.chatApp`) apps are registered there. `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist` contain Firebase client configuration and are not private keys. A new Firebase project could not be created because the Google account has reached its project quota.
- Supabase Edge Function secrets `FIREBASE_SERVICE_ACCOUNT_B64` and `PUSH_WEBHOOK_SECRET` are configured remotely. The database trigger reads its function URL and webhook secret from Supabase Vault. The service account has the Firebase Cloud Messaging API Admin role. Never commit its key or copy it into handoff notes.
- iOS delivery still requires an APNs authentication key to be uploaded in Firebase and Push Notifications capability configured for the Apple app. Web push is not enabled yet; it needs a Firebase Web app, a VAPID key, and the Firebase messaging service worker. Android delivery has not been physically tested because this machine has no Android SDK/device; install a release APK on two Android devices to verify end-to-end delivery.

## Supabase database

Migrations are in `supabase/migrations` and must be committed in timestamp order. On 2026-11-02, the three feature migrations below were applied to the linked project and `supabase migration list --linked` confirmed them as applied:

1. `20261102000000_chat_media_calls.sql` adds avatar/file buckets and access rules, call signaling policies, and the conversation-list RPC changes.
2. `20261102010000_chat_background_preference.sql` stores the selected built-in background on the profile.
3. `20261102020000_chat_background_images.sql` stores custom-background paths and secures the background bucket.

For another environment, set up the Supabase CLI and link the intended project, then review the pending migrations before applying them:

```sh
supabase migration list --linked
supabase db push --linked
```

`db push` changes the linked database. Confirm the link points to the intended project before running it.

## Cloudflare R2 storage

- **Bucket:** `chat-app-storage` (private R2 bucket).
- **Worker:** `bro-chat-storage`, currently deployed at `https://bro-chat-storage.twistedoliver211fs.workers.dev`.
- **Configuration/source:** `cloudflare/storage/wrangler.jsonc` and `cloudflare/storage/src/index.js`.
- **Worker secrets:** `SUPABASE_ANON_KEY` and `URL_SIGNING_SECRET`. They are set in Cloudflare and must never be committed or copied into this document. The Supabase anon/publishable key is used with the caller’s access token to validate the user; the signing secret protects short-lived download URLs.

Upload flow: the Flutter storage methods send the signed-in user token to the Worker. The Worker validates the token with Supabase Auth, checks conversation membership for chat files, and stores the object in R2. Background images are stored under the owner’s user ID. The Worker issues signed download links that expire after one hour. On a cache miss in R2, it falls back to a Supabase Storage signed link so files uploaded before the R2 switch remain accessible.

To redeploy the Worker after changing its source, use Wrangler from its project directory:

```sh
cd cloudflare/storage
wrangler deploy
```

To inspect buckets or the configured secret names, use `wrangler r2 bucket list` and `wrangler secret list`. These commands do not display secret values. Do not enable public access on the R2 bucket; downloads should continue through the Worker authorization flow.

## Local development

Flutter 3.47.7 is the version pinned by the GitHub workflows. On the original development machine, it is installed at `/home/marvel/flutter_sdk`; new zsh sessions include it on `PATH` through `.zprofile` and `.zshrc`. On another machine, install Flutter 3.47.7 or use the version pinned in CI.

Create a gitignored `.env.local` containing `SUPABASE_URL` and `SUPABASE_ANON_KEY`. Do not commit it. Then run:

```sh
flutter pub get
./scripts/build.sh web
# or: ./scripts/build.sh apk
```

The app defaults to the deployed Cloudflare Worker URL; a different endpoint can be supplied with `--dart-define=CLOUD_STORAGE_URL=...`. Android development also requires the Android SDK and accepted Android SDK licenses. Flutter Doctor on the original machine reported that the Android SDK is not installed there, so local Android builds need that toolchain added first.

## GitHub builds and releases

Pushing to `main` or `master` starts three workflows:

- `.github/workflows/ci.yml`: `flutter analyze` and `flutter test`.
- `.github/workflows/build-apk.yml`: builds split release APKs and publishes a GitHub Release tagged `v<run number>`.
- `.github/workflows/pages.yml`: builds the Flutter web app and deploys it to GitHub Pages.

Repository Actions secrets `SUPABASE_URL` and `SUPABASE_ANON_KEY` must be set for the app builds. The GitHub token needs permission to create releases; the Pages deployment also requires GitHub Pages to be enabled for the repository. Cloudflare Worker deployment is a separate Wrangler operation; the GitHub workflows do not deploy it.

### Release signing (required)

The APK workflow also requires `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS` and `KEY_PASSWORD`. Create them once with `./scripts/generate_keystore.sh`, keep the keystore backed up, and never replace it: Android only installs an update signed by the same certificate, so a new key means every installed copy must be uninstalled first.

The workflow refuses to build without those secrets, `android/app/build.gradle.kts` refuses to fall back to the debug key when `REQUIRE_RELEASE_SIGNING=true`, and the release step runs `apksigner verify --print-certs` and fails on a debug certificate. Releases `v63`–`v71` either failed to build or (from runs before the keystore step existed, e.g. `v62`) shipped debug-signed, so they cannot be updated in place.

### Why the v63–v71 builds failed

| Run | Cause |
| --- | --- |
| `v63` | Dart compile errors: `_P.volt` was missing from the palette and a `children: [` list was unterminated. |
| `v64`–`v69` | Follow-on compile failures and plugin configuration errors. |
| `v70` | `permission_handler_android` required `compileSdk 37`; AGP 9.1.0 warns that 36 is its maximum supported value. |
| `v71` | `flutter_windowmanager 0.2.0` calls `jcenter()`, removed in Gradle 9, so project evaluation aborted. |

Fixed by removing the unused `flutter_windowmanager` (FLAG_SECURE is now handled by a `bro/secure` method channel in `MainActivity.kt`), replacing `permission_handler` with the `record` plugin's own `hasPermission()`, and dropping the unused `archive`, `path_provider` and `swipe` dependencies.

After pushing, check the repository’s Actions page for all three runs. The release workflow should attach the three ABI APK files; the Pages workflow should finish its deployment. If a run fails, inspect the failed step’s logs before retrying.

## Operational notes

- Keep `.env.local`, Supabase credentials beyond the public app key, Cloudflare API tokens, and `URL_SIGNING_SECRET` out of Git.
- The Supabase avatar bucket is public by design; chat-file and chat-background buckets are private.
- WebRTC calls currently have no TURN relay. Configure one before relying on calls across restrictive mobile, office, or carrier networks.
- The app uses an expiring download URL, so a shared link can be opened by its holder until it expires. Keep the expiry short if the threat model changes.
- Message notification behavior is platform-specific: Android push is wired; iOS depends on APNs setup; the Flutter web client currently skips FCM until its Web Push VAPID key and service worker are configured.

## Current work status (2026-11-03)

Uncommitted work in progress: a code review was completed against these changes, and the shared-state and connectivity workstreams from the follow-up plan are implemented and verified.

### Completed in this session

- **Code review report:** delivered to the user; findings are listed below as outstanding issues.
- **Shared state widgets:** `lib/ui/states.dart` provides `AppEmptyState`, `AppErrorState`, `AppLoader` (with an `AppLoader.standard()` factory; call sites therefore drop `const` where a loader is used), `ListSkeleton`, and `BubbleSkeleton`. All widgets derive colors/sizes from the theme; no new dependencies.
- **Wiring in `lib/main.dart`:** the conversation list shows the loader, an error state ("Failed to load conversations"), or an empty state whose CTA refocuses the profile search; both narrow and wide chat layouts show message skeletons, a "Failed to load messages" error state, or a "Wave hello" empty state that prefills "Hey! 👋" and sends. The old inline `_EmptyState`/`_ErrorState` classes were deleted.
- **Connectivity monitoring:** `connectivity_plus: ^7.3.2` added to `pubspec.yaml`; `lib/services/connection_monitor.dart` watches the connectivity stream with a 3-second debounce and exposes a static `isOnline` notifier. `ConnectionMonitor.start()` is called on app start and disposed on shutdown; `OfflineBanner` (in `lib/ui/states.dart`) renders as a non-tappable overlay at the top of the screen when offline. The app initializes connection monitoring before the Supabase auth stream so a reload while offline is handled gracefully.
- **Verification:** `flutter analyze` reports no issues; all three widget tests pass.
- **Deferred by decision:** offline *queued sends* (compose offline → queue → auto-flush on reconnect) are part of Phase B1, not this workstream; they require `PendingMessage`.

### Resolved review findings

1. ~~No UPDATE policy on `conversations`~~ — `20261111000000_fix_conversations_update_rls.sql`.
2. ~~Pin offered on peer messages / rejected by the trigger~~ — `20261111010000_fix_pin_message_security.sql` adds `pin_message()`, and the client only offers Pin on own messages.
3. ~~`updateProfileDetails` wrote `'0 seconds'` for a null expiry~~ — the update map is conditional.
4. ~~`delete_expired_messages()` never scheduled~~ — `pg_cron` schedule in `20261106000000_privacy_and_fixes.sql`.
5. ~~Privacy columns not enforced~~ — reads go through the `visible_profiles` view.
6. ~~Pin call site omitted `conversationId`~~ — passes `widget.conversationId`; `setMessagePinned` also enforces the 5-pin cap early.
7. ~~`last_seen` only on resume~~ — recorded from `_BroAppState.initState` too.

Additional fixes in the release-hardening pass:

- `messages` had **no DELETE policy**, so both delete actions affected zero rows. Deletion is now tombstone-based (`deleted_at`, `hidden_for`) behind `delete_message_for_everyone()` / `hide_message_for_me()` (`20261112000000_message_delete.sql`).
- `blocked_users`, `user_reports` and `contacts` were queried by the client but **never created**; any block, report or message-request check raised "relation does not exist". Added in `20261112010000_block_report_contacts.sql`, with a trigger that stops blocked users messaging.
- `mark_messages_read` ignored `read_receipts_enabled`; receipts are now gated (`20261112020000_read_receipt_privacy.sql`).
- Two migrations shared the timestamp `20261111020000`, which makes migration ordering ambiguous; the config-validation one is now `20261111020001`.
- The app-lock PIN was a "not implemented" snackbar, the lock overlay had no `Directionality` ancestor, and App Lock could be switched off without authentication.

### Still open

- `watchMessages` re-queries `message_reads` per snapshot via `asyncMap`; follower counts load all follows instead of using `.count()`; `expires_at` uses the client clock (skew risk).
- Attachment uploads, voice notes and WebRTC calls have not been exercised against a live Supabase project from this environment.
- `voice_note.dart` writes to a relative `audioplayerscache/` path, which is not a valid absolute temp path on Android; it needs `path_provider` (deliberately dropped here) before voice notes work.

### Remaining plan

**Phase B — core chat polish:**

- `lib/models/pending_message.dart`: `localId`, `status` (`sending`/`sent`/`failed`/`queued`), `toOptimisticMessage()`, retry count.
- `lib/chat/widgets.dart`: `UnreadDivider`, `JumpToBottomButton`, `PendingBubble` (tap-to-retry), `TypingFooterRow`, `FileBubble` (non-image attachments; note the no-comments repo rule applies to all new code except `///` dartdoc on public widgets).
- `lib/main.dart`: optimistic append in `_send`/`_sendAttachment` with matching by `localId`; unread divider plus jump-to-bottom button when scrolled >400px; typing footer stub.
- Phase B1: offline queued sends — queue failed/offline sends, auto-flush on reconnect using `ConnectionMonitor.isOnline`.
- Deferred to Phase C: reply-to, reactions, in-conversation search.

**Phase C — social surfaces:**

- Statuses screen (sidebar entry, story viewer, ring avatars, create flow) using `Supa.createStatus`/`Supa.watchStatuses`.
- Follow UI using `isFollowing`/`setFollowing` and the follower-count RPC.
- Settings toggles for read receipts and default message expiry.

### Handoff mechanics

- Local SDK: `/home/marvel/flutter_sdk/bin/flutter`; run analyze/test from the repo root.
- All work so far is uncommitted; review findings plus the remaining phases describe exactly where to resume.
