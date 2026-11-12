#!/usr/bin/env node
// Node24 can import the website's TypeScript validator without a second implementation.
import { readFile, realpath, access } from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { parseCatalogue } from '../web/src/lib/releases.ts';

const root = fileURLToPath(new URL('../', import.meta.url));
const manifestPath = path.resolve(process.argv[2] || path.join(root, 'web/public/releases.json'));
const project = JSON.parse(await readFile(path.join(root, '.firebaserc'), 'utf8')).projects.default;
if (project !== 'nanashi-mkinvest57') throw new Error('Refusing an unexpected Firebase project');
const manifest = parseCatalogue(JSON.parse(await readFile(manifestPath, 'utf8')));
const serialized = JSON.stringify(manifest);
if (Buffer.byteLength(serialized) > 131072) throw new Error('Catalogue exceeds the public metadata size limit');

// Reuse the official CLI's existing account. No service-account key is created or exported.
// Invoke with `npm exec --package=firebase-tools@15.36.0 -- node ...` or a Firebase CLI on PATH.
let firebaseEntry;
for (const directory of (process.env.PATH || '').split(path.delimiter)) {
  const candidate = path.join(directory, 'firebase');
  try { await access(candidate); firebaseEntry = await realpath(candidate); break; } catch {}
}
if (!firebaseEntry) throw new Error('Firebase CLI missing; run through npm exec with firebase-tools@15.36.0');
const cli = createRequire(firebaseEntry);
const auth = cli('../auth.js');
const account = auth.getProjectDefaultAccount(root);
if (!account) throw new Error('Sign in with the official Firebase CLI before publishing');
await cli('../requireAuth.js').requireAuth({ project, ...account, nonInteractive: true });
const { Client } = cli('../apiv2.js');
const client = new Client({ urlPrefix: 'https://firestore.googleapis.com', apiVersion: 'v1' });
const documentPath = `/projects/${project}/databases/(default)/documents/catalogue/stable`;
await client.request({
  method: 'PATCH', path: documentPath,
  body: { fields: {
    manifest: { stringValue: serialized },
    updatedAt: { timestampValue: new Date().toISOString() },
  } },
});
console.log(`Published validated public catalogue to ${project}/catalogue/stable`);
