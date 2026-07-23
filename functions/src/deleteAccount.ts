import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getFirestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';

const ANONYMIZED_HANDLE = 'DELETED-AUTHOR';

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

  const batch = db.batch();
  for (const doc of ownedContributions.docs) {
    if (doc.data().status === 'approved') {
      batch.update(doc.ref, { authorUid: null, authorHandle: ANONYMIZED_HANDLE });
    } else {
      batch.delete(doc.ref);
    }
  }
  for (const doc of ownedVotes.docs) {
    batch.delete(doc.ref);
  }
  await batch.commit();

  await db.doc(`profiles/${uid}`).delete();
  await getAuth().deleteUser(uid);
  return { deleted: true };
});
