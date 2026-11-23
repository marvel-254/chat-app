# TDD evidence: chat Phase A (voice notes)

Source plan: `docs/CHAT_IMPROVEMENT_PLAN.md`, Phase A.

## User journeys

1. As a BRO user on Android, I want to record a voice note and have it arrive in the chat with the same retry behaviour as a text message.
2. As the recipient, I want to tap a voice note and hear it, even though the audio lives in a private storage bucket.
3. As a web user, I want the app to be honest about unsupported recording instead of failing silently.

## RED and GREEN evidence

| Guarantee | RED evidence | GREEN evidence |
| --- | --- | --- |
| Voice content round-trips and malformed payloads are rejected | `flutter test test/voice_note_codec_test.dart` failed to compile: `Method not found: 'voiceNoteFailureMessage'` and `Undefined name 'VoiceNoteFailure'` | Same command: `All tests passed!` (7 tests) |
| Voice notes enter the durable outbox with encoded content and survive serialisation | `flutter test test/voice_note_send_test.dart` failed to compile: `Method not found: 'voiceNotePendingMessage'` | Same command: `All tests passed!` (4 tests) |

Commands were run from `/home/marvel/chat_app` with `export PATH="$HOME/flutter_sdk/bin:$PATH"`.

Full gate after implementation:

- `flutter analyze --no-fatal-infos`: completed with the analyzer clean (`=== ANALYZE OK ===`).
- `flutter test`: completed with all tests passing (`=== TESTS OK ===`).
- `./scripts/build.sh web`: see release verification below.

## Checkpoint commits

- `eaf3754` test: add voice note codec reproducer (RED)
- `f3a0028` fix: add tested voice note codec and limits (GREEN)
- `11426bd` test: add voice note outbox mapping reproducer (RED)
- `bd6be34` fix: route voice notes through the durable outbox (GREEN)
- `5e8c561` test: import codec in outbox mapping test (GREEN correction)

Correction note: `bd6be34` was labelled GREEN before the test actually passed. The remaining failure was a missing test import, not a production bug. It was fixed and the suite rerun green in `5e8c561`. This is recorded rather than rewritten.

## Test specification

| # | Guarantee | Test | Type | Result |
| --- | --- | --- | --- | --- |
| 1 | A storage path survives voice content encoding and decoding | `test/voice_note_codec_test.dart` | unit | PASS |
| 2 | Non-voice, malformed, and empty payloads never yield a path | `test/voice_note_codec_test.dart` | unit | PASS |
| 3 | Byte cap accepts exactly 20 MB and rejects one byte more | `test/voice_note_codec_test.dart` | unit | PASS |
| 4 | Duration cap accepts exactly 60 s and rejects one tick more | `test/voice_note_codec_test.dart` | unit | PASS |
| 5 | Every failure enum has distinct user-facing copy | `test/voice_note_codec_test.dart` | unit | PASS |
| 6 | Failed outcomes carry no enqueueable content | `test/voice_note_send_test.dart` | unit | PASS |
| 7 | Pending voice messages keep content, sender, conversation and expiry | `test/voice_note_send_test.dart` | unit | PASS |
| 8 | Voice content survives outbox JSON round-trip | `test/voice_note_send_test.dart` | unit | PASS |

## Coverage and known gaps

- The pure codec/outbox layer is directly tested. Overall project coverage was not measured with `flutter test --coverage`; the full suite is green.
- Signed URL resolution, recorder lifecycle, and the web mic guard are verified by analyzer and web build, not by unit tests, because they depend on Supabase and platform channels.
- A two-account device check for recording, delivery, and playback is still required. It cannot be proven locally.
- Web recording is deliberately hidden; playback still works.

## Merge evidence

Phase A was released as part of the tag created from the green gate. CI and release assets are verified in the release commit history.
