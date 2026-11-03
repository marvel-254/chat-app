# Feature implementation handoff

## Current state

The requested feature list is in [`features.md`](features.md). It contains 22 planned headings spanning message controls, privacy, social/status, groups and polls, scanning, and games. The list is **not complete**; treat this as an in-progress branch, not a release-ready feature set.

### Implemented in the working tree

- Direct-message message controls have a first implementation: a per-chat expiry selector (off, 24 hours, 7 days, 30 days), expiry on newly sent text messages, long-press actions to pin/unpin, edit, or copy, and pinned/edited indicators.
- Profile model/service work exists for About text, three visibility preferences, last-seen writes, and follow/unfollow operations.
- Settings has About and visibility selectors. These currently persist preferences but **do not yet enforce visibility for other users**.
- Firebase plugin registration was regenerated for macOS and Windows.

### Database state

- `20261103000000_message_controls.sql` was applied to the linked Supabase project using `supabase db push --linked`; a follow-up migration list showed it applied.
- `20261104000000_profile_privacy_presence.sql` is in the local tree and **has not been applied**.
- The message-controls migration adds `expires_at`, pin/edit fields, per-message reads, and a server-side 15-minute edit guard. It defines `delete_expired_messages()` but no scheduled invocation is configured; expired messages are hidden by the client after expiration, while physical cleanup needs a scheduled job.
- `message_expiry` is stored per conversation. A profile-level default timer has not been implemented.

## Important gaps and risks

- Read receipts are written to `message_reads`, but message streaming does not join that table and the UI still relies on the legacy `messages.read_at` field. Receipt indicators and the opt-out preference are incomplete.
- Pinning currently supports the current user's own messages only; the documented message cap and pinned-message header/list are absent.
- Edit history stores the original text but there is no history UI. Editing attachments is disabled.
- Status creation/viewing UI and media upload are absent. The local schema supports text/media path/mood, but the status media path has no storage flow yet.
- Photo/about/status visibility is not enforced in profile reads or avatar rendering. Public avatars cannot meet a “Nobody” guarantee until storage and read access are redesigned; do not claim this is secure privacy yet.
- The profile migration's `user_follows` read policy permits all authenticated users to inspect follow edges. Review whether that is acceptable before applying it.
- The profile migration does not provide group, poll, self-chat, chat-lock, scan, reaction, or game functionality.
- No Supabase deployment was performed for the profile migration.

## Verification

- Previous `flutter analyze` and `flutter test` passed before the latest Settings edits.
- Latest `flutter analyze` reports three deprecation infos: replace `DropdownButtonFormField.value` with `initialValue` at `lib/main.dart` lines 2979–2981.
- Tests have not been rerun since the feature changes.
- A web release build passed earlier in the session. Android build was unavailable because the local Android SDK was missing; a GitHub APK download attempt failed mid-transfer.

## Recommended next work

1. Fix the analyzer deprecations and run analyzer/tests.
2. Complete and review the profile migration, including RLS and privacy semantics, then apply it to the intended linked Supabase project.
3. Enforce privacy through server-side/profile read APIs and migrate avatar storage away from public URLs before promising photo privacy.
4. Finish message reads (preference, realtime data, indicators), pin limits/list, conversation-default timers, and scheduled expiry cleanup.
5. Implement statuses and follow lists, then groups and polls, self-chat, chat lock, scanning, emoji reactions, and games.
6. Update each status in `features.md` only after the feature is implemented and checked. The current status table still describes everything as planning and is stale.

## Working tree notes

Do not remove the pre-existing untracked `docs/` directory. The current generated registrant diffs were produced by Flutter after the Firebase dependencies were already declared; keep them if macOS/Windows plugin registration is intended.
