# BRO next feature plan

Status: proposed. All GitHub issues are closed as of 2026-11-24; v1.5.7 shipped with voice-note fixes. Scope: `lib/`, `docs/`, tests, and timestamped Supabase migrations only when a phase needs them. No route changes, no brand refresh, no E2EE protocol rewrite, no other projects.

## 1. Current state

- GitHub: 0 open issues; 15 most-recent closed issues include E2EE, calls, rich media, notifications-related hardening, friend suggestions and the Supabase service outage.
- Release: `v1.5.7` at `c9a17e7`; CI Checks and Build APK green, three signed split APKs attached, Supabase CI green.
- Pages: two v1.5.7 deploys failed with `Found 0 artifact(s)` from `actions/deploy-pages@v4`; stale same-named artifacts were deleted and clean run `45412663778` is green with the PWA returning 200.
- Earlier plans: `docs/CHAT_IMPROVEMENT_PLAN.md` Phase A (voice notes) is implemented and shipped in v1.5.7; `docs/DESKTOP_CIRCLES_PLAN.md` Phases A and B shipped in v1.5.5 and v1.5.6.

## 2. Diagnosis

Observably broken or misleading:

1. `Supa.watchConversations()` claims realtime at `lib/services/supabase.dart:1181-1186`, but `_conversationChanges()` at `lib/services/supabase.dart:1138-1151` is a manual trigger plus a 5-second poll. There is no `postgres_changes` stream for conversations. The shipped circle stream in `lib/services/circles.dart` is the working pattern to copy.
2. `docs/PUSH.md` says tokens live in `public.push_tokens`, while the client writes `public.bro_push_devices` at `lib/services/push_notifications.dart:209`. Both tables exist in the linked project, so the documentation is stale, not necessarily the runtime.
3. Web push is display-only. `web/service-worker.js` handles `push` and `notificationclick`, but there is no VAPID key pair, no `PushManager.subscribe` call, and no server-side web sender. Do not advertise browser notifications as working.
4. `docs/PUSH.md` and `docs/OVERHAUL_CHECKLIST.md` still cite old test counts and unfinished verification; platform delivery has only been verified by code inspection, not a device round trip.

Verified existing, not missing:

- FCM registration, token refresh, permission request, foreground/background/tap handlers: `lib/services/push_notifications.dart:72-113,136,184`.
- Notification preferences UI: `lib/screens/settings/notification_settings_screen.dart:33-68`.
- Message-to-push trigger: `supabase/migrations/20261102030000_message_push_tokens.sql:54` and the newer claim-based path in `20261120130000_push_delivery.sql`.
- `push-new-message` Edge Function is ACTIVE at version 5 in the linked project and authenticates with `PUSH_WEBHOOK_SECRET` and `FIREBASE_SERVICE_ACCOUNT_B64`.
- Friend suggestions and people search ship (`conversation_list_screen.dart:159,171,540-584`, `/suggest-friends` in `lib/main.dart`); do not rebuild them.

Gaps, not outages:

- Peer photos appear in the conversation list (`conversation_list_screen.dart:284`) but nowhere in `ChatScreen`; `_MessageRow` at `chat_screen.dart:2599` has no avatar slot even though `Conversation.peerAvatarUrl` is mapped at `supabase.dart:1114`.
- No desktop list-and-detail pane; there is no `lib/widgets/desktop_workspace_shell.dart` and `ChatScreen` owns its own `NavSidebar`.
- In-chat message search is absent, but `_ScrollToMessage` exists at `chat_screen.dart:657`.
- Circle avatars, circle search and circle unread counts remain open from `docs/DESKTOP_CIRCLES_PLAN.md` Phase D.
- X3DH/Double Ratchet remains unfinished in `docs/OVERHAUL_CHECKLIST.md`; messages still travel through the legacy plaintext path.

## 3. Product checks

- Who: BRO users on Android and web, plus circle admins and desktop users.
- Pain: notifications are the only way a user learns about a message while the app is closed; a reported gap here means messages go unseen. Desktop users must navigate back to see another conversation.
- Why now: the push pipeline, Realtime pattern and responsive shell are already in place. These are wiring and verification tasks, not new infrastructure.
- 10-star: reliable cross-device delivery, encrypted media, a true two-pane desktop workspace and instant sync.
- Anti-goals: no E2EE protocol work in these phases, no new storage buckets, no route renames, no visual refresh.

