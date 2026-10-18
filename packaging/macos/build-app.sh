#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
DS_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DS_VERSION=$(cat "$DS_ROOT/VERSION")
[[ "$DS_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?$ ]] || exit 64
DS_SHORT=${DS_VERSION%%-*}
DS_BUILD=1
if [[ "$DS_VERSION" =~ -preview\.([0-9]+)$ ]]; then DS_BUILD=${BASH_REMATCH[1]}; fi
DS_TEMP=$(mktemp -d /private/tmp/ds720d-app.XXXXXX)
trap 'rm -rf "$DS_TEMP"' EXIT
DS_APP="$DS_TEMP/DS-720D Scanner.app"
DS_IDENTITY=${DS_SIGN_IDENTITY:--}
mkdir -p "$DS_APP/Contents/MacOS" "$DS_APP/Contents/Resources"
cp "$DS_ROOT/build/ds720d-universal" "$DS_APP/Contents/MacOS/ds720d"
cp "$DS_ROOT/build/DS720DScanner-universal" "$DS_APP/Contents/MacOS/DS720DScanner"
cp "$DS_ROOT/build/DS720DDoctor-universal" "$DS_APP/Contents/MacOS/DS720DDoctor"
cp "$DS_ROOT/LICENSE" "$DS_APP/Contents/Resources/LICENSE.txt"
cat > "$DS_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>info.korben.ds720d</string>
<key>CFBundleName</key><string>DS-720D Scanner</string>
<key>CFBundleDisplayName</key><string>DS-720D Scanner</string>
<key>CFBundleExecutable</key><string>DS720DScanner</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$DS_SHORT</string>
<key>CFBundleVersion</key><string>$DS_BUILD</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>2026 Korben · MIT License</string>
</dict></plist>
PLIST
xcrun clang -fobjc-arc -Wall -Wextra -Werror "$DS_ROOT/macos/make-icon.m" -framework AppKit -o "$DS_ROOT/build/make-icon"
"$DS_ROOT/build/make-icon" "$DS_ROOT/build/AppIcon.iconset"
iconutil -c icns "$DS_ROOT/build/AppIcon.iconset" -o "$DS_APP/Contents/Resources/AppIcon.icns"
if [[ "$DS_IDENTITY" == "-" ]]; then
    codesign --force --sign - --identifier info.korben.ds720d.cli "$DS_APP/Contents/MacOS/DS720DDoctor"
    codesign --force --sign - --identifier info.korben.ds720d.cli "$DS_APP/Contents/MacOS/ds720d"
    codesign --force --sign - "$DS_APP/Contents/MacOS/DS720DScanner"
    codesign --force --sign - "$DS_APP"
else
    codesign --force --options runtime --timestamp --sign "$DS_IDENTITY" --identifier info.korben.ds720d.cli "$DS_APP/Contents/MacOS/DS720DDoctor"
    codesign --force --options runtime --timestamp --sign "$DS_IDENTITY" --identifier info.korben.ds720d.cli "$DS_APP/Contents/MacOS/ds720d"
    codesign --force --options runtime --timestamp --sign "$DS_IDENTITY" "$DS_APP/Contents/MacOS/DS720DScanner"
    codesign --force --options runtime --timestamp --sign "$DS_IDENTITY" "$DS_APP"
fi
codesign --verify --deep --strict "$DS_APP"
plutil -lint "$DS_APP/Contents/Info.plist"
DS_ICA="$DS_TEMP/DS720DICA.app"
mkdir -p "$DS_ICA/Contents/MacOS" "$DS_ICA/Contents/Resources"
cp "$DS_ROOT/build/DS720DICA-universal" "$DS_ICA/Contents/MacOS/DS720DICA"
cp "$DS_ROOT/packaging/macos/DeviceMatchingInfo.plist" "$DS_ROOT/packaging/macos/DeviceInfo.plist" "$DS_ROOT/LICENSE" "$DS_ICA/Contents/Resources/"
cat > "$DS_ICA/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>info.korben.ds720d.ica</string>
<key>CFBundleName</key><string>DS720DICA</string>
<key>CFBundleExecutable</key><string>DS720DICA</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$DS_SHORT</string>
<key>CFBundleVersion</key><string>$DS_BUILD</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
cp "$DS_ROOT/build/DS720DUSBService-universal" "$DS_TEMP/info.korben.ds720d.usb"
DS_SIGN_FLAGS=(--force --sign "$DS_IDENTITY")
if [[ "$DS_IDENTITY" != "-" ]]; then DS_SIGN_FLAGS+=(--options runtime --timestamp); fi
codesign "${DS_SIGN_FLAGS[@]}" "$DS_ICA"
codesign "${DS_SIGN_FLAGS[@]}" --identifier info.korben.ds720d.usb "$DS_TEMP/info.korben.ds720d.usb"
codesign --verify --deep --strict "$DS_ICA"
codesign --verify --strict "$DS_TEMP/info.korben.ds720d.usb"
rm -rf "$DS_ROOT/build/DS-720D Scanner.app" "$DS_ROOT/build/DS720DICA.app"
ditto "$DS_APP" "$DS_ROOT/build/DS-720D Scanner.app"
ditto "$DS_ICA" "$DS_ROOT/build/DS720DICA.app"
cp "$DS_TEMP/info.korben.ds720d.usb" "$DS_ROOT/build/info.korben.ds720d.usb"
printf '%s\n' "$DS_ROOT/build/DS-720D Scanner.app"
