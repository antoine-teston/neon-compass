// Le carnet de hotfix — les gestes correctifs, en données pures.
//
// Un geste correctif n'est pas un bouton. C'est une fiche à quatre champs,
// écrite à froid : ce que ça fait, ce que ça coûte, comment savoir que ça a
// marché, comment revenir en arrière. On les écrit calme, on les lit à 23 h.
//
// Deux règles tiennent ce fichier :
//
//   1. Un geste dont on ne sait pas ÉNONCER le retour arrière n'entre pas au
//      carnet — il reste une commande au terminal. « Sans objet, l'opération est
//      idempotente » est une réponse valable ; « je ne sais pas » ne l'est pas.
//   2. Le défaut de tout champ dangereux est le sûr. Les gestes `destructive`
//      exigent une confirmation explicite côté serveur, comme partout ailleurs.
//
// Ce fichier ne décide RIEN de ce qui peut s'exécuter : c'est `actions.mjs` qui
// tient la liste blanche. Le carnet n'est qu'une vue par-dessus, plus les quatre
// champs. Un geste qui référence une action inexistante est une erreur attrapée
// par les tests, pas un silence.

/**
 * Le cache d'`app_config`, et pourquoi il apparaît dans presque toutes les
 * fiches.
 *
 * Vérifié le 2026-08-07 dans `NeonCompass/Core/Config/SupabaseAppConfig.swift` :
 * les valeurs sont mémorisées dans `cached`, SANS durée de vie, et le seul
 * `invalidate()` du fichier n'a aucun appelant dans l'app. Conséquence à ne pas
 * découvrir pendant un incident : **une bascule d'`app_config` n'atteint un
 * utilisateur qu'au prochain lancement à froid.** Ce n'est pas un coupe-circuit
 * instantané, et le présenter comme tel serait le pire endroit où se tromper.
 */
export const APP_CONFIG_LATENCE =
  "N'atteint un client qu'à son prochain lancement à froid : "
  + 'SupabaseAppConfig met en cache sans durée de vie, et invalidate() n’a aucun appelant.';

/**
 * Le carnet, ORDONNÉ. L'ordre n'est pas alphabétique — c'est celui dans lequel
 * on tend la main pendant un incident : arrêter l'hémorragie, puis réparer,
 * puis republier.
 */
export const CARNET = [
  {
    action: 'kill-switch-off',
    quoi: 'Ferme la soumission de spots communautaires.',
    cout: `Les spots déjà approuvés restent visibles. ${APP_CONFIG_LATENCE}`,
    verification: '« État du coupe-circuit communauté » doit rapporter DISABLED.',
    retour: 'Le geste inverse — « Rouvrir les contributions ».',
  },
  {
    action: 'kill-switch-on',
    quoi: 'Rouvre la soumission de spots communautaires.',
    cout: APP_CONFIG_LATENCE,
    verification: '« État du coupe-circuit communauté » doit rapporter ENABLED.',
    retour: 'Le geste inverse — « Couper les contributions ».',
  },
  {
    action: 'deploy-function',
    quoi: 'Redéploie une edge function depuis `main`, par le workflow Functions.',
    cout:
      'Une fonction non déployée ne casse rien — elle rend l’ANCIENNE réponse, '
      + 'ce qui est invisible tant qu’on ne compare pas. Le déploiement lit '
      + 'supabase/config.toml, donc les `verify_jwt = false` sont préservés.',
    verification:
      'tools/edge-functions/drift.mjs ne doit plus signaler cette fonction. '
      + 'Sonde sans écriture : resoumettre à la même position déclenche la '
      + 'déduplication, donc un 409 dont on lit le corps — `code` absent = ancienne version.',
    retour: 'Redéployer depuis le commit précédent.',
  },
  {
    action: 'republish-bundles',
    quoi: 'Repose le drapeau `dirty` et reconstruit les fragments communauté.',
    cout:
      'À faire après un déploiement qui change la FORME du fragment. Sans lui, '
      + 'la reconstruction n’agit que sur changement d’une CONTRIBUTION ou après '
      + 'une heure : le déploiement paraît alors sans effet, indéfiniment.',
    verification: 'Comparer un fragment publié au champ attendu.',
    retour: 'Sans objet — idempotent : reconstruit depuis l’état courant de la base.',
  },
  {
    action: 'migrations-dry',
    quoi: 'Liste les migrations qui seraient appliquées, sans rien appliquer.',
    cout: 'Aucun. C’est la répétition, à faire avant l’autre.',
    verification: 'La sortie liste les migrations en attente.',
    retour: 'Sans objet — n’écrit rien.',
  },
  {
    action: 'migrations-apply',
    quoi: 'Applique les migrations en attente à la base de production.',
    cout: 'Écrit en base. Une migration appliquée ne se retire pas.',
    verification:
      'supabase/tests/privileges_test.sql — lecture pure, donc sûr contre la '
      + 'production. Le workflow le lance lui-même après application.',
    retour:
      'Une migration inverse à écrire, à relire et à appliquer. Il n’y a pas de '
      + 'bouton — c’est précisément pourquoi la répétition existe.',
  },
  {
    action: 'content-source',
    quoi: 'Change `contentBaseURL` : sortie de secours vers un autre hébergeur, sans mise à jour de l’app.',
    cout: `« off » rend l’app à son socle embarqué, donc au contenu figé du binaire. ${APP_CONFIG_LATENCE}`,
    verification: '« Source de contenu actuelle » doit rapporter la nouvelle valeur.',
    retour: 'Reposer l’ancienne valeur, ou « off ».',
  },
];

/** Les fiches par nom d'action, pour l'affichage. */
export const FICHES = Object.fromEntries(CARNET.map((f) => [f.action, f]));
