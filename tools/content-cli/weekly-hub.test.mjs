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
  parseBonusUntil,
  parseDiscount,
  localizedName,
  localizedTitle,
  hubToFact,
  parseRewards,
} from './weekly-hub.mjs';
import { notANominativeName } from './nominative-fields.mjs';

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

// --- Verdicts de lecture de la page ---------------------------------------
//
// La page RÉELLE du 2026-08-06 à 19:00 UTC : nouveau design, et aucune semaine
// publiée — la source déclare elle-même la fin de phase. C'est l'état dans lequel
// la refonte a été découverte.
const SANS_SEMAINE = readFileSync(new URL('./fixtures/weekly-hub-sans-semaine.html', import.meta.url), 'utf8');

/** Chaque verdict s'assert sur DEUX choses : le code, et une sous-chaîne du
 *  message. Le seul code ne distingue pas « a reconnu la situation » de « a
 *  planté en chemin » — les deux lèvent. */
function verdictOf(html) {
  try {
    return { verdict: parseWeeklyHub(html).verdict, message: null };
  } catch (error) {
    return { verdict: error.verdict, message: error.message };
  }
}

test('la page qui déclare sa phase close rend « sans-semaine », pas une erreur', () => {
  const read = parseWeeklyHub(SANS_SEMAINE);
  assert.equal(read.verdict, 'sans-semaine');
  assert.match(read.declaration, /event offers still active/i);
  assert.match(read.statement, /weekly bonus phase has ended/i);
});

test('une page sans payload RSC lève en « payload-absent »', () => {
  const { verdict, message } = verdictOf('<html><body>rien</body></html>');
  assert.equal(verdict, 'payload-absent');
  assert.match(message, /payload RSC introuvable/);
});

test('un payload sans les ancres de la page lève en « page-meconnaissable »', () => {
  const { verdict, message } = verdictOf(push('["$",{"autre":{"a":1}}]'));
  assert.equal(verdict, 'page-meconnaissable');
  assert.match(message, /ancres manquantes/);
});

// LE contrôle négatif qui porte le principe. Une page reconnue dont la
// déclaration est inconnue — c'est-à-dire, aujourd'hui, une semaine VIVANTE —
// doit LEVER. La classer « pas de semaine » avalerait une semaine en silence, et
// personne ne le saurait : c'est le seul mode de panne muet de toute la chaîne.
test('une déclaration hors énumération lève, au lieu de passer pour « pas de semaine »', () => {
  const vivante = SANS_SEMAINE
    .replaceAll('GTA Online event offers still active', 'GTA Online weekly update: bonuses and discounts')
    .replaceAll('The current weekly bonus phase has ended', 'This week’s bonuses are live now');
  const { verdict, message } = verdictOf(vivante);
  assert.equal(verdict, 'declaration-inconnue');
  assert.match(message, /semaine VIVANTE/);
  assert.notEqual(verdict, 'sans-semaine');
});

// L'ancienne page — payload `hub`, ancien balisage — ne doit PAS produire un faux
// « sans-semaine » du seul fait qu'elle ne déclare rien. C'est la même garantie
// prise par l'autre bout : ni la nouvelle forme ni l'ancienne ne peuvent glisser
// dans le verdict silencieux par défaut.
test('l’ancienne page lève en « page-meconnaissable », jamais en « sans-semaine »', () => {
  const { verdict } = verdictOf(minimalPage());
  assert.equal(verdict, 'page-meconnaissable');
});

