// La référence des fonctions de la console, servie par la CLI.
//
// ─────────────────────────────────────────────────────────────────────────────
// UNE SEULE SOURCE, ET C'EST TOUT L'INTÉRÊT
//
// Le markdown de `docs/ops/` est la source, et la seule. Recopier son contenu
// ici pour l'imprimer plus facilement reproduirait EXACTEMENT la panne que
// `commands.mjs` a corrigée : deux copies d'une même liste, toutes deux dérivées,
// dont l'une proposait une commande disparue depuis des semaines.
//
// « Une aide fausse est pire qu'une aide absente : l'absence envoie lire le
// code, le mensonge envoie taper une commande qui n'existe pas. » La même phrase
// vaut pour une référence.
//
// Ce que ce fichier s'autorise, donc : LIRE, découper, mettre en forme. Jamais
// énoncer un fait de son côté. Le seul fait qu'il détient est le chemin.
//
// `doc.test.mjs` tient l'autre bout : il compare ce que la référence ÉNONCE à ce
// que le code fait — les noms d'actions, leur nombre, les fiches du carnet. Une
// action retirée d'`actions.mjs` sans l'être de la référence fait échouer la
// suite, dans les deux sens.

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { ROOT } from './schemas.mjs';

/** La référence. Un seul fichier, nommé une seule fois dans tout le dépôt. */
export const CHEMIN = join(
  ROOT,
  'docs',
  'ops',
  '2026-08-09-console-reference-des-fonctions.md',
);

/** Le markdown brut.
 *
 *  Une erreur EXPLICITE plutôt qu'un ENOENT : si la référence a été déplacée,
 *  le message doit dire où elle était attendue, pas laisser lire une trace de
 *  pile pour retrouver un chemin. */
export function lire(chemin = CHEMIN) {
  try {
    return readFileSync(chemin, 'utf8');
  } catch {
    throw new Error(
      `référence introuvable : ${chemin}\n`
      + 'Elle a été déplacée ou renommée — corriger CHEMIN dans tools/content-cli/doc.mjs.',
    );
  }
}

/** Les sections de premier niveau (`## `), dans l'ordre du document.
 *
 *  Le titre est gardé tel quel : il porte déjà son numéro (« 3. Les 29
 *  actions »), et le renuméroter ici ferait diverger l'affichage du fichier. */
export function sections(markdown) {
  return [...String(markdown).matchAll(/^## +(.+)$/gm)].map((m, i) => ({
    rang: i + 1,
    titre: m[1].trim(),
    debut: m.index,
  }));
}

/**
 * Une section, désignée par son rang (« 3 ») ou par un mot de son titre
 * (« carnet », « actions »).
 *
 * Rend `null` plutôt que de deviner : demander une section qui n'existe pas doit
 * lister ce qui existe, pas afficher la première venue.
 */
export function sectionDe(markdown, quoi) {
  const liste = sections(markdown);
  if (!liste.length || quoi === undefined || quoi === null || quoi === '') return null;

  const cherche = String(quoi).trim().toLowerCase();
  const parRang = /^\d+$/.test(cherche)
    ? liste.find((s) => s.rang === Number(cherche) || s.titre.startsWith(`${cherche}.`))
    : null;
  // Sans accents ni casse : on tape « controles » pour « Contrôles ». La plage
  // est écrite échappée — un intervalle de diacritiques combinants collé en
  // clair dans une source est invisible à la relecture et se perd à la copie.
  const plat = (s) => s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
  const parMot = parRang ?? liste.find((s) => plat(s.titre).includes(plat(cherche)));
  if (!parMot) return null;

  const suivante = liste.find((s) => s.debut > parMot.debut);
  const fin = suivante ? suivante.debut : markdown.length;
  return { ...parMot, texte: markdown.slice(parMot.debut, fin).trimEnd() };
}

/**
 * Markdown → terminal.
 *
 * Volontairement minimal, et c'est un choix : un rendu riche demanderait une
 * dépendance, et ce dépôt n'en ajoute pas une pour de la mise en forme. Ce qui
 * est retiré l'est parce qu'il NUIT à la lecture en monospace (les lignes de
 * séparation des tableaux, les marqueurs d'emphase) ; les tableaux eux-mêmes
 * restent, ils se lisent très bien alignés.
 */
export function rendre(markdown) {
  // L'emphase est retirée AVANT le découpage en lignes, et pas dans `nettoyer` :
  // un `**…**` court souvent sur deux lignes dans un paragraphe justifié, et une
  // substitution ligne à ligne laisse alors les deux marqueurs en place — le
  // texte s'affiche `**quoi,` ↵ `coûte**`. Constaté sur la section du carnet.
  const sansEmphase = String(markdown).replace(/\*\*([\s\S]+?)\*\*/g, '$1');

  const lignes = [];
  for (const ligne of sansEmphase.split('\n')) {
    // La ligne d'alignement d'un tableau : `|---|:-:|`. Elle ne porte aucune
    // information et coupe le tableau en deux à l'œil.
    if (/^\s*\|[\s:|-]+\|\s*$/.test(ligne)) continue;

    const titre = ligne.match(/^(#{1,4}) +(.+)$/);
    if (titre) {
      const [, diese, texte] = titre;
      const nu = nettoyer(texte);
      if (diese.length <= 2) {
        lignes.push('', nu.toUpperCase(), '─'.repeat(Math.min(nu.length, 78)));
      } else {
        lignes.push('', nu);
      }
      continue;
    }
    lignes.push(nettoyer(ligne));
  }
  // Jamais plus d'une ligne vide d'affilée : les titres en ajoutent une devant,
  // qui double celle que le markdown avait déjà.
  return lignes.join('\n').replace(/\n{3,}/g, '\n\n').trim();
}

/** Retire ce qui est du balisage et non du texte. Les backticks partent, mais
 *  le contenu reste : `deliver` doit se lire deliver, pas disparaître. */
function nettoyer(texte) {
  return String(texte)
    .replace(/\*\*(.+?)\*\*/g, '$1')
    .replace(/(?<!`)`([^`]+)`(?!`)/g, '$1')
    .replace(/^> ?/, '')
    // Les liens markdown : garder le libellé ET la cible, qui est un chemin de
    // fichier qu'on veut pouvoir copier.
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '$1 ($2)');
}

/** Le sommaire, pour `--list` et pour le message d'une section inconnue. */
export function sommaire(markdown) {
  return sections(markdown).map((s) => `  ${String(s.rang).padStart(2)}. ${s.titre.replace(/^\d+\.\s*/, '')}`).join('\n');
}
