// Pont vers Firestore via firebase-admin — n'est importé que par la commande
// `publish` (jamais par validate/check-publishable/translate, qui restent
// utilisables sans credentials). La clé de compte de service est lue depuis
// la variable d'environnement FIREBASE_SERVICE_ACCOUNT_PATH, jamais committée.

import { readFileSync } from 'node:fs';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getRemoteConfig } from 'firebase-admin/remote-config';
import { getSecurityRules } from 'firebase-admin/security-rules';

let appInstance = null;

function app() {
  if (appInstance) return appInstance;
  const keyPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
  if (!keyPath) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT_PATH env var not set — cannot publish without credentials');
  }
  const serviceAccount = JSON.parse(readFileSync(keyPath, 'utf8'));
  appInstance = initializeApp({ credential: cert(serviceAccount) });
  return appInstance;
}

export async function pushDocuments(collectionName, documents) {
  const db = getFirestore(app());
  const batch = db.batch();
  for (const doc of documents) {
    batch.set(db.collection(collectionName).doc(doc.id), doc);
  }
  await batch.commit();
}

export async function incrementContentVersion() {
  const rc = getRemoteConfig(app());
  const template = await rc.getTemplate();
  const current = Number(template.parameters.contentVersion?.defaultValue?.value ?? '0');
  template.parameters.contentVersion = {
    defaultValue: { value: String(current + 1) },
  };
  await rc.publishTemplate(template);
  return current + 1;
}

// Déploie firestore.rules (à la racine du repo) comme le ruleset actif de
// Cloud Firestore sur le projet live. Un seul appel crée le Ruleset et
// l'applique (pas de release séparée nécessaire).
export async function deployFirestoreRules(rulesSource) {
  const securityRules = getSecurityRules(app());
  await securityRules.releaseFirestoreRulesetFromSource(rulesSource);
}

// Mirrors functions/src/xp.ts's levelForXP — duplicated intentionally (see
// Task 4's Interfaces note: this CLI is a separate package, not built
// alongside functions/).
const LEVEL_THRESHOLDS = [0, 50, 150, 400, 900, 2000];
function levelForXP(xp) {
  let level = 0;
  for (let i = 0; i < LEVEL_THRESHOLDS.length; i++) {
    if (xp >= LEVEL_THRESHOLDS[i]) level = i;
  }
  return level;
}
const XP_PER_APPROVED_CONTRIBUTION = 20;

export async function listPendingContributions() {
  const db = getFirestore(app());
  const snapshot = await db.collection('contributions').where('status', '==', 'pending').get();
  // Flagged-for-review first (velocity monitoring's priority-review signal,
  // spec point 5), then oldest first within each group.
  return snapshot.docs
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .sort((a, b) => {
      if (Boolean(a.flaggedForReview) !== Boolean(b.flaggedForReview)) {
        return a.flaggedForReview ? -1 : 1;
      }
      return (a.createdAt?.toMillis() ?? 0) - (b.createdAt?.toMillis() ?? 0);
    });
}

export async function approveContribution(contributionId) {
  const db = getFirestore(app());
  const contributionRef = db.collection('contributions').doc(contributionId);
  const snapshot = await contributionRef.get();
  if (!snapshot.exists) throw new Error(`contribution ${contributionId} not found`);
  const authorUid = snapshot.data().authorUid;

  await contributionRef.update({ status: 'approved' });

  if (authorUid) {
    const profileRef = db.doc(`profiles/${authorUid}`);
    await db.runTransaction(async (transaction) => {
      const profileSnapshot = await transaction.get(profileRef);
      const currentXP = profileSnapshot.data()?.xp ?? 0;
      const newXP = currentXP + XP_PER_APPROVED_CONTRIBUTION;
      transaction.update(profileRef, { xp: newXP, level: levelForXP(newXP) });
    });
  }
}

export async function rejectContribution(contributionId) {
  const db = getFirestore(app());
  await db.collection('contributions').doc(contributionId).update({ status: 'rejected' });
}

export async function shadowBanUser(uid) {
  const db = getFirestore(app());
  await db.doc(`profiles/${uid}`).update({ isShadowBanned: true });
  const ownContributions = await db.collection('contributions').where('authorUid', '==', uid).get();
  const batch = db.batch();
  ownContributions.docs.forEach((doc) => batch.update(doc.ref, { shadowHidden: true }));
  await batch.commit();
}

export async function liftShadowBan(uid) {
  const db = getFirestore(app());
  await db.doc(`profiles/${uid}`).update({ isShadowBanned: false });
  const ownContributions = await db.collection('contributions').where('authorUid', '==', uid).get();
  const batch = db.batch();
  ownContributions.docs.forEach((doc) => batch.update(doc.ref, { shadowHidden: false }));
  await batch.commit();
}

export async function getCommunityContributionsEnabled() {
  const rc = getRemoteConfig(app());
  const template = await rc.getTemplate();
  return template.parameters.communityContributionsEnabled?.defaultValue?.value !== 'false';
}

export async function setCommunityContributionsEnabled(enabled) {
  const rc = getRemoteConfig(app());
  const template = await rc.getTemplate();
  template.parameters.communityContributionsEnabled = {
    defaultValue: { value: enabled ? 'true' : 'false' },
  };
  await rc.publishTemplate(template);
}
