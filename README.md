# NYX

A beautifully dark messaging app built with Flutter.

## Getting Started

Before running the app, configure its Supabase project. Create a local `.env.local` file (it is gitignored) with `SUPABASE_URL` and `SUPABASE_ANON_KEY`, using the Project URL and publishable/anon key from your Supabase project settings. Build with `./scripts/build.sh` (or `./scripts/build.sh web`). The app shows a setup message instead of starting with a fake backend endpoint when either value is missing.

For GitHub Actions builds, configure repository secrets named `SUPABASE_URL` and `SUPABASE_ANON_KEY`.

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## License

Copyright © 2026 marvel-254. All Rights Reserved — see [LICENSE](LICENSE).
NYX is proprietary software: the source is viewable but no usage, modification, or distribution rights are granted.
