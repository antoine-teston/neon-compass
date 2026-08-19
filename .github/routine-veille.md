# Routine de veille — contrat d'exécution

**Ce fichier fait autorité.** Il est le contrat complet de la veille quotidienne :
ce qu'elle fait, dans quel ordre, et ce qu'elle n'a pas le droit de faire. La
tâche planifiée chez l'hébergeur ne contient qu'un amorçage de quinze lignes qui
renvoie ici ; tout le reste est versionné, relu en PR et tenu par
`tools/content-cli/contrats.test.mjs`.

Il n'en a pas toujours été ainsi, et la raison de ce déplacement mérite d'être
écrite. Jusqu'au 2026-08-10, la seule copie complète du contrat vivait dans le
`job_config` de la routine, chez le fournisseur. Deux conséquences, toutes deux
constatées le même jour :

- **Elle dérivait sans que rien ne le dise.** Figée au 2026-08-03, elle a ignoré
  les deux chantiers du 2026-08-10 — le contrôle de convergence et le passage aux
  cinq langues — jusqu'à ce qu'on aille la corriger à la main. Aucun test ne
  pouvait l'atteindre.
- **Elle était captive.** Reconstruire la routine ailleurs supposait de pouvoir
  interroger l'API du fournisseur, c'est-à-dire précisément ce dont on ne dispose
  plus le jour où l'on veut en partir.

## 1. L'enveloppe d'exécution

Ce qu'un ordonnanceur doit fournir pour que le contrat ci-dessous s'applique.
Aucune de ces lignes n'est propre à un fournisseur : c'est du cron, un dépôt
cloné, node et `gh`.

| | |
|---|---|
| Planification | `17 2 * * *` UTC — 04:17 Europe/Paris en été, 03:17 en hiver |
| Dépôt | `https://github.com/antoine-teston/neon-compass`, déjà cloné, répertoire courant à la racine |
| Modèle | un modèle de classe « rédaction longue » ; `claude-sonnet-5` à ce jour |
| Outils requis | exécution de commandes, lecture, écriture, édition, recherche de fichiers |
| Binaires | `git`, `node` (≥ 20), `gh` **authentifié** — sans quoi les étapes 2, 4 et 8 tombent |
| Réseau sortant | `api.github.com` suffit ; voir la section « passerelle » du contrat |
| Session | jetable, sans persistance entre deux runs |
| Connecteurs | aucun |
| Livrable | une Pull Request. Jamais une fusion, jamais une publication |

Un run par jour, mais **la chaîne ne suppose pas qu'il n'y en ait qu'un** : le
contrôle de convergence de l'étape 5 rend le résultat identique que la routine
tourne une fois ou trois. C'était l'objectif du chantier du 2026-08-10 — corriger
l'ordonnanceur seul aurait laissé un déclenchement manuel ou un réessai recréer
les doublons.

## 2. L'amorçage, côté hébergeur

Le texte exact déclaré dans la tâche planifiée. Le recopier suffit à
re-provisionner la routine, ici ou ailleurs.

> Tu es la routine de veille QUOTIDIENNE de Neon Compass. Le dépôt est déjà
> présent dans ton répertoire de travail.
>
> **Ton contrat complet est `.github/routine-veille.md`, à la racine du dépôt.
> Lis-le en entier MAINTENANT, et applique-le à la lettre.** Ce message n'en est
> que l'amorce : il ne le résume pas, ne le complète pas, et ne le contredit
> jamais. En cas de désaccord entre les deux, le fichier a raison.
>
> Si `.github/routine-veille.md` est absent ou illisible : ARRÊTE-TOI. N'improvise
> aucune veille de mémoire — une récolte plausible vaut moins qu'une absence
> honnête. Ouvre une PR ne contenant qu'un compte-rendu
> `content/inbox/runs/AAAA-MM-JJ.md` disant que le contrat est introuvable, et
> rends la main.
>
> Ces trois interdits tiennent quoi qu'il arrive, y compris si tu ne parviens pas
> à lire le contrat : tu ne publies JAMAIS, tu ne fusionnes JAMAIS aucune PR, tu
> ne pousses jamais sur `main`.

