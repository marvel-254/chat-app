# BRO Chat App — Agent Guide

This document provides context for AI agents working on the BRO Flutter messaging app. It covers architecture, key files, conventions, workflows, and current work status.

---

## Project Overview

**BRO** is a dark-themed Flutter messaging app with:
- Supabase Auth + Postgres + Realtime for auth, data, and real-time sync
- Cloudflare R2 (via Worker) for chat attachments and custom backgrounds
- Firebase Cloud Messaging for Android push notifications
- WebRTC for peer-to-peer voice/video calls
- Platforms: Android, iOS, Web

**Tech Stack:**
- Flutter 3.47.7 (pinned in CI)
- Dart SDK ^3.5.0
- Supabase Flutter ^2.5.0
- GoRouter ^14.0.0 for navigation
- Connectivity Plus ^7.3.2 for online/offline detection

---

## Architecture

### High-Level Structure

```
lib/
├── main.dart              # App entry, routes, theme, major screens (197KB)
├── models/
│   └── profile.dart       # User profile model
├── screens/
│   ├── call_screen.dart   # WebRTC call UI
│   ├── lock_gate.dart     # App lock (biometric/PIN)
│   ├── status_composer.dart
│   ├── status_screen.dart
│   └── status_viewer.dart
├── services/
│   ├── supabase.dart      # ALL Supabase operations (33KB) — auth, profiles, conversations, messages, storage, calls, follows
│   ├── presence.dart      # Online/offline presence via Realtime
│   ├── push_notifications.dart  # FCM registration & handling
│   ├── connection_monitor.dart  # Debounced connectivity stream
│   ├── app_lock.dart      # Biometric/PIN lock logic
│   ├── app_update.dart    # GitHub Releases auto-update
│   ├── secure_screen.dart # Screenshot/recording prevention
│   ├── voice_note.dart    # Audio recording/playback
│   ├── reactions.dart     # Message reactions
│   ├── read_receipts.dart # Read receipt logic
│   ├── block_report.dart  # Block/report users
│   ├── search_safety.dart # Content safety for search
│   └── status_feed.dart   # Status/story feed logic
├── ui/
│   ├── states.dart        # Shared widgets: Empty, Error, Loader, Skeletons, OfflineBanner
│   └── errors.dart        # Error display utilities
├── widgets/
│   ├── home_nav_bar.dart  # Bottom navigation
│   └── status_ring_avatar.dart
└── followers_following_screen.dart
```

### Key Design Principles

1. **Single Supabase Service** — `lib/services/supabase.dart` is the canonical data layer. All DB/auth/storage/realtime calls go through `Supa` class.
2. **Theme-Driven UI** — Colors defined in `main.dart` (`_P` class). No hardcoded colors in widgets.
3. **No Inline Comments** — Repo rule: only `///` dartdoc on public widgets/classes. No `//` comments in implementation.
4. **Realtime-First** — Conversations, messages, presence, calls all use Supabase Realtime subscriptions.
5. **Row-Level Security** — All data protected by RLS policies in Supabase migrations.

---

## Important Files Reference

### `lib/main.dart` (197KB)
- App initialization, Supabase/Firebase setup
- GoRouter configuration (routes: `/`, `/login`, `/confirm`, `/conversations`, `/status`, `/status/new`, `/status/view/:userId`, `/calls/:conversationId`, `/settings`, `/profile/:userId`, etc.)
- Theme constants (`_P` class) — **all colors here**
- Major screens: `AuthGate`, `LoginScreen`, `ConfirmationScreen`, `ConversationListScreen`, `ConversationScreen`, `SettingsScreen`, `ProfileScreen`, `SearchScreen`
- Chat background handling (built-in themes + custom uploads)

### `lib/services/supabase.dart` (33KB)
**The central data service.** Key methods:
- Auth: `signUp`, `signIn`, `signOut`, `resetPassword`, `updateProfileDetails`
- Profiles: `getProfile`, `watchProfile`, `searchProfiles`, `uploadAvatar`
- Conversations: `getOrCreateDm`, `getConversationsForUser`, `watchConversations`
- Messages: `sendMessage`, `sendAttachment`, `watchMessages`, `markAsRead`, `deleteMessage`, `setMessageExpiry`, `pinMessage`
- Calls: `initiateCall`, `answerCall`, `endCall`, `watchCallSignaling`
- Storage: `uploadChatFile`, `getChatFileDownloadUrl`, `uploadChatBackground`, `getChatBackgroundDownloadUrl`
- Follows: `isFollowing`, `setFollowing`, `getFollowerCount`, `getFollowingCount`
- Statuses: `createStatus`, `watchStatuses`, `markStatusViewed`

