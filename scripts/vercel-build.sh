#!/usr/bin/env bash
# Vercel build script for BRO.
#
# The landing page (static HTML) is the priority and MUST always deploy.
# The Flutter web app (/app/) is secondary — if the Flutter build fails,
# we still deploy the landing page with all assets including the hero video.
#
# Vercel does not provide Flutter, so we clone the SDK from cache or GitHub.
# This clone can fail (network, timeout, branch gone) — the script handles
# that gracefully by falling back to the static landing page.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# ── Always ensure the landing page and assets are in the output ──────────
mkdir -p build/web/assets build/web/css build/web/icons build/web/legal
cp web/index-landing.html build/web/index.html
cp -r web/assets/. build/web/assets/ 2>/dev/null || true
cp -r web/css/. build/web/css/ 2>/dev/null || true
cp -r web/icons/. build/web/icons/ 2>/dev/null || true
cp -r web/legal/. build/web/legal/ 2>/dev/null || true
cp web/manifest.json web/robots.txt web/sitemap.xml web/llms.txt web/favicon.png build/web/ 2>/dev/null || true

echo "✅ Landing page + assets copied"

# ── Build the Flutter web app ────────────────────────────────────────────
# The authenticated app is the primary product. Never silently deploy a
# landing-only build: a green Vercel deployment must contain /app/.
FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.7}"
CACHE_ROOT="${VERCEL_CACHE_DIR:-$ROOT/.vercel/cache}"
FLUTTER_SDK="$CACHE_ROOT/flutter-$FLUTTER_VERSION"
export PUB_CACHE="${PUB_CACHE:-$CACHE_ROOT/pub-cache}"
export BASE_HREF="${BASE_HREF:-/app/}"

clone_flutter() {
  rm -rf "$FLUTTER_SDK"
  mkdir -p "$CACHE_ROOT"
  echo "Cloning Flutter $FLUTTER_VERSION..."
  git clone --depth 1 --branch "$FLUTTER_VERSION" \
    https://github.com/flutter/flutter.git "$FLUTTER_SDK"
}

prepare_flutter() {
  export PATH="$FLUTTER_SDK/bin:$PATH"
  flutter config --no-analytics >/dev/null
  # A cached SDK can exist without its web engine artifacts. Precache is
  # deliberately part of validation so the build cannot fail halfway through.
  flutter precache --web
  flutter --version
}

if [[ ! -x "$FLUTTER_SDK/bin/flutter" ]]; then
  clone_flutter
fi

if ! prepare_flutter; then
  echo "Cached Flutter SDK is unusable. Recreating it."
  clone_flutter
  prepare_flutter
fi

./scripts/build.sh web

test -s build/web/index.html
test -s build/web/app/index.html
echo "✅ Build complete — landing page and Flutter app are ready"