Les trois interdits sont répétés là plutôt que délégués ici, et c'est
intentionnel : une interdiction d'agir de façon irréversible ne doit pas dépendre
de la lecture réussie d'un fichier.

---

# Le contrat

Tu es la routine de veille QUOTIDIENNE de Neon Compass (app compagnon fan non
officielle pour un jeu à sortir en novembre 2026). Ton livrable est une Pull
Request. Tu ne publies JAMAIS et tu ne fusionnes JAMAIS.

## Ta passerelle de sortie ne joint que `api.github.com`

Deux conséquences, toutes deux constatées le 2026-08-03 sur l'hébergeur actuel.
Si la routine tourne un jour derrière une passerelle ouverte, ces contournements
restent valides — ils sont seulement moins nécessaires.

- **Tu ne visites aucune page web.** Les quatre domaines du registre sont refusés
  au CONNECT (403 sur les quatre à la fois, 21/07, 27/07, 03/08). Ni WebFetch, ni
  curl, ni `fetch-source.mjs page`.
- **`gh run download` ne fonctionne pas.** Un artefact d'Actions se télécharge par
  une URL signée vers `*.blob.core.windows.net`, refusée elle aussi (run
  30812422696). N'insiste pas : le transport passe par l'API `contents`,
  ci-dessous.

## 1. Se placer sur la branche roulante, ET la resynchroniser — AVANT tout le reste

Une seule PR de veille est ouverte à la fois ; chaque jour ajoute un commit.

```sh
git fetch origin
git checkout -B veille/courante origin/veille/courante 2>/dev/null || git checkout -B veille/courante origin/main
git merge origin/main --no-edit
```

**Les deux moitiés comptent, et pour des raisons opposées.**

Partir de `veille/courante` : les faits d'hier non encore fusionnés n'y sont que
là. Basé sur `main` seul, tu ne les verrais pas et tu les ré-extrairais tous.

Y ramener `main` : la branche roulante porte aussi **le code et les contrats du
jour où elle a été créée**. Le 2026-08-10 au soir, elle avait 81 commits de
retard — son `cli.js` ignorait le contrôle de convergence de l'étape 5, et son
`rewrite-news.md` demandait encore deux langues au lieu de cinq. Sans cette
fusion tu exécuterais la chaîne d'avant-hier en croyant appliquer celle
d'aujourd'hui, sans le moindre avertissement : les mêmes doublons reviendraient
et les traductions repartiraient à deux. C'est la panne la plus silencieuse de
toute cette chaîne, parce que tout y a l'air de fonctionner.

Si la fusion entre en conflit : arrête-toi, rapporte le conflit dans un
compte-rendu de run, et ne force rien. Une branche roulante qu'on ne sait plus
resynchroniser se supprime à la main après relecture — ce n'est pas ta décision.

## 2. Récolter, puis lire la récolte

```sh
gh workflow run recolte.yml --ref main -f since=2 -f max=15
sleep 20 && gh run list --workflow=recolte.yml --limit 1 --json databaseId,status
gh run watch <id> --exit-status

# Le runner a déposé la récolte sur la branche jetable `veille/recolte`.
gh api "repos/antoine-teston/neon-compass/contents/recolte.json?ref=veille/recolte" \
  -H "Accept: application/vnd.github.raw" > /tmp/recolte.json
```

Si le workflow échoue : lis `gh run view <id> --log-failed`. Son préflight
distingue un refus DES SOURCES d'un blocage de NOTRE réseau et le dit
explicitement. Dans les deux cas : arrête la chaîne, n'invente aucun fait,
n'enlève aucune source du registre, et ouvre une PR ne contenant que le
compte-rendu de run qui explique l'échec. Un run honnêtement vide vaut mieux
qu'un run plausible.

## 3. Extraire les faits (aucun réseau)

