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
  (`weekly-hub.mjs`) — **ou dit pourquoi il n'y en a pas**, voir ci-dessous ;
- matérialisé les faits `kind: "news"` et `kind: "online-event"` — de façon
  idempotente, un fait déjà traité ne recrée pas de doublon ;
- rédigé les items neufs en FR et EN, sans marque déposée ;
- passé les garde-fous : schémas, règles éditoriales, socles embarqués à jour,
  et les tests des transformations.

## Semaine du mode en ligne

<!-- La Routine remplit cette section depuis `weekly.json`, déposé par le
     workflow sur la branche de transport à côté des faits. Elle la remplit
     TOUJOURS, y compris — surtout — quand il n'y a pas de semaine. -->

**Verdict :** `<verdict>` — `<message>`

Quatre issues possibles, et une seule n'est pas une anomalie :

| verdict | ce que ça veut dire |
|---|---|
| `sans-semaine` | La source déclare sa phase hebdomadaire close. **Rien à récolter, et ce n'est pas une panne** — le cas normal entre deux semaines. |
| `declaration-inconnue` | La page est reconnue mais se déclare autrement. C'est le cas d'une **semaine vivante** que l'extracteur ne sait pas encore lire. À traiter. |
| `page-meconnaissable` | Les ancres de la page ont bougé : refonte côté source. À traiter. |
| `payload-absent` / `hub-injoignable` | La page n'est plus rendue par Next.js, ou n'a pas répondu. |

Pourquoi cette section existe : jusqu'au 2026-08-06, un échec de cette étape ne
produisait **aucun fichier**, et « absent parce que cassé » était indiscernable
d'« absent parce que rien de neuf ». La panne a couru une journée avant d'être vue
depuis l'app. Le HTML du hub est joint sur `veille/recolte` (`hub.html`) quand rien
n'a été récolté.

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
