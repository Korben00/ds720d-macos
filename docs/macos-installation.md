# Installed macOS driver

The installer adds four project-owned components:

| Component | Installed location |
| --- | --- |
| GUI | `/Applications/DS-720D Scanner.app` |
| Image Capture module | `/Library/Image Capture/Devices/DS720DICA.app` |
| Fixed USB service | `/Library/PrivilegedHelperTools/info.korben.ds720d.usb` |
| On-demand launchd job | `/Library/LaunchDaemons/info.korben.ds720d.usb.plist` |

macOS requests administrator permission to install these components. Subsequent
scans use XPC and do not invoke administrator authorization. The old `authorize-*`
CLI commands remain development diagnostics only and are not used by the GUI or
ICA module.

The service runs as root because IOUSBHost device capture requires root or a
managed entitlement. It exposes **ping, prepare, release** only. Preparation
captures exactly one `04f9:60e2` device, selects its configuration without kernel
driver matching, then surrenders ownership without resetting USB. It never opens
the mass-storage interface, sends scanner commands, receives image bytes or
creates files. No client may supply CDBs, memory addresses, shell commands,
executable paths or output paths. A connection-scoped lease prevents another
client from reconfiguring an ongoing acquisition, expires after 180 seconds and
is released on disconnect. Release cannot remove another connection's lease.

The GUI/ICA client opens the bulk pipes and runs the fixed 300 dpi RGB duplex
engine as the logged-in user, bounded by time, bytes and frame count.
Cancellation is local to that client and keeps the service lease until scanner
STOP/RELEASE cleanup finishes. This separation matters because macOS classifies
the scanner's `08/06/50` interface as removable storage. TCC denied an interface
open in the root daemon; an unprivileged pipe-only hardware probe succeeded.
macOS may request removable-volume consent once for the GUI or ICA module.
The signed bundles contain a usage description; the driver does not request
Full Disk Access. Code signing and notarization do not replace privacy consent.

Every incoming message is authenticated using its XPC audit token through
`SecCodeCreateWithXPCMessage` and a Developer ID requirement with the helper's
own signing team and these exact identifiers: `info.korben.ds720d`,
`info.korben.ds720d.ica`, `info.korben.ds720d.cli`. The client also authenticates
the helper with an XPC peer requirement. Unsigned/adhoc development builds cannot
use the installed service. Both sides use hardened-runtime Developer ID signatures
in a signed distribution build. Processing and file creation run as the user.

The ICA module advertises a 300 dpi RGB document feeder with optional duplex.
It delivers image bands for memory-based clients and ImageIO files for file-based
clients. It does not offer an overview pass. On the development Mac, installation,
authenticated service access, ICA enumeration, opening a scanner session and
reading the feeder's 300 dpi/duplex capabilities have been verified without
per-scan administrator authorization. On 18 October 2026, one complete duplex
pass through ImageCaptureCore produced two readable, correctly oriented PNGs
at 300 dpi on macOS 27.0.1 / Apple Silicon, using the installed preview.3 module
and service as user UID 501. The pages measured 2463×3478 and 2464×3478 pixels
after cleanup. No administrator authorization API is called in that scan path.
This is one successful hardware pass, not validation of every error or format.

`DS720DDoctor` checks detection/session readiness without scanning. Image Capture
session opening and functional-unit parameter delivery are asynchronous; the
diagnostic waits for readiness and resolutions before inspecting the feeder.
`DS720DDoctor usb-probe` additionally prepares the connection through the root
service and opens/closes the two bulk pipes as the user, without moving paper.
The GUI's File menu provides the same check. USB ownership is surrendered without a device
reset, so closing a transfer does not disconnect the ICA client. New interfaces
created during configuration are re-enumerated for at most three seconds.
`make build/DS720DICAScan-universal` builds an explicit hardware test client.
Only its `scan /absolute/private/output-directory` command starts one duplex pass.
No CI job executes that command.

## Build and sign

```sh
make app                  # adhoc build for software tests
DS_SIGN_IDENTITY='Developer ID Application: …' make dmg
```

For distribution, also provide `DS_INSTALLER_IDENTITY` with a **Developer ID
Installer** certificate and `DS_NOTARY_PROFILE` with an existing `notarytool`
keychain profile. A Mac App Store installer certificate is a different identity.
With that profile set, the build notarizes and staples the installer before
putting it into the DMG, then notarizes and staples the DMG itself.
Never put keys, passwords or notarization credentials in the repository.
Without those optional settings the applications and DMG can be signed, but the
installer package is unsigned and the DMG has no notarization ticket. Such a
development build is not a finished Gatekeeper-ready release.

If a notarization profile is not configured, run
`packaging/macos/configure-notary.command` locally. It obtains the team ID from
the installed app and asks for the Apple ID. Apple's tool prompts for an
app-specific password directly in Terminal and stores it in Keychain under
`ds720d-notary-TEAMID`. The script does not read or export the password.
A Developer ID Installer identity remains separately necessary to sign the pkg:
see Apple's [certificate creation](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)
and [CSR instructions](https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request/).

Packaging signs inside a temporary directory outside File Provider storage,
then copies only the selected deliverables into `build/` and `dist/`. No scan,
private research file or vendor binary enters the package.

## Uninstall

Close scanning applications. The following explicit commands remove only this
driver (administrator authorization is required):

```sh
sudo launchctl bootout system/info.korben.ds720d.usb
sudo rm /Library/LaunchDaemons/info.korben.ds720d.usb.plist
sudo rm /Library/PrivilegedHelperTools/info.korben.ds720d.usb
sudo rm -r '/Library/Image Capture/Devices/DS720DICA.app'
sudo rm -r '/Applications/DS-720D Scanner.app'
```

User scan files are not removed.

Apple references: [device module launch behavior](https://developer.apple.com/library/archive/qa/qa1946/_index.html),
[removable-volume consent](https://developer.apple.com/documentation/bundleresources/information-property-list/nsremovablevolumesusagedescription),
[Apple DTS discussion of helper and GUI consent](https://developer.apple.com/forums/thread/802650),
[official VirtualScanner SDK example](https://developer.apple.com/library/archive/samplecode/VirtualScanner/VirtualScanner.zip),
and the public ICADevices, IOUSBHost, Security and XPC headers in the current SDK.
The module is an original implementation; no Apple sample code is incorporated.
