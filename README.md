# DS-720D for macOS

An independent, MIT-licensed native driver project for the **Brother DSmobile
DS-720D**, starting with a command-line interface. The current development host
is Apple Silicon running macOS 27.0.1.

**Development status:** native device discovery works on the connected DS-720D.
USB packet handling and the scanner bridge state machine build and pass software
tests. Exclusive USB access, the scanner inquiry, image acquisition, duplex
decoding, and integration with macOS applications are still awaiting hardware
validation. This is not yet a working scanning release.

## Build and test

Install Apple's Command Line Tools, then run:

```sh
make
make test
make analyze
./build/ds720d list
```

There are no third-party libraries to install. The program uses Apple's
Foundation, IOKit and IOUSBHost frameworks. The deployment target is macOS 14;
older macOS releases and Intel Macs have not been tested. A deployment target
is not a hardware compatibility claim.

The GitHub workflow is prepared to build and run software tests on Apple
Silicon and Intel runners. It has not run remotely yet and cannot test a
physical scanner.

## Hardware diagnostic

Connect exactly one DS-720D, close applications that might use it, then run:

```sh
sudo ./build/ds720d probe
```

Enter the administrator password in your own terminal. The program takes
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

## License and provenance

All source code in this repository is an original implementation under the
[MIT license](LICENSE). It does not link to or distribute a Brother driver,
SANE backend, firmware image, or other manufacturer's binary. Interoperability
research uses USB descriptors, Apple's SDK documentation, and protocol facts
identified from the official Linux package. See [protocol notes](docs/protocol.md)
for the distinction between observed facts and unverified behavior.

## Release requirements

Before calling the driver functional, validate exclusive access and scanner
identity, obtain readable images from real sheets, verify both sides in duplex
mode, and test cancellation, disconnection, missing paper, and recovery. PNG/PDF
output and integration with macOS scanning applications are planned after the
first real scan.
