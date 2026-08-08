// Ce que la CLI sait faire — la déclaration, et la SEULE.
//
// ─────────────────────────────────────────────────────────────────────────────
// POURQUOI CE FICHIER EXISTE
//
// L'aide de `cli.js` était une chaîne de 400 caractères recopiée à deux endroits,
// et elle MENTAIT : elle proposait `deploy-rules`, disparu quand les règles
// d'accès sont devenues des politiques RLS versionnées, et passait sous silence
// `bundle`, `check-seeds`, `release`, `deploy-cdn` et `seed`. Une aide fausse est
// pire qu'une aide absente : l'absence envoie lire le code, le mensonge envoie
// taper une commande qui n'existe pas.
//
// La liste vit donc ici, et `commands.test.mjs` la compare aux `case` réellement
// présents dans le `switch`. Ajouter une commande sans l'y déclarer fait échouer
// la suite ; déclarer une commande qui n'existe pas aussi.
//
// L'ordre des groupes suit la journée type : on regarde, on récolte, on rédige,
// on publie, on modère.

export const GROUPES = [
  ['Regarder', 'Ne touchent à rien. Utilisables sans credential.'],
  ['Récolter', 'Font entrer de la matière première dans le dépôt.'],
  ['Contrôler', 'Disent si le contenu est publiable. Aucune écriture.'],
  ['Publier', 'Écrivent en ligne. Demandent SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY.'],
  ['Modérer', 'Agissent sur les contributions des joueurs.'],
];

/**
 * Une commande.
 *
 * @property {string} nom       tel qu'on le tape
 * @property {string} groupe    l'un de `GROUPES`
 * @property {string} resume    UNE ligne, à l'impératif, qui dit ce que ça fait
 * @property {string} [args]    la forme des arguments, affichée telle quelle
 * @property {string[]} [notes] ce qu'on regretterait de ne pas savoir avant
 * @property {string[]} [exemples] des lignes de commande complètes
 */
export const COMMANDES = [
  // ---- Regarder -----------------------------------------------------------
  {
    nom: 'news',
    groupe: 'Regarder',
    resume: 'Liste les actus, filtrées par date et par statut.',
    args: '[--since JJ] [--until JJ] [--days N] [--status draft|published] [--json]',
    notes: [
      'Les dates portent sur `publishedAt`, jamais sur la date du fichier.',
      '`--days 7` vaut `--since` il y a sept jours, bornes comprises.',
    ],
    exemples: [
      'cli.js news --days 7',
      'cli.js news --since 2026-08-01 --status draft',
      'cli.js news --json | jq -r ".[].id"',
    ],
  },
  {
    nom: 'translate',
    groupe: 'Regarder',
    resume: 'Liste les champs ES / IT / DE manquants.',
    args: '--dry-run',
    notes: ['Seul `--dry-run` est implémenté : l’appel au traducteur reste à câbler.'],
  },
  {
    nom: 'content-source',
    groupe: 'Regarder',
    resume: 'Affiche ou change la source de contenu que lit l’app.',
    args: '[url|off]',
    notes: [
      'Sans argument, affiche seulement. `off` renvoie l’app sur son socle embarqué.',
      'La bascule n’atteint un client qu’à son prochain lancement à froid : le cache d’`app_config` n’a pas de durée de vie.',
    ],
  },

  // ---- Récolter -----------------------------------------------------------
  {
    nom: 'pull-news',
    groupe: 'Récolter',
    resume: 'Matérialise les faits `news` de content/inbox en squelettes à rédiger.',
    args: '[--dry-run]',
    notes: ['Idempotent : l’identifiant est frappé sur le contenu du fait.'],
  },
  {
    nom: 'pull-online-events',
    groupe: 'Récolter',
    resume: 'Même chose pour les faits `online-event`.',
    args: '[--dry-run]',
  },
  {
    nom: 'pull-drafts',
    groupe: 'Récolter',
    resume: 'Matérialise les brouillons posés au doigt dans le build debug.',
    args: '[--file X]',
    notes: [
      'Sans `--file`, lit Supabase et demande donc des credentials.',
      'Avec `--file`, lit un export de l’app : aucun credential.',
    ],
  },

  // ---- Contrôler ----------------------------------------------------------
  {
    nom: 'validate',
    groupe: 'Contrôler',
    resume: 'Valide tout content/**.json contre les schémas.',
  },
  {
    nom: 'check-publishable',
    groupe: 'Contrôler',
    resume: 'Applique les règles éditoriales et le contrôle de marques.',
    notes: [
      'Presque toutes ses règles ne mordent que sur `status: published` — un brouillon les passe trivialement.',
    ],
  },
  {
    nom: 'check-seeds',
    groupe: 'Contrôler',
    resume: 'Vérifie que les socles embarqués ne sont pas en retard sur content/.',
    notes: [
      'C’est le contrôle qui ne s’attrape pas à la relecture : un POI édité sans régénération livre un binaire en retard, et rien ne le signale.',
    ],
  },
  {
    nom: 'bundle',
    groupe: 'Contrôler',
    resume: 'Régénère les socles embarqués depuis content/.',
    args: '[--dry-run]',
    notes: ['`--dry-run` équivaut à `check-seeds`.'],
  },

  // ---- Publier ------------------------------------------------------------
  {
    nom: 'release',
    groupe: 'Publier',
    resume: 'LA commande de publication : tous les contrôles, puis publie et bumpe.',
    args: '[--dry-run]',
    notes: [
      'Arbre propre exigé, sauf en `--dry-run` — qui doit rester utilisable en pleine édition.',
      'Enchaîner les contrôles à la main est exactement la séquence dont on oublie une étape.',
    ],
  },
  {
    nom: 'publish',
    groupe: 'Publier',
    resume: 'Construit le site de contenu et le téléverse sur Storage.',
    args: '[--dry-run]',
    notes: ['Préférer `release`, qui passe les contrôles avant.'],
  },
  {
    nom: 'build-cdn',
    groupe: 'Publier',
    resume: 'Construit le site statique dans dist/, sans rien téléverser.',
  },
  {
    nom: 'deploy-cdn',
    groupe: 'Publier',
    resume: 'Téléverse dist/ dans le bucket public `cdn`.',
  },

  // ---- Modérer ------------------------------------------------------------
  {
    nom: 'moderate:list',
    groupe: 'Modérer',
    resume: 'Liste les contributions en attente, signalées en tête.',
  },
  {
    nom: 'moderate:approve',
    groupe: 'Modérer',
    resume: 'Approuve une contribution et attribue son XP.',
    args: '<id>',
  },
  {
    nom: 'moderate:reject',
    groupe: 'Modérer',
    resume: 'Refuse une contribution.',
    args: '<id>',
  },
  {
    nom: 'shadow-ban',
    groupe: 'Modérer',
    resume: 'Masque les contributions d’un compte sans le lui dire.',
    args: '<uid>',
  },
  {
    nom: 'lift-shadow-ban',
    groupe: 'Modérer',
    resume: 'Lève un shadow-ban.',
    args: '<uid>',
  },
  {
    nom: 'kill-switch',
    groupe: 'Modérer',
    resume: 'Coupe ou rétablit les contributions communautaires.',
    args: '[on|off]',
    notes: ['Sans argument, affiche l’état courant.'],
  },
];

