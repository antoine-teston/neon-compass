# Sources de données du mode en ligne — plan de récupération

**Date** : 2026-08-02
**État** : lot C1 (extracteur hebdomadaire) livré en preuve de concept ; C2→C5 à planifier.

## Le problème

Tout est là sauf la donnée. `content/schema/online-event.schema.json` existe,
`OnlineEvent`/`OnlineEventsModel`/`OnlineEventCard` s'affichent,
`EventReminderScheduler` programme le rappel, `facts-to-online-event.mjs`
matérialise, `pull-online-events` est câblé dans `veille.yml`, et
`check-originality.mjs` couvre le type. **`content/online-events/` est vide.**

La raison est unique : rien ne produit de fait `kind: "online-event"`. Le seul
producteur prévu est `data-scout`, un agent qui lit des flux et rédige des
`claim` en prose. Or un événement hebdomadaire n'est pas une phrase, c'est un
**tableau** : huit bonus, onze remises, des pourcentages, une fenêtre horaire.
Confier ça à une reformulation en langage naturel, puis demander à
`content-editor` de le re-structurer, c'est deux traversées de modèle pour une
donnée qui est déjà tabulaire à la source — avec le taux d'erreur que ça
implique sur des nombres.

Le plan ci-dessous part donc de l'inverse : **récupérer la structure comme
structure**, et ne garder le modèle que là où il apporte quelque chose (la
langue).

## Ce que « toutes les activités en ligne » recouvre

Relevé sur la semaine du 30/07/2026, qui est représentative. Colonne « porté »
= représentable par le schéma actuel.

| # | Catégorie | Exemple de la semaine | Porté |
|---|---|---|---|
| 1 | Multiplicateurs d'activité | Fleeca Heist Finale, 2× | ✅ `bonuses[]` |
| 2 | Remises en pourcentage | Karin Kuruma, −60 % | ✅ `discounts[]` |
| 3 | Véhicule du podium | *aucun cette semaine* | ✅ `podiumVehicle` |
| 4 | Remises en montant fixe | Art Studio, −1 000 000 | ❌ `percent` est un entier 1-100 |
| 5 | Remises conditionnelles | Hao's Special Works, −50 % **abonnés** | ⚠️ la condition n'a pas de champ |
| 6 | Récompenses à réclamer | livrée Fleeca Circuit, pull Pacific Standard | ✅ `rewards[]` (C4) |
| 7 | Défi hebdomadaire + sa prime | gagner deux modes, 100 000 + tee-shirt | ❌ |
| 8 | Rotations de stock | Gun Van, lineup d'œuvres du Kortz Center | ❌ |
| 9 | Avantages d'abonnement | véhicule offert, +15 % sur les cartes | ⚠️ passe en `bonuses` sans sa condition |
| 10 | Phases d'événement | « semaine 1 sur 2 », bascule le 06/08 | ❌ |
| 11 | Essais chronométrés | *aucun cette semaine* | ❌ |
| 12 | Prize Ride / Test Ride | *aucun cette semaine* | ❌ |

Trois quarts des catégories ne rentrent pas. **Ce n'est pas un défaut du
schéma** : il a été dimensionné pour ce que la carte affiche (spec
`2026-07-31-onglet-social-design.md` §1 — compte à rebours, bonus, remises,
podium). L'extension est un choix produit à faire après C1, pas une évidence :
afficher douze catégories, c'est reconstruire le hub d'un site dans une app.

## Ce que les sources donnent réellement

Mesuré le 2026-08-02, pas supposé. Le registre (`source-policy.mjs`) n'est pas
élargi : les quatre domaines autorisés le restent, Rockstar Newswire et Reddit
restent interdits.

### GTABOOM — le hub hebdomadaire, structuré

`https://www.gtaboom.com/gta-online-weekly-updates` (robots.txt : `Allow: /`)
est une page Next.js dont le payload RSC porte **la donnée déjà structurée**,
avant tout rendu :

