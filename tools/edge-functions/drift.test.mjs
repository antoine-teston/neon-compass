import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { classify, dependsOnShared, latestCommit, normalizeDeployedAt, report } from './drift.mjs';

test('une fonction qui importe _shared en dépend', () => {
  // Le cas RÉEL du 05/08 : `_shared/auth.ts` gagne un champ, et les six
  // fonctions qui l'importent sont périmées d'un coup sans qu'aucun de leurs
  // dossiers n'ait bougé.
  assert.equal(dependsOnShared("import { serveJSON } from '../_shared/auth.ts';"), true);
  assert.equal(dependsOnShared("import { createClient } from 'jsr:@supabase/supabase-js@2';"), false);
});

test('la date retenue est la plus récente, les absentes ignorées', () => {
  assert.equal(
    latestCommit('2026-08-01T10:00:00Z', '2026-08-04T09:00:00Z'),
    new Date('2026-08-04T09:00:00Z').toISOString()
  );
  assert.equal(latestCommit(null, '2026-08-01T10:00:00Z'), new Date('2026-08-01T10:00:00Z').toISOString());
  assert.equal(latestCommit(null, undefined), null);
  assert.equal(latestCommit('pas une date'), null);
});

test('une source plus récente que le déploiement est une dérive', () => {
  assert.equal(classify({ commit: '2026-08-04T09:00:00Z', deployedAt: '2026-08-02T09:00:00Z' }), 'dérivée');
  assert.equal(classify({ commit: '2026-08-02T09:00:00Z', deployedAt: '2026-08-04T09:00:00Z' }), 'à jour');
});

test('à égalité de date, on ne déclare PAS la dérive', () => {
  // Le déploiement suit toujours son commit : des dates égales signifient qu'on
  // vient de déployer, pas qu'on a oublié.
  assert.equal(classify({ commit: '2026-08-04T09:00:00Z', deployedAt: '2026-08-04T09:00:00Z' }), 'à jour');
});

test('une fonction jamais déployée est signalée pour ce qu’elle est', () => {
  // Distinct de « dérivée » : on ne rattrape pas un retard, on met en ligne
  // quelque chose qui n'a jamais tourné. Le lecteur du compte-rendu doit
  // pouvoir le voir.
  assert.equal(classify({ commit: '2026-08-04T09:00:00Z', deployedAt: null }), 'jamais-déployée');
});

test('un horodatage se lit en époque comme en ISO', () => {
  // L'API v1 rend des millisecondes ; rien ne garantit qu'elle s'y tienne.
  const epoch = normalizeDeployedAt(1_754_395_200_000);
  assert.equal(epoch, new Date(1_754_395_200_000).toISOString());
  assert.equal(normalizeDeployedAt('2026-08-05T12:00:00Z'), new Date('2026-08-05T12:00:00Z').toISOString());
  assert.equal(normalizeDeployedAt(null), null);
  assert.equal(normalizeDeployedAt('n’importe quoi'), null);
});

test('le rapport garde une ligne par fonction, dérivée ou non', () => {
  const rows = report({
    slugs: ['submit-contribution', 'send-push', 'delete-account'],
    commits: {
      'submit-contribution': '2026-08-05T12:00:00Z',
      'send-push': '2026-08-01T08:00:00Z',
      'delete-account': '2026-08-01T08:00:00Z',
    },
    deployed: {
      'submit-contribution': '2026-08-02T10:00:00Z',
      'send-push': '2026-08-03T10:00:00Z',
      // `delete-account` absente du projet.
    },
  });

  assert.deepEqual(
    rows.map((r) => [r.slug, r.state]),
    [
      ['submit-contribution', 'dérivée'],
      ['send-push', 'à jour'],
      ['delete-account', 'jamais-déployée'],
    ]
  );
});