test('une page qui n’a qu’une des deux ancres n’est pas reconnue à moitié', () => {
  const uneSeule = SANS_SEMAINE.replaceAll('aria-label="Weekly event sections"', 'aria-label="Autre chose"');
  const { verdict, message } = verdictOf(uneSeule);
  assert.equal(verdict, 'page-meconnaissable');
  assert.match(message, /Weekly event sections/);
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

test('le titre composé ne reprend aucune marque', () => {
  for (const value of Object.values(localizedTitle('2026-07-30'))) {
    assert.doesNotMatch(value, /\b(GTA|Grand Theft Auto|Rockstar|Vice City|Leonida|Take-Two)\b/i, value);
  }
});

test('le bonus ne porte AUCUN texte — c’est ce qui permet à l’app d’écrire « GTA$ »', () => {
  // Un libellé dans le contenu obligerait à choisir entre « 2× GTA$ », refusé par
  // check-publishable, et « 2× argent », qui perd la désignation officielle.
  const { fact } = REAL();
  for (const bonus of fact.bonuses) {
    assert.deepEqual(Object.keys(bonus).filter((k) => k !== 'activity').sort().filter((k) => k.includes('label')), []);
    assert.ok(bonus.multiplier !== undefined || bonus.percentBonus !== undefined, JSON.stringify(bonus));
    assert.equal(typeof bonus.includesRP, 'boolean');
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

/** Instant situé DANS la fenêtre relevée (30/07 → 05/08). Injecté, jamais lu de
 *  l'horloge : sinon ce fichier de tests cesserait de passer le 6 août. */
const PENDANT_LA_SEMAINE = new Date('2026-08-02T12:00:00Z');

const REAL = (now = PENDANT_LA_SEMAINE) =>
  hubToFact({
    hub: PAYLOAD,
    articleURL: 'https://www.gtaboom.com/gta-online-summer-heist-event-july-2026',
    articleDate: '2026-07-30',
    now,
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

test('un nom qui porte une marque passe tel quel — usage référentiel', () => {
  // « GTA+ Shark Cards » de la semaine réelle. L'extracteur l'écartait, et privait
  // la carte d'un bonus réel alors que la remise du MÊME abonnement passait déjà.
  // L'exception et sa contrepartie vivent dans `nominative-fields.mjs`.
  const { fact } = REAL();
  const shark = fact.bonuses.find((b) => b.activity.en.includes('Shark Cards'));
  assert.ok(shark, 'le bonus d’abonnement doit être retenu');
  assert.equal(shark.activity.en, 'GTA+ Shark Cards');
  assert.equal(shark.percentBonus, 15);
  assert.equal(shark.multiplier, undefined);
});

test('la date de fin propre à un bonus est extraite de la prose, et seulement si elle dépasse', () => {
  assert.equal(parseBonusUntil('pays double through August 12.', '2026-08-05T23:59:59Z'), '2026-08-12');
  // La plupart des détails répètent la fin de la semaine : rien à afficher.
  assert.equal(parseBonusUntil('pays double through August 5.', '2026-08-05T23:59:59Z'), null);
  // Une semaine à cheval sur le 31 décembre : l'année vient de la fenêtre.
  assert.equal(parseBonusUntil('through January 3.', '2026-12-30T23:59:59Z'), '2027-01-03');
  assert.equal(parseBonusUntil('aucune date ici', '2026-08-05T23:59:59Z'), null);
  assert.equal(parseBonusUntil(null, '2026-08-05T23:59:59Z'), null);
});

test('la semaine réelle porte la seule fin de bonus qui dépasse la fenêtre', () => {
  const { fact } = REAL();
  const prolongés = fact.bonuses.filter((b) => b.until);
  assert.equal(prolongés.length, 1);
  assert.equal(prolongés[0].until, '2026-08-12');
  assert.match(prolongés[0].activity.en, /Superyacht/);
});

test('sept bonus et dix remises sont retenus, deux entrées écartées avec leur raison', () => {
  const { fact, skipped } = REAL();
  assert.equal(fact.bonuses.length, 7);
  assert.equal(fact.discounts.length, 10);
  assert.equal(skipped.length, 2);
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

test('aucun champ RÉDIGÉ ne porte de marque', () => {
  // Les noms en portent, eux, et c'est permis. Ce qui est composé par nous n'a
  // aucune raison d'en porter : `check-publishable` les scanne.
  const { fact } = REAL();
  const texts = [
    ...Object.values(fact.title),
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
    now: new Date('2026-08-08T12:00:00Z'),
  });
  assert.notEqual(week1.claim, week2.claim);
});

test('une fenêtre incohérente lève plutôt que d’afficher un compte à rebours faux', () => {
  assert.throws(
    () => hubToFact({ hub: PAYLOAD, articleURL: 'https://www.gtaboom.com/x', articleDate: '2026-09-01', now: PENDANT_LA_SEMAINE }),
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
        now: PENDANT_LA_SEMAINE,
      }),
    /ni bonus ni remise retenus/,
  );
});

test('tout nom émis tient la promesse qui lui vaut son exception', () => {
  // Sans ça, l'exception aux marques accordée par `check-publishable` reposerait
  // sur un contrat que l'extracteur ne respecte pas forcément.
  const { fact } = REAL();
  const names = [
    ...fact.bonuses.flatMap((b) => Object.values(b.activity)),
    ...fact.discounts.flatMap((d) => Object.values(d.item)),
  ];
  assert.ok(names.length > 0);
  for (const name of names) {
    assert.equal(notANominativeName(name), null, name);
  }
});

// --- Péremption du hub ----------------------------------------------------
//
// Le mode de panne le plus dangereux de la chaîne, parce qu'il ne casse rien :
// une source qui cesse de tenir son hub répond toujours 200 et s'analyse
// toujours. Sans ce contrôle, on republierait la semaine dernière indéfiniment.

test('une fenêtre déjà close est un ÉCHEC, pas une donnée', () => {
  assert.throws(() => REAL(new Date('2026-08-06T12:00:00Z')), /fenêtre déjà expirée/);
});

test('la seconde exacte de la fin est déjà trop tard', () => {
  // `endsAt <= now` et non `<` : à l'instant de la fin, il n'y a plus rien à
  // décompter, et `OnlineEvent.remaining(at:)` rendrait déjà nil côté app.
  assert.throws(() => REAL(new Date('2026-08-05T23:59:59Z')), /fenêtre déjà expirée/);
  assert.doesNotThrow(() => REAL(new Date('2026-08-05T23:59:58Z')));
});

test('now est obligatoire — un oubli ne doit pas désactiver le contrôle en silence', () => {
  assert.throws(
    () => hubToFact({ hub: PAYLOAD, articleURL: 'https://www.gtaboom.com/x', articleDate: '2026-07-30' }),
    /now est obligatoire/,
  );
  assert.throws(
    () => hubToFact({ hub: PAYLOAD, articleURL: 'https://www.gtaboom.com/x', articleDate: '2026-07-30', now: '2026-08-02' }),
    /now est obligatoire/,
  );
});

// --- Récompenses : lues dans le MARQUAGE, best-effort ---------------------
//
// Contrairement aux bonus et remises, la source ne les publie pas en JSON. Cette
// extraction est donc la partie fragile de la chaîne, et elle est traitée comme
// telle : elle ne lève jamais, et son absence n'invalide pas la semaine.

const REWARDS_HTML = readFileSync(new URL('./fixtures/weekly-hub-rewards.html', import.meta.url), 'utf8');

test('la section réelle rend ses cinq récompenses, typées', () => {
  const { rewards } = parseRewards(REWARDS_HTML);
  assert.deepEqual(
    rewards.map((r) => r.kind),
    ['challenge', 'login', 'challenge', 'vehicle', 'cash'],
  );
  assert.equal(rewards[0].item.en, 'Fleeca Circuit livery for the Übermacht Cypher');
  assert.equal(rewards[3].item.en, 'Grotti Veleno GT in Attack livery');
});

test('une carte dont la nature n’est pas au vocabulaire est écartée, avec sa raison', () => {
  // La carte « Gun Van » de la semaine réelle : pas de nature reconnue.
  const { skipped } = parseRewards(REWARDS_HTML);
  assert.equal(skipped.length, 1);
  assert.match(skipped[0].reason, /nature de récompense inconnue/);
  assert.ok(skipped[0].name);
});

test('un nom de récompense qui n’est pas un nom est écarté, pas publié', () => {
  // Sinon `check-publishable` échouerait sur la semaine ENTIÈRE, et il faudrait
  // un aller-retour manuel chaque jeudi.
  const html = `<section id="weekly-rewards"><article>
      <p data-variant="overline">login reward</p>
      <h3>Log in before August 5 to receive the sweater, then wait 72 hours.</h3>
    </article></section>`;
  const { rewards, skipped } = parseRewards(html);
  assert.equal(rewards.length, 0);
  assert.match(skipped[0].reason, /n'est pas un nom/);
});

test('tout nom de récompense émis tient la promesse de son exception', () => {
  for (const reward of parseRewards(REWARDS_HTML).rewards) {
    assert.equal(notANominativeName(reward.item.en), null, reward.item.en);
  }
});

test('l’extraction des récompenses ne lève JAMAIS', () => {
  // Une semaine perdue parce qu'un `<article>` est devenu un `<li>` coûterait
  // plus que des récompenses manquantes.
  for (const input of [null, undefined, '', '<html></html>', '<section id="weekly-rewards">', 42, {}]) {
    assert.doesNotThrow(() => parseRewards(input), String(input));
    assert.deepEqual(parseRewards(input).rewards, []);
  }
});

test('une semaine sans récompenses reste une semaine valide', () => {
  const { fact } = hubToFact({
    hub: PAYLOAD,
    articleURL: 'https://www.gtaboom.com/x',
    articleDate: '2026-07-30',
    now: PENDANT_LA_SEMAINE,
  });
  assert.deepEqual(fact.rewards, []);
  assert.ok(fact.bonuses.length > 0);
});

test('les récompenses écartées remontent au même compte-rendu que le reste', () => {
  const { skipped } = hubToFact({
    hub: PAYLOAD,
    articleURL: 'https://www.gtaboom.com/x',
    articleDate: '2026-07-30',
    now: PENDANT_LA_SEMAINE,
    rewards: [],
    rewardsSkipped: [{ name: 'Gun Van', label: null, reason: 'nature inconnue' }],
  });
  assert.ok(skipped.some((entry) => entry.name === 'Gun Van'));
});
