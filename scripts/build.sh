#!/usr/bin/env bash
# Local build wrapper for BRO.
#
# Auto-loads build config from the gitignored .env.local and injects it as
# --dart-define values, so you never pass the Supabase key (or any secret) on
# the command line. The real values live ONLY in .env.local, which is gitignored.
#
# Usage:
#   ./scripts/build.sh            # release APK (split per-abi)
#   ./scripts/build.sh web        # web build
#   ./scripts/build.sh --help
#
# .env.local must define SUPABASE_URL and SUPABASE_ANON_KEY with the
# values from the Supabase project settings. Do not commit this file.
set -euo pipefail

cd "$(dirname "$0")/.."

# Collect --dart-define flags from .env.local if it exists.
DEFINES=()
if [[ -f .env.local ]]; then
  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    # Skip blank lines and comments.
    [[ -z "$key" || "$key" == \#* ]] && continue
    # Trim surrounding whitespace and quotes.
    key="$(echo "$key" | xargs)"
    value="$(echo "$value" | sed 's/^"\(.*\)"$/\1/; s/^'\''\(.*\)'\''$/\1/')"
    case "$key" in
      SUPABASE_URL|SUPABASE_ANON_KEY|CLOUD_STORAGE_URL|CALL_RELAY_ONLY|FIREBASE_WEB_API_KEY|FIREBASE_WEB_APP_ID|FIREBASE_WEB_SENDER_ID|FIREBASE_WEB_PROJECT_ID|FIREBASE_WEB_VAPID_KEY)
        if [[ -z "${!key:-}" ]]; then export "$key=$value"; fi ;;
    esac
  done < .env.local
fi

# CI and shell environments can provide the public Supabase client config too.
# These values are safe for client apps; never pass a service-role key here.
for key in SUPABASE_URL SUPABASE_ANON_KEY CLOUD_STORAGE_URL CALL_RELAY_ONLY FIREBASE_WEB_API_KEY FIREBASE_WEB_APP_ID FIREBASE_WEB_SENDER_ID FIREBASE_WEB_PROJECT_ID FIREBASE_WEB_VAPID_KEY; do
  value="${!key:-}"
  if [[ -n "$value" ]]; then
    DEFINES+=(--dart-define="${key}=${value}")
  fi
done

# Tag Sentry events with the same release across Vercel, GitHub Pages, and
# local builds. APP_RELEASE can be overridden by CI when needed.
if [[ -z "${APP_RELEASE:-}" ]]; then
  APP_VERSION="$(awk '/^version:/{print $2; exit}' pubspec.yaml)"
  APP_RELEASE="bro@${APP_VERSION:-dev}"
fi
DEFINES+=(--dart-define="APP_RELEASE=${APP_RELEASE}")

TARGET="${1:-apk}"
# Base href for the PWA. Local dev defaults to /app/; CI (GitHub Pages
# project site) passes e.g. /chat-app/app/ via BASE_HREF env var.
BASE_HREF="${BASE_HREF:-/app/}"
case "$TARGET" in
  apk)
    flutter build apk --release --split-per-abi "${DEFINES[@]}"
    ;;
  web)
    # Build Flutter web app with base-href for the PWA subdirectory
    flutter build web --release --base-href "$BASE_HREF" "${DEFINES[@]}"
    # Move compiled Flutter app into build/web/app/ (PWA lives under /app/)
    mkdir -p build/web/app
    for entry in $(ls build/web); do
      if [ "$entry" != "app" ]; then
        mv "build/web/$entry" "build/web/app/$entry"
      fi
    done
    # Copy landing page and assets to build/web/ root
    mkdir -p build/web/css build/web/icons build/web/assets build/web/legal
    cp web/index-landing.html build/web/index.html
    cp web/index.html build/web/app.html
    cp web/manifest.json web/robots.txt web/sitemap.xml web/llms.txt web/favicon.png build/web/ 2>/dev/null || true
    cp web/service-worker.js build/web/app/service-worker.js
    node scripts/web-push-config.mjs build/web/app/push-config.js
    cp -r web/css/. build/web/css/
    cp -r web/icons/. build/web/icons/
    cp -r web/assets/. build/web/assets/
    cp -r web/legal/. build/web/legal/
    # Landing page links to the PWA under /app/ and contains no private-only design docs.
    ;;
  --help|-h)
    echo "Usage: ./scripts/build.sh [apk|web]"
    echo "  apk (default): release APK, split per ABI, secrets from .env"
    echo "  web:           web release build (landing page + PWA at /app/), secrets from .env"
    echo "  Env: BASE_HREF defaults to /app/ (override for project-site subpaths)"
    ;;
  *)
    echo "Unknown target: $TARGET (use: apk, web, --help)" >&2
    exit 1
    ;;
esac