```json
{ "id": "04c51a48-…", "currentPhaseEndsAt": "2026-08-05T23:59:59+00:00",
  "bonuses":   [ { "activityName": "Fleeca Heist Finale", "multiplierLabel": "2x GTA$", "details": "…" } ],
  "discounts": [ { "itemName": "Karin Kuruma", "discountLabel": "60% off", "details": "…" } ] }
```

Trois conséquences importantes :

1. **La fin de fenêtre est datée à la seconde par la source elle-même**
   (`currentPhaseEndsAt`). C'est ce qui débloque tout : le schéma exige un
   horodatage UTC complet, et la spec interdit de le calculer par jour de
   semaine. On n'invente aucune heure de reset — on reprend celle publiée.
2. Bonus et remises arrivent **normalisés** (nom, étiquette, détail). Aucun
   parsing de tableau HTML, aucune extraction par le modèle.
3. Le reste de la page (récompenses, Gun Van, phase) n'est **pas** dans ce
   payload : c'est du balisage Tailwind sans attribut sémantique. Les
   catégories 6→12 se paieront en parsing de DOM volatil — argument de plus
   pour ne pas les prendre en C1.

Le début de fenêtre n'est pas dans le payload. Il vient de l'article lié
(`Read the news story` → `/gta-online-summer-heist-event-july-2026`), dont la
date de publication est lue **dans le flux** — donc sans parcourir le site.

### Les autres

| Source | Ce qu'elle apporte pour l'Online | Rôle |
|---|---|---|
| Leonidaverse (flux) | relais de l'update, en prose | corroboration → `multi-source` |
| GTA6.gg | couvre surtout le jeu à venir | marginal ici |
| GTA Wiki (API) | pages de fond (mécaniques, listes de véhicules) | catalogue, pas hebdomadaire |
| Jeu en main | l'écran des remises | vérité de dernier recours, saisie humaine |
| Rockstar Newswire | la source primaire | **interdit** (`ClaudeBot: Disallow: /`) |

Tant qu'une seule source est exploitée, la confiance honnête est
`single-source`. `check-publishable` l'accepte (il ne refuse que `rumor`).

## L'architecture de récupération

Trois étages, un seul ajout par étage :

```
fetch-source.mjs weekly            weekly-hub.mjs              pull-online-events
────────────────────────           ──────────────              ──────────────────
réseau + liste blanche      →      extraction & normalisation   →   content/online-events/*.json
flux (date de l'article)           payload RSC → fait d'inbox        (idempotent par processedFrom)
hub (payload)                      structuré, localisé
```

Ce qui reste hors du chemin : **aucun modèle**. Les noms d'activités et de
biens sont des faits (comme les noms de POI, déjà publiés) et passent tels
quels ; les étiquettes sont **composées** dans les cinq langues à partir du
multiplicateur analysé. `needsRewrite` tombe donc à `false` et l'entrée est
publiable après relecture humaine, sans passage par `content-editor`.

### La cadence : un second cron, pas un run quotidien

La spec de l'onglet Social prévoyait de faire passer `veille.yml` à
l'hebdomadaire → quotidien, et s'en déclarait dépendante. Retenu à la place :
**un second cron le jeudi 16:00 UTC**, qui ne fait que le mode en ligne.

Le lundi seul ne marchait pas, et pas d'un peu : la semaine bascule le jeudi et
finit le mercredi suivant. Récoltée le lundi, elle arriverait avec deux jours de
fenêtre sur sept — or c'est le compte à rebours qui justifie la fonctionnalité.
16:00 laisse quelques heures à la source pour publier après la bascule.

Le quotidien reste écarté pour la raison que la spec pointait elle-même : sept PR
par semaine sans relecture reproduiraient le symptôme que le run hebdomadaire
avait été bâti pour corriger. Deux runs suffisent à rendre le compte à rebours
crédible.

