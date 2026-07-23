import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const MAX_REASON_LENGTH = 280;

// Apple 1.2 (UGC) requires the reporting mechanism to exist even before
// there's an active moderation queue reading `reports` — triage of this
// collection is Plan 5c's job, not this task's.
export const reportContribution = onCall({ region: 'europe-west1', enforceAppCheck: true }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }

  const spotId = request.data?.spotId;
  if (typeof spotId !== 'string' || spotId.length === 0) {
    throw new HttpsError('invalid-argument', 'spotId must be a non-empty string.');
  }
  const reason = request.data?.reason;
  if (reason !== undefined && (typeof reason !== 'string' || reason.length > MAX_REASON_LENGTH)) {
    throw new HttpsError('invalid-argument', `reason must be a string of at most ${MAX_REASON_LENGTH} characters.`);
  }

  const db = getFirestore();
  const contributionSnapshot = await db.doc(`contributions/${spotId}`).get();
  if (!contributionSnapshot.exists) {
    throw new HttpsError('not-found', 'Contribution not found.');
  }

  await db.collection('reports').add({
    contributionId: spotId,
    reporterUid: request.auth.uid,
    reason: reason ?? null,
    createdAt: FieldValue.serverTimestamp(),
  });

  return { reported: true };
});
