import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getRemoteConfig } from 'firebase-admin/remote-config';
import { validateSubmission, containsBannedVocabulary, isTooCloseToExistingSpot, COOLDOWN_SECONDS } from './contribution.js';

// Mirrors tools/content-cli/firestore-client.js's getCommunityContributionsEnabled
// (same "not equal to the string 'false'" fail-open check), re-implemented
// for the Cloud Functions Admin SDK context. This is the actual enforcement
// point for the kill-switch — the client UI hiding the submit button is
// only a UX nicety, not a security boundary.
async function isCommunityContributionsEnabled(): Promise<boolean> {
  const template = await getRemoteConfig().getTemplate();
  const defaultValue = template.parameters.communityContributionsEnabled?.defaultValue;
  const value = defaultValue && 'value' in defaultValue ? defaultValue.value : undefined;
  return value !== 'false';
}

export const submitContribution = onCall({ region: 'europe-west1', enforceAppCheck: true }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }
  const uid = request.auth.uid;

  if (!(await isCommunityContributionsEnabled())) {
    throw new HttpsError('failed-precondition', 'Community contributions are temporarily disabled.');
  }

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

  const profileData = profileSnapshot.data();
  const isShadowBanned = profileData?.isShadowBanned === true;

  // Cooldown (spec point 3): minute-order gap between two submissions, no
  // daily cap, no pending-submission limit — see this plan's Global
  // Constraints for why that's deliberate, not a gap to close later.
  const lastSubmissionAt = profileData?.lastSubmissionAt as FirebaseFirestore.Timestamp | undefined;
  if (lastSubmissionAt) {
    const secondsSinceLastSubmission = (Date.now() - lastSubmissionAt.toMillis()) / 1000;
    if (secondsSinceLastSubmission < COOLDOWN_SECONDS) {
      throw new HttpsError('resource-exhausted', `Please wait before submitting again (${Math.ceil(COOLDOWN_SECONDS - secondsSinceLastSubmission)}s).`);
    }
  }

  if (containsBannedVocabulary(input.title)) {
    throw new HttpsError('invalid-argument', 'Submission contains disallowed content.');
  }

  const nearbySnapshot = await db
    .collection('contributions')
    .where('status', '==', 'approved')
    .where('category', '==', input.category)
    .get();
  const nearbyPositions = nearbySnapshot.docs.map((doc) => doc.data().position as { x: number; y: number });
  if (isTooCloseToExistingSpot(input.position, nearbyPositions)) {
    throw new HttpsError('already-exists', 'A spot of this category already exists nearby.');
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
    shadowHidden: isShadowBanned,
    createdAt: FieldValue.serverTimestamp(),
  });

  await db.doc(`profiles/${uid}`).update({ lastSubmissionAt: FieldValue.serverTimestamp() });

  return { id: docRef.id };
});