Le run du jeudi ne dépense rien : la récupération est déterministe, donc les
étapes de veille et de rédaction (les deux appels de modèle) sont sautées via
`ONLINE_ONLY`. Un `workflow_dispatch` fait toujours la chaîne complète.

Une dérive de structure chez la source **ne fait pas tomber le reste de la
veille** — `continue-on-error` sur l'étape, puis une étape finale, après
l'ouverture de la PR, qui écrit le compte-rendu dans le résumé du run et fait
rougir le job. Les faits d'actu déjà dans l'inbox continuent d'être
matérialisés ; c'était précisément le mode de panne à éviter.

Corollaire dans `data-scout.md` : l'agent n'émet **plus jamais** de fait
`kind: "online-event"`. L'identité d'un fait est le hachage de
`source_url + claim` — un fait rédigé à la main et un fait extrait porteraient
deux identités pour la même semaine, donc deux cartes concurrentes dans l'app.

### Pourquoi la normalisation ne peut pas recopier les étiquettes

`"2x GTA$"` contient une marque. `TRADEMARKS` (cli.js) la rejetterait sur
`title` ; sur `bonuses[].label` elle passerait aujourd'hui, `UI_FIELDS` ne
couvrant pas les listes — un trou à combler (C2). L'extracteur n'écrit donc
jamais l'étiquette de la source : il l'analyse en `{ times, cash, rp }` puis
la recompose (`2× argent & RP`). Bénéfice secondaire : les cinq langues
arrivent gratuitement, sans traduction à commander.

### Le point dur : l'originalité contre les noms propres

`check-originality.mjs` compare les champs affichés à `sourceClaim` et refuse
toute reprise intégrale. Or `sourceClaim` doit rester **la prose brute de la
source** — c'est ce qui donne sa valeur au contrôle — et cette prose contient
forcément « Fleeca Heist Finale », qui est aussi la valeur de
`bonuses[].activity`. Le contrôle échouerait sur une donnée parfaitement
légitime.

Tranché ainsi : un **nom** n'est pas une **rédaction**. Les champs qui ne
portent qu'un nom propre (`bonuses[].activity`, `discounts[].item`,
`podiumVehicle`) sortent du contrôle de reprise et entrent dans un contrôle
propre — *rester un nom* : pas de ponctuation de phrase, pas plus de huit mots.
On ne peut donc pas faire passer de la prose en la déguisant en nom. Les champs
rédigés (`title`, `bonuses[].label`) restent, eux, comparés à la prose source.

## Ce que C1 produit réellement

Chaîne exécutée en réel le 2026-08-02 sur la semaine du 30/07 :

```sh
node tools/content-cli/fetch-source.mjs weekly --write   # 2 appels réseau
node tools/content-cli/cli.js pull-online-events         # → online_21f049bb.json
cd tools/content-cli && npm run check
```

Sortie : **7 bonus et 10 remises** retenus sur 8 + 11 publiés, `startsAt`
2026-07-30T00:00:00Z → `endsAt` 2026-08-05T23:59:59Z, titre et étiquettes dans
les cinq langues, `needsRewrite: false`, `status: draft`. Les deux entrées
écartées sont nommées dans le compte-rendu, avec leur raison (rotation d'œuvres
sans multiplicateur ; remise en montant fixe).

`validate` 632/632, `check-publishable` 632/632, `check-seeds` à jour,
`check-originality` 61 champs — et les deux garde-fous vérifiés en les faisant
échouer exprès (prose recopiée dans un `label` ; description déguisée en nom).

### `single-source` est publiable pour ce kind — tranché le 2026-08-02

