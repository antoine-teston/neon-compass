// Tests de la validation de soumission — reprise de
// functions/src/contribution.test.ts, à l'identique sur le fond.
//
//   deno test supabase/functions/_shared/contribution.test.ts

import { assertEquals, assertThrows } from 'jsr:@std/assert@1';
import {
  containsBannedVocabulary,
  DEDUP_THRESHOLD_NORMALIZED,
  isTooCloseToExistingSpot,
  validateSubmission,
} from './contribution.ts';

const valid = {
  category: 'landmark',
  title: '  Un spot  ',
  position_x: 0.5,
  position_y: 0.5,
  language_code: 'fr',
};

Deno.test('une soumission valide est normalisée', () => {
  const result = validateSubmission(valid);
  assertEquals(result.category, 'landmark');
  assertEquals(result.title, 'Un spot', 'le titre doit être détouré');
  assertEquals(result.positionX, 0.5);
  assertEquals(result.languageCode, 'fr');
});

Deno.test('une catégorie inconnue est refusée', () => {
  assertThrows(() => validateSubmission({ ...valid, category: 'nuclear-bunker' }));
});

Deno.test('une langue non livrée est refusée', () => {
  // Cinq langues en v1. En accepter une sixième produirait du contenu que
  // personne ne peut relire.
  assertThrows(() => validateSubmission({ ...valid, language_code: 'pt' }));
});

Deno.test('un titre vide ou trop long est refusé', () => {
  assertThrows(() => validateSubmission({ ...valid, title: '   ' }));
  assertThrows(() => validateSubmission({ ...valid, title: 'x'.repeat(281) }));
});

Deno.test('une position hors de [0,1] est refusée', () => {
  assertThrows(() => validateSubmission({ ...valid, position_x: 1.5 }));
  assertThrows(() => validateSubmission({ ...valid, position_y: -0.1 }));
});

Deno.test('les coordonnées sont deux scalaires, pas un objet imbriqué', () => {
  // Le format Firestore. L'accepter en silence écrirait une position nulle.
  assertThrows(() => validateSubmission({ ...valid, position_x: undefined, position: { x: 0.5, y: 0.5 } }));
});

Deno.test('le filtre de vocabulaire attrape les liens', () => {
  assertEquals(containsBannedVocabulary('visitez https://spam.example'), true);
  assertEquals(containsBannedVocabulary('un joli point de vue'), false);
});

Deno.test('la déduplication géographique borne au seuil', () => {
  const candidate = { x: 0.5, y: 0.5 };
  const justInside = [{ x: 0.5 + DEDUP_THRESHOLD_NORMALIZED / 2, y: 0.5 }];
  const justOutside = [{ x: 0.5 + DEDUP_THRESHOLD_NORMALIZED * 2, y: 0.5 }];

  assertEquals(isTooCloseToExistingSpot(candidate, justInside), true);
  assertEquals(isTooCloseToExistingSpot(candidate, justOutside), false);
  assertEquals(isTooCloseToExistingSpot(candidate, []), false);
});
