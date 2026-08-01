/** Ce que le classement a besoin de savoir d'une contribution approuvée.
 *  Forme réelle du document (`submitContribution.ts`) : le handle y est
 *  dénormalisé, donc compter n'exige aucune lecture de profil. */
export interface ApprovedContribution {
  authorUid: string;
  authorHandle: string;
  shadowHidden?: boolean;
}

export interface LeaderboardRow {
  uid: string;
  handle: string;
  xp: number;
  approvedCount: number;
}

/**
 * Décompte par auteur, masquées exclues.
 *
 * `shadowHidden` vit sur la CONTRIBUTION, jamais sur le profil — et c'est ce
 * qui rend l'exclusion gratuite : un auteur shadow-banni voit toutes les
 * siennes masquées (`flagSuspiciousContribution.ts` les reprend
 * rétroactivement), son décompte tombe à zéro, et il disparaît du classement
 * sans qu'aucune règle ne le nomme.
 */
export function tallyApproved(
  contributions: ApprovedContribution[]
): Map<string, { handle: string; approvedCount: number }> {
  const tally = new Map<string, { handle: string; approvedCount: number }>();
  for (const contribution of contributions) {
    if (contribution.shadowHidden === true) continue;
    const existing = tally.get(contribution.authorUid);
    if (existing) {
      existing.approvedCount += 1;
    } else {
      tally.set(contribution.authorUid, { handle: contribution.authorHandle, approvedCount: 1 });
    }
  }
  return tally;
}

/**
 * Classement des contributeurs, sans aucun appel Firestore — c'est ce qui le
 * rend testable, comme la logique de contribution l'est déjà.
 *
 * Classé sur l'XP et non sur le décompte : l'XP se gagne aussi par les votes
 * reçus (`xp.ts`), donc elle récompense ce que les autres ont jugé utile, pas
 * le volume produit. Le décompte reste affiché, il ne classe pas.
 *
 * Une XP absente vaut zéro plutôt qu'une exclusion : un profil peut ne pas
 * encore porter le champ, et disparaître du classement pour cette raison serait
 * incompréhensible pour son auteur.
 */
export function rankContributors(
  tally: Map<string, { handle: string; approvedCount: number }>,
  xpByUid: Map<string, number>,
  limit: number
): LeaderboardRow[] {
  return [...tally.entries()]
    .map(([uid, { handle, approvedCount }]) => ({
      uid,
      handle,
      xp: xpByUid.get(uid) ?? 0,
      approvedCount,
    }))
    // Départage par uid à XP égale : sans ça l'ordre dépendrait de celui que
    // Firestore a rendu, et le classement bougerait sans raison d'un run à
    // l'autre.
    .sort((a, b) => b.xp - a.xp || a.uid.localeCompare(b.uid))
    .slice(0, limit);
}
