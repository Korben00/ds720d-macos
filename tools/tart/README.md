# Tart USB/IP test relay

These MIT development tools let a Linux SANE driver in Tart talk to the real
DS-720D. They are optional test infrastructure, not part of the Linux package
or the installed macOS driver. The exporter uses the MIT `jiegec/usbip` library,
pinned to commit `5561aa4abf372f5d3eb05c65b1474a9489b735f8`, and system libusb.
Other build dependencies retain their own licenses.

Only one physical `04f9:60e2` is exported. Both TCP listeners bind to localhost;
bytes cross the host/guest boundary through Tart's existing guest-agent channel.
There is no LAN listener, root network daemon or system network tuning.
Stop the relay when the test ends; USB/IP itself is not an authenticated service.

## Requirements

- A dedicated running Linux Tart VM with Python 3, the Tart guest agent,
  `usbip`, `vhci-hcd`, SANE and the ARM64 DS-720D package.
- A Tart 2.41.1+ **client** for `exec -i` binary streaming. The tested VM runner
  was Tart 2.28.2; an independent 2.41.1 app bundle supplied the client.
  When using a downloaded Tart app, keep its executable inside that bundle.
- On the Mac: Python 3, Rust 1.89+, libusb, pkg-config, and the installed signed
  DS-720D preparation service. Run the relay as the current user.

Build from the repository root:

```sh
cargo build --release --locked --manifest-path tools/tart/usbip-host/Cargo.toml
```

## Attach and scan

Close other scanner applications. Prepare only the USB interface, without
moving the paper, using the installed diagnostic:

```sh
"/Applications/DS-720D Scanner.app/Contents/MacOS/DS720DDoctor" usb-probe
```

Start the exporter in one terminal and keep its printed USB bus ID:

```sh
./tools/tart/usbip-host/target/release/ds720d-tart-usbip
```

In another terminal, start the private channel. Replace `VM_NAME` with the
dedicated VM name. `--tart` can select a newer client without upgrading the
VM runner or changing other running VMs:

```sh
python3 tools/tart/usbip-channel.py VM_NAME --tart /absolute/path/to/tart
```

Wait for `Private USB/IP guest endpoint ready`. In the Linux guest, attach
using the ID printed by the exporter (replace `BUS_ID`):

```sh
sudo modprobe vhci-hcd
sudo usbip attach -r 127.0.0.1 -b BUS_ID
sudo udevadm settle
ds720d-linux probe
```

The scanning user needs the packaged udev permissions, for example membership
in `scanner` with a fresh login. Verify identity first, insert one test sheet,
then run the SANE command in [the Linux guide](../../docs/linux.md) as that user.
Do not run a scanning application as root.

Detach with `sudo usbip detach -p PORT` in the guest, using the reported port
(the dedicated test VM used port 0). Stop both host relay processes, then stop
the dedicated VM if no longer needed. Reopen the macOS scanner application.

## Feed-pause regression check

The original channel omitted `TCP_NODELAY` on its guest-side TCP socket.
Nagle buffering combined with delayed ACKs held up the final fragments of
64 KiB responses for about 40 ms. That limited throughput enough to interrupt
the physical feed. `usbip-channel.py` now disables Nagle on both endpoints;
the exporter does the same on accepted sockets, as the Linux USB/IP tools do.

With the real exporter stopped and the dedicated VM still running, run:

```sh
python3 tools/tart/transport-benchmark.py VM_NAME \
  --tart /absolute/path/to/tart --compare
```

The benchmark exchanges 128 synthetic CBW/data/CSW-shaped cycles over the
actual channel: 8 MiB of data in 64 KiB blocks. It never opens a USB device.
`--compare` deliberately enables Nagle for a baseline; the normal relay CLI
always disables it. The test verifies byte counts/content and rejects a
corrected transport below 5 MiB/s. A busy host may need investigation before
interpreting that performance threshold.

The recorded comparison is [benchmark-2026-10-18.json](benchmark-2026-10-18.json).
Hardware confirmation produced two readable 300 dpi PNGs in 15.63 seconds,
with the user confirming complete ejection and no feed pauses. Synthetic
measurements alone do not establish scanner hardware behavior.
