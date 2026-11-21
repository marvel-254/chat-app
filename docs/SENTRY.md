# Sentry source maps

Flutter web builds include source maps (`--source-maps` in `scripts/build.sh`). The Pages workflow uploads them to Sentry after each web build.

Release naming comes from `pubspec.yaml`:

- release: `bro@<version>` (for example `bro@1.5.2+24`)
- dist: the build number after `+` (for example `24`)

## Required repository secret

Add `SENTRY_AUTH_TOKEN` as a GitHub Actions secret:

```bash
gh secret set SENTRY_AUTH_TOKEN
```

The token must allow `project:releases` and `org:read` for `omix-systems`. Never commit it or print it in logs. If the secret is missing, the workflow logs a notice and skips the upload.

## Manual upload

Useful when investigating a release that predates automatic upload:

```bash
sentry sourcemaps upload \
  --org omix-systems \
  --project bro \
  --release 'bro@1.5.2+24' \
  --dist 24 \
  build/web/app
```

Read release and dist from the Sentry event JSON before uploading. Older minified events may remain minified; new events after upload are symbolicated.
