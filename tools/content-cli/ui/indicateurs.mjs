// Ce que chaque onglet dit de lui-même, sans qu'on ait à l'ouvrir.
//
// ─────────────────────────────────────────────────────────────────────────────
// POURQUOI
//
// La barre d'onglets répondait à « où sont les choses », pas à « où faut-il
// aller ». Une file de modération qui gonfle dans Revue, des fragments périmés
// dans Contrôles, un coupe-circuit resté fermé dans Pilotage : rien de tout ça
// ne se voyait depuis l'onglet d'à côté. Le tableau de bord montrait, mais
// seulement l'onglet ouvert — ce qui reproduit à l'échelle de la page la panne
// qu'il existe pour supprimer.
//
// ─────────────────────────────────────────────────────────────────────────────
// TROIS RÈGLES, ET LA PREMIÈRE EST LA MÊME QUE PARTOUT ICI
//
//   1. **Aucun indicateur ne ment par omission.** Une donnée absente donne
//      `inconnu` et un `?`, JAMAIS un zéro. « 0 en attente » parce qu'un jeton
//      manque est exactement la panne qu'on supprime.
//   2. **Le sens ne repose jamais sur la couleur.** Les trois teintes de statut
//      de cette console sont à ΔE 6,6 en deutéranopie — ambre et citron y sont
//      quasi indiscernables. Chaque indicateur porte donc un CHIFFRE ou un MOT,
//      et le niveau ne fait que le teinter.
//   3. **Une file n'est pas une alerte.** Treize actus à relire, c'est du
//      travail, pas une panne. Ce qui mérite l'ambre, c'est l'ANCIENNETÉ — un
//      brouillon publiable oublié depuis trois semaines — ou une panne franche.
//      Alerter sur le volume apprendrait à ignorer l'alerte.
//
// Ce fichier ne connaît pas le DOM : il reçoit l'état et rend des objets, donc
// il se teste sans navigateur.

/** Au-delà, une file n'est plus en cours de traitement : elle est oubliée.
 *
 *  Quatorze jours, comme la dernière tranche de l'histogramme d'ancienneté — un
 *  seuil de plus, avec une valeur différente, obligerait à se demander lequel
 *  fait foi. */
export const OUBLI_JOURS = 14;

/** Les niveaux, du plus calme au plus grave. L'ordre compte : `pire()` s'en
 *  sert pour retenir le plus alarmant d'un onglet. */
export const NIVEAUX = ['bon', 'neutre', 'inconnu', 'attention', 'grave'];

const pire = (...n) => n.filter(Boolean).sort((a, b) => NIVEAUX.indexOf(b) - NIVEAUX.indexOf(a))[0] ?? 'neutre';

/** Un morceau d'indicateur : ce qui s'affiche, et à quel point c'est ennuyeux. */
const bout = (texte, niveau = 'neutre', pourquoi = null) => ({ texte, niveau, pourquoi });

/** Assemble les bouts d'un onglet en un indicateur unique.
 *
 *  Les bouts vides sont écartés ; si tout est vide, l'onglet n'affiche RIEN
 *  plutôt qu'un « OK » — un onglet sans rien à dire ne doit pas ajouter du bruit
 *  à une barre qu'on lit en diagonale. */
function assembler(bouts) {
  const gardes = bouts.filter(Boolean);
  if (!gardes.length) return null;
  return {
    texte: gardes.map((b) => b.texte).join(' · '),
    niveau: pire(...gardes.map((b) => b.niveau)),
    // L'infobulle porte le POURQUOI, que l'étiquette courte ne peut pas dire.
    titre: gardes.map((b) => b.pourquoi ?? b.texte).join('\n'),
  };
}

// ---------------------------------------------------------------------------
// Revue — ce qui attend une décision
// ---------------------------------------------------------------------------

