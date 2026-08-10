// node --test gabarits.test.mjs
//
// Le test qui porte tout ce fichier est celui de l'ORACLE : le français existe
// déjà pour les 537 POI de la carte de référence, il a été relu, et il est donc
// la seule preuve disponible que la table décrit vraiment la structure des
// titres. Si `composer` ne sait pas reproduire le FR d'un item, elle n'a pas le
// droit d'écrire ses ES/IT/DE non plus — c'est ce refus qui rend la composition
// sûre, pas la table elle-même.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { GABARITS, composer, titresComposables } from './gabarits.mjs';

const ICI = dirname(fileURLToPath(import.meta.url));
const POI_GTAV = join(ICI, '..', '..', 'content', 'poi-gtav');

// ---------------------------------------------------------------------------
// La composition
// ---------------------------------------------------------------------------

test('un titre gabarité garde son numéro et son lieu', () => {
  assert.equal(composer('Letter Scrap #36 - Pacific Bluffs', 'fr'), 'Fragment de lettre #36 - Pacific Bluffs');
  assert.equal(composer('Letter Scrap #36 - Pacific Bluffs', 'de'), 'Brieffetzen #36 - Pacific Bluffs');
});

test('un lieu ne se traduit jamais', () => {
  // « Grand Senora Desert » est un nom propre : le traduire inventerait un lieu
  // qui n'existe pas dans le jeu, et le joueur ne le retrouverait pas.
  for (const langue of ['es', 'it', 'de']) {
    assert.match(composer('Spaceship Part #10 - Grand Senora Desert', langue), /Grand Senora Desert$/);
  }
});

test('une famille sans numéro se compose aussi', () => {
  assert.equal(composer('Gas Station', 'es'), 'Gasolinera');
});

test('le marqueur de numéro du français est celui des données, pas le nôtre', () => {
  // `Hidden Package` est la seule famille dont le FR écrit « n° » là où toutes
  // les autres écrivent « # ». C'est une irrégularité des données existantes ;
  // on la REPRODUIT pour que l'oracle puisse valider, sans la propager aux
  // langues neuves.
  assert.equal(composer('Hidden Package #7', 'fr'), 'Magot caché n°7');
  assert.equal(composer('Hidden Package #7', 'it'), 'Pacco nascosto #7');
});

test('un titre hors table ne se compose pas', () => {
  assert.equal(composer('Michaels mansion', 'es'), null);
});

// ---------------------------------------------------------------------------
// L'oracle : le français déjà relu
// ---------------------------------------------------------------------------

const poiReels = () => readdirSync(POI_GTAV)
  .filter((f) => f.endsWith('.json'))
  .map((f) => ({ file: `poi-gtav/${f}`, data: JSON.parse(readFileSync(join(POI_GTAV, f), 'utf8')) }));

test('un titre dont le FR ne se reproduit pas est ÉCARTÉ, jamais composé', () => {
  // Le test le plus important du fichier, et le contrat exact : la table a le
  // droit de ne pas décrire un titre. Elle n'a pas le droit d'écrire trois
  // langues pour un titre qu'elle décrit MAL.
  //
  // Sur FIXTURE et non sur le contenu réel, délibérément : une fois le
  // rattrapage passé, plus aucun item réel n'est en attente, et le test
  // deviendrait vide sans rien dire. Ce qu'on veut garder vivant est la RÈGLE,
  // pas l'état du dépôt un jour donné.
  //
  // Le cas encodé ici est réel : `Hidden Package #9 - $25,000`, dont un humain
  // avait francisé le montant — « — 25 000 $ » plutôt que « - $25,000 ». La
  // composition ne redonne pas ce FR, donc elle n'y touche pas.
  const devie = [{
    file: 'poi-gtav/devie.json',
    data: { title: { en: 'Hidden Package #9 - $25,000', fr: 'Magot caché n°9 — 25 000 $' } },
  }];
  const { composables, ignores } = titresComposables(devie);

  assert.equal(composables.length, 0, 'un titre déformé ne doit jamais être composé');
  assert.equal(ignores.length, 1);
  assert.match(ignores[0].raison, /ne redonne pas le FR/, 'un écart doit DIRE pourquoi');
});

// Ces deux tests portent sur l'ÉTAT du contenu, pas sur ce qu'il resterait à
// faire. Écrits d'abord en comptant les « composables », ils sont tombés dès que
// la composition a été appliquée : ils mesuraient un état transitoire. Un test
// qui cesse d'être vrai parce que le travail a été fait ne testait pas le
// travail, il testait son absence.

test('un titre que la table SAIT décrire n’est jamais traduit autrement', () => {
  // La garantie qui survit à tout : là où la table fait autorité, rien ne la
  // contredit. Elle attrape aussi bien une table modifiée après coup qu'un ES
  // écrit à la main de travers sur un titre gabarité.
  //
  // Un titre que la table ne sait PAS décrire en est exempt, et c'est le
  // pendant du test précédent : ces titres-là partent à la rédaction, et un
  // humain a le droit d'y faire mieux qu'un gabarit — le montant localisé de
  // `Hidden Package #9` en est l'exemple.
  const fautifs = [];
  for (const { data } of poiReels()) {
    const t = data.title ?? {};
    if (!t.en || !t.es) continue;
    if (t.en === t.fr) {
      if (t.es !== t.en) fautifs.push(`${t.en} : nom propre traduit en « ${t.es} »`);
      continue;
    }
    if (composer(t.en, 'fr') !== t.fr) continue; // hors du domaine de la table
    const attendu = composer(t.en, 'es');
    if (attendu !== t.es) fautifs.push(`${t.en} : ${t.es} ≠ ${attendu}`);
  }
  assert.deepEqual(fautifs, [], `${fautifs.length} titre(s) incohérent(s) avec la table`);
});

test('ce qui reste à rédiger est borné, et nommé', () => {
  const restants = poiReels().filter(({ data }) => data.title?.en && !data.title.es);
  assert.ok(restants.length <= 70, `${restants.length} titres sans ES — la composition en a moins couvert qu'attendu`);
  // Chacun doit avoir une RAISON d'être resté, jamais être tombé au travers.
  const { ignores } = titresComposables(poiReels());
  assert.equal(ignores.length, restants.length, 'un titre sans ES doit figurer parmi les écartés, avec son motif');
});

test('un item déjà traduit n’est pas recomposé', () => {
  const dejaFait = [{ file: 'poi-gtav/x.json', data: { title: { en: 'Gas Station', fr: 'Station-service', es: 'Gasolinera', it: 'X', de: 'Y' } } }];
  assert.equal(titresComposables(dejaFait).composables.length, 0);
});

// ---------------------------------------------------------------------------
// La table elle-même
// ---------------------------------------------------------------------------

test('chaque gabarit porte les quatre langues', () => {
  for (const g of GABARITS) {
    for (const l of ['fr', 'es', 'it', 'de']) {
      assert.ok(g[l] && g[l].trim(), `« ${g.en} » n'a pas de ${l}`);
    }
  }
});
