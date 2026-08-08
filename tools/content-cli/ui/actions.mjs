// Liste blanche des actions exposées par la console web.
//
// C'est la pièce de sécurité du dispositif. Un serveur HTTP local qui lance des
// commandes est un vecteur d'exécution de code : rien de ce qui vient de la
// requête ne doit jamais atteindre une ligne de commande. D'où ce modèle —
// chaque action est un `argv` FIXE, désigné par une clé. Les seules données
// variables sont des PARAMÈTRES DÉCLARÉS, chacun avec son motif, passés en
// éléments de tableau distincts (donc jamais interprétés par un shell).
//
// La règle qui rend le modèle vérifiable : **un paramètre non déclaré est un
// refus, jamais un laissez-passer.** Il n'y a pas de chemin par lequel une clé
// inconnue du corps de requête arrive dans un argv.
//
// `destructive: true` signifie « écrit en production » : le serveur exige alors
// une confirmation explicite dans le corps de la requête ET la présence des
// credentials.

import { join } from 'node:path';

const CLI = 'cli.js';
const BASEMAP = join('..', 'basemap');

/// UUID et identifiants : alphanumériques, tirets, underscores. Assez permissif
/// pour un UUID de contribution comme pour un uid de compte, assez strict pour
/// exclure tout ce qui ressemble à un chemin, un espace ou un métacaractère.
export const ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

/// Fenêtres et plafonds de la Récolte : des entiers, rien d'autre.
const NUM_PATTERN = /^\d{1,3}$/;

/// Noms de dossiers sous `supabase/functions/`. Volontairement plus strict que
/// ID_PATTERN : ces valeurs deviennent `-f functions=<v>`, et une fonction ne
/// s'est jamais appelée `A_b`.
const FUNCTION_PATTERN = /^[a-z0-9-]{1,64}$/;

