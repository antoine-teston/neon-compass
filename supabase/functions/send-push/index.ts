// Envoi des notifications de catégorie suivie, en APNs DIRECT.
//
// Remplace notifyFollowedCategory.ts et FCM d'un seul coup. Ce que FCM apportait
// — les topics — est devenu une requête SQL sur `push_tokens.categories` ; ce
// qu'il coûtait — un second tableau de bord, un second jeu de credentials, une
// clé APNs téléversée dans une console tierce — disparaît. La clé `.p8` vit dans
// un secret Supabase.
//
// **Vidange d'une file, pas un appel depuis un trigger.** Le trigger
// `contributions_enqueue_push` dépose une ligne dans `push_outbox` ; cette
// fonction la consomme. Un envoi raté est rejoué, une transaction d'écriture ne
// dépend pas de la disponibilité d'APNs, et aucun secret ne vit dans du SQL.
//
// Secrets attendus (supabase secrets set) :
//   APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID, APNS_PRIVATE_KEY (PEM PKCS#8),
//   APNS_HOST (api.push.apple.com, ou api.sandbox.push.apple.com en dev)

import { adminClient, serveJSON } from '../_shared/auth.ts';

const MAX_ATTEMPTS = 5;

function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/** Jeton de fournisseur APNs : un JWT ES256 signé avec la clé `.p8`.
 *
 *  Apple accepte un même jeton pendant une heure et refuse qu'on en génère plus
 *  d'un par vingt minutes. Il est donc calculé une fois par vidange, jamais par
 *  message. */
async function providerToken(): Promise<string> {
  const keyId = Deno.env.get('APNS_KEY_ID')!;
  const teamId = Deno.env.get('APNS_TEAM_ID')!;
  const pem = Deno.env.get('APNS_PRIVATE_KEY')!;

  const der = Uint8Array.from(
    atob(pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, '').replace(/\s+/g, '')),
    (c) => c.charCodeAt(0),
  );
  const key = await crypto.subtle.importKey(
    'pkcs8',
    der,
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  );

  const header = base64url(new TextEncoder().encode(JSON.stringify({ alg: 'ES256', kid: keyId })));
  const claims = base64url(
    new TextEncoder().encode(JSON.stringify({ iss: teamId, iat: Math.floor(Date.now() / 1000) })),
  );
  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  return `${header}.${claims}.${base64url(new Uint8Array(signature))}`;
}

serveJSON(async () => {
  const admin = adminClient();

  const { data: pending, error } = await admin
    .from('push_outbox')
    .select('id,category,title,attempts')
    .is('sent_at', null)
    .lt('attempts', MAX_ATTEMPTS)
    .order('created_at', { ascending: true })
    .limit(100);
  if (error) throw error;
  if (!pending?.length) return { sent: 0, recipients: 0 };

  const token = await providerToken();
  const host = Deno.env.get('APNS_HOST') ?? 'api.push.apple.com';
  const bundleId = Deno.env.get('APNS_BUNDLE_ID')!;

  let sent = 0;
  let recipients = 0;

  for (const message of pending) {
    // « Qui suit cette catégorie » : un opérateur de tableau, là où FCM
    // demandait de maintenir un topic par catégorie.
    const { data: targets, error: targetsError } = await admin
      .from('push_tokens')
      .select('token')
      .contains('categories', [message.category]);
    if (targetsError) throw targetsError;

    // Le texte n'est PAS localisé, et c'est une limite assumée, héritée telle
    // quelle de la Function d'origine : une charge APNs porte des chaînes
    // décidées serveur, pas des clés de String Catalog. Localiser demanderait
    // soit la langue de chaque destinataire en base, soit `loc-key`/`loc-args`
    // et donc des clés figées côté app. À traiter à part, pas à moitié ici.
    const payload = JSON.stringify({
      aps: { alert: { title: 'New spot in a category you follow', body: message.title }, sound: 'default' },
    });

    let delivered = 0;
    for (const target of targets ?? []) {
      const response = await fetch(`https://${host}/3/device/${target.token}`, {
        method: 'POST',
        headers: {
          authorization: `bearer ${token}`,
          'apns-topic': bundleId,
          'apns-push-type': 'alert',
        },
        body: payload,
      });

      if (response.ok) {
        delivered++;
        continue;
      }

      // 410 = l'appareil ne veut plus rien recevoir sur ce jeton. Le retirer
      // est la seule réponse correcte : le garder ferait grossir la file à
      // chaque envoi, indéfiniment.
      if (response.status === 410) {
        await admin.from('push_tokens').delete().eq('token', target.token);
      } else {
        console.error(`APNs ${response.status} pour ${target.token.slice(0, 8)}… : ${await response.text()}`);
      }
    }

    recipients += delivered;
    sent++;
    await admin
      .from('push_outbox')
      .update({ sent_at: new Date().toISOString(), attempts: message.attempts + 1 })
      .eq('id', message.id);
  }

  return { sent, recipients };
});
