import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getFirestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';

// Scope note (Plan 5 infra): only the profile doc and the Auth user itself
// are deleted here. There are no contribution/vote documents yet — when
// that system exists, this function must be revisited to anonymize
// approved contributions instead of leaving them referencing a deleted uid
// (spec: "anonymisée, jamais effacée" for approved contributions).
export const deleteAccount = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }
  const uid = request.auth.uid;
  await getFirestore().doc(`profiles/${uid}`).delete();
  await getAuth().deleteUser(uid);
  return { deleted: true };
});
