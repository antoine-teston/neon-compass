// L'INVARIANT du moniteur, et c'est le seul test de ce dossier qui compte
// vraiment :
//
//   RIEN DANS `tools/monitor/` NE PEUT LANCER UN PROCESSUS, ÉCRIRE UN FICHIER,
//   NI PARLER À POSTGRES.
//
// ─────────────────────────────────────────────────────────────────────────────
// Pourquoi un test plutôt qu'une intention
//
// La console du Mac tient parce qu'elle écoute sur 127.0.0.1 : personne d'autre
// ne peut l'atteindre. Le moniteur, lui, tourne sur un Raspberry Pi et est
// joignable par tout le réseau local. La protection « personne ne peut appeler »
// disparaît, et il ne reste que « il n'y a rien à appeler ».
//
// Ce n'est vrai que tant que personne n'ajoute un import par commodité. Un jour
// quelqu'un — moi, probablement — voudra « juste relancer la reconstruction des
// fragments depuis le tableau de bord ». Ce test est là pour que ce jour-là
// coûte un échec rouge plutôt qu'un Pi qui peut publier.
//
// Il lit le TEXTE des fichiers, pas leur graphe d'exécution : un module qui
// n'importe rien d'interdit mais construit `'child_' + 'process'` passerait.
// C'est assumé — le but est d'attraper la commodité, pas la malveillance, et
// personne ne contourne sa propre garde par accident.

import { ok, strictEqual } from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const ICI = dirname(fileURLToPath(import.meta.url));

/** Ce qui n'a rien à faire ici, et la raison — le message d'échec doit expliquer
 *  pourquoi c'est refusé, sinon le prochain lecteur le contournera en croyant
 *  bien faire. */
const INTERDITS = [
  ['node:child_process', 'lancer un processus depuis un service joignable sur le LAN'],
  ['child_process', 'lancer un processus depuis un service joignable sur le LAN'],
  ['@supabase/supabase-js', 'parler à Postgres directement — le moniteur passe par `metrics`, qui n’agrège que des nombres'],
  ['SERVICE_ROLE', 'détenir la clé qui contourne RLS sur une carte SD'],
  ['../content-cli', 'importer la console d’écriture, qui elle sait publier'],
];

/** Les écritures disque. `writeFile` et consorts : un moniteur n'a rien à
 *  écrire, et un dossier en écriture est une prise pour qui atteint le service. */
const ECRITURES = /\b(writeFile|writeFileSync|appendFile|appendFileSync|rm|rmSync|unlink|unlinkSync|mkdir|mkdirSync)\b/;

/** Retire commentaires de ligne et de bloc.
 *
 *  Indispensable, et la première version de ce test l'avait oublié : les
 *  en-têtes de ce dossier EXPLIQUENT qu'ils n'importent pas `child_process`, et
 *  le test échouait donc sur sa propre documentation. Un contrôle incapable de
 *  distinguer « je n'importe pas X » de « j'importe X » ne contrôle rien.
 *
 *  Approximation assumée : un `//` à l'intérieur d'une chaîne (une URL) tronque
 *  la fin de sa ligne. Sans conséquence ici — on cherche des noms de modules,
 *  pas à réécrire le fichier. */
function sansCommentaires(texte) {
  return texte.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/(^|[^:])\/\/.*$/gm, '$1');
}

function sources() {
  return readdirSync(ICI)
    .filter((f) => /\.(mjs|js)$/.test(f) && !f.endsWith('.test.mjs'))
    .map((f) => [f, sansCommentaires(readFileSync(join(ICI, f), 'utf8'))]);
}

test('le dossier contient bien des sources à vérifier', () => {
  // Sans ça, supprimer les fichiers ferait passer tous les tests suivants — un
  // contrôle qui ne contrôle rien est pire que pas de contrôle.
  ok(sources().length >= 2, `attendu au moins 2 sources, trouvé ${sources().length}`);
});

test('aucune source du moniteur n’importe de quoi écrire', () => {
  const fautes = [];
  for (const [nom, texte] of sources()) {
    for (const [motif, pourquoi] of INTERDITS) {
      if (texte.includes(motif)) fautes.push(`${nom} mentionne \`${motif}\` — ${pourquoi}`);
    }
  }
  strictEqual(fautes.join('\n'), '', `\n${fautes.join('\n')}\n`);
});

test('aucune source du moniteur n’écrit sur le disque', () => {
  const fautes = [];
  for (const [nom, texte] of sources()) {
    const trouve = texte.match(ECRITURES);
    if (trouve) fautes.push(`${nom} appelle \`${trouve[0]}\``);
  }
  strictEqual(fautes.join('\n'), '', `\n${fautes.join('\n')}\n`);
});

test('le serveur du moniteur ne sert que du GET', () => {
  // Un POST sur un service sans authentification, sur un réseau local, c'est
  // une porte. Il n'y en a pas.
  const serveur = readFileSync(join(ICI, 'server.mjs'), 'utf8');
  ok(!/'POST'|"POST"/.test(serveur), 'le serveur du moniteur mentionne POST');
});
