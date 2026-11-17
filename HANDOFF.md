# BRO chat app handoff

This guide describes the app, its backend, local development, and release process. It is intended for the next developer who needs to operate or extend the current implementation.

## Architecture

- **Client:** Flutter 3.47.7. The codebase uses a screen-focused folder structure:
  - `lib/main.dart` (~200 lines) contains `main()`, `BroApp`, routing, and theme configuration.
  - `lib/theme/app_colors.dart` holds all color constants and the `_P` palette.
  - `lib/screens/auth/` contains auth gate, login, and confirmation screens.
  - `lib/screens/chat/` contains the conversation list, chat screen, and all chat widgets (bubbles, composer, pickers, etc.).
  - `lib/screens/settings/` contains account settings.
  - `lib/screens/profile/` contains the user profile screen and profile-related widgets.
  - `lib/screens/navigation/` contains the navigation sidebar.
  - `lib/services/` contains domain-specific services: auth, profile, conversation, message, storage, follow, and status services, plus a thin Supabase client wrapper.
  - `lib/services/push_notifications.dart` handles Firebase Messaging registration and received notifications.
  - `lib/services/connection_monitor.dart` publishes a debounced online/offline signal from connectivity_plus.
  - `lib/ui/states.dart` holds the shared empty/error/loading/offline widgets.
  - `lib/screens/call_screen.dart` implements the call experience.
- **Authentication and data:** Supabase Auth, Postgres, and Realtime. User and conversation data are protected by row-level security and database functions/policies.
- **Object storage:** Avatars remain in Supabase Storage. Chat files and custom chat backgrounds use a private Cloudflare R2 bucket through a Cloudflare Worker. Supabase hosted Storage cannot be directly redirected to R2, so the Worker is the authenticated bridge.
- **Platforms:** Android, iOS, and Web. The repository's automated release workflow builds Android APKs; Pages builds the web app.

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

The `lib/main.dart` file is now ~200 lines containing only `main()`, `BroApp`, routing, and theme. All screens live under `lib/screens/` and all services are split by domain under `lib/services/`. Run `flutter analyze` after any changes to verify imports are correct across the new file structure.

## GitHub builds and releases

Pushing to `main` or `master` starts three workflows:

- `.github/workflows/ci.yml`: `flutter analyze` and `flutter test`.
- `.github/workflows/build-apk.yml`: builds split release APKs and publishes a GitHub Release tagged `v<run number>`.
- `.github/workflows/pages.yml`: builds the Flutter web app and deploys it to GitHub Pages.

The signed APK workflow uses repository Actions secrets `SUPABASE_URL` and `SUPABASE_ANON_KEY`. The Pages workflow uses the public Supabase URL and publishable key directly because browser builds must expose client-side config; never use a service-role key there. The GitHub token needs permission to create releases; the Pages deployment also requires GitHub Pages to be enabled for the repository. Cloudflare Worker deployment is a separate Wrangler operation; the GitHub workflows do not deploy it.

After pushing, check the repository’s Actions page for all three runs. The release workflow should attach the three ABI APK files; the Pages workflow should finish its deployment. If a run fails, inspect the failed step’s logs before retrying.

## Operational notes

- Keep `.env.local`, Supabase credentials beyond the public app key, Cloudflare API tokens, and `URL_SIGNING_SECRET` out of Git.
- The Supabase avatar bucket is public by design; chat-file and chat-background buckets are private.
- WebRTC calls currently have no TURN relay. Configure one before relying on calls across restrictive mobile, office, or carrier networks.
- The app uses an expiring download URL, so a shared link can be opened by its holder until it expires. Keep the expiry short if the threat model changes.
- Message notification behavior is platform-specific: Android push is wired; iOS depends on APNs setup; the Flutter web client currently skips FCM until its Web Push VAPID key and service worker are configured.

## Current work status (2026-11-17)

### Sentry error monitoring (v1.2.0+)

