// node --test refus.test.mjs
//
// Le registre porte des décisions ÉDITORIALES. Un registre qu'on ne sait pas
// lire ne vaut pas un registre vide : se dégrader en « aucun refus » ferait
// revenir en silence tout ce qui a été écarté. D'où le test du fichier illisible.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { inscrireRefus, lireRefus } from './refus.mjs';
import { cleDeRefus, confianceSuperieure } from './vocabulaire.mjs';

const tmp = () => join(mkdtempSync(join(tmpdir(), 'refus-')), 'refus.json');

test('un registre absent est un registre vide', () => {
  assert.deepEqual(lireRefus(tmp()), {});
});

test('un registre illisible LÈVE, il ne se dégrade pas en vide', () => {
  const chemin = tmp();
  writeFileSync(chemin, '{ ceci n’est pas du JSON');
  assert.throws(() => lireRefus(chemin), /illisible/);
});

test('un registre qui n’est pas un objet est refusé', () => {
  const chemin = tmp();
  writeFileSync(chemin, '["une", "liste"]');
  assert.throws(() => lireRefus(chemin), /malformé/);
});

test('la clé n’emprunte rien au claim', () => {
  // C'est tout le point : `processedFrom` contient le claim rédigé, donc une
  // reformulation aurait ressuscité l'entrée écartée.
  assert.equal(cleDeRefus('news', 'https://x.test/a'), 'news|https://x.test/a');
});

test('un refus est inscrit pour CHAQUE source de l’entrée', () => {
  const chemin = tmp();
  const registre = inscrireRefus(chemin, {
    kind: 'news',
    sources: ['https://x.test/a', 'https://y.test/b'],
    motif: 'rumeur non confirmée',
    entree: 'news_abc',
    confiance: 'rumor',
    le: '2026-08-09',
  });
  assert.equal(Object.keys(registre).length, 2);
  assert.equal(registre['news|https://x.test/a'].motif, 'rumeur non confirmée');
  assert.equal(registre['news|https://y.test/b'].entree, 'news_abc');
  assert.deepEqual(lireRefus(chemin), registre, 'ce qui est rendu doit être ce qui est écrit');
});

test('inscrire n’écrase pas les refus déjà là', () => {
  const chemin = tmp();
  inscrireRefus(chemin, { kind: 'news', sources: ['https://x.test/a'], motif: 'm1', entree: 'news_1', confiance: 'rumor', le: '2026-08-01' });
  const registre = inscrireRefus(chemin, { kind: 'news', sources: ['https://x.test/b'], motif: 'm2', entree: 'news_2', confiance: 'rumor', le: '2026-08-02' });
  assert.equal(Object.keys(registre).length, 2);
});

test('la levée exige une confiance STRICTEMENT supérieure', () => {
  assert.equal(confianceSuperieure('multi-source', 'rumor'), true);
  assert.equal(confianceSuperieure('rumor', 'rumor'), false, 'égale ne lève pas');
  assert.equal(confianceSuperieure('rumor', 'multi-source'), false, 'inférieure ne lève pas');
  assert.equal(confianceSuperieure('confirmed-official', 'multi-source'), true);
});

test('une confiance inconnue ne lève JAMAIS', () => {
  // Dans le doute, le refus tient. Un contrôle qui approuve quand il ne sait pas
  // n'est pas un contrôle.
  assert.equal(confianceSuperieure('inventée', 'rumor'), false);
  assert.equal(confianceSuperieure('confirmed-official', 'inventée'), false);
});
