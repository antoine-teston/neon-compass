# Fusion automatique des PR de veille

**Décidé le 17 août 2026.** Une PR de veille dont les contrôles passent fusionne
seule, et son contenu part au CDN dans la foulée. La relecture humaine ne
disparaît pas : elle devient un contrôle **a posteriori**.

Ce document renverse deux décisions écrites, et c'est sa raison d'être — les
retrouver plus tard sans savoir qu'elles ont été levées coûterait une demi-heure
de perplexité :

- `.github/routine-veille.md` §8 : « Ne fusionne jamais toi-même : la relecture
  humaine de la PR est le portail d'approbation. »
- `.github/workflows/content.yml` (en-tête, 2026-08-03) : « la décision humaine
  existe toujours, c'est la RELECTURE DE LA PR de veille. Un bouton qui ne montre
  rien est un moins bon garde-fou qu'un diff qu'on relit. »

## Ce qui change vraiment

Rien dans la mécanique de publication. `publish-news` publie déjà tout seul au
merge sur `main` depuis le 2026-08-03 — c'est prouvé par le run 31996867305 du
17 août, étape « Publier » verte. Ce qui change est **qui déclenche le merge** :
un humain hier, la CI aujourd'hui.

La conséquence est donc entière et il faut la nommer : **du contenu part vers
tous les clients sans qu'un humain l'ait lu.**

## Pourquoi c'est acceptable

Parce que la relecture humaine n'était pas le seul garde-fou, ni même le plus
fiable. Ce que `check` refuse déjà, sans intervention :

| Risque | Ce qui l'arrête | Où |
| --- | --- | --- |
| Marque déposée dans un champ rédigé, dans l'une des cinq langues | `nominative-fields` + `check-publishable` | `publishable.mjs` |
| Rumeur publiée | `check-publishable` (une `rumor` ne passe jamais en `published`) | `publishable.mjs:65` |
| Texte non reformulé | `needsRewrite` bloque la publication | `publishable.mjs:57` |
| `multi-source` non prouvé | ≥ 2 hôtes distincts exigés | `publishable.mjs:76` |
| Reprise littérale d'une source | `check-originality` | `check-originality.mjs` |
| Source hors registre | `source-policy` | `source-policy.mjs` |
| Socle embarqué en retard | `check-seeds` | `cli.js` |

À quoi s'ajoute la Routine elle-même, qui ne marque `published` que ce qui est
`confirmed-official` ou `multi-source` : le reste reste `draft`, donc invisible.

Ce qui n'est plus vérifié avant publication, et qu'il faut assumer : **la
véracité et l'intérêt du claim**. Un modèle a reformulé une information tirée
d'une source du registre ; personne ne la relit avant qu'elle parte. Le remède
est la dépublication (repasser en `draft`, republier), pas la prévention.

C'est un arbitrage en faveur de la fraîcheur, qui est la fonctionnalité même de
ce fil — l'en-tête de `content.yml` le disait déjà pour ces deux kinds : « un
compte à rebours publié trois jours en retard n'est pas du contenu en retard,
c'est du contenu faux. »

## Le périmètre, qui est le vrai garde-fou

La fusion automatique ne mord que sur une PR **dont le diff entier** tient dans :

```
content/news/**   content/online-events/**   content/inbox/**
```

Tout le reste — un POI, un cheat, une collection, un fichier Swift, un workflow,
un agent — rend la PR non éligible, et elle attend un humain. Ce n'est pas de la
prudence décorative : c'est exactement la frontière que `publish-news` applique
déjà pour refuser de publier (`content.yml`, étape « Le merge reste-t-il dans le
périmètre de la veille »), et les deux doivent dire la même chose. POI et cheats
sont embarqués dans les socles de l'app : une erreur y coûte un binaire à
reprendre, pas un fragment à republier.

Une PR de veille qui déborde de son périmètre est d'ailleurs le signal qu'il
s'est passé autre chose que de la veille — précisément le cas où un humain doit
regarder.

## Le piège technique qui décide de l'architecture

**Un push fait avec `GITHUB_TOKEN` ne déclenche aucun workflow.** C'est une règle
de GitHub, destinée à empêcher les boucles ; elle n'a d'exception que pour
`workflow_dispatch` et `repository_dispatch`.

