# BRO — a messaging app built with Flutter

A beautifully dark messaging app with voice notes, WebRTC calls, and a modern dark-mode UI.

## Getting Started

Before running the app, configure its Supabase project. Create a local `.env.local` file (it is gitignored) with `SUPABASE_URL` and `SUPABASE_ANON_KEY`, using the Project URL and publishable/anon key from your Supabase project settings. Build with `./scripts/build.sh` (or `./scripts/build.sh web`). The app shows a setup message instead of starting with a fake backend endpoint when either value is missing.

For GitHub Actions builds, configure repository secrets named `SUPABASE_URL` and `SUPABASE_ANON_KEY`, plus the release-signing secrets described under [Releases and signing](#releases-and-signing).

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

## Releases and signing

Pushing to `main` runs `.github/workflows/build-apk.yml`, which builds split
per-ABI release APKs and publishes them as GitHub Release `v<run number>`.

Every release **must** be signed with the same key, otherwise Android refuses to
install the update over an existing copy. The workflow therefore:

1. materialises `android/app/release.keystore` and `android/app/key.properties`
   from the `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS` and
   `KEY_PASSWORD` repository secrets, failing loudly if any is missing;
2. builds with `REQUIRE_RELEASE_SIGNING=true`, which makes
   `android/app/build.gradle.kts` refuse to fall back to the debug key;
3. runs `apksigner verify --print-certs` on every artefact and fails if a debug
   certificate is found.

Create the keystore once with `./scripts/generate_keystore.sh`, which also
prints the secret values to paste into GitHub. Keep the keystore backed up:
losing it makes in-place updates impossible for installed copies.

There is currently **no in-app auto-update**: the app does not check GitHub
Releases or install downloads itself. Users update by installing the newer APK
from the Releases page over the existing app (which works because the signing
key is stable).

To publish a release manually instead of via `main`:

1. Build and sign an APK (`./scripts/build.sh apk` needs a local `.env.local`).
2. Attach it to a GitHub Release tagged `v<version>` (e.g. `v1.0.0`).

## License

Copyright © 2026 marvel-254. All Rights Reserved — see [LICENSE](LICENSE).
BRO is proprietary software: the source is viewable but no usage, modification, or distribution rights are granted.
