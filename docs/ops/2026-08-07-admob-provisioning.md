# Mettre les revenus publicitaires en service — marche à suivre

**Date** : 2026-08-07
**Prérequis** : PR #63 fusionnée (`eaa80965`). Le code est prêt ; il tourne sur les identifiants de test de Google jusqu'à ce que ce document soit exécuté.

## L'ordre, et pourquoi il n'est pas libre

```
1. Compte AdMob  ──┬─→ 3. Poser les identifiants (script)
                   │
                   └─→ 2. Domaine + app-ads.txt ──→ ⏸ vérifiable seulement APRÈS publication App Store
4. Clé app_config (indépendante, faisable tout de suite)
```

**`app-ads.txt` ne peut pas être vérifié avant la publication de l'app.** Google crawle le site développeur *déclaré dans la fiche du store* — sans fiche publiée, il n'y a rien à crawler. Le fichier se prépare maintenant et se valide au lancement. Ce n'est pas une raison de le repousser : il vaut 10 à 30 % d'eCPM, et il doit être en place le jour où la fiche paraît.

---

## 1 · Le compte AdMob

**Où** : <https://apps.admob.com> — se connecter avec le compte Google du projet.

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