export const NOMS = COMMANDES.map((c) => c.nom);

/**
 * La distance d'édition entre deux chaînes (Levenshtein), plafonnée à ce qui
 * nous intéresse. Sert uniquement à proposer « vouliez-vous dire » : une faute
 * de frappe ne doit pas obliger à relire toute l'aide.
 */
export function distance(a, b) {
  const m = a.length;
  const n = b.length;
  let ligne = Array.from({ length: n + 1 }, (_, j) => j);
  for (let i = 1; i <= m; i++) {
    const suivante = [i];
    for (let j = 1; j <= n; j++) {
      suivante[j] = Math.min(
        ligne[j] + 1,
        suivante[j - 1] + 1,
        ligne[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1),
      );
    }
    ligne = suivante;
  }
  return ligne[n];
}

/**
 * La commande la plus proche d'une saisie, ou `null` si rien n'est assez proche.
 *
 * Le seuil monte avec la longueur du mot : deux fautes sur `news` en font un
 * autre mot, deux fautes sur `pull-online-events` restent une faute de frappe.
 */
export function suggestion(saisie) {
  if (!saisie) return null;
  const candidats = NOMS
    .map((nom) => ({ nom, d: distance(saisie.toLowerCase(), nom) }))
    .sort((a, b) => a.d - b.d);
  const meilleur = candidats[0];
  const seuil = Math.max(2, Math.floor(meilleur.nom.length / 3));
  return meilleur.d <= seuil ? meilleur.nom : null;
}

/** L'aide complète, en texte. Rendue par une fonction PURE pour qu'un test
 *  puisse la lire sans lancer de processus ni capturer une sortie. */
export function aide() {
  const lignes = [
    'cli.js — contenu, socles et publication de Neon Compass',
    '',
    '  cli.js <commande> [options]',
    '  cli.js help <commande>     le détail d’une seule',
    '',
  ];
  const large = Math.max(...COMMANDES.map((c) => c.nom.length));
  for (const [groupe, quoi] of GROUPES) {
    lignes.push(`${groupe.toUpperCase()} — ${quoi}`);
    for (const c of COMMANDES.filter((x) => x.groupe === groupe)) {
      lignes.push(`  ${c.nom.padEnd(large)}  ${c.resume}`);
    }
    lignes.push('');
  }
  lignes.push('Tout ce qui écrit en ligne demande SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY.');
  lignes.push('La console web fait la même chose au clic :  npm run ui');
  return lignes.join('\n');
}

/** Le détail d'une commande, ou `null` si elle est inconnue. */
export function aideDe(nom) {
  const c = COMMANDES.find((x) => x.nom === nom);
  if (!c) return null;
  const lignes = [`  cli.js ${c.nom}${c.args ? ` ${c.args}` : ''}`, '', `  ${c.resume}`];
  if (c.notes?.length) {
    lignes.push('');
    for (const n of c.notes) lignes.push(`  · ${n}`);
  }
  if (c.exemples?.length) {
    lignes.push('', '  Exemples :');
    for (const e of c.exemples) lignes.push(`    ${e}`);
  }
  return lignes.join('\n');
}
