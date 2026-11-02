# BRO chat app handoff

This guide describes the app, its backend, local development, and release process. It is intended for the next developer who needs to operate or extend the current implementation.

## Architecture

- **Client:** Flutter 3.47.7. `lib/main.dart` contains the app routes and screens; `lib/services/supabase.dart` wraps authentication, profiles, conversations, messaging, and storage; `lib/services/push_notifications.dart` handles Firebase Messaging registration and received notifications; `lib/screens/call_screen.dart` implements the call experience.
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

After pushing, check the repository’s Actions page for all three runs. The release workflow should attach the three ABI APK files; the Pages workflow should finish its deployment. If a run fails, inspect the failed step’s logs before retrying.

## Operational notes

- Keep `.env.local`, Supabase credentials beyond the public app key, Cloudflare API tokens, and `URL_SIGNING_SECRET` out of Git.
- The Supabase avatar bucket is public by design; chat-file and chat-background buckets are private.
- WebRTC calls currently have no TURN relay. Configure one before relying on calls across restrictive mobile, office, or carrier networks.
- The app uses an expiring download URL, so a shared link can be opened by its holder until it expires. Keep the expiry short if the threat model changes.
- Message notification behavior is platform-specific: Android push is wired; iOS depends on APNs setup; the Flutter web client currently skips FCM until its Web Push VAPID key and service worker are configured.
