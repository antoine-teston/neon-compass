# Le hub hebdomadaire rend un verdict — temps 1

**Date** : 2026-08-06
**Statut** : validé
**Remplace partiellement** : `2026-08-02-sources-online-design.md` §C1 (extraction du hub)

## Le problème

Le 2026-08-06 à 02:19 UTC, `fetch-source.mjs weekly` a commencé à sortir en code 1 :

```
clé « hub » absente du payload RSC — structure de page changée côté source
```

L'événement en ligne publié couvrait le 2026-07-30 → 2026-08-05T23:59:59Z. Sa fenêtre
s'est fermée le soir même. `OnlineEventsModel.currentEvent(at:)` ne rend que l'événement
dont la fenêtre contient `now` : depuis le 06/08 à 00:00 UTC, la page Social n'a plus rien
à montrer, et dit « terminé ».

Personne ne l'a vu pendant une journée. Trois raisons cumulées :

1. L'étape est en `continue-on-error: true` — délibéré, une dérive du hub ne doit pas
   emporter la récolte d'actu. Effet de bord : l'API `actions/runs/<id>/jobs` rapporte
   alors `conclusion: success` pour cette étape même quand elle sort en code 1.
2. Le workflow n'ouvre aucune PR. C'est la Routine cloud `neon-compass-veille` qui lit la
   branche de transport, juge, et tient la PR roulante. Quand l'extraction échoue, **le
   fichier de faits est simplement absent** — et « absent parce que cassé » est
   indiscernable pour elle de « absent parce que rien de neuf ».
3. Le message d'erreur diagnostiquait un redesign. C'était en partie vrai et en partie
   trompeur : il n'y avait, ce jour-là, **aucune semaine à récolter**.

## Ce que la source a fait, mesuré le 2026-08-06 à 19:00 UTC

**La page a été refondue.** La donnée n'a pas quitté le payload RSC ; elle a changé de
nature. Elle n'y est plus comme objet de données, elle y est comme **arbre React rendu** :

```js
["$","section","bonus-A Superyacht Life missions-2026-08-12T23:59:59+00:00",{…}]
["$","p",null,{"data-variant":"body",…,"children":"2x GTA$ and RP Ends Wednesday, Aug 12, 2026."}]
```

Ancrages disparus, tous vérifiés absents : la clé `hub`, `currentPhaseEndsAt`,
`activityName`, `multiplierLabel`, `itemName`, `discountLabel`, la section
`id="weekly-rewards"`, et le libellé `Read the news story` — devenu `Read the event story`,
pointant désormais un article d'événement (`/gta-online-summer-heist-event-july-2026`) et
non l'article de la semaine.

Ancrages neufs, tous vérifiés présents : `<h1 id="weekly-updates-heading">`,
`<nav aria-label="Weekly event sections">`, les sections `id="weekly-reset"` et
`id="showcase-offers"`, et une clé React par carte de la forme
`<nature>-<nom>-<fin ISO>`.

**Et il n'y avait aucune semaine publiée.** La page le déclare elle-même :

```html
<h1 id="weekly-updates-heading">GTA Online event offers still active</h1>
<p …>The current weekly bonus phase has ended, but explicitly dated event-wide offers
   or earned rewards are still active.</p>
```

Le 2026-08-06 est un **jeudi**, jour de reset (la page l'écrit : « GTA Online normally
starts a new event week on Thursday »). La semaine précédente s'est fermée le mercredi
05/08 à 23:59:59Z ; à 19:00 UTC le jeudi, la source n'avait toujours pas publié la
suivante. Les ancres `#qualified-rewards` et `#showcase-schedule` sont référencées par la
navigation de la page mais **n'existent pas dans le DOM** — elles n'ont rien à montrer.

Conséquence directe sur ce qu'on peut construire : **le balisage d'une semaine vivante sous
le nouveau design n'est pas observable aujourd'hui.** Écrire maintenant le parseur complet
reviendrait à deviner la forme de `#showcase-offers` peuplé et de deux sections jamais
vues — exactement ce que ce module s'interdit (« une structure qu'on ne reconnaît pas
LÈVE »).

D'où un découpage en deux temps. **Ce document ne couvre que le temps 1.**

## Périmètre

