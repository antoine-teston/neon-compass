import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  HUB_URL,
  rscFlight,
  parseWeeklyHub,
  normalizeInstant,
  resolveArticleDate,
  parseMultiplier,
  localizedMultiplier,
  parseDiscount,
  localizedName,
  localizedTitle,
  hubToFact,
} from './weekly-hub.mjs';

// Le payload RÉEL d'une semaine, relevé le 2026-08-02. C'est lui qui porte les
// cas tordus que personne n'inventerait : une entrée sans multiplicateur, un
// bonus en pourcentage plutôt qu'en multiple, une remise conditionnée à
// l'abonnement, une remise en montant fixe que le schéma ne peut pas porter.
const PAYLOAD = JSON.parse(readFileSync(new URL('./fixtures/weekly-hub-payload.json', import.meta.url), 'utf8'));

/** Reconstruit un morceau de payload RSC comme la source l'émet : un littéral JS
 *  dans un appel `self.__next_f.push`. */
function push(text) {
  return `<script>self.__next_f.push([1,${JSON.stringify(text)}])</script>`;
}

const MINIMAL_HUB = { currentPhaseEndsAt: '2026-08-05T23:59:59+00:00', bonuses: [], discounts: [] };

function minimalPage(hub = MINIMAL_HUB, { cta = true } = {}) {
  const payload = `["$","$L25",null,{"hub":${JSON.stringify(hub)},"other":1}]`;
  const link = `["$","$L24",null,{"href":"/gta-online-week-of-july-30","children":["${cta ? 'Read the news story' : 'Ailleurs'}"]}]`;
  return `<html><body>${push(link)}${push(payload)}</body></html>`;
}

// --- Recollage du payload -------------------------------------------------

test('un objet coupé en travers de deux morceaux est recollé', () => {
  const html = `${push('["$",{"hub":{"currentPhaseEndsAt":"2026-08-05T2')}${push('3:59:59+00:00","bonuses":[],"discounts":[]}}]')}`;
  const flight = rscFlight(html);
  assert.match(flight, /"currentPhaseEndsAt":"2026-08-05T23:59:59\+00:00"/);
});

test('un morceau illisible ne condamne pas les autres', () => {
  const html = `<script>self.__next_f.push([1,"pas du JSON \\u"])</script>${push('{"hub":{"currentPhaseEndsAt":"x","bonuses":[],"discounts":[]}}')}`;
  assert.match(rscFlight(html), /currentPhaseEndsAt/);
});

// --- Lecture de la page ---------------------------------------------------

test('la page rend le hub et le chemin de son article', () => {
  const { hub, articlePath } = parseWeeklyHub(minimalPage());
  assert.equal(hub.currentPhaseEndsAt, '2026-08-05T23:59:59+00:00');
  assert.equal(articlePath, '/gta-online-week-of-july-30');
});

test('une page sans payload RSC lève, en le disant', () => {
  assert.throws(() => parseWeeklyHub('<html><body>rien</body></html>'), /payload RSC introuvable/);
});

test('un payload sans clé hub lève, en le disant', () => {
  assert.throws(() => parseWeeklyHub(push('["$",{"autre":{"a":1}}]')), /clé « hub » absente/);
});

test('un hub sans fin de fenêtre lève — c’est le compte à rebours qui disparaîtrait', () => {
  const html = minimalPage({ bonuses: [], discounts: [] });
  assert.throws(() => parseWeeklyHub(html), /currentPhaseEndsAt absent/);
});

test('des bonus qui ne sont plus un tableau lèvent', () => {
  const html = minimalPage({ ...MINIMAL_HUB, bonuses: {} });
  assert.throws(() => parseWeeklyHub(html), /ne sont plus des tableaux/);
});

test('un article introuvable lève plutôt que de deviner le début de fenêtre', () => {
  assert.throws(() => parseWeeklyHub(minimalPage(MINIMAL_HUB, { cta: false })), /DÉBUT de fenêtre/);
});

// --- Horodatage et date d'article ----------------------------------------