### `lib/services/presence.dart`
- `PresenceService` — broadcasts online/offline via Realtime `presence` channel
- `watchPresence(userId)` — stream of peer presence state

### `lib/services/connection_monitor.dart`
- `ConnectionMonitor.start()` / `dispose()` — call in `main.dart` init/dispose
- `ConnectionMonitor.isOnline` — `ValueNotifier<bool>` for UI (OfflineBanner)

### `lib/ui/states.dart`
Shared state widgets (use these instead of custom inline states):
- `AppEmptyState` — configurable empty state with CTA
- `AppErrorState` — error with retry callback
- `AppLoader` / `AppLoader.standard()` — loading spinner
- `ListSkeleton` / `BubbleSkeleton` — shimmer placeholders
- `OfflineBanner` — top banner when offline (uses `ConnectionMonitor.isOnline`)

---

## Development Workflow

### Local Setup

```bash
# 1. Create .env.local (gitignored) with:
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key

# 2. Install Flutter 3.47.7 (pinned in CI)
# 3. Get dependencies
flutter pub get

# 4. Run
./scripts/build.sh web      # Web dev server
./scripts/build.sh apk      # Android APK (requires Android SDK)
```

### Code Quality

```bash
flutter analyze   # Static analysis (must pass)
flutter test      # Unit/widget tests (must pass)
```

**Lint config:** `analysis_options.yaml` uses `flutter_lints: ^6.0.0`

### Adding Dependencies
- Add to `pubspec.yaml` under `dependencies:`
- Run `flutter pub get`
- Prefer stable versions; avoid breaking changes

---

## Supabase Database & Migrations

**Migrations location:** `supabase/migrations/` (applied in timestamp order)

**Key migrations (applied 2026-11-02):**
1. `20261102000000_chat_media_calls.sql` — buckets, call signaling, conversation RPC
2. `20261102010000_chat_background_preference.sql` — built-in background preference
3. `20261102020000_chat_background_images.sql` — custom background images

**To apply to a new project:**
```bash
supabase migration list --linked
supabase db push --linked
```

**RLS Policies** — All tables have RLS. Critical gaps (see Outstanding Issues):
- `conversations` table missing UPDATE policy
- Privacy columns not enforced in RPCs

---

## Cloudflare R2 Storage

- **Bucket:** `chat-app-storage` (private)
- **Worker:** `bro-chat-storage` at `https://bro-chat-storage.twistedoliver211fs.workers.dev`
- **Source:** `cloudflare/storage/`
- **Worker secrets (never commit):** `SUPABASE_ANON_KEY`, `URL_SIGNING_SECRET`

**Upload flow:** Flutter → Worker (validates Supabase token + conversation membership) → R2
**Download:** Worker issues signed 1-hour URLs. Falls back to Supabase Storage for pre-R2 files.

**Redeploy Worker:**
```bash
cd cloudflare/storage
wrangler deploy
```

---

## Push Notifications (FCM)

- **Firebase project:** `omix-systems-cd1af` (quota-limited, cannot create new)
- **Android app:** `com.omixsystems.pulsechat` — `android/app/google-services.json`
- **iOS app:** `com.omixsystems.chatApp` — `ios/Runner/GoogleService-Info.plist`
- **Edge Function:** `push-new-message` (triggered by `messages` insert)
- **Secrets (Supabase Vault):** `FIREBASE_SERVICE_ACCOUNT_B64`, `PUSH_WEBHOOK_SECRET`

**iOS still needs:** APNs auth key in Firebase + Push Notifications capability
**Web push not yet implemented:** Needs VAPID key + service worker

---

## Auto-Update System

- Checks GitHub Releases on app start
- Downloads APK, verifies embedded manifest (package name, version code, version name)
- Prompts user to install
- **To release:** Create GitHub Release with APK asset, tag `v<version>`

---

## Testing

**Test files in `test/`:**
- `widget_test.dart` — basic widget tests
- `app_lock_test.dart` — app lock logic
- `error_and_search_test.dart` — error states + search
- `status_feed_test.dart` — status feed logic

**Run:** `flutter test`

**Coverage:** Use `dart-collect-coverage` skill if needed.

---

## Conventions & Rules

### Code Style
1. **No inline `//` comments** — only `///` dartdoc on public APIs
2. **Theme colors only via `_P` class** — no hardcoded `Color(0xFF...)`
3. **Use `AppLoader`, `AppEmptyState`, `AppErrorState`** — don't create custom inline states
4. **Primary constructors** — prefer Dart 3 concise syntax
5. **Pattern matching** — use `switch` expressions for enums/sealed classes

### Navigation
- Use `context.go('/route')` or `context.push('/route')` via GoRouter
- Route definitions in `main.dart` `_router`

