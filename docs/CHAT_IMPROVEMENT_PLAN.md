# Chat improvement plan

Status: Phase A implemented and gate-verified; release pending. Phases B-E proposed. Scope: `lib/screens/chat/`, `lib/services/voice_note.dart`, `lib/services/supabase.dart`, `test/`, and timestamped Supabase migrations if a phase needs them. No route changes, no brand refresh, no E2EE protocol work, no other projects.

## Diagnosis

### Observably broken

1. Voice notes cannot play for a receiver. `_VoiceMessage._toggle` at `lib/screens/chat/chat_screen.dart:2817` passes the raw storage object path to `UrlSource`. The `chat-files` bucket is private (verified: `public = false` in `storage.buckets`), while the signed-URL helper already exists at `lib/services/supabase.dart:945-950` and is unused here.
2. Voice note sending bypasses the message pipeline. `VoiceNoteService.stopAndUpload` at `lib/services/voice_note.dart:51-79` inserts straight into `messages` with `content_format: LegacyMessageCodec.plaintext` at line 108. It skips `MessageOutbox`, has no offline retry or optimistic status, and collapses every failure to an empty string.
3. The recording contract is wrong. The header comment promises a 60 s cap at `voice_note.dart:11`, but no timer exists. The dialog says "Hold to record, tap stop when done." at `chat_screen.dart:2996`, while the only gesture is `onTap` at line 3016.
4. Web recording cannot work. `voice_note.dart:14,53,55,79` uses `dart:io.File`. Flutter web stubs `dart:io`, so the app compiles and then fails at runtime. Web is a shipping target via GitHub Pages.

### Missing, not broken

5. Incoming message bubbles have no avatar. `_MessageRow` at `chat_screen.dart:2635-2646` passes no image into `_Bubble` (line 3068). The `Avatar` widget at `lib/screens/chat/widgets/avatar.dart:6` is used in the conversation list (`conversation_list_screen.dart:282`) and chat header (`chat_screen.dart:1859`), but never beside a message.
6. Header and list resolve avatars differently. The header uses `Supa.getProfile` at `supabase.dart:93-99`, which reads `visible_profiles` and masks `avatar_url` by `photo_visibility`; the list reads `converse_rows.peer_avatar_url` through `supabase.dart:1114`. Default visibility is `everyone` in the linked project, so this is a consistency gap rather than the current outage.
7. The conversation list refetches every 5 seconds even when nothing changed (`supabase.dart:1138-1150`).
8. Desktop chat is one 600 px message column plus `NavSidebar` (`chat_screen.dart:2126,2221`). There is no conversation list pane beside it.
9. The voice player has no duration, progress, or seek; `_VoiceMessage` spans `chat_screen.dart:2775-2924` and renders a filename and toggle only.
10. In-chat message search does not exist. People search and suggestions already do: `conversation_list_screen.dart:159,171,540-584` and the `/suggest-friends` route at `lib/main.dart:238`. The earlier "no suggestions" report looks stale. Verify it on a device before writing code.

## Product checks

- Who: BRO users on Android and web who send voice notes and read 1:1 or circle chats.
- Pain: a recorded voice note does not play on the receiving device; a photo set in settings never appears next to messages.
- Why now: the recording, storage, and avatar components all exist. The gaps are wiring, not new infrastructure.
- 10-star: reliable E2EE media with waveforms, desktop two-pane chat, and instant sync across devices.
- MVP: a voice note that plays on the other device and peer photos visible in the chat surface.
- Anti-goals: no X3DH/Double Ratchet work here (tracked in `docs/OVERHAUL_CHECKLIST.md`, Phase 2), no route changes, no visual refresh, no rewrite of the 5,506-line `ChatScreen`, no new storage buckets.

## Priority

ICE = impact x confidence / effort.

| Phase | Candidate | I | C | E | Score |
| --- | --- | --- | --- | --- | --- |
| A | Voice note correctness | 5 | 5 | 2 | 12.5 |
| B | Peer photos in the chat surface | 4 | 4 | 2 | 8.0 |
| C | Realtime conversation list | 3 | 4 | 3 | 4.0 |
| D | Desktop two-pane chat | 4 | 4 | 5 | 3.2 |
| E | In-chat message search | 3 | 3 | 3 | 3.0 |

## Phase A: voice notes that work (implemented)

