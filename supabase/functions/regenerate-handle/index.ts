// Régénération du pseudonyme — portage de functions/src/regenerateHandle.ts.
//
// La génération elle-même vit en SQL (`public.generate_handle()`), pas ici :
// c'est le trigger d'inscription qui l'appelle en premier, et deux
// implémentations du même tirage — l'une en TypeScript pour la Function,
// l'autre pour le trigger — auraient dérivé. Les listes de mots sont
// originales, à thème synthwave, jamais un terme Rockstar/GTA.

import { adminClient, HttpError, requireUser, serveJSON } from '../_shared/auth.ts';

serveJSON(async (request) => {
  const uid = await requireUser(request);
  const admin = adminClient();

  // `handle` est unique : une collision sur 6 400 combinaisons est rare mais
  // certaine à l'échelle. On réessaie, plutôt que de rendre une erreur que
  // l'utilisateur ne saurait pas interpréter — il a juste demandé un autre nom.
  for (let attempt = 0; attempt < 10; attempt++) {
    const { data: candidate, error: generateError } = await admin.rpc('generate_handle');
    if (generateError) throw generateError;

    const { error: updateError } = await admin
      .from('profiles')
      .update({ handle: candidate })
      .eq('uid', uid);

    if (!updateError) return { handle: candidate };
    // 23505 = unique_violation. Toute autre erreur est réelle et remonte.
    if (updateError.code !== '23505') throw updateError;
  }

  throw new HttpError(503, 'Could not allocate a handle, please try again.');
});
