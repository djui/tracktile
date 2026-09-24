#!/usr/bin/env bash
# Builds TrackTile.app and packages it as build/TrackTile-<version>.zip for a
# GitHub release, with a matching .sha256 file.
#
# Usage: scripts/release.sh <version>      e.g. scripts/release.sh 0.1.0
#
# Environment (in addition to those of bundle.sh):
#   NOTARY_PROFILE  A `xcrun notarytool store-credentials` profile name. When
#                   set (and the app is signed with Developer ID), the app is
#                   notarized and the ticket stapled before zipping.
set -euo pipefail

cd "$(dirname "$0")/.."

version="${1:-${VERSION:-}}"
if [[ -z "$version" ]]; then
  echo "usage: $0 <version>" >&2
  exit 64
fi
version="${version#v}"

VERSION="$version" ./scripts/bundle.sh

APP="build/TrackTile.app"
ZIP="build/TrackTile-$version.zip"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "Notarizing with profile $NOTARY_PROFILE"
  ditto -c -k --keepParent "$APP" build/notarize.zip
  xcrun notarytool submit build/notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm build/notarize.zip
fi

rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
(cd build && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")

echo "Release artifact: $ZIP"
cat "$ZIP.sha256"
