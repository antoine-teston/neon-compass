# Les revenus publicitaires — encaisser avant d'optimiser

**Date** : 2026-08-07
**Statut** : validé, prêt pour le plan d'implémentation
**Prolonge** : `docs/superpowers/plans/2026-07-23-plan-6a-ads.md`, qui a posé la
bannière, le consentement et la politique de plafonnement — mais qui a laissé
hors de son périmètre, explicitement, le point de déclenchement de
l'interstitiel.

## Le problème

L'app ne peut rapporter strictement rien aujourd'hui, et ce n'est pas une
question de réseau publicitaire.

- `NeonCompass/Support/Info-Ads.plist` porte `ca-app-pub-3940256099942544~1458002511`,
  l'App ID de test publiquement documenté par Google. Idem pour la bannière
  (`BannerAdView.swift:64`) et l'interstitiel (`AdMobInterstitialProvider.swift:53`).
  Il n'existe pas de compte AdMob.
- Il n'y a pas d'`app-ads.txt`, ni de domaine pour le servir. Sans ce fichier à
  la racine du site développeur déclaré dans App Store Connect, l'inventaire est
  classé « vendeur non autorisé » et une part des acheteurs programmatiques
  refuse d'enchérir dessus.
- L'interstitiel est écrit et testé, mais **jamais déclenché** :
  `InterstitialCapPolicy.shouldShow` n'est appelé de nulle part. Le fichier le
  dit lui-même dans son commentaire.
- L'ATT est demandé au premier lancement (`RootView.swift:40`), avant le
  formulaire RGPD et avant que l'utilisateur ait vu la moindre valeur. C'est
  l'ordre inverse de celui que Google recommande, et le pire moment possible
  pour un opt-in — or l'opt-in gouverne le CPM.

Ces quatre défauts sont multiplicatifs entre eux, et tous multiplient zéro tant
que le premier tient.

## Ce qu'on écarte, et pourquoi

**Remplacer AdMob par Meta Audience Network.** C'était la demande d'origine.
Meta Audience Network est en enchères uniquement depuis 2021 : ses conditions
éditeur n'autorisent l'intégration que « via une intégration approuvée par Meta,
comme un fournisseur de technologie d'enchères approuvé ». MAN n'est donc pas un
remplaçant d'AdMob mais une source de demande qui se branche dans une couche de
médiation — et AdMob est justement une de ces couches. « Passer sur Meta au lieu
d'AdMob » n'est pas une option que Meta offre.

