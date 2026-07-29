Récolte hebdomadaire automatique (workflow `Veille hebdomadaire`).

**Rien n'a été publié.** La publication reste le déclenchement manuel du
workflow `Contenu`, et cette PR n'y touche pas.

Ce que le run a fait :

- extrait les faits de la semaine vers `content/inbox/` (agent `data-scout`) ;
- matérialisé les faits `kind: "news"` en items `content/news/` — de façon
  idempotente, un fait déjà traité ne recrée pas de doublon ;
- rédigé les items neufs en FR et EN, sans marque déposée ;
- passé les garde-fous : schémas, règles éditoriales, socles embarqués à jour,
  et les tests des transformations.

À relire avant de fusionner :

- la formulation des items rédigés ce run — c'est le seul maillon confié à un
  modèle ;
- le statut `draft` / `published` de chacun. Les rumeurs restent en `draft` par
  construction : `check-publishable` refuse de les publier.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