L'entrée sort en `confidence: single-source`. `check-publishable` l'acceptait
déjà (il ne refuse que `rumor`), mais la règle éditoriale de
`content-editor.md` réservait `published` à `confirmed-official` et
`multi-source`, héritée de l'actu. Elle ne s'applique pas ici : **les deux
temporalités n'ont rien à voir.** Une actu spéculative reste fausse pour
toujours ; une semaine du mode en ligne se vérifie en jeu en trente secondes et
périme d'elle-même en sept jours. Exiger `multi-source` n'achèterait qu'une
illusion de rigueur — deux sites qui relaient le même communiqué ne font pas
deux sources indépendantes.

Ce qui tient lieu de garantie est donc la **relecture humaine avant
publication** : le pipeline sort `draft`, un humain passe à `published`.
`content-editor` a désormais la consigne explicite de ne jamais franchir ce pas.
C5 (corroboration Leonidaverse) reste utile pour la confiance affichée, mais
n'est plus un prérequis de publication.

Contrepartie assumée, et traitée : publier ces entrées met à l'écran des textes
que `check-publishable` ne regardait pas. Son filet à marques s'arrêtait à
`UI_FIELDS` (`title`, `note`, `effect`, `body`) alors qu'une carte affiche aussi
`podiumVehicle` et les textes portés par `bonuses[]`/`discounts[]` — or une
étiquette vient tout droit d'une source qui écrit « 2x GTA$ ». Ces champs sont
désormais couverts, sans rejoindre `UI_FIELDS` pour autant : celui-ci sert aussi
à `translate`, qui réclamerait alors une traduction pour des noms propres.

### Une marque peut vivre dans un NOM — tranché le 2026-08-02

Le premier scan a fait échouer notre propre donnée : `bonuses[].activity` valait
« GTA+ Shark Cards ». Réaction initiale : écarter ces entrées à l'extraction.
Elle était fausse, pour trois raisons qui se tiennent.

1. **La règle du projet ne disait pas ça.** `CLAUDE.md` interdit les marques dans
   le nom de l'app, l'icône, le sous-titre App Store et le bundle ID — son
   *identité*. Pas dans le contenu. Le scan appliqué à tout `title` était un
   durcissement jamais énoncé comme tel.
2. **Nommer le produit d'un tiers pour en parler est l'usage référentiel.** C'est
   ce qui permet à la presse spécialisée d'écrire « GTA Online ». « GRAND THEFT
   AUTO » et « GTA » sont bien des marques déposées de Take-Two — la question
   n'est pas là.
3. **Le filtre était incohérent avec lui-même.** Il écartait le bonus
   « GTA+ Shark Cards » tout en laissant passer la remise « Hao's Special Works
   (abonnés) », qui relève du même abonnement. L'incohérence venait du filtre.

D'où l'exception, et elle est étroite : `nominative-fields.mjs` énumère par kind
les champs dont la valeur entière est un nom propre — `bonuses[].activity`,
`discounts[].item`, `podiumVehicle`. Eux seuls échappent au scan de marques. Ce
que nous rédigeons — `title`, `bonuses[].label` — reste interdit.

**L'exception n'est pas gratuite.** Ces champs doivent prouver qu'ils sont des
noms : pas de ponctuation de phrase, huit mots au plus, et **jamais une marque
nue** (« GTA » seul ne nomme rien ; « GTA+ Shark Cards » nomme un produit). On ne
peut donc pas y glisser un slogan déposé.

Détail d'architecture qui compte : `check-publishable` applique le test de nom
**lui-même**, au moment d'accorder l'exception, plutôt que de compter sur
`check-originality` qui utilise pourtant la même notion. Les deux scripts
tournent ensemble dans `npm run check`, ce qui rendait la délégation tentante —
et aurait laissé deux contrôles se renvoyer la responsabilité d'une permission
qu'aucun des deux n'aurait justifiée.

Effet de bord réparé au passage : le `claim` du fait ne compte plus les bonus
retenus. Il ne porte que la fenêtre. Compter les entrées refrappait un `id` à
chaque changement de filtrage — l'entrée déjà relue et publiée de la semaine en
cours s'en trouvait orphelinée, ce qui est arrivé deux fois.

## Découpage

