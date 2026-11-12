# Nanashi installation sources

Verified on 2026-11-12. These references support the first-party French guide at
`/installation-sidestore` and `/installation-nanashi`; they are not a requirement for users to leave the guide
and read another manual. The guide paraphrases the process and retains the names
of native controls so they can be found on the user's device.

## Direct downloads

| Purpose | Official destination | Evidence |
| --- | --- | --- |
| iloader, Intel/Apple Silicon Mac | https://github.com/nab138/iloader/releases/latest/download/iloader-darwin-universal.dmg | Universal DMG; HTTP 200 |
| iloader, Windows x64 | https://github.com/nab138/iloader/releases/latest/download/iloader-windows-x64.msi | MSI; HTTP 200 |
| Windows alternate installer | https://github.com/nab138/iloader/releases/latest/download/iloader-windows-x64.exe | EXE; HTTP 200 |
| Apple iTunes, Windows | https://www.apple.com/itunes/download/win64 | Official 64-bit installer; HTTP 200 |
| LocalDevVPN | https://apps.apple.com/app/localdevvpn/id6755608044 | Coxson Engineering LLC; HTTP 200 |

The current iloader release at verification was 2.4.1. The `latest/download` URLs
follow the publisher's release; recheck asset names when updating the guide.
Windows 32-bit and Windows 10 ARM are not supported by this installer path.
iCloud is not an iloader prerequisite. Apple Devices is a driver alternative when
the documented iTunes path fails, not another compulsory setup step.

## Process evidence

- [SideStore prerequisites](https://docs.sidestore.io/docs/installation/prerequisites):
  computer support, Windows drivers, local VPN and network requirements.
- [SideStore installation](https://docs.sidestore.io/docs/installation/install):
  iloader, device trust, developer mode, login and first manual self-refresh.
- [iloader source](https://github.com/nab138/iloader/blob/v2.4.1/src-tauri/src/sideload.rs):
  stable installer choice and automatic placement of the pairing file. Manual
  pairing-file export is not part of normal setup.
- [Apple developer mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device):
  enabling, restarting and confirming on the phone.
- [LocalDevVPN shortcut source](https://github.com/jkcoxson/LocalDevVPN/blob/main/LocalDevVPN/VPNShortcuts.swift):
  the Enable operation.
- [SideStore refresh shortcut source](https://github.com/SideStore/SideStore/blob/0.7.0-alpha/AltStore/Intents/App%20Intents/RefreshAllAppsIntent.swift):
  Refresh All Apps. Shortcut availability and labels depend on the installed version.
- [Apple personal automations](https://support.apple.com/fr-fr/guide/shortcuts/apdfbdbd7123/ios):
  daily timing and immediate execution. The five-second VPN wait is a practical
  margin, not an Apple or SideStore guarantee.
- [SideStore troubleshooting](https://docs.sidestore.io/docs/troubleshooting/common-issues):
  check Wi-Fi/VPN and restart before attempting invasive account/pairing resets.
- [iloader branding notice](https://github.com/nab138/iloader/blob/v2.4.1/LICENSE-BRANDING):
  retain a discreet attribution link to the original project in the guide.

## Limits of verification

HTTP checks validate link availability, not a successful Windows installation,
Mac installer execution or physical iPhone pairing. Browser tests do not download
or run native installers, enter an Apple account, enable a VPN or sign apps.

The guide must not assert device readiness from a link click. A free Apple account
still needs recurring signature renewal, valid credentials and network access.
Initial self-refresh is separate from installing Nanashi and from configuring a
daily automation. A future iOS update or invalid pairing can require a computer
again. Preserve the existing Nanashi app and backup before any troubleshooting
that could change its identity; never recommend deleting it as a routine fix.

## Ready shortcut and installer preview

- [Owner-shared shortcut](https://www.icloud.com/shortcuts/2afd063477f048f0a16f04c268ce9655), inspected 2026-11-12: three actions, no credential fields. Its SideStore AppIntent descriptor is tied to the original signing team. No universal rebinding is claimed.
- [Apple sharing](https://support.apple.com/en-hk/guide/shortcuts/apdf01f8c054/ios): a recipient confirms adding the shortcut.
- [Apple 27 changes](https://support.apple.com/en-us/149045): shared shortcuts can include automation triggers. The export's time alone does not prove activation or daily repetition.
- [AltStore official Classic catalogue](https://cdn.altstore.io/file/altstore/apps.json): version 2.3.3, build 75, iOS 17.4 minimum. The actual official IPA was downloaded and its metadata and SHA-256 verified.
- [AltStore Remote setup](https://github.com/altstoreio/FAQ/blob/main/altstore-classic/remote-altservers.md): LocalDevVPN, connected Wi-Fi, association and Apple sign-in remain necessary.
- [Classic URL schemes](https://github.com/altstoreio/AltStore/blob/v2.3/AltStore/SceneDelegate.swift): `altstore-classic://install?url=...` avoids ambiguity with AltStore PAL.
- [Native background refresh](https://github.com/altstoreio/AltStore/blob/v2.3/AltStore/AppDelegate.swift): iOS schedules the background work; the website cannot guarantee an execution time.
- [Nanashi Installer source and verification](https://github.com/mkinvest57/nanashi-installer): independent MIT-based iloader adaptation; existing licenses and attribution preserved. Preview status must remain visible until physical acceptance checks pass.

No shortcut was executed, Apple account authenticated, certificate revoked, app migrated or phone installation validated by these website checks.