function revue(brouillons, metriques) {
  const bouts = [];

  if (!brouillons) bouts.push(bout('actus ?', 'inconnu', 'brouillons pas encore chargés'));
  else if (brouillons.indisponible) bouts.push(bout('actus ?', 'inconnu', brouillons.indisponible));
  else {
    const n = brouillons.totaux.attend;
    const jours = ancienneteEnJours(brouillons.plusAncien);
    const vieux = jours !== null && jours > OUBLI_JOURS;
    bouts.push(bout(
      `${n} actu${n > 1 ? 's' : ''}`,
      n === 0 ? 'bon' : vieux ? 'attention' : 'neutre',
      n === 0
        ? 'aucun brouillon n’attend de décision'
        : vieux
          ? `${n} brouillon(s) publiable(s), le plus ancien depuis ${jours} jours`
          : `${n} brouillon(s) attendent une décision`,
    ));
  }

  const m = metriques?.instantane?.moderation;
  if (!metriques) bouts.push(bout('contribs ?', 'inconnu', 'métriques pas encore chargées'));
  else if (metriques.indisponible) bouts.push(bout('contribs ?', 'inconnu', metriques.indisponible));
  else {
    const n = m.enAttente;
    const vieux = m.plusAncienJours !== null && m.plusAncienJours > OUBLI_JOURS;
    // Les signalées d'abord : elles restent VISIBLES des joueurs pendant
    // qu'elles attendent, contrairement aux autres.
    const niveau = m.signales > 0 ? 'attention' : n === 0 ? 'bon' : vieux ? 'attention' : 'neutre';
    bouts.push(bout(
      `${n} contrib${n > 1 ? 's' : ''}${m.signales ? ` (${m.signales} signalée${m.signales > 1 ? 's' : ''})` : ''}`,
      niveau,
      m.signales
        ? `${m.signales} contribution(s) signalée(s), visibles des joueurs en attendant`
        : n === 0
          ? 'file de modération vide'
          : `${n} contribution(s) en attente${vieux ? `, la plus ancienne depuis ${m.plusAncienJours} jours` : ''}`,
    ));
  }

  return assembler(bouts);
}

/** L'ancienneté en jours d'une date `AAAA-MM-JJ`, ou `null`.
 *
 *  Accepte l'objet `{ date, jours }` que produit `statistiques`, autant que la
 *  chaîne nue de `carteBrouillons` — les deux circulent dans la page. */
export function ancienneteEnJours(plusAncien, aujourdhui = new Date().toISOString().slice(0, 10)) {
  if (!plusAncien) return null;
  if (typeof plusAncien === 'object') return plusAncien.jours ?? null;
  const ms = Date.parse(`${aujourdhui}T00:00:00Z`) - Date.parse(`${plusAncien}T00:00:00Z`);
  return Number.isNaN(ms) ? null : Math.max(0, Math.floor(ms / 86400000));
}

// ---------------------------------------------------------------------------
// Veille — la dernière récolte, et ce qui est prêt à partir
// ---------------------------------------------------------------------------

/** Les verdicts de `runs.mjs`, et ce qu'ils valent. « indéterminé » n'est PAS un
 *  succès : c'est ce qu'on rend quand le journal ne prouve rien. */
const VERDICTS = {
  complète: 'bon',
  échec: 'grave',
  indéterminé: 'attention',
};

function veille(reseau, livraison) {
  const bouts = [];
  const r = reseau?.recolte;

  if (!reseau) bouts.push(bout('récolte ?', 'inconnu', 'état réseau pas encore chargé'));
  else if (r?.indisponible) bouts.push(bout('récolte ?', 'inconnu', r.indisponible));
  else if (!r?.verdict) bouts.push(bout('récolte ?', 'inconnu', 'aucun run trouvé'));
  else {
    // « partielle — <étape> muette » commence par « partielle ».
    const niveau = VERDICTS[r.verdict] ?? (r.verdict.startsWith('partielle') ? 'attention' : 'inconnu');
    bouts.push(bout(`récolte ${r.verdict.split(' —')[0]}`, niveau, `dernière récolte : ${r.verdict}`));
  }

  const n = livraison?.changements?.length;
  if (n) {
    bouts.push(bout(
      `${n} à livrer`,
      'neutre',
      `${n} fichier(s) de contenu modifié(s), pas encore dans une pull request`,
    ));
  }
  return assembler(bouts);
}

// ---------------------------------------------------------------------------
// Contrôles — ce qui casse en silence
// ---------------------------------------------------------------------------

