#!/usr/bin/env bash
# Local build wrapper for NYX.
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
# .env.local format (one KEY=VALUE per line, gitignored):
#   SUPABASE_URL=https://your-project.supabase.co
#   SUPABASE_ANON_KEY=***
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
    DEFINES+=(--dart-define="${key}=${value}")
  done < .env.local
fi

TARGET="${1:-apk}"
case "$TARGET" in
  apk)
    flutter build apk --release --split-per-abi "${DEFINES[@]}"
    ;;
  web)
    flutter build web --release "${DEFINES[@]}"
    ;;
  --help|-h)
    echo "Usage: ./scripts/build.sh [apk|web]"
    echo "  apk (default): release APK, split per ABI, secrets from .env"
    echo "  web:           web release build, secrets from .env"
    ;;
  *)
    echo "Unknown target: $TARGET (use: apk, web, --help)" >&2
    exit 1
    ;;
esac
