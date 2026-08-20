# Parcours interactif sur la carte — design validé

**Date** : 2026-08-19
**Statut** : validé par Antoine (chat, deux questions AskUserQuestion + design en quatre sections approuvé par « Ok go »)
**Remplace** : la feuille `RoutePlannerSheet` (liste numérotée statique), issue du plan 6b-2.

## Contexte et objectif

Le planificateur d'itinéraire Pro calcule un glouton du plus proche voisin sur
les collectibles restants (`Core/Map/RoutePlanner.swift`) et l'affiche dans une
feuille purement présentationnelle. Une liste de noms sans carte n'aide pas à
faire la tournée : l'utilisateur doit garder la feuille en tête, chercher chaque
point à la main, et le marquer trouvé depuis sa fiche.

Le remplacement : un **mode parcours** sur la carte elle-même, sur le modèle du
mode de placement des épingles — un état, un panneau, une épingle dédiée, une
sortie. La caméra mène de point en point ; une coche valide l'étape et fait
avancer.

## Décisions (tranchées, ne pas relitiger)

1. **La coche marque « trouvé »** — c'est `MapModel.toggleFound(_:)`, le seul
   registre : anneaux du Profil, « masquer les trouvés », synchro Pro en
   profitent. Pas de second registre propre au parcours.
2. **Mode direct, feuille supprimée** — le bouton itinéraire (Pro, inchangé
   dans `MapFilterControls`) entre immédiatement en mode. `RoutePlannerSheet`
   est supprimé. Le panneau du mode affiche « Étape n/N », ce qui rend la
   liste statique redondante.

   **Amendé le 2026-08-20** : le bouton entre d'abord dans une étape de
   **désignation du départ** — un tap sur la carte choisit le collectible
   restant le plus proche, et la tournée part de là. Ce qui est supprimé
   reste supprimé (aucune feuille, aucune liste) ; ce qui change est qu'on ne
   tombe plus dans la tournée sur un départ arbitraire. Motif : le départ
   était le premier élément de l'ordre des fichiers de contenu, ce qui ne
   coûtait rien quand la tournée était une liste, mais coûte un vrai trajet
   depuis que la caméra y vole. Décision d'Antoine, contre les deux autres
   options proposées (laisser tel quel ; démarrer au plus près du centre de
   la vue).

7. **Les instructions du lieu s'affichent dans le panneau** — décidé le
   2026-08-20. Le champ `POI.note`, que 141 des 152 collectibles renseignent,
   dit où chercher (« immergée dans la petite baie au nord, elle brille sur le
   fond »). Sans elle, le mode indique un point sur une carte sans dire quoi y
   faire. Rendue avec le traitement déjà en place dans la fiche
   (`ViewThatFits` : hauteur naturelle, ou défilement si la note est longue),
   l'appelant bornant ce qu'il PROPOSE — les notes vont jusqu'à 440
   caractères et un panneau non borné avalerait la carte.
3. **Ordre figé à l'entrée** — le glouton est calculé une fois. Pas de
   recalcul dynamique : un « Passer » suivi d'un recalcul re-proposerait
   immédiatement le point passé (il reste le plus proche), ce qui rendrait le
   saut inopérant.
4. **Périmètre inchangé** — collectibles restants non trouvés, calculés sur
   `model.pois` COMPLET, jamais sur `filteredPOIs` : les puces de catégorie et
   la recherche ne rétrécissent pas la tournée en silence (décision du plan
   6b-2, revalidée ici).