**Temps 1 — ce document.** Rendre les verdicts justes et l'absence visible. Aucune
tentative de lire une semaine vivante.

**Temps 2 — hors de ce document.** Quand la source aura publié une semaine, le run la
capturera (voir « La capture » ci-dessous), et le parseur se réancrera sur du balisage
réel, avec fixture.

## Principe directeur

**Le parseur reconnaît positivement « pas de semaine publiée » ; il ne le déduit jamais
d'une absence.**

Sans quoi, le jour où la source publiera une semaine vivante sous un balisage qu'on ne sait
pas lire, on la classerait « rien à récolter » et on ne le saurait jamais. **Absence de
donnée et absence de compréhension sont deux verdicts distincts**, et un seul des deux est
silencieux.

Corollaire assumé : l'énumération des déclarations reconnues est **fermée**, comme
`REWARD_KINDS`. Une reformulation côté source nous rend bruyants, pas muets — c'est le bon
sens de l'erreur.

## Architecture

### 1. `parseWeeklyHub` rend un verdict

Le module garde son découpage actuel, qui est déjà le bon : une **façade d'extraction** qui
lit la page, et des **transformations** en aval (`hubToFact`, `parseMultiplier`,
`parseDiscount`, `parseBonusUntil`, `localizedName`, `localizedTitle`, `normalizeInstant`,
`resolveArticleDate`) qui ne connaissent que des données déjà structurées.

**Seule la façade change.** Les transformations sont intactes — le temps 2 les réalimentera
depuis le nouveau balisage.

| verdict | condition | effet |
|---|---|---|
| `payload-absent` | aucun morceau `self.__next_f.push` | **lève** — page plus rendue par Next.js, ou HTML tronqué |
| `page-meconnaissable` | payload présent, mais ni `id="weekly-updates-heading"` ni `aria-label="Weekly event sections"` | **lève** — refonte non couverte |
| `declaration-inconnue` | page reconnue, déclaration de statut hors énumération | **lève** — c'est ici qu'une semaine vivante tombe aujourd'hui, et c'est voulu |
| `sans-semaine` | page reconnue, déclaration reconnue comme « phase close » | **rend** `{ verdict, declaration }` — ce n'est pas une erreur |

L'ordre compte : chaque verdict suppose le précédent écarté, et chaque message nomme
l'ancrage qui a lâché, sans quoi le diagnostic se referait à la main dans 430 ko de HTML.

Il n'y a **pas** de branche `semaine-vivante` au temps 1. Une semaine vivante produit
`declaration-inconnue`, donc un échec bruyant. C'est le comportement correct tant qu'on ne
sait pas la lire : mieux vaut un run rouge qu'une semaine avalée en silence.

### 2. La capture

`commandWeekly` accepte `--capture <dir>`. Elle y écrit **toujours** `weekly.json` :

```json
{ "verdict": "sans-semaine", "message": "…", "declaration": "…", "capture": "hub.html" }
```

et y dépose `hub.html` — le HTML brut du hub — **dès qu'aucun fait n'a été produit**, quel
que soit le verdict.

Deux effets, et le second est le plus important :

- la Routine sait *pourquoi* il n'y a pas de semaine, et peut le porter dans la PR ;
- **la fixture du temps 2 se ramasse toute seule.** Aujourd'hui le HTML est jeté après
  usage : il a fallu aller rechercher la page à la main pour diagnostiquer. Au premier run
  qui suivra la publication d'une semaine, on aura le balisage réel d'une semaine vivante
  sans rien faire de plus.

`commandWeekly` n'échoue plus par exception non rattrapée : elle attrape, écrit le verdict,
**puis** décide du code de sortie — `0` pour `sans-semaine`, `1` pour tous les autres.

Deux verdicts lui appartiennent en propre, parce qu'ils ne portent pas sur la structure de
la page :

| verdict | quand |
|---|---|
| `hub-injoignable` | la requête a échoué — une source muette n'est pas un verdict sur sa structure, et les confondre relancerait la fausse piste du 06/08 |
| `erreur-interne` | l'exception ne porte pas de verdict : ce n'est pas la façade qui a parlé, c'est nous qui avons cassé |

