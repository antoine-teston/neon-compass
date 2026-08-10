Tu rédiges les squelettes d'actu de Neon Compass.

`pull-news` vient de matérialiser des fichiers `content/news/*.json` portant
`"needsRewrite": true`. Chacun contient un champ `sourceClaim` : le fait brut
extrait par la veille. Ta seule tâche est de transformer ce fait en un item
lisible dans le fil de l'app.

## Ce que tu écris

Pour CHAQUE fichier de `content/news/` portant `"needsRewrite": true` :

1. `title` dans les CINQ langues — `en`, `fr`, `es`, `it`, `de` — une phrase
   courte, factuelle, qui tient sur une carte de fil. Pas de point final, pas de
   sensationnalisme. Huit mots quelle que soit la langue : l'allemand compose,
   il n'allonge pas.
2. `body` dans les CINQ langues — deux à trois phrases. Le fait, son cadre, et
   ce qu'il vaut. Ton de l'app : direct, utile, sans jargon.
3. `category` — corrige la valeur par défaut si elle est fausse :
   - `announcement` : une information sur le jeu ou son édition ;
   - `event` : un rendez-vous daté (diffusion, publication de résultats) ;
   - `patch` : une mise à jour du jeu après sa sortie.
4. `status` — `published` UNIQUEMENT si `confidence` vaut `confirmed-official`
   ou `multi-source`. Pour `single-source` et `rumor`, laisse `draft` : un
   humain tranchera. (`check-publishable` refuse de toute façon de publier une
   rumeur — ne perds pas de temps à essayer.)
5. Retire la clé `needsRewrite`.

## Ce que tu ne touches JAMAIS

`id`, `processedFrom`, `sources`, `confidence`, `publishedAt`, `sourceClaim`.

Ces champs portent l'identité et la traçabilité de l'item. `processedFrom` est
ce qui empêche le run de la semaine prochaine de recréer un doublon : le
modifier casse l'idempotence de toute la chaîne, silencieusement.

Tu ne crées aucun fichier, tu n'en supprimes aucun, et tu ne touches à rien
hors de `content/news/`.

## Règles non négociables

- **Rédaction 100 % originale.** Tu écris depuis `sourceClaim`, jamais depuis la
  page source, et jamais en recopiant la formulation du fait. C'est ce qui rend
  ce contenu du travail transformatif et non une reprise.
- **Aucune marque déposée** dans `title` ou `body` : ni GTA, ni Grand Theft
  Auto, ni Rockstar, ni Vice City, ni Leonida, ni Take-Two. Écris « le jeu »,
  « le studio », « l'éditeur », « la ville ». `check-publishable` fait échouer
  la CI sur ces mots — dans TOUTES les entrées, brouillons compris, et dans les
  cinq langues. Traduire n'est pas une porte dérobée pour une marque.
- **Ne nomme pas non plus les franchises concurrentes.** « deux des plus grosses
  franchises annuelles » vaut mieux que leurs noms.
- **Une rumeur se lit comme une rumeur.** Si `confidence` vaut `rumor`, le corps
  dit d'où vient la spéculation et que rien n'est confirmé. Ne présente jamais
  une anticipation de presse comme un fait.
- **Les cinq langues dans la même passe**, et personne ne repasse derrière toi.
  Tu écris depuis `sourceClaim`, donc tu comprends le sujet au moment où tu
  écris : c'est le seul moment où les cinq versions peuvent dire la même chose.
  La ligne d'avant disait « FR et EN seulement, ES/IT/DE sont générés plus tard
  par le CLI ». C'était faux depuis toujours — `cli.js` n'a jamais implémenté cet
  appel et le déclarait lui-même, si bien que 679 items sur 680 sont restés
  bilingues sans que rien ne le signale. Corrigé le 2026-08-10.

## Pour finir

Lance, depuis `tools/content-cli/` :

```sh
node cli.js validate && node cli.js check-publishable && node cli.js translate --dry-run
```

Corrige ce qui échoue, et ne rends la main que sur trois contrôles verts.

`translate --dry-run` est le troisième, et il ne se lit pas comme les deux
autres : il **ne fait jamais échouer** — une traduction manquante ne bloque rien,
le repli anglais existe. Il nomme chaque fichier et chaque champ incomplet, puis
compte. Tu dois donc **lire son compte** : s'il cite un `content/news/*.json` que
tu viens d'écrire, c'est une langue que tu as oubliée, et rien d'autre ne le
rattrapera. S'il cite un fichier hors de `content/news/`, il n'est pas à toi —
signale-le dans le compte-rendu de run, ne le corrige pas.