5. **Saut automatique des trouvés externes** — un POI marqué trouvé pendant le
   parcours par un autre chemin (fiche POI, synchro d'un autre appareil) est
   sauté à l'avancement, sans état d'erreur.
6. **Sortie libre** — un bouton quitte le mode à tout instant. Rien à
   sauvegarder : les validations sont déjà dans la progression. Le parcours ne
   persiste pas entre lancements de l'app.

## Cycle du mode

```
bouton itinéraire (Pro)
  → collectibles restants
      ├─ vide → panneau en état « tout est trouvé » (map.routePlanner.empty), seule sortie : Quitter
      └─ non vide → DÉSIGNATION DU DÉPART (amendement du 20/08)
            invite « Choisissez votre départ », frappe du contenu éteinte
            tap sur la carte → collectible restant le plus proche du doigt
                             → glouton depuis ce point → mode actif, focus caméra
            bouton itinéraire (2e appui) ou Annuler → sortie, aucune tournée
mode actif, étape n :
  Valider → toggleFound(POI courant) → avance (en sautant les trouvés externes) → focus caméra
  Passer  → avance sans marquer → focus caméra
  Quitter → sortie immédiate
dernier point validé/passé → état « tournée terminée » (~1 s) → sortie automatique
```

L'avancement « saute les trouvés externes » : `advance()` cherche le prochain
index dont le POI n'est pas trouvé. Un POI passé (skippé) n'est PAS re-proposé
dans ce parcours.

## Interface

- **Panneau** : même modèle d'accueil que le panneau de placement
  (`placementPanel` dans `MapScreen`) — en bas en compact, latéral en régulier,
  verre (`.glassEffect`). Contenu : « Étape n/N », titre du POI courant
  (`title.resolved(for:)`), boutons Valider (proéminent), Passer, Quitter (X).
- **POI courant** : rendu comme **épingle dédiée par-dessus la carte**, par le
  même canal que `MapPlacementPin` dans `MapScrollView` — jamais via le
  pipeline de groupement (un cluster n'a pas de « point courant »). Pleine
  taille, halo pulsant dans la teinte de sa catégorie (`POIPinPalette`). Reste
  dans la règle « trois accents lumineux par écran ».
- **Caméra** : `MapFocusRequest` existant (canal du carnet d'épingles), un
  focus par avancement.
- Les interactions normales de la carte restent actives pendant le mode
  (zoom, pan, fiches POI) — le mode est un calque, pas une modale.

## Architecture

| Unité | Rôle | Dépendances |
|---|---|---|
| `Core/Map/RouteRun.swift` (nouveau) | Logique pure du parcours : liste ordonnée d'identifiants, index courant, `validate`/`skip`/avancement avec sauts, état terminé. Aucun import UI. | `POI` (identifiants seulement) |
| `Features/Map/RouteModePanel.swift` (nouveau) | Le panneau, muet : affiche l'état, remonte trois actions par fermetures. | `RouteRun` (lecture), catalogue |
| `MapScreen` | Détient l'état du mode (`@State`), l'entrée depuis le bouton, le câblage `toggleFound`/caméra/panneau. `showRoutePlanner` et sa `.sheet` disparaissent. | tout l'existant |
| `MapScrollView` | Un rendu « cible de parcours » à côté du rendu placement existant (position + catégorie). | existant |
| `RoutePlanner` | Inchangé. | — |

`RoutePlannerSheet.swift` supprimé → `xcodegen generate` obligatoire.

## Localisation

Nouvelles clés (5 langues, registre informel existant) : validation, passer,
quitter, format d'étape « n/N », titre du POI en cours de tournée, état
terminé. Réutilisées : `map.routePlanner.title`, `map.routePlanner.empty`.
Supprimée : `map.routePlanner.stepFormat` (avec la feuille). Édition du
catalogue par retouches chirurgicales UNIQUEMENT — jamais de relecture/redump
JSON du fichier entier (règle du plan 6c).

## Tests

- `RouteRunTests` (Swift Testing, logique pure) : ordre initial, avance sur
  validation, avance sur saut, saut automatique d'un trouvé externe (y compris
  plusieurs consécutifs), terminaison par validation et par saut, entrée vide,
  « le point passé n'est pas re-proposé ».
- Vérification simulateur (le compte Pro de test est en place) : entrée en
  mode, zoom point-à-point réel, la coche coche vraiment (fiche POI + anneau du
  Profil), Passer, Quitter, tournée terminée. Rappel : taps `cliclick` hors
  `ScrollView` seulement — la barre de boutons de la carte et le panneau du
  mode y échappent, comme le panneau de placement.

## Hors périmètre (volontaire)

- Tracé d'une polyligne entre les points.
- Recalcul dynamique de l'ordre en cours de route.
- Réordonnancement manuel des étapes.
- Persistance du parcours entre lancements.
- Toute retouche aux thèmes/icônes Pro (remarque d'Antoine du 2026-08-19 :
  peu différenciants — noté, chantier séparé s'il a lieu).
