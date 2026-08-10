// node --test traduction.test.mjs
//
// Ce module ne traduit pas — il prépare le travail et range le résultat. Ses
// tests portent donc presque tous sur ce qu'il REFUSE : un rattrapage rejoué par
// mégarde ne doit pas écraser une traduction qu'un humain a corrigée à la main,
// et un lot dont un seul item est fautif ne doit rien écrire du tout.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { LANGS_CIBLES, appliquer, problemesDeTraduction, travailATraduire } from './traduction.mjs';

const item = (file, data) => ({ kind: file.split('/')[0], file, data });

const actu = (surcharge = {}) => item('news/news_aaaaaaaa.json', {
  id: 'news_aaaaaaaa',
  title: { en: 'A title', fr: 'Un titre' },
  body: { en: 'A body', fr: 'Un corps' },
  ...surcharge,
});

// ---------------------------------------------------------------------------
// Le travail à faire
// ---------------------------------------------------------------------------

test('le travail ne liste que les champs dont une langue manque', () => {
  const travail = travailATraduire([actu()]);
  assert.deepEqual(Object.keys(travail), ['news/news_aaaaaaaa.json']);
  assert.deepEqual(Object.keys(travail['news/news_aaaaaaaa.json']).sort(), ['body', 'title']);
});

test('un item déjà complet ne donne aucun travail', () => {
  const complet = actu({
    title: { en: 'A', fr: 'B', es: 'C', it: 'D', de: 'E' },
    body: { en: 'A', fr: 'B', es: 'C', it: 'D', de: 'E' },
  });
  assert.deepEqual(travailATraduire([complet]), {});
});

test('le travail porte le EN et le FR, pas seulement le EN', () => {
  // Deux formulations lèvent une ambiguïté qu'une seule laisserait : un titre
  // d'actu tient en huit mots, et l'anglais seul peut être ambigu là où le
  // français tranche.
  const champ = travailATraduire([actu()])['news/news_aaaaaaaa.json'].title;
  assert.equal(champ.en, 'A title');
  assert.equal(champ.fr, 'Un titre');
});

test('une langue déjà présente ne redemande pas de travail pour elle seule', () => {
  const partiel = actu({ title: { en: 'A', fr: 'B', es: 'C' } });
  const travail = travailATraduire([partiel]);
  // `title` reste à faire — il manque it et de — mais le travail ne se compte
  // pas en champs terminés.
  assert.ok(travail['news/news_aaaaaaaa.json'].title);
});

test('le kind et la limite bornent le travail', () => {
  const entrees = [actu(), item('cheats/cheat_x.json', { id: 'cheat_x', effect: { en: 'E', fr: 'F' } })];
  assert.deepEqual(Object.keys(travailATraduire(entrees, { kind: 'cheats' })), ['cheats/cheat_x.json']);
  assert.equal(Object.keys(travailATraduire(entrees, { limite: 1 })).length, 1);
});

// ---------------------------------------------------------------------------
// Ce que l'application REFUSE
// ---------------------------------------------------------------------------

const charge = (surcharge = {}) => ({
  'news/news_aaaaaaaa.json': { title: { es: 'Es', it: 'It', de: 'De' }, ...surcharge },
});

test('un lot valide ne pose aucun problème', () => {
  assert.deepEqual(problemesDeTraduction([actu()], charge()), []);
});

test('un item inexistant est refusé, et nommé', () => {
  const p = problemesDeTraduction([actu()], { 'news/inconnu.json': { title: { es: 'x' } } });
  assert.equal(p.length, 1);
  assert.match(p[0], /news\/inconnu\.json/);
});

test('un champ hors de UI_FIELDS est refusé', () => {
  // On ne crée pas un champ localisé que le schéma ne connaît pas.
  const p = problemesDeTraduction([actu()], { 'news/news_aaaaaaaa.json': { inventé: { es: 'x' } } });
  assert.equal(p.length, 1);
  assert.match(p[0], /inventé/);
});

test('une langue hors des cibles est refusée', () => {
  // `en` et `fr` s'écrivent à la rédaction, jamais par un rattrapage.
  const p = problemesDeTraduction([actu()], { 'news/news_aaaaaaaa.json': { title: { en: 'écrasé' } } });
  assert.equal(p.length, 1);
  assert.match(p[0], /en/);
});

test('une valeur vide ou non-chaîne est refusée', () => {
  assert.equal(problemesDeTraduction([actu()], { 'news/news_aaaaaaaa.json': { title: { es: '  ' } } }).length, 1);
  assert.equal(problemesDeTraduction([actu()], { 'news/news_aaaaaaaa.json': { title: { es: 42 } } }).length, 1);
});

test('écraser une valeur DÉJÀ présente est refusé, sauf --force', () => {
  // Le refus qui compte : un rattrapage rejoué ne doit pas effacer une
  // traduction qu'un humain a corrigée à la main.
  const dejaTraduit = actu({ title: { en: 'A', fr: 'B', es: 'corrigé à la main' } });
  const p = problemesDeTraduction([dejaTraduit], charge());
  assert.equal(p.length, 1);
  assert.match(p[0], /existe déjà/);
  assert.deepEqual(problemesDeTraduction([dejaTraduit], charge(), { force: true }), []);
});

test('un champ absent de l’item est refusé', () => {
  const sansCorps = actu({ body: undefined });
  const p = problemesDeTraduction([sansCorps], { 'news/news_aaaaaaaa.json': { body: { es: 'x' } } });
  assert.equal(p.length, 1);
});

// ---------------------------------------------------------------------------
// L'application elle-même
// ---------------------------------------------------------------------------

test('appliquer écrit les trois langues sans toucher au reste', () => {
  const [ecriture] = appliquer([actu()], charge());
  assert.equal(ecriture.file, 'news/news_aaaaaaaa.json');
  assert.deepEqual(ecriture.data.title, { en: 'A title', fr: 'Un titre', es: 'Es', it: 'It', de: 'De' });
  assert.deepEqual(ecriture.data.body, { en: 'A body', fr: 'Un corps' }, 'le champ non visé ne bouge pas');
});

test('appliquer ne rend que les items réellement touchés', () => {
  const autre = item('news/news_bbbbbbbb.json', { id: 'news_bbbbbbbb', title: { en: 'X', fr: 'Y' } });
  const ecritures = appliquer([actu(), autre], charge());
  assert.equal(ecritures.length, 1);
});

test('les langues cibles sont exactement es, it, de', () => {
  // `en` est la base, `fr` s'écrit à la rédaction. Si cette liste bouge, tout
  // ce fichier doit être relu.
  assert.deepEqual([...LANGS_CIBLES], ['es', 'it', 'de']);
});
