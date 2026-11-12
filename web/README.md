# Nanashi web

A small, static React site for Nanashi releases, installation instructions and project attribution. Vercel project root: `web`. Build command: `npm run build`. Output: `dist`. Native apps remain in the repository root; this site is not a web port of the app.

## Development

Use Node 24 LTS (Node 20.18 also satisfies this Vite version).

```sh
npm ci
npm run dev
npm run build
npm test
npm run test:e2e
```

Playwright uses installed Google Chrome when `PLAYWRIGHT_CHANNEL=chrome` is set; otherwise it uses its managed Chromium. Browser tests exercise platform selection, keyboard tabs, release availability, checksums, retry and narrow layouts. Unit tests cover untrusted release metadata and Firebase fallback/cancellation. No test calls an AI provider or uploads health records.

## Release catalogue

`public/releases.json` is the versioned, static fallback and the default source. Empty publication state is deliberately `latest: null`; it never invents a download. `Tools/nanashi_release.py` in the parent repository generates published metadata from verified artifacts.

```json
{
  "schemaVersion": 1,
  "repository": "https://github.com/mkinvest57/nanashi",
  "updatedAt": null,
  "latest": null
}
```

A published `latest` contains `version`, `releaseURL`, `publishedAt` and optional `ios` / `android` artifacts. Each artifact requires `version`, `build` (string or integer), `downloadURL` (HTTPS), `size` (positive bytes), `sha256` (64 hexadecimal characters). iOS additionally requires the preserved `bundleIdentifier` (`com.rayanmakhlouf.noopdev.noop`) and `minOSVersion`. Android requires `applicationId` (`com.rayanmakhlouf.nanashi`) and `minSDK`. Each artifact version must agree with the release version. Extra generator metadata is ignored, not rendered as HTML.

Optional `sideStore.sourceURL` is a public HTTPS source manifest. The client derives `sidestore://source?url=...` itself and only exposes it when an eligible iOS artifact exists. The source manifest is published as `/altstore-source.json`; it is not needed for Android-only releases.

### Optional Firebase mirror

Set `VITE_FIREBASE_PROJECT_ID` to the public Firebase project ID at build time. The site reads one public Firestore document:

`projects/{project}/databases/(default)/documents/catalogue/stable`

Its `manifest` field is a string containing the same release catalogue JSON. The client fetches remote and static manifests in parallel and validates both through the same parser. A usable release always wins over an empty or artifact-free catalogue; stable semantic version and publication date select the newer release, never the metadata `updatedAt` value. A stale Firebase mirror therefore cannot hide a new static release. A missing document, permissions error, invalid metadata or three-second remote timeout leaves the static result available; static errors likewise leave a valid remote result available. Static loading is bounded to five seconds; the outer page request has a twelve-second guard and may be retried explicitly. There are no listeners, polling, Firebase Auth, cookies, private records, admin credentials or health uploads. A public project ID is not an admin credential. The Firestore rules must allow reads only of the public catalogue document and deny client writes.

## Design and provenance

The website carries the established Nanashi Cold Glass identity and Harbor Blue palette. It adapts three sources retrieved with the official 21st CLI on 2026-11-12:

- [Glass Card by @educalvolpz](https://21st.dev/@educalvolpz/components/glass-card), component 28259: frosted body, polished inset rim and shallow shadow. Pointer tracking, displacement filters and the animation runtime are omitted.
- [Glass Button by @jahed](https://21st.dev/@jahed/components/glass-button), component 4922: rounded reflective face, edge highlight and finite press response. Static CSS replaces runtime-injected CSS and CVA.
- [Pill Morph Tabs by @ruixen.ui](https://21st.dev/@ruixen.ui/components/pill-morph-tabs), component 7878: glass selection plate and labelled tab row. CSS replaces the motion dependency; native buttons implement roving keyboard focus.

The page includes visible links to these sources. These are source-informed adaptations, not claims of unchanged component source or authorship. The retrieved component metadata did not include individual license fields; this project does not invent MIT notices for those authors. See the [21st terms](https://docs.21st.dev/terms) and retain their attribution when reusing the adaptations. No 21st catalogue preview media are republished.

`public/icon*.png` comes from Nanashi's existing icon assets. `public/app-preview.jpg` is a compressed capture of the existing iPhone simulator's synthetic fixture (`build/nanashi-coldglass/captures/home-dark.png`), inspected before inclusion. It contains no private health export or profile image. The page labels it as demonstration data; it is not evidence of a new hardware test or Android parity. Lucide icons retain their package license.

The native application remains an independent fork of [NOOP](https://github.com/ryanbr/noop). Preserve its PolyForm Noncommercial 1.0.0 license, required copyright notice and contributor attribution. No commercial ownership or official WHOOP affiliation is implied.

## Privacy

The browser requests static assets and public release metadata. Downloads link to GitHub; iPhone setup links to SideStore's official documentation. No audience analytics, tracking SDK, service worker, health form or authentication is included. Hosting services may retain ordinary technical access logs. The native Coach remains optional and uses the provider configured by the user; the public website does not access it.