| Lot | Contenu | État |
|---|---|---|
| **C1** | `weekly-hub.mjs`, commande `weekly`, faits structurés honorés par `factToOnlineEvent`, contrôle d'originalité recalibré, tests sur payload réel | **livré (PoC)** |
| **C2** | Entrée dans `veille.yml` avec cron du jeudi, dérive signalée sans emporter le run, filet à marques sur les listes | **livré** |
| **C2b** | Fenêtre mutable : identité par le début, révision au lieu de duplication, sélection déterministe côté app | **livré** |
| **C3** | Catégories 4/5/9 — remise en montant fixe et condition d'abonnement (champs `amount`, `requires`) | à arbitrer |
| **C4** | Catégorie 6 — les récompenses à réclamer : `rewards[]` au schéma, extraction du marquage, section sur la carte | **livré** |
| **C4b** | Catégories 7/8 — défi hebdomadaire chiffré, Gun Van, rotations d'inventaire | pas fait, voir ci-dessous |
| **C5** | Corroboration → `multi-source` | **abandonné, voir ci-dessous.** La détection de source qui se ferme, elle, est livrée |

C3 et C4 sont des décisions produit : chaque catégorie ajoutée est une ligne
d'écran de plus et une source de dérive de plus.

### Les récompenses : la première extraction fragile, traitée comme telle

`rewards[]` porte la catégorie 6 — ce qu'il y a à **réclamer** cette semaine. Une
livrée, un vêtement, un véhicule offert : c'est le contenu le plus périssable de
la carte, il expire avec la fenêtre, et c'est exactement ce que le compte à
rebours existe pour rattraper.

Différence de nature avec tout le reste : **la source ne les publie pas en
JSON.** Elles vivent dans le marquage. L'extraction s'accroche donc à ce qui a le
plus de chances de survivre à un redesign — l'`id` de section, la balise
`<article>`, l'attribut `data-variant="overline"` — et jamais à une classe
Tailwind. Et surtout **elle ne lève jamais** : une carte sans récompenses reste
utile, une semaine perdue parce qu'un `<article>` est devenu un `<li>` ne l'est
pas. Le seuil d'échec ne porte que sur le cœur (bonus et remises).

Deux choix de conception qui se répondent :

- **`kind` est une énumération fermée, pas un libellé.** Contrairement à
  `bonuses[].label`, composé dans le contenu, ce qui s'affiche ici est un texte
  d'interface : il vit donc dans le String Catalog, comme l'exige `CLAUDE.md`. Le
  contenu ne transporte que la nature ; le nom de l'objet, lui, est un fait. Une
  nature hors vocabulaire est **écartée à l'extraction** et signalée — « Autre »
  n'apprendrait rien sur une carte étroite.
- **Le nom passe par le garde-fou nominatif** (`notANominativeName`) avant d'être
  émis. Sans ça, une source qui met une phrase dans son titre ferait échouer
  `check-publishable` sur la semaine ENTIÈRE, et coûterait un aller-retour manuel
  chaque jeudi. C'est la composition qui justifie que ce garde-fou soit un module
  partagé plutôt qu'un bout de code dans un script.

Relevé sur la semaine réelle : 5 récompenses retenues sur 6 cartes, la sixième
(« Gun Van ») écartée et nommée.

### Ce qui n'est pas fait, et pourquoi

**C4b — défi hebdomadaire, Gun Van, rotations.** Le défi arrive déjà en partie
comme récompense (`kind: challenge`), mais sa condition chiffrée (« gagner deux
modes ») est de la prose : la porter demanderait soit un champ rédigé — donc le
retour d'un modèle dans la chaîne, dont tout ce lot s'est employé à sortir — soit
une grammaire de conditions, qui est un projet à elle seule. Le Gun Van est une
liste d'armes avec des remises : c'est un `discounts[]` d'un autre lieu, et
l'afficher demanderait de distinguer les deux sur la carte.

