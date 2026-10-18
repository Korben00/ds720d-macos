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
managed entitlement. Code signing by itself does not grant that entitlement.
It exposes **ping, capture, cancel** only. Capture is fixed at 300 dpi RGB duplex
for one `04f9:60e2` scanner, bounded by time, bytes and frame count. No client
may supply CDBs, memory addresses, shell commands, executable paths or output paths.
Cancellation applies only to the requesting connection. Only one capture can run.

Every incoming message is authenticated using its XPC audit token through
`SecCodeCreateWithXPCMessage` and a Developer ID requirement with the helper's
own signing team and these exact identifiers: `info.korben.ds720d`,
`info.korben.ds720d.ica`, `info.korben.ds720d.cli`. The client also authenticates
the helper with an XPC peer requirement. Unsigned/adhoc development builds cannot
use the installed service. Both sides use hardened-runtime Developer ID signatures
in a signed distribution build. Processing and file creation run as the user.

The ICA module advertises a 300 dpi RGB document feeder with optional duplex.
It delivers image bands for memory-based clients and ImageIO files for file-based
clients. It does not offer an overview pass. Current physical validation covers
the native acquisition engine; installed ICA behavior still requires verification.

## Build and sign

```sh
make app                  # adhoc build for software tests
DS_SIGN_IDENTITY='Developer ID Application: …' make dmg
```

For distribution, also provide `DS_INSTALLER_IDENTITY` with a **Developer ID
Installer** certificate and `DS_NOTARY_PROFILE` with an existing `notarytool`
keychain profile. A Mac App Store installer certificate is a different identity.
Never put keys, passwords or notarization credentials in the repository.
Without those optional settings the applications and DMG can be signed, but the
installer package is unsigned and the DMG has no notarization ticket. Such a
development build is not a finished Gatekeeper-ready release.

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
[official VirtualScanner SDK example](https://developer.apple.com/library/archive/samplecode/VirtualScanner/VirtualScanner.zip),
and the public ICADevices, IOUSBHost, Security and XPC headers in the current SDK.
The module is an original implementation; no Apple sample code is incorporated.
