# Mettre les revenus publicitaires en service — marche à suivre

**Date** : 2026-08-07
**Prérequis** : PR #63 fusionnée (`eaa80965`). Le code est prêt ; il tourne sur les identifiants de test de Google jusqu'à ce que ce document soit exécuté.

## L'ordre, et pourquoi il n'est pas libre

```
0. Identité (compte Google + entreprise)  ──→ 1. Compte AdMob ──→ 3. Poser les identifiants (script)
   │                                                          │
   └─→ Apple Developer ──→ soumission App Store               └─→ 2. Domaine + app-ads.txt
                                    │                                        │
                                    └────────────────────────────────────────┴─→ ⏸ app-ads.txt vérifiable ICI seulement

4. Clé app_config (indépendante, faisable tout de suite)
```

**`app-ads.txt` ne peut pas être vérifié avant la publication de l'app.** Google crawle le site développeur *déclaré dans la fiche du store* — sans fiche publiée, il n'y a rien à crawler. Le fichier se prépare maintenant et se valide au lancement. Ce n'est pas une raison de le repousser : il vaut 10 à 30 % d'eCPM, et il doit être en place le jour où la fiche paraît.

**L'étape 0 commande tout le reste et elle a des délais administratifs.** La soumission App Store est visée fin octobre. En remontant : l'inscription Apple Developer en tant qu'organisation demande un numéro D-U-N-S (plusieurs jours à plusieurs semaines), qui demande que l'entreprise existe, qui demande un SIRET (une à deux semaines). **La décision doit être prise début septembre au plus tard.**

---

## 0 · L'identité : quel compte, quelle entreprise

> Ce qui suit n'est pas un conseil fiscal. Ce sont les questions à porter à un comptable, les chiffres 2026 vérifiés, et l'enchaînement des délais. La ligne fiscale se tranche avec un professionnel.

### Le compte Google

AdMob n'exige pas Workspace : un compte Google gratuit suffit techniquement. Mais trois choses rendent ce choix quasi définitif.

- **AdMob n'autorise qu'un compte par éditeur.** En créer un second est une violation de règlement, pas un contournement.
- **L'identifiant éditeur `pub-XXXX` part dans le binaire et dans `app-ads.txt`.** Changer de compte plus tard, c'est une nouvelle fiche AdMob, un nouveau fichier, et une mise à jour de l'app.
- **C'est le compte payeur** : il portera les coordonnées bancaires et les informations fiscales, celles qui devront correspondre à l'entreprise.

**À ne pas utiliser** : une adresse d'employeur (`@codoc.co`) ou d'établissement (`@univ-lille.fr`). Le domaine appartient à quelqu'un d'autre, qui peut révoquer le compte sans procédure de récupération — et le jour où le lien avec l'organisation s'arrête, l'accès au compte qui encaisse s'arrête avec lui. Second motif propre à ce projet : c'est une app de fan non officielle autour d'une IP Take-Two, et le domaine d'un tiers n'a aucune raison d'y figurer.

**Retenu** : un compte Google gratuit dédié, créé pour l'occasion, utilisé aussi pour Apple Developer afin que la même identité tienne toute la chaîne. Bascule possible vers Workspace sur le domaine acheté à l'étape 2 quand une adresse `contact@<domaine>` devient utile pour le support App Store — Google permet d'ajouter un domaine à un compte existant, sans repartir de zéro.

### L'entreprise

**Pourquoi maintenant et pas après la sortie.** Deux raisons indépendantes :

1. **Apple veut que le titulaire du compte développeur soit l'entité qui vend.** Le nom du vendeur est **public** sur la fiche App Store. Une inscription « personne physique » l'affiche en nom propre ; une inscription « organisation » affiche le nom de l'entreprise, mais exige un numéro **D-U-N-S** — gratuit, demandé à Dun & Bradstreet, plusieurs jours à plusieurs semaines. Pour une app non officielle autour d'une IP tierce, exposer un nom personnel ou une raison sociale n'est pas la même exposition.
2. **Les obligations de TVA commencent au premier euro**, bien avant les seuils. Voir plus bas.

**Statut, au regard du modèle de revenus.** Chiffres 2026 vérifiés :

