> **Périmé depuis le 2026-08-02.** La contrainte que ce document décrit a disparu avec la
> migration vers Supabase : les Edge Functions sont incluses dans l'offre gratuite, il n'y a plus
> de plan Blaze à activer, et les cinq surfaces listées ci-dessous n'ont plus de raison d'être
> éteintes. Conservé pour l'historique — c'est lui qui explique pourquoi la v1 était amputée, et
> pourquoi la suppression de compte passait par un contournement client.
>
> Ce qui reste vrai : `backendFeaturesEnabled` gouverne toujours l'allumage, et il vaut toujours
> faux par défaut. Il se pose désormais dans la table `app_config`, plus dans Remote Config.

# Fonctionner sans Blaze — ce qui est coupé, et comment tout rallumer

**Date** : 2026-07-27
**Décision** : pas de plan Blaze pour l'instant. La v1 se soumet sans Cloud Functions.

## Le fait de départ

Les Cloud Functions exigent le plan Blaze. Sans lui, **les dix Functions du dépôt ne sont déployées
nulle part** : `createUserProfile`, `regenerateHandle`, `deleteAccount`, `submitContribution`,
`castVote`, `reportContribution`, `flagSuspiciousContribution`, `notifyFollowedCategory`,
`appStoreServerNotification`, plus `rebuildCommunityBundles` et `flagCommunityBundlesDirty`.

Vérifié le 2026-07-27 : l'API Cloud Functions n'a **jamais été activée** sur `neoncompass-gt-vi`
(`403 — API has not been used in project before`). Aucune Function n'a donc jamais tourné en
production, et ce constat est antérieur à la décision.

Restent gratuits et opérationnels : Firestore, Authentication (Sign in with Apple compris), Remote
Config, FCM, App Check, Analytics, Hosting.

## Ce qui est coupé dans la v1

| Surface | État | Pourquoi |
|---|---|---|
| Contributions communautaires | coupée | `submitContribution` ; les règles interdisent l'écriture cliente |
| Votes, signalements | coupés | idem |
| Pseudo, XP, niveaux | coupés | `createUserProfile` est un déclencheur d'authentification |
| Mes contributions, auteurs bloqués | coupés | dépendent de ce qui précède |
| Notifications de catégorie suivie | coupées | `notifyFollowedCategory` |
| **Sync de progression iPhone↔iPad** | **conservée** | écrit dans `profiles/{uid}/progression`, autorisé par les règles seules |
| Sign in with Apple | **conservé** | gratuit, et c'est ce qui porte la sync |

## Comment c'est gouverné

Un unique paramètre Remote Config, **`backendFeaturesEnabled`**, lu par `RemoteConfigServerFeatureGate`.

**Il échoue fermé**, à l'inverse du coupe-circuit `communityContributionsEnabled` qui échoue ouvert.
Les deux défauts sont opposés délibérément : le coupe-circuit éteint une capacité qui existe, ce
drapeau décrit une capacité qui n'existe pas encore. Se tromper dans un sens n'affiche rien ; se
tromper dans l'autre affiche des écrans qui échouent.

Conséquence pratique : **aucune mise à jour de l'app n'est nécessaire pour rallumer**. Poser le
paramètre à `true` suffit.

## Deux points de conformité, à ne pas perdre de vue

1. **Suppression de compte.** Apple l'exige dès qu'une app permet de créer un compte. La cascade
   serveur (`deleteAccount`) n'étant pas déployée, un chemin client la remplace
   (`FirebaseClientAccountDeletion`) : il efface la progression synchronisée puis le compte Auth,
   dans cet ordre — l'inverse rendrait la progression orpheline et définitivement inaccessible. Le
   périmètre réduit le permet : sans profil ni contributions, il n'y a rien d'autre à effacer.
   `user.delete()` refuse une session ancienne ; l'app affiche alors un message qui demande de se
   reconnecter.
2. **Ne pas vendre ce qu'on ne livre pas.** Le paywall retire de lui-même la ligne « notifications
   suivies » tant que le drapeau est faux. **La fiche App Store devra faire pareil** : annoncer une
   fonction absente est un motif de rejet documenté, pas une maladresse. Le pack Pro compte donc six
   promesses sur sept au lancement.

## Le jour où Blaze est activé

1. Console Firebase → Authentication → activer Sign in with Apple (Services ID, Team ID, Key ID,
   clé `.p8` depuis le compte développeur Apple).
2. Passer le projet en Blaze, et **poser immédiatement une alerte de budget** GCP.
3. `cd functions && npm test && firebase deploy --only functions`.
4. Remote Config : `backendFeaturesEnabled` → `true`.
5. Vérifier que les fragments communautaires se construisent (`content_bundles/community_spots_manifest`
   doit apparaître dans les cinq minutes), puis rajouter la ligne « notifications suivies » à la fiche
   App Store.

Aucune de ces étapes ne demande une mise à jour de l'app.
