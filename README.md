# BRO — a messaging app built with Flutter

A beautifully dark messaging app with automatic updates, voice notes, and a modern dark-mode UI.

**Security rollout: not production-verified.** See the [security, calls and push runbook](docs/security-calls-push.md) for the threat model, configuration, migration order, rollback and device test matrix. BRO production is blocked by [#107](https://github.com/marvel-254/chat-app/issues/107).

## Getting Started

Before running the app, configure its Supabase project. Create a local `.env.local` file (it is gitignored) with `SUPABASE_URL` and `SUPABASE_ANON_KEY`, using the Project URL and publishable/anon key from your Supabase project settings. Build with `./scripts/build.sh` (or `./scripts/build.sh web`). The app shows a setup message instead of starting with a fake backend endpoint when either value is missing.

The GitHub Pages workflow builds the browser app with BRO's public Supabase URL and publishable key; those are client-side values, never a service-role key. The signed APK workflow reads repository secrets named `SUPABASE_URL` and `SUPABASE_ANON_KEY`.

## Chat features

See [HANDOFF.md](HANDOFF.md) for the architecture, storage flow, migrations, local setup, and release operations.

Apply the migrations in `supabase/migrations` to the configured Supabase project before using chat uploads or calls. The media migrations create the public avatar bucket, private conversation-file and chat-background buckets, storage access rules, and private Realtime policies for call signaling. Chat backgrounds include built-in themes and private uploaded images.

Calls use authenticated, DM-scoped signaling, expiring invitations and short-lived TURN credentials. A configured relay and the matching backend migrations are required. Background incoming notifications additionally require Firebase setup.

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

## Vercel production deployment

The existing `bro-landing` Vercel project is linked to this repository's `main` branch and builds the landing page and Flutter web app together, with the app mounted under `/app/`. `vercel.json` configures Vercel's native Git build, and `scripts/vercel-build.sh` installs the pinned Flutter SDK into Vercel's build cache before running `scripts/build.sh web`. The landing page's relative `app/` link therefore stays on the same hostname (`bro.omixsystems.store`). Vercel's production environment needs the public `SUPABASE_URL` and `SUPABASE_ANON_KEY` variables; do not configure a service-role key in the browser build. GitHub Pages remains configured as a legacy/fallback deployment for now.

## Cloudflare file storage

Private Supabase Storage is the default. To use existing R2 files, first deploy the BRO-configured Worker in `cloudflare/storage`, bind the correct bucket, set its `SUPABASE_ANON_KEY` and `URL_SIGNING_SECRET` as Worker secrets, and set the public `CLOUD_STORAGE_URL` on the client build. Verify old and new objects with authorized and unauthorized accounts. Historical paths still require their original backend. New chat attachments upload opaque ciphertext, unlike public/profile or timeline assets.

## Auto-update

BRO checks for updates automatically. When a new release is published on GitHub Releases, the app shows an in-app update dialog. The update service downloads the APK from the release asset, verifies the embedded manifest (package name, version code, and version name), and offers to install it.

End users receive updates automatically. To publish a new release:

1. Create a new GitHub Release with the APK attached (e.g., `build/app/outputs/flutter-apk/*-release.apk`).
2. Tag the release as `v<version>` (e.g., `v1.0.0`).
3. The app detects the new release and prompts the user to update.

The release must include a manifest file embedded in the APK for the app to verify the update. See `lib/services/update_logic.dart` for the manifest format.

## License

Copyright © 2026 marvel-254. All Rights Reserved — see [LICENSE](LICENSE).
NYX is proprietary software: the source is viewable but no usage, modification, or distribution rights are granted.