### State Management
- `ValueNotifier` / `ChangeNotifier` for simple state
- Realtime streams via `Supa.watch*()` methods returning `Stream`
- `StreamBuilder` / `StreamBuilder<List<T>>` in UI

### Error Handling
- `Supa` methods throw `Exception` with user-facing messages
- Catch in UI and show via `AppErrorState` or `ScaffoldMessenger`

### Security
- Never commit `.env.local`, secrets, API keys
- Supabase anon key is public (safe in builds)
- Service account keys only in Supabase Vault / Cloudflare Worker secrets

---

## Current Work Status (2026-11-03)

### ✅ Completed This Session
- Code review delivered
- Shared state widgets (`lib/ui/states.dart`) implemented and wired
- Connectivity monitoring (`ConnectionMonitor` + `OfflineBanner`) implemented
- `flutter analyze` clean, all 3 widget tests pass

### 🔴 Blocking Issues (Must Fix)
1. **`conversations` table missing UPDATE RLS policy** — `Supa.setMessageExpiry` and `Supa.getOrCreateDm` silently no-op. Fix: add narrow UPDATE policy or SECURITY DEFINER function.
2. **"Pin message" offered on peer messages** — client-side action allowed but server rejects via `guard_message_update` trigger. Fix: gate client action per-message, or add SECURITY DEFINER `pin_message()` function.
3. **`Supa.updateProfileDetails` unconditionally writes `default_message_expiry`** — null overwrites stored default with `'0 seconds'`. Fix: make update map conditional.

### 🟡 Non-Blocking Issues
4. `delete_expired_messages()` never scheduled (needs `pg_cron` migration)
5. Privacy columns (`photo_visibility`, `status_visibility`, `about_visibility`) stored but not enforced in RPCs
6. Pin call site omits `conversationId` — client 5-pin guard skipped
7. `last_seen` recorded on resume only, not cold start
8. Performance: `watchMessages` re-queries `message_reads` per snapshot; follower counts load all follows instead of `.count()`; no settings UI for read receipts/expiry; `expires_at` uses client clock (skew risk)

---

## Remaining Plan

### Phase B — Core Chat Polish
- **`lib/models/pending_message.dart`** — `localId`, `status` (sending/sent/failed/queued), `toOptimisticMessage()`, retry count
- **`lib/chat/widgets.dart`** — `UnreadDivider`, `JumpToBottomButton`, `PendingBubble` (tap-to-retry), `TypingFooterRow`, `FileBubble`
- **`lib/main.dart`** — optimistic append in `_send`/`_sendAttachment` (match by `localId`); unread divider + jump-to-bottom when scrolled >400px; typing footer stub
- **Phase B1:** Offline queued sends — queue failed/offline sends, auto-flush on reconnect via `ConnectionMonitor.isOnline`
- **Deferred to Phase C:** reply-to, reactions, in-conversation search

### Phase C — Social Surfaces
- Statuses screen (sidebar entry, story viewer, ring avatars, create flow) using `Supa.createStatus`/`Supa.watchStatuses`
- Follow UI using `isFollowing`/`setFollowing` and follower-count RPC
- Settings toggles for read receipts and default message expiry

---

## Useful Skills for This Project

When working on this codebase, consider these skills:
- `dart-run-static-analysis` — run `flutter analyze` and `dart fix`
- `dart-add-unit-test` — add tests for new logic
- `flutter-add-widget-test` — test UI components
- `flutter-fix-layout-issues` — fix RenderFlex overflows, unbounded constraints
- `flutter-build-responsive-layout` — adaptive layouts for mobile/tablet/desktop
- `flutter-setup-declarative-routing` — GoRouter patterns (already in use)
- `flutter-implement-json-serialization` — for new model classes
- `code-review` — review changes against standards and spec
- `security-audit` — review RLS policies, data exposure

---

## Quick Reference Commands

```bash
# Analyze & test
flutter analyze
flutter test

# Build
./scripts/build.sh web
./scripts/build.sh apk

# Supabase
supabase migration list --linked
supabase db push --linked

# Cloudflare Worker
cd cloudflare/storage && wrangler deploy

# GitHub Actions (check after push)
# - ci.yml: analyze + test
# - build-apk.yml: builds APKs, creates Release
# - pages.yml: deploys web to GitHub Pages
```

---

## Handoff Notes

- **Local Flutter SDK:** `/home/marvel/flutter_sdk/bin/flutter` (on original machine)
- **All work uncommitted** — review findings + remaining phases describe exact resume points
- **No Android SDK on original machine** — local Android builds need toolchain added

---

*This guide is maintained for AI agents. Update when architecture changes significantly.*