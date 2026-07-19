# Agents de récolte & traitement de données — architecture

> 20 juillet 2026. Prolonge le pipeline (pseudocode du même jour) : les étapes
> humaines coûteuses sont déléguées à des agents planifiés. La donnée approuvée
> arrive « directement in app » via le chemin existant CLI → Firestore →
> `contentVersion` → sync SwiftData — sans release App Store.

## Principe : agents partout, humain au portail

```
                    ┌──────────── AGENTS (planifiés) ────────────┐
[Sources autorisées] → scout → content/inbox/*.facts.json        │
                       editor → content/{poi,cheats,guides}/ (draft)
                       qa     → rapport conformité + recoupement │
                    └────────────────────┬───────────────────────┘
                              HUMAIN : review du diff git, approve
                                         │
                            CLI publish → Firestore → app (delta sync)
```

Ce qui est automatisé : veille des sources, extraction de **faits** structurés,
reformulation multilingue, recoupement ≥ 2 sources, validation de schéma,
préparation du diff de publication.
Ce qui ne l'est pas (v1) : l'approbation finale. Un `git diff` de `content/` se
relit en minutes ; c'est l'assurance IP (reformulation réellement originale) et
la garde anti-hallucination. Si la qualité tient sur la durée, l'auto-publish
pourra être ouvert par catégorie à faible risque (actu) — jamais pour les cheats.

## Les trois agents (`.claude/agents/`)

| Agent | Rôle | Sorties |
|---|---|---|
| `data-scout` | Veille des sources du registre (§7 du spec). Extrait des **faits bruts** avec URL + date, jamais de texte recopié | `content/inbox/YYYY-MM-DD-*.facts.json` |
| `content-editor` | Transforme les faits de l'inbox en contenu au schéma `content/` : rédaction originale EN/FR, statut `draft` | fichiers `draft` dans `content/` |
| `content-qa` | Vérifie : recoupement ≥ 2 sources (cheats), schéma, aucune phrase copiée d'une source, aucun terme déposé, positions 0-1 valides | `content/inbox/qa-report.md` |

Chaîne type (hebdo avant la sortie, quotidienne après) :
`data-scout → content-editor → content-qa → [humain] → CLI publish`.

## Règles de collecte imposées aux agents (dures)

1. **Liste blanche de sources** = le registre du spec, rien d'autre. Jamais de
   site dont le robots.txt exclut les bots IA (State of Leonida en est exclu).
2. **Faits seulement** : un fait extrait = `{claim, source_url, date, quote_forbidden}`.
   Le texte source n'est jamais stocké au-delà du strict nécessaire au recoupement.
3. **Volume de veille, pas de crawl** : quelques pages ciblées par run, pas de
   parcours exhaustif d'un site (interdit §7).
4. **Cheats** : `status: published` impossible sans `verifiedBy >= 2` — le CLI
   le rejette de toute façon (garde-fou déjà spécifié).
5. Traçabilité : chaque run laisse un log daté dans `content/inbox/runs/`.

## Déclenchement

- **Maintenant → octobre** : run hebdomadaire manuel (`claude` + agent) ou
  planifié via `/schedule` (agent cloud récurrent). Peu de matière avant la sortie.
- **Sprint jour J (19 nov.)** : cadence quotidienne, l'inbox devient la todo du
  matin ; le mode éditeur in-app reste le chemin primaire pour les POI découverts
  en jeu, les agents couvrent la veille communautaire (cheats surtout).
- Alternative CI : GitHub Actions cron qui ouvre une PR `content/` par run —
  la review de PR devient le portail humain.

## Ce que ça change dans l'app : rien

L'app ne sait pas que des agents existent. Elle consomme Firestore via la sync
delta déjà spécifiée. C'est voulu : le pipeline de production de contenu peut
évoluer librement (plus d'agents, auto-publish partiel) sans toucher au client.
