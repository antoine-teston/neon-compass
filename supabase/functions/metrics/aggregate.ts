// L'agrégation, séparée de la fonction qui la sert — donc vérifiable sans lever
// de serveur ni de base.
//
// ─────────────────────────────────────────────────────────────────────────────
// LA RÈGLE DE CE FICHIER : IL NE SORT QUE DES NOMBRES.
//
// C'est elle qui rend le Raspberry Pi inoffensif. Le moniteur ne reçoit jamais
// un titre, un pseudonyme, un uid ni un identifiant de contribution — il reçoit
// des décomptes. Un Pi volé sur une étagère ne donne donc accès à rien qu'on ne
// publierait pas soi-même.
//
// Ce n'est pas une intention, c'est une propriété testée : `formeDeSortie` liste
// les clés autorisées, et un test échoue si une chaîne apparaît là où on
// attendait un entier.

/** Les mêmes tranches que l'atelier des brouillons (`ui/drafts.mjs`).
 *
 *  Dupliquées à dessein plutôt qu'importées : ce fichier tourne sous Deno dans
 *  une Edge Function, l'autre sous Node dans la console. Un import à travers
 *  cette frontière serait une dépendance de déploiement pour une constante de
 *  cinq lignes. Le test `tranches identiques` les compare. */
export const TRANCHES = [
  { label: "aujourd'hui", max: 0 },
  { label: '1 à 3 j', max: 3 },
  { label: '4 à 7 j', max: 7 },
  { label: '8 à 14 j', max: 14 },
  { label: 'plus de 14 j', max: Infinity },
];

export const CATEGORIES = [
  'landmark',
  'collectible',
  'activity',
  'safehouse',
  'vehicle',
  'event',
];

/** Le nombre de jours affichés par le graphe de flux. */
export const FENETRE_JOURS = 30;

const JOUR_MS = 24 * 60 * 60 * 1000;

/** Le jour civil d'un horodatage, en UTC.
 *
 *  UTC et non le fuseau local : la fonction tourne sur un serveur dont on ne
 *  choisit pas la zone, et le moniteur tourne sur un Pi dont on ne la choisit
 *  pas non plus. Deux jours civils différents pour un même enregistrement
 *  feraient boiter le graphe sans que rien ne le dise. */
export function jourDe(iso: string): string {
  return new Date(iso).toISOString().slice(0, 10);
}

/** Le nombre de jours ENTIERS écoulés depuis une date, vu du jour `aujourdhui`.
 *
 *  Négatif ramené à zéro : une date future — horloge décalée, saisie manuelle —
 *  ne doit pas produire « il attend depuis -3 jours ». */
export function ageEnJours(iso: string, aujourdhui: string): number {
  const jours = Math.floor(
    (Date.parse(`${aujourdhui}T00:00:00Z`) - Date.parse(`${jourDe(iso)}T00:00:00Z`)) / JOUR_MS,
  );
  return Math.max(0, jours);
}

/** Range des âges dans les tranches. Rend un tableau d'entiers, dans l'ordre de
 *  `TRANCHES` — donc ORDINAL, ce que le graphe encode par une rampe à une seule
 *  teinte plutôt que par des couleurs distinctes. */
export function parTranche(ages: number[]): number[] {
  const compte = TRANCHES.map(() => 0);
  for (const age of ages) {
    const index = TRANCHES.findIndex((t) => age <= t.max);
    compte[index === -1 ? TRANCHES.length - 1 : index] += 1;
  }
  return compte;
}

/**
 * Le flux jour par jour, sur `FENETRE_JOURS` jours, du plus ancien au plus récent.
 *
 * TOUS les jours sont présents, y compris ceux à zéro. Un graphe qui n'aurait
 * que les jours actifs mentirait sur le rythme : trois contributions étalées sur
 * trois semaines dessineraient la même ligne que trois contributions en un jour.
 *
 * ⚠️ `approbations`, et pas « décisions ». Un refus ne laisse AUCUN horodatage
 * dans le schéma (`contributions` porte `approved_at`, pas de `rejected_at`) :
 * une contribution refusée quitte la file sans trace datée. La courbe compte
 * donc ce qui a été approuvé, pas ce qui a été traité, et le graphe le dit.
 * La vérité sur la file reste `enAttente`, qui, lui, est un décompte direct.
 */
export function flux(
  arrivees: string[],
  approbations: string[],
  aujourdhui: string,
): { jour: string; arrivees: number; approbations: number }[] {
  const jours: { jour: string; arrivees: number; approbations: number }[] = [];
  const index = new Map<string, number>();
  const fin = Date.parse(`${aujourdhui}T00:00:00Z`);

  for (let i = FENETRE_JOURS - 1; i >= 0; i--) {
    const jour = new Date(fin - i * JOUR_MS).toISOString().slice(0, 10);
    index.set(jour, jours.length);
    jours.push({ jour, arrivees: 0, approbations: 0 });
  }

  const compter = (isos: string[], champ: 'arrivees' | 'approbations') => {
    for (const iso of isos) {
      const at = index.get(jourDe(iso));
      // Hors fenêtre : ignoré sans bruit. La requête filtre déjà sur la
      // fenêtre ; ce garde-fou existe pour que la fonction reste juste si on
      // lui passe plus large un jour.
      if (at !== undefined) jours[at][champ] += 1;
    }
  };
  compter(arrivees, 'arrivees');
  compter(approbations, 'approbations');

  return jours;
}

/** Minutes écoulées depuis un horodatage, ou `null` s'il n'y en a pas.
 *
 *  `null` est un ÉTAT, pas un zéro : « jamais construit » et « construit il y a
 *  zéro minute » sont opposés, et c'est exactement le genre de confusion qui
 *  fait passer une panne pour un succès. */
