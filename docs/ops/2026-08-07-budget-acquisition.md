# Un budget publicitaire pour l'app ? Ce que le modèle de revenus permet de payer

**Date** : 2026-08-07
**S'appuie sur** : `docs/ops/2026-08-07-projections-revenus-publicitaires.md`
**Tranche** : la spec fondatrice §12 posait « aucun budget pub payant en v1 » sans
le démontrer. On peut maintenant le vérifier.

## La réponse

**Non à l'acquisition payante classique, et l'écart n'est pas serré : il faudrait
un coût par installation de 0,20 € là où le marché iOS en Europe de l'Ouest en
demande 1,25 à 3,15 €.** On perdrait entre 1,05 € et 2,95 € par utilisateur
acheté.

Mais deux dépenses se défendent, et une troisième est un pari assumable. Elles
sont chiffrées plus bas.

## Ce que vaut un utilisateur

La valeur vie d'une installation, sur six mois, publicité + achat Pro :

| Scénario | Installs | Pub 6 mois | Pro | Total | **LTV / install** |
|---|---|---|---|---|---|
| Pessimiste | 50 k | 11 169 € | 3 818 € | 14 986 € | **0,300 €** |
| Médian | 250 k | 55 844 € | 25 450 € | 81 294 € | **0,325 €** |
| Optimiste | 1 M | 223 375 € | 127 250 € | 350 625 € | **0,351 €** |

Ce qui rend ce nombre utilisable, c'est sa stabilité : **0,30 à 0,35 € quel que
soit le scénario**, alors que les revenus totaux varient d'un facteur 23 entre
les deux extrêmes. Les installs et les revenus bougent ensemble ; le rapport,
lui, tient. C'est donc une base de décision solide, contrairement aux totaux.

Deux corrections à appliquer avant de s'en servir pour acheter :

- **Un install payant vaut moins qu'un install organique.** Il n'a pas cherché
  l'app, il l'a subie : la rétention chute couramment de 30 à 50 %. On retient
  −40 %, soit **0,195 € de LTV réelle pour un utilisateur acheté**.
- **La LTV dépend des trois chantiers.** Avec la bannière seule, sans
  interstitiel ni correction ATT, elle tombe à 0,19 € organique — soit 0,11 €
  acheté. Toute réflexion sur l'acquisition payante est prématurée tant que la
  spec du 7 août n'est pas livrée.

## Ce que coûte un utilisateur

Références 2026 : le coût par installation iOS mondial atteint 5,84 $ au premier
trimestre, en hausse de 19 % sur un an ; l'Europe de l'Ouest se situe à 3,40 $,
soit environ **3,15 €**. Les campagnes Advantage+ de Meta rendent 20 à 35 % de
moins que les campagnes manuelles — à condition de leur fournir au moins 50
installations par jour pour nourrir la phase d'apprentissage, ce qui est déjà un
budget plancher de 120 €/jour.

| Canal | CPI | LTV acheté | Récupéré | Perte par install |
|---|---|---|---|---|
| Programmatique Europe de l'Ouest, brut | 3,15 € | 0,195 € | 6 % | −2,95 € |
| Meta Advantage+ (−24 %) | 2,39 € | 0,195 € | 8 % | −2,20 € |
| Très bien optimisé, hypothèse favorable | 1,60 € | 0,195 € | 12 % | −1,40 € |
| Apple Search Ads, intention forte | 1,25 € | 0,195 € | **16 %** | −1,05 € |

Autrement dit, 2 000 € dépensés en programmatique :

| | Installs achetés | Revenu récupéré | **Perte sèche** |
|---|---|---|---|
| Europe de l'Ouest brut | 635 | 124 € | **1 876 €** |
| Meta Advantage+ | 837 | 163 € | **1 837 €** |
| Très bien optimisé | 1 250 | 244 € | **1 756 €** |

Le meilleur cas récupère un huitième de la mise.

## Pourquoi c'est structurel, et non un défaut d'exécution

Ce n'est pas un problème de ciblage, de créa ou de canal. **Une app gratuite
financée par la publicité, dont le pic dure dix semaines, n'a mécaniquement pas
assez de valeur par utilisateur pour en acheter sur un marché iOS à 3 €.** Même
en doublant la LTV — ce qu'aucun des chantiers identifiés ne permet — on
resterait à un sixième du coût.

Le corollaire est utile : les leviers qui augmentent la LTV (les trois chantiers,
puis la médiation) valent chacun plus que n'importe quel euro d'acquisition, et
ils sont à somme positive au lieu d'être à somme négative.

## Les trois dépenses qui se défendent

### 1. Apple Search Ads sur son propre nom — défensif, petit, rentable

Le seul poste dont le retour est positif de façon fiable. Le coût par contact
sur son propre nom est très bas — l'app a le meilleur score de pertinence sur
son propre terme — et la conversion est très haute : la personne a tapé « Neon
Compass », elle vient d'une vidéo de créateur ou du bouche-à-oreille. Sans cette
protection, un concurrent peut enchérir sur notre nom et récupérer ce trafic
gratuit que nous avons généré.

**Budget : 5 à 10 €/jour pendant les huit semaines du pic, soit 300 à 550 €.**
C'est la seule ligne que je recommande sans réserve.

### 2. Les créateurs — le seul canal qui puisse franchir la barre

Un partenariat rémunéré avec un créateur GTA n'est pas de la publicité
programmatique : l'audience est parfaitement appariée, et le format — quelqu'un
de confiance qui montre l'app à l'usage — convertit à des taux qu'aucun encart
n'atteint.

Le seuil de rentabilité est calculable. À 0,325 € de LTV, **il faut 3,1
installations par euro dépensé** :