**Ajouter la médiation Meta / AppLovin / Unity maintenant.** Reporté à une spec
suivante, pas abandonné. Le gain typique est de 15 à 40 % d'eCPM, mais il
s'applique à un revenu qui vaut zéro tant que les identifiants sont ceux de
test. Meta a par ailleurs fait un bond réel sur iOS le 27 janvier 2026 (+125 %
d'eCPM en moyenne sur un panel de dix apps) — mais sur **vidéo récompensée et
interstitiel, dans des jeux**. Sur un mix dominé par la bannière, il faut
attendre le bas de la fourchette, et le gain sera plus grand une fois
l'interstitiel réellement branché. Deux points à lever tôt le moment venu : Meta
valide chaque app, et une app compagnon non officielle autour d'une IP AAA n'est
pas un dossier neutre chez eux ; le seuil de versement est de 100 $ cumulés.

**Les cellules natives du fil.** Déjà reportées par le plan 6a, pour la même
raison qu'alors : elles réclament un type de contenu publicitaire et un flux
éditorial qui leur sont propres.

**La vidéo récompensée.** C'est le format au plus fort eCPM du marché, mais il
lui faut une récompense — et toutes les récompenses évidentes de cette app
(plafond du carnet d'épingles, thèmes) sont précisément ce que Pro vend. Une
décision produit doit précéder toute ligne de code ; elle n'est pas prise.

**Le format App Open.** Taillé pour une app ouverte dix fois par jour, donc
tentant ici, mais c'est le format le plus détestable quand il est mal dosé, et
la rétention est un objectif produit de premier rang dans la spec fondatrice.
Écarté pour la v1.

## Chantier 1 — Les identifiants réels, sans servir de vraie pub en développement

Remplacer les constantes par les vrais identifiants suffirait à faire de chaque
lancement en simulateur du trafic invalide : la règle AdMob interdit de servir
et de cliquer de vraies publicités en développement, et la sanction est la
suspension du compte. Le remplacement doit donc être conditionnel dès le premier
jour, pas « après, quand on y pensera ».

**`NeonCompass/Core/Ads/AdUnits.swift`** — un seul endroit qui expose les
identifiants de la bannière et de l'interstitiel, avec un `#if DEBUG` qui rend
les unités de test de Google et, en Release, les vraies. Les identifiants
d'unité ne sont pas des secrets : ils sont lisibles dans le binaire de n'importe
quelle app publiée. Pas d'xcconfig, pas de trousseau, pas d'indirection — ce
serait de la cérémonie sans bénéfice. `BannerAdView` et
`AdMobInterstitialProvider` cessent de porter la leur en dur.

**L'App ID ne peut pas porter de `#if`**, puisqu'il vit dans un fichier de
propriétés. `Info-Ads.plist` reçoit `$(GAD_APP_ID)`, et `project.yml` définit la
variable par configuration sous `settings.configs.Debug` / `.Release`. Le projet
utilise déjà ce mécanisme pour les clés de partage de fichiers en Debug : c'est
un motif de la maison, pas une invention. L'App ID et les unités doivent rester
cohérents entre eux dans une même configuration — un App ID de test avec une
unité réelle ne sert rien et n'échoue pas bruyamment.

**`app-ads.txt`** — une ligne, `google.com, pub-XXXXXXXXXXXXXXXX, DIRECT,
f08c47fec0942fa0`, servie à la racine du domaine déclaré comme site développeur
dans App Store Connect. Le domaine n'est pas encore acquis ; le fichier est donc
spécifié ici et son hébergement reste une tâche d'ops. Le fichier grandira d'une
ligne par partenaire quand viendra la médiation. Un hébergement sous
`*.supabase.co` a été envisagé et écarté : Google exige la racine du domaine
déclaré, que nous ne contrôlerions pas.

## Chantier 2 — L'interstitiel déclenché

Trois manques et un piège.

**Le point de branchement.** Aucun onglet n'a de `NavigationStack`, et les
détails ne sont même pas présentés de la même façon d'une feature à l'autre :
`NewsDetailView` est une vraie feuille (`FeedListView.swift:43`), `POIDetailView`
est construit à la volée dans `MapScreen.swift:641`, `CheatReaderView` est posé
en ligne dans `CheatsScreen.swift:53`. Il n'existe donc aucun point de passage
unique à intercepter. On introduit **`InterstitialCoordinator`**, `@Observable`,
posé dans l'environnement par `RootView`, avec une seule entrée publique —
`contentConsumed()`. Les écrans l'appellent à la fermeture d'un détail et ne
savent rien du reste. Le coordinateur consulte, dans cet ordre : l'entitlement
Pro, le réglage serveur, puis `InterstitialCapPolicy` — dont la logique reste
pure et inchangée, son unique modification étant le renommage de paramètre
ci-dessous.

**Le moment, et les deux endroits.** À la fermeture d'un écran de détail :
l'utilisateur a obtenu ce qu'il venait chercher et revient à une liste, c'est la
pause naturelle qu'attend la règle AdMob. Jamais à l'entrée d'une tâche, jamais
en pleine lecture, jamais pendant une contribution — cette dernière interdiction
est déjà portée par `InterstitialCapPolicy`.

Deux sites d'appel, pas trois :

1. `FeedListView` — à la fermeture de `NewsDetailView` ;
2. `CheatsScreen` — à la fermeture du lecteur de code ou d'un guide.

**La carte est délibérément exclue.** C'était le troisième site évident, et il
est écarté. La spec fondatrice protège la carte de la publicité pendant
l'interaction, et c'est précisément là que le geste s'enchaîne : on ouvre une
fiche POI, on la referme, on en ouvre une autre, dix fois de suite en explorant.
Une pleine page au milieu de cette boucle est l'interruption la plus coûteuse
que l'app puisse produire, sur l'écran qui justifie son existence. On y
reviendra si les deux autres sites se révèlent trop maigres — ce sera une
mesure, pas une intuition.

**Le nom mensonger.** Le paramètre `remoteConfigFrequency` nomme un outil parti
avec Firebase, et son propre commentaire annonce que « renommer attendra le
branchement de l'interstitiel ». C'est ce branchement : il devient
`serverFrequency`, alimenté par `app_config` via le chemin qui sert déjà
`ServerFeatures`. La valeur zéro reste le coupe-circuit, actionnable sans mise à
jour de l'app.

**Pro, une fois pour toutes.** `BannerAdView` ne se protège pas elle-même :
c'est chaque écran qui teste `isProEntitled` (`FeedListView.swift:53`). Ce motif
est tolérable pour une bannière, où un oubli se voit ; il ne l'est pas pour une
pleine page servie à un client payant. Le coordinateur porte la garde en
interne, une seule fois, et aucun site d'appel n'a à y penser.

**Le piège iPad.** Le plafond vaut « un par session » et `sessionShownCount` vit
en mémoire : la session, c'est donc la vie du processus. Or le cas d'usage phare
de l'iPad est la tablette posée à côté de la télé toute la soirée — le processus
ne meurt jamais et « un par session » devient « un par jour ». On introduit
**`InterstitialSession`**, un type pur à horloge injectée qui compte les
présentations et se réarme après un séjour d'au moins cinq minutes en
arrière-plan. Le plafond redevient ce que la spec fondatrice voulait dire.

## Chantier 3 — L'ATT au bon moment, et dans le bon ordre

**L'ordre s'inverse** : `disclaimer → UMP → ATT`, et non plus
`disclaimer → ATT → UMP`. C'est le flux que Google documente — écran RGPD, puis
explication ATT, puis boîte système — et il a une conséquence forte : si
l'utilisateur refuse au formulaire RGPD, la boîte ATT n'est jamais présentée.
Demander l'IDFA à quelqu'un qui vient de refuser le consentement, c'est brûler
l'unique demande que le système autorise par installation.

Le signal existe déjà et se fait jeter : `ConsentProviding.requestConsent()`
rend un `Bool` — « peut-on demander des pubs » — que `OnboardingModel:44`
écrase avec `_ = try? await`. Il suffit de cesser de le perdre.

**Le démarrage du SDK se découple de l'ATT.** `RootView.swift:72-74` attend
aujourd'hui que les trois portes soient franchies avant `MobileAds.shared.start()`.
Repousser l'ATT repousserait alors toute la publicité avec lui, soit l'inverse
du but. La règle devient : le SDK démarre dès que l'UMP est résolu et sert du
contextuel ; l'ATT, quand il arrive, fait basculer vers le personnalisé. Servir
des publicités avant l'ATT est le fonctionnement normal du SDK, pas un
contournement — sans autorisation, il n'utilise simplement pas l'IDFA.

**La demande arrive à la deuxième session.** Un compteur de lancements persisté
dans `UserDefaults`, à côté des trois drapeaux qu'`OnboardingModel` y tient
déjà ; l'explication n'apparaît qu'au deuxième démarrage. Quelqu'un qui revient
a déjà jugé l'app utile et accepte bien plus volontiers — c'est là qu'est
l'essentiel du gain d'opt-in, et la publicité personnalisée vaut couramment deux
à trois fois la contextuelle.

**L'écran d'explication est le nôtre**, pas celui d'UMP. Un message ATT hébergé
par la console Privacy & messaging éviterait un écran à coder et serait
modifiable sans mise à jour, mais il s'affiche pendant le flux de consentement,
au premier lancement : il rendrait la bascule à la deuxième session impossible.
Le texte passe donc par le String Catalog, traduit dans les cinq langues comme
le reste de l'app.

**Un garde-fou** : `requestTrackingAuthorization` échoue en silence si l'app
n'est pas active. La demande doit être attachée à un moment où l'app est au
premier plan, et non à un `.task` susceptible de courir pendant une transition.
Et si le statut ATT est déjà déterminé, l'explication n'est jamais représentée.

## Tests

Quatre suites, toutes sans I/O ni appareil.

- **`AdUnitsTests`** — en Debug, toute unité rendue est une unité de test
  documentée par Google. Les tests tournent en Debug : un vrai identifiant
  glissé dans la mauvaise branche fait échouer la suite au lieu de facturer des
  impressions frauduleuses. C'est le seul test des quatre dont l'absence
  coûterait un compte.
- **`InterstitialSessionTests`** — le compteur se réarme après cinq minutes
  d'arrière-plan et pas avant, quatre minutes cinquante-neuf ne suffisent pas,
  et un aller-retour instantané ne réarme rien. Horloge injectée.
- **`InterstitialCoordinatorTests`** — un abonné Pro ne voit jamais rien ;
  `serverFrequency` à zéro coupe tout ; un chargement raté ne présente rien et
  ne relance pas en boucle. `InterstitialAdProviding` est déjà un protocole, la
  doublure est gratuite.
- **`OnboardingModelTests`** — l'ATT n'est pas demandé quand le consentement est
  refusé, ni au premier lancement, et l'est au second. `defaults` et
  `consentProvider` sont déjà injectables.

Chaque test doit être vu échouer avant d'être cru : un contrôle qui ne sait
qu'approuver est indiscernable d'un bon.

## Échecs

Aucun ne bloque l'app.

| Ce qui rate | Ce qui se passe |
|---|---|
| Chargement publicitaire | On renonce en silence. Une tentative par moment éligible, jamais de boucle de reprise — la règle AdMob sanctionne les requêtes excessives. |
| UMP | Traité comme « pas de consentement » : le SDK démarre et sert du contextuel. |
| ATT déjà statué | L'explication n'est jamais représentée. |
| `app_config` injoignable | `serverFrequency` retombe sur sa valeur par défaut, l'interstitiel reste possible. Un coupe-circuit qui s'arme tout seul en cas de panne réseau serait un coupe-circuit qui coupe au pire moment. |

## Ce qui dépend de l'humain

Le code livré reste sur les identifiants de test tant que ces trois-là manquent.
C'est le comportement voulu, pas une régression.

1. Créer le compte AdMob et l'app, relever l'App ID et les deux identifiants
   d'unité.
2. Acquérir un domaine, y servir `app-ads.txt`, le déclarer comme site
   développeur dans App Store Connect, puis lancer la vérification côté AdMob.
3. Ajouter la clé de coupe-circuit de l'interstitiel dans `app_config`.

## Ce qui vient après

Dans cet ordre, et chacun dans sa spec : la médiation en enchères (Meta Audience
Network, AppLovin, Unity comme sources de demande dans AdMob), puis les cellules
natives du fil, puis — si et seulement si une récompense qui ne cannibalise pas
Pro se dégage — la vidéo récompensée.

## Sources externes

- [Meta Audience Network Terms](https://www.facebook.com/ads/manage/audience_network/publisher_tos) — l'intégration doit passer par un fournisseur d'enchères approuvé par Meta.
- [Integrate Meta Audience Network with bidding | iOS](https://developers.google.com/admob/ios/mediation/meta) — l'adaptateur existe côté médiation AdMob.
- [Meta is Back on iOS — Audience Network iOS Performance 2026](https://www.gamebizconsulting.com/newsletter/admon-newsletter-8-meta-is-back-on-ios) — le bond du 27 janvier 2026, et son panel restreint.
- [About Audience Network payments](https://en-gb.facebook.com/business/help/1664302973836952) — seuil de versement de 100 $.
- [ATT explainer message — AdMob](https://support.google.com/admob/answer/10115027) — explication puis boîte système ; l'ordre RGPD d'abord.
