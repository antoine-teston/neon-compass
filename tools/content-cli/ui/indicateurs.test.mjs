// node --test tools/content-cli/ui/indicateurs.test.mjs
//
// Le test qui compte est celui du « ? » : un indicateur qui afficherait `0` sur
// une donnée absente ferait croire à une file vide alors qu'on n'a rien lu.
// C'est la panne que toute cette console existe pour supprimer, et un indicateur
// est l'endroit où elle serait le plus coûteuse — on le regarde justement pour
// ne PAS ouvrir l'onglet.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { OUBLI_JOURS, ancienneteEnJours, indicateurs } from './indicateurs.mjs';

const AUJOURDHUI = '2026-08-08';

const etatSain = {
  brouillons: { totaux: { attend: 3, retenu: 1, casse: 0 }, plusAncien: '2026-08-07' },
  socles: { aJour: true },
};
const metriquesSaines = {
  instantane: {
    moderation: { enAttente: 2, signales: 0, plusAncienJours: 1 },
    blocages: { fragmentsSales: false, fragmentsDepuisMinutes: 5, pushEnAttente: 0, pushCoinces: 0 },
  },
};
const reseauSain = {
  recolte: { verdict: 'complète' },
  fonctions: { derivees: [] },
  appConfig: { valeurs: { communityContributionsEnabled: true, contentBaseURL: 'https://x.test/', backendFeaturesEnabled: true } },
};

// ---------------------------------------------------------------------------
// LA règle : rien n'est jamais zéro par défaut
// ---------------------------------------------------------------------------

test('sans aucune donnée, tout dit « ? » et rien ne dit « 0 »', () => {
  const i = indicateurs({});
  assert.match(i.revue.texte, /actus \?/);
  assert.match(i.revue.texte, /contribs \?/);
  assert.equal(i.revue.niveau, 'inconnu');
  assert.match(i.veille.texte, /récolte \?/);
  assert.equal(i.pilotage.niveau, 'inconnu');
  // Et surtout : aucun zéro nulle part.
  for (const ind of Object.values(i)) {
    if (ind) assert.doesNotMatch(ind.texte, /\b0\b/, `zéro affiché sans donnée : ${ind.texte}`);
  }
});

test('une source indisponible dit POURQUOI, sans contaminer les autres', () => {
  const i = indicateurs({
    state: etatSain,
    metriques: { indisponible: 'MONITOR_TOKEN absent' },
  });
  assert.match(i.revue.texte, /3 actus/);        // celle-là a répondu
  assert.match(i.revue.texte, /contribs \?/);     // celle-là non
  assert.match(i.revue.titre, /MONITOR_TOKEN absent/);
  assert.equal(i.revue.niveau, 'inconnu');
});

test('« inconnu » n’est ni bon ni grave', () => {
  // Le teinter en vert ferait passer une panne de lecture pour une bonne
  // nouvelle ; en rouge, l'inverse. Il reste à part.
  const i = indicateurs({ state: { brouillons: { indisponible: 'content/ illisible' }, socles: { aJour: true } } });
  assert.equal(i.revue.niveau, 'inconnu');
});

// ---------------------------------------------------------------------------
// Revue
// ---------------------------------------------------------------------------

test('une file vide est une bonne nouvelle, une file pleine ne l’est pas moins', () => {
  // Une file n'est pas une alerte : treize actus à relire, c'est du travail.
  // Alerter sur le volume apprendrait à ignorer l'alerte.
  const vide = indicateurs({
    state: { brouillons: { totaux: { attend: 0 }, plusAncien: null }, socles: { aJour: true } },
    metriques: { instantane: { moderation: { enAttente: 0, signales: 0, plusAncienJours: null }, blocages: {} } },
  });
  assert.equal(vide.revue.niveau, 'bon');

  const pleine = indicateurs({ state: etatSain, metriques: metriquesSaines });
  assert.equal(pleine.revue.niveau, 'neutre');
  assert.match(pleine.revue.texte, /3 actus · 2 contribs/);
});

test('c’est l’ANCIENNETÉ qui alerte, pas le volume', () => {
  const vieux = indicateurs({
    state: { brouillons: { totaux: { attend: 1 }, plusAncien: '2026-07-01' }, socles: { aJour: true } },
    metriques: metriquesSaines,
  });
  assert.equal(vieux.revue.niveau, 'attention');
  assert.match(vieux.revue.titre, /le plus ancien depuis \d+ jours/);
});

