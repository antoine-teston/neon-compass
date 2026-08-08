// L'accès aux nombres, côté client. Partagé par la console (Mac) et le moniteur
// (Raspberry Pi) — délibérément, pour que le chemin du Pi soit exercé tous les
// jours depuis le Mac plutôt que découvert cassé sur une étagère.
//
// ─────────────────────────────────────────────────────────────────────────────
// CE FICHIER NE PEUT RIEN ÉCRIRE.
//
// Pas d'import de `node:child_process`, pas de `@supabase/supabase-js`, pas de
// `service_role`. Une requête HTTP GET vers une fonction, un jeton, et un
// garde-fou sur la forme de la réponse. C'est ce qui rend le dossier `monitor/`
// copiable tel quel dans une image Docker sans y faire entrer le pouvoir
// d'écrire — `imports.test.mjs` le vérifie sur tout le dossier.
//
// ─────────────────────────────────────────────────────────────────────────────
// ET IL NE MENT JAMAIS PAR OMISSION.
//
// Toute panne rend `{ indisponible: <phrase> }`, jamais un instantané vide.
// « 0 contribution en attente » parce qu'un jeton manque est exactement la
// panne qu'on supprime, pas qu'on déplace. La règle vaut aussi pour une réponse
// MALFORMÉE : `garder` refuse ce qu'il ne reconnaît pas, parce qu'un JSON
// inattendu affiché tel quel dessinerait des graphes à zéro.

/** Le nom de la fonction déployée. */
export const FONCTION = 'metrics';

export const CONFIG_MANQUANTE =
  'SUPABASE_URL, SUPABASE_ANON_KEY et MONITOR_TOKEN requis — le jeton se pose avec '
  + '`supabase secrets set MONITOR_TOKEN=…` puis se recopie dans l’environnement local';

/** Délai au-delà duquel on cesse d'attendre.
 *
 *  Sans lui, une fonction qui ne répond jamais laisserait le tableau de bord sur
 *  « chargement… » pour toujours — l'état le plus trompeur de tous, parce qu'il
 *  ressemble à du travail en cours. */
export const DELAI_MS = 8000;

/** Lit la configuration dans un environnement. Prend `env` en argument plutôt
 *  que de lire `process.env` : c'est ce qui rend les cas d'absence testables. */
export function configDe(env) {
  const url = env.SUPABASE_URL;
  const apikey = env.SUPABASE_ANON_KEY;
  const jeton = env.MONITOR_TOKEN;
  if (!url || !apikey || !jeton) return { indisponible: CONFIG_MANQUANTE };
  return { url: `${url.replace(/\/+$/, '')}/functions/v1/${FONCTION}`, apikey, jeton };
}

/** Les clés attendues et leur type. Une LISTE, comme les actions et les fichiers
 *  servis : ce qui n'est pas déclaré n'est pas reconnu. */
const FORME = {
  prisLe: 'string',
  moderation: 'object',
  flux: 'array',
  blocages: 'object',
  communaute: 'object',
};

function typeDe(v) {
  if (Array.isArray(v)) return 'array';
  return v === null ? 'null' : typeof v;
}

/**
 * Refuse un instantané qui n'a pas la forme attendue, en NOMMANT ce qui cloche.
 *
 * Le message compte : « métriques illisibles » enverrait chercher au mauvais
 * endroit. « champ `flux` absent » dit que la fonction déployée est plus
 * ancienne que cette page, ce qui est la panne réelle et se corrige en un
 * déploiement.
 */
export function garder(brut) {
  if (typeDe(brut) !== 'object') {
    return { indisponible: `réponse inattendue de \`${FONCTION}\` (${typeDe(brut)})` };
  }
  const manques = [];
  for (const [cle, attendu] of Object.entries(FORME)) {
    const trouve = typeDe(brut[cle]);
    if (trouve === 'undefined') manques.push(`\`${cle}\` absent`);
    else if (trouve !== attendu) manques.push(`\`${cle}\` est ${trouve} au lieu de ${attendu}`);
  }
  if (manques.length) {
    return {
      indisponible:
        `\`${FONCTION}\` répond hors contrat (${manques.join(', ')}) — la fonction déployée est `
        + 'sans doute plus ancienne que cette page ; redéployer `metrics`',
    };
  }
  return { instantane: brut };
}

/** Traduit un statut HTTP en une phrase qui dit quoi faire.
 *
 *  Un 401 et un 503 ont la même tête dans un journal et des causes opposées :
 *  jeton faux d'un côté, secret jamais posé de l'autre. */
export function messageDeStatut(statut) {
  if (statut === 401) return `\`${FONCTION}\` refuse le jeton — MONITOR_TOKEN ne correspond pas au secret déployé`;
  if (statut === 503) return `\`${FONCTION}\` n’a pas de MONITOR_TOKEN — \`supabase secrets set MONITOR_TOKEN=…\``;
  if (statut === 404) return `\`${FONCTION}\` n’est pas déployée — \`supabase functions deploy ${FONCTION}\``;
  return `\`${FONCTION}\` répond ${statut}`;
}

/**
 * Va chercher l'instantané. Ne LÈVE jamais : toute panne devient une phrase.
 *
 * @param {object} env l'environnement où lire la configuration
 * @param {typeof fetch} [aller] injectable pour les tests — le réseau est
 *   précisément ce qu'on ne veut pas dans une suite de tests
 */
export async function instantane(env, aller = fetch) {
  const config = configDe(env);
  if (config.indisponible) return config;

  const stop = AbortSignal.timeout(DELAI_MS);
  let reponse;
  try {
    // GET, parce que c'est une lecture. Rien de ce que le moniteur fait ne
    // devrait pouvoir s'écrire autrement.
    reponse = await aller(config.url, {
      method: 'GET',
      headers: {
        // La clé publiable ouvre la porte de la plateforme ; le jeton ouvre la
        // nôtre. Les deux sont nécessaires, aucune ne suffit.
        apikey: config.apikey,
        Authorization: `Bearer ${config.apikey}`,
        'X-Monitor-Token': config.jeton,
      },
      signal: stop,
    });
  } catch (err) {
    const quoi = err?.name === 'TimeoutError' ? `pas de réponse en ${DELAI_MS / 1000} s` : err.message;
    return { indisponible: `\`${FONCTION}\` injoignable — ${quoi}` };
  }

  if (!reponse.ok) return { indisponible: messageDeStatut(reponse.status) };

  let brut;
  try {
    brut = await reponse.json();
  } catch (err) {
    return { indisponible: `\`${FONCTION}\` ne rend pas du JSON — ${err.message}` };
  }
  return garder(brut);
}
