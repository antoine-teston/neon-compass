// Webhook App Store Server Notifications V2 — portage de
// functions/src/appStoreServerNotification.ts.
//
// **Miroir de badge, au mieux. Jamais une autorisation.** Le droit Pro est
// vérifié sur l'appareil par StoreKit et nulle part ailleurs. Si cette fonction
// est en panne, mal configurée, ou si aucun profil ne porte le jeton de la
// transaction, le pire résultat est un badge `isPremium` périmé ou absent sur
// l'écran Profil — jamais une fonctionnalité cassée.
//
// **`verify_jwt = false` est indispensable ici**, et c'est la seule fonction du
// projet dans ce cas : Apple appelle cette URL sans jeton Supabase. Ce qui
// remplace cette vérification, c'est la signature JWS d'Apple, vérifiée
// ci-dessous contre sa chaîne de certificats AVANT que quoi que ce soit du
// contenu ne soit lu. Ne jamais analyser un JWT non vérifié.
//
// Secrets attendus :
//   APP_STORE_ENVIRONMENT (`sandbox` en TestFlight, sinon production)
//   APP_BUNDLE_ID, APP_STORE_APPLE_ID (ce dernier requis en production)

import { Environment, SignedDataVerifier } from 'npm:@apple/app-store-server-library@3';
// La bibliothèque est écrite pour Node et attend des `Buffer`, pas des
// `Uint8Array`. Deno fournit le module, donc la conversion est une ligne
// plutôt qu'une reécriture de la vérification de signature.
import { Buffer } from 'node:buffer';
import { adminClient } from '../_shared/auth.ts';
import { APPLE_ROOT_CA_G3_BASE64 } from './apple-root-ca.ts';

// Les notifications du bac à sable d'Apple — celles de TestFlight — doivent
// être vérifiées contre `SANDBOX`, sinon même une charge authentiquement signée
// échoue à la vérification.
const APP_STORE_ENVIRONMENT = Deno.env.get('APP_STORE_ENVIRONMENT') === 'sandbox'
  ? Environment.SANDBOX
  : Environment.PRODUCTION;

const BUNDLE_ID = Deno.env.get('APP_BUNDLE_ID') ?? 'co.antoineteston.NeonCompass';
const APP_APPLE_ID = Deno.env.get('APP_STORE_APPLE_ID')
  ? Number(Deno.env.get('APP_STORE_APPLE_ID'))
  : undefined;

// Pro est un achat unique non consommable, pas un abonnement (spec : « Pro
// one-shot 5,99 € »). `subtype` n'est donc jamais renseigné, et le signal
// correct est `notificationType`. Tous les autres types — TEST,
// CONSUMPTION_REQUEST, ceux propres aux abonnements — ne concernent pas ce
// produit et sont acquittés sans rien faire.
const GRANT_TYPES = new Set(['ONE_TIME_CHARGE']);
const REVOKE_TYPES = new Set(['REFUND', 'REVOKE']);

let cachedVerifier: SignedDataVerifier | undefined;

function verifier(): SignedDataVerifier {
  if (cachedVerifier) return cachedVerifier;
  // Le certificat vient d'un module, pas d'un fichier voisin : le déploiement
  // n'empaquette que ce qui est atteint par un import. Voir apple-root-ca.ts.
  const certificate = Buffer.from(APPLE_ROOT_CA_G3_BASE64, 'base64');
  // Contrôles en ligne activés : révocation et expiration vérifiées contre
  // l'heure courante, en défense supplémentaire contre un certificat
  // intermédiaire compromis ou expiré.
  cachedVerifier = new SignedDataVerifier(
    [certificate],
    true,
    APP_STORE_ENVIRONMENT,
    BUNDLE_ID,
    APP_APPLE_ID,
  );
  return cachedVerifier;
}

Deno.serve(async (request) => {
  const body = await request.json().catch(() => null);
  const signedPayload = body?.signedPayload;
  if (typeof signedPayload !== 'string') return new Response('missing signedPayload', { status: 400 });

  const check = verifier();

  let notification;
  try {
    notification = await check.verifyAndDecodeNotification(signedPayload);
  } catch (error) {
    console.warn('signature de notification invalide', error);
    return new Response('invalid signature', { status: 400 });
  }

  const type = notification.notificationType;
  const isGrant = typeof type === 'string' && GRANT_TYPES.has(type);
  const isRevoke = typeof type === 'string' && REVOKE_TYPES.has(type);
  // Acquitter même ce qui ne nous concerne pas : sans 200, Apple réessaie.
  if (!isGrant && !isRevoke) return new Response('notification type not relevant, ignored');

  // `signedTransactionInfo` est lui-même un JWS signé, pas un objet déjà
  // décodé : lire un champ dessus sans le vérifier séparément rendrait
  // toujours `undefined`. C'est le piège que le portage d'origine avait déjà
  // documenté, et il se reproduit à l'identique ici.
  const signedTransactionInfo = notification.data?.signedTransactionInfo;
  if (typeof signedTransactionInfo !== 'string') {
    console.warn('notification sans signedTransactionInfo', { type });
    return new Response('no transaction info, ignored');
  }

  let appAccountToken: string | undefined;
  try {
    appAccountToken = (await check.verifyAndDecodeTransaction(signedTransactionInfo)).appAccountToken;
  } catch (error) {
    console.warn('signature de transaction invalide', error);
    return new Response('invalid transaction signature', { status: 400 });
  }

  if (!appAccountToken) {
    // Achat fait sans être connecté. Ce n'est pas une erreur mais le cas
    // NORMAL : la spec pose que « l'achat ne requiert jamais de connexion ».
    // Il n'y a simplement aucun profil à mettre à jour.
    return new Response('no account token, ignored');
  }

  const { error } = await adminClient()
    .from('profiles')
    .update({ is_premium: isGrant })
    .eq('app_account_token', appAccountToken);
  if (error) {
    console.error('mise à jour du badge impossible', error);
    // 500 pour qu'Apple réessaie : c'est une panne de notre côté, pas une
    // notification invalide.
    return new Response('update failed', { status: 500 });
  }

  return new Response('ok');
});