test('une contribution SIGNALÉE alerte quel que soit le reste', () => {
  // Elle reste visible des joueurs pendant qu'elle attend, contrairement aux
  // autres : la noyer dans le total reviendrait à ne pas l'avoir marquée.
  const i = indicateurs({
    state: etatSain,
    metriques: { instantane: { moderation: { enAttente: 5, signales: 2, plusAncienJours: 0 }, blocages: {} } },
  });
  assert.equal(i.revue.niveau, 'attention');
  assert.match(i.revue.texte, /2 signalées/);
});

test('l’ancienneté se lit en date comme en jours', () => {
  assert.equal(ancienneteEnJours('2026-08-01', AUJOURDHUI), 7);
  assert.equal(ancienneteEnJours({ date: '2026-08-01', jours: 7 }), 7);
  assert.equal(ancienneteEnJours(null), null);
  assert.equal(ancienneteEnJours('pas une date', AUJOURDHUI), null);
  assert.ok(OUBLI_JOURS === 14, 'le seuil doit rester celui de la dernière tranche du graphe');
});

// ---------------------------------------------------------------------------
// Veille
// ---------------------------------------------------------------------------

test('« indéterminé » n’est PAS un succès', () => {
  // C'est ce que rend `runs.mjs` quand le journal ne prouve rien. Le teinter en
  // vert annulerait tout le travail de lecture des marqueurs positifs.
  const i = indicateurs({ reseau: { ...reseauSain, recolte: { verdict: 'indéterminé' } } });
  assert.equal(i.veille.niveau, 'attention');
});

test('une récolte partielle nomme sa nature sans son détail', () => {
  const i = indicateurs({ reseau: { ...reseauSain, recolte: { verdict: 'partielle — extraction muette' } } });
  assert.equal(i.veille.niveau, 'attention');
  assert.match(i.veille.texte, /récolte partielle/);
  assert.doesNotMatch(i.veille.texte, /muette/);      // trop long pour un onglet
  assert.match(i.veille.titre, /extraction muette/);  // mais l'infobulle l'a
});

test('un échec de récolte est grave', () => {
  assert.equal(indicateurs({ reseau: { ...reseauSain, recolte: { verdict: 'échec' } } }).veille.niveau, 'grave');
});

test('ce qui attend d’être livré s’affiche', () => {
  const i = indicateurs({ reseau: reseauSain, livraison: { changements: [1, 2, 3] } });
  assert.match(i.veille.texte, /3 à livrer/);
});

// ---------------------------------------------------------------------------
// Contrôles
// ---------------------------------------------------------------------------

test('des socles en retard sont graves', () => {
  const i = indicateurs({ state: { ...etatSain, socles: { aJour: false } } });
  assert.equal(i.controles.niveau, 'grave');
  assert.match(i.controles.titre, /rien ne le signale/);
});

test('une fonction dérivée est grave, et elle est NOMMÉE', () => {
  const i = indicateurs({ state: etatSain, reseau: { ...reseauSain, fonctions: { derivees: ['send-push'] } } });
  assert.equal(i.controles.niveau, 'grave');
  assert.match(i.controles.titre, /send-push/);
  assert.match(i.controles.titre, /ANCIENNE réponse/);
});

test('des fragments périmés et une file de push coincée remontent', () => {
  const i = indicateurs({
    state: etatSain,
    metriques: { instantane: {
      moderation: { enAttente: 0, signales: 0, plusAncienJours: null },
      blocages: { fragmentsSales: true, fragmentsDepuisMinutes: 400, pushEnAttente: 4, pushCoinces: 2 },
    } },
  });
  assert.equal(i.controles.niveau, 'grave');
  assert.match(i.controles.texte, /fragments périmés/);
  assert.match(i.controles.texte, /2 push coincé/);
});

test('des fragments sales mais RÉCENTS ne sont pas une panne', () => {
  // La reconstruction se force toutes les heures : du sale depuis cinq minutes
  // est le fonctionnement normal.
  //
  // Les trois sources sont fournies à dessein : depuis la correction du
  // 2026-08-08, « à jour » exige que les trois aient répondu. En laisser une de
  // côté ici testerait l'incertitude, pas la tolérance au sale récent.
  const i = indicateurs({
    state: etatSain,
    reseau: reseauSain,
    metriques: { instantane: {
      moderation: { enAttente: 0, signales: 0, plusAncienJours: null },
      blocages: { fragmentsSales: true, fragmentsDepuisMinutes: 5, pushEnAttente: 0, pushCoinces: 0 },
    } },
  });
  assert.equal(i.controles.niveau, 'bon');
});

