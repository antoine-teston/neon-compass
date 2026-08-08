// node --test tools/content-cli/docker/docker.test.mjs
//
// UN SEUL INVARIANT COMPTE ICI, ET IL TIENT EN UN PRÉFIXE.
//
// La console n'a aucune authentification. Sa porte « geste » lance
// `gh workflow run`, `git push` et des migrations ; sa porte « édition » écrit
// dans `content/`. La seule chose qui empêche n'importe quoi sur le réseau
// local de publier en production, c'est que le port soit lié à **127.0.0.1**.
//
// `"4321:4321"` au lieu de `"127.0.0.1:4321:4321"` est la faute d'un
// caractère, elle ne casse rien, elle ne produit aucune erreur, et elle met une
// console de publication sur le LAN. C'est exactement le genre de panne que ce
// dépôt attrape par un test plutôt que par la vigilance.
//
// Le moniteur du Pi fait l'INVERSE, à dessein : il écoute partout parce qu'il
// n'y a rien à appeler. Les deux fichiers sont donc vérifiés ensemble — la
// distinction est le sujet, pas un détail de configuration.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ICI = dirname(fileURLToPath(import.meta.url));
const RACINE = join(ICI, '..', '..', '..');

/** Le texte sans ses commentaires YAML.
 *
 *  Troisième fois dans ce dépôt qu'il faut le faire : le commentaire qui
 *  EXPLIQUE une règle la cite, donc un test qui la cherche dans le texte brut
 *  est satisfait par sa propre documentation. */
const sansCommentaires = (texte) => texte.replace(/^\s*#.*$/gm, '');

const lire = (chemin) => sansCommentaires(readFileSync(chemin, 'utf8'));

/** Les entrées de `ports:` d'un compose, telles qu'écrites. */
function portsDe(yaml) {
  const bloc = /^\s*ports:\s*$((?:\s*-\s*.*$)+)/m.exec(yaml);
  if (!bloc) return [];
  return [...bloc[1].matchAll(/-\s*"?([^"\s]+)"?/g)].map((m) => m[1]);
}

test('la console n’est liée qu’à la boucle locale', () => {
  const ports = portsDe(lire(join(ICI, 'compose.yml')));
  assert.ok(ports.length, 'aucun port déclaré dans le compose de la console');
  for (const p of ports) {
    assert.ok(
      p.startsWith('127.0.0.1:'),
      `port « ${p} » : la console publie en production et n'a AUCUNE authentification. `
      + 'Sans le préfixe 127.0.0.1, elle est joignable depuis tout le réseau local.',
    );
  }
});

test('le moniteur, lui, écoute partout — et c’est voulu', () => {
  // La distinction est le sujet. Si ce test tombe parce que le moniteur s'est
  // replié sur la boucle locale, c'est qu'on a copié la mauvaise règle : il
  // n'aurait plus aucun intérêt sur un Raspberry Pi.
  const ports = portsDe(lire(join(RACINE, 'tools', 'monitor', 'compose.yml')));
  assert.ok(ports.length, 'aucun port déclaré dans le compose du moniteur');
  for (const p of ports) {
    assert.ok(
      !p.startsWith('127.0.0.1:'),
      `port « ${p} » : un moniteur qu'on ne peut regarder que depuis le Pi ne sert à personne.`,
    );
  }
});

test('l’image de la console embarque git et gh, celle du moniteur ni l’un ni l’autre', () => {
  // Les deux moitiés du raisonnement, côte à côte : celle qui écrit a besoin
  // des outils, celle qui lit ne doit surtout pas les avoir.
  const console = lire(join(ICI, 'Dockerfile'));
  assert.match(console, /\bgit\b/, 'la console commite : sans git, « Livrer » ne peut pas exister');
  assert.match(console, /\bgh\b/, 'la console déclenche des workflows');

  const moniteur = lire(join(RACINE, 'tools', 'monitor', 'Dockerfile'));
  assert.doesNotMatch(moniteur, /apt-get install .*\bgit\b/, 'git est entré dans l’image du moniteur');
  assert.doesNotMatch(moniteur, /apk add .*\bgit\b/, 'git est entré dans l’image du moniteur');
});

test('le dépôt est MONTÉ, jamais copié dans l’image', () => {
  // Une copie serait figée à la construction, et les brouillons édités depuis
  // la console disparaîtraient au redémarrage — sans que rien ne le dise.
  const dockerfile = lire(join(ICI, 'Dockerfile'));
  assert.doesNotMatch(dockerfile, /^COPY\s+\.\.?\s/m, 'le Dockerfile copie le dépôt');
  assert.match(lire(join(ICI, 'compose.yml')), /:\/depot\b/, 'aucun montage du dépôt dans le compose');
});

test('le conteneur écrit sous l’utilisateur du Mac', () => {
  // Sans `user:`, il écrit en root dans le dépôt monté et les fichiers
  // deviennent inéditables depuis le Mac sans un `sudo chown`.
  assert.match(lire(join(ICI, 'compose.yml')), /user:\s*"\$\{HOST_UID/);
});

test('aucun secret n’est écrit en dur', () => {
  // `.env.example` explique quoi mettre ; il ne doit rien contenir. Un exemple
  // rempli finit toujours par être copié tel quel.
  const exemple = readFileSync(join(ICI, '.env.example'), 'utf8');
  for (const ligne of exemple.split('\n')) {
    if (ligne.startsWith('#') || !ligne.includes('=')) continue;
    const [cle, valeur] = ligne.split('=');
    if (['HOST_UID', 'HOST_GID'].includes(cle)) continue;
    assert.equal(valeur.trim(), '', `${cle} porte une valeur dans .env.example`);
  }
});
