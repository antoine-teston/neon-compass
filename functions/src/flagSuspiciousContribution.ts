// functions/src/flagSuspiciousContribution.ts
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

const VELOCITY_WINDOW_SECONDS = 300; // 5 minutes
const VELOCITY_THRESHOLD = 5; // more than this many submissions by the same author in the window is suspicious

// Never auto-rejects or auto-blocks (spec point 5: "jamais un blocage
// automatique d'utilisateur légitime") — only marks the document for
// priority human review and, on a repeated pattern, shadow-bans the author.
// A shadow-ban does not delete or hide the author's OWN view of their
// content (still readable via fetchMine) — it only removes future/existing
// approved spots from the public fetchApproved() query (see firestore.rules
// and Task 4's approve-command note in this same plan).
export const flagSuspiciousContribution = onDocumentCreated(
  { region: 'europe-west1', document: 'contributions/{contributionId}' },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    const data = snapshot.data();
    const authorUid = data.authorUid as string | null;
    if (!authorUid) return;

    const db = getFirestore();
    const windowStart = Timestamp.fromMillis(Date.now() - VELOCITY_WINDOW_SECONDS * 1000);
    const recentSnapshot = await db
      .collection('contributions')
      .where('authorUid', '==', authorUid)
      .where('createdAt', '>=', windowStart)
      .get();

    if (recentSnapshot.size <= VELOCITY_THRESHOLD) return;

    await snapshot.ref.update({ flaggedForReview: true });

    // Repeated bursts (this isn't the author's first flagged burst) escalate
    // to a shadow-ban rather than re-flagging forever — the moderation CLI
    // (Task 4) also allows a human to shadow-ban/lift manually at any time.
    const profileRef = db.doc(`profiles/${authorUid}`);
    const profileSnapshot = await profileRef.get();
    const alreadyFlaggedCount = (profileSnapshot.data()?.flaggedBurstCount as number | undefined) ?? 0;
    if (alreadyFlaggedCount >= 1) {
      await profileRef.update({ isShadowBanned: true, flaggedBurstCount: alreadyFlaggedCount + 1 });
      // Retroactively hide this author's already-approved spots too — a
      // shadow-ban that only affects future submissions would leave every
      // previously-approved spot publicly visible, contradicting this
      // function's own guarantee (see the file-level comment above).
      // Mirrors tools/content-cli/firestore-client.js's shadowBanUser.
      const ownContributions = await db.collection('contributions').where('authorUid', '==', authorUid).get();
      const batch = db.batch();
      ownContributions.docs.forEach((doc) => batch.update(doc.ref, { shadowHidden: true }));
      await batch.commit();
    } else {
      await profileRef.update({ flaggedBurstCount: alreadyFlaggedCount + 1 });
    }
  }
);
