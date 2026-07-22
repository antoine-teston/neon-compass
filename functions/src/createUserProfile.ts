import { user } from 'firebase-functions/v1/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { generateHandle } from './handle.js';

// Runs once per new Firebase Auth user (Sign in with Apple, in this app's
// case — no other provider is offered). Writes the initial profile doc;
// xp/level/isPremium are reserved fields for future plans (contribution
// system, StoreKit) and are never touched by anything else in this plan.
//
// Deviation from brief: `firebase-functions/v1/auth` (v6 SDK, per
// functions/package.json) has no standalone `onCreate` export — the
// background trigger is built via `user().onCreate(handler)` on the
// UserBuilder returned by `user()`. Same trigger semantics (background
// onCreate, not a blocking beforeCreate) as specified in the brief.
export const createUserProfile = user().onCreate(async (authUser) => {
  const db = getFirestore();
  await db.doc(`profiles/${authUser.uid}`).set({
    handle: generateHandle(),
    xp: 0,
    level: 0,
    isPremium: false,
    createdAt: FieldValue.serverTimestamp(),
  });
});
