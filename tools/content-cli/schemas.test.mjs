// node --test schemas.test.mjs
//
// Ces tables decident si un controle s'applique a un kind. Une table qui prend
// du retard sur `KINDS` ne se voit pas : le kind neuf tombe dans un defaut
// implicite au lieu d'etre tranche. D'ou l'exhaustivite, testee ici.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { CARDINALITE, CONFIANCE_ORDRE, HORS_CONTROLE, KINDS } from './schemas.mjs';

const ICI = dirname(fileURLToPath(import.meta.url));

test('tout kind figure dans exactement une des deux tables', () => {
  for (const kind of Object.keys(KINDS)) {
    const places = [CARDINALITE[kind] !== undefined, HORS_CONTROLE[kind] !== undefined];
    assert.equal(
      places.filter(Boolean).length,
      1,
      `kind ${kind} : il lui faut une cardinalite OU une exemption motivee, pas les deux ni aucune`,
    );
  }
});

test('aucune table ne cite un kind qui n\'existe pas', () => {
  for (const kind of [...Object.keys(CARDINALITE), ...Object.keys(HORS_CONTROLE)]) {
    assert.ok(KINDS[kind], `kind inconnu cite dans une table : ${kind}`);
  }
});

test('une exemption dit toujours POURQUOI', () => {
  for (const [kind, raison] of Object.entries(HORS_CONTROLE)) {
    assert.ok(String(raison).length > 20, `exemption de ${kind} sans raison lisible`);
  }
});

test('l\'echelle de confiance couvre exactement l\'enumeration du schema', () => {
  // Le schema la donne dans l'ordre INVERSE. Comparer les ensembles, pas les
  // ordres : ajouter un niveau au schema doit faire tomber ce test plutot que
  // de creer une comparaison muette qui rendrait toujours `false`.
  const schema = JSON.parse(
    readFileSync(join(ICI, '..', '..', 'content', 'schema', 'news.schema.json'), 'utf8'),
  );
  assert.deepEqual(
    [...CONFIANCE_ORDRE].sort(),
    [...schema.properties.confidence.enum].sort(),
  );
});

test('l\'echelle va du plus faible au plus fort', () => {
  assert.equal(CONFIANCE_ORDRE[0], 'rumor');
  assert.equal(CONFIANCE_ORDRE.at(-1), 'confirmed-official');
});
