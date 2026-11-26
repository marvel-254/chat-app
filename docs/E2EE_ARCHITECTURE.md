# BRO E2EE protocol selection (internal ADR)

Status: implementation in progress; not yet ready to advertise as fully E2EE.

## Decision

Use the **Signal Protocol** via the `libsignal` Dart package (version 9.x), which binds the official Signal `libsignal` Rust core (v0.106.x). Do not implement cryptographic primitives, key derivation for sessions, or wire formats in BRO.

Rejected alternatives:

- Continuing the current scheme in `lib/services/e2ee.dart`: keys are deterministically derived from sorted participant IDs (`deriveSharedKey`) and decryption failures return plaintext. This is not encryption against a server adversary and must be removed.
- Hand-rolled X25519 + AES-GCM: would invent a protocol and omit forward secrecy, replay protection, identity binding and session management.
- `dart_signal_protocol` / `kennss/dart-signal-protocol`: its own SECURITY.md states there has been no external third-party audit, and it carries unresolved caller obligations (direct ratchet decrypt rollback risk, in-memory replay cache, dart:io web breakage).
- `libsignal_protocol_dart`: pure Dart and web-friendly but a separate implementation of the protocol with no independent audit and GPL-3.0 licensing.
- `libsignal` (chosen): wraps the upstream audited Signal implementation, supports Android/iOS/desktop and Flutter Web through WASM (dart2js builds), and exposes X3DH, Double Ratchet, prekeys, sealed sender, safety numbers and durable store interfaces.

## Licensing caveat

`libsignal` is AGPL-3.0. That is a copyleft licence with obligations for network-facing distribution. BRO is currently distributed as closed-source APKs and a hosted web app. This is a legal decision that cannot be resolved by code: **product owner must confirm AGPL-3.0 compliance or choose a licensed alternative before commercial distribution.** The implementation work below does not change that obligation. No private keys are ever sent to the server.

## Architecture

- One cryptographic identity per installed device: identity key pair, signed prekey, one-time prekeys, registration ID. Private keys stay in `flutter_secure_storage` / Android Keystore-backed storage; only public material is uploaded.
- Server stores public device keys, prekey bundles and device metadata. No private key material is accepted by any API.
- Sender builds an X3DH session from the recipient's public bundle; messages use Double Ratchet ciphertext with authenticated encryption, per-message keys, replay protection and forward secrecy.
- Every message carries an encryption envelope version. A message that claims to be encrypted but cannot be decrypted is shown as an error, never as plaintext.
- Legacy plaintext rows remain readable as an explicit, clearly labelled migration class; new sends are encrypted only. There is no silent downgrade.
- File, voice, GIF, and scheduled-message sending is disabled until client-side encryption and per-device delivery are implemented. Existing uploaded media is not retroactively encrypted.
- Device revocation removes registered public keys; existing sessions are discarded. Identity changes are surfaced to users, never silently accepted.

## Required infrastructure

- Supabase tables and RLS for `signal_devices`, `signal_prekeys`, `signal_signed_prekeys`, `signal_sessions` (if sessions are server-relayed) and `signal_device_revocations`, plus RPCs for atomic prekey reservation and bundle lookup.
- Build hook must provision `web/pkg/libsignal_frb.js` and WASM assets for Flutter Web (dart2js only; dart2wasm is not supported upstream).
- TURN credentials for calls and a Firebase service account / web push VAPID key for notifications (separate ADRs pending audit results).

## Current implementation limits

- New text messages use Signal ciphertext by default and the database migration rejects new plaintext message inserts. Both the client release and migrations must be deployed before that policy takes effect.
- The current bundle lookup and addressing are single-device. Account-scoped storage prevents one signed-in account from reusing another account's private keys on the same install, but delivery to multiple devices for one account still needs implementation before claiming multi-device support.
- New text messages require every participant to have opened a compatible client and published a public bundle. Sending fails closed if a bundle is missing.
- Existing messages remain legacy plaintext or legacy ciphertext and are not converted in place.
- The current client does not encrypt attachments, voice notes, GIF files, scheduled messages, or edit history; those send paths are disabled. Reactions and routing metadata remain visible to Supabase.
- Web and Android runtime interoperability, identity change behavior, and server RLS still require integration verification before general release.

## Fail-closed rules

1. No participant-ID-derived keys anywhere.
2. No plaintext fallback for a message that declares encryption.
3. No private keys in Supabase, logs, analytics, Sentry breadcrumbs or error reports.
4. Decryption errors are typed and reported; malformed payloads never advance ratchet state in BRO-managed code.
