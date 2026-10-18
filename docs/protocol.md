# DS-720D interoperability notes

These notes describe wire-format facts used by an original implementation.
They are not copied manufacturer source code. Hardware observations and facts
derived from local reference inspection are distinguished below.

## Observed on the development machine

The connected device reports vendor `0x04f9`, product `0x60e2`, one USB mass
storage interface with class/subclass/protocol `08/06/50`, two endpoints,
and SCSI revision `0.27`. macOS 27.0.1 attaches its storage driver and presents
a small, read-only virtual volume. No scanner serial number or document image
is recorded in the repository.

## Transport

USB Mass Storage Bulk-Only Transport uses a 31-byte command block wrapper and
a 13-byte command status wrapper. Integers in these wrappers are little endian.
The implementation verifies signatures, tags, status values, transfer counts
and residue before accepting a successful transaction. Invalid framing ends
the USB session rather than attempting to continue with unknown framing.

The vendor command block is 16 bytes:

| Bytes | Meaning |
| --- | --- |
| 0–1 | `c5 07` |
| 2–5 | Address, zero for the bridge operations used here |
| 6–9 | Transfer length, big endian |
| 10 | Operation group |
| 11 | Action |
| 12 | Channel |
| 13–15 | Zero |

Group `ff`, action `02` reads a four-byte transport identity, expected to be
`NOVA`. Service actions `03`, `04`, `05`, `06` query lock state, query completion,
claim a transaction, and release a transaction. They read 16-byte replies with
a little-endian size at offset zero and a result flag at offset eight.

Group `02` is the scanner bridge. Action `03` writes a packet. A read uses
action `01`, waits for completion, then action `02`. Each read or write has its
own firmware transaction lock. The client checks for an existing lock and
does not forcibly clear another transaction.

Channel zero carries a ten-byte scanner command followed by any output data,
and receives scanner response data. Channel one returns a four-byte scanner
status. Inquiry (`12`) first requests five bytes to learn the response length,
then requests that many bytes, capped at 255. These exchanges, including the
`BROTHER DS-720D` identity, have succeeded on the connected scanner.

## Native image acquisition

The working experimental sequence is unit ready (`00`), illumination preparation,
calibration-format inspection, set window (`24`), reserve (`16`), start (`1b`,
byte five `c0`), image reads (`28`), stop (`1b`, byte five zero), release (`17`).
The observed calibration flags are `03`; the reference preparation path considers
this state already calibrated. Other states are rejected before starting.

The native window has an eight-byte header and a 71-byte descriptor. It selects
300 dpi, 2592 pixels, eight-bit RGB (composition `05`), duplex, and a maximum
4335 physical rows per face including the rear sensor offset. Even a grayscale
request is expanded to RGB by reference parameter preparation. Direct grayscale
requests in early experiments yielded sparse, banded data and a blank rear image.
Compression fields at descriptor offsets 32 and 33 remain zero. Descriptor byte
42 is `e0`; offset 61 is a background row count, not a sheet count.

This model uses a memory image path rather than ordinary channel-zero image
response data. After each image read command, channel two returns six
little-endian 32-bit words. Words 3 and 4 multiply to the available byte length;
word 5 is the image memory address. State 1 indicates data and state 3 end of
page. Empty end-of-page frames have been observed. Memory reads use `c3 07`,
with big-endian address at byte 2 and length at byte 6, in chunks up to 65536.
They do not acquire an additional firmware transaction lock.

In the successful RGB capture, metadata reported 2592 component bytes and
240 component rows, totaling 622080 bytes per block. This is 80 physical RGB
rows of 7776 bytes each, not 240 physical image rows. Each physical row contains
separate R, G and B planes. Front and rear data alternate in 80-physical-row
stripes; this alternation applies to the entire stream rather than USB transfer
boundaries. The rear sensor is horizontally mirrored. All these layout facts
were checked against the real decoded images.

One complete capture contained 94 data blocks and one empty end-of-page block:
58,475,520 bytes, decoded to two 2592-by-3760 RGB PNGs at 300 dpi. Both sides
contain legible text. No captured pixels or identifying document contents are
included in these notes. The decoder now applies optional document rendering:
the same captured sheet was checked visually after paper cropping and local white
balance. This does not establish calibrated color or exact page alignment.
A separate channel-zero streaming experiment was invalid
for this configuration and stopped a sheet before it had cleared the feed.

## Evidence

The manufacturer package used for local protocol research is
`libsane-dsseries_1.0.5-1_amd64.deb`, downloaded from
[Brother](https://download.brother.com/welcome/dlf100976/libsane-dsseries_1.0.5-1_amd64.deb).
Its SHA-256 is
`4e0b649df73f8e9900c045d5bbf7361fd32ca7e3dc18ca2723406fca66809927`.
It was extracted for inspection and selected parameter-preparation routines
were emulated locally without USB access. It was not installed, linked into the
driver, or run natively. Neither this package, its disassembly nor the research
emulator belongs in the MIT source repository. The encoder and generic RGB
decoder here are original code; only interoperability facts are recorded.

Native capture behavior is documented in the local macOS SDK headers
`IOUSBHostObject.h` and `IOUSBHostDefinitions.h`. The capture option requires
root, or Apple's documented device-access entitlement and authorization.
That entitlement is restricted: adding it to an ad-hoc signature caused macOS
to refuse to run the executable. This project therefore does not add it.

## Verification boundary

Software tests exercise packet corruption, short transfers, transaction
ownership, scanner errors and bounded waits against synthetic responses. Image
tests compare decoded RGB pixel values, mirrored rear orientation, stripe
boundaries across differently sized frames, DPI metadata, both forms of end of
page, and rejection of malformed or incomplete captures. Build, sanitizer tests
and static analysis pass locally. The real-sheet test establishes a first duplex
scan on one Apple Silicon Mac with firmware 0.27, not broad compatibility,
recovery reliability or production image quality. Document-rendering tests also
check uneven gray paper, a different rear brightness, thin dark and faint print,
color retention, border removal and preservation of the original RGB input.
