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

# ── Try to build the Flutter web app (optional) ──────────────────────────
FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.7}"
CACHE_ROOT="${VERCEL_CACHE_DIR:-$ROOT/.vercel/cache}"
FLUTTER_SDK="$CACHE_ROOT/flutter-$FLUTTER_VERSION"

if [[ -x "$FLUTTER_SDK/bin/flutter" ]]; then
  export PATH="$FLUTTER_SDK/bin:$PATH"
  export PUB_CACHE="${PUB_CACHE:-$CACHE_ROOT/pub-cache}"
  export BASE_HREF="${BASE_HREF:-/app/}"

  if flutter config --no-analytics 2>/dev/null && flutter --version 2>/dev/null; then
    if ./scripts/build.sh web 2>&1; then
      echo "✅ Flutter web build succeeded"
    else
      echo "⚠️  Flutter web build failed — landing page will still deploy"
    fi
  else
    echo "⚠️  Flutter SDK found but not working — skipping web build"
  fi
else
  echo "⚠️  Flutter SDK not cached — cloning (this may take a while)..."
  if mkdir -p "$CACHE_ROOT" && \
     git clone --depth 1 --branch "$FLUTTER_VERSION" \
       https://github.com/flutter/flutter.git "$FLUTTER_SDK" 2>/dev/null && \
     [[ -x "$FLUTTER_SDK/bin/flutter" ]]; then
    export PATH="$FLUTTER_SDK/bin:$PATH"
    export PUB_CACHE="${PUB_CACHE:-$CACHE_ROOT/pub-cache}"
    export BASE_HREF="${BASE_HREF:-/app/}"

    if flutter config --no-analytics 2>/dev/null && flutter --version 2>/dev/null; then
      if ./scripts/build.sh web 2>&1; then
        echo "✅ Flutter web build succeeded"
      else
        echo "⚠️  Flutter web build failed — landing page will still deploy"
      fi
    else
      echo "⚠️  Flutter SDK cloned but not working — skipping web build"
    fi
  else
    echo "⚠️  Flutter SDK clone failed — deploying landing page only"
  fi
fi

# ── Verify ───────────────────────────────────────────────────────────────
test -s build/web/index.html
echo "✅ Build complete — landing page is ready"
