// functions/src/flagCommunityBundlesDirty.ts
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { getFirestore } from 'firebase-admin/firestore';
import { isDirtyingChange, MANIFEST_ID } from './communityBundles.js';

// Signatures vérifiées contre les typings résolus (firebase-functions v6,
// `lib/v2/providers/firestore.d.ts:66`) : `onDocumentWritten(opts, handler)`
// donne un `FirestoreEvent<Change<DocumentSnapshot> | undefined, …>`, donc
// `event.data` peut être absent et `before`/`after` peuvent exister sans
// contenir de document (création : `before.exists === false`).
//
// Ce déclencheur n'écrit QU'UN drapeau. Reconstruire ici serait tentant et
// faux : un burst d'approbations reconstruirait autant de fois qu'il y a
// d'approbations, alors que la reconstruction planifiée les absorbe toutes en
// une passe.
export const flagCommunityBundlesDirty = onDocumentWritten(
  { region: 'europe-west1', document: 'contributions/{contributionId}' },
  async (event) => {
    const before = event.data?.before.exists ? event.data.before.data() : undefined;
    const after = event.data?.after.exists ? event.data.after.data() : undefined;
    if (!before && !after) return;

    // Un vote ne change que les compteurs : il ne salit rien. C'est ce qui
    // évite de reconstruire en continu au pic, exactement quand ça coûterait
    // le plus cher.
    if (!isDirtyingChange(before, after)) return;

    await getFirestore()
      .doc(`content_bundles/${MANIFEST_ID}`)
      .set({ dirty: true }, { merge: true });
  }
);
