# DS-720D for macOS

An independent, MIT-licensed native driver project for the **Brother DSmobile
DS-720D**, starting with a command-line interface. The current development host
is Apple Silicon running macOS 27.0.1.

**Experimental prototype:** a real duplex sheet was acquired on the development
Mac on 18 October 2026. Both faces contain legible text in 300 dpi RGB PNGs;
the rear sensor's mirrored image is corrected during decoding. Native USB
access, scanner identification and end-of-page detection worked on this device.
Document rendering now removes the dark scanner borders and balances the paper
background independently on each face. The result has been checked visually on
the captured sheet. Raw RGB remains available. This is not a production scanning
release: recovery, distribution and wider hardware testing remain unfinished.

## Build and test

Install Apple's Command Line Tools, then run:

```sh
make
make test
make analyze
./build/ds720d list
```

There are no third-party libraries to install. The program uses Apple's
Foundation, IOKit, IOUSBHost, Security, ImageIO and CoreGraphics frameworks.
The deployment target is macOS 14;
Physical scanning has only been tested on the Apple Silicon development Mac.
A deployment target is not a hardware compatibility claim.

The GitHub workflow builds, runs sanitizer tests and analyzes the source on
Apple Silicon and Intel runners; both jobs have passed. It cannot test a
physical scanner.

## Hardware diagnostic

Connect exactly one DS-720D, close applications that might use it, then run:

```sh
sudo ./build/ds720d probe
```

Alternatively, `./build/ds720d authorize-probe` requests a one-shot native macOS
administrator authorization. Enter any password only in the macOS dialog or
your own terminal. The program takes
exclusive ownership of this USB device, reads its transport and scanner
identities, then releases it. macOS can briefly remove and recreate the
scanner's small virtual storage volume during capture. No kernel extension or
permanent background service is installed.

The scanner presents itself as USB mass storage (`04f9:60e2`, interface
`08/06/50`). Its scanner commands travel through a vendor-specific bridge.
Generic SCSI access returned `unsupported function` on the development Mac,
so this prototype uses IOUSBHost device capture, which requires administrator
access in an independently built application.

`probe-usb` prints raw configuration descriptors without issuing scanner
commands. `probe-scsi` reports whether the system SCSI interface is available.
Neither diagnostic starts the paper feed.

## Experimental duplex capture

Insert one sheet printed on both sides, then run:

```sh
./build/ds720d authorize-scan
./build/ds720d decode /absolute/path/to/the/reported/capture.jsonl
```

Capture requests native RGB at 300 dpi and reads image memory until the scanner
reports end of page, with limits on time, frame count and total bytes. It saves
the raw capture privately in `captures/`; decoding creates front and back PNGs.
The prototype currently supports this one acquisition configuration only.
The default decoder renders documents with automatic paper cropping and local
white balance. It retains color and 300 dpi resolution without resampling.
PDF export is not implemented.

For photos, faint shading, colored paper or exact acquisition values, use raw
rendering instead:

```sh
./build/ds720d decode /absolute/path/to/capture.jsonl --raw
```

This produces `-raw-front.png` and `-raw-back.png` without cropping or tone
adjustment. Both modes retain the corrected rear orientation. Decoding never
changes the original capture file and does not move the paper feed.
See [document rendering](docs/document-rendering.md) for the algorithm and limits.

`authorize-inspect` performs bounded diagnostics without starting the feed.
The authorization helper is development-only and uses Apple's deprecated
`AuthorizationExecuteWithPrivileges`; a supported distribution mechanism remains
to be designed. No helper is installed permanently.

Earlier experiments produced corrupted images and one stopped a sheet halfway.
Cancellation, timeout cleanup, disconnection and jam recovery are not yet
validated. Do not use valuable or fragile originals for prototype testing.
If the scanner remains internally locked, disconnect and reconnect its USB
cable with no sheet inserted. The program does not clear a foreign firmware lock.

## License and provenance

All source code in this repository is an original implementation under the
[MIT license](LICENSE). It does not link to or distribute a Brother driver,
SANE backend, firmware image, or other manufacturer's binary. Interoperability
research uses USB descriptors, Apple's SDK documentation, and protocol facts
identified by local inspection and emulation of parameter preparation in the
official Linux package. See [protocol notes](docs/protocol.md)
for the distinction between observed facts and unverified behavior.

## Release requirements

Readable duplex PNG acquisition and document cleanup have passed one real-sheet
test. Repeated scans, calibrated color, cancellation, disconnection, missing paper
and recovery still need validation. PDF output, signing/distribution and integration
with macOS scanning applications remain future work. Scans, personal document
data, vendor binaries and local research files are excluded from this repository.
