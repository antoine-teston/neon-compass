// Le registre des refus éditoriaux — le seul état neuf de ce chantier.
//
// Pourquoi il ne se dérive de rien, contrairement au registre des URL récoltées
// (qui EST l'inbox) : un fait écarté n'a plus d'entrée, donc plus rien à lire.
// Sans ce fichier, `pull-news` recrée au run suivant ce qu'un humain vient
// d'écarter — constaté sur `news_9bd3ef15`, écartée le 2026-08-09 et que
// `pull-news --dry-run` voulait réécrire le 2026-08-10.
//
// Ce module est le SEUL à toucher `refus.json`. `facts-to-news.mjs` le reçoit
// en paramètre : son en-tête promet « aucune I/O », et cette promesse est ce
// qui le rend testable sans disque.

import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { CONTENT } from './schemas.mjs';
import { CONFIANCE_ORDRE } from './vocabulaire.mjs';

/** Le chemin réel, absolu, construit depuis `CONTENT` comme tout le reste du
 *  dossier. Absolu et non relatif : deux appelants qui le résoudraient chacun
 *  de leur côté finiraient par diverger d'un `join` près, et le refus serait
 *  écrit dans un fichier que la lecture ne regarde pas.
 *
 *  Les fonctions prennent malgré tout le chemin en PARAMÈTRE : sans ça, les
 *  tests écriraient dans le vrai registre du dépôt à chaque exécution. */
export const CHEMIN_REFUS = join(CONTENT, 'inbox', 'refus.json');

/** La clé d'un refus : `kind` et URL.
 *
 *  Alignée sur celle du contrôle de convergence, et NON sur `processedFrom` —
 *  ce discriminant contient le claim rédigé, donc une simple reformulation
 *  aurait suffi à ressusciter l'entrée écartée. */
export const cleDeRefus = (kind, url) => `${kind}|${url}`;

/** Vrai si `candidate` est STRICTEMENT plus forte que `reference`.
 *
 *  C'est la levée automatique : le 2026-08-09 n'a pas écarté un sujet, il a
 *  écarté une rumeur. Une confiance inconnue ne lève jamais — dans le doute, le
 *  refus tient. */
export function confianceSuperieure(candidate, reference) {
  const a = CONFIANCE_ORDRE.indexOf(candidate);
  const b = CONFIANCE_ORDRE.indexOf(reference);
  if (a === -1 || b === -1) return false;
  return a > b;
}

/** Lit le registre.
 *
 *  Absent = vide, l'état initial légitime. ILLISIBLE = on lève : un registre
 *  qu'on ne sait pas lire ne vaut pas un registre vide, qui laisserait repasser
 *  en silence tout ce qui a été écarté. */
export function lireRefus(chemin) {
  if (!existsSync(chemin)) return {};
  let data;
  try {
    data = JSON.parse(readFileSync(chemin, 'utf8'));
  } catch (err) {
    throw new Error(`registre des refus illisible (${chemin}) : ${err.message}`);
  }
  if (data === null || typeof data !== 'object' || Array.isArray(data)) {
    throw new Error(`registre des refus malformé (${chemin}) : un objet est attendu`);
  }
  return data;
}

/** Inscrit un refus, une entrée par source.
 *
 *  Une entrée à plusieurs sources en pose autant : le refus doit mordre quelle
 *  que soit celle qui la re-signale. */
export function inscrireRefus(chemin, { kind, sources, motif, entree, confiance, le }) {
  const registre = lireRefus(chemin);
  for (const url of sources) {
    registre[cleDeRefus(kind, url)] = { motif, entree, confiance, le };
  }
  writeFileSync(chemin, `${JSON.stringify(registre, null, 2)}\n`);
  return registre;
}
