// Tests de l'agrégation.
//
//   deno test supabase/functions/metrics/aggregate.test.ts
//
// Le test qui compte est le dernier : `fuitesDe` sur un instantané complet. Tous
// les autres vérifient des décomptes ; celui-là vérifie la PROMESSE de la porte
// — qu'un pseudonyme ne peut pas en sortir. Une promesse qu'on n'exerce pas est
// indiscernable d'une promesse tenue.

import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  ageEnJours,
  assembler,
  type Brut,
  flux,
  fuitesDe,
  minutesDepuis,
  parCategorie,
  parTranche,
  TRANCHES,
} from './aggregate.ts';

const MIDI = Date.parse('2026-08-08T12:00:00Z');

/** Un brut minimal, que chaque test surcharge sur le seul champ qui l'intéresse. */
function brutVide(): Brut {
  return {
    attente: [],
    arrivees: [],
    approbations: [],
    bundle: null,
    push: [],
    totaux: { profils: 0, approuvees: 0, rejetees: 0, votes: 0, signalements: 0 },
  };
}

// ---------------------------------------------------------------------------
// Âges et tranches
// ---------------------------------------------------------------------------

Deno.test('un dépôt du jour a zéro jour', () => {
  assertEquals(ageEnJours('2026-08-08T23:59:00Z', '2026-08-08'), 0);
});

Deno.test('une date future ne rend jamais un âge négatif', () => {
  // Horloge décalée, import manuel : un « -3 jours » dans un graphe d'ancienneté
  // est un non-sens qu'on préfère écraser à zéro.
  assertEquals(ageEnJours('2026-08-20T00:00:00Z', '2026-08-08'), 0);
});

Deno.test('les tranches rangent aux bornes exactes', () => {
  // Les bornes sont ce qui casse : 3 appartient à « 1 à 3 j », 4 à la suivante.
  assertEquals(parTranche([0, 1, 3, 4, 7, 8, 14, 15, 400]), [1, 2, 2, 2, 2]);
});

Deno.test('les tranches sont celles de l’atelier des brouillons', () => {
  // Dupliquées de `ui/drafts.mjs` parce qu'elles traversent Deno/Node. Ce test
  // est le seul endroit où la duplication se remarquerait si elle divergeait.
  assertEquals(TRANCHES.map((t) => t.label), [
    "aujourd'hui",
    '1 à 3 j',
    '4 à 7 j',
    '8 à 14 j',
    'plus de 14 j',
  ]);
});

// ---------------------------------------------------------------------------
// Flux
// ---------------------------------------------------------------------------

Deno.test('le flux garde les jours vides', () => {
  // La raison d'être du graphe : trois contributions en trois semaines et trois
  // contributions en un jour ne doivent pas dessiner la même ligne.
  const jours = flux(['2026-08-08T09:00:00Z'], [], '2026-08-08');
  assertEquals(jours.length, 30);
  assertEquals(jours.at(-1), { jour: '2026-08-08', arrivees: 1, approbations: 0 });
  assertEquals(jours[0], { jour: '2026-07-10', arrivees: 0, approbations: 0 });
});

Deno.test('le flux compte arrivées et approbations séparément', () => {
  const jours = flux(
    ['2026-08-07T01:00:00Z', '2026-08-07T22:00:00Z'],
    ['2026-08-08T08:00:00Z'],
    '2026-08-08',
  );
  assertEquals(jours.at(-2), { jour: '2026-08-07', arrivees: 2, approbations: 0 });
  assertEquals(jours.at(-1), { jour: '2026-08-08', arrivees: 0, approbations: 1 });
});

Deno.test('le flux ignore ce qui tombe hors fenêtre', () => {
  const jours = flux(['2020-01-01T00:00:00Z'], [], '2026-08-08');
  assertEquals(jours.reduce((n, j) => n + j.arrivees, 0), 0);
});

// ---------------------------------------------------------------------------
// Blocages
// ---------------------------------------------------------------------------

