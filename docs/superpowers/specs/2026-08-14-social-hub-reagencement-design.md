# Onglet Social — réagencement en hub à deux gabarits

**Date** : 2026-08-14
**Statut** : validé sur maquette (itération 3 — vitrine communautaire en
module), prêt pour le plan d'implémentation
**Maquette** : artefact « Maquette — Social en hub à sections », itération 3,
validée le 14/08 (https://claude.ai/code/artifact/2f19e0d5-3c55-4924-becd-ea9c36910bcc)
**Prolonge** : `2026-07-31-onglet-social-design.md` (les piliers),
`2026-08-04-contributions-communautaires-design.md` (le vote),
`2026-08-10-hub-communautaire-design.md` (annuaire et promotion)
**Amende** : la disposition en volets de la spec du 31/07 (§L'écran) et le
« troisième volet » de la spec du 10/08 (§L'annuaire dans le Social). Les
piliers demeurent tels quels — c'est leur agencement qui change.

## Le problème

L'onglet Social est un sélecteur à segments qui bascule entre trois volets
exclusifs (Événements, Propositions, Communautés). Six défauts, dont aucun
n'est cosmétique :

1. **Le sélecteur ne passe pas à l'échelle.** Trois segments aujourd'hui,
   quatre avec le LFG v1.1 — et le volet Événements empile déjà une deuxième
   barre de segments (V/VI) sous la première, le motif que la spec du 31/07
   qualifiait elle-même d'illisible. En allemand et en espagnol, quatre
   libellés seraient tronqués.
2. **Tout ce qui n'est pas le volet actif est invisible.** Trois propositions
   à voter, un événement samedi, un rang qui bouge : aucun signal ne traverse
   les volets, alors que la boucle de rétention est le produit de l'onglet.
3. **Le classement est mal rangé** — dans Événements, alors qu'il est le
   versant « gloire » de la boucle contribution (proposer → voter → XP → rang).
4. **Des segments qui apparaissent et disparaissent** selon `serverFeatures`
   et `app_config`, c'est un sélecteur qui change de forme entre deux
   lancements. Des sections dans un flux absorbent ça sans étonner personne.
5. **iPad** : une colonne de 640 pt centrée dans 13 pouces, à rebours du cas
   d'usage compagnon-à-côté-de-la-télé.
6. **La grammaire est datée.** Le segmented picker comme navigation principale
   est un motif iOS 7 ; la grammaire actuelle est le hub à sections, et
   Liquid Glass s'y prête exactement.

À quoi s'ajoute l'exigence produit posée par Antoine : **le maximum de
features visibles au premier écran**, et une hiérarchie qui dit ce qui compte —
le vote d'abord, car c'est lui qui alimente la carte VI en POI ; puis, dès
qu'elle existe, la vitrine des communautés promues, mise en valeur aussi mais
secondairement, car cette visibilité est ce que l'abonnement Spotlight vend ;
le classement enfin, résumé tant que la base de contributeurs se construit.

**Écarté d'office** : éclater le Social entre les autres onglets (événements
vers Feed, classement vers Profil). La spec du 31/07 justifie l'onglet par les
événements, et le Feed vit sur `publishedAt` quand un événement vit sur
`endsAt` — deux temporalités qu'on a déjà refusé de mélanger.

## Le principe : deux gabarits

Le hub est un seul flux vertical, sans segments. Chaque pilier y vit dans un
de deux gabarits :

| Gabarit | Largeur | Rôle | Qui l'occupe |
|---|---|---|---|
| **Module** | pleine | on agit dedans — contenu vivant, ou vitrine payée | le héro « Cette semaine », « À voter », la vitrine Communautés (v1.1) |
| **Tuile** | demie (grille 2 colonnes) | une ligne vivante + un accès | Classement ; puis Coéquipiers |

L'ordre du flux : **héro → À voter → vitrine Communautés (v1.1) → grille de
tuiles → bannière.**

Trois règles tiennent le système :

- **Une section sans contenu disparaît** — la règle `showsGamePicker`
  généralisée. La grille se compacte ; une tuile orpheline s'étire en pleine
  largeur. Avant le 19 novembre, drapeaux fermés, le hub c'est le héro seul
  et la bannière — pas de trou, pas de « bientôt ».
- **Les drapeaux gouvernent l'existence, la version gouverne la forme.**
  `serverFeatures` et `app_config` continuent d'allumer ou d'éteindre une
  section ; le passage d'une feature de tuile à module (ou l'inverse) est une
  décision de design livrée par version d'app. Piloter une *forme* par
  `app_config` créerait deux dispositions à maintenir et à tester — et son
  cache sans TTL ferait cohabiter les deux selon l'heure du dernier lancement
  à froid.
- **La vitrine payée naît module, jamais tuile.** La visibilité des
  communautés promues est le produit même de l'abonnement Spotlight : la
  résumer en tuile viderait ce que l'abonné paie. Dès l'allumage du hub
  communautaire, Communautés et Événements forment donc un module sous
  « À voter » — mis en valeur, mais secondaire. La spec du 10/08 promettait
  le carrousel « en haut du volet » ; le volet n'existant plus, la promesse
  devient : premier module après « À voter », plus la mise en avant dans
  l'annuaire. À refléter dans la page produit de l'abonnement avant sa mise
  en vente — rien n'est vendu aujourd'hui, la promesse n'a pas de client.

## Le héro « Cette semaine »

Compact et **paginé par jeu** : une carte par jeu pourvu d'événements,
**VI en premier**, glissement horizontal avec points de page. Un seul jeu
pourvu = une seule carte, pas de points — la règle actuelle du sélecteur,
transposée. Le picker segmenté V/VI de l'écran disparaît.

La carte tient en deux lignes :

- **Ligne 1** : pastille du jeu (`Game.shortLabel`, chiffres romains nus),
  intitulé de la semaine, et le rebours — l'unique accent lumineux de
  l'écran.
- **Ligne 2** : les deux premières entrées (bonus puis remises, l'ordre du
  contenu), condensées, suivies de « +N › » qui ouvre la fiche complète de la
  semaine (la `OnlineEventDetailSheet` existante).

Le rebours s'affiche par `Text(timerInterval:)` — auto-actualisé, sans
minuterie à entretenir — et la sélection de la semaine courante est réévaluée
à la minute par `TimelineView(.everyMinute)`. Le pipeline Combine de
`SocialScreen` et l'import qui l'accompagne disparaissent. Les règles de fond
ne bougent pas : jamais de rebours négatif, état vide honnête, rappel local à
`endsAt − 24 h` reprogrammé à la synchronisation.

**Le rebours épinglé.** Quand le héro sort de l'écran, son rebours se replie
en capsule de verre flottante en haut du flux, portant le jeu de la page
active. Le seuil de bascule est une valeur pure extraite (donc testée), réglée
à l'œil au simulateur — la maquette part de « héro masqué à 92 % ».

## Le module « À voter »

Juste sous le héro : c'est lui qui alimente la carte VI en POI, il prime tant
que la base de contributeurs se construit. Il existe sous la même condition
que le volet Propositions aujourd'hui — `serverFeatures`, et des propositions
à montrer.

- **Jusqu'à trois propositions** de la section « À découvrir » — l'ordre
  existant, qui donne leur chance aux spots pas encore votés.
- **Vote inline** par `ContributionRow`, sans navigation. Déconnecté : la
  même alerte qu'aujourd'hui.
- **Pastille** sur le titre de section : le nombre de propositions visibles
  que *je* n'ai pas votées (`visibleSpots` moins `myVotes`, calcul local,
  zéro serveur).
