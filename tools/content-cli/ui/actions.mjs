// Liste blanche des actions exposées par la console web.
//
// C'est la pièce de sécurité du dispositif. Un serveur HTTP local qui lance des
// commandes est un vecteur d'exécution de code : rien de ce qui vient de la
// requête ne doit jamais atteindre une ligne de commande. D'où ce modèle —
// chaque action est un `argv` FIXE, désigné par une clé. Les seules données
// variables sont des identifiants, passés en éléments de tableau distincts (donc
// jamais interprétés par un shell) et validés par `idPattern`.
//
// `destructive: true` signifie « écrit en production » : le serveur exige alors
// une confirmation explicite dans le corps de la requête ET la présence des
// credentials.

import { join } from 'node:path';

const CLI = 'cli.js';
const BASEMAP = join('..', 'basemap');

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
  import: {
    label: 'Ré-importer la carte de référence',
    group: 'local',
    hint: 'Refetch les dumps amont. Long, et réseau. Les ids existants sont réutilisés.',
    argv: [join(BASEMAP, 'gtav-poi.mjs')],
    writesRepo: true,
    slow: true,
  },

  // --- Production : credentials + confirmation ------------------------------
  release: {
    label: 'Publier',
    group: 'prod',
    hint: 'Contrôles, push Firestore, bump de contentVersion. Fait re-télécharger le contenu à tous les clients.',
    argv: [CLI, 'release'],
    destructive: true,
  },
  'deploy-rules': {
    label: 'Déployer firestore.rules',
    group: 'prod',
    hint: 'Remplace le ruleset actif du projet live',
    argv: [CLI, 'deploy-rules'],
    destructive: true,
  },
  'kill-switch-status': {
    label: 'État du coupe-circuit communauté',
    group: 'prod',
    argv: [CLI, 'kill-switch'],
    needsCredentials: true,
  },
  'kill-switch-on': {
    label: 'Réactiver les contributions',
    group: 'prod',
    argv: [CLI, 'kill-switch', 'on'],
    destructive: true,
  },
  'kill-switch-off': {
    label: 'Couper les contributions',
    group: 'prod',
    argv: [CLI, 'kill-switch', 'off'],
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

/// Identifiants Firestore et UID : alphanumériques, tirets, underscores. Assez
/// permissif pour tout ce que Firebase génère, assez strict pour exclure tout
/// ce qui ressemble à un chemin, un espace ou un métacaractère.
export const ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

/**
 * Construit l'`argv` d'une action. Lève plutôt que de deviner : une action
 * inconnue, un identifiant manquant ou mal formé sont des erreurs, jamais des
 * cas à rattraper au vol.
 */
export function resolveAction(name, { id } = {}) {
  const action = ACTIONS[name];
  if (!action) throw new Error(`action inconnue : ${name}`);

  const argv = [...action.argv];
  if (action.needsID) {
    if (!id) throw new Error(`l'action « ${name} » exige un identifiant`);
    if (!ID_PATTERN.test(id)) throw new Error(`identifiant refusé : ${id}`);
    argv.push(id);
  } else if (id) {
    throw new Error(`l'action « ${name} » n'accepte pas d'identifiant`);
  }

  return { action, argv };
}