/// `contentBaseURL` : soit la sortie de secours vers un hôte en HTTPS, soit
/// `off` qui rend l'app à son socle embarqué. Rien d'autre — surtout pas `http`,
/// qui ferait servir du contenu en clair à tous les clients.
const CONTENT_SOURCE_PATTERN = /^(off|https:\/\/[A-Za-z0-9._~:/?#@!$&'()*+,;=%-]{1,300})$/;

// `--ref main` est explicite partout, et ce n'est pas de la décoration : sans
// lui, `gh` déclenche le workflow sur la branche par défaut du dépôt telle que
// GitHub la connaît, ce qui est presque toujours ce qu'on veut mais jamais ce
// qu'on a écrit. Un correctif appliqué à 23 h ne doit pas dépendre d'un défaut
// implicite.
const GH = (workflow, ...rest) => ['workflow', 'run', workflow, '--ref', 'main', ...rest];

export const ACTIONS = {
  // --- Contrôles : aucun credential, aucune écriture -----------------------
  validate: {
    label: 'Valider les schémas',
    group: 'checks',
    argv: [CLI, 'validate'],
  },
  'check-publishable': {
    label: 'Règles éditoriales',
    group: 'checks',
    hint: 'Marques déposées, cheats vérifiés par au moins deux sources',
    argv: [CLI, 'check-publishable'],
  },
  'check-seeds': {
    label: 'Socles embarqués à jour',
    group: 'checks',
    hint: "Détecte un seed-poi.json en retard sur content/ — invisible autrement",
    argv: [CLI, 'check-seeds'],
  },
  'translate-dry': {
    label: 'Traductions manquantes',
    group: 'checks',
    hint: 'Champs ES/IT/DE absents',
    argv: [CLI, 'translate', '--dry-run'],
  },
  'release-dry': {
    label: 'Répétition de publication',
    group: 'checks',
    hint: 'Tous les contrôles, plus le diff qui partirait. N’écrit rien.',
    argv: [CLI, 'release', '--dry-run'],
  },
  tests: {
    label: 'Tests de frappe des identifiants',
    group: 'checks',
    hint: "L'invariant le plus coûteux du dépôt : un id publié ne doit jamais désigner un autre POI",
    argv: ['--test', join(BASEMAP, 'gtav-poi-ids.test.mjs')],
  },

  // --- Écritures locales : modifient le dépôt, pas la production -----------
  bundle: {
    label: 'Régénérer le catalogue embarqué',
    group: 'local',
    hint: 'collections.json depuis content/collections',
    argv: [CLI, 'bundle'],
    writesRepo: true,
  },
  'pull-drafts': {
    label: 'Récupérer les brouillons de l’éditeur',
    group: 'local',
    hint: 'Matérialise ce qui a été posé au doigt en fichiers content/poi',
    argv: [CLI, 'pull-drafts'],
    writesRepo: true,
    needsCredentials: true,
  },
  'pull-news': {
    label: 'Matérialiser les faits d’actu',
    group: 'local',
    hint: 'Transforme les faits de content/inbox en squelettes à rédiger. Idempotent.',
    argv: [CLI, 'pull-news'],
    writesRepo: true,
  },
  'pull-online-events': {
    label: 'Matérialiser les événements en ligne',
    group: 'local',
    argv: [CLI, 'pull-online-events'],
    writesRepo: true,
  },
  'deliver-dry': {
    label: 'Livrer — répétition',
    group: 'livraison',
    hint: 'Montre la branche, le titre et les fichiers qui partiraient. N’écrit rien.',
    argv: ['deliver.mjs', '--dry-run'],
  },
  deliver: {
    label: 'Livrer : brancher, commiter, ouvrir la PR',
    group: 'livraison',
    hint: 'Titre et corps COMPOSÉS depuis le diff — rien de saisi. La PR n’est pas fusionnée.',
    argv: ['deliver.mjs'],
    writesRepo: true,
  },
  import: {
    label: 'Ré-importer la carte de référence',
    group: 'local',
    hint: 'Refetch les dumps amont. Long, et réseau. Les ids existants sont réutilisés.',
    argv: [join(BASEMAP, 'gtav-poi.mjs')],
    writesRepo: true,
    slow: true,
  },

  // --- GitHub : la moitié du pilotage qui ne vit pas sur cette machine ------
  // La Récolte ne peut PAS tourner ici : la passerelle de sortie des sessions
  // d'agent refuse le CONNECT sur les quatre sources du registre. Le runner CI
  // est le seul endroit d'où elles répondent — d'où le déclenchement à distance
  // plutôt qu'une commande locale.
  recolte: {
    label: 'Lancer la Récolte',
    group: 'github',
    hint: 'Déclenche le workflow sur GitHub. Le verdict se lit dans le journal, pas dans le statut.',
    bin: 'gh',
    argv: GH('recolte.yml'),
    params: {
      since: { pattern: NUM_PATTERN, default: '2', flag: '-f', field: 'since' },
      max: { pattern: NUM_PATTERN, default: '15', flag: '-f', field: 'max' },
    },
  },

  // --- Production : credentials + confirmation ------------------------------
  release: {
    label: 'Publier',
    group: 'prod',
    hint: 'Contrôles, construction du site et téléversement sur le CDN. Toute collection modifiée est retéléchargée par les clients.',
    argv: [CLI, 'release'],
    destructive: true,
  },
  // Pas d'action de déploiement des règles d'accès : ce sont des politiques RLS
  // versionnées dans supabase/migrations/, appliquées par `supabase db push` et
  // relues en pull request. Une console web n'a pas à pouvoir les remplacer d'un
  // clic.
  'kill-switch-status': {
    label: 'État du coupe-circuit communauté',
    group: 'prod',
    argv: [CLI, 'kill-switch'],
    needsCredentials: true,
  },
  'content-source-status': {
    label: 'Source de contenu actuelle',
    group: 'prod',
    hint: 'Lit contentBaseURL dans app_config',
    argv: [CLI, 'content-source'],
    needsCredentials: true,
  },

  // --- Carnet de hotfix : gestes correctifs nommés --------------------------
  // Chacun porte une fiche dans hotfix.mjs — ce que ça coûte, comment vérifier,
  // comment revenir en arrière. Un geste sans fiche n'est pas affiché : voir le
  // test « tout geste du carnet a sa fiche ».
  'kill-switch-off': {
    label: 'Couper les contributions',
    group: 'hotfix',
    argv: [CLI, 'kill-switch', 'off'],
    destructive: true,
  },
  'kill-switch-on': {
    label: 'Rouvrir les contributions',
    group: 'hotfix',
    argv: [CLI, 'kill-switch', 'on'],
    destructive: true,
  },
  'content-source': {
    label: 'Basculer la source de contenu',
    group: 'hotfix',
    hint: 'Sortie de secours vers un autre hébergeur, sans mise à jour de l’app. « off » rend l’app à son socle embarqué.',
    argv: [CLI, 'content-source'],
    destructive: true,
    params: {
      url: { pattern: CONTENT_SOURCE_PATTERN, required: true },
    },
  },
  'deploy-function': {
    label: 'Redéployer une edge function',
    group: 'hotfix',
    hint: 'Une fonction non déployée ne casse rien — elle rend l’ANCIENNE réponse.',
    bin: 'gh',
    argv: GH('functions.yml', '-f', 'dry-run=false'),
    destructive: true,
    params: {
      name: { pattern: FUNCTION_PATTERN, required: true, flag: '-f', field: 'functions' },
    },
  },
  'republish-bundles': {
    label: 'Reconstruire les fragments communauté',
    group: 'hotfix',
    hint: 'À faire après un déploiement qui change la FORME du fragment — sinon rien ne bouge pendant une heure.',
    bin: 'gh',
    argv: GH('functions.yml', '-f', 'dry-run=false', '-f', 'republish-bundles=true'),
    destructive: true,
  },
  'migrations-dry': {
    label: 'Migrations — lister sans appliquer',
    group: 'hotfix',
    bin: 'gh',
    argv: GH('migrations.yml', '-f', 'dry-run=true'),
  },
  'migrations-apply': {
    label: 'Migrations — appliquer',
    group: 'hotfix',
    hint: 'Écrit en base. Le retour arrière est une migration inverse à écrire.',
    bin: 'gh',
    argv: GH('migrations.yml', '-f', 'dry-run=false'),
    destructive: true,
  },

  // --- Modération : la vraie plus-value d'une interface --------------------
  // Lister puis agir sur une ligne, au lieu de recopier des identifiants dans un
  // terminal.
  'moderate:list': {
    label: 'Contributions en attente',
    group: 'moderation',
    argv: [CLI, 'moderate:list'],
    needsCredentials: true,
  },
  'moderate:approve': {
    label: 'Approuver',
    group: 'moderation',
    argv: [CLI, 'moderate:approve'],
    destructive: true,
    needsID: true,
  },
  'moderate:reject': {
    label: 'Rejeter',
    group: 'moderation',
    argv: [CLI, 'moderate:reject'],
    destructive: true,
    needsID: true,
  },
  'shadow-ban': {
    label: 'Shadow-ban',
    group: 'moderation',
    hint: 'Masque aussi les spots déjà approuvés de cet auteur',
    argv: [CLI, 'shadow-ban'],
    destructive: true,
    needsID: true,
  },
  'lift-shadow-ban': {
    label: 'Lever le shadow-ban',
    group: 'moderation',
    argv: [CLI, 'lift-shadow-ban'],
    destructive: true,
    needsID: true,
  },
};

/**
 * Les paramètres déclarés d'une action, forme normalisée.
 *
 * `needsID: true` est du sucre pour le paramètre historique — les quatre actions
 * de modération l'utilisent, et leurs messages d'erreur sont ceux que la page
 * affiche depuis le début.
 */
function paramsOf(action) {
  if (action.needsID) return { id: { pattern: ID_PATTERN, required: true, isLegacyID: true } };
  return action.params ?? {};
}

/**
 * Construit l'`argv` d'une action. Lève plutôt que de deviner : une action
 * inconnue, un paramètre manquant, mal formé ou NON DÉCLARÉ sont des erreurs,
 * jamais des cas à rattraper au vol.
 *
 * Rend aussi `bin` : le binaire à lancer. `null` = Node, ce qui reste le cas de
 * toutes les actions locales.
 */
export function resolveAction(name, values = {}) {
  const action = ACTIONS[name];
  if (!action) throw new Error(`action inconnue : ${name}`);

  const declared = paramsOf(action);

  // D'abord le refus : toute clé fournie qui n'est pas déclarée. Fait AVANT la
  // construction de l'argv, pour qu'une clé inconnue ne puisse jamais être lue,
  // même par accident, par le code qui suit.
  for (const key of Object.keys(values)) {
    if (values[key] === undefined || values[key] === null) continue;
    if (declared[key]) continue;
    if (key === 'id') throw new Error(`l'action « ${name} » n'accepte pas d'identifiant`);
    throw new Error(`l'action « ${name} » n'accepte pas le paramètre « ${key} »`);
  }

  const argv = [...action.argv];
  for (const [key, spec] of Object.entries(declared)) {
    // Une case vidée vaut « absente », donc le défaut DÉCLARÉ s'applique — pas
    // celui que le workflow porte de son côté. La console envoie ainsi la valeur
    // qu'elle affichait, plutôt que de s'en remettre à un défaut distant qu'elle
    // ne montre nulle part.
    const fourni = values[key];
    const vide = fourni === undefined || fourni === null || fourni === '';
    const raw = vide ? spec.default : fourni;
    if (raw === undefined || raw === null || raw === '') {
      if (spec.required) {
        throw new Error(
          spec.isLegacyID
            ? `l'action « ${name} » exige un identifiant`
            : `l'action « ${name} » exige le paramètre « ${key} »`,
        );
      }
      continue;
    }
    const value = String(raw);
    if (!spec.pattern.test(value)) {
      throw new Error(spec.isLegacyID ? `identifiant refusé : ${value}` : `paramètre « ${key} » refusé : ${value}`);
    }
    // La valeur part TOUJOURS dans son propre élément de tableau. `-f since=2`
    // est un seul élément parce que `gh` l'exige ainsi, mais il n'est jamais
    // concaténé à autre chose que le nom du champ, lui-même constant.
    if (spec.flag) argv.push(spec.flag, `${spec.field}=${value}`);
    else argv.push(value);
  }

  return { action, argv, bin: action.bin ?? null };
}
