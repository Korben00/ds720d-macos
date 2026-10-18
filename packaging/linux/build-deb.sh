#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
DS_ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
DS_VERSION=$(cat "$DS_ROOT/VERSION")
# Debian's tilde orders previews before the corresponding stable version.
DS_DEB_VERSION=$(printf '%s' "$DS_VERSION" | sed 's/-/~/')
DS_ARCH=$(dpkg --print-architecture)
DS_TEMP=$(mktemp -d)
trap 'rm -rf "$DS_TEMP"' EXIT
make -C "$DS_ROOT/linux" install DESTDIR="$DS_TEMP/package"
mkdir -p "$DS_TEMP/package/DEBIAN" "$DS_ROOT/dist"
cat > "$DS_TEMP/package/DEBIAN/control" <<CONTROL
Package: ds720d-mit
Version: $DS_DEB_VERSION
Architecture: $DS_ARCH
Maintainer: DS720D contributors <noreply@github.com>
Section: graphics
Priority: optional
Depends: libc6 (>= 2.35), libusb-1.0-0 (>= 1.0.23), libpng16-16 | libpng16-16t64, libsane1, udev, adduser
Description: Independent MIT Brother DS-720D USB scanner driver
 Native 300 dpi RGB duplex acquisition, SANE backend and command-line tool.
 Experimental. Linux hardware scanning still needs validation.
CONTROL
cp "$DS_ROOT/packaging/linux/postinst" "$DS_TEMP/package/DEBIAN/postinst"
chmod 755 "$DS_TEMP/package/DEBIAN/postinst"
dpkg-deb --root-owner-group --build "$DS_TEMP/package" "$DS_ROOT/dist/ds720d-mit_${DS_VERSION}_${DS_ARCH}.deb"
cd "$DS_ROOT/dist"
sha256sum "ds720d-mit_${DS_VERSION}_${DS_ARCH}.deb" > "ds720d-mit_${DS_VERSION}_${DS_ARCH}.deb.sha256"
