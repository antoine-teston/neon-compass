// Neon Compass Cloud Functions — account lifecycle (Plan 5) plus
// community contributions and voting (Plan 5b). Moderation triage of the
// `reports` collection is Plan 5c, not here.
//
// Deviation from brief (discovered during Task 3's emulator smoke test):
// no file in this codebase called initializeApp() — every Admin SDK call
// (getFirestore()/getAuth()) in createUserProfile, regenerateHandle and
// deleteAccount failed at runtime with "The default Firebase app does not
// exist." This is a gap from the Task 1/2 scaffolding, not something the
// Task 3 brief mentioned. index.ts is the shared entry point for all three
// functions and the one file here we're allowed to edit, so the fix lives
// here rather than in createUserProfile.ts (out of scope for this task).
import { initializeApp } from 'firebase-admin/app';
initializeApp();

export { createUserProfile } from './createUserProfile.js';
export { regenerateHandle } from './regenerateHandle.js';
export { deleteAccount } from './deleteAccount.js';
export { submitContribution } from './submitContribution.js';
export { castVote } from './castVote.js';
export { reportContribution } from './reportContribution.js';
export { flagSuspiciousContribution } from './flagSuspiciousContribution.js';
export { appStoreServerNotification } from './appStoreServerNotification.js';
export { notifyFollowedCategory } from './notifyFollowedCategory.js';
export { flagCommunityBundlesDirty } from './flagCommunityBundlesDirty.js';
export { rebuildCommunityBundles } from './rebuildCommunityBundles.js';
export { rebuildLeaderboard } from './rebuildLeaderboard.js';
