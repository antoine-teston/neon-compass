# Mode éditeur interne — mise en service et boucle de travail

**Date** : 2026-07-27
**Spec** : `docs/superpowers/specs/2026-07-27-editeur-interne-design.md`

L'éditeur est un **poseur de pins au doigt**, disponible uniquement dans le build debug lancé depuis
Xcode. Il n'existe pas dans le binaire soumis à Apple.

## 1. Mise en service (une fois)

L'écriture dans `editor_drafts` est réservée à un seul UID, et `firestore.rules` porte aujourd'hui un
marqueur à remplacer :

```
request.auth.uid == 'REMPLACER_PAR_UID_EDITEUR'
```

Tant qu'il est là, **personne ne peut écrire** — le défaut est fermé, pas ouvert. Pour le renseigner :

1. Lancer l'app en debug, onglet Carte, carte « VI ».
2. Armer l'éditeur (bouton crayon, en bas à droite). Le bandeau affiche l'UID du compte connecté ; il
   est sélectionnable pour être copié.
3. Le reporter dans `firestore.rules` à la place du marqueur.
4. `cd tools/content-cli && node cli.js rules-diff` — le diff ne doit montrer que le bloc
   `editor_drafts`.
5. `node cli.js deploy-rules`.

> `deploy-rules` remplace le ruleset **d'un bloc**. Toujours regarder le diff avant : les lignes
> préfixées `-` sont celles qu'un déploiement perdrait.

Note : la commande `pull-drafts` passe par le compte de service, qui contourne les règles. Elle
fonctionne donc même avant cette étape — c'est l'app qui ne peut pas écrire tant que l'UID manque.

## 2. La boucle de travail

**Sur le téléphone, manette en main.** Une règle unique gouverne les gestes :

| Geste | Effet |
|---|---|
| Appui long sur le vide | Grille des six catégories → un tap → posé (moins de 3 s) |
| Appui long sur un POI → « Déplacer » | Arme le déplacement ; l'appui long **suivant** pose la nouvelle position |
| Appui long sur un POI → « Supprimer » | Confirmation, puis brouillon de suppression |
| Tap sur un spot communautaire → « Adopter » | Brouillon pré-rempli avec sa position et son titre |

Les pins de brouillon portent un contour pointillé. Le bandeau indique combien ont été posés et
combien restent à envoyer — hors-ligne, la file du SDK Firestore encaisse et rejoue au retour du
réseau, y compris après avoir tué l'app.

L'éditeur refuse de s'armer sur la carte de référence GTA V, et se désarme tout seul si on y bascule.

**Sur le Mac, ensuite :**

```sh
cd tools/content-cli
node cli.js pull-drafts     # ou le bouton dans la console web (npm run ui)
```

Chaque brouillon devient un fichier `content/poi/*.json` en `status: "draft"`, avec un titre généré
horodaté. Il ne reste qu'à écrire les vrais titres et notes, passer en `published`, puis publier :

```sh
npm run release
```

`publish` ne pousse que le `published` : un brouillon incomplet peut dormir dans le dépôt aussi
longtemps qu'il faut sans jamais risquer la production.

## 3. Ce que `pull-drafts` garantit

- **Idempotent** : la clé d'identité vit dans `processedFrom`, donc relancer la commande se réapparie
  au fichier existant au lieu d'en créer un second.
- **Jamais à moitié** : un conflit (un id frappé qui désignerait déjà autre chose) bloque le lot
  entier et n'écrit rien.
- **Une suppression de POI publié devient une pierre tombale** (`deleted: true`), pas une suppression
  de fichier — le socle embarqué ne se décompile pas du binaire.
- **Un déplacement vers un POI disparu du dépôt** est signalé et classé, pas rejoué indéfiniment.

## 4. Avant toute soumission App Store

```sh
xcodebuild -project NeonCompass.xcodeproj -scheme NeonCompass -configuration Release \
  -destination "$(Scripts/simulator-destination.sh)" build
Scripts/check-release-binary.sh
```

Le script cherche le marqueur `NCEditorArmedMarker` dans tous les Mach-O du bundle et échoue si
l'éditeur a fui hors de `#if DEBUG`.

**Piège rencontré en l'écrivant, et pourquoi le script refuse une build Debug** : en Debug, Xcode 26
place le code de l'app dans `NeonCompass.debug.dylib` et laisse un binaire principal de 58 Ko
quasiment vide. Chercher le marqueur dans le seul binaire principal d'une build Debug ne trouve donc
rien — un succès parfaitement trompeur. Le script détecte ce cas et sort en erreur plutôt que de
rassurer à tort.

État vérifié le 2026-07-27 : marqueur **absent** du binaire Release, **présent** dans le
`.debug.dylib` de la build Debug. Le contrôle prouve donc quelque chose.
