// Tests de l'accès aux nombres.
//
// Tout est vérifié SANS réseau : `instantane` prend son `fetch` en argument.
// Une suite qui aurait besoin d'Internet ne tournerait pas sur le Pi, et c'est
// justement là qu'on voudra la lancer le jour où quelque chose cloche.

import { deepStrictEqual, match, ok, strictEqual } from 'node:assert/strict';
import test from 'node:test';
import { CONFIG_MANQUANTE, configDe, garder, instantane, messageDeStatut } from './metrics.mjs';

const ENV = {
  SUPABASE_URL: 'https://exemple.supabase.co',
  SUPABASE_ANON_KEY: 'cle-publiable',
  MONITOR_TOKEN: 'jeton-du-pi',
};

const INSTANTANE = {
  prisLe: '2026-08-08T12:00:00.000Z',
  moderation: { enAttente: 3, signales: 1, plusAncienJours: 7, parTranche: [0, 1, 1, 1, 0], parCategorie: {} },
  flux: [{ jour: '2026-08-08', arrivees: 1, approbations: 0 }],
  blocages: { fragmentsSales: false, fragmentsDepuisMinutes: 4, pushEnAttente: 0, pushPlusAncienMinutes: null, pushCoinces: 0 },
  communaute: { profils: 12, approuvees: 40, rejetees: 3, votes: 91, signalements: 2 },
};

const repond = (statut, corps) => async () => ({
  ok: statut >= 200 && statut < 300,
  status: statut,
  json: async () => corps,
});

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

test('la configuration dit ce qui manque plutôt que d’échouer plus loin', () => {
  strictEqual(configDe({}).indisponible, CONFIG_MANQUANTE);
  strictEqual(configDe({ ...ENV, MONITOR_TOKEN: '' }).indisponible, CONFIG_MANQUANTE);
});

test('l’URL de la fonction se construit sans double barre', () => {
  // Un `SUPABASE_URL` recopié depuis le tableau de bord finit souvent par « / ».
  // Deux barres donnent un 404 dont la cause est invisible.
  strictEqual(
    configDe({ ...ENV, SUPABASE_URL: 'https://exemple.supabase.co/' }).url,
    'https://exemple.supabase.co/functions/v1/metrics',
  );
});

// ---------------------------------------------------------------------------
// Le garde-fou de forme
// ---------------------------------------------------------------------------

test('un instantané complet passe', () => {
  deepStrictEqual(garder(INSTANTANE), { instantane: INSTANTANE });
});

test('un champ absent est NOMMÉ', () => {
  // Le point de tout le garde-fou : « métriques illisibles » enverrait chercher
  // au mauvais endroit ; « `flux` absent » désigne une fonction périmée.
  const { flux, ...ampute } = INSTANTANE;
  match(garder(ampute).indisponible, /`flux` absent/);
  match(garder(ampute).indisponible, /redéployer/);
});

test('un champ du mauvais type est refusé, pas affiché', () => {
  // Le cas qui dessinerait des graphes vides si on ne le voyait pas.
  match(garder({ ...INSTANTANE, flux: {} }).indisponible, /`flux` est object au lieu de array/);
});

test('une réponse qui n’est pas un objet est refusée', () => {
  match(garder('bonjour').indisponible, /réponse inattendue/);
  match(garder(null).indisponible, /réponse inattendue/);
});

// ---------------------------------------------------------------------------
// Les statuts, et ce qu'ils veulent dire
// ---------------------------------------------------------------------------

test('401 et 503 ne disent pas la même chose', () => {
  // Même tête dans un journal, causes opposées : jeton faux d'un côté, secret
  // jamais posé de l'autre. Les confondre coûte une demi-heure.
  match(messageDeStatut(401), /ne correspond pas au secret déployé/);
  match(messageDeStatut(503), /supabase secrets set/);
  match(messageDeStatut(404), /functions deploy/);
});

// ---------------------------------------------------------------------------
// Le chemin complet
// ---------------------------------------------------------------------------

test('un aller-retour nominal rend l’instantané', async () => {
  const resultat = await instantane(ENV, repond(200, INSTANTANE));
  deepStrictEqual(resultat.instantane, INSTANTANE);
});

test('les deux serrures voyagent dans les en-têtes', async () => {
  let vues = null;
  await instantane(ENV, async (_url, options) => {
    vues = options.headers;
    return { ok: true, status: 200, json: async () => INSTANTANE };
  });
  strictEqual(vues.apikey, 'cle-publiable');
  strictEqual(vues.Authorization, 'Bearer cle-publiable');
  strictEqual(vues['X-Monitor-Token'], 'jeton-du-pi');
});

test('le jeton ne part JAMAIS dans l’URL', async () => {
  // Une URL se retrouve dans les journaux d'accès, l'historique, les référents.
  // Un en-tête, beaucoup moins.
  let url = null;
  await instantane(ENV, async (u) => {
    url = u;
    return { ok: true, status: 200, json: async () => INSTANTANE };
  });
  ok(!url.includes('jeton-du-pi'), `le jeton apparaît dans l’URL : ${url}`);
});

test('un refus devient une phrase, jamais un instantané vide', async () => {
  const resultat = await instantane(ENV, repond(401, {}));
  strictEqual(resultat.instantane, undefined);
  match(resultat.indisponible, /refuse le jeton/);
});

test('un réseau muet devient une phrase', async () => {
  const resultat = await instantane(ENV, async () => {
    throw new Error('getaddrinfo ENOTFOUND');
  });
  match(resultat.indisponible, /injoignable — getaddrinfo ENOTFOUND/);
});

test('un JSON illisible devient une phrase', async () => {
  const resultat = await instantane(ENV, async () => ({
    ok: true,
    status: 200,
    json: async () => {
      throw new Error('Unexpected token <');
    },
  }));
  match(resultat.indisponible, /ne rend pas du JSON/);
});

test('une configuration absente n’essaie même pas le réseau', async () => {
  let appele = false;
  const resultat = await instantane({}, async () => {
    appele = true;
  });
  strictEqual(appele, false);
  strictEqual(resultat.indisponible, CONFIG_MANQUANTE);
});
