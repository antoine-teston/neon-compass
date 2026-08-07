# Projections publicitaires — la bannière contre l'interstitiel

**Date** : 2026-08-07
**Accompagne** : `docs/superpowers/specs/2026-08-07-revenus-publicitaires-design.md`
**But** : décomposer, format par format, l'ARPDAU que la spec fondatrice posait
en bloc entre 0,015 et 0,025 € (§13), et chiffrer ce que chaque chantier
rapporte.

Toutes les hypothèses sont dans le premier tableau. Elles sont discutables une
par une — c'est fait pour.

## Les paramètres

| Paramètre | Valeur | D'où elle vient |
|---|---|---|
| Sessions par utilisateur actif et par jour | 3 | Hypothèse déjà utilisée par les modèles de coût du dépôt (`editeur-interne-design.md`, `community-bundles-design.md`) — on ne change pas de chiffre en cours de route |
| Durée moyenne d'une session | 4 min | App compagnon consultée par à-coups |
| Part du temps passée sur un écran porteur de bannière | 50 % | Le fil, les codes, les guides et Social en portent ; **la carte n'en porte pas**, et c'est l'écran cœur |
| Rafraîchissement de la bannière | 60 s | Réglage de la console AdMob — voir « Le levier à 9 700 € » plus bas |
| Bannières en ligne croisées au défilement | 2 par session | `InlineAdPlacement` intercale tous les 2 à 5 encarts, jamais après la dernière carte |
| **Impressions bannière par session** | **4** | 2 par rafraîchissement + 2 en ligne |
| Sessions où l'on ouvre puis referme un détail du fil ou des codes | 55 % | Les deux sites d'appel retenus par la spec |
| Plafond interstitiel | 1 par session | Session réarmée après 5 min en arrière-plan |
| Taux de remplissage interstitiel | 90 % | Ordre de grandeur AdMob sur l'Europe de l'Ouest |
| **Impressions interstitiel par session** | **0,5** | 55 % × 90 % |

Soit, par utilisateur actif et par jour : **12 impressions de bannière** et
**1,5 impression d'interstitiel**.

### Les eCPM

Ordres de grandeur iOS 2026, hors jeux, sur le mix de langues visé
(FR, EN, ES, IT, DE). Ils ne seront réellement connus qu'après deux semaines en
production — la section « Ce qui peut faire mentir tout ça » les fait varier.

| Format | Publicité personnalisée | Publicité contextuelle |
|---|---|---|
| Bannière | 1,50 € | 0,40 € |
| Interstitiel | 6,00 € | 2,50 € |

L'écart entre les deux colonnes est la raison d'être du chantier 3 : c'est le
taux d'opt-in ATT qui décide de la pondération.