- **`sentry_flutter: ^9.20.0`** added to `pubspec.yaml`.
- `lib/main.dart` wraps all app initialization in `SentryFlutter.init()` with DSN pointing to `omix-systems/bro` project (DE region). `tracesSampleRate` is set to `1.0` for local/dev — consider lowering to `0.1` for production.
- `lib/widgets/sentry_test_button.dart` provides a `SentryTestButton` widget for verifying Sentry captures events during development.
- `test/sentry_test.dart` adds a widget test for the Sentry test button.
- Errors, crashes, and performance traces from user devices now flow to [Sentry dashboard](https://sentry.io/organizations/omix-systems/issues/).
- Offline caching: if the device is offline when an error occurs, Sentry queues it and sends it when connection returns.

### Fixed: BRO-4 — AlignmentDirectional null check error (v1.2.1)

- **Issue:** `TypeError: Null check operator used on a null value` at `AlignmentDirectional.resolve` in `alignment.dart`. The `Stack` widget wrapping `MaterialApp.router` in `lib/main.dart` used the default `AlignmentDirectional.topStart` alignment. During the very first frame, before `MaterialApp` provides a `Directionality` widget, `AlignmentDirectional.resolve` fails because `Directionality.maybeOf(context)` returns null.
- **Fix:** Added explicit `alignment: Alignment.topLeft` to the `Stack` widget at line 339 in `lib/main.dart`. This avoids the `AlignmentDirectional` dependency on `Directionality` context.
- **Verified:** All 20 tests pass; `flutter analyze` reports 0 errors.

### Fixed: BRO-5 — Missing database functions (v1.3.1)

- **Issue:** `PostgrestException: Could not find the function public.get_all_conversations_for_user` (29 escalating events, 2 users affected). The app calls `get_all_conversations_for_user()` via Supabase RPC, but 5 database migrations had never been pushed to the live Supabase project. The migrations also contained bugs: `converse_rows` view was referenced but never created, functions had broken SQL (cross joins with missing columns), and type mismatches (`null` without casts).
- **Root cause:** Migrations in `supabase/migrations/` were written locally but never deployed with `supabase db push --linked`. The `circles_conversations` migration referenced a non-existent `converse_rows` view and had broken function logic.
- **Fix:**
  - Created the missing `converse_rows` view in `20261114020000_circles_conversations.sql` that enriches the `conversations` table with peer identity, last message, unread count, and lock status.
  - Rewrote `get_conversations_for_user()` and `get_all_conversations_for_user()` functions with correct SQL and proper type casts (`null::uuid`, `null::text`).
  - Fixed migration order: table creation before function definitions.
  - Fixed `20261114030000_scheduled_messages.sql`: removed `now()` from partial index predicate (PostgreSQL requires IMMUTABLE functions in index predicates).
  - Pushed all 5 pending migrations to the live Supabase database.
- **Files changed:** `supabase/migrations/20261114020000_circles_conversations.sql`, `supabase/migrations/20261114030000_scheduled_messages.sql`
- **Verified:** `supabase db push --linked` succeeded; all 5 migrations applied. New v1.3.1 release built and published.

### UI Upgrades, Motion & Animations (v1.3.1)

Comprehensive end-to-end UI overhaul and motion polish across the client:
- **Motion primitives (`lib/ui/motion.dart`)**:
  - `PressScale`: interactive spring press feedback (scaling down to 0.90–0.96 with bounce back on release).
  - `FadeSlideIn`: staggered entrance animations for chat bubbles, list tiles, and dialog items.
  - `PulseScale`: gentle breathing/pulsing animation for live indicators, status rings, and unread count badges.
- **Navigation & Bottom Bar**:
  - Fixed tab index bug where `StatusScreen` highlighted Circles (index 1) instead of Status (index 2).
  - Polished `HomeNavBar` with top border gradient and rounded Volt indicator pill.
  - Polished desktop/tablet `NavSidebar` with active route highlight and profile avatar chip.
- **Conversation List**:
  - Pill search bar with glow border on focus and animated clear button.
  - "People you may know" stories carousel with glowing avatar rings and `PressScale`.
  - Staggered `FadeSlideIn` entry for conversation tiles.
  - Real-time `PulseScale` badge on unread message counts.
  - Added Floating Action Button (Volt Lime pen icon) to quickly start a new chat.
- **Chat Screen & Messaging**:
  - Outgoing bubbles with Electric Street Volt lime gradient and crisp high-contrast text.
  - Delivery receipt indicators: sending spinner, sent (`✓`), delivered/read (`✓✓`), and failed exclamation.
  - Floating "Jump to bottom" button that smoothly scales/fades in when scrolled up > 350px.
  - Composer input bar upgraded to a floating pill with spring micro-interactions.
  - AnimatedSwitcher button morphing between mic and arrow send buttons.
  - Attachment action sheet redesigned into a modern 5-category icon grid modal (Gallery, Camera, Document, GIF, Stickers).
- **Circles & Statuses**:
  - Card elevation and interactive press feedback.
  - Cohesive dark Material 3 dialogs and bottom sheets.
- **Verification**: `flutter test` passed all 20 tests; `flutter analyze` zero errors.

### Fixed: BRO-8 and BRO-9 — Circles null checks and type cast errors (v1.3.4)

Two new issues were detected by Sentry from user devices running the circles feature.

**BRO-8 — `TypeError: Null check operator used on a null value`** (54 events, escalating)

- **Cause:** `circle.description!` in `circles_screen.dart` (line 434) force-unwrapped a nullable `description` field. Although guarded by `isNotEmpty`, the `!` operator could still fire if the value changed between the guard and the use (e.g., during stream refresh). Additionally, `circles.dart` used `client.auth.currentUser!.id` in `updateCircle()`, which crashes if the user is not authenticated.
- **Fix:** Replaced `circle.description!` with `circle.description ?? ''` in `circles_screen.dart`. Replaced `currentUser!.id` with a null-safe guard in `circles.dart` that returns early if the user is not authenticated.

**BRO-9 — `TypeError: type 'CircleMember' is not a subtype of type 'Map<String, dynamic>'`** (2 events)

- **Cause:** `_MembersList` in `circle_detail_screen.dart` declared `members` as `List<dynamic>` and cast each element to `Map<String, dynamic>` using bracket notation (`member['user_id']`). However, `Circles.getCircleMembers()` returns `List<CircleMember>`, so the cast failed at runtime.
- **Fix:** Changed `_MembersList` to accept `List<CircleMember>` and use property access (`member.userId`, `member.displayName`, `member.username`, `member.isAdmin`) instead of Map bracket notation. Updated the `_members` field type in `_CircleDetailScreenState` to match.

**Files changed:** `lib/screens/circles_screen.dart`, `lib/services/circles.dart`, `lib/screens/circle_detail_screen.dart`
**Verified:** `flutter analyze` reports 0 errors.

### Landing page hero video background (2026-11-17)

Added a subtle background video to the hero section of the web landing page (`web/index-landing.html`) to give the download page a more natural, lived-in atmosphere.

**What changed:**
- **`web/assets/video/man_chatting_on_phone.mp4`** — Video file (~3.3 MB) placed in web assets for serving by the landing page.
- **`web/index-landing.html`** — Added `.hero-video-bg` wrapper with an autoplaying, muted, looping `<video>` element behind the hero content. The video is styled with `opacity: 0.15`, `blur(2px)`, and `saturate(0.8)` so it reads as ambient atmosphere rather than a focal element. A dark gradient overlay (`.hero-video-overlay`) ensures the hero text and CTAs remain fully readable. The hero grid content sits at `z-index: 3` above the video layer.
- Video uses `preload="metadata"` to minimize initial load impact and `playsinline` for mobile compatibility.

**Design rationale:** The low opacity, blur, and desaturation keep the video from competing with the headline and CTA. It adds a subtle sense of motion and humanity — someone chatting on their phone — without feeling staged or distracting.

### Polished onboarding flow (v1.3.3)

The single-page onboarding screen was replaced with a **3-page swipeable onboarding flow** with animations and visual polish.

**What changed:**
- **3 onboarding pages** instead of 1 static screen:
  1. "For the people who feel like home." — conversation artwork with message tiles and voice note preview
  2. "Your circle. Your rules." — animated orbiting avatars around a central group node with connection lines
  3. "Private. Instant. Yours." — breathing shield icon with floating ENCRYPTED/INSTANT/VERIFIED badges
- **Staggered entrance animations** on each page: title fades/slides in first, then subtitle, then artwork (800ms total)
- **Ambient background glow** — a subtle radial gradient that slowly orbits behind all pages
- **Page indicators** — pill-shaped dots at the bottom that animate width on the active page
- **"Skip" button** — top-right corner lets users bypass onboarding entirely
- **Dynamic CTA button** — shows "Next →" on pages 1–2, "Get started 🚀" on page 3
- **Smooth page transitions** — 350ms `easeOutCubic` curve between pages

**Files changed:**
- `lib/screens/auth/onboarding_screen.dart` — complete rewrite (~1280 lines), added `_OnboardingPage`, `_CircleArtwork`, `_PrivacyArtwork`, `_AmbientGlowPainter`, `_OrbitAvatar`, `_CircleLinesPainter`, `_FeatureBadge`

**Verification:** `flutter analyze` 0 errors; all 20 tests pass.

### Improved auto-updater (v1.3.0)

The auto-updater in `lib/services/app_update.dart` was rewritten to provide a seamless in-app update experience for sideloaded APKs.

**Previous behavior:** Checked GitHub Releases, opened the browser to the APK download URL, and required the user to manually download and install — all outside the app. Critically, it only ran after the first frame (`addPostFrameCallback`), so if the app crashed on startup (like BRO-4), the updater never fired.

**New behavior:**

- **Direct APK download:** Downloads the APK directly to the device's app documents directory with a progress bar shown in a modal dialog.
- **Android PackageInstaller integration:** Uses a platform channel (`MethodChannel`) to `MainActivity.kt` which triggers Android's `PackageInstaller` via `Intent.ACTION_VIEW` with a `FileProvider` URI — the user sees the system install confirmation dialog without leaving the app.
- **FileProvider configuration:** `android/app/src/main/res/xml/file_paths.xml` and a `<provider>` entry in `AndroidManifest.xml` enable secure file sharing on Android 7+ (API 24+).
- **`REQUEST_INSTALL_PACKAGES` permission:** Added to `AndroidManifest.xml` to allow installing downloaded APKs.
- **Periodic background checks:** Every 6 hours the app silently checks GitHub Releases for newer versions. The check interval is stored in `SharedPreferences` so repeated launches within the window skip redundant API calls.
- **Better update dialog:** Shows release notes (truncated to 200 chars), a "Remind me later" option, and remembers which tag the user has already seen so it doesn't nag on every launch.
- **Download progress dialog:** Non-dismissible modal with `LinearProgressIndicator` showing percentage and an "Installing..." state after download completes.

**Files changed:**
- `lib/services/app_update.dart` — complete rewrite with download, progress, and background check logic.
- `lib/main.dart` — added `_startBackgroundUpdateChecks()` and `_periodicUpdateCheck()`.
- `android/app/src/main/kotlin/com/omixsystems/pulsechat/MainActivity.kt` — added `installApk` method channel handler.
- `android/app/src/main/res/xml/file_paths.xml` — new FileProvider path config.
- `android/app/src/main/AndroidManifest.xml` — added `REQUEST_INSTALL_PACKAGES` permission and `FileProvider` registration.

**Limitation:** If the app crashes before the first frame (e.g., a fatal error in `main()`), the auto-updater still cannot run. This is inherent to sideloaded APKs — there is no pre-launch update mechanism without a wrapper app or system-level installer.

## Current work status (2026-11-16)

**Major refactoring completed:** The monolithic `lib/main.dart` (7,867 lines, 60+ classes) was split into a proper folder structure under `lib/screens/` with focused files. The `lib/services/supabase.dart` (1,272 lines) was split into domain-specific services. All `.md` documentation files were removed except `HANDOFF.md` and `README.md`.

### Changes
- `lib/main.dart` reduced to ~200 lines containing only `main()`, `BroApp`, routing, and theme.
- Screens extracted to `lib/screens/auth/`, `lib/screens/chat/`, `lib/screens/settings/`, `lib/screens/profile/`, and `lib/screens/navigation/`.
- Chat widgets extracted to `lib/screens/chat/widgets/` (bubbles, composer, pickers, etc.).
- `lib/services/supabase.dart` reduced to a thin client wrapper; methods split into `auth_service.dart`, `profile_service.dart`, `conversation_service.dart`, `message_service.dart`, `storage_service.dart`, `follow_service.dart`, and `status_service.dart`.
- Color constants moved to `lib/theme/app_colors.dart`.
- All `.md` files removed except `HANDOFF.md` and `README.md`.

### Completed in this session
- **Code review report:** delivered to the user; findings are listed below as outstanding issues.
- **Shared state widgets:** `lib/ui/states.dart` provides `AppEmptyState`, `AppErrorState`, `AppLoader` (with an `AppLoader.standard()` factory; call sites therefore drop `const` where a loader is used), `ListSkeleton`, and `BubbleSkeleton`. All widgets derive colors/sizes from the theme; no new dependencies.
- **Wiring in `lib/main.dart`:** the conversation list shows the loader, an error state ("Failed to load conversations"), or an empty state whose CTA refocuses the profile search; both narrow and wide chat layouts show message skeletons, a "Failed to load messages" error state, or a "Wave hello" empty state that prefills "Hey! 👋" and sends. The old inline `_EmptyState`/`_ErrorState` classes were deleted.
- **Connectivity monitoring:** `connectivity_plus: ^7.3.2` added to `pubspec.yaml`; `lib/services/connection_monitor.dart` watches the connectivity stream with a 3-second debounce and exposes a static `isOnline` notifier. `ConnectionMonitor.start()` is called on app start and disposed on shutdown; `OfflineBanner` (in `lib/ui/states.dart`) renders as a non-tappable overlay at the top of the screen when offline. The app initializes connection monitoring before the Supabase auth stream so a reload while offline is handled gracefully.
- **Verification:** `flutter analyze` reports no issues; all three widget tests pass.
- **Deferred by decision:** offline *queued sends* (compose offline → queue → auto-flush on reconnect) are part of Phase B1, not this workstream; they require `PendingMessage`.

Uncommitted work in progress: a code review was completed against these changes, and the shared-state and connectivity workstreams from the follow-up plan are implemented and verified.

### Completed in this session

- **Code review report:** delivered to the user; findings are listed below as outstanding issues.
- **Shared state widgets:** `lib/ui/states.dart` provides `AppEmptyState`, `AppErrorState`, `AppLoader` (with an `AppLoader.standard()` factory; call sites therefore drop `const` where a loader is used), `ListSkeleton`, and `BubbleSkeleton`. All widgets derive colors/sizes from the theme; no new dependencies.
- **Wiring in `lib/main.dart`:** the conversation list shows the loader, an error state ("Failed to load conversations"), or an empty state whose CTA refocuses the profile search; both narrow and wide chat layouts show message skeletons, a "Failed to load messages" error state, or a "Wave hello" empty state that prefills "Hey! 👋" and sends. The old inline `_EmptyState`/`_ErrorState` classes were deleted.
- **Connectivity monitoring:** `connectivity_plus: ^7.3.2` added to `pubspec.yaml`; `lib/services/connection_monitor.dart` watches the connectivity stream with a 3-second debounce and exposes a static `isOnline` notifier. `ConnectionMonitor.start()` is called on app start and disposed on shutdown; `OfflineBanner` (in `lib/ui/states.dart`) renders as a non-tappable overlay at the top of the screen when offline. The app initializes connection monitoring before the Supabase auth stream so a reload while offline is handled gracefully.
- **Verification:** `flutter analyze` reports no issues; all three widget tests pass.
- **Deferred by decision:** offline *queued sends* (compose offline → queue → auto-flush on reconnect) are part of Phase B1, not this workstream; they require `PendingMessage`.

### Outstanding review findings

Blocking:

1. The `conversations` table has no UPDATE RLS policy, so `Supa.setMessageExpiry` and `Supa.getOrCreateDm` writes silently no-op. Fix with a narrow UPDATE policy or a SECURITY DEFINER function.
2. "Pin message" is offered on peer messages (client-side), but the "Sender updates own message" policy plus the `guard_message_update` trigger reject non-author updates. Gate the client action per-message, or add a SECURITY DEFINER `pin_message()` function (keeping the 5-pin limit).
3. `Supa.updateProfileDetails` unconditionally writes `default_message_expiry`, so a null value overwrites the stored default with `'0 seconds'`. Make the update map conditional.

Non-blocking:

4. `delete_expired_messages()` is never scheduled; `pg_cron` is not in any migration.
5. Privacy columns (`photo_visibility`, `status_visibility`, `about_visibility`) are stored but not enforced in `get_conversations_for_user`, `getProfile`, or `record_last_seen`.
6. The pin call site omits `conversationId`, so the client-side 5-pin guard is skipped.
7. `last_seen` is recorded on app resume only, not on cold start.
8. Minor: `watchMessages` re-queries `message_reads` per snapshot via asyncMap; follower counts load all follows instead of using `.count()`; there is no settings UI for `read_receipts_enabled`/`default_message_expiry`; `expires_at` is set with the client clock (skew risk).

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