| Cachet | Installs pour rentrer dans ses frais | Sur une vidéo à 200 k vues |
|---|---|---|
| 500 € | 1 540 | 0,8 % des vues |
| 1 500 € | 4 615 | 2,3 % des vues |

Une conversion de 0,8 % pour une app compagnon montrée à une audience GTA
pendant la semaine de sortie est atteignable. Et si la vidéo fait 5 000
installations pour 500 €, le coût par installation effectif tombe à **0,10 €** —
sous la barre des 0,20 €, ce que ne fait aucun canal payant.

C'est donc là que doit aller l'argent. **Budget : 1 500 à 3 000 € répartis sur
quatre à six créateurs de taille moyenne, en français, anglais et espagnol.** La
variance est forte : traiter chaque partenariat comme un billet indépendant, pas
comme un achat de volume. Mention de collaboration commerciale obligatoire.

### 3. Le classement — un pari, pas un investissement

Le seul argument en faveur d'une vraie dépense programmatique : une salve
concentrée le jour de la sortie peut hisser l'app dans un classement, lequel
génère ensuite des installations organiques à coût marginal nul.

**Je ne sais pas chiffrer ce multiplicateur de façon crédible**, et je préfère le
dire que de fabriquer un nombre. Ce qu'on peut dire : la perte directe est
connue (environ 1 850 € par tranche de 2 000 €), le gain ne l'est pas. Pour un
développeur seul avec un budget fixe, c'est un pari, et il doit être nommé comme
tel.

La version gratuite du même mécanisme existe et figure déjà dans la spec
fondatrice : **la pré-commande App Store**. Les pré-commandes se convertissent
toutes le jour de la sortie, ce qui concentre les installations sur vingt-quatre
heures — exactement l'effet recherché, sans dépense.

## Sur les mots-clés « GTA » en Apple Search Ads

Une précision qui revient toujours, et qui mérite d'être posée correctement.

Apple autorise les enchères sur les termes de marque de tiers. La restriction de
la règle 2.3.7 porte sur **les métadonnées et le texte de l'annonce** — nom de
l'app, champ mots-clés, copie publicitaire — **pas sur les enchères**. Enchérir
sur « gta 6 map » n'est donc pas interdit par Apple, alors que l'écrire dans le
champ mots-clés l'est.

Le volet juridique est distinct et n'est pas tranché ici : l'usage d'une marque
comme mot-clé publicitaire relève d'une analyse propre, où ce qui compte est
l'absence de confusion sur l'origine. Notre annonce ne pourrait de toute façon
pas contenir « GTA », et l'app porte un autre nom.

**Mais la question est sans objet sur le plan économique.** Même le trafic le
mieux intentionné du catalogue revient à 1,25 € l'installation, soit six fois la
barre des 0,20 €. Prendre un risque de propriété intellectuelle face à
Take-Two — le risque numéro un du projet — pour un canal qui perd 1,05 € par
utilisateur serait payer deux fois.

## Trois budgets, au choix

| | Contenu | Montant | Retour attendu |
|---|---|---|---|
| **Minimal** | Apple Search Ads sur le nom propre, 5 €/jour × 8 semaines | **400 €** | Positif, faible volume. Protège l'acquis. |
| **Recommandé** | Le minimal + 4 à 6 créateurs FR/EN/ES | **2 500 à 3 500 €** | Positif si un seul partenariat sur trois fonctionne. |
| **Agressif** | Le recommandé + salve programmatique sur les 72 h de sortie | **10 000 €** | Perte directe attendue d'environ 6 000 €, gain de classement non chiffrable. Un pari. |

**Recommandation : le budget recommandé, et pas un euro de programmatique.**
Zéro achat sur Meta, Google ou TikTok en v1 — la spec fondatrice avait raison, et
on sait maintenant pourquoi.

Un dernier arbitrage à garder en tête : le risque numéro un du projet est le
rejet App Store au titre de la propriété intellectuelle. À budget égal, une
réserve pour affronter ce scénario vaut probablement plus que huit cents
installations achetées.

## Ce qui ferait changer d'avis

- **Une LTV mesurée nettement supérieure à 0,33 €.** Si l'eCPM réel dépasse les
  hypothèses de 40 % et que la conversion Pro atteint 3 %, la LTV monte à environ
  0,50 € — soit 0,30 € acheté. Toujours quatre fois sous le coût par
  installation. Il faudrait un facteur dix, pas un facteur deux.
- **Un coût par installation effondré sur un segment précis.** À surveiller sur
  Apple Search Ads dans les pays hispanophones et italophones, structurellement
  moins chers que la France et le Royaume-Uni, où la concurrence sur les termes
  gaming est féroce.
- **Un modèle d'abonnement**, écarté par la spec fondatrice pour cause de churn
  post-pic. C'est pourtant la seule structure de revenus qui rendrait
  l'acquisition payante finançable. Le refus reste justifié — mais il faut savoir
  qu'il ferme aussi cette porte-là.

## Sources externes

- [Mobile App Marketing Benchmarks 2026 — Admiral Media](https://admiral.media/mobile-app-marketing-benchmarks-2026/) — CPI iOS mondial 5,84 $, Europe de l'Ouest 3,40 $.
- [Meta App Install Campaigns: 2026 Guide](https://vmobify.com/blog/meta-app-install-campaigns) — Advantage+ 20-35 % moins cher, seuil de 50 installations/jour.
- [Apple Search Ads in 2026: cost, placements, and bidding](https://adapty.io/blog/apple-search-ads/) — structure des coûts par contact.
- [How to bid on competitor keywords in Apple Search Ads](https://www.rocketshiphq.com/bid-competitor-keywords-apple-search-ads/) — la règle 2.3.7 porte sur les métadonnées et l'annonce, pas sur les enchères.
