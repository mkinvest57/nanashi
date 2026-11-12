import { after, before, test } from 'node:test';
import { readFile } from 'node:fs/promises';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { collection, deleteDoc, doc, getDoc, getDocs, setDoc, updateDoc } from 'firebase/firestore';

let environment;
before(async () => {
  environment = await initializeTestEnvironment({
    projectId: 'demo-nanashi',
    firestore: {
      host: '127.0.0.1', port: 8085,
      rules: await readFile(new URL('./firestore.rules', import.meta.url), 'utf8'),
    },
  });
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'catalogue/stable'), { manifest: '{"schemaVersion":1,"latest":null}' });
    await setDoc(doc(db, 'private/example'), { value: 'must remain private' });
  });
});
after(async () => environment?.cleanup());

test('anonymous visitors can read only the stable public catalogue', async () => {
  const db = environment.unauthenticatedContext().firestore();
  await assertSucceeds(getDoc(doc(db, 'catalogue/stable')));
  await assertFails(getDoc(doc(db, 'catalogue/internal')));
  await assertFails(getDocs(collection(db, 'catalogue')));
  await assertFails(getDoc(doc(db, 'private/example')));
});

for (const signedIn of [false, true]) {
  test(`${signedIn ? 'authenticated' : 'anonymous'} clients cannot publish or modify any data`, async () => {
    const db = (signedIn ? environment.authenticatedContext('test-owner', { admin: true }) : environment.unauthenticatedContext()).firestore();
    await assertFails(setDoc(doc(db, 'catalogue/rogue'), { manifest: '{}' }));
    await assertFails(updateDoc(doc(db, 'catalogue/stable'), { manifest: '{}' }));
    await assertFails(deleteDoc(doc(db, 'catalogue/stable')));
    await assertFails(setDoc(doc(db, 'private/example'), { value: 'tampered' }));
    await assertFails(getDoc(doc(db, 'private/example')));
  });
}
