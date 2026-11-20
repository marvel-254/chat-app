# Release checklist (2026-11-20)
- [x] Inventory Flutter UI/services, Android activity/manifest, PWA, R2 worker, Supabase migrations/functions, CI and tests. Confirm project identity and report outage (#107).
- [x] Replace the insecure writer; route message/attachment/voice/reaction/schedule writes through authenticated encryption and remove false UI claims.
- [x] Add public-key ownership/revocation, local verification and legacy read-only history.
- [x] Implement TURN issuance, scoped signaling, invitation leases, capture service and recovery bounds.
- [x] Implement FCM token lifecycle, backend retry/claims and a real scoped background push worker.
- [x] Exercise new migrations and authorization under isolated PostgreSQL roles; add protocol, worker, attachment and delivery checks.
- [x] Document the threat model, operator setup, manual matrix and rollback.
- [ ] Independent security review and real device verification.
- [ ] Verify relay credentials, signaling timeouts, recovery and lifecycle on device pairs.
- [ ] Test real Firebase registration, expiry, account changes and browser background delivery.
- [ ] Reset a full staging stack, verify RLS and run Android/web release tests before rollout.

Initial risks: AES-GCM key material was reconstructible by the server, crypto exceptions returned plaintext, and undifferentiated base64 had no version or identity. Voice uploaded and inserted directly. Drafts, scheduled messages, files, reactions, webhook records and edit history bypassed the intended boundary. Outbox prefs were not secret storage. Call invite delivery was ephemeral and chat-scoped, establishment STUN-only with no deadline; cleanup awaited network before stopping capture. Push click membership was skipped when recipient matched. The pinned FlutterFire SDK actually supports registered FIDs and the current HTTP v1 schema has a distinct `fid` target; a raw installations ID is not a registration token. Do not relabel old registrations as tokens. See the runbook for implemented scope and release gates.
