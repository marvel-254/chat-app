# BRO threat model (draft, tied to the E2EE overhaul)

This document describes the security goals and limits of the in-progress overhaul. BRO must not be advertised as fully end-to-end encrypted until the implementation, tests and documented assumptions below are complete.

## Assets

- Message plaintext, edits, replies, reactions and read state.
- Attachment bytes (images, video, documents, voice notes).
- Long-term identity private keys, signed prekeys, one-time prekeys and Double Ratchet session state on each device.
- Supabase access tokens, FCM tokens, Web Push subscriptions, TURN credentials.

## Adversaries

1. **Honest-but-curious server / database read.** Supabase operators or an attacker with read access to the database must not obtain message plaintext or private keys.
2. **Compromised application server / Edge Function.** Must not obtain plaintext message content or private keys; public key material may be visible because it is necessary for delivery.
3. **Network attacker.** TLS protects transport; Signal Protocol must additionally provide confidentiality, integrity, replay resistance and forward secrecy for message content.
4. **Malicious peer.** Must not be able to impersonate another identity without detection after verification; must not be able to decrypt messages addressed to other devices.
5. **Stolen device.** Secure storage and Android Keystore raise the bar; account-level revocation must remove that device's ability to establish new sessions.
6. **Malicious push/call infrastructure.** Push payloads and call signalling must not reveal message content or grant access to conversations.

## Trust boundaries

- Client device: the only place private keys, plaintext and session state exist.
- Supabase: stores public device keys, prekeys, encrypted message envelopes, metadata and access tokens. Never private keys or plaintext.
- Cloudflare Worker/R2: stores opaque encrypted attachment objects. Signed download URLs are short-lived.
- FCM/Web Push: receive minimal, generic notifications; no plaintext for encrypted messages unless the user explicitly enables previews and the security model permits it.
- TURN: relays encrypted WebRTC media; credentials must be short-lived and never shipped in the APK.

## Security guarantees being implemented

- Per-device Signal identities; X3DH session establishment; Double Ratchet message keys; authenticated encryption.
- No deterministic keys derived from user IDs, no hardcoded keys, no silent plaintext fallback.
- Envelope versioning; failed decryption is a visible error state; legacy plaintext is labelled as legacy.
- Safety numbers / fingerprints for contact verification, with persistent identity-change warnings.
- Server-side ownership checks and RLS for device keys, prekeys, push tokens, subscriptions and preferences.

## Known limits and residual risks

- **Metadata remains visible:** conversation IDs, participant IDs, message timestamps, device IDs and delivery events are necessary for routing and are not hidden by this design.
- **Verification is opt-in until the user performs it:** first contact is trust-on-first-use. A hostile server can substitute keys before the first verification. Safety numbers must be shown prominently.
- **Multi-device:** each device has its own session. Compromise of one device does not reveal other devices' session state, but that device can read messages delivered to it until revoked.
- **Backups / account recovery:** no secure value recovery is implemented. Losing all devices loses access to session state and stored private keys; a documented reset flow must be explicit and must not silently create a new identity that peers accept without warning.
- **Calls:** WebRTC media is encrypted by SRTP, but call signalling and metadata go through Supabase Realtime. TURN is required for restrictive NATs; without it, calls may fail rather than fall back insecurely.
- **Push:** generic notifications are default. A message preview preference, if enabled by the user, is a deliberate confidentiality trade-off and must be documented in the UI.
- **Legacy data:** existing plaintext messages are not retroactively encrypted. They must be labelled and excluded from any claim of E2EE.
- **Library risk:** the chosen Signal binding wraps upstream libsignal but the Dart binding itself has no independent audit. Track upstream advisories and pin dependency versions.

## Deployment gates

Before claiming completion: all fail-closed tests pass; no `deriveSharedKey` or plaintext fallback path remains; RLS verified on the linked BRO project; web and Android builds succeed; identity verification and key-change warnings are user-visible; push payloads contain no plaintext; TURN credential flow is documented and no permanent secret is in the client.
