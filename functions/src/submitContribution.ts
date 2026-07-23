import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { validateSubmission } from './contribution.js';

export const submitContribution = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }
  const uid = request.auth.uid;

  let input;
  try {
    input = validateSubmission(request.data);
  } catch (error) {
    throw new HttpsError('invalid-argument', error instanceof Error ? error.message : 'Invalid submission.');
  }

  const db = getFirestore();
  const profileSnapshot = await db.doc(`profiles/${uid}`).get();
  const authorHandle = profileSnapshot.data()?.handle;
  if (typeof authorHandle !== 'string') {
    // Should never happen: createUserProfile (Plan 5) writes the handle
    // synchronously... except it's an Auth onCreate trigger, so there's a
    // narrow window right after sign-up where the profile doc doesn't
    // exist yet. Surface a retryable error rather than writing a
    // contribution with no author handle.
    throw new HttpsError('failed-precondition', 'Profile not ready yet — try again shortly.');
  }

  const docRef = await db.collection('contributions').add({
    authorUid: uid,
    authorHandle,
    category: input.category,
    title: input.title,
    languageCode: input.languageCode,
    position: input.position,
    status: 'pending',
    upvotes: 0,
    downvotes: 0,
    createdAt: FieldValue.serverTimestamp(),
  });

  return { id: docRef.id };
});