function controles(socles, reseau, metriques) {
  const bouts = [];
  // Ce qu'on n'a PAS pu vérifier. Le distinguer de ce qui va bien est tout
  // l'objet de ce compteur : cet indicateur affichait « à jour » en vert alors
  // qu'il n'avait regardé que les socles, le réseau n'étant pas encore rentré.
  // Trois sources, une seule lue, et un vert franc — exactement le mensonge par
  // omission que ce fichier prétend interdire, dans le fichier qui l'interdit.
  const muettes = [];

  if (!socles) muettes.push('socles');
  else if (socles.indisponible) muettes.push('socles');
  else if (!socles.aJour) {
    bouts.push(bout('socles en retard', 'grave',
      'un POI édité sans régénération livre un binaire dont le socle est en retard, et rien ne le signale'));
  }

  const f = reseau?.fonctions;
  if (!f || f.indisponible) muettes.push('fonctions');
  else if (f.derivees.length) {
    bouts.push(bout(`${f.derivees.length} fonction(s) dérivée(s)`, 'grave',
      `${f.derivees.join(', ')} — une fonction non déployée ne casse rien, elle rend l’ANCIENNE réponse`));
  }

  const b = metriques?.instantane?.blocages;
  if (!b) muettes.push('files');
  else {
    if (b.fragmentsSales && (b.fragmentsDepuisMinutes === null || b.fragmentsDepuisMinutes > 120)) {
      bouts.push(bout('fragments périmés', 'grave',
        'une contribution approuvée n’apparaît chez personne tant que les fragments ne sont pas reconstruits'));
    }
    if (b.pushCoinces > 0) {
      bouts.push(bout(`${b.pushCoinces} push coincé(s)`, 'grave',
        'après trois tentatives, un quatrième essai n’y changera rien'));
    }
  }

  // Une panne trouvée passe DEVANT une source muette : savoir que les socles
  // sont en retard reste utile même si les fonctions n'ont pas répondu.
  if (bouts.length) {
    if (muettes.length) {
      bouts.push(bout(`${muettes.join(', ')} ?`, 'inconnu', `non vérifié : ${muettes.join(', ')}`));
    }
    return assembler(bouts);
  }
  // Rien à signaler, mais tout n'a pas été lu : on ne dit surtout pas « à jour ».
  if (muettes.length) {
    return assembler([bout(`${muettes.join(', ')} ?`, 'inconnu', `pas encore vérifié : ${muettes.join(', ')}`)]);
  }
  return assembler([bout('à jour', 'bon', 'socles, fonctions et files : les trois ont répondu, rien à signaler')]);
}

// ---------------------------------------------------------------------------
// Pilotage — les interrupteurs de production, qu'on oublie d'avoir baissés
// ---------------------------------------------------------------------------

function pilotage(reseau) {
  const bouts = [];
  const c = reseau?.appConfig;

  if (!reseau) return assembler([bout('config ?', 'inconnu', 'état réseau pas encore chargé')]);
  if (c?.indisponible) return assembler([bout('config ?', 'inconnu', c.indisponible)]);

  const v = c?.valeurs ?? {};
  // `communityContributionsEnabled` absent vaut VRAI — coupe-circuit sur une
  // capacité qui existe (voir la migration initiale). Ne pas confondre avec
  // `backendFeaturesEnabled`, absent = faux.
  if (v.communityContributionsEnabled === false) {
    bouts.push(bout('contributions coupées', 'attention',
      'le coupe-circuit est fermé : les joueurs ne peuvent plus proposer de spot'));
  }
  if (v.contentBaseURL === 'off' || v.contentBaseURL == null) {
    bouts.push(bout('CDN coupé', 'attention',
      'l’app ne lit que son socle embarqué : aucune publication ne l’atteint'));
  }
  if (v.backendFeaturesEnabled === false) {
    bouts.push(bout('backend coupé', 'attention', 'les fonctionnalités serveur sont désactivées côté app'));
  }

  // Un interrupteur baissé est un ÉTAT VOULU, mais qu'on oublie. Quand tout est
  // ouvert, l'onglet ne dit rien : il n'y a rien à ne pas oublier.
  return bouts.length ? assembler(bouts) : null;
}

// ---------------------------------------------------------------------------

/**
 * L'indicateur de chaque onglet, ou `null` quand il n'a rien à dire.
 *
 * Tolérant aux absences par construction : la page appelle cette fonction dès le
 * premier rendu, alors que le réseau n'a encore rien rapporté. Chaque source
 * manquante donne `?` plutôt que de faire échouer l'ensemble.
 */
export function indicateurs({ state, metriques, reseau, livraison } = {}) {
  return {
    revue: revue(state?.brouillons, metriques),
    veille: veille(reseau, livraison),
    controles: controles(state?.socles, reseau, metriques),
    pilotage: pilotage(reseau),
  };
}
