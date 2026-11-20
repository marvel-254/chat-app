# BRO call reliability and TURN

## Current implementation

- WebRTC via `flutter_webrtc`; signalling is Supabase Realtime broadcast on `call:<conversationId>` with private channels.
- Typed state machine in `lib/services/call_state_machine.dart`: outgoing, incoming, ringing, accepted, connected, reconnecting, ended, failed. Invalid transitions throw `InvalidCallTransition`.
- A 45-second ringing/answer timeout prevents calls stuck on "Calling…".
- ICE failure triggers a bounded ICE restart (maximum 2 attempts per call, 12-second recovery window) using `RTCPeerConnection.restartIce()`. Repeated failure ends the call with `networkFailure` instead of retrying forever.
- All terminal paths cancel timers, stop tracks, close the peer connection, remove the Realtime channel and dispose renderers.

## TURN configuration

STUN alone is not sufficient across restrictive NATs. The app reads four build-time values:

| Define | Purpose |
| --- | --- |
| `TURN_URL` | TURN URI, e.g. `turn:turn.example.com:3478` |
| `TURN_USER` | short-lived username |
| `TURN_PASS` | short-lived credential |
| `TURN_RELAY_ONLY` | `true` removes STUN and forces relay for diagnostics |

Example:

```sh
flutter build apk --release \
  --dart-define=TURN_URL=turn:turn.example.com:3478 \
  --dart-define=TURN_USER=<short-lived-user> \
  --dart-define=TURN_PASS=<short-lived-credential>
```

**Deployment blocker:** no managed TURN account, coturn host or credential-minting service is configured for this project. The client integration is complete, but dependable calls across restrictive networks require provisioning one of:

1. A managed TURN provider with regional coverage.
2. Self-hosted coturn with TLS and short-lived credentials.

Short-lived credentials must be minted by an authenticated backend endpoint. Permanent TURN secrets must not be embedded in the APK, source, CI logs or `.env.example`. `--dart-define` values are compiled into the binary, so use them only with credentials whose lifetime is shorter than the app release lifetime, or replace them with a runtime fetch before production distribution.

## Manual testing matrix

Run each scenario on Android and Web where supported:

- Same Wi-Fi, different Wi-Fi, mobile data.
- Wi-Fi to mobile and back mid-call.
- Restrictive NAT with TURN disabled, then relay-only enabled.
- App backgrounded, screen locked, foregrounded.
- Microphone/camera permission denied and granted later.
- Incoming call after app termination.
- Temporary network loss and recovery.
- Repeated calls, hangup from either side, rejection, timeout.
- Bluetooth audio, speaker and earpiece routing.

## Diagnostics safety

The state machine records failure category and reconnection attempt count only. Never log media, SDP bodies containing credentials, auth tokens, message content or private keys.