Deno.test('« jamais construit » n’est pas « construit il y a zéro minute »', () => {
  // La confusion exacte qui fait passer une panne pour un succès.
  assertEquals(minutesDepuis(null, MIDI), null);
  assertEquals(minutesDepuis('2026-08-08T12:00:00Z', MIDI), 0);
});

Deno.test('une file de push coincée se distingue d’une file lente', () => {
  const instantane = assembler(
    {
      ...brutVide(),
      push: [
        { created_at: '2026-08-08T11:00:00Z', sent_at: null, attempts: 0 },
        { created_at: '2026-08-08T10:00:00Z', sent_at: null, attempts: 5 },
      ],
    },
    '2026-08-08',
    MIDI,
  );
  assertEquals(instantane.blocages.pushEnAttente, 2);
  assertEquals(instantane.blocages.pushCoinces, 1);
  assertEquals(instantane.blocages.pushPlusAncienMinutes, 120);
});

// ---------------------------------------------------------------------------
// Modération
// ---------------------------------------------------------------------------

Deno.test('une file vide n’a pas de « plus ancien »', () => {
  // `0` décrirait une file qui vient de recevoir quelque chose. `null` dit
  // qu'il n'y a rien, et le graphe le tait au lieu d'afficher un zéro.
  assertEquals(assembler(brutVide(), '2026-08-08', MIDI).moderation.plusAncienJours, null);
});

Deno.test('les signalés sont comptés à part sans quitter la file', () => {
  const instantane = assembler(
    {
      ...brutVide(),
      attente: [
        { created_at: '2026-08-01T00:00:00Z', category: 'landmark', flagged_for_review: true },
        { created_at: '2026-08-08T00:00:00Z', category: 'vehicle', flagged_for_review: false },
      ],
    },
    '2026-08-08',
    MIDI,
  );
  assertEquals(instantane.moderation.enAttente, 2);
  assertEquals(instantane.moderation.signales, 1);
  assertEquals(instantane.moderation.plusAncienJours, 7);
});

Deno.test('toutes les catégories sont présentes, même à zéro', () => {
  // Sinon les colonnes du graphe changeraient de place d'un rafraîchissement à
  // l'autre, ce qui rend toute comparaison visuelle fausse.
  const compte = parCategorie(['vehicle']);
  assertEquals(Object.keys(compte).length, 6);
  assertEquals(compte.vehicle, 1);
  assertEquals(compte.landmark, 0);
});

Deno.test('une catégorie inconnue apparaît plutôt que de disparaître', () => {
  // Un schéma qui a bougé sans que ce fichier le sache : la voir dans le graphe
  // est le seul signal qu'on aura.
  assertEquals(parCategorie(['heliport']).heliport, 1);
});

// ---------------------------------------------------------------------------
// LA promesse
// ---------------------------------------------------------------------------

Deno.test('l’instantané ne contient AUCUN nominatif', () => {
  const instantane = assembler(
    {
      attente: [
        { created_at: '2026-08-01T00:00:00Z', category: 'landmark', flagged_for_review: true },
      ],
      arrivees: ['2026-08-01T00:00:00Z'],
      approbations: ['2026-08-02T00:00:00Z'],
      bundle: { dirty: true, built_at: '2026-08-08T10:00:00Z' },
      push: [{ created_at: '2026-08-08T11:00:00Z', sent_at: null, attempts: 1 }],
      totaux: { profils: 12, approuvees: 40, rejetees: 3, votes: 91, signalements: 2 },
    },
    '2026-08-08',
    MIDI,
  );
  assertEquals(fuitesDe(instantane), []);
});

Deno.test('le détecteur de fuite sait échouer', () => {
  // Un contrôle qui ne sait qu'approuver est indiscernable d'un bon. Celui-ci
  // doit attraper précisément ce qu'on redoute : un pseudonyme.
  const fuites = fuitesDe({ moderation: { premier: { authorHandle: 'NeonRider' } } });
  assertEquals(fuites, ['moderation.premier.authorHandle = "NeonRider"']);
  // Et il ne doit pas se laisser berner par un tableau.
  assert(fuitesDe({ files: [{ title: 'Un titre' }] }).length === 1);
});