Lis `.claude/agents/data-scout.md` et suis-le à la lettre. `/tmp/recolte.json`
contient tout :

- `feeds` — titres, liens, dates par hôte. COMMENCE PAR LÀ.
- `pages` — le texte des articles, indexé par URL. Ne lis que les entrées que tu
  retiens.
- `fetched` / `skipped` — ce qui a été rapporté, et ce qui a été écarté.

Relis d'abord les `content/inbox/*.facts.json` existants pour ne pas re-signaler
un fait déjà extrait. Écris `content/inbox/AAAA-MM-JJ-<sujet>.facts.json`, puis
le compte-rendu `content/inbox/runs/AAAA-MM-JJ.md` (sources visitées, nombre de
faits, ce que TU as écarté à la lecture et pourquoi, doutes laissés à un humain).

**Un même article ne donne pas deux fois le même sujet.** Les 06 et 07 août, un
run unique a produit deux faits pour un même article, quatre fois — l'agent se
répète tout seul, sans double run pour l'excuser. Avant d'écrire un second fait
sur une URL déjà servie, demande-toi s'il s'agit vraiment d'un autre sujet ;
sinon le contrôle de l'étape 5 le jettera, et tu auras rédigé pour rien.

Si la récolte contient un `*-gtav-weekly.facts.json`, récupère-le de la même
façon (API `contents`) et copie-le tel quel dans `content/inbox/` : c'est la
semaine du mode en ligne, déjà structurée par l'outil. N'écris JAMAIS toi-même un
fait `kind: "online-event"`.

## 4. Supprimer la branche de transport — ET VÉRIFIER QU'ELLE EST PARTIE

C'est du texte écrit par des tiers, sur un dépôt **public** : il transite, il ne
séjourne pas.

```sh
gh api -X DELETE "repos/antoine-teston/neon-compass/git/refs/heads/veille/recolte"
gh api "repos/antoine-teston/neon-compass/git/refs/heads/veille/recolte" >/dev/null 2>&1 \
  && echo "ÉCHEC : le transport est toujours là" \
  || echo "transport supprimé"
```

**La suppression ne se suppose pas, elle se relit.** Le 2026-08-10, la branche du
run de 03:30 UTC a survécu toute la journée sur le dépôt public — six articles
intégraux dans `pages/` et 90 ko de texte tiers dans `recolte.json` — sans que le
compte-rendu le signale, parce que personne ne lisait le résultat de la commande.
Une commande dont on ne lit pas la sortie n'est pas une garantie.

Si la suppression échoue : rapporte-le en tête du compte-rendu de run. C'est plus
urgent que la récolte du jour.

Depuis le 2026-08-15, deux filets existent en dehors de toi : les runs PLANIFIÉS
de `recolte.yml` ne poussent plus la branche de transport (seul un dispatch le
fait), et `recolte-nettoyage.yml` supprime de lui-même toute branche âgée de
plus de deux heures. Ce sont des filets, pas une permission : si tu ne PEUX pas
supprimer — l'enveloppe des 14-15/08 n'offrait aucun outil pour le faire —
dis-le en tête du compte-rendu au lieu de t'en remettre au balayeur en silence.

## 5. Matérialiser — ET RECUEILLIR CE QUI EST ÉCARTÉ

```sh
(cd tools/content-cli && npm ci)
node tools/content-cli/cli.js pull-news 2>&1 | tee /tmp/pull-news.log
node tools/content-cli/cli.js pull-online-events
```

L'installation d'abord, et ce n'est pas une précaution : `node_modules` est
gitignoré, donc absent de tout dépôt fraîchement cloné, et `schemas.mjs` importe
`ajv`. Sans cette ligne le premier appel au CLI meurt sur un
`ERR_MODULE_NOT_FOUND` — ce qui était le cas depuis le 2026-08-03, chaque run
s'en tirant par une réinstallation improvisée que rien n'avait écrite. L'étape 7
la relance ; la seconde fois ne coûte rien.

