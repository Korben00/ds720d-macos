#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
DS_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DS_VERSION=$(cat "$DS_ROOT/VERSION")
[[ "$DS_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?$ ]] || exit 64
DS_TEMP=$(mktemp -d /private/tmp/ds720d-dmg.XXXXXX)
trap 'rm -rf "$DS_TEMP"' EXIT
DS_STAGE="$DS_TEMP/stage"
DS_DMG="$DS_ROOT/dist/DS720DScanner-$DS_VERSION-macos-universal.dmg"
mkdir -p "$DS_STAGE" "$DS_ROOT/dist"
# A fresh staging directory contains only these explicitly selected deliverables.
cp "$DS_ROOT/dist/DS720DScanner-$DS_VERSION-macos-universal.pkg" "$DS_STAGE/Installer DS-720D.pkg"
cp "$DS_ROOT/packaging/macos/README.txt" "$DS_STAGE/Lisez-moi.txt"
cp "$DS_ROOT/LICENSE" "$DS_STAGE/LICENSE.txt"
hdiutil create -ov -format UDZO -volname 'DS-720D Scanner' -srcfolder "$DS_STAGE" "$DS_DMG"
if [[ ${DS_SIGN_IDENTITY:--} != "-" ]]; then
    codesign --force --timestamp --sign "$DS_SIGN_IDENTITY" "$DS_DMG"
fi
if [[ -n ${DS_NOTARY_PROFILE:-} ]]; then
    [[ ${DS_SIGN_IDENTITY:--} != "-" ]] || { printf 'Notarization requires a Developer ID signature.\n' >&2; exit 1; }
    xcrun notarytool submit "$DS_DMG" --keychain-profile "$DS_NOTARY_PROFILE" --wait
    xcrun stapler staple "$DS_DMG"
    xcrun stapler validate "$DS_DMG"
fi
shasum -a 256 "$DS_DMG" > "$DS_DMG.sha256"
printf '%s\n' "$DS_DMG"