| Seuil | Montant 2026 | Ce que dit le modèle de revenus |
|---|---|---|
| Régime micro (BIC/BNC, prestations de services) | **83 600 €** (2026-2028, contre 77 700 € avant) | Dépassé en année 1 au scénario médian (~133 k€ pub + Pro). Confortable au pessimiste (~15 k€) |
| Franchise en base de TVA (services) | **37 500 €** de base, **41 250 €** majoré | **Dépassé dès le premier trimestre au médian** (44 100 € de pub sur 13 semaines) |

Lecture : la micro-entreprise est le bon point de départ — création en ligne, gratuite, immédiate, et on n'en sort pas brutalement (le régime micro se perd après deux années consécutives de dépassement). **Mais la franchise de TVA, elle, saute beaucoup plus tôt** — potentiellement dans les six premières semaines. C'est le seuil à surveiller, pas celui du micro.

**L'obligation que personne ne voit venir : le numéro de TVA intracommunautaire, dès le premier euro.**

Les revenus AdMob viennent de **Google Ireland**, et ceux de l'App Store d'une entité européenne d'Apple. Dans les deux cas, vendre de l'espace publicitaire ou du logiciel à une entreprise d'un autre État membre est une **prestation de services intracommunautaire** : la TVA est due par le preneur (autoliquidation, article 196 de la directive 2006/112/CE), et le prestataire doit posséder un numéro de TVA intracommunautaire **quel que soit son chiffre d'affaires** — y compris en franchise en base.

Deux conséquences pratiques :

- **Demander le numéro au SIE** dès l'obtention du SIRET (compter ~2 semaines). Sans lui, Google facture la TVA irlandaise, qui n'est pas récupérable.
- **Déposer une DES** (déclaration européenne de services) **mensuellement**, auprès de la douane. Le manquement est sanctionné, et l'oubli est fréquent parce que rien ne le rappelle.

### L'ordre et les délais

| # | Action | Délai | Bloque |
|---|---|---|---|
| 0.1 | Créer le compte Google dédié | 2 min | AdMob, Apple Developer |
| 0.2 | Trancher : personne physique ou société ? | décision | tout le reste |
| 0.3 | Créer la micro-entreprise (guichet unique INPI) | ~1-2 semaines pour le SIRET | 0.4, 0.5, paiements AdMob |
| 0.4 | Demander le numéro de TVA intracommunautaire au SIE | ~2 semaines | facturation correcte de Google |
| 0.5 | Ouvrir un compte bancaire dédié | ~3 jours | versements |
| 0.6 | D-U-N-S si inscription en organisation | jours à semaines | inscription Apple |
| 0.7 | Inscription Apple Developer (99 $/an) + **Small Business Program** | ~1-2 jours après validation | soumission fin octobre |