| Taux d'opt-in ATT | Bannière mélangée | Interstitiel mélangé |
|---|---|---|
| **25 %** — demande au 1er lancement, avant le RGPD (l'existant) | 0,675 € | 3,375 € |
| **45 %** — demande à la 2ᵉ session, après le RGPD (le chantier 3) | 0,895 € | 4,075 € |

## L'échelle, barreau par barreau

Chaque ligne ajoute un chantier au précédent. L'ARPDAU est en euros par
utilisateur actif et par jour.

| État | Bannière | Interstitiel | **ARPDAU** | vs. départ |
|---|---|---|---|---|
| 1. Vrais identifiants, bannière seule (ce que livre le chantier 1 seul) | 0,00810 | — | **0,00810** | — |
| 2. + interstitiel branché (chantier 2) | 0,00810 | 0,00506 | **0,01316** | ×1,6 |
| 3. + ATT au bon moment (chantier 3) | 0,01074 | 0,00611 | **0,01685** | ×2,1 |
| 4. + médiation en enchères (spec suivante, +25 % d'eCPM) | 0,01343 | 0,00764 | **0,02107** | ×2,6 |

**Le contrôle qui compte** : la spec fondatrice supposait 0,015 à 0,025 €. Le
modèle par en bas atterrit à 0,0169 une fois les trois chantiers faits, et à
0,0211 avec la médiation. Les deux méthodes se rejoignent — mais la bannière
seule donne 0,0081, soit **sous le plancher de la fourchette**. Autrement dit
les projections de la spec fondatrice ne tiennent que si l'interstitiel est
branché. Il ne l'est pas.

## La réponse à la question : bannière ou interstitiel ?

À l'état 3, celui que livre la spec :

| | Impressions | Part des impressions | Revenu | Part du revenu |
|---|---|---|---|---|
| Bannière | 12 / jour | **89 %** | 0,01074 € | **64 %** |
| Interstitiel | 1,5 / jour | **11 %** | 0,00611 € | **36 %** |

**Une impression d'interstitiel vaut 4,6 fois une impression de bannière.**
L'interstitiel produit un tiers du revenu publicitaire avec un dixième des
impressions — et c'est le format qui, aujourd'hui, n'est jamais affiché.

La bannière reste majoritaire en valeur absolue, mais par le volume, pas par la
qualité. C'est une rente de présence : elle rapporte parce qu'elle est toujours
là, pas parce qu'elle est bien payée.

## Sur trois mois, aux trois scénarios de la spec fondatrice

Revenu publicitaire sur 90 jours = DAU moyen × 90 × ARPDAU. Le Pro retire ses
acheteurs de l'assiette : compter environ −3 %, non répercuté ci-dessous.

| | Pessimiste (4 k DAU) | Médian (20 k DAU) | Optimiste (80 k DAU) |
|---|---|---|---|
| 1. Bannière seule | 2 900 € | 14 600 € | 58 000 € |
| 2. + interstitiel | 4 700 € | 23 700 € | 95 000 € |
| 3. + ATT au bon moment | 6 100 € | 30 300 € | 121 000 € |
| 4. + médiation | 7 600 € | **37 900 €** | 152 000 € |
| *Rappel spec fondatrice* | *5 000 €* | *36 000 €* | *180 000 €* |

Ce que chaque chantier rapporte, au scénario médian et sur trois mois :

| Chantier | Effort | Gain |
|---|---|---|
| 1 — Vrais identifiants + `app-ads.txt` | 1 h, plus un compte et un domaine | **de 0 à 14 600 €** |
| 2 — Brancher l'interstitiel écrit | ~½ journée | **+ 9 100 €** |
| 3 — ATT au bon moment | ~½ journée | **+ 6 600 €** |
| 4 — Médiation Meta / AppLovin / Unity | ~1 journée + deux comptes | **+ 7 600 €** |

Le chantier 2 est le mieux payé du lot : une demi-journée de branchement sur du
code déjà écrit et déjà testé, pour neuf mille euros au scénario médian.

## Le levier à 9 700 €, qui n'est pas du code

Le rafraîchissement automatique de la bannière est un **réglage de la console
AdMob**, pas une ligne de Swift. S'il est laissé désactivé, les deux impressions
par session dues au rafraîchissement disparaissent : il ne reste que les deux
bannières croisées au défilement. Le revenu bannière est divisé par deux, et
l'ARPDAU total tombe de 0,0169 à 0,0115 — **−32 %**.

Au scénario médian, sur trois mois : **9 700 € perdus** pour une case à cocher
oubliée. À vérifier explicitement à la création de l'unité, et non à supposer.

## Ce que coûte l'exclusion de la carte

La spec écarte délibérément la carte comme troisième site de déclenchement, pour
protéger la boucle d'exploration. Le prix de cette décision se chiffre.

Inclure la carte ne créerait pas d'impressions au-delà du plafond d'une par
session : cela ferait simplement atteindre ce plafond plus souvent — la part des
sessions déclenchantes passerait d'environ 55 % à 80 %.

| | Impressions interstitiel / jour | ARPDAU | Médian sur 3 mois |
|---|---|---|---|
| Sans la carte (la spec) | 1,50 | 0,01685 | 30 300 € |
| Avec la carte | 2,16 | 0,01954 | 35 200 € |

**Environ 4 900 €** au scénario médian, 19 400 € à l'optimiste. C'est le prix de
la tranquillité sur l'écran cœur — un prix réel, à assumer sciemment plutôt qu'à
découvrir après coup. La décision reste défendable : la rétention est un
objectif produit de premier rang dans la spec fondatrice, et une app désinstallée
ne rapporte plus rien du tout. Mais elle n'est pas gratuite.

Même raisonnement pour le plafond : le passer de 1 à 2 par session, en supposant
que 30 % des sessions produisent une seconde ouverture-fermeture, vaudrait
+19 %, soit environ 5 800 € au médian. Les deux assouplissements se cumulent
mal — ils puisent dans la même patience.

## La courbe dans le temps

Les tableaux précédents lissent le DAU sur 90 jours. La réalité est une bosse,
et la forme de cette bosse change les conclusions.

### La forme retenue

`DAU(semaine) = plancher + (pic − plancher) × e^(−(s−1)/6)` — une décroissance
exponentielle de constante 6 semaines vers un plancher durable, calée pour que
la moyenne sur 13 semaines retombe sur les DAU moyens de la spec fondatrice.

| Scénario | Pic (semaine 1) | Plancher | Moyenne 13 semaines | Rappel spec |
|---|---|---|---|---|
| Pessimiste | 8 000 | 1 000 | 4 106 | 4 000 |
| Médian | 40 000 | 5 000 | 20 528 | 20 000 |
| Optimiste | 160 000 | 20 000 | 82 113 | 80 000 |

### La saisonnalité, qui joue en notre faveur

Les eCPM mobiles suivent le budget des annonceurs : ils culminent en novembre et
décembre, s'effondrent en janvier. **La sortie de GTA VI, le 19 novembre 2026,
place notre pic d'audience exactement sur le pic annuel des prix.** Les deux
courbes se multiplient au lieu de se compenser.

Coefficients appliqués : ×1,15 en novembre, ×1,30 à 1,35 en décembre, ×0,80 en
janvier, ×0,85 en février. Ce sont des normes de marché, pas des mesures.

L'effet est loin d'être marginal : sur 13 semaines au scénario médian, il porte
le total de 37 900 € (lissé, sans saisonnalité) à **44 100 €**, soit +16 %
gagnés uniquement sur la date de sortie.

### Semaine par semaine, scénario médian, ARPDAU à 0,02107 €

| Semaine | Dates | DAU | Saison | Revenu | Cumul |
|---|---|---|---|---|---|
| 1 | 19-25 nov | 40 000 | ×1,15 | 6 785 € | 6 785 € |
| 2 | 26 nov-2 déc | 34 627 | ×1,20 | 6 129 € | 12 913 € |
| 3 | 3-9 déc | 30 079 | ×1,30 | 5 767 € | 18 680 € |
| 4 | 10-16 déc | 26 229 | ×1,30 | 5 029 € | **23 709 €** |
| 5 | 17-23 déc | 22 970 | ×1,35 | 4 574 € | 28 283 € |
| 6 | 24-30 déc | 20 211 | ×1,35 | 4 024 € | **32 307 €** |
| 7 | 31 déc-6 janv | 17 876 | ×1,05 | 2 768 € | 35 075 € |
| 8 | 7-13 janv | 15 899 | ×0,80 | 1 876 € | 36 951 € |
| 9 | 14-20 janv | 14 226 | ×0,80 | 1 679 € | 38 630 € |
| 10 | 21-27 janv | 12 810 | ×0,80 | 1 511 € | 40 141 € |
| 11 | 28 janv-3 fév | 11 611 | ×0,85 | 1 456 € | 41 597 € |
| 12 | 4-10 fév | 10 596 | ×0,85 | 1 328 € | 42 925 € |
| 13 | 11-17 fév | 9 737 | ×0,85 | 1 221 € | **44 146 €** |

Les deux autres scénarios se déduisent par simple proportion : diviser par 5
pour le pessimiste, multiplier par 4 pour l'optimiste.

| | 13 semaines | Mois 4-6 | **6 mois** |
|---|---|---|---|
| Pessimiste | 8 800 € | 2 300 € | **11 200 €** |
| Médian | 44 100 € | 11 700 € | **55 800 €** |
| Optimiste | 176 600 € | 46 800 € | **223 400 €** |

### Le chiffre à retenir

**Les quatre premières semaines font 54 % du trimestre. Les six premières en
font 73 %.** Et ce n'est pas un artefact du modèle : l'audience décroît pendant
que les eCPM décrochent aussi, en janvier. Les deux effets se composent.

### Ce que coûte le retard

Chaque semaine où la chaîne publicitaire n'est pas complète est une semaine
prise sur la partie la plus chère de la courbe. Scénario médian, sur 13
semaines :

| Retard à la sortie | Encaissé | Perdu |
|---|---|---|
| Aucun | 44 100 € | — |
| 1 semaine | 37 400 € | 6 800 € (**15 %**) |
| 2 semaines | 31 200 € | 12 900 € (29 %) |
| 4 semaines | 20 400 € | 23 700 € (**54 %**) |
| 6 semaines | 11 800 € | 32 300 € (73 %) |

Appliqué au seul interstitiel, qui pèse 36 % de l'ARPDAU et représente 16 000 €
sur le trimestre médian :

| Disponible à partir de | Ce qu'il rapporte | Part du possible |
|---|---|---|
| Semaine 1 (19 nov) | 16 000 € | 100 % |
| Semaine 5 (17 déc) | 7 400 € | 46 % |
| Semaine 9 (14 janv) | 2 600 € | **16 %** |

Livrer l'interstitiel en janvier plutôt qu'au jour J, c'est faire le même
travail pour un sixième du résultat. C'est l'argument le plus fort de tout ce
document : **la demi-journée de branchement doit être faite avant le 19
novembre, pas après.**

## Correction — le « pic de 10 semaines » décrivait la hype, pas l'app

La formule ci-dessus vient de la spec fondatrice §13 : « le pic de revenus dure
6-10 semaines puis décroît fortement ». Reprise telle quelle, elle a été
transformée en une exponentielle unique décroissant vers un plancher. C'était une
erreur de lecture : **ces dix semaines décrivent la durée du battage médiatique
autour de la sortie, pas la durée de vie de l'app.**

Or l'app n'est pas adossée à la hype. Elle est adossée à trois usages qui vivent
aussi longtemps que le jeu : les **codes**, qui sont une référence qu'on
reconsulte à chaque session ; la **carte**, dont la complétion prend des mois et
que le mode en ligne prolonge indéfiniment ; et l'**Actu**, qui donne une raison
de rouvrir entre deux sessions de jeu. GTA V est sorti en 2013 et son mode en
ligne est encore joué en 2026 — ce n'est pas la hype qui dure, c'est le jeu.

Deux formes sont donc à comparer, et la vérité dépend de ce qu'on livre.

| | Modèle A — hype pure | Modèle B — service vivant |
|---|---|---|
| Constante de décroissance | 6 semaines | 8 semaines |
| Plancher durable (médian) | 5 000 DAU (2,0 % des installs) | 8 000 DAU (3,2 %) |
| Relances de contenu | aucune | trimestrielles |
| **6 mois** | 56 200 € | **74 200 €** |
| **12 mois** | 75 100 € | **108 100 €** |

**Le modèle B rapporte 44 % de plus sur douze mois.** Et il redistribue : dans le
modèle B, les 13 premières semaines font 52 900 € et les 39 suivantes 55 200 €.
**La traîne vaut légèrement plus que le trimestre de lancement.**

### La surprise : les relances de contenu ne valent presque rien

C'est le résultat le plus utile du remodèle, et il contredit l'intuition.

| Rythme de relance (plancher 8 000) | 12 mois |
|---|---|
| Aucune relance | 103 300 € |
| Deux par an | 105 900 € |
| Trimestrielle | 108 100 € |
| Mensuelle | 110 800 € |

**7 % d'écart entre rien et une relance par mois.** À côté :

| Plancher durable | 12 mois |
|---|---|
| 3 000 DAU (1,2 % des installs) | 75 400 € |
| 5 000 DAU (2,0 %) | 88 400 € |
| 8 000 DAU (3,2 %) | 108 100 € |
| 12 000 DAU (4,8 %) | 134 200 € |
| 16 000 DAU (6,4 %) | 160 400 € |

**Un facteur 2,1 sur le plancher, contre 1,07 sur les relances.** L'arithmétique
est évidente une fois écrite : une bosse de +50 % pendant deux semaines, quatre
fois par an, ne pèse rien face à cinquante-deux semaines de plancher.

Conséquence de conception, et elle est contre-intuitive : **l'Actu ne gagne pas
son existence par ses pics, mais par le plancher qu'elle soutient.** Un fil qui
fait revenir massivement le jour d'une annonce puis laisse repartir tout le monde
ne vaut presque rien. Un fil qui donne une raison d'ouvrir chaque semaine, même
sans événement, vaut le double du reste du modèle.

Réserve sur cette conclusion : les relances sont modélisées comme transitoires —
les revenants repartent. Si une annonce majeure convertit durablement des
utilisateurs perdus, elle agit alors sur le plancher, et non sur un pic. C'est
précisément la métrique à surveiller : **une relance de contenu doit être jugée
sur le plancher qu'elle laisse derrière elle, pas sur le pic qu'elle produit.**

### Ce qui doit être vrai pour que le modèle B l'emporte

Le plancher n'est pas une hypothèse de marché, c'est une conséquence de ce qu'on
livre. Trois conditions, dont deux sont des engagements et non des fonctions :

1. **Les codes doivent être complets et exacts au jour J.** C'est de la donnée de
   référence : quelqu'un qui cherche un code, ne le trouve pas et file sur un
   wiki ne revient pas. Un catalogue à 80 % ne retient pas 80 % des gens.
2. **La couverture de la carte doit dépasser celle des wikis.** Difficulté connue
   et déjà inscrite au registre des risques : la vraie carte n'est pas connue
   avant la sortie.
3. **L'Actu doit être réellement alimentée**, chaque semaine, dans cinq langues,
   indéfiniment. C'est une opération de contenu, pas une fonctionnalité — et un
   fil vide est pire que pas de fil, parce qu'il enseigne qu'il est inutile
   d'ouvrir l'app.

Tant que ces trois-là ne sont pas tenues, c'est le modèle A qui s'applique.

### Ce qui ne change pas

L'argument de la date de sortie tient dans les deux modèles : les quatre
premières semaines restent 54 % du trimestre, et le trimestre reste la moitié de
la première année. **Livrer en retard coûte exactement autant qu'annoncé.** Le
désaccord porte sur ce qui vient après, pas sur l'urgence.

## Ce qui peut faire mentir tout ça

Les eCPM sont le paramètre le plus incertain, et le plus multiplicatif.
Sensibilité à l'état 4, scénario médian :

| Hypothèse eCPM | Trois mois |
|---|---|
| −40 % (mix géographique défavorable, inventaire mal valorisé) | 22 800 € |
| Retenue | 37 900 € |
| +40 % (pic de sortie, demande saisonnière forte) | 53 100 € |

Les autres fragilités, par ordre d'impact décroissant :

1. **Le DAU**, qui commande tout linéairement. L'écart entre pessimiste et
   optimiste est un facteur 20 ; il écrase toutes les optimisations de format.
2. **Le taux d'opt-in ATT réel.** Les 45 % visés sont un ordre de grandeur de
   marché, pas une promesse. À 30 %, le chantier 3 ne rapporte plus que 1 700 €
   au médian au lieu de 6 600 — c'est le seul des quatre chantiers dont le gain
   puisse fondre des trois quarts sans que rien n'ait été mal fait.
3. **La part du temps passée sur la carte.** Si elle monte à 70 % au lieu de
   50 %, les impressions de bannière tombent de 12 à 7,2 par jour et l'ARPDAU
   perd 25 %. La carte est le cœur de l'app et n'a pas de bannière : c'est
   cohérent, mais ça coûte.
4. **Le plancher durable.** C'est le paramètre décisif de toute la première
   année, et le moins étayé — voir la section « Correction » ci-dessus, qui lui
   est entièrement consacrée. Il fait varier le total à douze mois d'un facteur
   2,1 sur sa plage plausible, là où le rythme des relances de contenu ne le
   fait varier que de 1,07.
5. **La constante de décroissance.** Six à huit semaines est une hypothèse de
   forme. Plus courte, tout se concentre davantage sur le premier mois et
   l'argument du retard devient plus dur encore ; plus longue, la traîne pèse
   plus lourd. Le classement des chantiers ne change dans aucun des deux cas.

## À mesurer dès la première semaine en production

Trois nombres, et le modèle se recale tout seul :

- **eCPM réel par format et par pays** — remplace la table d'hypothèses.
- **Taux d'opt-in ATT observé** — arbitre à lui seul l'intérêt d'aller plus loin
  sur le sujet.
- **Part des sessions qui déclenchent un interstitiel** — le 55 % est
  l'hypothèse la plus fragile du modèle, et c'est celle qui décide si la carte
  doit finir par entrer dans la boucle.
