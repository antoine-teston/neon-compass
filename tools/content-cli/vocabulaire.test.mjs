// node --test vocabulaire.test.mjs
//
// Ces tables décident si un contrôle s'applique à un kind. Une table qui prend
// du retard sur `KINDS` ne se voit pas : le kind neuf tombe dans un défaut
// implicite au lieu d'être tranché. D'où l'exhaustivité, testée ici.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { KINDS } from './schemas.mjs';
import { CARDINALITE, CONFIANCE_ORDRE, HORS_CONTROLE } from './vocabulaire.mjs';

const ICI = dirname(fileURLToPath(import.meta.url));

test('tout kind figure dans exactement une des deux tables', () => {
  for (const kind of Object.keys(KINDS)) {
    const places = [CARDINALITE[kind] !== undefined, HORS_CONTROLE[kind] !== undefined];
    assert.equal(
      places.filter(Boolean).length,
      1,
      `kind « ${kind} » : il lui faut une cardinalité OU une exemption motivée, pas les deux ni aucune`,
    );
  }
});

test('aucune table ne cite un kind qui n’existe pas', () => {
  for (const kind of [...Object.keys(CARDINALITE), ...Object.keys(HORS_CONTROLE)]) {
    assert.ok(KINDS[kind], `kind inconnu cité dans une table : ${kind}`);
  }
});

test('une exemption dit toujours POURQUOI', () => {
  for (const [kind, raison] of Object.entries(HORS_CONTROLE)) {
    assert.ok(String(raison).length > 20, `exemption de « ${kind} » sans raison lisible`);
  }
});

test('l’échelle de confiance couvre exactement l’énumération du schéma', () => {
  // Le schéma la donne dans l'ordre INVERSE. Comparer les ensembles, pas les
  // ordres : ajouter un niveau au schéma doit faire tomber ce test plutôt que
  // de créer une comparaison muette qui rendrait toujours `false`.
  const schema = JSON.parse(
    readFileSync(join(ICI, '..', '..', 'content', 'schema', 'news.schema.json'), 'utf8'),
  );
  assert.deepEqual(
    [...CONFIANCE_ORDRE].sort(),
    [...schema.properties.confidence.enum].sort(),
  );
});

test('l’échelle va du plus faible au plus fort', () => {
  assert.equal(CONFIANCE_ORDRE[0], 'rumor');
  assert.equal(CONFIANCE_ORDRE.at(-1), 'confirmed-official');
});
