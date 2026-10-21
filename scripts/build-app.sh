#!/bin/zsh
# Builds build/Speek2Me.app from the Swift package and signs it.
#
# Signing: the Keychain items (API keys) are tied to the signing identity, so a stable
# "Speek2Me Signing" certificate keeps them readable across rebuilds. Locally it lives in its own
# keychain, unlocked here with its own password so codesign never shows a dialog; a release
# workflow can load it from secrets and set SIGN_IDENTITY. Without either, the app is ad-hoc
# signed and macOS may ask for Keychain access again after a rebuild.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
APP="build/Speek2Me.app"
SIGNING="$HOME/Library/Application Support/Speek2Me Signing"
SIGN_ARGS=()
if [[ -z "${SIGN_IDENTITY:-}" && -f "$SIGNING/signing.keychain-db" ]]; then
  security unlock-keychain -p "$(<"$SIGNING/keychain-password")" "$SIGNING/signing.keychain-db"
  # By hash: the self-signed certificate is not trusted, and codesign only takes an untrusted
  # identity by hash. The keychain must be on the search list (security list-keychains).
  SIGN_IDENTITY="$(security find-certificate -c "Speek2Me Signing" -Z "$SIGNING/signing.keychain-db" | awk '/SHA-1/ {print $3}')"
  SIGN_ARGS=(--keychain "$SIGNING/signing.keychain-db")
fi

swift build -c "$CONFIG" --product Speek2Me
swift build -c "$CONFIG" --product speek2me-hook
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Speek2Me" "$APP/Contents/MacOS/Speek2Me"
cp "$BIN_DIR/speek2me-hook" "$APP/Contents/MacOS/speek2me-hook"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Release builds stamp their version here.
if [[ -n "${VERSION:-}" ]]; then
  plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
fi
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# The nested hook CLI is signed first, then the bundle.
codesign --force --options runtime --sign "${SIGN_IDENTITY:--}" "${SIGN_ARGS[@]}" "$APP/Contents/MacOS/speek2me-hook"
codesign --force --options runtime \
  --entitlements Resources/Speek2Me.entitlements \
  --sign "${SIGN_IDENTITY:--}" "${SIGN_ARGS[@]}" \
  "$APP"

codesign --verify --strict "$APP"
echo "Built $APP"
