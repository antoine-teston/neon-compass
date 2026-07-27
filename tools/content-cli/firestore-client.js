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

// Un batch Firestore est plafonné à 500 opérations. La fixture GTA V en compte
// 537 : sans découpage, un `publish` échouerait d'un bloc.
const BATCH_LIMIT = 500;

// Doit rester aligné sur `ContentBundle.chunkSize` côté Swift : l'app trie les
// fragments par `chunk` et concatène, elle ne devine pas leur taille.
const BUNDLE_CHUNK_SIZE = 500;

function chunked(items, size) {
  const chunks = [];
  for (let i = 0; i < items.length; i += size) chunks.push(items.slice(i, i + size));
  return chunks;
}

async function commitAll(db, operations) {
  for (const group of chunked(operations, BATCH_LIMIT)) {
    const batch = db.batch();
    for (const apply of group) apply(batch);
    await batch.commit();
  }
}

export async function pushDocuments(collectionName, documents) {
  const db = getFirestore(app());
  await commitAll(
    db,
    documents.map((doc) => (batch) => batch.set(db.collection(collectionName).doc(doc.id), doc)),
  );
}

/**
 * Écrit la collection sous forme d'agrégats dans `content_bundles`, ce que
 * l'app lit réellement.
 *
 * Firestore facture UNE LECTURE PAR DOCUMENT : lire les POI un par un coûtait
 * autant de lectures qu'il y a d'entrées, à chaque bump de `contentVersion`,
 * fois le nombre de clients. En agrégats de 500, un client lit ⌈N/500⌉
 * documents — trois au lieu de mille cinq cents.
 *
 * Le découpage n'est pas cosmétique : un document Firestore est plafonné à
 * 1 MiB, atteignable vers 1 300 entrées à cinq langues remplies.
 */
export async function pushBundles(collectionName, documents) {
  const db = getFirestore(app());
  const bundles = db.collection('content_bundles');
  const chunks = chunked(documents, BUNDLE_CHUNK_SIZE);

  const operations = chunks.map((items, chunk) => (batch) =>
    batch.set(bundles.doc(`${collectionName}_${chunk}`), { collection: collectionName, chunk, items }));

  // Une publication plus étroite que la précédente laisserait sinon derrière
  // elle les fragments de la précédente, plus large — que les clients liraient
  // comme du contenu encore vivant.
  const existing = await bundles.where('collection', '==', collectionName).get();
  const stale = existing.docs.filter((doc) => doc.get('chunk') >= chunks.length);
  for (const doc of stale) operations.push((batch) => batch.delete(doc.ref));

  await commitAll(db, operations);
  return { chunks: chunks.length, pruned: stale.length };
}

export async function incrementContentVersion(commit) {
  const rc = getRemoteConfig(app());
  const template = await rc.getTemplate();
  const current = Number(template.parameters.contentVersion?.defaultValue?.value ?? '0');
  template.parameters.contentVersion = {
    defaultValue: { value: String(current + 1) },
  };
  // Le SHA du commit publié, à côté de la version. Sans lui, « quel contenu est
  // en ligne ? » ne se répond qu'en comparant des documents à la main.
  if (commit) {
    template.parameters.contentCommit = {
      defaultValue: { value: commit },
      description: 'Commit git dont le contenu est actuellement publié (écrit par content-cli).',
    };
  }
  await rc.publishTemplate(template);
  return current + 1;
}

/** Source du ruleset Firestore actuellement RELEASED sur le projet live.
 *
 *  Sert à regarder la cible avant de l'écraser : `deploy-rules` remplace le
 *  ruleset actif d'un bloc, donc une modification faite directement en console
 *  Firebase disparaîtrait sans laisser de trace. */
/// Lit et écrit un paramètre Remote Config sans toucher aux autres.
///
/// `publishTemplate` remplace le template **entier** : lire, modifier, republier
/// est le seul chemin sûr. Une écriture naïve effacerait `contentVersion`,
/// `contentCommit` et le coupe-circuit communautaire d'un bloc.
export async function getRemoteConfigParameter(key) {
  const rc = getRemoteConfig(app());
  const template = await rc.getTemplate();
  return template.parameters[key]?.defaultValue?.value;
}

export async function setRemoteConfigParameter(key, value, description) {
  const rc = getRemoteConfig(app());
  const template = await rc.getTemplate();
  template.parameters[key] = {
    defaultValue: { value: String(value) },
    ...(description ? { description } : {}),
  };
  await rc.publishTemplate(template);
  return value;
}

export async function fetchFirestoreRules() {
  const ruleset = await getSecurityRules(app()).getFirestoreRuleset();
  return ruleset.source.map((file) => file.content).join('\n');
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

/// Brouillons du mode éditeur pas encore matérialisés en fichiers.
///
/// `appliedAt` absent plutôt qu'un booléen : la date sert aussi de trace de
/// quand le dépôt les a absorbés. Le filtrage se fait en mémoire — la collection
/// se compte en dizaines d'entrées entre deux `pull-drafts`, un index Firestore
/// pour ça serait du cérémonial.
export async function listEditorDrafts() {
  const db = getFirestore(app());
  const snapshot = await db.collection('editor_drafts').get();
  return snapshot.docs
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .filter((draft) => !draft.appliedAt)
    .sort((a, b) => (a.capturedAt?.toMillis?.() ?? 0) - (b.capturedAt?.toMillis?.() ?? 0));
}

export async function markEditorDraftsApplied(ids) {
  if (!ids.length) return;
  const db = getFirestore(app());
  const batch = db.batch();
  ids.forEach((id) => batch.update(db.collection('editor_drafts').doc(id), { appliedAt: new Date() }));
  await batch.commit();
}

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