- **« Proposer un spot »** remonte en pied de module — l'élan naît en votant,
  et la porte était jusqu'ici enfouie dans le volet. Mêmes gardes que
  l'existant (alerte si déconnecté, `ContributeHintSheet` sinon).
- **« Tout › »** ouvre l'écran complet des propositions (l'actuel
  `ContributionsPanel`, en sheet), avec ses deux sections et le bouton
  contribuer en bas.

## La vitrine Communautés (v1.1)

Sous « À voter », dès l'allumage du hub communautaire : un module en
**rangées retirables**, qui est l'espace que l'abonnement Spotlight vend.

- **Le carrousel des promues** — réservé aux communautés Spotlight : cartes
  compactes (badge ✦, nom, plateforme, tranche de membres), tri et plafond
  de la spec du 10/08 (`promoted_until` décroissant, 5 max). Aucune promue :
  pas de carrousel.
- **Les prochains événements** — jusqu'à trois lignes (type, communauté,
  date), triées par `starts_at`. Seules les promues peuvent en poster : cette
  rangée aussi est de l'espace payé. Une ligne ouvre la fiche de la
  communauté. Aucun événement : pas de rangée.
- **« Annuaire › »** en tête de module — l'accès à l'annuaire complet
  (l'actuel `CommunitiesPanel` : filtres, liste, création), en sheet ou en
  panneau. Présent tant que le module existe.

Réduit à son accès annuaire, le module devient une simple barre pleine
largeur — même dégradation que le reste du hub, jamais une rangée vide.
L'accent du module est le ✦ rose Spotlight ; avec le cyan du rebours et de la
pastille, la règle des trois accents tient.

## La grille de tuiles

Deux colonnes en largeur compacte. Chaque tuile : un titre en petites
capitales, **une ligne vivante**, une sous-ligne, un chevron. Une tuile est un
bouton entier ; son contenu quand la donnée manque n'est pas un état vide —
la tuile disparaît.

| Tuile | Ligne vivante | Sous-ligne | Ouvre | Existe si |
|---|---|---|---|---|
| **Classement** | le meneur (« VoltRider en tête ») | mon rang si connecté, sinon le nombre de contributeurs | classement complet : podium top 3 + liste (le `LeaderboardSection` actuel) | `serverFeatures` et des lignes |
| **Coéquipiers** *(v1.1)* | — | — | — | n'existe pas tant que le LFG n'est pas construit ; la grille l'absorbera |

Le podium du classement quitte donc le premier écran : il vit dans la vue
complète. Il retrouvera de la place quand la base de contributeurs le
justifiera — par version, comme le reste des formes.

## Navigation

Toutes les vues complètes et les fiches s'ouvrent en **sheet** avec leur
propre `NavigationStack` — jamais de stack sur un écran d'onglet, la règle du
projet. Les sheets existantes (`CommunityDetailSheet`, `CreateCommunitySheet`,
`ContributeHintSheet`, `OnlineEventDetailSheet`) sont réutilisées telles
quelles.

**En largeur régulière**, les mêmes contenus s'ouvrent en **panneau latéral**
au lieu d'une sheet — le motif que CLAUDE.md impose. La disposition iPad :
héro compact pleine largeur, puis « À voter » en colonne large à gauche ; à
droite, la vitrine Communautés puis la grille de tuiles. Tout l'état d'un
seul regard, sans défiler.

## Signaux, et rien de plus

- La pastille « À voter » (ci-dessus).
- **Un point sur l'onglet Social** dans `CompactTabBar` quand une semaine pas
  encore vue est synchronisée — « vue » = l'identifiant de l'événement
  courant, mémorisé localement à l'ouverture de l'onglet. `CompactTabBar` est
  à nous, aucun mécanisme système à détourner.
- Pas de badge sur les tuiles : un événement a une date, pas de notion de
  « nouveau pour moi ». Retenue : le cyan du rebours et de la pastille, le
  ✦ rose de la vitrine — et rien d'autre.

## Ce qui ne bouge pas

Aucun changement serveur, de contenu ni de modèle : `OnlineEventsModel`,
`CommunityModel`, `CommunitiesModel`, les repositories, les drapeaux, les
rappels locaux, la RLS. `SocialScreen` est recomposé : l'énumération `Panel`
disparaît, `availablePanels` devient `availableSections` — même logique de
gardes, plus la garde de contenu par section. La bannière garde ses
conditions : du contenu affiché, et pas d'abonné Pro.

## Accessibilité, localisation, performance

- **Dynamic Type** : en taille XXL la ligne des bonus passe à la ligne, le
  rebours ne se tronque jamais ; les tuiles grandissent en hauteur.
- **VoiceOver** : le héro paginé s'annonce (« Semaine VI, page 1 sur 2 »),
  chaque tuile est un élément unique au label combiné.
- **Localisation** : clés `social.hub.*` dans le String Catalog, cinq
  langues ; libellés de section courts, pensés pour l'allemand.
- **Performance** : un `GlassEffectContainer` par zone, animer la commande
  jamais la liste, ombres bornées — les trois leçons déjà payées.

## Tests

- `availableSections` : chaque combinaison de drapeaux et de contenu, dont la
  tuile orpheline et le hub réduit au héro.
- L'ordre des pages du héro : VI avant V quand les deux jeux sont pourvus, une
  page sans points sinon.
- La pastille : `visibleSpots` moins `myVotes`, et sa disparition à zéro.
- Le seuil d'épinglage du rebours : valeur pure, testée aux bornes.
- La tuile Classement : meneur, mon rang absent si déconnecté, tuile absente
  sans lignes.
- La vitrine : chaque rangée disparaît seule (sans promue, sans événement),
  et le module se réduit à l'accès annuaire.
- Le point d'onglet : nouvelle semaine → présent, ouverture de l'onglet →
  mémorisé, même semaine re-synchronisée → absent.
- `LocalizationCoverageTests` sur les nouvelles clés.
- Et la vérification à l'écran, iPhone et iPad — les deux derniers défauts
  d'UI de cet onglet n'ont été vus qu'au simulateur.

## Livraison

| Palier | Contenu | Cible |
|---|---|---|
| **H1** | recomposition de `SocialScreen` : héro paginé compact, module À voter, tuile Classement, sheets, épinglage, pastille, point d'onglet, mosaïque iPad | v1 — remplace les volets avant la soumission d'octobre |
| **H2** | la vitrine Communautés : carrousel des promues, rangée d'événements, annuaire en sheet/panneau, suppression du volet `.communities` | avec l'allumage du hub communautaire et de l'abonnement (paliers C2-C4 de la spec du 10/08) |

H1 se suffit : drapeaux fermés, l'onglet reste le héro et sa bannière, comme
aujourd'hui. Note de planning : H1 touche l'écran v1 — chantier d'UI pur, sans
migration, à caser avant la soumission d'octobre.

## Risques

| Risque | Parade |
|---|---|
| Le héro compact cache des bonus | « +N › » ouvre la fiche complète ; la carte montre toujours les deux premières entrées |
| La densité recule en Dynamic Type XXL | L'ordre du flux porte la hiérarchie ; rien ne se tronque, ça défile |
| Régression visuelle en recomposant un écran livré | Captures simulateur avant/après ; les règles de garde existantes sont reprises en tests |
| La promesse Spotlight « en haut du volet » n'a plus de volet | Reformulée ici (premier module après À voter) avant toute mise en vente — aucun client existant |
| Deux gabarits = deux formes à maintenir par feature | Borné par la règle : une tuile n'affiche qu'une ligne vivante et une sous-ligne |

## Ce qui n'est pas fait ici

- Le LFG lui-même (spec à part, horizon v1.1 inchangé).
- Un mode édition du hub (réordonner les tuiles à la Fitness) — rien ne le
  justifie à quatre tuiles.
- Widget, historique des semaines passées, notifications nouvelles : déjà
  écartés par les specs amont, rien ne change.