Sans `--capture`, le comportement est celui d'aujourd'hui, moins le plantage sur
`sans-semaine`.

### 3. Le transport et le compte-rendu

`recolte.yml` :

- passe `--capture "$RUNNER_TEMP/recolte"` — le répertoire à partir duquel la branche de
  transport `veille/recolte` est construite. Rien n'atterrit dans le dépôt : le HTML de
  tiers transite par une branche orpheline jetable, force-poussée chaque jour, comme
  `pages/*.txt` déjà aujourd'hui. La contrainte IP porte sur `main`, et `main` n'est pas
  touché.
- l'étape « Compte-rendu » lit `weekly.json` au lieu de `steps.weekly.outcome`. Le message
  actuel — « structure du hub probablement changée » — n'est qu'une des quatre issues, et
  il nous a envoyés sur une fausse piste ce matin.

`.github/pr-body-veille.md` gagne une section qui dit à la relectrice ou au relecteur ce que
la semaine du mode en ligne a donné, y compris quand la réponse est « rien, et voici
pourquoi ».

`continue-on-error: true` **reste**. C'était une décision correcte et ce document ne la
rouvre pas : une dérive du hub ne doit pas emporter la récolte d'actu.

## Gestion d'erreur

Le tableau des verdicts ci-dessus **est** la gestion d'erreur. Deux règles s'y ajoutent :

- **Le code de sortie ne suffit jamais à distinguer les issues** — `1` couvre trois
  verdicts différents. `weekly.json` est la source de vérité ; le code de sortie ne sert
  qu'à colorer le run.
- **Un verdict qui lève écrit quand même sa capture.** Un échec qui détruit sa propre
  preuve force le diagnostic manuel — c'est ce qui a coûté la soirée du 06/08.

## Tests

Le module est du Node pur sans dépendance : `node --test`, comme le reste de
`tools/content-cli/`.

**Le cas négatif s'écrit en même temps que le contrôle, jamais « plus tard ».** Un contrôle
qu'on n'a jamais vu échouer est indiscernable d'un contrôle qui approuve à raison.

| cas | attendu |
|---|---|
| fixture réelle du 06/08 (semaine close, nouveau design) | `sans-semaine`, déclaration rapportée |
| HTML sans aucun morceau RSC | lève, message nommant le payload |
| payload présent, aucune ancre de page | lève, message nommant la page |
| page reconnue, déclaration inconnue | **lève** — le cas qui garde le principe honnête |
| ancienne page (payload `hub`, ancien balisage) | lève en `page-meconnaissable`, **jamais** un faux `sans-semaine` |

La dernière ligne est le contrôle négatif qui compte : c'est elle qui prouve que
`sans-semaine` ne peut pas être rendu par défaut.

Les tests des transformations en aval (`hubToFact`, `parseMultiplier`, `parseDiscount`,
`parseBonusUntil`, `localizedName`, `localizedTitle`, `normalizeInstant`,
`resolveArticleDate`, `parseRewards`) sont **conservés tels quels** : ces fonctions ne
changent pas, et elles portent les cas tordus d'une semaine réelle que personne
n'inventerait.

La fixture du temps 1 est un extrait réduit de la page réelle — même pratique que
`weekly-hub-rewards.html`, qui est déjà une section réelle de la source.

## Ce que ce document ne fait pas

- **Il ne lit aucune semaine vivante.** Temps 2.
- **Il ne réancre pas `ARTICLE_CTA` ni `parseRewards`.** Les deux visent des ancrages
  mesurés disparus (`Read the news story`, `id="weekly-rewards"`). Les corriger à l'aveugle
  serait deviner. Ils sont documentés comme périmés et se retranchent au temps 2, sur du
  balisage réel.
- **Il ne surveille pas la fraîcheur du contenu publié.** Un contrôle périodique — « existe-t-il
  un événement en ligne dont la fenêtre contient `now` ? le manifeste du CDN est-il en
  retard sur le dépôt ? » — attraperait toutes les causes, y compris la publication perdue
  du 06/08 quand GitHub Actions était en panne majeure et n'a créé aucun run pour la fusion
  de la PR #59. C'est la bonne réponse à une classe de problèmes plus large, et elle mérite
  son propre chantier plutôt qu'un diff qui fait deux choses.