## 4. Priority

ICE = impact x confidence / effort.

| Phase | Candidate | I | C | E | Score |
| --- | --- | --- | --- | --- | --- |
| A | Prove and harden notifications | 5 | 4 | 2 | 10.0 |
| B | Peer photos in chat bubbles | 4 | 4 | 2 | 8.0 |
| C | Realtime conversation list | 3 | 4 | 3 | 4.0 |
| D | Desktop two-pane chat and circles | 4 | 4 | 5 | 3.2 |
| E | In-chat message search | 3 | 3 | 3 | 3.0 |
| F | Circle completeness | 3 | 3 | 3 | 3.0 |
| G | Genuine E2EE completion | 5 | 3 | 5 | 3.0 |

## 5. Phase A: prove and harden notifications

1. Confirm the runtime table: instrument or query `bro_push_devices` for a real account after `PushNotifications.enable()` and confirm a non-expired FCM token with a single device id. Do not trust `docs/PUSH.md`.
2. Confirm the send path: send a message from account A to account B with B's app in background and terminated. Verify a generic notification arrives in both states, then tap it and confirm routing to the correct conversation. Record what was and was not tested; do not claim cold-start delivery without a device result.
3. Confirm preferences: toggle each `bro_notification_preferences` switch in Settings and verify `claim_bro_push` respects it via a linked-DB query under the caller role.
4. Fix `docs/PUSH.md` to name the tables and functions the code actually uses, and record the device results and remaining gaps.
5. Scope out web push only: keep VAPID provisioning and `PushManager.subscribe` as a separate proposal. No browser notification opt-in until the server sender exists.
6. Verification gate: analyzer clean, tests green, DB suites green if a migration changes, and an explicit device matrix in `docs/testing/` with pass/fail per case.

## 6. Phase B: peer photos in chat bubbles

Use `Conversation.peerAvatarUrl` and the existing `Avatar` widget. Show an avatar only on the last bubble of an incoming group; keep initials fallback and `photo_visibility` masking. Add widget tests for URL, grouped and fallback cases, then verify with two real accounts. This is the directly shippable follow-on to the voice-note work.

## 7. Phase C: realtime conversation list

Mirror the v1.5.6 circle pattern: add `conversations`, `conversation_participants` and `messages` to the publication if absent; replace `_conversationChanges()`'s 5-second poll with a channel stream plus a slow fallback poll; cancel channels on stream cancellation. Update the misleading doc comment at `supabase.dart:1181`.

## 8. Phase D: desktop workspace

Add `DesktopWorkspaceShell` with a 320 px list pane and `Expanded` detail pane above `ResponsiveAppShell`; extract `ConversationListPane` with `selectedId` and `onSelected`. Remove the duplicate `NavSidebar` when embedded. Apply the same pattern to circles. Keep all existing routes for narrow screens. Test at 1280 px.

## 9. Phases E to G

- E: local in-chat search with result count and jump-to-message via `_scrollToMessage`.
- F: circle avatars, list search, member role labels and unread counts; fix `linkConversation(circleId, circleId)` after checking `create_conversation_for_circle` against the linked DB.
- G: keep as a separate security programme under `docs/OVERHAUL_CHECKLIST.md`; do not mix it with feature releases.

## 10. Verification gates

- `flutter analyze --no-fatal-infos` clean and `flutter test` green after every phase.
- `node supabase/tests/bro_calls_push.mjs`, `scheduled_and_search.mjs`, `circle_invites.mjs` when migrations change.
- CI green on the tag, three signed APKs on the release, Pages green on the same SHA, PWA 200 after deploy.
- Device checks for notifications, voice playback and avatars; unit tests cannot prove these.

## 11. Risks

- Push delivery depends on Firebase credentials and the deployed Edge Function secrets; a code fix cannot prove delivery without a device.
- Two failed Pages runs left duplicate artifacts; delete stale artifacts before another deploy rather than rerunning the failed workflow.
- `ChatScreen` is large and stateful; keep each phase narrow and test-backed.
- A post-tag fix needs a new patch version; never rewrite an existing tag.

## 12. Recommended first move

Phase A. Notifications are the only feature the user explicitly called out as unverified, the code already exists, and the work is mostly proof plus documentation correction. Approve Phase A to begin.