Conséquence directe, et contre-intuitive : si la CI fusionnait la PR avec son
jeton par défaut, le push sur `main` qui en résulte ne partirait **pas**, donc
`publish-news` ne tournerait pas, donc **rien ne serait publié**. L'automatisation
obtiendrait l'exact inverse de son but, en silence — le merge aurait l'air d'avoir
réussi.

D'où l'unique dépendance externe de ce chantier : un **jeton personnel à portée
fine** (`VEILLE_MERGE_TOKEN`, droits `contents: write` et `pull-requests: write`
sur ce seul dépôt). Le merge fait avec lui est attribué à un utilisateur réel, et
la chaîne de publication repart normalement.

Les deux alternatives ont été écartées :

- **Auto-merge natif GitHub** (`gh pr merge --auto`) : exige une protection de
  branche avec contrôles requis, et l'activer depuis la CI ramène le même
  problème d'attribution.
- **Fusionner avec `GITHUB_TOKEN` puis déclencher la publication à la main**
  (`workflow_dispatch`, qui échappe à la règle) : le job de publication manuelle
  publie TOUTES les collections et ne connaît pas le périmètre du merge. Il
  faudrait lui passer le SHA en entrée et dupliquer sa garde de périmètre — plus
  de pièces mobiles dans le job le plus délicat du dépôt.

## Architecture

Un workflow neuf, `.github/workflows/veille-fusion.yml`, et rien d'autre. Ni
`content.yml` ni `routine-veille.md` ne changent de comportement — le contrat de
la Routine gagne seulement une phrase disant que la fusion ne lui appartient
toujours pas, mais qu'elle n'attend plus un humain.

Déclencheur : `workflow_run` sur la fin de « Contenu ». C'est ce qui garantit que
la fusion ne peut pas précéder les contrôles, sans dépendre d'une protection de
branche. Il donne aussi la branche (`head_branch`) et la conclusion.

Suite de gardes, dans cet ordre, chacune capable d'arrêter seule :

1. La conclusion du run est `success`.
2. Le run portait sur `pull_request` (pas un push sur `main`).
3. La branche est exactement `veille/courante`.
4. Une PR ouverte existe pour cette branche, vers `main`.
5. Son diff entier tient dans le périmètre ci-dessus.
6. Le secret `VEILLE_MERGE_TOKEN` existe.

Chaque refus **s'écrit dans le résumé du run**, plutôt que de faire échouer le
workflow : une PR non éligible est un cas normal, et un rouge quotidien
apprendrait surtout à ignorer le rouge — la même règle que le reste de la chaîne.

Fusion en **squash**, comme tout le dépôt (`allow_squash_merge` est le seul mode
autorisé côté GitHub), et la branche n'est **pas** supprimée : la Routine repart
de `veille/courante` chaque jour et y ajoute un commit.

> **Corrigé le 2026-08-20 : la fusion se fait en MERGE COMMIT.** Les deux
> moitiés du paragraphe ci-dessus étaient en contradiction, et la première était
> fausse. `allow_merge_commit` et `allow_rebase_merge` sont vrais sur ce dépôt —
> vérifié par l'API, le squash n'a jamais été « le seul mode autorisé ».
>
> La contradiction : un squash n'est pas un ancêtre de la branche qu'il aplatit.
> Sur une branche **qu'on ne supprime pas**, les fichiers qu'elle a créés perdent
> donc tout ancêtre commun avec leurs jumeaux sur `main`, et dès que
> `publish-news` les transforme en aval (`status: draft` → `published`, plus
> `listedAt`), le resync du lendemain les rend en `both added` au lieu d'une
> modification que git fusionnerait seul. Le run du 2026-08-20 s'est arrêté là,
> sur quatre actus, et le contrat lui interdisait à juste titre de forcer ; ça se
> serait reproduit à chaque cycle où une actu est réellement publiée.
>
> Le merge commit rend les commits de la branche ancêtres de `main` : le resync
> suivant est un fast-forward et ne peut plus conflire. Sans effet sur la
> publication — `publish-news` calcule son périmètre par
> `git diff <avant> <après> -- content/`, dont le résultat net est le même dans
> les deux modes. Ce que la branche roulante gagne en propreté, `main` le paie
> en commits de veille visibles dans son historique : c'est le prix assumé, et
> il ne concerne que cette PR-là.

## Ce qui reste à la charge d'un humain

- Relire `main` après coup, et dépublier ce qui ne va pas.
- Toute PR de veille qui sort du périmètre.
- La publication des POI, cheats, guides et collections — inchangée, bouton
  manuel.
