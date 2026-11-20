# Security, calls and push overhaul checklist

Working checklist for the BRO infrastructure overhaul. Update status as work lands.

## Phase 1: repository audit and architecture discovery

- [x] Flutter/Dart, Android, Web, messaging, crypto, WebRTC, push, Supabase, CI and tests audited (parallel subagent audits dispatched).
- [x] Current E2EE inspected: `lib/services/e2ee.dart` derives keys from participant IDs and falls back to plaintext.
- [ ] Consolidate audit findings into concrete risk register.
- [x] Protocol selection recorded in `docs/E2EE_ARCHITECTURE.md`.

## Phase 2: genuine E2EE

- [x] Added `libsignal 9.0.1` and verified a full Flutter Web build; Android APK build remains CI-only on this machine.
- [x] Migration `20261121000000_signal_identity_and_push.sql` applied to the linked BRO project; RLS verified on all new tables and `signal_claim_prekey` exists.
- [x] Per-device identity, signed/Kyber/one-time prekeys generated and stored in `flutter_secure_storage`; public bundles registered through RLS-protected tables. Multi-device receive remains single-device-id=1 pending full fan-out.
- [ ] Client: X3DH session establishment, Double Ratchet encrypt/decrypt, identity-change detection.
- [x] Removed `lib/services/e2ee.dart`; send throws on failure, receive shows explicit decryption/identity warnings.
- [ ] Encrypt text, replies, edits, reactions, scheduled messages, voice notes and attachments.
- [ ] Session recovery, offline recipients, failed/malformed decryption handling, device revocation.
- [x] Fail-closed unit tests added; full suite 92 tests passes. Multi-device live exchange and revocation tests remain outstanding.

## Phase 3: calls

- [ ] Audit findings applied: signalling auth, TURN configuration, ICE/DTLS lifecycle, call state recovery.
- [x] TURN defines and relay-only switch implemented; `docs/CALLS.md` records provisioning blocker.
- [ ] Add tests/config validation for signalling payloads and TURN env wiring.

## Phase 4: push

- [ ] Audit findings applied: token lifecycle, routing, privacy-preserving payloads, edge function hardening.
- [ ] Document Firebase credentials, web push VAPID requirements and unverified platform gaps.

## Phase 5: verification and release

- [x] Analyzer has no errors (28 info/warnings), 92 tests pass, web build succeeds.
- [ ] Migration list and RLS verified against linked project.
- [ ] CI green; release only after all blockers are resolved.
- [ ] No commit/deploy that claims E2EE while plaintext fallback remains.

## Phase 11 - Call history, missed calls and camera controls

- [x] Recent Calls screen in main navigation (mobile and desktop).
- [x] All statuses represented: completed, missed, rejected, cancelled, unanswered, failed.
- [x] Duration starts at connection and survives reconnections.
- [x] Filters, details sheet, callbacks, profile link, individual delete and clear-all.
- [x] Offline cache, pending write queue, loading/error/empty/retry states.
- [x] Supabase migration with RLS, unique `(user_id, call_id)` and indexes.
- [x] Missed-call push with deduplication and tap-through to call details.
- [x] Front/rear camera switch with busy state, resource-safe controls and no peer reset.
- [x] Tests added; full suite passes.
- [x] Documentation in `docs/CALL_HISTORY.md`.
- [ ] Physical-device verification of camera hardware and background push.
