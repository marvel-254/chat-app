# BRO — a messaging app built with Flutter

A beautifully dark messaging app with automatic updates, voice notes, and a modern dark-mode UI.

## Getting Started

Before running the app, configure its Supabase project. Create a local `.env.local` file (it is gitignored) with `SUPABASE_URL` and `SUPABASE_ANON_KEY`, using the Project URL and publishable/anon key from your Supabase project settings. Build with `./scripts/build.sh` (or `./scripts/build.sh web`). The app shows a setup message instead of starting with a fake backend endpoint when either value is missing.

For GitHub Actions builds, configure repository secrets named `SUPABASE_URL` and `SUPABASE_ANON_KEY`.

## Chat features

See [HANDOFF.md](HANDOFF.md) for the architecture, storage flow, migrations, local setup, and release operations.

Apply the migrations in `supabase/migrations` to the configured Supabase project before using chat uploads or calls. The media migrations create the public avatar bucket, private conversation-file and chat-background buckets, storage access rules, and private Realtime policies for call signaling. Chat backgrounds include built-in themes and private uploaded images.

Voice and video calls use peer-to-peer WebRTC with a public STUN server for connection setup. Calls work when the two networks can establish a direct WebRTC path; production deployments should configure a TURN relay for networks that block direct peer connections. Incoming calls are shown while the recipient has that conversation open.

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

## Cloudflare file storage

Chat attachments and custom chat backgrounds are stored in the private Cloudflare R2 bucket `chat-app-storage` through the authenticated Worker at `https://bro-chat-storage.twistedoliver211fs.workers.dev`. Avatar images remain in Supabase Storage. The Worker checks the signed-in Supabase user and conversation membership before issuing uploads or download links.

The Worker is configured in `cloudflare/storage`. To redeploy it, run `wrangler deploy` from that directory. Its `SUPABASE_ANON_KEY` and `URL_SIGNING_SECRET` are Cloudflare Worker secrets; do not add them to this repository. Local builds use the deployed Worker URL by default and can override it with `--dart-define=CLOUD_STORAGE_URL=...`.

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
