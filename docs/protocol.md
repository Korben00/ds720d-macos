# DS-720D interoperability notes

These notes describe wire-format facts used by an original implementation.
They are not copied manufacturer source code. All vendor-specific behavior
below still requires confirmation through actual USB exchanges.

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
then requests that many bytes, capped at 255. Image and mechanical commands
are not implemented yet.

## Evidence

The manufacturer package used for local protocol research is
`libsane-dsseries_1.0.5-1_amd64.deb`, downloaded from
[Brother](https://download.brother.com/welcome/dlf100976/libsane-dsseries_1.0.5-1_amd64.deb).
Its SHA-256 is
`4e0b649df73f8e9900c045d5bbf7361fd32ca7e3dc18ca2723406fca66809927`.
It was extracted for inspection, not installed or executed. Neither this
package nor its disassembly belongs in the MIT source repository.

Native capture behavior is documented in the local macOS SDK headers
`IOUSBHostObject.h` and `IOUSBHostDefinitions.h`. The capture option requires
root, or Apple's documented device-access entitlement and authorization.
That entitlement is restricted: adding it to an ad-hoc signature caused macOS
to refuse to run the executable. This project therefore does not add it.

## Verification boundary

Software tests exercise packet corruption, short transfers, transaction
ownership, scanner errors and bounded waits against synthetic responses.
They do not prove hardware compatibility or successful scanning. The next
acceptance gate is an administrator-run `ds720d probe` on the real scanner.
