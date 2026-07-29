# Bascule de la politique de marques après approbation App Store

*Rédigé le 2026-07-29. À exécuter le lendemain de l'approbation, pas avant.*

## Pourquoi ce plan existe

Le contenu du fil est aujourd'hui rédigé sans jamais nommer les jeux : « l'épisode
précédent », « le volet de 2004 », « le jeu en ligne actuel », « l'éditeur », « le
studio ». Ces périphrases ont un coût réel de compréhension — **un lecteur qui n'a
pas le contexte ne peut pas savoir de quel jeu on parle**. Les pastilles V/VI
ajoutées sur les cartes sont le symptôme de cette contrainte : il a fallu inventer
un chiffre romain parce qu'on ne pouvait pas écrire le nom.

La contrainte n'est pas juridique. L'usage nominatif — citer une marque pour
désigner la chose qu'elle désigne — est largement admis, et c'est ce que fait
chaque site d'actualité. Notre propre contenu écrit d'ailleurs « PS5 », « Xbox
Series X|S », « PlayStation Store », « iOS » sans hésiter : ce sont aussi des
marques déposées. La règle n'est donc pas « pas de marques », c'est « pas les
marques *de Rockstar* » — un choix de risque ciblé sur qui est susceptible de se
plaindre.

Ce choix vient du spec §1, qui limite l'usage nominatif à la description App
Store, en face de la ligne directrice **Apple 5.2.1** que le spec qualifie de
« mur principal pour une app fan ». Il est délibérément plus strict que le droit,
pour présenter zéro surface de marque au moment de la review.

**Ce que ce plan exploite** : le contenu vient du CDN, pas du binaire. La
politique de marques est donc une décision de *contenu*, révocable en une
republication, sans mise à jour de l'app et sans repasser par la review. Ce n'est
pas un choix binaire, c'est un choix de séquence.

## Ce qui ne bascule JAMAIS

À garder propre définitivement, quoi qu'il arrive après l'approbation — c'est là
que le risque est permanent, et c'est aussi ce que le spec §12 traite comme une
contrainte structurante de nommage :

- le nom de l'app, l'icône, le sous-titre App Store, le bundle ID ;
- le champ mots-clés App Store (y glisser « GTA » est un motif de rejet
  documenté) ;
- les captures d'écran de la fiche ;
- tout asset Rockstar/Take-Two : logos, artwork, audio, données extraites. Ça ne
  relève pas des marques mais du droit d'auteur, et aucune approbation ne le
  débloque.

## Préconditions

1. L'app est **approuvée** et disponible sur l'App Store. Pas « soumise »,
   pas « en review » : approuvée.
2. La fiche App Store porte le disclaimer « non officiel » exigé par le spec.
3. `contentBaseURL` pointe bien sur le CDN — sinon la republication ne touche
   personne (vérifier avec `content-cli content-source`).

## Étape 1 — Rendre la règle pilotable

`tools/content-cli/cli.js` porte aujourd'hui la règle en dur :

```js
const TRADEMARKS = /\b(GTA|Grand Theft Auto|Rockstar|Vice City|Leonida|Take-Two)\b/i;
const UI_FIELDS = ['title', 'note', 'effect', 'body'];
```

La remplacer par un drapeau explicite, défaut STRICT, avec la date de bascule en
commentaire pour que personne ne le relâche par accident :

```js
// Politique de marques. `strict` refuse toute marque Rockstar/Take-Two dans les
// champs affichés ; `nominative` l'autorise dans le corps du contenu.
//
// Le défaut RESTE strict après la bascule : c'est ce qui protège une éventuelle
// resoumission (mise à jour majeure, appel, changement de politique Apple) d'un
// relâchement oublié.
const TRADEMARK_POLICY = process.env.NC_TRADEMARK_POLICY ?? 'strict';
```

Et faire dépendre la vérification du drapeau, en gardant le message d'échec
explicite sur la raison — pas seulement sur le mot trouvé.

**Test à écrire d'abord** : un item contenant « Grand Theft Auto VI » dans son
corps échoue en `strict` et passe en `nominative`. Sans ce test, le drapeau est
une intention, pas un mécanisme.

## Étape 2 — Réécrire les items, sans les recréer

**Ne pas toucher aux identifiants.** `id` et `processedFrom` portent l'identité :
les regénérer créerait 27 doublons dans le fil et casserait l'idempotence du run
hebdomadaire. Seuls `title` et `body` changent.