test('un instant est normalisé sur le format qu’impose le schéma', () => {
  assert.equal(normalizeInstant('2026-08-05T23:59:59+00:00'), '2026-08-05T23:59:59Z');
  assert.match(normalizeInstant('2026-08-05T23:59:59+00:00'), /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
});

test('un décalage horaire est ramené en UTC, pas tronqué', () => {
  assert.equal(normalizeInstant('2026-08-05T18:59:59-05:00'), '2026-08-05T23:59:59Z');
});

test('un horodatage illisible lève', () => {
  assert.throws(() => normalizeInstant('jeudi prochain'), /illisible/);
});

test('la date de l’article vient du flux', () => {
  const feed = [
    { title: 'autre', link: 'https://www.gtaboom.com/autre-chose', date: '2026-07-29' },
    { title: 'semaine', link: 'https://www.gtaboom.com/gta-online-week-of-july-30', date: '2026-07-30' },
  ];
  assert.equal(resolveArticleDate('/gta-online-week-of-july-30', feed), '2026-07-30');
});

test('un article absent du flux lève — le début de fenêtre en dépend', () => {
  assert.throws(() => resolveArticleDate('/absent', [{ link: 'https://www.gtaboom.com/x', date: '2026-07-30' }]), /absent du flux/);
});

// --- Analyse des étiquettes ----------------------------------------------

test('les formes de multiplicateur relevées sur une semaine réelle sont toutes reconnues', () => {
  assert.deepEqual(parseMultiplier('2x GTA$'), { times: 2, rp: false });
  assert.deepEqual(parseMultiplier('2x GTA$ and RP'), { times: 2, rp: true });
  assert.deepEqual(parseMultiplier('3x GTA$ and RP'), { times: 3, rp: true });
  assert.deepEqual(parseMultiplier('15% bonus cash'), { percentBonus: 15, rp: false });
});

test('une entrée sans bonus chiffré n’est pas un bonus', () => {
  assert.equal(parseMultiplier(null), null);
  assert.equal(parseMultiplier('rotating art lineup'), null);
});

test('l’étiquette composée ne reprend aucune marque', () => {
  const values = [
    ...Object.values(localizedMultiplier({ times: 2, rp: true })),
    ...Object.values(localizedMultiplier({ times: 2, rp: false })),
    ...Object.values(localizedMultiplier({ percentBonus: 15, rp: false })),
    ...Object.values(localizedTitle('2026-07-30')),
  ];
  for (const value of values) {
    assert.doesNotMatch(value, /\b(GTA|Grand Theft Auto|Rockstar|Vice City|Leonida|Take-Two)\b/i, value);
  }
});

test('l’étiquette est composée dans les cinq langues', () => {
  for (const parsed of [{ times: 2, rp: true }, { times: 3, rp: false }, { percentBonus: 15, rp: false }]) {
    assert.deepEqual(Object.keys(localizedMultiplier(parsed)).sort(), ['de', 'en', 'es', 'fr', 'it']);
  }
});

test('les formes de remise relevées sur une semaine réelle sont reconnues', () => {
  assert.deepEqual(parseDiscount('60% off'), { percent: 60 });
  assert.deepEqual(parseDiscount('50% off for GTA+ members'), { percent: 50, requires: 'membership' });
});

test('une remise en montant fixe n’est pas un pourcentage', () => {
  assert.equal(parseDiscount('GTA$1,000,000 off for GTA+ members'), null);
});

test('un nom propre n’est pas traduit, une condition l’est', () => {
  assert.deepEqual(localizedName('Karin Kuruma'), { en: 'Karin Kuruma' });
  const members = localizedName('Hao’s Special Works conversions', 'membership');
  assert.equal(members.en, 'Hao’s Special Works conversions (members)');
  assert.equal(members.fr, 'Hao’s Special Works conversions (abonnés)');
  assert.deepEqual(Object.keys(members).sort(), ['de', 'en', 'es', 'fr', 'it']);
});

// --- Normalisation complète, sur le payload réel -------------------------

const REAL = () =>
  hubToFact({
    hub: PAYLOAD,
    articleURL: 'https://www.gtaboom.com/gta-online-summer-heist-event-july-2026',
    articleDate: '2026-07-30',
  });

test('la semaine réelle produit un fait complet', () => {
  const { fact } = REAL();
  assert.equal(fact.kind, 'online-event');
  assert.equal(fact.game, 'gtav');
  assert.equal(fact.starts_at, '2026-07-30T00:00:00Z');
  assert.equal(fact.ends_at, '2026-08-05T23:59:59Z');
  assert.equal(fact.source_url, HUB_URL);
  assert.equal(fact.source_date, '2026-07-30');
  assert.equal(fact.confidence, 'single-source');
});

test('un nom qui porte une marque est écarté, pas reformulé', () => {
  // « GTA+ Shark Cards » de la semaine réelle : la marque est DANS le nom. Le
  // reformuler mentirait sur ce qu'il désigne, et le laisser passer ferait
  // échouer `check-publishable` sur une entrée déjà écrite.
  const { fact, skipped } = REAL();
  assert.ok(!fact.bonuses.some((b) => /GTA/i.test(b.activity.en)));
  assert.ok(skipped.some((entry) => /marque/.test(entry.reason) && entry.name.includes('Shark Cards')));
});

test('six bonus et dix remises sont retenus, trois entrées écartées avec leur raison', () => {
  const { fact, skipped } = REAL();
  assert.equal(fact.bonuses.length, 6);
  assert.equal(fact.discounts.length, 10);
  assert.equal(skipped.length, 3);
  // Ce qui est écarté doit être NOMMÉ : une catégorie qui disparaît en silence
  // ne se remarque que des semaines plus tard.
  assert.ok(skipped.every((entry) => entry.name && entry.reason));
});

test('les remises retenues portent un pourcentage valide au schéma', () => {
  const { fact } = REAL();
  for (const discount of fact.discounts) {
    assert.ok(Number.isInteger(discount.percent) && discount.percent >= 1 && discount.percent <= 100, JSON.stringify(discount));
    assert.equal(typeof discount.item.en, 'string');
  }
});

test('la condition d’abonnement se lit sur le bien concerné', () => {
  const { fact } = REAL();
  const members = fact.discounts.filter((d) => d.item.fr?.includes('(abonnés)'));
  assert.equal(members.length, 1);
  assert.equal(members[0].percent, 50);
});

test('aucun champ affichable ne porte de marque', () => {
  const { fact } = REAL();
  const texts = [
    ...Object.values(fact.title),
    ...fact.bonuses.flatMap((b) => [...Object.values(b.label), ...Object.values(b.activity)]),
    ...fact.discounts.flatMap((d) => Object.values(d.item)),
  ];
  for (const text of texts) {
    assert.doesNotMatch(text, /\b(GTA|Grand Theft Auto|Rockstar|Vice City|Leonida|Take-Two)\b/i, text);
  }
});

test('la prose de la source est conservée comme corpus, pas comme affichage', () => {
  const { fact } = REAL();
  // Elle a le droit de citer ses marques : elle n'est jamais affichée.
  assert.match(fact.source_prose, /GTA\$/);
  assert.ok(fact.source_prose.split('\n').length >= PAYLOAD.bonuses.length);
  // Le claim, lui, est reformulé : aucune phrase de la source.
  assert.doesNotMatch(fact.claim, /GTA\$/);
});

test('le claim porte la fenêtre — sans quoi deux semaines partageraient une identité', () => {
  const { fact: week1 } = REAL();
  const { fact: week2 } = hubToFact({
    hub: { ...PAYLOAD, currentPhaseEndsAt: '2026-08-12T23:59:59+00:00' },
    articleURL: 'https://www.gtaboom.com/x',
    articleDate: '2026-08-06',
  });
  assert.notEqual(week1.claim, week2.claim);
});

test('une fenêtre incohérente lève plutôt que d’afficher un compte à rebours faux', () => {
  assert.throws(
    () => hubToFact({ hub: PAYLOAD, articleURL: 'https://www.gtaboom.com/x', articleDate: '2026-09-01' }),
    /fenêtre incohérente/,
  );
});

test('un hub dont plus aucune étiquette n’est reconnue lève', () => {
  assert.throws(
    () =>
      hubToFact({
        hub: { ...PAYLOAD, bonuses: [{ activityName: 'X', multiplierLabel: 'twice the money' }], discounts: [] },
        articleURL: 'https://www.gtaboom.com/x',
        articleDate: '2026-07-30',
      }),
    /ni bonus ni remise retenus/,
  );
});
