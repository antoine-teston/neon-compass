// Suppression de compte — portage de functions/src/deleteAccount.ts.
//
// Apple l'exige dès qu'une app permet de créer un compte. Côté Firebase, cette
// cascade n'était déployée nulle part (plan Blaze), et un chemin client la
// remplaçait au prix d'un périmètre réduit et d'un ordre critique. Les Edge
// Functions étant incluses dans l'offre gratuite, elle redevient le chemin
// normal.
//
// La politique de suppression est inchangée, et chaque branche a sa raison :
//
//   - les contributions APPROUVÉES sont ANONYMISÉES, jamais supprimées. La
//     donnée cartographique appartient à la carte ; ce qui doit disparaître,
//     ce sont les champs identifiants. C'est ce qui sort l'enregistrement du
//     champ du RGPD sans perdre le contenu.
//   - les contributions en attente ou rejetées n'ont jamais été publiques :
//     elles partent, il n'y a rien à préserver.
//   - les votes partent. Les compteurs agrégés sur les spots des autres, eux,
//     restent : ils reflètent un jugement réel de la communauté, et la spec ne
//     demande pas de le défaire.
//
// Deux choses que Postgres rend gratuites et qui demandaient du code :
// le découpage en lots de 500 (limite d'un batch Firestore, qu'une progression
// active dépassait) disparaît — un DELETE est un DELETE ; et la progression,
// les votes et le profil partent par contrainte de clé étrangère au moment où
// le compte est supprimé, sans qu'on ait à les nommer.

import { adminClient, requireUser, serveJSON } from '../_shared/auth.ts';

const ANONYMIZED_HANDLE = 'DELETED-AUTHOR';

serveJSON(async (request) => {
  const uid = await requireUser(request);
  const admin = adminClient();

  // Anonymiser AVANT de supprimer le compte : `author_uid` est en
  // `on delete set null`, donc l'ordre inverse laisserait des contributions
  // portant encore le pseudonyme de leur auteur, avec un uid déjà nul — le pire
  // des deux mondes.
  const { error: anonymizeError } = await admin
    .from('contributions')
    .update({ author_uid: null, author_handle: ANONYMIZED_HANDLE })
    .eq('author_uid', uid)
    .eq('status', 'approved');
  if (anonymizeError) throw anonymizeError;

  const { error: purgeError } = await admin
    .from('contributions')
    .delete()
    .eq('author_uid', uid)
    .neq('status', 'approved');
  if (purgeError) throw purgeError;

  // Emporte en cascade : profil, progression, votes, signalements, jetons de
  // push, appartenance à `editors`.
  const { error: deleteError } = await admin.auth.admin.deleteUser(uid);
  if (deleteError) throw deleteError;

  return { deleted: true };
});
