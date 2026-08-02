import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  MAX_NAME_WORDS,
  notANominativeName,
  nominativeFieldsFor,
  nominativeListFieldsFor,
  redactedListFieldsFor,
} from './nominative-fields.mjs';

// Ce garde-fou porte DEUX exceptions à lui seul : celle de `check-publishable`
// aux marques déposées, et celle de `check-originality` aux reprises littérales.
// Les deux ne valent que par lui. C'est le fichier le plus testé du lot pour
// cette raison.

test('un nom propre passe, marque comprise', () => {
  for (const name of [
    'Fleeca Heist Finale',
    'Karin Kuruma',
    'Galaxy Super Yacht and modifications',
    'Hao’s Special Works conversions (abonnés)',
    // L'usage référentiel : nommer le produit d'un tiers pour en parler.
    'GTA+ Shark Cards',
    'Rockstar Editor',
    'Vice City Business Park',
  ]) {
    assert.equal(notANominativeName(name), null, name);
  }
});

test('une marque NUE ne désigne aucun produit — refusée', () => {
  // C'est la limite de l'usage référentiel : « GTA » tout seul ne nomme rien,
  // il ne fait que porter la marque.
  for (const bare of ['GTA', 'Rockstar', 'Grand Theft Auto', 'gta', '  Take-Two  ', 'GTA — Rockstar']) {
    assert.match(notANominativeName(bare) ?? '', /MARQUE NUE/, bare);
  }
});

test('une phrase ne passe pas pour un nom', () => {
  assert.match(
    notANominativeName('The Galaxy Super Yacht and all of its modifications are discounted.') ?? '',
    /PONCTUATION DE PHRASE/,
  );
  assert.match(notANominativeName('gains doublés : cette semaine seulement') ?? '', /PONCTUATION DE PHRASE/);
});

test('un nom trop long est une description déguisée', () => {
  const long = Array.from({ length: MAX_NAME_WORDS + 1 }, (_, i) => `mot${i}`).join(' ');
  assert.match(notANominativeName(long) ?? '', new RegExp(`${MAX_NAME_WORDS + 1} mots`));
  const limite = Array.from({ length: MAX_NAME_WORDS }, (_, i) => `mot${i}`).join(' ');
  assert.equal(notANominativeName(limite), null);
});

test('une valeur vide ou non textuelle est refusée', () => {
  for (const bad of ['', '   ', null, undefined, 42, {}]) {
    assert.match(notANominativeName(bad) ?? '', /valeur vide/, JSON.stringify(bad));
  }
});

test('les listes de champs sont vides pour un kind qui n’en déclare pas', () => {
  for (const kind of ['poi', 'news', 'cheats']) {
    assert.deepEqual(nominativeFieldsFor(kind), []);
    assert.deepEqual(nominativeListFieldsFor(kind), []);
    assert.deepEqual(redactedListFieldsFor(kind), []);
  }
});

test('un champ n’est jamais à la fois nominatif et rédigé', () => {
  // Sinon l'exception aux marques et le contrôle de reprise s'appliqueraient tous
  // deux au même champ, avec des exigences contradictoires.
  for (const kind of ['online-events']) {
    const nominative = new Set(nominativeListFieldsFor(kind).map(([l, t]) => `${l}.${t}`));
    for (const [listField, textField] of redactedListFieldsFor(kind)) {
      assert.ok(!nominative.has(`${listField}.${textField}`), `${listField}.${textField}`);
    }
  }
});
