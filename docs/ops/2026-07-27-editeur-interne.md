# Mode éditeur interne — mise en service et boucle de travail

**Date** : 2026-07-27
**Spec** : `docs/superpowers/specs/2026-07-27-editeur-interne-design.md`

L'éditeur est un **poseur de pins au doigt**, disponible uniquement dans le build debug lancé depuis
Xcode. Il n'existe pas dans le binaire soumis à Apple.

## 0. Repli sans compte — le mode par défaut aujourd'hui

Écrire dans `editor_drafts` demande un compte, un compte demande Sign in with Apple, et Sign in with
Apple demande l'**adhésion payante au programme développeur Apple** (elle seule permet de provisionner
cette capacité, ainsi que les App Groups et les push). Vérifié le 2026-07-27 : sans elle, le build sur
appareil s'arrête net sur `Signing for "NeonCompass" requires a development team`, et la connexion
échoue en simulateur dans les services d'Apple eux-mêmes (`Failed to check in with IDMS`, 401 sur
`gsas.apple.com`) — l'app n'est jamais rappelée.

L'éditeur fonctionne donc **sans rien de tout ça** :

1. Les brouillons sont écrits dans `Documents/editor-drafts.json`, visible depuis l'app **Fichiers**
   (« Sur mon iPhone » → NeonCompass). Cette visibilité est activée **en Debug seulement** : l'app
   publiée n'ouvre pas son dossier.
2. Récupérer le fichier (AirDrop, iCloud Drive, câble), puis :

```sh
cd tools/content-cli && node cli.js pull-drafts --file ~/Downloads/editor-drafts.json
```

Aucun credential n'est requis sur ce chemin. Le fichier est ensuite renommé `.applied.json` plutôt que
supprimé — une capture de terrain ne se refait pas, et l'idempotence par `processedFrom` rend un rejeu
inoffensif de toute façon.

`EditorDraftRouter` choisit **à chaque écriture** : Firestore si un compte existe, le fichier sinon.
Le jour où l'adhésion est prise, rien à changer — le chemin distant se rallume tout seul, et un refus
distant retombe malgré tout sur le fichier plutôt que de perdre une capture.

## 1. Mise en service du chemin Firestore (le jour où un compte existe)

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

Depuis le 2026-08-06, **le workflow `Binaire Release` le fait pour toi** à chaque poussée et à
chaque PR vers `main` qui touche les sources. À la main, si besoin :

```sh
Scripts/check-release-binary-test.sh          # le contrôle sait-il encore échouer ?
xcodebuild -project NeonCompass.xcodeproj -scheme NeonCompass -configuration Release \
  -destination "$(Scripts/simulator-destination.sh)" build
Scripts/check-release-binary.sh
```

Le script cherche le marqueur `NCEditorArmedMarker` dans le binaire principal et dans les
exécutables des extensions sous `PlugIns/`, et échoue si l'éditeur a fui hors de `#if DEBUG`. Pas
dans `Frameworks/` : nos marqueurs ne peuvent pas s'y trouver, et un tiers qui contiendrait cette
chaîne ne produirait qu'un faux positif.

**Piège rencontré en l'écrivant, et pourquoi le script refuse une build Debug** : en Debug, Xcode 26
place le code de l'app dans `NeonCompass.debug.dylib` et laisse un binaire principal de 58 Ko
quasiment vide. Chercher le marqueur dans le seul binaire principal d'une build Debug ne trouve donc
rien — un succès parfaitement trompeur. Le script détecte ce cas et sort en erreur plutôt que de
rassurer à tort.

**Ce paragraphe affirmait une garantie qui n'existait pas, du 2026-07-27 au 2026-08-06.** Il disait :
« marqueur absent du binaire Release, présent dans le `.debug.dylib` de la build Debug — le contrôle
prouve donc quelque chose. » Le premier fait était vrai, la conclusion ne l'était pas : le contrôle
**ne pouvait pas échouer**. `grep -q` sous `pipefail` sortait au premier succès et fermait le tuyau,
le SIGPIPE reçu par `strings` devenait le statut de la pipeline, et un marqueur trouvé rendait 141 —
jamais 0. Soumis à un vrai binaire Release où le marqueur avait été délibérément mis à fuir, il
répondait « ✓ ».

Ce qui l'a rendu invisible dix jours : **le cas nominal passait**, et un contrôle qui ne sait
qu'approuver est indiscernable d'un contrôle qui approuve à raison. Le seul moyen de le voir était de
le faire échouer exprès.

État vérifié le 2026-08-06, dans les deux sens : un build Release sain est **accepté** (2 Mach-O
balayés — le binaire et l'extension widget), et un build Release où le marqueur a été mis à fuir est
**refusé**. `Scripts/check-release-binary-test.sh` retient les six cas et tourne en une seconde,
avant le build, dans le workflow.