export function minutesDepuis(iso: string | null, maintenant: number): number | null {
  if (!iso) return null;
  return Math.max(0, Math.floor((maintenant - Date.parse(iso)) / 60000));
}

/** Compte par catégorie, TOUTES les catégories présentes même à zéro — pour que
 *  le graphe garde des colonnes stables d'un rafraîchissement à l'autre. */
export function parCategorie(categories: string[]): Record<string, number> {
  const compte: Record<string, number> = Object.fromEntries(CATEGORIES.map((c) => [c, 0]));
  for (const categorie of categories) {
    // Une catégorie inconnue serait un schéma qui a bougé sans que ce fichier le
    // sache. On la garde plutôt que de la jeter : la voir apparaître dans le
    // graphe est le seul signal qu'on aura.
    compte[categorie] = (compte[categorie] ?? 0) + 1;
  }
  return compte;
}

// ---------------------------------------------------------------------------
// L'assemblage
// ---------------------------------------------------------------------------

/** Ce que les requêtes rapportent. Des horodatages et des décomptes, rien
 *  d'autre — c'est le point de passage où l'on peut vérifier qu'aucun champ
 *  nominatif n'a été demandé. */
export interface Brut {
  attente: { created_at: string; category: string; flagged_for_review: boolean }[];
  arrivees: string[];
  approbations: string[];
  bundle: { dirty: boolean; built_at: string | null } | null;
  push: { created_at: string; sent_at: string | null; attempts: number }[];
  totaux: {
    profils: number | null;
    approuvees: number | null;
    rejetees: number | null;
    votes: number | null;
    signalements: number | null;
  };
}

export interface Instantane {
  prisLe: string;
  moderation: {
    enAttente: number;
    signales: number;
    plusAncienJours: number | null;
    parTranche: number[];
    parCategorie: Record<string, number>;
  };
  flux: { jour: string; arrivees: number; approbations: number }[];
  blocages: {
    fragmentsSales: boolean;
    fragmentsDepuisMinutes: number | null;
    pushEnAttente: number;
    pushPlusAncienMinutes: number | null;
    pushCoinces: number;
  };
  communaute: Brut['totaux'];
}

/** Un envoi de notification qui a déjà échoué trois fois n'échouera pas moins la
 *  quatrième. Au-delà, ce n'est plus une file lente, c'est une file coincée. */
export const TENTATIVES_COINCE = 3;

/**
 * Assemble l'instantané. Fonction PURE : `aujourdhui` et `maintenant` sont
 * passés plutôt que lus, sans quoi le résultat dépendrait de l'heure d'exécution
 * et ne se testerait pas.
 */
export function assembler(brut: Brut, aujourdhui: string, maintenant: number): Instantane {
  const attente = brut.attente ?? [];
  const ages = attente.map((c) => ageEnJours(c.created_at, aujourdhui));
  const push = brut.push ?? [];
  const enAttentePush = push.filter((p) => !p.sent_at);
  const plusAncienPush = enAttentePush.map((p) => p.created_at).sort()[0] ?? null;

  return {
    prisLe: new Date(maintenant).toISOString(),
    moderation: {
      enAttente: attente.length,
      signales: attente.filter((c) => c.flagged_for_review).length,
      // `null` et non `0` sur une file vide : « le plus ancien a zéro jour »
      // décrirait une file qui vient de recevoir quelque chose, pas une file
      // vide. Le graphe affiche l'un et tait l'autre.
      plusAncienJours: ages.length ? Math.max(...ages) : null,
      parTranche: parTranche(ages),
      parCategorie: parCategorie(attente.map((c) => c.category)),
    },
    flux: flux(brut.arrivees ?? [], brut.approbations ?? [], aujourdhui),
    blocages: {
      fragmentsSales: Boolean(brut.bundle?.dirty),
      fragmentsDepuisMinutes: minutesDepuis(brut.bundle?.built_at ?? null, maintenant),
      pushEnAttente: enAttentePush.length,
      pushPlusAncienMinutes: minutesDepuis(plusAncienPush, maintenant),
      pushCoinces: enAttentePush.filter((p) => (p.attempts ?? 0) >= TENTATIVES_COINCE).length,
    },
    communaute: brut.totaux,
  };
}

/**
 * Le filet de sécurité de la règle du fichier : parcourt l'instantané et rend la
 * liste des valeurs qui ne sont ni un nombre, ni un booléen, ni `null`, ni une
 * chaîne de la forme attendue (une date, un jour, une clé de catégorie).
 *
 * Existe pour être appelé par un TEST, pas en production : l'intérêt est qu'un
 * champ nominatif ajouté par distraction fasse échouer la suite au lieu de
 * partir sur le réseau. Un contrôle qu'on n'exerce pas ne protège de rien.
 */
export function fuitesDe(valeur: unknown, chemin = ''): string[] {
  if (valeur === null || typeof valeur === 'number' || typeof valeur === 'boolean') return [];
  if (typeof valeur === 'string') {
    const inoffensive = /^\d{4}-\d{2}-\d{2}([T ].*)?$/.test(valeur);
    return inoffensive ? [] : [`${chemin} = ${JSON.stringify(valeur)}`];
  }
  if (Array.isArray(valeur)) return valeur.flatMap((v, i) => fuitesDe(v, `${chemin}[${i}]`));
  if (typeof valeur === 'object') {
    return Object.entries(valeur as Record<string, unknown>).flatMap(([k, v]) =>
      fuitesDe(v, chemin ? `${chemin}.${k}` : k)
    );
  }
  return [`${chemin} = ${typeof valeur}`];
}
