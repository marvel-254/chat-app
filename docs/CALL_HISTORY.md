# BRO call history and camera controls (Phase 11)

## Data architecture

Call history is stored in Supabase `public.call_history` (migration `20261121020000_call_history.sql`) and mirrored locally with `shared_preferences`.

- One row per participant per `call_id`, with `unique (user_id, call_id)`. A late or duplicated signalling event cannot create a second row or overwrite the final state through the UI dedupe rules.
- RLS restricts every read, write and delete to `auth.uid() = user_id`.
- Indexes cover `(user_id, started_at desc)`, `conversation_id` and missed calls.
- No recordings, media or technical diagnostics are stored. `failure_reason` is a short, user-safe note only.

`CallHistory` writes the final event once when the call ends. If Supabase is unavailable the event is queued locally and retried on the next screen open or pull-to-refresh. The Recent Calls screen shows cached records immediately with an offline banner and retry action.

## Outcome classification

`resolveCallStatus` in `lib/models/call_history.dart` is the single source of truth:

- outgoing + connected: `completed`
- outgoing + local hangup before connect: `cancelled`
- outgoing + peer hangup before connect: `unanswered`
- incoming + connected: `completed`
- incoming + local hangup before answer: `rejected`
- incoming + peer hangup before answer: `missed`
- timeout: missed for incoming, unanswered for outgoing
- network or permission failure: `failed`

A cancelled outgoing call is never classified as missed.

## Duration

Duration starts only when the WebRTC connection reaches `connected`, via `_startDurationTimer()` in `lib/screens/call_screen.dart`. Reconnections do not reset it. The timer stops when the call ends. Unanswered, missed, rejected and cancelled calls store `duration_seconds = 0` and display `Not connected`. Formatting is in `formatCallDuration` (`2 min 34 sec`).

## Missed-call notifications

The `dispatch_missed_call_push` trigger posts an outgoing webhook only for newly inserted rows with `status = 'missed'` and `direction = 'incoming'`. The `push-new-message` Edge Function:

- accepts `MISSED_CALL` webhooks,
- delivers only to the callee,
- deduplicates on `missed:<call_id>:<user_id>` in `public.notification_deliveries`,
- sends a generic `Missed call` notification with no caller name or message content,
- includes only `conversation_id`, `call_id` and `kind` in the data payload,
- checks `public.notification_settings.missed_call_push` before sending. Users control this in Settings > Notifications > Missed call alerts (migration `20261121030000_notification_preferences.sql`).

Tapping the notification routes to `/calls?call_id=...` and opens the call details sheet after the session is verified. The client validates the call id and conversation membership before navigating.

## Recent Calls UI

`lib/screens/calls/recent_calls_screen.dart` uses the shared `ResponsiveAppShell` and `HomeNavBar`. Calls are a first-class navigation destination on mobile and desktop.

- Filters: All, Missed, Incoming, Outgoing.
- Entries show contact, avatar, voice/video type, direction, status, time and duration for completed calls.
- Tap opens a details sheet with contact, type, direction, status, times, duration, failure note, call back, video call and profile actions.
- Individual delete and clear-all both require confirmation.
- Empty, loading, offline and retry states are implemented.
- The data source and peer resolver are injectable, so widget tests run without Supabase.

## Video camera switching

`CallScreen` detects available cameras with `Helper.cameras` after `getUserMedia`. The switch control:

- is disabled when fewer than two cameras are available,
- shows a progress indicator while switching,
- uses `Helper.switchCamera(track)` on native and a targeted device id plus stream on web,
- never rebuilds the peer connection, touches audio tracks, changes speaker routing or resets the duration timer,
- guards against overlapping switches, unmounted screens and call termination during a switch,
- reports permission or hardware failures with a user-safe snackbar.

## Verification

- `flutter analyze --no-fatal-warnings --no-fatal-infos`: no errors.
- `flutter test`: 100 tests pass, including 12 new domain/widget tests for status classification, duration formatting, dedupe, notification routing, filters, empty state and details navigation.
- Migration applied to linked project `dbfgyehzgrmsajpwydps`; RLS and trigger verified.
- `push-new-message` Edge Function redeployed with missed-call support.

## Remaining manual checks

Physical-device checks are still required for front/rear switching on real hardware, background FCM delivery, cold-start notification tap-through and single-camera devices. These are documented, not claimed as executed here.
