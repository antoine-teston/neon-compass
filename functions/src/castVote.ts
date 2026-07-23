import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { applyVoteDelta, VoteDirection } from './vote.js';
import { awardXP, XP_PER_UPVOTE_RECEIVED } from './xp.js';

export const castVote = onCall({ region: 'europe-west1', enforceAppCheck: true }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }
  const uid = request.auth.uid;

  const spotId = request.data?.spotId;
  const direction = request.data?.direction;
  if (typeof spotId !== 'string' || spotId.length === 0) {
    throw new HttpsError('invalid-argument', 'spotId must be a non-empty string.');
  }
  if (direction !== 'up' && direction !== 'down') {
    throw new HttpsError('invalid-argument', "direction must be 'up' or 'down'.");
  }

  const db = getFirestore();
  const contributionRef = db.doc(`contributions/${spotId}`);
  const voteRef = db.doc(`votes/${spotId}_${uid}`);

  const result = await db.runTransaction(async (transaction) => {
    const [contributionSnapshot, voteSnapshot] = await Promise.all([
      transaction.get(contributionRef),
      transaction.get(voteRef),
    ]);
    if (!contributionSnapshot.exists) {
      throw new HttpsError('not-found', 'Contribution not found.');
    }

    const previousDirection = (voteSnapshot.data()?.direction as VoteDirection | undefined) ?? null;
    const delta = applyVoteDelta(previousDirection, direction as VoteDirection);

    const currentUpvotes = (contributionSnapshot.data()?.upvotes as number | undefined) ?? 0;
    const currentDownvotes = (contributionSnapshot.data()?.downvotes as number | undefined) ?? 0;
    const upvotes = currentUpvotes + delta.upvoteDelta;
    const downvotes = currentDownvotes + delta.downvoteDelta;

    transaction.set(voteRef, { spotId, uid, direction, updatedAt: FieldValue.serverTimestamp() });
    transaction.update(contributionRef, { upvotes, downvotes });

    const authorUid = contributionSnapshot.data()?.authorUid as string | undefined;

    return { upvotes, downvotes, authorUid, delta, previousDirection };
  });

  const { upvotes, downvotes, authorUid, previousDirection } = result;

  // Award XP only on a genuine first-ever upvote for this (spot, voter)
  // pair — never on a down→up re-toggle (that's the same delta.upvoteDelta
  // as a first upvote, which would let a voter farm unlimited XP for the
  // author by looping down/up), and never when the voter is the author
  // (no self-farming).
  const isGenuineFirstUpvote = previousDirection === null && direction === 'up';
  if (isGenuineFirstUpvote && authorUid && authorUid !== uid) {
    await awardXP(db, authorUid, XP_PER_UPVOTE_RECEIVED);
  }

  return { upvotes, downvotes };
});