Independently shippable. No schema change needed.

1. In `_VoiceMessage._toggle`, resolve the object path with `Supa.attachmentUrl(_path!)` before calling `AudioPlayer.play`. Cache the signed URL and refresh it when playback is retried after the 3600 s expiry. Handle resolve failure with a visible "Could not load voice note" state instead of a silent no-op.
2. Change `VoiceNoteService.stopAndUpload` to return only the object path and metadata. Have `ChatScreen` wrap that in the existing `PendingMessage` path via `_addPending` (`chat_screen.dart:533`) and `_flushOutbox` (`chat_screen.dart:128`), so legacy gating, optimistic status, and retry behave like text messages. Keep `content_format` consistent with the rest of the outbox.
3. Replace the empty-string failure contract with a typed result carrying the failure reason, and surface it in `_VoiceNoteDialog` at `chat_screen.dart:2934-3066`.
4. Enforce the 60 s cap with a timer started in `VoiceNoteService.start` and a UI countdown in the dialog. Change the copy to "Tap to start recording, tap again to stop" so it matches `onTap`, or implement real hold semantics. Do not keep the current mismatch.
5. On web, keep playback and hide the mic action when recording is unsupported instead of letting `dart:io.File` fail at runtime. Add a clear tooltip explaining the platform limit.
6. Tests: unit tests for the voice content codec and signed-URL resolution, plus a widget test for idle, recording, sending, and failed states of the voice dialog.

## Phase B: peer photos in the chat surface

1. Add an avatar slot to `_MessageRow` and `_Bubble`, driven by the conversation's `peerAvatarUrl` (`Conversation.peerAvatarUrl`, mapped at `supabase.dart:1114`). Show it only on the last bubble in an incoming group so grouped messages stay clean.
2. Keep `Avatar` as the single rendering path so digital avatars and initials fallback continue to work (`avatar.dart:32-61`).
3. Add a widget test covering an incoming bubble with a URL, a grouped bubble without one, and the initials fallback.
4. Verify with two real accounts after shipping. Do not rebuild people suggestions; confirm the existing row at `conversation_list_screen.dart:540-584` is visible on web and Android first.

## Phase C: realtime conversation list

1. Mirror the shipped circle pattern from v1.5.6: add `conversations`, `conversation_participants`, and `messages` to the Realtime publication, and verify with `pg_publication_tables`.
2. Add a `Supa.watchConversations()` broadcast stream with `postgres_changes`, debounce bursts, and keep the 5 s poll as fallback (`supabase.dart:1141`). Cancel the channel and poll on stream cancellation.
3. Verify unread counts still refresh after sends from another device.

## Phase D: desktop two-pane chat

1. Place the conversation list and `ChatScreen` side by side inside `ResponsiveAppShell`. `ChatScreen` currently adds its own `NavSidebar` at `chat_screen.dart:2129`; remove that duplicate when embedded so desktop does not show two nav rails.
2. Escape clears selection, arrow keys move through the list, focus rings use the existing accent token. No decorative motion.

## Phase E: in-chat message search

1. Add a search field scoped to the open conversation, with a result count and jump-to-message using the existing `_scrollToMessage` at `chat_screen.dart:640`.
2. Keep it local-only. No new RPC unless measurement shows the message list cannot be held in memory.

## Verification gates

- `flutter analyze --no-fatal-infos` clean.
- `flutter test` green, including the new voice and avatar tests.
- `node supabase/tests/bro_calls_push.mjs`, `scheduled_and_search.mjs`, and `circle_invites.mjs` green when migrations change.
- `scripts/build.sh` web build succeeds; check the live PWA after release.
- CI green on the tag before calling a phase done.
- Two-account device check for voice note playback and avatar display. These cannot be proven by unit tests.

## Risks

- Signed URLs expire after an hour; playback must refresh on retry.
- Voice notes remain plaintext via legacy messaging until the separate E2EE work lands. Say so in the UI, do not imply end-to-end encryption.
- `ChatScreen` is large and stateful; keep Phase A changes narrow and use widget tests to catch regressions.
- Hiding web recording is a deliberate platform limit, not a permanent decision. Reconsider when a web recorder path is implemented.

## Next step

Start Phase A. It fixes a feature that records successfully but cannot be played by the recipient, and it needs no schema migration or route change.
