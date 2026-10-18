#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
DS_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DS_VERSION=$(cat "$DS_ROOT/VERSION")
DS_SHORT=${DS_VERSION%%-*}
DS_TEMP=$(mktemp -d /private/tmp/ds720d-pkg.XXXXXX)
trap 'rm -rf "$DS_TEMP"' EXIT
DS_PAYLOAD="$DS_TEMP/payload"
mkdir -p "$DS_PAYLOAD/Applications" "$DS_PAYLOAD/Library/Image Capture/Devices" "$DS_PAYLOAD/Library/PrivilegedHelperTools" "$DS_PAYLOAD/Library/LaunchDaemons" "$DS_ROOT/dist"
ditto "$DS_ROOT/build/DS-720D Scanner.app" "$DS_PAYLOAD/Applications/DS-720D Scanner.app"
ditto "$DS_ROOT/build/DS720DICA.app" "$DS_PAYLOAD/Library/Image Capture/Devices/DS720DICA.app"
cp "$DS_ROOT/build/info.korben.ds720d.usb" "$DS_PAYLOAD/Library/PrivilegedHelperTools/"
cp "$DS_ROOT/packaging/macos/info.korben.ds720d.usb.plist" "$DS_PAYLOAD/Library/LaunchDaemons/"
chmod 755 "$DS_PAYLOAD/Library/PrivilegedHelperTools/info.korben.ds720d.usb"
chmod 644 "$DS_PAYLOAD/Library/LaunchDaemons/info.korben.ds720d.usb.plist"
pkgbuild --analyze --root "$DS_PAYLOAD" "$DS_TEMP/components.plist"
# Fixed system paths; never relocate an older copy found elsewhere.
/usr/libexec/PlistBuddy -c 'Add :0:BundleIsRelocatable bool false' "$DS_TEMP/components.plist"
/usr/libexec/PlistBuddy -c 'Add :1:BundleIsRelocatable bool false' "$DS_TEMP/components.plist"
pkgbuild --root "$DS_PAYLOAD" --ownership recommended --component-plist "$DS_TEMP/components.plist" \
    --identifier info.korben.ds720d.installer --version "$DS_SHORT" --scripts "$DS_ROOT/packaging/macos/scripts" "$DS_TEMP/component.pkg"
cat > "$DS_TEMP/distribution.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<installer-gui-script minSpecVersion="2">
<title>DS-720D Scanner $DS_VERSION</title>
<options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
<domains enable_localSystem="true" enable_currentUserHome="false" enable_anywhere="false"/>
<allowed-os-versions><os-version min="14.0"/></allowed-os-versions>
<choices-outline><line choice="driver"/></choices-outline>
<choice id="driver" visible="false"><pkg-ref id="info.korben.ds720d.installer"/></choice>
<pkg-ref id="info.korben.ds720d.installer" version="$DS_SHORT" auth="Root">component.pkg</pkg-ref>
</installer-gui-script>
XML
if [[ -n ${DS_INSTALLER_IDENTITY:-} ]]; then
    productbuild --distribution "$DS_TEMP/distribution.xml" --package-path "$DS_TEMP" --sign "$DS_INSTALLER_IDENTITY" --timestamp "$DS_TEMP/DS720DScanner.pkg"
else
    productbuild --distribution "$DS_TEMP/distribution.xml" --package-path "$DS_TEMP" "$DS_TEMP/DS720DScanner.pkg"
fi
cp "$DS_TEMP/DS720DScanner.pkg" "$DS_ROOT/dist/DS720DScanner-$DS_VERSION-macos-universal.pkg"
