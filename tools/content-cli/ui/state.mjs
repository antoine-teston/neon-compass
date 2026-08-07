// Ce que le tableau de bord agrège.
//
// Il répond à UNE question : qu'est-ce qui attend quelque chose de moi ?
//
// Trois classes de cartes, séparées par ce qu'elles coûtent :
//
//   - INSTANTANÉES — disque seul, calculées à chaque chargement.
//   - RÉSEAU — chacune demandée à part, avec son propre état.
//   - JAMAIS AU CHARGEMENT — `release --dry-run`. Trop lent, et c'est une
//     décision, pas un état.
//
// LA RÈGLE QUI COMPTE : **une carte ne ment jamais par omission.** `gh` non
// authentifié, credentials absents, réseau tombé — la carte le DIT. Elle
// n'affiche jamais un zéro. « 0 brouillon en attente » parce qu'un dossier n'a
// pas pu être lu est exactement la panne qu'on supprime, pas qu'on déplace.
// D'où `indisponible` partout plutôt qu'un `catch` qui rendrait une valeur vide.

import { execFileSync } from 'node:child_process';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { triageAll } from './drafts.mjs';
import { derniereRecolte } from './runs.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const CLI_DIR = join(HERE, '..');
const ROOT = join(CLI_DIR, '..', '..');
const CONTENT = join(ROOT, 'content');
const FUNCTIONS_DIR = join(ROOT, 'supabase', 'functions');

/**
 * Les credentials qui ouvrent les actions de production.
 *
 * Corrigé le 2026-08-07 : ce test portait sur `FIREBASE_SERVICE_ACCOUNT_PATH`,
 * resté de l'avant-migration. Depuis la bascule vers Supabase du 2026-08-02, la
 * CLI lit `SUPABASE_URL` et `SUPABASE_SERVICE_ROLE_KEY` — la console bloquait
 * donc TOUTES ses actions de production sur une variable que plus rien ne pose,
 * en renvoyant vers une documentation Firebase.
 */
export function credentialsPresent() {
  return Boolean(process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY);
}

export const CREDENTIALS_MANQUANTS =
  'SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY absents — voir docs/ops/2026-08-02-supabase-console-manual-steps.md';

function git(args) {
  try {
    return execFileSync('git', args, { cwd: ROOT, encoding: 'utf8' }).trim();
  } catch {
    return '';
  }
}

// ---------------------------------------------------------------------------
// Cartes instantanées — disque seul
// ---------------------------------------------------------------------------

/** La carte qui aurait rendu visibles les brouillons dormants. */
export function carteBrouillons() {
  try {
    const { parKind, totaux } = triageAll();
    // L'âge du plus ancien qui attend : un brouillon publiable depuis trois
    // semaines n'est pas la même nouvelle qu'un brouillon d'hier.
    const attendus = Object.values(parKind).flatMap((t) => t.attend);
    const plusAncien = attendus.map((i) => i.date).filter(Boolean).sort()[0] ?? null;
    return { parKind, totaux, plusAncien };
  } catch (err) {
    return { indisponible: `content/ illisible — ${err.message}` };
  }
}

/** Inventaire par kind : ce qui partirait, et ce qui attend. */
export function carteInventaire() {
  const kinds = {};
  try {
    for (const kind of ['poi', 'poi-gtav', 'cheats', 'collections', 'news', 'online-events']) {
      const dir = join(CONTENT, kind);
      if (!existsSync(dir)) continue;
      const files = readdirSync(dir).filter((f) => f.endsWith('.json'));
      let published = 0;
      for (const f of files) {
        if (JSON.parse(readFileSync(join(dir, f), 'utf8')).status === 'published') published++;
      }
      kinds[kind] = { total: files.length, published, draft: files.length - published };
    }

    // Les collections méritent leur propre coup d'œil : un défi sans total
    // attendu s'affiche en décompte brut côté app, ce qui est voulu mais mérite
    // d'être vu.
    const dir = join(CONTENT, 'collections');
    const collections = existsSync(dir)
      ? readdirSync(dir)
          .filter((f) => f.endsWith('.json'))
          .map((f) => JSON.parse(readFileSync(join(dir, f), 'utf8')))
          .sort((a, b) => a.id.localeCompare(b.id))
      : [];

    return { kinds, collections };
  } catch (err) {
    return { indisponible: `content/ illisible — ${err.message}` };
  }
}

export function carteGit() {
  const branche = git(['rev-parse', '--abbrev-ref', 'HEAD']);
  if (!branche) return { indisponible: 'git muet — ce répertoire est-il bien un dépôt ?' };
  const sale = git(['status', '--porcelain']);
  return {
    branche,
    commit: git(['rev-parse', '--short', 'HEAD']),
    modifies: sale ? sale.split('\n').length : 0,
  };
}

