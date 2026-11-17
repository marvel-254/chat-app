#!/usr/bin/env bash
# Vercel's native Git integration has Node but not Flutter. Download the pinned
# Flutter SDK into Vercel's persistent build cache, then assemble the site.
#
# The landing page (static HTML) is critical and must always deploy. If the
# Flutter web build fails, we still copy the landing page and all assets so
# the site remains functional with the hero video background.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.7}"
CACHE_ROOT="${VERCEL_CACHE_DIR:-$ROOT/.vercel/cache}"
FLUTTER_SDK="$CACHE_ROOT/flutter-$FLUTTER_VERSION"

if [[ ! -x "$FLUTTER_SDK/bin/flutter" ]]; then
  mkdir -p "$CACHE_ROOT"
  rm -rf "$FLUTTER_SDK"
  git clone --depth 1 --branch "$FLUTTER_VERSION" \
    https://github.com/flutter/flutter.git "$FLUTTER_SDK"
fi

export PATH="$FLUTTER_SDK/bin:$PATH"
export PUB_CACHE="${PUB_CACHE:-$CACHE_ROOT/pub-cache}"
export BASE_HREF="${BASE_HREF:-/app/}"

flutter config --no-analytics
flutter --version

# Try the Flutter web build; if it fails, continue so the landing page still deploys.
if ./scripts/build.sh web; then
  echo "✅ Flutter web build succeeded"
else
  echo "⚠️  Flutter web build failed — deploying landing page only"
  # Ensure the output directory exists with the landing page
  mkdir -p build/web
  cp web/index-landing.html build/web/index.html
fi

# Always copy web assets (landing page assets, branding, video, etc.)
# This ensures the hero background video is always available.
mkdir -p build/web/assets build/web/css build/web/icons build/web/legal
cp -r web/assets/. build/web/assets/ 2>/dev/null || true
cp -r web/css/. build/web/css/ 2>/dev/null || true
cp -r web/icons/. build/web/icons/ 2>/dev/null || true
cp -r web/legal/. build/web/legal/ 2>/dev/null || true
cp web/manifest.json web/robots.txt web/sitemap.xml web/llms.txt web/favicon.png build/web/ 2>/dev/null || true

# Verify the landing page deployed
test -s build/web/index.html
echo "✅ Landing page deployed successfully"
