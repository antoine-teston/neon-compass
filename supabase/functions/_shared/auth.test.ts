// Tests du corps d'erreur commun.
//
//   deno test supabase/functions/_shared/auth.test.ts
//
// `serveJSON` n'est pas testé ici : il appelle `Deno.serve`, donc le vérifier
// demanderait de lever un serveur. Ce qui compte pour le client est le corps
// JSON, et c'est lui qu'on isole.

import { assertEquals } from 'jsr:@std/assert@1';
import { errorBody, HttpError } from './auth.ts';

Deno.test('un refus sans code ne rend que son message', () => {
  // Le contrat des fonctions qui n'ont pas été converties : elles ne doivent
  // pas voir leur réponse changer de forme.
  assertEquals(errorBody(new HttpError(500, 'Internal error.')), { error: 'Internal error.' });
});

Deno.test('un refus codé rend son code', () => {
  assertEquals(
    errorBody(new HttpError(409, 'A spot of this category already exists nearby.', 'duplicate')),
    { error: 'A spot of this category already exists nearby.', code: 'duplicate' },
  );
});

Deno.test('un cooldown rend ses secondes en clair', () => {
  // Le point de tout l'ajout : le client ne doit pas avoir à repêcher « 42 »
  // dans une phrase anglaise.
  assertEquals(
    errorBody(new HttpError(429, 'Please wait before submitting again (42s).', 'cooldown', 42)),
    { error: 'Please wait before submitting again (42s).', code: 'cooldown', retryAfter: 42 },
  );
});

Deno.test('un cooldown de zéro seconde reste sérialisé', () => {
  // Piège classique du `if (error.retryAfter)` : zéro est falsy, et l'omettre
  // ferait retomber le client sur son repli de 60 s alors que le serveur vient
  // de dire que l'attente est finie.
  assertEquals(errorBody(new HttpError(429, 'Wait.', 'cooldown', 0)).retryAfter, 0);
});
