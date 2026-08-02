Récolte hebdomadaire automatique (workflow `Veille hebdomadaire`).

**Rien n'a été publié.** La publication reste le déclenchement manuel du
workflow `Contenu`, et cette PR n'y touche pas.

Ce que le run a fait :

- extrait les faits de la semaine vers `content/inbox/` (agent `data-scout`) —
  **run du lundi seulement** ;
- récupéré la semaine du mode en ligne depuis le hub de la source, en tableau et
  sans modèle (`weekly-hub.mjs`) ;
- matérialisé les faits `kind: "news"` et `kind: "online-event"` dans leurs
  répertoires — de façon idempotente, un fait déjà traité ne recrée pas de
  doublon ;
- rédigé les items neufs en FR et EN, sans marque déposée — **lundi seulement** ;
- passé les garde-fous : schémas, règles éditoriales, socles embarqués à jour,
  et les tests des transformations.

À relire avant de fusionner :

- la formulation des items d'actu rédigés ce run — c'est le seul maillon confié à
  un modèle. Les événements en ligne n'en passent pas : leurs étiquettes sont
  composées, leurs noms sont repris tels quels ;
- **le résumé du run**, section « Mode en ligne » : il liste ce que la source
  publie et que le schéma n'a pas pu porter. Écarté n'est pas absent ;
- le statut `draft` / `published` de chacun. Les rumeurs restent en `draft` par
  construction : `check-publishable` refuse de les publier. Un événement en ligne
  arrive en `draft` même complet — le passer à `published` est la ratification
  humaine, et c'est la seule garantie de ce kind (`single-source` y est
  publiable, contrairement à l'actu).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
