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

// ---------------------------------------------------------------------------
// Rendu HTML, pour la console web
//
// Pourquoi un rendu de plus, et pas le `<pre>` du terminal : la page STYLE DÉJÀ
// les tableaux (`table`, `th`, `td` dans `index.html`), et la référence en est
// pleine. Servir du texte préformaté afficherait des colonnes désalignées à
// côté de tableaux natifs, dans la même fenêtre.
//
// Ce rendu reste volontairement partiel — il ne couvre que ce que la référence
// emploie réellement. Un convertisseur markdown complet serait une dépendance,
// ou trois cents lignes à maintenir pour des cas qu'aucun fichier n'utilise.
// ---------------------------------------------------------------------------

/** L'échappement, fait AVANT toute mise en forme.
 *
 *  Le fichier est local et écrit par nous, donc ceci n'est pas une défense
 *  contre un attaquant — c'est ce qui empêche un `<h2>` cité dans une phrase de
 *  disparaître de l'écran en devenant une balise. */
function echapper(texte) {
  return String(texte).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

/** Gras, code, liens — appliqués après l'échappement, sur un paragraphe entier
 *  et non ligne à ligne : `**…**` court souvent sur deux lignes. */
function enLigne(texte) {
  return texte
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([\s\S]+?)\*\*/g, '<strong>$1</strong>')
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>');
}

const estSeparateurDeTableau = (l) => /^\s*\|[\s:|-]+\|\s*$/.test(l);
const cellules = (l) => l.trim().replace(/^\||\|$/g, '').split('|').map((c) => c.trim());

/**
 * Markdown → HTML, pour l'injection dans la boîte de dialogue de la console.
 *
 * Couvre : titres, tableaux, listes à puces et numérotées, citations, filets,
 * paragraphes, et la mise en forme en ligne. C'est tout ce que la référence
 * emploie — `doc.test.mjs` le vérifie sur le fichier réel plutôt que sur des
 * exemples inventés, pour qu'une construction nouvelle ne passe pas inaperçue.
 */
export function enHTML(markdown) {
  const lignes = String(markdown).split('\n');
  const sortie = [];
  let paragraphe = [];
  let liste = null;

  const viderParagraphe = () => {
    if (!paragraphe.length) return;
    sortie.push(`<p>${enLigne(echapper(paragraphe.join('\n')))}</p>`);
    paragraphe = [];
  };
  const fermerListe = () => {
    if (!liste) return;
    sortie.push(`</${liste}>`);
    liste = null;
  };
  const vider = () => { viderParagraphe(); fermerListe(); };

  for (let i = 0; i < lignes.length; i++) {
    const ligne = lignes[i];

    if (!ligne.trim()) { vider(); continue; }

    const titre = ligne.match(/^(#{1,4}) +(.+)$/);
    if (titre) {
      vider();
      // Le `#` du document devient un `h2` : la boîte de dialogue porte déjà son
      // propre titre, et deux `h1` dans une page en font un de trop.
      const niveau = Math.min(titre[1].length + 1, 5);
      sortie.push(`<h${niveau}>${enLigne(echapper(titre[2]))}</h${niveau}>`);
      continue;
    }

    if (/^---+$/.test(ligne.trim())) { vider(); sortie.push('<hr>'); continue; }

    // Un tableau : la ligne d'en-tête, son séparateur, puis les lignes de corps.
    if (ligne.trim().startsWith('|') && estSeparateurDeTableau(lignes[i + 1] ?? '')) {
      vider();
      const entetes = cellules(ligne);
      sortie.push('<table><thead><tr>');
      for (const c of entetes) sortie.push(`<th>${enLigne(echapper(c))}</th>`);
      sortie.push('</tr></thead><tbody>');
      i += 1; // le séparateur, qui ne porte que l'alignement
      while ((lignes[i + 1] ?? '').trim().startsWith('|')) {
        i += 1;
        sortie.push('<tr>');
        for (const c of cellules(lignes[i])) sortie.push(`<td>${enLigne(echapper(c))}</td>`);
        sortie.push('</tr>');
      }
      sortie.push('</tbody></table>');
      continue;
    }

    const puce = ligne.match(/^ *[-*] +(.+)$/);
    const numero = ligne.match(/^ *\d+\. +(.+)$/);
    if (puce || numero) {
      viderParagraphe();
      const voulue = puce ? 'ul' : 'ol';
      if (liste !== voulue) { fermerListe(); sortie.push(`<${voulue}>`); liste = voulue; }
      sortie.push(`<li>${enLigne(echapper((puce ?? numero)[1]))}</li>`);
      continue;
    }

    if (ligne.startsWith('> ')) {
      vider();
      sortie.push(`<blockquote>${enLigne(echapper(ligne.slice(2)))}</blockquote>`);
      continue;
    }

    // Une ligne d'un élément de liste qui se poursuit reste dans cet élément
    // plutôt que d'ouvrir un paragraphe au milieu d'une liste.
    if (liste && /^ {2,}\S/.test(ligne)) {
      sortie[sortie.length - 1] = sortie[sortie.length - 1].replace(
        /<\/li>$/,
        ` ${enLigne(echapper(ligne.trim()))}</li>`,
      );
      continue;
    }

    fermerListe();
    paragraphe.push(ligne);
  }

  vider();
  return sortie.join('\n');
}

/** Le sommaire, pour `--list` et pour le message d'une section inconnue. */
export function sommaire(markdown) {
  return sections(markdown).map((s) => `  ${String(s.rang).padStart(2)}. ${s.titre.replace(/^\d+\.\s*/, '')}`).join('\n');
}
