# Nanashi

Your sleep, recovery and training, on your terms.

Nanashi is a personal, noncommercial fork of [NOOP](https://github.com/ryanbr/noop).
It keeps the local Bluetooth, SQLite and physiological analytics foundation while
adding its Cold Glass identity, an improved iPhone navigation, a personalized Coach,
and its own distribution site and release catalogue.

## Install

Open **[nanashi-mk.vercel.app](https://nanashi-mk.vercel.app)** on your phone for the
platform-specific guide and available downloads.

- **iPhone:** install the Nanashi IPA with SideStore and your own Apple account.
  Keep the app and widget extensions. A free Apple account requires periodic
  re-signing; SideStore can automate it when its local VPN and network are available.
- **Android:** download the signed Nanashi APK and allow installation from your
  browser when Android asks. Android 8 or newer is required.
- **Updates:** use [Nanashi Releases](https://github.com/mkinvest57/nanashi/releases),
  never the upstream NOOP release channel for this fork.

The existing Nanashi iPhone bundle identity is preserved. Update the installed app
instead of deleting it, and make a recent local backup first. Signing with a different
Apple team may create a different sandbox; a website cannot bypass Apple's signing
rules or migrate a private sandbox automatically.

See [distribution and release instructions](docs/NANASHI_DISTRIBUTION.md).

## What lives where

| Part | Location | Purpose |
| --- | --- | --- |
| iOS and macOS | `Strand/`, `StrandiOS/`, `Packages/` | Native app, local storage and analytics |
| Android | `android/` | Kotlin app with matching physiological calculations |
| Website | `web/` | Vercel installation hub and release instructions |
| Firebase | `firebase/` | Public release catalogue only |
| Release tooling | `Tools/nanashi_release.py` | Inspect actual artifacts, build SideStore/site catalogues |

Health records remain on the device. Firebase stores public download metadata;
there is no Nanashi health account, automatic health upload, telemetry or remote
strap processing. The optional Coach sends data to the provider explicitly selected
and authorized by the user. API keys stay in the platform's protected storage.

## Build and verify

The source of truth for Apple targets is `project.yml`; regenerate with XcodeGen.

```sh
xcodegen generate
xcodebuild -project Strand.xcodeproj -scheme NOOPiOS \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Strand.xcodeproj -scheme Strand \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
cd web
npm ci
npm test
npm run build
```

Android builds require JDK17, Android SDK35 and a private signing key for releases.
No private signing keys, real health databases, API credentials or generated
applications belong in Git. See [BUILD](docs/BUILD.md), [iOS](docs/IOS.md), and
[the Firebase catalogue](firebase/README.md) for the separate build/deployment steps.

## Upstream and license

This fork integrates NOOP `main` through
[`2a1de760`](https://github.com/ryanbr/noop/commit/2a1de7609843b095505274ad6fc811757210be80).
The upstream published release `v12.0.0` is older than that source revision;
Nanashi release `12.1.1` adds the fork integration and distribution changes. See [integration notes](docs/NANASHI_UPSTREAM.md).

Upstream work remains credited to [@ryanbr and the NOOP contributors](https://github.com/ryanbr/noop/graphs/contributors).
Protocol interoperability credits remain in the source and upstream documentation.
The license remains [PolyForm Noncommercial 1.0.0](LICENSE), including the required
notice **Copyright 2026 NoopApp**. This fork does not grant commercial rights or
represent an official WHOOP product. Adapted 21st.dev components retain their
individual notices in the design packages and [website credits](web/THIRD_PARTY.md).
