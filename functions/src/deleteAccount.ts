import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getFirestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';

const ANONYMIZED_HANDLE = 'DELETED-AUTHOR';

// Firestore caps a single batch at 500 write operations. An active user's
// vote count alone can exceed that (Plan 5b intentionally ships without
// submission cooldowns or caps — see Plan 5c). Chunk writes across as many
// batches as needed so account deletion never silently fails once a user's
// contributions+votes cross the limit.
async function commitInChunks(
  db: FirebaseFirestore.Firestore,
  ops: Array<(batch: FirebaseFirestore.WriteBatch) => void>
): Promise<void> {
  const CHUNK_SIZE = 500;
  for (let i = 0; i < ops.length; i += CHUNK_SIZE) {
    const batch = db.batch();
    for (const op of ops.slice(i, i + CHUNK_SIZE)) {
      op(batch);
    }
    await batch.commit();
  }
}

// Plan 5b cascade (was a known gap flagged in Plan 5's self-review):
// - approved contributions are ANONYMIZED, never deleted (spec: the
//   community map data is preserved, only the identifying author fields
//   are stripped — this is what takes the record out of GDPR scope
//   without losing the map content).
// - pending/rejected contributions were never shown publicly, so they're
//   deleted outright rather than anonymized (nothing worth preserving).
// - all vote documents by this uid are deleted (spec: "profil et votes
//   effacés"). Aggregate upvote/downvote counts on other users' spots are
//   intentionally left as-is — they reflect real community sentiment and
//   the spec doesn't ask for them to be unwound.
export const deleteAccount = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }
  const uid = request.auth.uid;
  const db = getFirestore();

  const [ownedContributions, ownedVotes] = await Promise.all([
    db.collection('contributions').where('authorUid', '==', uid).get(),
    db.collection('votes').where('uid', '==', uid).get(),
  ]);

  const ops: Array<(batch: FirebaseFirestore.WriteBatch) => void> = [];
  for (const doc of ownedContributions.docs) {
    if (doc.data().status === 'approved') {
      ops.push((batch) => batch.update(doc.ref, { authorUid: null, authorHandle: ANONYMIZED_HANDLE }));
    } else {
      ops.push((batch) => batch.delete(doc.ref));
    }
  }
  for (const doc of ownedVotes.docs) {
    ops.push((batch) => batch.delete(doc.ref));
  }
  await commitInChunks(db, ops);

  await db.doc(`profiles/${uid}`).delete();
  await getAuth().deleteUser(uid);
  return { deleted: true };
});
