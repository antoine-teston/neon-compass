# Nom de l'app — la marque en descripteur, jamais en nom propre

**Décidé le 8 août 2026.** Remplace l'interdiction absolue de la contrainte IP
(`CLAUDE.md`) pour le nom, le sous-titre et les mots-clés App Store. L'icône et
le bundle ID restent interdits de marque, sans exception.

Nom App Store retenu, base anglaise : **`Neon Compass: GTA 6 Companion`**.

## Pourquoi rouvrir

Ce n'est pas un revirement, c'est le rendez-vous que la spec fondatrice s'était
donné. `2026-07-19-neon-compass-companion-design.md` §221 écrivait, à propos des
mots-clés App Store :

> y glisser « GTA » est une pratique répandue mais c'est un motif de rejet
> documenté ; on s'en abstient pour la review de lancement, **réévaluation
> ensuite**.

La même section actait la conséquence de l'interdiction : « la découvrabilité ne
viendra pas du nom ». Pour une app compagnon, c'est un prix très élevé — la
requête « GTA 6 » *est* le canal d'acquisition, et le budget d'acquisition est
nul (`2026-08-07-budget-acquisition.md`). D'où la réévaluation.

## Le raisonnement : la position de la marque, pas sa présence

L'interdiction d'origine traitait « GTA apparaît » comme le fait déclencheur.
C'est le mauvais critère, et le projet le sait déjà : `nominative-fields.mjs`
distingue depuis le 2 août la marque qui **désigne** un produit tiers de la
marque qui **s'approprie** une identité. Cette décision étend la même distinction
du contenu vers l'identité.

Ce qui compte est la position syntaxique :

| Forme | Ce que ça dit | Verdict |
|---|---|---|
| `GTA 6 Companion` | *on s'appelle GTA* | Interdit — la marque est le nom propre |
| `Neon Compass: GTA 6 Companion` | *on s'appelle Neon Compass, et on parle de GTA 6* | Autorisé — usage référentiel |
| `Companion for GTA` | marque nue | Interdit — voir ci-dessous |

**La marque nue échoue au test que le projet s'applique déjà.**
`notANominativeName` (dans `nominative-fields.mjs`) refuse `GTA` seul au motif
qu'il ne désigne aucun produit, là où `GTA+ Shark Cards` en désigne un. La même
règle vaut ici : le descripteur doit nommer **le jeu**, donc porter son numéro.
`GTA 6` plutôt que `GTA` — et `6` plutôt que `VI`, qui est la graphie officielle
de Rockstar mais pas celle que les gens tapent dans une barre de recherche.

## Trois emplacements, trois régimes

Le point qui a failli faire dériver le chantier vers un renommage de 372
fichiers : ces trois noms sont indépendants, et la décision n'en touche qu'un.

| Emplacement | Limite | Valeur | Vit où |
|---|---|---|---|
| Nom App Store | 30 car. | `Neon Compass: GTA 6 Companion` | App Store Connect — **pas dans le dépôt** |
| Nom écran d'accueil | ~12 car. lisibles | `Neon Compass` | `project.yml` |
| Identité technique | — | `NeonCompass`, `co.antoineteston.NeonCompass` | inchangée |

L'écran d'accueil tronque au-delà d'une douzaine de caractères : y mettre « GTA »
ne produirait rien de lisible. L'identité technique reste vierge de marque
délibérément — un bundle ID propre est ce qu'on veut pouvoir montrer si Apple ou
Take-Two demandent, pas une dette à rembourser.

**Défaut corrigé au passage.** Aucun `INFOPLIST_KEY_CFBundleDisplayName` n'était
défini : l'écran d'accueil affichait `NeonCompass`, sans espace, hérité du
`PRODUCT_NAME`. La clé est désormais posée explicitement.

## Les cinq noms de boutique

Le champ nom de l'App Store est localisable par boutique. Il fait 30 caractères,
et c'est la contrainte qui a éliminé la formulation initiale
(`Neon Compass - Compagnon pour GTA`, 33 caractères).

```
EN  Neon Compass: GTA 6 Companion     29
FR  Neon Compass : Compagnon GTA 6    30
ES  Neon Compass: Compañero GTA 6     29
IT  Neon Compass: Compagno GTA 6      28
DE  Neon Compass: GTA 6 Begleiter     29
```

Le français est exactement à la limite : toute retouche de ponctuation le fait
déborder. C'est voulu — l'espace insécable avant le deux-points est la
typographie correcte et on ne la sacrifie pas.

La demande d'un « terme international » se règle d'elle-même dans cette
structure. `Compass` devient la partie nom propre, qui n'a aucune raison de se
traduire ; `Companion`, qui partage sa racine latine en FR/ES/IT, est le
descripteur, et il est localisé par boutique de toute façon.

## La règle qui remplace l'interdiction

Dans `CLAUDE.md`, la contrainte IP passe d'une liste d'emplacements interdits à
une règle de position :

- **Nom, sous-titre et mots-clés App Store** — la marque est admise **en
  descripteur, après un nom propre qui nous appartient**, et seulement si elle
  nomme le jeu (`GTA 6`, pas `GTA`).
- **Icône et bundle ID** — interdiction absolue, inchangée.
- **Notes internes et documentation** — n'ont jamais été couvertes par la
  contrainte, qui porte sur ce qu'on expédie. Explicité pour couper court.

## Ce que ça ne change pas

Rien dans la chaîne de contenu. `TRADEMARKS` (`cli.js`), `check-publishable`,
`nominative-fields.mjs` et leurs tests restent à l'identique : la prose qu'on
rédige nous-mêmes reste interdite de marque, les champs nominatifs gardent leur
exception et leur contrepartie. Cette décision emprunte le raisonnement de ce
mécanisme, elle n'y touche pas.

## Risque résiduel

C'est la forme la plus défendable, pas une forme sûre.

La règle 5.2.1 de l'App Store (propriété intellectuelle) est appliquée au cas par
cas, et Take-Two fait retirer des projets de fans avec constance. `Neon Compass:
GTA 6 Companion` est la construction que la presse spécialisée et les apps
compagnons établies utilisent, mais elle ne garantit ni le passage en review ni
l'absence de signalement.

Signaux qui rouvriraient la décision :

- rejet App Review citant 5.2.1 ou 4.1 ;
- mise en demeure ou signalement Take-Two ;
- retrait constaté d'apps compagnons tierces employant la même construction.

Repli en cas de rejet : revenir à `Neon Compass` seul dans le champ nom et
déplacer le descripteur vers le sous-titre, qui est indexé pour la recherche lui
aussi. Le repli ne coûte rien — aucun code, aucun bundle ID, aucune icône ne
dépend de cette décision.

## Documents mis à jour

- `CLAUDE.md` — contrainte IP.
- `project.yml` — `INFOPLIST_KEY_CFBundleDisplayName`.
- `docs/superpowers/specs/2026-07-19-neon-compass-companion-design.md` — §26 et
  §221, marquées comme remplacées.
- `docs/ops/2026-08-07-admob-provisioning.md` §93 — le nom déclaré dans la
  console AdMob suit celui de l'App Store.
