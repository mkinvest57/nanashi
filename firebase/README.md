# Nanashi release catalogue

Project: `nanashi-mkinvest57`, Standard edition, free tier, Europe (`eur3`).
Deletion protection is enabled. Firebase serves **public distribution metadata only**. The native apps keep their
health databases on-device and do not depend on Firebase to launch or sync a strap.
No health data, API keys, device identifiers, accounts, or telemetry are uploaded.

The only anonymously readable document is `catalogue/stable`. It contains a
`manifest` string, the validated JSON generated as `web/public/releases.json`, and
an `updatedAt` timestamp. Browser writes, collection listing, and every other path
are denied. Publishing requires project IAM authorization. The site validates the
document and falls back to its bundled manifest when Firebase is unavailable.

Deploy rules with `firebase deploy --only firestore --project PROJECT_ID` from the
repository root. Use the free Spark plan; no billing account is required for this
catalogue. Create the default Firestore database in `eur3` before deploying rules.
Set the website's public `VITE_FIREBASE_PROJECT_ID` build variable to the exact
project ID. Never add service account credentials to Git or Vite environment values.

Test with Node24, JDK21, `npm ci --prefix firebase`, followed by
`npx -y firebase-tools@15.36.0 emulators:exec --only firestore --project demo-nanashi "npm test --prefix firebase"`.
The grpc override updates a vulnerable transitive development dependency while
keeping the Firebase test SDK pinned; the website has no Firebase SDK dependency.

After a release has been validated and its static catalogues generated, publish
the same metadata using the existing authorized Firebase CLI account:

```sh
npm exec --package=firebase-tools@15.36.0 -- node firebase/publish-catalogue.mjs
```

The publisher reuses the website's validation and only sends the resulting public
manifest. It does not export credentials or create a service-account key. It uses
the pinned CLI's authentication client because the available Firestore tooling has
no document publishing command. The website compares the local and remote catalogues
by release version/date so an old mirror cannot hide a newer deployment.

The upstream NOOP project has no operated backend. This separate catalogue is a
Nanashi fork distribution service and is not an upstream NOOP service.
