# BRO — a messaging app built with Flutter

A beautifully dark messaging app with automatic updates, voice notes, and a modern dark-mode UI.

## Getting Started

Before running the app, configure its Supabase project. Create a local `.env.local` file (it is gitignored) with `SUPABASE_URL` and `SUPABASE_ANON_KEY`, using the Project URL and publishable/anon key from your Supabase project settings. Build with `./scripts/build.sh` (or `./scripts/build.sh web`). The app shows a setup message instead of starting with a fake backend endpoint when either value is missing.

Set `SUPABASE_URL` and `SUPABASE_ANON_KEY` in the GitHub Pages environment to BRO's verified project and publishable key. These are client-side values, never a service-role key. The signed APK workflow reads repository secrets named `SUPABASE_URL` and `SUPABASE_ANON_KEY`.

## Chat features

See [HANDOFF.md](HANDOFF.md) for the architecture, storage flow, migrations, local setup, and release operations.

Apply the migrations in `supabase/migrations` to the configured Supabase project before using chat uploads or calls. The media migrations create the public avatar bucket, private conversation-file and chat-background buckets, storage access rules, and private Realtime policies for call signaling. Chat backgrounds include built-in themes and private uploaded images.

Voice and video calls use WebRTC with private signaling; configure TURN for networks that block direct connections. Incoming calls can appear anywhere in the signed-in app. Use **Calls** to review, filter, and return recent calls.

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

## Vercel production deployment

The existing `bro-landing` Vercel project is linked to this repository's `main` branch and builds the landing page and Flutter web app together, with the app mounted under `/app/`. `vercel.json` configures Vercel's native Git build, and `scripts/vercel-build.sh` installs the pinned Flutter SDK into Vercel's build cache before running `scripts/build.sh web`. The landing page's relative `app/` link therefore stays on the same hostname (`bro.omixsystems.store`). Vercel's production environment needs the public `SUPABASE_URL` and `SUPABASE_ANON_KEY` variables; do not configure a service-role key in the browser build. GitHub Pages remains configured as a legacy/fallback deployment for now.

## Cloudflare file storage

The default backend for new attachments and chat backgrounds is Supabase Storage. BRO can optionally use the authenticated R2 worker in `cloudflare/storage`. Verify that the Worker points at the same BRO Supabase project before setting `CLOUD_STORAGE_URL`. Previously stored R2 objects require their original worker or an approved storage migration. The R2 worker's signing secret is server-side only.

## Auto-update

BRO checks GitHub Releases every six hours and offers an in-app APK update. The
build stamps its semantic version (`APP_VERSION`, injected from `pubspec.yaml`)
and compares it with release tags such as `v1.4.5`; local builds without that
define do not prompt.

The updater picks the arm64 APK for Android devices, checks that the download
is a ZIP/APK, and verifies it against the `sha256:` digest GitHub publishes for
the release asset before handing it to the Android installer. There is no
separate embedded manifest file. If no APK asset is available, the release page
is opened in the browser instead.

To publish a new release:

1. Create a GitHub Release with the three split APKs attached.
2. Tag it `v<version>` and keep `pubspec.yaml`'s version in sync.
3. The app detects the new tag on its next check and prompts the user.

See `lib/services/app_update.dart` for the comparison and verification logic.

## License

Copyright © 2026 marvel-254. All Rights Reserved — see [LICENSE](LICENSE).
NYX is proprietary software: the source is viewable but no usage, modification, or distribution rights are granted.

### Messaging, calls, and notifications

BRO's legacy messaging is **not end-to-end encrypted**. See the [security and infrastructure rollout guide](docs/security-calls-push.md) for the threat model, Recent Calls behavior, TURN, Android/Web push, deployment and validation steps.
