import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import {
  parseIds,
  appAdsTxt,
  patchProjectYml,
  patchAdUnits,
  GOOGLE_TEST_PUBLISHER,
} from './set-admob-ids.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

const VALID = {
  appId: 'ca-app-pub-1234567890123456~1234567890',
  banner: 'ca-app-pub-1234567890123456/1111111111',
  interstitial: 'ca-app-pub-1234567890123456/2222222222',
};

test('trois identifiants cohérents passent et rendent leur éditeur', () => {
  assert.equal(parseIds(VALID).publisher, '1234567890123456');
});

// Le cas qui justifie ce script : les deux formes ne diffèrent que par le
// séparateur, et les intervertir ne lève nulle part dans le SDK.
test('un App ID donné comme unité est refusé, et le message dit pourquoi', () => {
  assert.throws(
    () => parseIds({ ...VALID, banner: VALID.appId }),
    /c'est un APP ID .*séparateur.*pas une unité/,
  );
});

test('une unité donnée comme App ID est refusée, et le message dit pourquoi', () => {
  assert.throws(
    () => parseIds({ ...VALID, appId: VALID.banner }),
    /c'est une UNITÉ .*pas un App ID/,
  );
});

test('deux unités identiques sont refusées', () => {
  assert.throws(
    () => parseIds({ ...VALID, interstitial: VALID.banner }),
    /même unité/,
  );
});

test('des identifiants de comptes différents sont refusés', () => {
  assert.throws(
    () => parseIds({ ...VALID, interstitial: 'ca-app-pub-9999999999999999/2222222222' }),
    /éditeurs différents/,
  );
});

// Poser les identifiants de test en Release ne rapporterait rien tout en donnant
// l'impression que le provisioning est fait.
test("les identifiants de test de Google sont refusés en Release", () => {
  assert.throws(
    () => parseIds({
      appId: `ca-app-pub-${GOOGLE_TEST_PUBLISHER}~1458002511`,
      banner: `ca-app-pub-${GOOGLE_TEST_PUBLISHER}/2934735716`,
      interstitial: `ca-app-pub-${GOOGLE_TEST_PUBLISHER}/4411468910`,
    }),
    /identifiants de TEST/,
  );
});

test("app-ads.txt porte l'éditeur et l'autorité de Google", () => {
  assert.equal(
    appAdsTxt('1234567890123456'),
    'google.com, pub-1234567890123456, DIRECT, f08c47fec0942fa0\n',
  );
});

// Les deux tests suivants opèrent sur les fichiers RÉELS du dépôt, pas sur des
// chaînes écrites à la main : c'est la seule façon de savoir que les motifs
// collent encore après une modification de project.yml ou d'AdUnits.swift.
test('project.yml réel : le Release est posé, le Debug est intact', () => {
  const before = readFileSync(join(ROOT, 'project.yml'), 'utf8');
  const after = patchProjectYml(before, VALID.appId);

  assert.match(after, /GAD_APP_ID: "ca-app-pub-1234567890123456~1234567890"/);
  assert.doesNotMatch(after, /TODO\(ops\) : remplacer par l'App ID réel/);
  // Le Debug garde l'App ID de test — c'est lui qui empêche le trafic invalide.
  assert.match(after, /GAD_APP_ID: "ca-app-pub-3940256099942544~1458002511"/);
});

test('AdUnits.swift réel : le Release est posé, la branche Debug est intacte', () => {
  const before = readFileSync(join(ROOT, 'NeonCompass', 'Core', 'Ads', 'AdUnits.swift'), 'utf8');
  const after = patchAdUnits(before, VALID);

  assert.match(after, /static let banner = "ca-app-pub-1234567890123456\/1111111111"/);
  assert.match(after, /static let interstitial = "ca-app-pub-1234567890123456\/2222222222"/);
  // La branche Debug rend toujours les unités de test, ce qu'AdUnitsTests exige.
  assert.match(after, /#if DEBUG\n    static let banner = Test\.banner/);
  // Et les constantes de test elles-mêmes n'ont pas bougé.
  assert.match(after, /static let banner = "ca-app-pub-3940256099942544\/2934735716"/);
});
