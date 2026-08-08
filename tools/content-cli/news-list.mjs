// `cli.js news` — voir les actus, et seulement celles qu'on cherche.
//
// Il n'existait aucun moyen de REGARDER le contenu depuis la ligne de commande :
// `validate` dit si c'est valide, `check-publishable` si c'est publiable, et
// rien ne dit simplement « qu'est-ce qu'il y a ». On ouvrait `content/news/`
// dans un éditeur, ou on lançait la console web pour trois lignes.
//
// Tout ce qui décide est PUR et prend son jour de référence en argument : sans
// ça, un test de `--days 7` dépendrait de la date à laquelle on le lance.

import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { CONTENT } from './schemas.mjs';

const JOUR = /^\d{4}-\d{2}-\d{2}$/;
const JOUR_MS = 24 * 60 * 60 * 1000;

/** Une date de filtre, ou une erreur qui dit ce qu'on attendait.
 *
 *  Refuser explicitement plutôt qu'ignorer : un `--since 08/2026` silencieux
 *  rendrait la liste entière et donnerait à croire qu'il n'y a rien à filtrer. */
export function jourValide(valeur, quoi) {
  if (!JOUR.test(valeur)) {
    throw new Error(`${quoi} : « ${valeur} » n'est pas une date AAAA-MM-JJ`);
  }
  if (Number.isNaN(Date.parse(`${valeur}T00:00:00Z`))) {
    throw new Error(`${quoi} : « ${valeur} » n'existe pas dans le calendrier`);
  }
  return valeur;
}

/** Le jour situé `n` jours avant `aujourdhui`. */
export function ilYA(n, aujourdhui) {
  return new Date(Date.parse(`${aujourdhui}T00:00:00Z`) - n * JOUR_MS).toISOString().slice(0, 10);
}

/**
 * Traduit les options en un intervalle fermé `[depuis, jusqua]`, bornes
 * comprises. `null` d'un côté veut dire « pas de borne ».
 *
 * `--days N` est un raccourci de `--since`, et il compte N jours EN INCLUANT
 * aujourd'hui : `--days 1` rend les actus du jour, pas celles d'hier. C'est ce
 * qu'on veut dire en tapant « les actus du jour ».
 */
export function intervalle({ since, until, days }, aujourdhui) {
  if (days !== undefined && since !== undefined) {
    throw new Error('--days et --since disent la même chose : n\'en garder qu\'un');
  }
  let depuis = since === undefined ? null : jourValide(since, '--since');
  const jusqua = until === undefined ? null : jourValide(until, '--until');

  if (days !== undefined) {
    const n = Number(days);
    if (!Number.isInteger(n) || n < 1 || n > 3650) {
      throw new Error(`--days : « ${days} » n'est pas un nombre de jours entre 1 et 3650`);
    }
    depuis = ilYA(n - 1, aujourdhui);
  }

  // Un intervalle vide est presque toujours une inversion de saisie, et il
  // rendrait « aucune actu » — le genre de zéro qui se prend pour un fait.
  if (depuis && jusqua && depuis > jusqua) {
    throw new Error(`intervalle vide : --since ${depuis} est après --until ${jusqua}`);
  }
  return { depuis, jusqua };
}

/** Lit toutes les actus du dépôt. Un fichier illisible n'est pas tu : il entre
 *  dans la liste avec sa panne, sinon il disparaîtrait exactement quand on le
 *  cherche. */
export function lireLesActus(racine = join(CONTENT, 'news')) {
  const items = [];
  for (const f of readdirSync(racine).filter((x) => x.endsWith('.json')).sort()) {
    const id = f.slice(0, -5);
    try {
      const d = JSON.parse(readFileSync(join(racine, f), 'utf8'));
      items.push({
        id,
        date: d.publishedAt ?? null,
        status: d.status ?? null,
        confidence: d.confidence ?? null,
        category: d.category ?? null,
        titre: d.title?.fr ?? d.title?.en ?? id,
        source: Array.isArray(d.sources) ? d.sources[0] ?? null : null,
      });
    } catch (err) {
      items.push({ id, date: null, status: null, illisible: err.message, titre: id });
    }
  }
  return items;
}

/**
 * Applique les filtres. Les items SANS date ne sont écartés que si un filtre de
 * date est posé — sinon on masquerait un fichier cassé au moment précis où on
 * liste le contenu pour comprendre ce qui cloche.
 */
export function filtrer(items, { depuis, jusqua, status }) {
  return items.filter((i) => {
    if (status && i.status !== status) return false;
    if (!depuis && !jusqua) return true;
    if (!i.date) return false;
    if (depuis && i.date < depuis) return false;
    if (jusqua && i.date > jusqua) return false;
    return true;
  });
}

/** Les plus récentes d'abord ; à date égale, l'ordre des identifiants, pour que
 *  deux exécutions rendent la même liste. */
export function trier(items) {
  return [...items].sort((a, b) => (b.date ?? '').localeCompare(a.date ?? '') || a.id.localeCompare(b.id));
}

const MARQUES = { published: '●', draft: '○' };

/** Le tableau texte. Colonnes alignées, une ligne par actu. */
export function formater(items, { depuis, jusqua, status } = {}) {
  if (!items.length) {
    const bornes = [
      depuis ? `depuis ${depuis}` : null,
      jusqua ? `jusqu'au ${jusqua}` : null,
      status ? `en ${status}` : null,
    ].filter(Boolean);
    return `aucune actu${bornes.length ? ` ${bornes.join(', ')}` : ''}.`;
  }

  const largeurId = Math.max(...items.map((i) => i.id.length));
  const lignes = items.map((i) => {
    if (i.illisible) return `  ✘ ${i.id.padEnd(largeurId)}  ILLISIBLE — ${i.illisible}`;
    const marque = MARQUES[i.status] ?? '?';
    const conf = (i.confidence ?? '').padEnd(18);
    return `  ${marque} ${(i.date ?? '—').padEnd(10)}  ${i.id.padEnd(largeurId)}  ${conf}  ${i.titre}`;
  });

  const publiees = items.filter((i) => i.status === 'published').length;
  const brouillons = items.filter((i) => i.status === 'draft').length;
  const cassees = items.filter((i) => i.illisible).length;
  lignes.push(
    '',
    `  ${items.length} actu(s) — ● ${publiees} publiée(s), ○ ${brouillons} brouillon(s)`
    + (cassees ? `, ✘ ${cassees} illisible(s)` : ''),
  );
  return lignes.join('\n');
}
