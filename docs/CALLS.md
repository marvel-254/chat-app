# BRO call reliability and TURN

## Current implementation

- WebRTC via `flutter_webrtc`; signalling is Supabase Realtime broadcast on `call:<conversationId>` with private channels.
- Typed state machine in `lib/services/call_state_machine.dart`: outgoing, incoming, ringing, accepted, connected, reconnecting, ended, failed. Invalid transitions throw `InvalidCallTransition`.
- A 45-second ringing/answer timeout prevents calls stuck on "Calling…".
- ICE failure triggers a bounded ICE restart (maximum 2 attempts per call, 12-second recovery window) using `RTCPeerConnection.restartIce()`. Repeated failure ends the call with `networkFailure` instead of retrying forever.
- All terminal paths cancel timers, stop tracks, close the peer connection, remove the Realtime channel and dispose renderers.

## TURN configuration

STUN alone cannot connect calls through some carrier networks and restrictive NATs. The app requests short-lived relay credentials from the authenticated `call-turn` Supabase Edge Function at runtime. The function supports Cloudflare Realtime TURN and coturn REST credentials; provider secrets stay on the server.

Chosen provider: Cloudflare Realtime TURN. Create a TURN key in the Cloudflare dashboard, then add these Supabase Edge Function secrets:

```sh
supabase secrets set \
  CLOUDFLARE_TURN_KEY_ID=<turn-key-id> \
  CLOUDFLARE_TURN_API_TOKEN=<turn-key-api-token> \
  --project-ref <supabase-project-ref>
```

The token must be a TURN key API token authorized to generate credentials for that key. The endpoint requests 12-hour credentials and only forwards Cloudflare TURN URLs to clients. Cloudflare documents 1,000 GB free TURN transfer, then $0.05/GB; confirm the current account terms before enabling usage.

Until those two secrets are configured, `call-turn` returns 503 and the app falls back to STUN. Calls may still work on permissive networks, but relay-dependent calls will fail. Never put the Cloudflare API token in the APK, web build, source, or `.env` file shipped to clients.

For a self-hosted coturn deployment instead, set `TURN_SHARED_SECRET` and comma-separated `TURN_URLS`; the function mints one-hour REST credentials. Do not configure both provider sets at once. `CALL_RELAY_ONLY=true` is reserved for diagnostics and forces calls to fail if relay is unavailable.

### Production verification (2026-11-25)

- `call-turn` is deployed and `ACTIVE` (version 1) on project `dbfgyehzgrmsajpwydps`.
- No TURN provider secrets are currently provisioned: neither the Cloudflare pair (`CLOUDFLARE_TURN_KEY_ID`, `CLOUDFLARE_TURN_API_TOKEN`) nor the coturn pair (`TURN_SHARED_SECRET`, `TURN_URLS`) is present. The function therefore returns 503 and clients fall back to Google STUN, which is expected to work only on permissive networks.
- To complete relay enablement, configure one provider pair via `supabase secrets set`, then invoke the function with a real authenticated user token and confirm the 200 response contains `turn:`/`turns:` URLs plus username and credential. Never place those tokens in client builds or tracked files.

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
