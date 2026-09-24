#!/usr/bin/env bash
# Builds a universal (arm64 + x86_64) TrackTile.app into ./build.
#
# Environment:
#   VERSION            Marketing version, e.g. 1.2.0 (default: Info.plist value)
#   BUILD_NUMBER       Build number (default: git commit count, or Info.plist value)
#   CODESIGN_IDENTITY  Certificate to sign with. Without it, the first
#                      "Developer ID Application" or "Apple Development" identity
#                      in the keychain is used, falling back to ad-hoc ("-").
#                      A stable identity keeps the Accessibility permission
#                      across rebuilds.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="TrackTile"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
ARCH_FLAGS=(--arch arm64 --arch x86_64)

swift build -c release "${ARCH_FLAGS[@]}"
BIN_PATH="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp ../LICENSE "$APP/Contents/Resources/LICENSE"

plist="$APP/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION#v}" "$plist"
fi
build_number="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || true)}"
if [[ -n "$build_number" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$plist"
fi

identity="${CODESIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  identity="$(grep -m1 '"Developer ID Application' <<<"$identities" | sed -E 's/.*"(.*)"/\1/' || true)"
  if [[ -z "$identity" ]]; then
    identity="$(grep -m1 '"Apple Development' <<<"$identities" | sed -E 's/.*"(.*)"/\1/' || true)"
  fi
fi
identity="${identity:--}"

echo "Signing with identity: $identity"
if [[ "$identity" == "-" ]]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$identity" "$APP"
fi
codesign --verify --strict "$APP"

echo "Built $APP ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist"))"