/** `check-seeds` est rapide et sans réseau : on le lance plutôt que de
 *  dupliquer sa logique — une règle dupliquée finit par diverger. */
export function carteSocles() {
  try {
    execFileSync(process.execPath, ['cli.js', 'check-seeds'], { cwd: CLI_DIR, stdio: 'pipe' });
    return { aJour: true };
  } catch (err) {
    // Un socle en retard n'est PAS une indisponibilité : c'est un résultat, et
    // c'est même celui qu'on cherche. Ne pas confondre les deux.
    if (err.status === 1) return { aJour: false };
    return { indisponible: `check-seeds injouable — ${err.message}` };
  }
}

export function cartesInstantanees() {
  return {
    credentials: credentialsPresent(),
    brouillons: carteBrouillons(),
    inventaire: carteInventaire(),
    git: carteGit(),
    socles: carteSocles(),
  };
}

// ---------------------------------------------------------------------------
// Cartes réseau — chacune sa requête, chacune son état
// ---------------------------------------------------------------------------

/** Les clés d'`app_config` qui pilotent l'app à chaud.
 *
 *  Lecture SEULE ici : elles ne changent que sous un geste nommé du carnet. Une
 *  valeur ne bouge que sous un nom qui dit pourquoi. */
export const CLES_APP_CONFIG = [
  'backendFeaturesEnabled',
  'communityContributionsEnabled',
  'contentBaseURL',
  'interstitialFrequency',
];

export async function carteAppConfig() {
  if (!credentialsPresent()) return { indisponible: CREDENTIALS_MANQUANTS };
  try {
    const { getConfig } = await import('../supabase-client.js');
    const valeurs = {};
    for (const cle of CLES_APP_CONFIG) valeurs[cle] = await getConfig(cle);
    return { valeurs };
  } catch (err) {
    return { indisponible: `app_config illisible — ${err.message}` };
  }
}

/** La dérive des edge functions.
 *
 *  Rappel de ce que ça attrape, parce que c'est invisible autrement : **une
 *  fonction non déployée ne casse rien — elle rend l'ANCIENNE réponse.** Six
 *  fonctions dérivaient le 2026-08-05, dont deux depuis plusieurs jours. */
export async function carteFonctions() {
  const projectRef = process.env.SUPABASE_PROJECT_REF;
  const token = process.env.SUPABASE_ACCESS_TOKEN;
  if (!projectRef || !token) {
    return {
      indisponible:
        'SUPABASE_PROJECT_REF et SUPABASE_ACCESS_TOKEN absents — le jeton est dans le trousseau, '
        + "service « Supabase CLI », compte « supabase »",
    };
  }
  try {
    const drift = await import('../../edge-functions/drift.mjs');
    // Racine ABSOLUE : `listSlugs` prend `supabase/functions` en relatif, donc
    // dépendrait du répertoire courant du serveur.
    const slugs = drift.listSlugs(FUNCTIONS_DIR);
    const lignes = drift.report({
      slugs,
      commits: drift.readCommits(slugs, FUNCTIONS_DIR),
      deployed: await drift.fetchDeployed({ projectRef, token }),
    });
    return { lignes, derivees: lignes.filter((l) => l.state !== 'à jour').map((l) => l.slug) };
  } catch (err) {
    return { indisponible: `dérive illisible — ${err.message}` };
  }
}

export async function carteRecolte() {
  try {
    return await derniereRecolte();
  } catch (err) {
    return { indisponible: `GitHub muet — ${err.message}` };
  }
}

/** Les cartes réseau, demandées ensemble mais échouant séparément.
 *
 *  `allSettled` et non `all` : une carte qui tombe ne doit pas emporter les
 *  autres. C'est la traduction technique de « une carte ne ment jamais par
 *  omission » — l'alternative serait un tableau de bord entièrement vide parce
 *  qu'un jeton manque. */
export async function cartesReseau() {
  const [recolte, appConfig, fonctions] = await Promise.allSettled([
    carteRecolte(),
    carteAppConfig(),
    carteFonctions(),
  ]);
  const denouer = (r, quoi) => (r.status === 'fulfilled' ? r.value : { indisponible: `${quoi} — ${r.reason?.message ?? r.reason}` });
  return {
    recolte: denouer(recolte, 'Récolte illisible'),
    appConfig: denouer(appConfig, 'app_config illisible'),
    fonctions: denouer(fonctions, 'dérive illisible'),
  };
}
