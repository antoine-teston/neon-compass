// functions/src/rebuildCommunityBundles.ts
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { getFirestore } from 'firebase-admin/firestore';
import {
  BUNDLE_COLLECTION,
  MANIFEST_ID,
  bundleItem,
  chunked,
  isPubliclyVisible,
  shouldRebuild,
  type Manifest,
} from './communityBundles.js';

// Signature vérifiée contre les typings résolus (firebase-functions v6,
// `lib/v2/providers/scheduler.d.ts:65`) : `onSchedule(options, handler)`.
//
// Toutes les cinq minutes, mais le cas nominal coûte UNE lecture : on lit le
// manifeste et on s'arrête si rien n'est sale et si la dernière construction a
// moins d'une heure. La lecture complète de `contributions` n'a lieu que quand
// il y a réellement quelque chose à reconstruire.
export const rebuildCommunityBundles = onSchedule(
  { region: 'europe-west1', schedule: 'every 5 minutes' },
  async () => {
    const db = getFirestore();
    const manifestRef = db.doc(`content_bundles/${MANIFEST_ID}`);
    const manifestSnapshot = await manifestRef.get();
    const manifest = manifestSnapshot.exists ? (manifestSnapshot.data() as Manifest) : undefined;

    if (!shouldRebuild(manifest, Date.now())) return;

    // `status == 'approved'` côté requête (Firestore filtre, on ne paie pas les
    // autres), `shadowHidden` côté application : le client ne lit plus
    // `contributions`, donc la Security Rule qui portait ce filtre ne protège
    // plus rien sur ce chemin. Un test fige ce comportement.
    const snapshot = await db.collection('contributions').where('status', '==', 'approved').get();
    const items = snapshot.docs
      .filter((doc) => isPubliclyVisible(doc.data()))
      .map((doc) => bundleItem(doc.id, doc.data()));

    const chunks = chunked(items);
    const bundles = db.collection('content_bundles');
    const batch = db.batch();

    chunks.forEach((chunkItems, chunk) => {
      batch.set(bundles.doc(`${BUNDLE_COLLECTION}_${chunk}`), {
        collection: BUNDLE_COLLECTION,
        chunk,
        items: chunkItems,
      });
    });

    // Une reconstruction plus étroite que la précédente laisserait sinon
    // derrière elle les fragments de la précédente, plus large — que les
    // clients liraient comme des spots encore vivants. Même raisonnement que
    // `pushBundles` côté CLI.
    const stale = await bundles.where('collection', '==', BUNDLE_COLLECTION).get();
    stale.docs
      .filter((doc) => (doc.get('chunk') as number) >= chunks.length)
      .forEach((doc) => batch.delete(doc.ref));

    // La version est ce que le client compare : elle doit monter à CHAQUE
    // reconstruction, y compris celle du rafraîchissement horaire, sinon les
    // compteurs de votes rafraîchis côté serveur ne descendraient jamais chez
    // les clients.
    batch.set(manifestRef, {
      collection: BUNDLE_COLLECTION,
      version: (manifest?.version ?? 0) + 1,
      chunks: chunks.length,
      dirty: false,
      builtAtMs: Date.now(),
    });

    await batch.commit();
  }
);
