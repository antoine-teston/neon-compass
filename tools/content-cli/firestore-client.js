// Pont vers Firestore via firebase-admin — n'est importé que par la commande
// `publish` (jamais par validate/check-publishable/translate, qui restent
// utilisables sans credentials). La clé de compte de service est lue depuis
// la variable d'environnement FIREBASE_SERVICE_ACCOUNT_PATH, jamais committée.

import { readFileSync } from 'node:fs';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getRemoteConfig } from 'firebase-admin/remote-config';

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
