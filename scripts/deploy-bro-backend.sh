#!/usr/bin/env bash
# No automatic link, restoration, secret handling, migration repair or reset.
set -euo pipefail
cd "$(dirname "$0")/.."
expected=zchsmnelvcuexchpwfgr
[[ $(cat supabase/.temp/project-ref 2>/dev/null) == "$expected" ]] || { echo 'Refusing: CLI is not linked to BRO.' >&2; exit 1; }
supabase migration list --linked
supabase db push --linked --dry-run
if [[ ${1:-} != --apply ]]; then echo 'Dry run only.'; exit 0; fi
supabase db push --linked
supabase functions deploy turn-credentials --project-ref "$expected"
supabase functions deploy push-new-message --project-ref "$expected" --no-verify-jwt
