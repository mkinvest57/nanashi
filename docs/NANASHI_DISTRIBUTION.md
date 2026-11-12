# Nanashi distribution

Nanashi is a personal, noncommercial adaptation of [NOOP](https://github.com/ryanbr/noop),
maintained separately at [mkinvest57/nanashi](https://github.com/mkinvest57/nanashi).
The upstream source, license, required notice and third-party attribution remain intact.
Required Notice: Copyright 2026 NoopApp. [PolyForm Noncommercial 1.0.0](../LICENSE)
does not grant commercial use; third-party dependencies retain their own terms in
[NOTICE](../NOTICE) and [ATTRIBUTION.md](../ATTRIBUTION.md).

The website is an installation and release hub. Native Bluetooth collection, local health
history and calculations stay in the native applications. Public release metadata may be
mirrored to Firebase; this distribution process never uploads health databases, backups,
API keys, Apple credentials, provisioning profiles or private signing keys.

## Installation channels

| Platform | Distributed artifact | Installation |
| --- | --- | --- |
| iPhone | Release IPA with an ad-hoc capability template | SideStore signs it with the device owner's account; retain the widget extension. |
| Android | APK signed with Nanashi's private release key | Download the APK and permit installation from the chosen browser/file manager when Android requests it. |

The site only enables a download after the corresponding artifact has been inspected and
published. An initial `releases.json` with `latest: null` is intentional: it does not imply
that a release is available. The APK's `minSDK` and IPA's `minOSVersion` come from the actual
artifacts, not from website copy or an old release manifest.

SideStore supports these [documented URL schemes](https://docs.sidestore.io/docs/advanced/url-schema):

```text
sidestore://source?url=<percent-encoded HTTPS source URL>
sidestore://install?url=<percent-encoded HTTPS IPA download URL>
```

The production source is `<website origin>/altstore-source.json`. The website must also
serve `/icon.png`. A GitHub release includes the same JSON files as downloadable assets,
but the stable website URL is the source users add to SideStore.

Adding the source makes published updates discoverable. It does not remove Apple's signing
limits. [Apple's Personal Team documentation](https://developer.apple.com/help/account/basics/about-your-developer-account)
states that free provisioning expires after seven days, with limits of three apps per
device, three devices and ten App IDs. The existing daily 09:00 shortcut can request
renewal through SideStore and LocalDevVPN, but successful execution still depends on the
device, network, VPN and Apple/SideStore services. A new iPhone requires its own initial
SideStore setup; the website cannot silently provision it. Android installation is also
subject to device and regional requirements described in
[Google's developer verification guidance](https://developer.android.com/developer-verification).

## Preserve existing installations

The distributed, not-yet-personally-signed iOS bundle identifiers are fixed:

| Item | Identifier |
| --- | --- |
| Application | `com.rayanmakhlouf.noopdev.noop` |
| Widget | `com.rayanmakhlouf.noopdev.noop.widgets` |
| Shared App Group | `group.com.rayanmakhlouf.noopdev.noop.staging` |
| SideStore source | `com.rayanmakhlouf.nanashi.source` |
| Android release application | `com.rayanmakhlouf.nanashi` |

SideStore applies the device owner's account-specific suffix while signing. Do not put a
personal suffix in a public IPA or source manifest. Retain the same SideStore account,
bundle identity, widget and App Group when updating the existing Nanashi. Do not uninstall
the installed app as a routine update step. Make a recent on-device export before a major
update, then check historical nights, Coach credentials, Health permissions and strap
connection on the phone. Publishing a binary does not itself validate these device flows.

Android updates require the same application ID and signing certificate, and an increasing
`versionCode`. Generate a private release key once, keep a separate secure backup, and use
it for every release. Never use the repository's shared `fork-debug.keystore`. Losing the
private key prevents normal in-place updates; see [Android signing](https://developer.android.com/studio/publish/app-signing).
The generator rejects a signer change relative to the previously published catalog.

## Manual release workflow

The dedicated [Nanashi release workflow](../.github/workflows/nanashi-release.yml) replaces
the upstream release workflow for this fork. Dispatch it from `main` with:

- A stable marketing version shared by Apple and Android, such as `12.1.1`.
- An iOS build counter, such as `446`.
- A separate Android build counter, such as `559`.
- The real HTTPS origin of the deployed website.

It uses the tag `v<version>`. Use a new marketing version for the next public release;
published versions and their binary files are immutable. The workflow refuses to attach
new source to an existing tag or public release. It also stops if `main` moves while the
builds are running, so the site catalog commit cannot overwrite concurrent source changes.

Configure these repository Actions secrets before an Android release:

| Secret | Value |
| --- | --- |
| `NANASHI_ANDROID_KEYSTORE_BASE64` | Base64 of the private release keystore, without line wrapping |
| `NANASHI_ANDROID_STORE_PASSWORD` | Keystore password |
| `NANASHI_ANDROID_KEY_ALIAS` | Release key alias; never `androiddebugkey` |
| `NANASHI_ANDROID_KEY_PASSWORD` | Private key password |
| `NANASHI_VERCEL_DEPLOY_HOOK` | Optional secret Vercel deploy hook URL |

The signing files are created only in the ephemeral build runner and removed even after a
failed build. No signing credentials are emitted in output or included in release assets.
The workflow has no debug-key fallback. Its Android Gradle properties are
`nanashiApplicationId`, `nanashiVersionName` and `nanashiVersionCode`.

The pipeline:

1. Runs the distribution regression tests and validates release inputs.
2. Builds iOS Release on macOS 26 and runs the shared macOS application tests. It copies
   the built app, removes Watch only from the distribution copy, retains the widget and
   calls `prepare-ios-sideload-app.sh` to embed discoverable HealthKit/App Group capabilities.
3. Runs Android JVM tests and builds the privately signed full Release APK with JDK 17 and
   SDK/build-tools 35. The staging flavor and debug certificate are never published.
4. Inspects each binary with native tools. It records metadata bound to that file's byte
   size and SHA-256; the iOS inspector also checks the complete bundle signature and
   app/widget capabilities, and the Android inspector runs `apksigner verify`.
5. Generates the web catalog, SideStore source and checksums after both platform jobs pass.
   A draft release receives both binaries, manifests, license and attribution before it
   becomes public. A failed build never creates a public partial release.
6. Commits the two generated JSON files to `web/public/`. Vercel's Git integration must
   deploy this commit, or the optional deploy hook must be configured. GitHub's default
   Actions token does not trigger another GitHub Actions workflow. A hook response means
   a deployment was requested, not that the website has finished deploying.

The final release job needs permission to push this catalog commit to `main`. If repository
branch protection prevents that, keep the complete release and submit the two generated
files through the repository's required review process instead. Do not delete or overwrite
the public binaries to recover a failed catalog deployment. The generated `releases.json`
and `altstore-source.json` are attached to the release and can be restored directly.

## Artifact inspection and local generation

`Tools/nanashi_release.py` uses the Python standard library. `inspect-ios` additionally
requires macOS `codesign`. `inspect-android` requires Android `aapt2` and `apksigner` with
a working JDK. `generate` runs on any platform and verifies the artifacts against their
inspection records before producing public URLs.

```sh
python3 Tools/nanashi_release.py inspect-ios \
  --ipa dist/Nanashi-ios-v12.1.1-b446.ipa --output dist/ios.metadata.json

python3 Tools/nanashi_release.py inspect-android \
  --apk dist/Nanashi-android-v12.1.1-b559.apk \
  --aapt2 "$ANDROID_HOME/build-tools/35.0.0/aapt2" \
  --apksigner "$ANDROID_HOME/build-tools/35.0.0/apksigner" \
  --output dist/android.metadata.json

python3 Tools/nanashi_release.py generate \
  --ipa dist/Nanashi-ios-v12.1.1-b446.ipa --ios-metadata dist/ios.metadata.json \
  --apk dist/Nanashi-android-v12.1.1-b559.apk --android-metadata dist/android.metadata.json \
  --base-url https://YOUR-DEPLOYED-NANASHI-SITE \
  --repository https://github.com/mkinvest57/nanashi --tag v12.1.1 \
  --source-sha "$(git rev-parse HEAD)" --output-dir dist/public

python3 -m unittest Tools.nanashi_release_tests
```

The example website host must be replaced with the verified production URL. These commands
prepare files; they do not publish or install anything. For an existing release channel,
also pass `--previous-catalog web/public/releases.json` and, when present,
`--previous-source web/public/altstore-source.json`. These preserve older compatible iOS
versions, enforce monotonic build counters and pin the Android signing certificate.
The CLI can produce a one-platform catalog by omitting the other artifact and metadata
together; the automated release workflow requires both platforms.

The web catalog contract is:

```json
{
  "schemaVersion": 1,
  "updatedAt": "ISO-8601 timestamp or null before the first release",
  "repository": "https://github.com/mkinvest57/nanashi",
  "latest": null,
  "sideStore": null
}
```

After a real release, `latest` contains `version`, `releaseURL`, `publishedAt`,
`sourceCommit`, and the available `ios`/`android` objects. Each platform object contains
`version`, `build`, `downloadURL`, `size` and `sha256`. iOS additionally contains
`bundleIdentifier` and `minOSVersion`; Android contains `applicationId`, `minSDK` and
`signingCertificateSHA256`. `sideStore` then contains `sourceURL` and `addSourceURL` if
an iOS artifact exists. Source permissions are derived from the IPA, as required by the
[AltStore source specification](https://faq.altstore.io/developers/make-a-source).

## Verification boundaries

The focused tool tests cover changed artifacts, signing identity drift, changed app/group
identifiers, missing extensions/capabilities, personally provisioned IPAs, malformed paths,
Android debug builds, absent artifacts, invalid URLs, platform version mismatches and
preservation of earlier releases. Native-tool tests use controlled outputs so they can run
without Xcode or Android tools; the release workflow performs the real binary inspections.

Compilation and signature verification do not prove real-phone Bluetooth behavior, data
retention, Keychain continuity, Apple Health permissions or automatic SideStore renewal.
Record those checks separately after an actual device update. No publication step changes
the user's existing SideStore pairing, LocalDevVPN configuration or daily renewal schedule.

## Deployed services

The public installation hub is https://nanashi-mk.vercel.app. The Vercel project is
`nanashimks-projects/nanashi`. Deploy from `web/` (project root directory `.`), not
from the native repository root. The GitHub integration did not have access to the
new fork at initial setup; deployments currently use the authenticated Vercel CLI.
Do not assume that pushing GitHub automatically deploys the site.

Firebase project `nanashi-mkinvest57` contains only `catalogue/stable` public release
metadata, Standard free tier in `eur3`, with deletion protection. After generating
the catalogues, run the publisher documented in `firebase/README.md`, build and
deploy the website, and verify the public manifest plus both artifact links.

The Android release key is held outside the repository in the owner's private
application-support directory and in encrypted GitHub Actions secrets. Keep that
private local key and password backed up; losing the key prevents normal Android
updates. No key, API secret, health database or personal backup is included here.
