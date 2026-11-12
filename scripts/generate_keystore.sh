#!/usr/bin/env bash
# Creates the release keystore used to sign BRO release APKs, and prints the
# four repository secrets the Build APK workflow needs.
#
#   ./scripts/generate_keystore.sh                 # create android/app/release.keystore
#   ./scripts/generate_keystore.sh --from-existing # reuse an existing keystore
#
# IMPORTANT: Android only installs an update when it is signed with the same
# certificate as the app already on the device. If you already published a
# release, reuse the keystore that signed it. Generating a new one forces every
# existing user to uninstall and reinstall (losing local data), so the script
# refuses to overwrite an existing keystore unless --force is passed.
set -euo pipefail

cd "$(dirname "$0")/.."

KEYSTORE="android/app/release.keystore"
ALIAS="bro-release"

die() { echo "error: $*" >&2; exit 1; }

command -v keytool >/dev/null 2>&1 || die "keytool not found. Install a JDK (17+) and retry."

if [[ "${1:-}" == "--from-existing" ]]; then
  [[ -f "$KEYSTORE" ]] || die "no keystore at $KEYSTORE to reuse"
elif [[ -f "$KEYSTORE" && "${1:-}" != "--force" ]]; then
  die "$KEYSTORE already exists.
Reuse it (Android needs the same certificate for updates), or pass --force to
replace it. Replacing it breaks in-place updates for every installed copy."
else
  read -r -p "Keystore password: " KEYSTORE_PASSWORD
  read -r -p "Key password [same as keystore]: " KEY_PASSWORD
  KEY_PASSWORD="${KEY_PASSWORD:-$KEYSTORE_PASSWORD}"
  [[ ${#KEYSTORE_PASSWORD} -ge 6 ]] || die "password must be at least 6 characters"

  keytool -genkeypair -v \
    -keystore "$KEYSTORE" \
    -alias "$ALIAS" \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass "$KEYSTORE_PASSWORD" \
    -keypass "$KEY_PASSWORD" \
    -dname "CN=BRO, OU=Mobile, O=Omix Systems, L=Nairobi, C=KE" \
    >/dev/null

  # key.properties is gitignored; it lets local release builds sign too.
  {
    echo "storeFile=release.keystore"
    echo "storePassword=$KEYSTORE_PASSWORD"
    echo "keyAlias=$ALIAS"
    echo "keyPassword=$KEY_PASSWORD"
  } > android/app/key.properties
  chmod 600 "$KEYSTORE" android/app/key.properties

  echo
  echo "Created $KEYSTORE (alias: $ALIAS)."
fi

echo
echo "Add these as repository secrets (Settings > Secrets and variables > Actions):"
echo
echo "  KEYSTORE_BASE64    = $(base64 -w0 < "$KEYSTORE" 2>/dev/null || base64 < "$KEYSTORE" | tr -d '\n')"
echo "  KEYSTORE_PASSWORD  = (the store password you entered)"
echo "  KEY_ALIAS          = $ALIAS"
echo "  KEY_PASSWORD       = (the key password you entered)"
echo
echo "Back up $KEYSTORE somewhere safe. Losing it means you can never update"
echo "installed copies in place again."