// ---------------------------------------------------------------------------
// Pilotage
// ---------------------------------------------------------------------------

test('tout ouvert : l’onglet ne dit RIEN', () => {
  // Un onglet sans rien à dire ne doit pas ajouter du bruit à une barre qu'on
  // lit en diagonale.
  assert.equal(indicateurs({ reseau: reseauSain }).pilotage, null);
});

test('un interrupteur baissé se rappelle à nous', () => {
  // C'est un état VOULU, mais qu'on oublie — et l'oublier coûte une journée de
  // contributions ou de publications qui n'arrivent nulle part.
  const coupe = indicateurs({ reseau: {
    ...reseauSain,
    appConfig: { valeurs: { communityContributionsEnabled: false, contentBaseURL: 'off', backendFeaturesEnabled: true } },
  } });
  assert.equal(coupe.pilotage.niveau, 'attention');
  assert.match(coupe.pilotage.texte, /contributions coupées/);
  assert.match(coupe.pilotage.texte, /CDN coupé/);
});

test('un contentBaseURL absent vaut coupé, pas inconnu', () => {
  // Absent, l'app ne lit que son socle embarqué — c'est un fait, pas une
  // incertitude, et le taire ferait chercher longtemps pourquoi une
  // publication n'arrive nulle part.
  const i = indicateurs({ reseau: { ...reseauSain, appConfig: { valeurs: { communityContributionsEnabled: true } } } });
  assert.match(i.pilotage.texte, /CDN coupé/);
});

// ---------------------------------------------------------------------------
// L'assemblage
// ---------------------------------------------------------------------------

test('le niveau d’un onglet est le PIRE de ses morceaux', () => {
  const i = indicateurs({
    state: { brouillons: { totaux: { attend: 0 }, plusAncien: null }, socles: { aJour: false } },
    reseau: { ...reseauSain, fonctions: { derivees: [] } },
  });
  // « socles en retard » est grave, même si le reste va bien.
  assert.equal(i.controles.niveau, 'grave');
});

test('l’infobulle porte le pourquoi que l’étiquette ne peut pas dire', () => {
  const i = indicateurs({ state: etatSain, metriques: metriquesSaines, reseau: reseauSain });
  assert.ok(i.revue.titre.length > i.revue.texte.length, 'l’infobulle n’ajoute rien');
});

// ---------------------------------------------------------------------------
// « Rien à signaler » ne veut pas dire « rien vérifié »
//
// Défaut trouvé en regardant la barre, pas en lisant le code : Contrôles
// affichait « à jour » en VERT avant l'arrivée du réseau, alors qu'il n'avait
// regardé que les socles. Trois sources, une seule lue, un vert franc — le
// mensonge par omission, dans le fichier qui prétend l'interdire.
// ---------------------------------------------------------------------------

test('Contrôles ne dit « à jour » qu’une fois les TROIS sources rentrées', () => {
  const socles = { aJour: true };

  // Les socles seuls : on ne sait rien des fonctions ni des files.
  const partiel = indicateurs({ state: { ...etatSain, socles } });
  assert.equal(partiel.controles.niveau, 'inconnu');
  assert.match(partiel.controles.texte, /fonctions, files \?/);
  assert.doesNotMatch(partiel.controles.texte, /à jour/);

  // Les trois, et seulement là.
  const complet = indicateurs({ state: { ...etatSain, socles }, reseau: reseauSain, metriques: metriquesSaines });
  assert.equal(complet.controles.niveau, 'bon');
  assert.match(complet.controles.texte, /à jour/);
  assert.match(complet.controles.titre, /les trois ont répondu/);
});

test('une panne trouvée passe devant une source muette', () => {
  // Savoir que les socles sont en retard reste utile même si les fonctions
  // n'ont pas répondu : taire la panne pour cause d'incertitude serait pire.
  const i = indicateurs({ state: { ...etatSain, socles: { aJour: false } } });
  assert.equal(i.controles.niveau, 'grave');
  assert.match(i.controles.texte, /^socles en retard/);
  assert.match(i.controles.texte, /fonctions, files \?/);
});
