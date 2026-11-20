# Supabase CI/CD

[Supabase CI/CD](../.github/workflows/supabase.yml) runs the calls/push SQL and RLS integration harness, browser worker tests, and Edge Function type checks and tests on every push and pull request. CI does not use hosted credentials. The SQL harness runs against fixtures, not the full hosted migration history.

After CI passes, every push to `main` in `marvel-254/chat-app` deploys to **`nyx` (`dbfgyehzgrmsajpwydps`)** when deployment is enabled. Feature branch pushes and pull requests never deploy to production. The workflow also supports **Run workflow** on `main`. Production runs are serialized; a queued run skips if its commit is no longer the tip of `main`.

## One-time GitHub setup

1. Under **Settings → Environments**, create `supabase-production` and restrict deployment branches to `main`. Use a required reviewer for the first cutover if your GitHub plan supports it. Protect `main` with PR review and the `calls-push` check from the new workflow; verify any existing required-check rule still points to the correct check.
2. Add these **environment secrets** through GitHub's settings. Never put their values in Git or chat:
   - `SUPABASE_ACCESS_TOKEN`: a Supabase management access token for an account authorized to deploy to `nyx`; use the narrowest available permissions. This is not an anon, publishable, or service-role API key.
   - `SUPABASE_DB_PASSWORD`: the database password for `nyx`.
3. Leave production CD disabled until the [calls and push cutover](security-calls-push.md#migration-verification-and-rollback) is ready. Two pending migrations replace paths older clients still use; `20261120150000_calls_push_cutover_compat` restores the legacy realtime/push paths alongside them. Validate against isolated staging, verify the backup and client rollout plan, and provision the required TURN, Firebase and Vault settings directly in Supabase. The workflow does not provision these.
4. When ready, under **Settings → Secrets and variables → Actions → Variables**, set the **repository variable** `SUPABASE_PRODUCTION_DEPLOY_ENABLED` to `true`. Then trigger the workflow from `main` or let the next push do it. Remove the variable or set it to `false` to pause future runs; it does not stop one already in progress.

## What a deployment does

The pinned Supabase CLI prints a dry-run plan, applies pending versioned migrations (including the two older pending versions on `nyx`), then deploys repository Edge Functions using `supabase/config.toml`. It does not seed data, sync Vault or other hosted settings, or delete remote-only functions. The dry run is logged, not an approval checkpoint; use the environment's deployment protection or a separate operator-run dry run if you need to review the plan before enabling deployment.

The final smoke test checks that both routes reject an unauthenticated request. It does not validate authenticated TURN sessions, relay traffic, Firebase delivery, or client compatibility. If a run fails, inspect which steps succeeded before retrying the latest `main`; migrations and function deployments are not one transaction. Recover with a reviewed forward migration or a known-compatible function deployment rather than resetting production or editing applied migrations.
