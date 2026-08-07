// Déclencher un workflow GitHub, et en lire le VRAI verdict.
//
// Tout ce fichier existe à cause d'une seule phrase, vérifiée le 2026-08-06 et
// réinscrite dans `recolte.yml` : **l'API `actions/runs/<id>/jobs` rapporte
// `conclusion: success` pour une étape en `continue-on-error` sortie en code 1.**
// Quatre runs se sont annoncés verts alors que deux avaient échoué. Le champ qui
// dirait la vérité (`outcome`) n'est pas exposé.
//
// Donc : le statut ne dit rien, et le journal est la seule autorité.
//
// La nuance qui décide de tout — on cherche **ce qui DOIT être là**, pas
// l'absence d'erreur. Chercher « pas d'erreur » se fait piéger par un journal
// vide, qui est précisément ce que produit une chaîne coupée tôt.

import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const run = promisify(execFile);

// `gh run view --log` n'émet PAS d'octet ESC : il rend les séquences ANSI en
// littéral `^[`. Vérifié sur le run 31146819752. Les deux formes sont acceptées
// ici, parce que dépendre de laquelle `gh` choisit serait dépendre d'un détail
// qu'aucun test ne surveille chez eux.
const ANSI = /(?:\x1b|\^\[)\[[0-9;]*m/g;

// Le piège le plus vicieux du journal : GitHub y recopie CHAQUE commande avant
// de l'exécuter, en cyan gras. La ligne
//
//     ^[[36;1mecho "récolte déposée sur veille/recolte (...)"^[[0m
//
// contient donc le marqueur… même si la commande n'a jamais tourné. Un lecteur
// naïf déclarerait « déposée » une récolte qui a échoué. Ces lignes sont retirées
// AVANT toute recherche.
const ECHO_DE_COMMANDE = /(?:\x1b|\^\[)\[36;1m/;

/** Le journal débarrassé de ses échos de commande et de ses couleurs. */
export function lignesReelles(log) {
  return String(log ?? '')
    .split('\n')
    .filter((l) => !ECHO_DE_COMMANDE.test(l))
    .map((l) => l.replace(ANSI, ''));
}

/**
 * Les marqueurs POSITIFS de la Récolte — la preuve que le travail a eu lieu.
 *
 * Chacun est une chaîne réellement imprimée, pas une invention : les trois
 * premiers viennent de `tools/content-cli/fetch-source.mjs`, le dernier de
 * l'étape « Déposer la récolte » de `recolte.yml`.
 */
export const MARQUEURS = [
  {
    etape: 'Préflight',
    motif: /(\d+) source\(s\) joignable\(s\)/,
    resume: (m) => `${m[1]} source(s) joignable(s)`,
  },
  {
    etape: 'Récolte',
    motif: /(\d+) page\(s\) rapportée\(s\), (\d+) flux lu\(s\)/,
    resume: (m) => `${m[1]} page(s), ${m[2]} flux`,
  },
  {
    // Deux sorties légitimes, et c'est important : « pas de semaine publiée »
    // n'est PAS une panne. La source ne publie pas toutes les semaines, et le
    // verdict `sans-semaine` est un résultat. Ce qui serait une panne, c'est le
    // SILENCE — ni l'un ni l'autre.
    etape: 'Semaine du mode en ligne',
    motif: /écrit content\/inbox\/[^\s]*gtav-weekly\.facts\.json|pas de semaine publiée/,
    resume: (m) => (m[0].startsWith('écrit') ? 'semaine récoltée' : 'aucune semaine publiée par la source'),
  },
  {
    etape: 'Dépôt sur la branche de transport',
    motif: /récolte déposée sur veille\/recolte/,
    resume: () => 'déposée',
  },
];

/**
 * Le verdict tiré du seul journal. Quatre issues, et la quatrième n'est PAS un
 * succès : un journal qu'on n'a pas su lire est `indéterminé`, jamais « ok ».
 * Un contrôle qui, dans le doute, approuve, ne contrôle rien.
 */
export function verdictFromLog(log) {
  const lignes = lignesReelles(log);
  const texte = lignes.join('\n');

  const etapes = MARQUEURS.map(({ etape, motif, resume }) => {
    const m = texte.match(motif);
    return { etape, vu: Boolean(m), resume: m ? resume(m) : null };
  });

  const vus = etapes.filter((e) => e.vu);

  if (!texte.trim()) {
    return { verdict: 'indéterminé', etapes, detail: 'journal vide — rien à lire' };
  }
  if (vus.length === 0) {
    return {
      verdict: 'échec',
      etapes,
      detail: 'aucun marqueur : la chaîne n’est pas allée jusqu’au premier résultat',
    };
  }
  if (vus.length === MARQUEURS.length) {
    return { verdict: 'complète', etapes, detail: etapes.map((e) => e.resume).join(' · ') };
  }
  const muettes = etapes.filter((e) => !e.vu).map((e) => e.etape);
  return {
    verdict: 'partielle',
    etapes,
    detail: `muette${muettes.length > 1 ? 's' : ''} : ${muettes.join(', ')}`,
  };
}

/**
 * Le verdict d'un run entier. La conclusion GitHub ne sert qu'à UNE chose —
 * dire qu'un run a franchement échoué, ce qu'elle ne peut pas fausser dans ce
 * sens-là. Pour tout le reste, elle est ignorée au profit du journal.
 */
export function verdictForRun({ status, conclusion }, log) {
  if (status && status !== 'completed') {
    return { verdict: 'en cours', etapes: [], detail: `run ${status}` };
  }
  if (conclusion === 'failure' || conclusion === 'cancelled' || conclusion === 'timed_out') {
    const duJournal = verdictFromLog(log);
    return { ...duJournal, verdict: 'échec', detail: `run ${conclusion} — ${duJournal.detail}` };
  }
  return verdictFromLog(log);
}

/** `gh`, sans shell, arguments en éléments distincts. */
async function gh(args) {
  const { stdout } = await run('gh', args, { maxBuffer: 32 * 1024 * 1024 });
  return stdout;
}

export async function ghDisponible() {
  try {
    await run('gh', ['auth', 'status']);
    return { ok: true };
  } catch (err) {
    return {
      ok: false,
      // Le message dit QUOI FAIRE, pas seulement ce qui a raté.
      erreur: /not found|ENOENT/i.test(err.message)
        ? 'gh introuvable — installer GitHub CLI (brew install gh)'
        : 'gh non authentifié — lancer « gh auth login »',
    };
  }
}

/**
 * Les derniers runs d'un workflow. `depuis` (ISO) écarte ceux d'avant, ce qui
 * évite de confondre le run qu'on vient de déclencher avec celui du cron de
 * 1 h 47 — `gh workflow run` ne rend pas d'identifiant, il faut le repêcher.
 */
export async function derniersRuns(workflow, { limite = 5, depuis = null } = {}) {
  const champs = 'databaseId,status,conclusion,createdAt,displayTitle,url,event';
  const brut = await gh(['run', 'list', '--workflow', workflow, '--limit', String(limite), '--json', champs]);
  const runs = JSON.parse(brut);
  return depuis ? runs.filter((r) => r.createdAt > depuis) : runs;
}

/** Le journal d'un run. Un run en cours n'en a pas encore : ce n'est pas une
 *  erreur, c'est une chaîne vide, et `verdictForRun` en fait « en cours ». */
export async function journalDeRun(id) {
  try {
    return await gh(['run', 'view', String(id), '--log']);
  } catch {
    return '';
  }
}

/** L'état de la dernière Récolte, verdict compris. */
export async function derniereRecolte() {
  const dispo = await ghDisponible();
  if (!dispo.ok) return { indisponible: dispo.erreur };

  const [dernier] = await derniersRuns('recolte.yml', { limite: 1 });
  if (!dernier) return { indisponible: 'aucun run de Récolte trouvé' };

  const log = dernier.status === 'completed' ? await journalDeRun(dernier.databaseId) : '';
  return { run: dernier, ...verdictForRun(dernier, log) };
}