**Le Small Business Program ramène la commission Apple de 30 % à 15 %** pour les développeurs sous 1 M$ de revenus annuels. Sur un Pro à 5,99 €, cela fait 5,09 € net au lieu de 4,19 €. La candidature est à déposer **avant** la mise en vente. *(Une version antérieure de la page Notion « 04 · Modèle économique » annonçait 8 % : c'est faux, ce chiffre relève des conditions alternatives du DMA, pas du Small Business Program.)*

### Les trois questions à poser au comptable

1. **BIC ou BNC ?** La qualification des revenus publicitaires et des ventes d'application n'est pas évidente et change l'abattement forfaitaire. Le modèle de revenus suppose des prestations de services.
2. **À quel moment sortir de la franchise de TVA**, et faut-il y renoncer volontairement dès le départ pour éviter un basculement en cours de trimestre ?
3. **Micro ou société**, au vu d'un revenu attendu entre 15 k€ (pessimiste) et 350 k€ (optimiste) sur six mois — un facteur 23 qui ne se tranche pas à l'avance. La bascule en cours de route est possible ; la question est son coût.

---

## 1 · Le compte AdMob

**Où** : <https://apps.admob.com> — se connecter avec le compte Google dédié créé à l'étape 0.1, jamais avec une adresse d'employeur ou d'établissement.

1. **Créer le compte éditeur** si ce n'est pas fait. Il demande une adresse de facturation et un pays. C'est cette adresse qui recevra les paiements ; le seuil de versement AdMob est de 100 $ cumulés.
2. **Apps → Ajouter une application**. À la question « Votre app est-elle publiée sur un store ? », répondre **non** — elle ne l'est pas encore. AdMob crée alors une entrée provisoire à relier plus tard à la fiche App Store.
3. **Nom de l'application : `Neon Compass`.** Aucune marque Rockstar nulle part, ni ici ni dans les descriptions. La contrainte IP du projet vaut aussi sur les consoles tierces.
4. **Plateforme : iOS.**

Relever ensuite **trois identifiants**, dans deux formats qu'il ne faut pas confondre :

| Ce qu'on relève | Où | Forme |
|---|---|---|
| **App ID** | Apps → Neon Compass → Paramètres de l'app | `ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY` — séparateur **tilde** |
| **Unité bannière** | Unités publicitaires → Ajouter → **Bannière** | `ca-app-pub-XXXXXXXXXXXXXXXX/BBBBBBBBBB` — séparateur **slash** |
| **Unité interstitiel** | Unités publicitaires → Ajouter → **Interstitiel** | `ca-app-pub-XXXXXXXXXXXXXXXX/IIIIIIIIII` — séparateur **slash** |

> **Le tilde contre le slash.** C'est la seule différence typographique entre une application et une unité, et les intervertir ne lève aucune erreur : l'inventaire ne remplit simplement jamais. Le symptôme est « la pub ne s'affiche plus », jamais « mauvais identifiant ». Le script de l'étape 3 refuse l'interversion et dit laquelle des deux est en cause.

### À faire dans la foulée, sur l'unité bannière

**Vérifier que le rafraîchissement automatique est actif** (Unité bannière → Modifier → *Taux d'actualisation*). Google le propose entre 30 et 120 secondes ; **60 secondes** est la valeur retenue par le modèle de revenus.

Laissé désactivé, il supprime deux impressions par session sur quatre : **−32 % d'ARPDAU, soit 9 700 € au scénario médian sur trois mois**. C'est le plus gros montant de tout le dossier publicitaire, et il ne coûte qu'une case à cocher. Voir `2026-08-07-projections-revenus-publicitaires.md`.

---

## 2 · Le domaine et `app-ads.txt`

**Ce qu'il faut** : un domaine que tu contrôles, servi en HTTPS, et qui sera déclaré comme **site développeur** dans App Store Connect.

1. **Acquérir le domaine.** Le bundle `co.antoineteston.neoncompass` suggère `antoineteston.co`, mais n'importe lequel convient — il doit seulement être le même que celui déclaré dans la fiche.
2. **Servir le fichier à la racine**, en clair, sans redirection : `https://<domaine>/app-ads.txt`. Le script de l'étape 3 rend son contenu exact ; c'est une ligne :
   ```
   google.com, pub-XXXXXXXXXXXXXXXX, DIRECT, f08c47fec0942fa0
   ```
   L'éditeur `pub-XXXXXXXXXXXXXXXX` est la partie centrale de l'App ID. `f08c47fec0942fa0` est l'identifiant de l'autorité de certification de Google, constant pour tout le monde.
3. **Déclarer le domaine dans App Store Connect** — champ « Site web du développeur » de la fiche produit, à la soumission.
4. **Après publication**, AdMob crawle sous 24 h. L'état se lit dans AdMob → Apps → *app-ads.txt*.

**Écarté et pourquoi** : héberger le fichier sur Supabase Storage. Techniquement un bucket public le servirait, mais l'URL serait sous `supabase.co`, que nous ne contrôlons pas — Google exige la racine du domaine déclaré. La vérification échouerait.

**Le fichier grandira.** Chaque partenaire de médiation ajouté plus tard (Meta Audience Network, AppLovin, Unity) y pose sa propre ligne. Prévoir un hébergement où éditer un fichier texte reste trivial.

---

## 3 · Poser les identifiants dans le code

Une seule commande, depuis la racine du dépôt :

```sh
node tools/ops/set-admob-ids.mjs \
  --app-id       ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY \
  --banner       ca-app-pub-XXXXXXXXXXXXXXXX/BBBBBBBBBB \
  --interstitial ca-app-pub-XXXXXXXXXXXXXXXX/IIIIIIIIII \
  --dry-run
```

`--dry-run` montre ce qui serait écrit sans rien toucher. Retirer le drapeau pour appliquer.

Le script modifie **la branche Release seulement** — `project.yml` et le `#else` de `Core/Ads/AdUnits.swift`. La branche Debug garde les identifiants de test, et ce n'est pas négociable : la règle AdMob interdit de servir et de cliquer de vraies annonces en développement, et chaque lancement en simulateur deviendrait du trafic invalide. La sanction est la suspension du compte.

Il refuse quatre erreurs : un App ID donné comme unité et l'inverse, deux unités identiques, des identifiants venant de comptes différents, et les identifiants de test posés en Release.

Il rend enfin le contenu exact d'`app-ads.txt` pour l'étape 2.

**Ensuite, obligatoirement :**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test
```

`AdUnitsTests` doit **rester vert**. Il ne contrôle que la branche Debug, que le script ne touche pas. **S'il rougit, un vrai identifiant a atterri du mauvais côté du `#if`** — ne pas commiter, relire le diff.

Vérifier aussi que l'App ID de Release atterrit bien dans le binaire, la substitution `$(GAD_APP_ID)` étant silencieuse quand elle échoue :

```sh
xcodebuild -scheme NeonCompass -configuration Release \
  -destination 'generic/platform=iOS' -showBuildSettings 2>/dev/null | grep GAD_APP_ID
```

---

## 4 · La clé `interstitialFrequency`

Indépendante des trois autres, faisable immédiatement. La migration est écrite : `supabase/migrations/20260807140000_interstitial_frequency.sql`.

**Appliquer** : GitHub → Actions → workflow **Migrations** → *Run workflow*.
- Laisser `dry-run` **coché** au premier passage pour lire ce qui serait appliqué.
- Relancer avec la case décochée.

La valeur semée est **1**, c'est-à-dire allumé. Semer 0 « par prudence » créerait un format muet dont personne ne saurait pourquoi il ne s'affiche pas.

**Pour éteindre l'interstitiel plus tard sans mise à jour de l'app** : passer la valeur à `0` dans l'éditeur de table Supabase (`app_config`, clé `interstitialFrequency`). L'effet est immédiat au prochain lancement de chaque client. C'est le coupe-circuit.

---

## Ce qu'on saura quand tout est fait

| Signe | Où le lire |
|---|---|
| Les unités remplissent | AdMob → Apps → Neon Compass, impressions non nulles après quelques heures |
| `app-ads.txt` est validé | AdMob → Apps → onglet *app-ads.txt* (après publication App Store seulement) |
| Le coupe-circuit répond | Passer `interstitialFrequency` à 0, relancer l'app, aucun interstitiel à la fermeture d'un détail |

Et les trois chiffres à relever dès la première semaine en production, qui recalent tout le modèle de revenus : **eCPM réel par format et par pays**, **taux d'opt-in ATT observé**, **part des sessions qui déclenchent un interstitiel** (l'hypothèse la plus fragile du modèle, posée à 55 %).

---

## Sources des chiffres administratifs

- [Nouveaux seuils micro-entreprise 2026-2028](https://www.lecoindesentrepreneurs.fr/nouveaux-seuils-micro-entreprise-2026-2027-2028/) — régime micro à 83 600 € pour les prestations de services.
- [TVA auto-entrepreneur, seuils 2026](https://www.portail-autoentrepreneur.fr/academie/statut-auto-entrepreneur/tva) — franchise en base à 37 500 € / 41 250 € pour les services.
- [Mon compte est rattaché à Google Ireland — Aide AdMob](https://support.google.com/admob/answer/4382717?hl=fr) — autoliquidation, numéro de TVA intracommunautaire requis.
- [Déclarer ses revenus AdSense en auto-entreprise](https://www.portail-autoentrepreneur.fr/academie/gestion-auto-entreprise/imposition/declarer-revenus-adsense-youtube) — DES mensuelle, obligation indépendante du chiffre d'affaires.

Ces montants sont ceux de 2026 et changent. Les revérifier avant d'agir plutôt que de faire confiance à ce document.
