# Linux driver (experimental)

The original MIT engine uses libusb for the DS-720D's USB mass-storage bridge.
The SANE backend exposes **Color, 300 dpi, ADF Duplex**. A physical acquisition
contains both sensors; the next SANE image returns the cached rear page without
feeding another sheet. Each side is an independent RGB image (`last_frame=true`).
Background cleanup is on by default and can be disabled for photographs/shading.

The software tests simulate firmware and a SANE frontend. **One real duplex
scan has passed through SANE in an Ubuntu ARM64 Tart VM with USB/IP.** Direct
USB on a physical Linux host remains unverified. No Brother library is used.
libusb and libpng are external system dependencies, with their own licenses.

CI also installs each amd64/arm64 package on Ubuntu 22.04 and checks that the
real SANE dynamic loader initializes the backend. There is no USB scanner in CI.

## Hardware validation: 18 October 2026

The published `0.1.0-preview.3` ARM64 Debian package was installed in an Ubuntu
24.04.5 Tart VM (Linux `7.0.0-38-generic`, SANE 1.2.1, libusb 1.0.27) on an
Apple Silicon Mac running macOS 27.0.1. Package SHA-256:
`7757fa192dedd0a114427b736af790f33bd60b790300b29d1e51b60dedafe2d6`.

The VM used the real physical DS-720D through the Linux `vhci-hcd` USB/IP
controller. Tart 2.28.2 has no physical USB passthrough; a temporary host-side
adapter using the MIT `usbip` 0.9.0 library forwarded control/bulk transfers.
Only `04f9:60e2` was exported, with loopback listeners and the Tart guest-agent
channel carrying the bytes. The macOS scan engine did not perform acquisition.
The guest-agent commands used a temporary Tart 2.41.1 client. This test adapter
is not part of the Linux package.

The packaged udev rule granted the `scanner` group access. The CLI identified
the bridge and scanner successfully, and `scanimage -L` loaded the packaged
SANE backend. Acquisition ran as the ordinary guest user, with membership in
`scanner`, using:

```sh
scanimage -d ds720d:usb:04f9:60e2 --format=png \
  --batch=page-%02d.png --batch-count=2 --verbose
```

One physical sheet pass produced two RGB PNGs: 2470×3481 and 2466×3483 pixels,
both with 300 dpi metadata. SANE returned EOF for each image and exited with
status 0; the second image came from the cached rear page. Both faces were
visually checked for legible text, corrected orientation, paper cleanup and
complete page content. Scanner identification also passed after the scan.
The images and detailed logs contain private document data and stay local.

Two feed pauses were observed during this roughly 52-second initial command.
There was no scan failure or visible missing image band. The follow-up below
identifies and corrects the relay bottleneck.

### Feed-pause correction, same day

A hardware-free benchmark reproduced a roughly 40 ms delay at the end of
each 64 KiB response. Disabling Nagle on the host exporter alone did not fix
it; setting `TCP_NODELAY` on the channel's **guest-side socket** did. On that
socket, Nagle buffering and delayed TCP acknowledgments were delaying the
last fragments before Linux could request the next scanner block.

The retained comparison, with identical synthetic requests and payloads,
measured 1.37 MiB/s before and 34.62 MiB/s after correction. Median 64 KiB
response latency fell from 43.20 ms to 0.90 ms. The original pause-producing
path could not drain scanner data quickly enough. The relay now disables
Nagle on both channel endpoints and the exporter's accepted sockets. This
matches the explicit `TCP_NODELAY` settings in the
[Linux USB/IP tools](https://github.com/torvalds/linux/blob/master/tools/usb/usbip/src/usbip_network.c).
No scanner acquisition parameters or Linux package binaries changed.

A second physical duplex sheet scan with the corrected relay completed in
**15.63 seconds**, exiting with status 0 and producing two complete RGB PNGs
(2463×3481 and 2464×3477, both 300 dpi). The images were visually checked;
the user confirmed complete ejection and continuous feed without either pause.
The two commands used different test sheets; the controlled transport benchmark
isolates the effect of the TCP correction.

The [relay source and reproducible benchmark](../tools/tart/README.md) are
retained in the repository. Direct Linux USB, AMD64 hardware, repeatability
across more units and error recovery still need validation.

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
