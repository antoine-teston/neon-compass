// Dit quelles Edge Functions sont plus récentes dans git que sur le projet.
//
//   node tools/edge-functions/drift.mjs            # tableau lisible
//   node tools/edge-functions/drift.mjs --slugs    # la liste des dérivées, à passer à `deploy`
//
// Pourquoi cet outil existe. Le 2026-08-05, deux fonctions traînaient en
// production dans une version antérieure de plusieurs jours à leur source, sans
// que rien ne le signale : `rebuild-community-bundles` publiait des fragments
// sans `approvedAt`, et `submit-contribution` rendait ses refus sans code
// machine. Le SQL a son workflow depuis le 03/08 ; les fonctions n'en avaient
// aucun, et une fonction non déployée ne casse rien — elle rend l'ancienne
// réponse, ce que personne ne voit.
//
// Un bouton de déploiement seul n'aurait rien empêché. Ce qui manquait, c'est de
// SAVOIR que le déploiement était dû.

import { execFileSync } from 'node:child_process';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

export const FUNCTIONS_DIR = 'supabase/functions';
/** Répertoire de modules partagés, pas une fonction déployable. */
export const SHARED = '_shared';

// ---------------------------------------------------------------------------
// Logique pure — c'est elle que les tests couvrent.
// ---------------------------------------------------------------------------

/** Une fonction qui importe `_shared` hérite de sa date.
 *
 *  Sans cette règle, le cas RÉEL du 05/08 passerait à travers : `_shared/auth.ts`
 *  gagne un champ dans `HttpError`, et les six fonctions qui l'importent sont
 *  périmées d'un coup — aucune n'ayant vu son propre dossier modifié. */
export function dependsOnShared(sourceText) {
  return sourceText.includes(`${SHARED}/`);
}

/** La plus récente de plusieurs dates ISO. Les valeurs absentes sont ignorées. */
export function latestCommit(...dates) {
  const usable = dates.filter(Boolean).map((d) => new Date(d)).filter((d) => !Number.isNaN(+d));
  if (!usable.length) return null;
  return new Date(Math.max(...usable.map((d) => +d))).toISOString();
}

/** L'état d'une fonction, par comparaison de sa source et de son déploiement.
 *
 *  Le sens de l'inégalité n'est pas symétrique, et c'est délibéré : un faux
 *  positif coûte un redéploiement inutile, un faux négatif laisse une fonction
 *  périmée en production sans que personne ne le sache. En cas de doute — dates
 *  égales, ou déploiement manquant — on déclare la dérive. */
export function classify({ commit, deployedAt }) {
  if (!deployedAt) return 'jamais-déployée';
  if (!commit) return 'inconnue';
  return new Date(commit) > new Date(deployedAt) ? 'dérivée' : 'à jour';
}

/** L'horodatage de déploiement, quelle que soit la forme que l'API lui donne :
 *  époque en millisecondes (v1 aujourd'hui) ou chaîne ISO. */
export function normalizeDeployedAt(value) {
  if (value == null) return null;
  const date = typeof value === 'number' ? new Date(value) : new Date(value);
  return Number.isNaN(+date) ? null : date.toISOString();
}

export function report({ slugs, commits, deployed }) {
  return slugs.map((slug) => {
    const commit = commits[slug] ?? null;
    const deployedAt = normalizeDeployedAt(deployed[slug]);
    return { slug, commit, deployedAt, state: classify({ commit, deployedAt }) };
  });
}

// ---------------------------------------------------------------------------
// Lecture du dépôt et du projet.
// ---------------------------------------------------------------------------

export function listSlugs(root = FUNCTIONS_DIR) {
  return readdirSync(root)
    .filter((name) => name !== SHARED && statSync(join(root, name)).isDirectory())
    .sort();
}

function gitLastCommit(path) {
  const out = execFileSync('git', ['log', '-1', '--format=%cI', '--', path], { encoding: 'utf8' }).trim();
  return out || null;
}

/** Lit les dates de commit, `_shared` compris pour qui l'importe.
 *
 *  Lève si git ne rend AUCUNE date : c'est le symptôme d'un clone superficiel
 *  (`actions/checkout` sans `fetch-depth: 0`), et le silence y ferait conclure
 *  « tout est à jour » sur un dépôt dont on ne sait rien. */
export function readCommits(slugs, root = FUNCTIONS_DIR) {
  const sharedCommit = gitLastCommit(join(root, SHARED));
  const commits = {};
  for (const slug of slugs) {
    const own = gitLastCommit(join(root, slug));
    const sources = readdirSync(join(root, slug))
      .map((name) => {
        try {
          return readFileSync(join(root, slug, name), 'utf8');
        } catch {
          return '';
        }
      })
      .join('\n');
    commits[slug] = dependsOnShared(sources) ? latestCommit(own, sharedCommit) : own;
  }
  if (Object.values(commits).every((c) => c === null)) {
    throw new Error(
      "git ne rend aucune date de commit — clone superficiel ? `actions/checkout` a besoin de `fetch-depth: 0`."
    );
  }
  return commits;
}

export async function fetchDeployed({ projectRef, token }) {
  const response = await fetch(`https://api.supabase.com/v1/projects/${projectRef}/functions`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!response.ok) {
    throw new Error(`API Supabase ${response.status} : ${(await response.text()).slice(0, 200)}`);
  }
  const deployed = {};
  for (const fn of await response.json()) deployed[fn.slug] = fn.updated_at;
  return deployed;
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

if (import.meta.url === `file://${process.argv[1]}`) {
  const projectRef = process.env.SUPABASE_PROJECT_REF;
  const token = process.env.SUPABASE_ACCESS_TOKEN;
  if (!projectRef || !token) {
    console.error('SUPABASE_PROJECT_REF et SUPABASE_ACCESS_TOKEN sont requis');
    process.exit(1);
  }

  const slugs = listSlugs();
  const rows = report({ slugs, commits: readCommits(slugs), deployed: await fetchDeployed({ projectRef, token }) });
  const drifted = rows.filter((r) => r.state !== 'à jour');

  if (process.argv.includes('--slugs')) {
    console.log(drifted.map((r) => r.slug).join(' '));
  } else {
    const width = Math.max(...rows.map((r) => r.slug.length));
    for (const row of rows) {
      const mark = row.state === 'à jour' ? ' ' : '!';
      console.log(
        `${mark} ${row.slug.padEnd(width)}  ${row.state.padEnd(16)}` +
          `source ${row.commit?.slice(0, 19) ?? '?'}   déployée ${row.deployedAt?.slice(0, 19) ?? '—'}`
      );
    }
    console.log();
    console.log(drifted.length ? `${drifted.length} à déployer` : 'tout est à jour');
  }
}
