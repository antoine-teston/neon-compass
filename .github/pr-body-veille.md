Récolte automatique quotidienne (Routine `neon-compass-veille`).

**Cette PR est roulante.** Elle porte **un commit par jour de récolte** et reste
ouverte jusqu'à sa fusion ; le run du lendemain la complète au lieu d'en ouvrir
une seconde. Relire commit par commit est la façon prévue de suivre une cadence
quotidienne sans sept PR par semaine.

**Rien n'a été publié.** La publication reste une étape distincte, et cette PR
n'y touche pas.

## Comment ce contenu est arrivé ici

La chaîne est coupée en deux, pour une raison qui n'est pas un choix de style :

1. **Le réseau** — workflow `Récolte` sur un runner GitHub. Les quatre sources
   du registre ne sont joignables que de là : la passerelle de sortie des
   sessions d'agent refuse le CONNECT sur ces domaines. Ce workflow ne fait que
   rapporter des octets, sans modèle ni clé d'API, et publie sa récolte en
   **artefact éphémère** — le texte des articles est du texte de tiers, il
   transite mais n'est jamais commité.
2. **Le jugement** — cette Routine. Elle lit l'artefact, en extrait des faits
   reformulés, matérialise et rédige. Elle ne visite aucune page web.

## Ce que le run a fait

- vérifié que les quatre sources répondent (`fetch-source.mjs preflight`) avant
  toute récolte — un run vert sans contenu signifie donc « journée calme »,
  jamais « veille aveugle » ;
- extrait les faits des dernières 48 h vers `content/inbox/`, en relisant les
  faits déjà présents pour ne rien re-signaler ;
- récupéré la semaine du mode en ligne, en tableau et sans modèle
  (`weekly-hub.mjs`) ;
- matérialisé les faits `kind: "news"` et `kind: "online-event"` — de façon
  idempotente, un fait déjà traité ne recrée pas de doublon ;
- rédigé les items neufs en FR et EN, sans marque déposée ;
- passé les garde-fous : schémas, règles éditoriales, socles embarqués à jour,
  et les tests des transformations.

## À relire avant de fusionner

- **le compte-rendu de run** dans `content/inbox/runs/` : il liste les sources
  visitées, ce qui a été écarté et pourquoi, et les doutes laissés à un humain.
  Écarté n'est pas absent ;
- la formulation des items d'actu rédigés ce run — c'est le seul maillon confié à
  un modèle. Les événements en ligne n'en passent pas : leurs étiquettes sont
  composées, leurs noms sont repris tels quels ;
- le statut `draft` / `published` de chacun. Les rumeurs restent en `draft` par
  construction : `check-publishable` refuse de les publier. Un événement en ligne
  arrive en `draft` même complet — le passer à `published` est la ratification
  humaine, et c'est la seule garantie de ce kind (`single-source` y est
  publiable, contrairement à l'actu).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