**C3 — remise en montant fixe.** Écarté volontairement. Ça récupérerait **une
ligne par semaine** (« −1 000 000 sur l'Art Studio », réservée aux abonnés) au
prix de rendre `percent` optionnel dans le schéma, donc dans le modèle Swift, donc
dans la carte, qui affiche aujourd'hui « −60 % » sans condition. Un champ de cœur
qu'on rend optionnel pour un cas marginal se paie partout, indéfiniment. La remise
reste **signalée comme écartée** à chaque run : elle est visible, simplement pas
affichée.

### Pourquoi C5 est abandonné, et ce qu'on a fait à la place

La corroboration automatique n'est **pas réalisable avec le registre actuel**,
vérifié le 2026-08-02 plutôt que supposé :

- **Leonidaverse** : son flux ne contient que **deux entrées, datées du
  26 juin**, sur le jeu à venir. Aucune couverture de l'update hebdomadaire du
  mode en ligne.
- **GTA6.gg** : aucun flux au registre, et le registre interdit de parcourir un
  site pour aller chercher une page — donc rien à interroger.
- **GTA Wiki** : des pages de fond, pas des rotations hebdomadaires éphémères.
- **L'article de GTABOOM** corrobore le hub, mais c'est le même éditeur : deux
  pages d'une même maison ne font pas deux sources.

Ajouter une source suppose de lire son robots.txt et de trancher — pas de la
fetcher pour voir. C'est une décision, pas une tâche. `single-source` +
ratification humaine reste donc le régime, ce qui est cohérent avec la décision
de publication ci-dessus.

**En revanche l'autre moitié de la motivation de C5 cachait le mode de panne le
plus dangereux de toute la chaîne, et il est traité.** Si la source cesse de
tenir son hub à jour, la page répond toujours 200 et le payload s'analyse
toujours : rien ne casse. On republierait la semaine dernière indéfiniment, soit
un compte à rebours sur une fenêtre déjà close — pire qu'une carte absente.

`hubToFact` refuse désormais une fenêtre expirée. `now` y est un paramètre
**obligatoire**, jamais lu depuis l'horloge — même discipline
qu'`OnlineEvent.isActive(at:)` côté app, et pour la même raison : un contrôle
temporel dont l'appelant peut omettre le temps est un contrôle qu'on désactive
par accident. Le cas le plus probable en pratique est bénin et le message le dit :
le run du jeudi est passé avant que la source ait publié la semaine.

## Risques

| Risque | Réponse |
|---|---|
| **Le payload RSC est privé et non documenté** — un déploiement de GTABOOM peut le renommer sans préavis | L'extraction lève avec une raison lisible plutôt que de rendre du vide. C2 en fait un échec de run visible. Repli documenté : la page reste lisible en texte, la structure des sections (`#weekly-bonuses`…) est stable |
| Une source unique | `single-source` assumé, C5 corrobore |
| GTABOOM synthétise elle-même l'article (son hub écrit « the article does not state the exact increase ») | La donnée est un relais, pas la vérité primaire. Le jeu en main reste l'arbitre |
| Fenêtre à cheval sur deux phases (« semaine 1 sur 2 ») | Une phase = une entrée. `currentPhaseEndsAt` borne la phase courante, pas l'événement entier — c'est bien ce que le compte à rebours doit annoncer |
| **Une fenêtre MUTE** — la source dit elle-même que Rockstar prolonge parfois un événement | Traité : l'identité tient au DÉBUT de fenêtre (`windowDiscriminant`), donc une prolongation RÉVISE l'entrée au lieu d'en créer une seconde. Deux étages de propriété : la fenêtre appartient toujours à la machine, le reste seulement quand elle en est l'unique auteur. Côté app, `currentEvent(at:)` départage désormais totalement |
| Marques dans les noms de biens | Les noms d'activités et de véhicules sont des références factuelles, comme les POI. `title` reste scanné |
