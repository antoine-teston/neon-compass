// functions/src/xp.ts
// Pure XP→level mapping — original synthwave-themed grade names, never a
// GTA/Rockstar rank (spec §"Profil & leveling"). Extend the two arrays
// together by hand if more levels are added; they must stay the same length.
export const LEVEL_THRESHOLDS = [0, 50, 150, 400, 900, 2000];
export const GRADE_NAMES = ['SIGNAL', 'PULSE', 'DRIFT', 'CIRCUIT', 'OVERDRIVE', 'SYNTHWAVE ICON'];

export function levelForXP(xp: number): number {
  let level = 0;
  for (let i = 0; i < LEVEL_THRESHOLDS.length; i++) {
    if (xp >= LEVEL_THRESHOLDS[i]) {
      level = i;
    }
  }
  return level;
}

export const XP_PER_APPROVED_CONTRIBUTION = 20;
export const XP_PER_UPVOTE_RECEIVED = 2;

// Applies an XP delta to a profile and recomputes its level in the same
// transaction — the only place in this codebase that mutates
// profiles/{uid}.xp or .level (spec: level is server-computed, never by the
// client, on both approval and votes-received).
export async function awardXP(
  db: FirebaseFirestore.Firestore,
  uid: string,
  amount: number
): Promise<void> {
  const profileRef = db.doc(`profiles/${uid}`);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(profileRef);
    const currentXP = (snapshot.data()?.xp as number | undefined) ?? 0;
    const newXP = currentXP + amount;
    transaction.update(profileRef, { xp: newXP, level: levelForXP(newXP) });
  });
}
