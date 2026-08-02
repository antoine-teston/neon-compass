import { onSchedule } from 'firebase-functions/v2/scheduler';
import { getFirestore } from 'firebase-admin/firestore';
import { tallyApproved, rankContributors, type ApprovedContribution } from './leaderboard.js';

const TOP_N = 50;

/**
 * Agrège le classement dans UN document.
 *
 * Jamais une requête client sur la collection des profils : les Security Rules
 * sont deny-by-default, et la balayer serait à la fois un coût et une fuite.
 * Chaque client lit deux documents — `leaderboards/weekly` et le sien — quel
 * que soit le nombre d'utilisateurs.
 *
 * Les profils ne sont lus que pour les auteurs QUI ONT une contribution
 * approuvée, jamais toute la collection : le décompte vient des contributions,
 * dont le handle est déjà dénormalisé.
 */
export const rebuildLeaderboard = onSchedule(
  { region: 'europe-west1', schedule: 'every day 04:00' },
  async () => {
    const db = getFirestore();
    const snapshot = await db.collection('contributions').where('status', '==', 'approved').get();
    const tally = tallyApproved(snapshot.docs.map((doc) => doc.data() as ApprovedContribution));

    const uids = [...tally.keys()];
    const xpByUid = new Map<string, number>();
    // getAll ne prend pas un tableau vide, et un premier run sans aucune
    // contribution approuvée est le cas normal, pas une anomalie.
    if (uids.length > 0) {
      const profiles = await db.getAll(...uids.map((uid) => db.doc(`profiles/${uid}`)));
      profiles.forEach((profile) => {
        if (profile.exists) xpByUid.set(profile.id, (profile.data()?.xp as number | undefined) ?? 0);
      });
    }

    const rows = rankContributors(tally, xpByUid, TOP_N);
    await db.doc('leaderboards/weekly').set({ rows, updatedAt: Date.now() });

    // Le rang personnel va dans le document de chacun : c'est ce qui permet au
    // Profil de l'afficher sans lire le classement entier.
    //
    // Découpé en lots : un batch Firestore plafonne à 500 écritures, et cette
    // boucle parcourt TOUS les contributeurs, pas seulement le top 50.
    const ranked = rankContributors(tally, xpByUid, tally.size);
    const CHUNK = 400;
    for (let i = 0; i < ranked.length; i += CHUNK) {
      const batch = db.batch();
      ranked.slice(i, i + CHUNK).forEach((row, offset) => {
        batch.set(db.doc(`profiles/${row.uid}`), { rank: i + offset + 1 }, { merge: true });
      });
      await batch.commit();
    }
  },
);
