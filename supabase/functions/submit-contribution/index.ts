// Soumission d'un spot — portage de functions/src/submitContribution.ts.
//
// La seule des trois écritures communautaires à rester une Edge Function : voter
// et signaler sont devenus des RPC Postgres, parce qu'ils ne font que valider et
// écrire. Celle-ci lit le coupe-circuit, applique le cooldown, filtre le
// vocabulaire et déduplique géographiquement — assez de logique pour mériter un
// vrai langage.

import { adminClient, HttpError, requireUser, serveJSON } from '../_shared/auth.ts';
import {
  containsBannedVocabulary,
  COOLDOWN_SECONDS,
  isTooCloseToExistingSpot,
  validateSubmission,
} from '../_shared/contribution.ts';

serveJSON(async (request) => {
  const uid = await requireUser(request);
  const admin = adminClient();

  // Le coupe-circuit est appliqué ICI, et c'est le seul point d'application qui
  // compte : le bouton masqué côté client est un confort d'interface, pas une
  // frontière de sécurité. Défaut OUVERT — une ligne absente laisse passer, la
  // même sémantique que côté app.
  const { data: gate } = await admin
    .from('app_config')
    .select('value')
    .eq('key', 'communityContributionsEnabled')
    .maybeSingle();
  if (gate?.value === false) {
    throw new HttpError(503, 'Community contributions are temporarily disabled.');
  }

  let input;
  try {
    input = validateSubmission(await request.json());
  } catch (error) {
    throw new HttpError(400, error instanceof Error ? error.message : 'Invalid submission.');
  }

  // Le profil existe forcément : il est créé par un trigger, dans la même
  // transaction que le compte. La fenêtre « Profile not ready yet » que
  // documentait submitContribution.ts — conséquence d'un déclencheur
  // d'authentification asynchrone — n'existe plus.
  const { data: profile, error: profileError } = await admin
    .from('profiles')
    .select('handle,is_shadow_banned,last_submission_at')
    .eq('uid', uid)
    .single();
  if (profileError || !profile) throw new HttpError(500, 'Profile unavailable.');

  // Cooldown de l'ordre de la minute. Pas de plafond journalier ni de limite de
  // contributions en attente : un contributeur légitime prolifique ne doit
  // jamais être bridé, c'est la ressource la plus précieuse au pic de sortie.
  if (profile.last_submission_at) {
    const elapsed = (Date.now() - new Date(profile.last_submission_at).getTime()) / 1000;
    if (elapsed < COOLDOWN_SECONDS) {
      throw new HttpError(429, `Please wait before submitting again (${Math.ceil(COOLDOWN_SECONDS - elapsed)}s).`);
    }
  }

  if (containsBannedVocabulary(input.title)) {
    throw new HttpError(400, 'Submission contains disallowed content.');
  }

  // Déduplication géographique. La requête est bornée à la catégorie ET aux
  // spots approuvés — c'est l'index partiel `contributions_public_idx` qui la
  // sert, là où Firestore lisait la collection entière et payait chaque
  // document.
  const { data: nearby, error: nearbyError } = await admin
    .from('contributions')
    .select('position_x,position_y')
    .eq('status', 'approved')
    .eq('category', input.category);
  if (nearbyError) throw nearbyError;

  const existing = (nearby ?? []).map((row) => ({ x: row.position_x, y: row.position_y }));
  if (isTooCloseToExistingSpot({ x: input.positionX, y: input.positionY }, existing)) {
    throw new HttpError(409, 'A spot of this category already exists nearby.');
  }

  const { data: inserted, error: insertError } = await admin
    .from('contributions')
    .insert({
      author_uid: uid,
      author_handle: profile.handle,
      category: input.category,
      title: input.title,
      language_code: input.languageCode,
      position_x: input.positionX,
      position_y: input.positionY,
      status: 'pending',
      // Un auteur shadow-banni voit ses soumissions masquées dès l'écriture.
      // Il ne le sait pas, et c'est le principe.
      shadow_hidden: profile.is_shadow_banned === true,
    })
    .select('id')
    .single();
  if (insertError) throw insertError;

  const { error: touchError } = await admin
    .from('profiles')
    .update({ last_submission_at: new Date().toISOString() })
    .eq('uid', uid);
  if (touchError) throw touchError;

  return { id: inserted.id };
});
