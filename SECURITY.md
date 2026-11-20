# Security Policy

## Supported versions

BRO is released from `main`. Security fixes are applied to the current release
line (1.4.x) and published as a new tagged release. Older release lines are not
patched; users should upgrade to the latest APK or web build.

| Version | Supported |
| ------- | --------- |
| 1.4.x   | ✅        |
| < 1.4   | ❌        |

## Reporting a vulnerability

Please do **not** open a public issue for a security problem. Use GitHub's
private vulnerability reporting for this repository:
https://github.com/marvel-254/chat-app/security/advisories/new

Include the affected component (Flutter client, Supabase schema/Edge Function,
Cloudflare storage worker, or web landing page), reproduction steps, and the
project/ref if the report concerns hosted infrastructure. For production, the
authorized Supabase project is **nyx** (`dbfgyehzgrmsajpwydps`).

You should receive an acknowledgement within five working days. We will confirm
the finding, agree on a disclosure timeline, and publish a fix and advisory
together where possible. Please allow us a reasonable window to remediate before
public disclosure.

## Scope and known limitations

- BRO's legacy message transport is **not end-to-end encrypted**. Server
  operators can read message content, attachments, drafts and scheduled
  messages. Do not describe it as E2EE.
- The local app lock is a device-convenience feature backed by PBKDF2 in
  platform secure storage; it is not a substitute for full-disk encryption.
- Sideloaded APK updates are verified against the SHA-256 digest published on
  the GitHub release asset. Android still performs its own signature check on
  installation.

See [docs/security-calls-push.md](docs/security-calls-push.md) for the current
threat model and deployment gates.
