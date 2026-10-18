# Linux driver (experimental)

The original MIT engine uses libusb for the DS-720D's USB mass-storage bridge.
The SANE backend exposes **Color, 300 dpi, ADF Duplex**. A physical acquisition
contains both sensors; the next SANE image returns the cached rear page without
feeding another sheet. Each side is an independent RGB image (`last_frame=true`).
Background cleanup is on by default and can be disabled for photographs/shading.

The software tests simulate firmware and a SANE frontend. **A physical Linux
scan has not yet been verified.** No Brother library is used. libusb and libpng
are external system dependencies, with their own licenses.

## Build

On Ubuntu 22.04+ / Debian with the corresponding development packages:

```sh
sudo apt install build-essential pkg-config libusb-1.0-0-dev libpng-dev libsane-dev sane-utils
make -C linux
make -C linux test
./linux/build/ds720d-linux probe
```

For system installation, use the matching `.deb` from a verified release,
or stage an installation with `make -C linux install DESTDIR=/absolute/staging`.
`packaging/linux/build-deb.sh` builds a package for the current architecture.
The package installs a SANE module, a dll.d entry, and one device-specific udev
rule. Reconnect the scanner after installation. The active local desktop session
gets access through `uaccess`; headless users may join the `scanner` group and
log in again. Do not run scan applications as root.

Close other scanner applications, insert one ordinary test sheet, then:

```sh
ds720d-linux scan ./document
# document-front.png and document-back.png, refusing existing files
scanimage -L
scanimage -d ds720d:usb:04f9:60e2 --batch=page-%02d.pnm --batch-count=2
```

For the unprocessed acquisition, use `ds720d-linux scan ./document --raw` or the
SANE option `--document-cleanup=no`. The fixed mode/resolution/source options are
read-only. The backend supports blocking reads; asynchronous select is not exposed.
Only one DS-720D may be connected. No other USB storage driver is disabled.

The backend does not implement calibration or model-specific paper/jam status
mapping yet. It refuses capture if the scanner reports that calibration is
required. Firmware locks owned by other software are never forcibly cleared.
If necessary, reconnect USB with the scanner empty.

## Uninstall

`sudo apt remove ds720d-mit` removes the packaged driver and udev rule. Other
SANE backends are left in place. Reconnect the scanner after changing drivers.
