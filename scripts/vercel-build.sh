#!/usr/bin/env bash
# Vercel's native Git integration has Node but not Flutter. Download the pinned
# Flutter SDK into Vercel's persistent build cache, then assemble the site.
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
./scripts/build.sh web

# Ensure web assets (including videos) are always copied to the output,
# even if the Flutter web build encounters issues.
mkdir -p build/web/assets
cp -r web/assets/. build/web/assets/ 2>/dev/null || true

# Catch path/layout regressions before Vercel publishes an incomplete site.
test -s build/web/index.html
test -s build/web/app/index.html
grep -q 'href="app/"' build/web/index.html
