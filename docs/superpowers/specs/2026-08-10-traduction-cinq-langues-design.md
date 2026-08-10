# Traduire le contenu dans les cinq langues

## Problème

L'app expédie FR, EN, ES, IT et DE depuis la v1. Le contenu, lui, est bilingue :
**679 items sur 680 n'ont que `en` et `fr`**, soit 3153 champs manquants et
245 ko de texte à produire. Un utilisateur espagnol, italien ou allemand voit
donc aujourd'hui tout le contenu en anglais, silencieusement, par le repli de
`LocalizedText`.

La cause n'est pas un oubli, c'est une couture — la même maladie que le chantier
identité/refus qui précède. Deux moitiés se déléguaient mutuellement le travail :

- `.claude/agents/content-editor.md:15` : « ES/IT/DE sont générés par le CLI —
  ne les remplis pas. »
- `tools/content-cli/cli.js:370` : « translate : seul `--dry-run` est implémenté
  (l'appel IA reste à câbler). »

L'agent ne traduit pas parce que le CLI s'en charge. Le CLI ne s'en charge pas.
Personne ne traduit, et rien ne le signale — `translate --dry-run` existe et
compte les manques depuis le début, mais aucun contrôle ne le lance.

**L'exception éclaire le reste.** Le seul item complet dans les cinq langues est
l'unique `online-event`, et il n'a jamais été traduit : `weekly-hub.mjs`
**compose** ses libellés depuis un vocabulaire figé qui existe en cinq langues
(`it: 'Aggiornamento settimanale'`, ligne 480). Là où une machine assemble, les
cinq langues sont là depuis le premier jour. Là où un modèle rédige, il n'y en a
que deux.

## Ce qui a été mesuré

| kind | items | champs manquants | texte à produire |
|---|---:|---:|---:|
| `poi-gtav` | 537 | 2454 | 153 ko |
| `news` | 80 | 480 | 77 ko |
| `poi` | 11 | 66 | 10 ko |
| `cheats` | 36 | 108 | 5 ko |
| `collections` | 15 | 45 | 1 ko |
| **total** | **679** | **3153** | **245 ko** |

Les deux natures ne se traitent pas pareil. Les 2520 champs de POI sont des
**noms de lieux et des notes courtes**, quasi mécaniques. Les 480 champs d'actu
sont de la **prose rédigée**, où le ton de l'app et la contrainte IP s'appliquent.

## Décisions de cadrage

**C'est la Routine qui traduit, pas le CLI.** Tranché le 2026-08-10. Elle écrit
déjà `title` et `body` en EN et FR depuis le `claim` ; écrire les cinq langues
est le même geste, avec le même modèle, dans la même passe — aucune clé d'API
nouvelle, aucun coût nouveau, aucun secret nouveau. L'« appel IA à câbler » de
`cli.js:370` n'a donc jamais à exister.

**Le CLI reste sans IA, mais cesse d'être passif.** Il gagne de quoi *préparer*
et *appliquer* une traduction produite ailleurs :

- `translate --todo` rend le travail à faire, texte source compris, en JSON.
- `translate --apply <fichier>` écrit les traductions rendues, après validation.

Ni l'un ni l'autre n'appelle un modèle. La frontière est nette : le CLI sait
quoi traduire et sait ranger le résultat ; il ne sait pas traduire.

**Aucun verrou sur la publication.** Une traduction manquante ne bloque rien : le
repli anglais existe et fonctionne, et bloquer figerait le fil quotidien au
premier hoquet. `translate --dry-run` reste le contrôle qui le dit, et la console
l'affiche déjà sous « Traductions manquantes ».

C'est un choix assumé et il a un coût : rien ne *force* la traduction à se faire.
Le garde-fou est ailleurs — dans le contrat de la Routine, qui écrit désormais
les cinq langues à la rédaction, donc au moment où le texte est frais et où le
sujet est compris.

**Le rattrapage se fait en une passe**, sur les 679 items d'un coup. Il produit
une PR relue.

**Mais les 537 POI de la carte de référence ne se traduisent pas — ils se
composent.** Constaté en les regardant, après avoir traduit les trois petits
kinds : leurs titres sont massivement GABARITÉS, et le suffixe est toujours un
nom de lieu qui reste identique dans les cinq langues.

| famille | occurrences |
|---|---:|
| `Gas Station` | 157 |
| `Under the Bridge #N` | 50 |
| `Nuclear Waste #N` | 30 |
| `Knife Flight #N` | 15 |
| `Hidden Package #N` | 11 |
| `Epsilon Tract #N` | 10 |
| `Spaceship Part #N - <lieu>`, `Stunt Jump #N - <lieu>`, `Letter Scrap #N - <lieu>` | ~150 |
| noms propres de véhicules, identiques EN=FR | 52 |

Confier ces 2454 champs à un modèle serait payer cher une variabilité qu'on ne
veut pas : deux passes produiraient deux formulations pour « Gas Station », et
rien ne le rattraperait. **Une table de préfixes, appliquée mécaniquement, rend
les cinq langues déterministes et relisibles** — c'est précisément ce qui fait
de l'unique `online-event` le seul item complet du dépôt depuis toujours.

Restent alors une soixantaine de titres descriptifs uniques (« Michaels
mansion », « Meth lab ») et les 281 notes, qui eux relèvent bien de la
rédaction.

**Conséquence sur l'ordre des lots** : `news` (prose, 80 items) et les notes de
POI passent par la Routine ; les titres gabarités passent par une table. Les
traiter d'un même geste était l'erreur de cadrage que ce constat évite.

## Architecture

### `translate --todo` — ce qu'il reste à faire

Rend sur la sortie standard un JSON `{ chemin: { champ: { en, fr } } }`, limité
aux champs dont il manque au moins une langue. Le `fr` accompagne le `en` parce
que deux formulations valent mieux qu'une pour lever une ambiguïté — un `title`
d'actu tient en huit mots, et l'anglais seul peut être ambigu là où le français
tranche.

Options : `--kind <nom>` pour ne sortir qu'un kind, `--limit <n>` pour découper
un rattrapage en lots. Les deux servent le même but — rendre le travail
digestible par une passe d'agent, plutôt que de produire un fichier de 245 ko
qu'aucun contexte ne tient.

### `translate --apply <fichier>` — ranger le résultat

Lit un JSON de la même forme, `{ chemin: { champ: { es, it, de } } }`, et écrit
les valeurs dans les fichiers de contenu.

Il REFUSE plutôt que de deviner, et chaque refus est un cas qui s'est déjà vu
ailleurs dans ce dépôt :

| Situation | Réponse |
|---|---|
| chemin hors de `content/` | refus — aucun chemin venu d'un fichier n'atteint le disque ailleurs |
| item inexistant | refus, en le nommant |
| champ absent de `UI_FIELDS` | refus — on ne crée pas un champ localisé qui n'existe pas au schéma |
| langue hors de `es`/`it`/`de` | refus — `en` et `fr` sont écrits à la rédaction, pas ici |
| valeur vide ou non-chaîne | refus |
| écrasement d'une valeur DÉJÀ présente | refus, sauf `--force` |

Le dernier compte le plus : un rattrapage rejoué par mégarde ne doit pas écraser
une traduction qu'un humain aurait corrigée à la main. Dans le doute, il refuse.

Après écriture, `--apply` relance `validate` sur les fichiers touchés. Une
traduction qui casserait le schéma doit tomber à l'écriture, pas trois jours plus
tard à la publication.

### Le contrat de la Routine

`.claude/agents/content-editor.md` bascule : cinq langues à la rédaction, plus
« ne les remplis pas ». C'est la moitié qui manquait, et elle se livre **dans le
même commit** que le CLI qui sait les ranger — livrer une moitié de couture est
précisément ce que ce dossier reproche à ses prédécesseurs.

La contrainte IP s'applique aux cinq langues comme aux deux : les marques restent
interdites partout où l'agent rédige, et `check-publishable` les traque déjà dans
tous les champs de `UI_FIELDS`, quelle que soit la langue.

## Erreurs

| Situation | Réponse |
|---|---|
| `--apply` sans fichier | usage, code 1 |
| fichier JSON illisible | l'erreur nomme le fichier, code 1 |
| un seul item fautif dans le lot | **rien n'est écrit** — le lot entier est refusé, comme `materializeNews` refuse un lot à conflit |
| `--todo` sans rien à faire | JSON vide `{}`, code 0 |

Le refus en bloc est délibéré : appliquer la moitié d'un lot laisserait un
rattrapage à moitié fait, sans qu'on sache lequel.

## Tests

- `--todo` ne rend que les champs réellement manquants, et rien pour un item
  complet.
- `--todo --kind` et `--limit` bornent, et le disent.
- `--apply` écrit les trois langues et le prouve en relisant le fichier.
- **Chaque refus du tableau ci-dessus a son test**, et le lot entier reste
  non écrit quand un seul item est fautif.
- `--apply` refuse d'écraser une valeur existante sans `--force`, et l'accepte
  avec — prouvé dans les deux sens.
- Un aller-retour complet sur un kind : `--todo`, traduction, `--apply`,
  `--dry-run` retombe à zéro pour ce kind.

## Hors périmètre

- **Le chinois**, candidat non engagé : il demande une décision d'écriture
  (simplifié ou traditionnel) et sa propre revue App Store.
- **Un verrou de publication** sur les traductions manquantes, écarté ci-dessus.
- **La qualité relue par un locuteur** de chaque langue. Personne dans l'équipe
  ne lit les cinq ; le contrôle disponible est le schéma, la contrainte IP et
  `check-originality`. C'est une limite réelle, écrite ici plutôt que découverte
  dans une critique de l'App Store.
