# Profil complet — les Défis rejoignent le Profil, les réglages en sortent

**Date** : 2026-07-31
**Statut** : validé, prêt pour le plan d'implémentation
**Prépare** : `2026-07-31-onglet-social-design.md` (qui prend l'emplacement libéré)

## Le problème

Deux onglets sur cinq ne méritent pas leur place, chacun pour la raison inverse
de l'autre.

**Les Défis n'ont rien qui les retienne.** `ProgressionScreen` affiche une carte
par jeu (anneau + lignes de défis) et une carte de trophées à cocher. C'est
juste, c'est utile — mais ça se consulte, ça ne se visite pas. Un onglet entier
pour un écran qu'on ouvre après avoir coché dix POI, puis plus jamais.

**Le Profil est un dépotoir de réglages.** `ProfileScreen.swift` empile dans un
seul `VStack(spacing: 24)` : badge Pro, catégories suivies, sélecteur de thème,
bascule d'icône d'app, bouton de connexion Apple, handle, badge niveau/XP,
régénération du handle, mes contributions, contributeurs bloqués, déconnexion,
suppression de compte. Aucune hiérarchie, aucune identité — et pour un
utilisateur non connecté, l'onglet se réduit à un bouton « Se connecter avec
Apple ». Or l'immense majorité ne se connectera jamais : le compte ne sert qu'aux
contributions et à la sync Pro.

La spec fondatrice prévoyait d'ailleurs autre chose. §5 : « L'Actu est l'écran
d'accueil par défaut ; **les réglages sont une icône** ». Cette intention n'a
jamais été appliquée ; les réglages ont atterri dans le Profil par défaut, pas
par décision.

Le lien entre les deux problèmes : **les Défis marchent sans compte.** La
progression vit dans SwiftData, en local. Les verser dans le Profil donne à
l'onglet un contenu utile aux 90 % qui ne se connecteront jamais, et donne aux
Défis une page qu'on rouvre pour voir son anneau monter.

## Ce qu'on construit

### Navigation

```
avant : [ Actu ] [ Codes ] [ ● CARTE ] [ Défis ] [ Profil ]
après : [ Actu ] [ Codes ] [ ● CARTE ] [ Social ] [ Profil ]
```

`AppTab.progress` est supprimé. `AppTab.social` prend sa position — l'utilisateur
ne réapprend rien, le Profil ne bouge pas.

L'écran Social lui-même est hors périmètre de ce spec : voir
`2026-07-31-onglet-social-design.md`. Ici on se contente de libérer
l'emplacement. Si le plan A est livré seul, `AppTab` passe temporairement à
quatre cas — c'est valide et testable en l'état.

**Pas de migration à prévoir.** `AppModel.selectedTab` est un simple défaut
`.feed` non persisté (`App/AppModel.swift:6`) : aucune valeur brute `"progress"`
ne traîne dans les préférences d'un utilisateur déjà installé.

### La page Profil

Un `ScrollView` de sections sur verre, dans cet ordre :

| Section | Contenu | Compte requis |
|---|---|---|
| **Identité** | Handle, niveau, barre d'XP vers le niveau suivant, rang contributeur, badge Pro | Non |
| **Progression** | Une carte par jeu : anneau + lignes de défis | Non |
| **Trophées** | La carte à cocher existante | Non |
| **Mes contributions** | Liste + statuts (en attente / approuvé / rejeté) | Oui |

**L'entête d'identité hors connexion** n'est pas un mur. Elle affiche un titre
neutre et l'anneau de progression global, avec une invitation à se connecter en
pied de section — jamais en travers du contenu. Un utilisateur non connecté doit
pouvoir consulter toute sa progression sans jamais croiser un obstacle.

**Le rang contributeur** (« 342ᵉ ») est lu depuis `profiles/{uid}`, écrit par la
Function planifiée du spec B. Tant que B n'est pas livré, le champ est absent et
la ligne ne s'affiche pas — la page n'en dépend pas.

### Les réglages sortent

Un `SettingsScreen` ouvert par une icône d'engrenage dans la toolbar du Profil.
Il reçoit, déplacés sans changement de comportement :

- Thème néon (Pro) et icône d'app alternative (Pro)
- Catégories suivies (Pro + serveur actif)
- Contributeurs bloqués, avec déblocage
- Connexion / déconnexion Apple
- Suppression de compte, avec sa confirmation et ses deux chemins (cascade
  serveur ou effacement local selon `ServerFeaturesModel`)
- Le bouton d'accès au paywall pour les non-Pro

Ce découpage a un effet concret au-delà de l'esthétique : « Supprimer mon
compte », action destructrice et irréversible, cesse de cohabiter à 200 px de
l'anneau de progression.

## Architecture

### Ce qui bouge, ce qui ne bouge pas

**Ne bouge pas — et c'est délibéré :**

- `ProgressionModel`, `ChallengeProgressCalculator`, `Trophy`, `TrophyProgress` :
  la logique de progression est déjà autonome et couverte
  (`ProgressionModelTests`, `ChallengeProgressCalculatorTests`, `TrophyTests`).
  Aucune ligne n'y est touchée.
- `ProgressionListView` : déplacé tel quel, réutilisé comme sous-vue.
- Le chargement du modèle (`ProgressionScreen.loadModel()`, quatre `ContentStore`
  + réconciliation de sync) part **intact** dans un `ProgressionSection`
  autonome que le Profil embarque.

**Pourquoi ne rien fusionner ici.** `RootView.hydrateWidgetSummaryFromCache()`
construit déjà un second `ProgressionModel` au lancement pour alimenter le widget
avant toute visite d'onglet (`App/RootView.swift:162-201`), et
`ProgressionScreen.reattachSyncIfNeeded()` referme une course entre l'entitlement
Pro et la construction du modèle. Ces deux mécanismes sont subtils et tous deux
issus de bugs réels. Les toucher en même temps qu'un déplacement d'écran mêlerait
deux risques sans rapport. Le déplacement est mécanique ; il le reste.

**Est extrait :**

| Nouveau | Depuis | Pourquoi |
|---|---|---|
| `Core/Auth/AppleSignInCoordinator` | `ProfileScreen` (nonce, SHA-256, `handleSignInResult`) | Aujourd'hui enfermé en `private static` dans une vue : **non testable**. C'est du protocole cryptographique, l'endroit le plus mal choisi pour ne pas avoir de test |
| `Features/Settings/SettingsScreen` + `SettingsModel` | `ProfileScreen` (thème, icône, catégories, blocages, compte) | — |
| `Features/Profile/ProfileHeaderView` | `ProfileScreen` (`levelBadge`) | — |
| `Features/Profile/ProgressionSection` | `ProgressionScreen` | Porte le chargement, pas la mise en page |

`ProfileScreen.swift` fait 354 lignes pour trois responsabilités mêlées : la vue,
le protocole Sign in with Apple et l'orchestration de quatre modèles
(`ProfileModel`, `CommunityModel`, `FollowedCategoriesStore`, `ThemeStore`). Y
verser les défis sans rien sortir le porterait au-delà de 600. L'extraction n'est
pas du refactoring opportuniste : sans elle, le fichier devient impossible à
tenir en tête d'un seul tenant.

### Flux de données

Rien de nouveau. Le Profil lit :

- `ProgressionModel` → défis, anneau, trophées (SwiftData local, sync Pro)
- `ProfileModel` → handle, niveau, XP, rang (Firestore, lecture seule)
- `CommunityModel` → mes contributions
- `AuthModel` → connecté ou non
- `ProEntitlementModel` → badge Pro

`SettingsScreen` reçoit les mêmes instances par l'environnement — aucune n'est
dupliquée, aucune n'est reconstruite à l'ouverture de la feuille.

## Erreurs et états dégradés

| Situation | Comportement |
|---|---|
| Non connecté | Progression et trophées pleinement consultables ; identité en version neutre ; « Mes contributions » absent, pas vide |
| `ServerFeaturesModel` faux | Handle, XP, contributions et catégories suivies absents (comportement actuel conservé) ; la progression locale reste entière |
| Hors ligne | Tout s'affiche depuis SwiftData ; la sync Pro échoue en silence, comme aujourd'hui |
| Aucun défi n'a de total connu | Pas d'anneau plutôt que 0 % — règle existante de `ProgressionListView`, conservée : afficher 0 % dirait « tu n'as rien trouvé » là où la vérité est « on ne sait pas encore combien il y en a » |
| Échec de connexion Apple | Alerte avec le détail technique — comportement actuel, déplacé dans `SettingsScreen` |
| Rang contributeur absent | La ligne ne s'affiche pas |

## Tests

**Ne doivent pas régresser** : `ProgressionModelTests`,
`ChallengeProgressCalculatorTests`, `TrophyTests`, `ProfileModelTests`,
`AuthModelTests`, `FollowedCategoriesStoreTests`, `SmokeTests`.

**Nouveaux**, tous en logique pure, sans I/O :

- `AppleSignInCoordinatorTests` — le nonce a la bonne longueur et le bon
  alphabet, le SHA-256 est celui attendu pour une entrée connue, une annulation
  utilisateur n'est pas signalée comme une erreur, un identifiant d'un type
  inattendu l'est. Aucun de ces cas n'a de test aujourd'hui.
- `SettingsModelTests` — le chemin de suppression choisi suit
  `ServerFeaturesModel` (cascade serveur ou effacement local).
- Test de fumée de navigation : `AppTab.allCases` ne contient plus `progress`, et
  chaque cas restant rend un écran.
- `LocalizationCoverageTests` couvre automatiquement les nouvelles clés dans les
  cinq langues.

## Ce qui n'est pas fait ici

- L'écran Social lui-même (spec B).
- Toute évolution du calcul de progression, de la sync, ou du widget.
- La fusion des deux chemins de construction de `ProgressionModel` — le doublon
  entre `RootView` et l'écran est connu, documenté, et laissé tel quel.
- Le classement public (spec B) ; seul le rang personnel est affiché, quand il
  existe.
