import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseCheats, CANONICAL_ALIASES } from './gtav-cheats.mjs';

const wiki = readFileSync(new URL('./fixtures/cheats-in-gtav.wiki', import.meta.url), 'utf8');

test('fusionne les libellés variables de la source en 36 triches canoniques', () => {
  const cheats = parseCheats(wiki);
  assert.equal(cheats.size, 36);
});

test('« Fast Running » et « Fast Run » sont la même triche', () => {
  const cheats = parseCheats(wiki);
  const entry = cheats.get('fast_run');
  assert.ok(entry, 'fast_run absent');
  assert.ok(entry.labels.length >= 2, `un seul libellé : ${entry.labels}`);
  assert.ok(entry.codes.playstation && entry.codes.pc);
});

test('« Slow Motion Aim » ne tombe pas dans « Slow Motion »', () => {
  const cheats = parseCheats(wiki);
  assert.ok(cheats.has('slow_motion'));
  assert.ok(cheats.has('slow_motion_aim'));
  assert.notDeepEqual(cheats.get('slow_motion').codes.pc, cheats.get('slow_motion_aim').codes.pc);
});

test('le téléphone couvre les 36 triches, la manette non', () => {
  const cheats = parseCheats(wiki);
  const withPhone = [...cheats.values()].filter((c) => c.codes.phone).length;
  const withPad = [...cheats.values()].filter((c) => c.codes.playstation || c.codes.xbox).length;
  assert.equal(withPhone, 36);
  assert.equal(withPad, 29);
});

test('les boutons sont normalisés en jetons du schéma', () => {
  const cheats = parseCheats(wiki);
  const allowed = new Set([
    'up', 'down', 'left', 'right',
    'cross', 'circle', 'square', 'triangle',
    'a', 'b', 'x', 'y',
    'l1', 'l2', 'r1', 'r2',
    'lb', 'lt', 'rb', 'rt',
  ]);
  for (const [key, c] of cheats) {
    for (const mode of ['playstation', 'xbox']) {
      for (const b of c.codes[mode]?.buttons ?? []) {
        assert.ok(allowed.has(b), `${key}/${mode} : jeton inconnu ${b}`);
      }
    }
  }
});

test('« X » est la croix sur PlayStation et le bouton X sur Xbox', () => {
  const cheats = parseCheats(wiki);
  const ps = [...cheats.values()].flatMap((c) => c.codes.playstation?.buttons ?? []);
  const xb = [...cheats.values()].flatMap((c) => c.codes.xbox?.buttons ?? []);
  assert.ok(ps.includes('cross'), 'aucune croix côté PlayStation');
  assert.ok(!ps.includes('a'), 'un bouton A a fui dans une séquence PlayStation');
  assert.ok(xb.includes('x'), 'aucun bouton X côté Xbox');
  assert.ok(!xb.includes('square'), 'un carré a fui dans une séquence Xbox');
});

test('le numéro de téléphone est séparé de son mnémonique', () => {
  const cheats = parseCheats(wiki);
  assert.deepEqual(cheats.get('spawn_comet').codes.phone, {
    kind: 'phone',
    number: '1-999-266-38',
    mnemonic: '1-999-COMET',
  });
});

test('le mode Réalisateur, dont le mnémonique est entre parenthèses nues, est parsé aussi', () => {
  const cheats = parseCheats(wiki);
  const phone = cheats.get('director_mode').codes.phone;
  assert.equal(phone.number, '1-999-57825368');
  assert.equal(phone.mnemonic, '1-999-LS-TALENT');
});

test('un mnémonique dont la source oublie un tiret est ramené à la forme canonique', () => {
  const cheats = parseCheats(wiki);
  // La source écrit « (1-999 HOT-HANDS) » avec une espace, là où toutes ses
  // autres entrées mettent un tiret. Effacer l'espace donnerait
  // « 1-999HOT-HANDS », que rien ne reconnaît.
  assert.equal(cheats.get('explosive_melee').codes.phone.mnemonic, '1-999-HOT-HANDS');
});

test('tous les mnémoniques respectent la forme attendue par le schéma', () => {
  const cheats = parseCheats(wiki);
  for (const [key, c] of cheats) {
    const m = c.codes.phone?.mnemonic;
    if (m) assert.match(m, /^1-999-[A-Z0-9-]+$/, `${key} : mnémonique hors forme — ${m}`);
  }
});

test('tous les numéros respectent la forme attendue par le schéma', () => {
  const cheats = parseCheats(wiki);
  for (const [key, c] of cheats) {
    const n = c.codes.phone?.number;
    if (n) assert.match(n, /^1-999-[0-9]+(-[0-9]+)*$/, `${key} : numéro hors forme — ${n}`);
  }
});

test('chaque alias canonique est réellement rencontré dans la source', () => {
  const cheats = parseCheats(wiki);
  for (const key of Object.keys(CANONICAL_ALIASES)) {
    assert.ok(cheats.has(key), `alias mort : ${key} n'apparaît nulle part dans la source`);
  }
});
