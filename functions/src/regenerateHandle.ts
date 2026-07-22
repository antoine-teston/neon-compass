import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getFirestore } from 'firebase-admin/firestore';
import { generateHandle } from './handle.js';

export const regenerateHandle = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }
  const newHandle = generateHandle();
  await getFirestore().doc(`profiles/${request.auth.uid}`).update({ handle: newHandle });
  return { handle: newHandle };
});
