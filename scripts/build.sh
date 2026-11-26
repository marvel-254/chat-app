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
      SUPABASE_URL|SUPABASE_ANON_KEY|CLOUD_STORAGE_URL|CALL_RELAY_ONLY|FIREBASE_WEB_API_KEY|FIREBASE_WEB_APP_ID|FIREBASE_WEB_SENDER_ID|FIREBASE_WEB_PROJECT_ID|FIREBASE_WEB_VAPID_KEY|TURNSTILE_SITE_KEY)
        if [[ -z "${!key:-}" ]]; then export "$key=$value"; fi ;;
    esac
  done < .env.local
fi

# CI and shell environments can provide the public Supabase client config too.
# These values are safe for client apps; never pass a service-role key here.
for key in SUPABASE_URL SUPABASE_ANON_KEY CLOUD_STORAGE_URL CALL_RELAY_ONLY FIREBASE_WEB_API_KEY FIREBASE_WEB_APP_ID FIREBASE_WEB_SENDER_ID FIREBASE_WEB_PROJECT_ID FIREBASE_WEB_VAPID_KEY TURNSTILE_SITE_KEY; do
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

# Semantic version from pubspec.yaml, used by the auto-updater to compare
# GitHub release tags. Keep this in sync with the version published on Releases.
APP_VERSION_FULL="$(awk '/^version:/{print $2; exit}' pubspec.yaml)"
APP_VERSION_VALUE="${APP_VERSION_FULL%%+*}"
APP_BUILD_NUMBER_VALUE="${APP_VERSION_FULL#*+}"
if [[ "$APP_BUILD_NUMBER_VALUE" == "$APP_VERSION_FULL" ]]; then
  APP_BUILD_NUMBER_VALUE=""
fi
if [[ -n "${APP_VERSION_VALUE}" ]]; then
  DEFINES+=(--dart-define="APP_VERSION=${APP_VERSION_VALUE}")
fi
if [[ -n "${APP_BUILD_NUMBER_VALUE}" ]]; then
  DEFINES+=(--dart-define="BUILD_NUMBER=${APP_BUILD_NUMBER_VALUE}")
fi

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
    flutter build web --release --source-maps --base-href "$BASE_HREF" "${DEFINES[@]}"
    # Move compiled Flutter app into build/web/app/ (PWA lives under /app/).
    # Remove any previous /app directory first: mv into an existing directory
    # nests the source (assets/assets) and breaks repeat local builds.
    rm -rf build/web/app
    mkdir -p build/web/app
    shopt -s dotglob nullglob
    for entry in build/web/*; do
      name="$(basename "$entry")"
      [ "$name" = "app" ] && continue
      mv "$entry" "build/web/app/$name"
    done
    shopt -u dotglob nullglob
    # Copy landing page and assets to build/web/ root
    mkdir -p build/web/css build/web/icons build/web/assets build/web/legal
    cp web/index-landing.html build/web/index.html
    # Keep public metadata at both scopes: the landing page uses the site
    # root, while the Flutter app's relative links resolve under /app/.
    cp web/manifest.json web/robots.txt web/sitemap.xml web/llms.txt web/favicon.png build/web/ 2>/dev/null || true
    cp web/manifest.json web/favicon.png build/web/app/ 2>/dev/null || true
    cp web/service-worker.js build/web/app/service-worker.js
    node scripts/web-push-config.mjs build/web/app/push-config.js "$APP_VERSION_FULL"
    cp -r web/css/. build/web/css/
    cp -r web/icons/. build/web/icons/
    mkdir -p build/web/app/icons
    cp -r web/icons/. build/web/app/icons/
    cp -r web/assets/. build/web/assets/
    cp -r web/legal/. build/web/legal/
    # Fail the build if the PWA scope is missing metadata the service worker
    # precaches and the Flutter web template links to relatively.
    test -s build/web/app/index.html
    test -s build/web/app/manifest.json
    test -s build/web/app/icons/Icon-192.png
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