Les périphrases à remplacer, telles qu'elles ont été employées :

| Périphrase actuelle | Devient |
|---|---|
| « l'épisode précédent », « le volet de 2004 » | le nom exact du jeu concerné |
| « le jeu en ligne actuel » | le nom du mode en ligne |
| « l'éditeur » | le nom de l'éditeur, quand c'est lui qui agit |
| « le studio » | le nom du studio |
| « un studio concurrent », « deux jeux de sport annuels » | à laisser tels quels : ce sont des marques de TIERS, hors du périmètre de cette bascule |

**Point de vigilance** : la bascule autorise les marques *Rockstar/Take-Two*. Elle
ne dit rien des marques de concurrents (les deux jeux de sport, le jeu de tir
annuel). Les nommer relève d'un autre arbitrage, à ne pas emporter dans celui-ci.

**Ce qui ne change pas** : `sourceClaim` reste tel quel — il n'est pas affiché, et
il porte déjà les noms exacts. C'est d'ailleurs la trace qui rend cette réécriture
possible sans retourner aux sources.

## Étape 3 — Les pastilles V/VI deviennent un choix, plus une nécessité

Une fois les jeux nommés dans les titres, `gameBadge` fait doublon avec le texte.
Deux options, à trancher à ce moment-là et pas maintenant :

- **la garder** : elle reste utile au balayage visuel, on repère le jeu sans lire ;
- **la retirer** : une information de moins sur une carte déjà dense.

Je penche pour la garder — un badge se scanne plus vite qu'un titre se lit — mais
c'est une décision d'usage qui mérite d'être prise devant l'écran rempli, pas
depuis un plan.

## Étape 4 — Publier

```sh
NC_TRADEMARK_POLICY=nominative node tools/content-cli/cli.js release
node tools/content-cli/cli.js build-cdn
GOOGLE_APPLICATION_CREDENTIALS="$FIREBASE_SERVICE_ACCOUNT_PATH" npx firebase-tools deploy --only hosting
```

`build-cdn` doit annoncer le même nombre d'entrées qu'avant la réécriture. **Un
chiffre différent signifie que des identifiants ont bougé** — arrêter là et
comprendre pourquoi avant de déployer.

Le manifeste est caché 60 secondes : les clients voient le nouveau texte dans la
minute, sans rien télécharger et sans mise à jour de l'app. C'est tout l'intérêt.

## Étape 5 — Aligner la documentation

- `CLAUDE.md` : la formulation actuelle ne mentionne que « app name, icon, App
  Store subtitle, bundle ID », ce qui est plus lâche que ce que le pipeline
  applique. C'est cet écart qui a rendu la règle difficile à interroger. Écrire la
  politique effective et son drapeau.
- Spec §1 : « usage nominatif autorisé uniquement dans la description » devient
  une règle **datée**, valable jusqu'à l'approbation. Ne pas effacer l'ancienne
  formulation — elle explique pourquoi le contenu de lancement était écrit ainsi.
- `.claude/agents/content-editor.md` et
  `tools/content-cli/prompts/rewrite-news.md` : ils portent tous deux l'interdiction
  en dur. Les faire dépendre du drapeau, sinon le run hebdomadaire continuera de
  produire des périphrases après la bascule.

## Le retour arrière

Il est symétrique et c'est ce qui rend la bascule acceptable : repasser
`NC_TRADEMARK_POLICY` à `strict`, restaurer les textes depuis git, republier.
Une minute pour les clients, aucune mise à jour d'app.

À faire immédiatement si Apple signale la marque lors d'une mise à jour
ultérieure — et sans discuter, parce que le spec prévoit qu'en cas de rejet 5.2.1
persistant le plan de repli est la bascule en PWA, ce qui coûte infiniment plus
cher que de remettre des périphrases.

## Ce que ce plan ne fait pas

- **Il ne touche pas aux images.** Les captures et artworks des sites sources
  restent interdits : c'est du droit d'auteur, pas du droit des marques, et
  l'approbation de l'app n'y change rien. La piste permise reste celle que
  CLAUDE.md décrit — des illustrations originales générées, une par rubrique,
  prompts archivés comme preuve d'originalité.
- **Il ne rouvre pas les sources écartées.** `rockstargames.com` reste exclu par
  son robots.txt, r/GTA6 par le sien et par les conditions de son API. Ces
  décisions sont indépendantes de la politique de marques.