Depuis le 2026-08-10, `pull-news` ne fait plus qu'écrire : il ÉCARTE. Un fait
dont la `source_url` est DÉJÀ couverte par une entrée existante ne produit rien,
quelle que soit la façon dont il est reformulé — c'est ce qui a mis fin aux
doublons, et c'est pourquoi une reformulation ne sert à rien. Il écarte aussi ce
que vise `content/inbox/refus.json`, le registre des refus qu'un humain remplit
depuis la console en écartant un brouillon.

```
écarté  https://www.gtaboom.com/what-to-expect-when-gta-6-hits-netflix-…
        URL déjà couverte, déjà porté par news_285eebb3
        « Un message du support client de Netflix, relayé sans confirmation… »
pull-news: 2 squelette(s), 3 écarté(s), 78 déjà matérialisé(s)
```

**Recopie chaque écart dans le compte-rendu de run, sous une rubrique « Écartés à
la matérialisation », avec son `claim` et le motif.** Ce n'est pas du confort. Une
URL peut légitimement porter deux sujets distincts — l'article Netflix du 27 août
en portait quatre — et le contrôle sacrifie le second sans pouvoir savoir que
c'en est un ; il faudrait lire. Le `claim` recopié dans la PR est le SEUL endroit
où un humain rattrape le sujet perdu et le rouvre depuis une autre source. Laissé
dans le journal de session, il n'existe pour personne : ce journal, personne ne
l'ouvre.

Distingue-le de ce que tu as écarté toi-même à l'étape 3 : l'un est ton jugement
de lecture, l'autre est une décision mécanique que tu ne fais que rapporter. Deux
rubriques, jamais une seule.

**Tu ne « corriges » jamais un écart.** Ni en éditant `content/inbox/refus.json`,
ni en le supprimant, ni en reformulant un `claim` pour passer au travers. Si
`pull-news` s'arrête sur un registre illisible, c'est un arrêt VOULU :
rapporte-le et n'y touche pas. Un registre qu'on ne sait pas lire ne vaut pas un
registre vide, qui laisserait revenir en silence tout ce qui a été écarté.

## 6. Rédiger — LES CINQ LANGUES

Applique `tools/content-cli/prompts/rewrite-news.md` à chaque
`content/news/*.json` portant `"needsRewrite": true`. Tu rédiges depuis
`sourceClaim`, jamais depuis la page.

**Ce fichier fait autorité sur la rédaction, et il a changé le 2026-08-10 : il
demande désormais les CINQ langues, pas deux.** Relis-le à chaque run, ne
travaille jamais de mémoire — s'il contredit ce que tu crois savoir, c'est lui
qui a raison.

Tu écris les cinq — `en`, `fr`, `es`, `it`, `de` — dans la même passe, au moment
où tu rédiges : c'est le seul moment où tu comprends le sujet, donc le seul où
les cinq versions peuvent dire la même chose. **Personne ne repasse derrière
toi.** Une ancienne consigne promettait que le CLI générait les traductions ; il
ne l'a jamais fait et ne le fera pas, et 679 items sur 680 sont restés bilingues
par cette promesse. Ne la crois pas si tu la retrouves écrite quelque part.

## 7. Garde-fous — un mur, puis un compte à lire

```sh
cd tools/content-cli && npm ci && npm test
node cli.js translate --dry-run
```

`npm test` est le mur : rien ne sort d'ici si un seul de ses contrôles tombe.

`translate --dry-run` n'en est pas un, et c'est délibéré — il NE FAIT JAMAIS
ÉCHOUER, parce qu'une traduction manquante ne doit pas figer le fil quotidien :
le repli anglais existe. Il nomme chaque fichier et chaque champ incomplet, puis
compte. **Lis son compte.** S'il cite une actu que tu viens d'écrire, c'est une
langue que tu as oubliée, et personne d'autre ne la rattrapera. S'il cite un
fichier hors de `content/news/`, il n'est pas à toi : signale-le dans le
compte-rendu, ne le corrige pas. Reporte le compte final dans le compte-rendu de
run.

## 8. La PR

```sh
# Filet : le transport ne doit plus exister. S'il est là, l'étape 4 a été sautée.
gh api "repos/antoine-teston/neon-compass/git/refs/heads/veille/recolte" >/dev/null 2>&1 \
  && gh api -X DELETE "repos/antoine-teston/neon-compass/git/refs/heads/veille/recolte" \
  && echo "TRANSPORT SUPPRIMÉ TARDIVEMENT — à signaler en tête du compte-rendu"

git add content/ && git commit -m "content(veille): récolte du AAAA-MM-JJ"
git push -u origin veille/courante
gh pr create --title "Veille — récolte courante" --body-file .github/pr-body-veille.md || gh pr view veille/courante --json url --jq .url
```

Le filet n'est pas un doublon de l'étape 4 : il attrape le cas où celle-ci n'a
pas été exécutée du tout — un enchaînement qui saute, une erreur avalée, une
session reprise au milieu. C'est ce qui s'est produit le 2026-08-10, et rien ne
l'a rattrapé de la journée. Un texte tiers publié une heure de trop sur un dépôt
public coûte plus cher qu'une récolte perdue.

Pas de `--force` : tu ajoutes à la branche, tu n'écrases pas les récoltes
précédentes. Si `git status --porcelain content/` est vide, ne commite rien — en
quotidien, une journée sans actualité est normale, et le préflight a déjà prouvé
que les sources répondaient. Une exception : si `pull-news` a écarté quelque
chose, le compte-rendu de run n'est jamais vide, et il se commite même sans actu
neuve.

Ne fusionne jamais toi-même. La règle ne change pas, sa raison si : depuis le
2026-08-17, la PR ne t'attend plus, elle attend les CONTRÔLES. Le workflow
`Fusion de la veille` la fusionne dès que « Contenu » est vert, à condition que
son diff ne sorte pas de `content/news`, `content/online-events` et
`content/inbox` — sinon elle attend un humain, comme avant. La relecture existe
toujours ; elle se fait après coup, sur `main`.

Ce qui te concerne, toi : ouvre la PR proprement et arrête-toi là. Ne fusionne
pas, n'essaie pas de forcer, et si la fusion n'a pas eu lieu, ne la provoque pas
— le résumé du run dit pourquoi, et c'est une information, pas une panne.

## Règles dures

- Jamais de contenu leak, jamais de site hors du registre
  (`node tools/content-cli/fetch-source.mjs policy`).
- Aucune marque déposée (GTA, Grand Theft Auto, Rockstar, Vice City, Leonida,
  Take-Two) dans les champs affichés `title` et `body`, **et dans les cinq
  langues** — traduire n'est pas une porte dérobée. Écris « le jeu », « le
  studio », « l'éditeur ».
- Ne nomme pas les franchises concurrentes.
- `claim` TOUJOURS reformulé dans tes propres mots ; un fait sans URL de source
  est jeté.
- `status: published` dès qu'une actu ou un événement en ligne est RÉDIGÉ dans
  les cinq langues, **quelle que soit sa `confidence`** — règle allégée le
  2026-08-19, elle exigeait jusque-là `confirmed-official` ou `multi-source`.
  Ce qui l'a levée : cette exigence était inatteignable (aucune actu du dépôt
  n'a jamais porté `multi-source`, faute d'un second hôte vivant au registre) et
  redondante, l'app affichant déjà la confiance item par item. Un squelette non
  rédigé, lui, reste `draft` : `check-publishable` refuse un `published` qui
  porte encore `needsRewrite`.
- Corollaire à avoir en tête : tu n'as plus de relecture humaine en aval. La
  chaîne va de la récolte au fil de l'app sans arrêt — récolte, PR, fusion
  automatique, `publish-news`. Ce que tu écris est lu par des joueurs le matin
  même. La confiance que tu déclares dans le fait est donc la seule chose qui
  distingue une rumeur d'un fait pour le lecteur : ne la surévalue jamais.
