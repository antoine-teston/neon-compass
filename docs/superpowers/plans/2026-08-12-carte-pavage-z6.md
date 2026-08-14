# Pavage z6 de la carte de Leonida — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Servir la carte de Leonida en 18 432 px au lieu de 8 192, en remplaçant l'image unique par un socle de 4 096 px surmonté d'une pyramide de tuiles de 512 px posées à la main.

> **L'empreinte mémoire divisée par trois était le second but, et il est MORT.** Mesuré à la tâche 7 : 332 Mo au pic sur iPhone et 390 sur iPad, contre 318 avant le chantier. Ce n'est pas une fuite — `placed` fait son travail, le raster CG retombe de 103,6 à 40,7 Mo au zoom maximal — c'est la géométrie : un niveau qui vient d'être engagé est sur-résolu et couvre tout l'écran, donc le pic se trouve au MILIEU du pincement (~112 tuiles), pas au bout (~50). L'utilisateur a arbitré le 14/08 : **on accepte, la netteté partout vaut ces 14 Mo**. Aucun document, aucune PR ne doit reconduire la promesse.

**Architecture :** Le générateur `tools/basemap/gtavi-tiles.mjs` télécharge la grille z6 (79 × 79 tuiles source), l'assemble en brut sur disque, complète le brut à 20 480 px avec la couleur d'océan, puis le fait passer **par quadrants** dans la transformation existante — extraite telle quelle de `gtavi-map.mjs` — avant d'en découper deux niveaux de tuiles (9 216 / 18 432 px, révisés par la tâche 10) et un socle de 4 096 px. Côté app, une `MapTileLayerView` (sous-classe `UIView` pilotant des `CALayer` ordinaires) s'insère **sous** le `UIHostingController` des épingles, dans un conteneur commun qui devient la cible du zoom. Le choix « quel niveau, quelles tuiles » est une fonction pure testée hors interface.

**Tech Stack :** Node 22 + sharp/libvips (pipeline) ; Swift 6 strict concurrency, UIKit `CALayer` + `UIScrollView`, SwiftUI pour les épingles, Swift Testing.

## Global Constraints

- **Pas de `CATiledLayer`.** Classe de plantage iOS 26 non corrigée sous hébergement SwiftUI (`NSInternalInconsistencyException` depuis `CAImageProviderThread` via `_UIHostingView.layoutSubviews()`, thread Apple 820296). Les tuiles sont des `CALayer` ordinaires. Voir `docs/superpowers/specs/2026-08-12-carte-pavage-z6-design.md`, section « Pourquoi PAS `CATiledLayer` ».
- **Aucune mutation de l'arbre de couches hors du fil principal.** Le décodage seul part ailleurs.
- iOS/iPadOS 26+, Swift 6 strict concurrency, SwiftUI (UIKit uniquement là où il l'est déjà).
- Swift Testing (`import Testing`), jamais XCTest.
- Relancer `xcodegen generate` après toute création ou suppression de fichier source, sinon `xcodebuild` rapporte « 0 tests » au lieu d'un échec de compilation.
- `MapArt/` et `MapTiles/` sont déclarés `type: folder` : **effacer la destination avant de reconstruire**, sinon le binaire embarque les anciennes images sans un mot dans le journal.
- `-only-testing` sur UN test Swift Testing ne lance rien et rapporte `TEST SUCCEEDED`. Cibler la SUITE et lire la ligne `Test run with N tests`.
- `xcodebuild test` peut réécrire `NeonCompass/Resources/Localizable.xcstrings` : vérifier `git status` avant de commiter, restaurer plutôt qu'emporter l'artefact.
- Chaque contrôle doit être **mis en échec exprès** avant d'être cru.
- Aucune marque Rockstar dans une prose que nous écrivons ; les crédits de fond de carte restent des fentes nominatives en `Text(verbatim:)`, hors catalogue de chaînes.
- Une tâche = un commit au minimum. La branche est `feat/carte-pavage-z6`, déjà créée, basée sur `perf/carte-chargement-deux-etages`.

## Constantes partagées, décidées une fois

| Constante | Valeur | D'où elle vient |
|---|---|---|
| Côté d'une tuile | **512 px** | Mesuré : 17,0 Mo pour 100 vraies tuiles z6 en 512, contre 21 % de plus en 256 (plus d'en-têtes PNG, moins de contexte de compression). |
| Facteur z6 / z5 | **exactement 2**, même origine | Mesuré, pas supposé : quatre tuiles z6 réduites de moitié rendent leur tuile z5 à un écart moyen de 0,00–0,02 sur 255 ; la même comparaison décalée d'une tuile donne 20 à 35. La grille z6 est donc une grille de 80 × 80 dont la dernière colonne et la dernière ligne manquent. |
| Côté source retenu | **20 480 px** (`2 × 10 240`) | Le brut assemblé fait 20 224 px ; on le **complète** à 20 480 avec la couleur d'océan. La bande manquante tombe entièrement dans les bords que la passe d'effacement peint en océan de toute façon (`x ≥ 19 480`, `y ≥ 19 680`). À ce prix, toute la géométrie du pipeline z5 vaut à z6 au facteur 2 exact. |
| Recadrage | z6 = **z5 × 2** : `left 2964, top 2188, côté 17 516` | Le z5 livré recadre en `left 1482, top 1094, 8758²` — relevé en régénérant `island-vi.png`, qui ressort **identique octet pour octet**. Le doubler, plutôt que le recalculer, garantit que les coordonnées d'épingle déjà saisies désignent le même point. |
| Niveau le plus fin | **16 384 px** (`512 × 32`) | Le recadrage n'apporte que 17 516 px de détail réel : viser 20 480 interpolerait 17 % de pixels inventés. 16 384 est le multiple de 512 immédiatement en dessous, et garde le même rapport de rééchantillonnage que le z5 livré (8 758 → 8 192). |
| Niveaux de tuiles | **8 192 / 16 384** | Facteur 2 ; `16² + 32² = 1 280` tuiles par carte. Le troisième palier de la chaîne, 4 096, **est** le socle — inutile de le paver aussi. |
| Socle | **4 096 px**, image unique | Couvre à lui seul tout le repos (l'écran ne montre que ≈2 642 px au repos sur un appareil 3×) et reste dessiné en permanence sous les tuiles. |
| Grille source z6 | **79 × 79 tuiles de 256 px** = 20 224 px | Sondé sur `map.stateofleonida.net`, et le sondage arrête le générateur en cas d'écart. |
| Découpage du traitement | **4 quadrants** de 10 240 px, halo **1 024 px** | Fenêtres de 11 264 à 12 288 px, ≈2,0 Go de tampons par quadrant. Le halo couvre toutes les portées locales du pipeline : composante de libellé plafonnée à `BOX_W = 300` px z5 (600 à z6), composante de tiret ≈250 px z6, rayon de colinéarité 130 px z5 (260 à z6), remplissages de voisinage ≤ 30 px z6. |
| Zoom maximal | **2,5 → 3,3** | Aujourd'hui le zoom maximal étire déjà 8 192 px sur `2048 × 2,5 × 3 = 15 360` pixels d'appareil (×1,88). Demain : 18 432 px sur `2048 × 3,3 × 3 = 20 275` (×1,10). Zoom plus lointain **et** image plus nette au point le plus tendu. |
| Seuil d'engagement des tuiles | `displayable > 4096` | Géométrie pure, aucune constante de jugement : sous 4 096 pixels affichables le socle en a déjà plus que l'écran ne peut montrer. |
| Cache de tuiles décodées | **48 tuiles** (48 Mo) | Un jeu visible en vaut 12 à 18 ; 48 rend un aller-retour de pincement entre niveaux gratuit. |
| Tuile uniforme | écart ≤ 2/255 sur les trois canaux | 17 % des tuiles au niveau 8 192 de la carte livrée. Non écrite ; le manifeste porte sa couleur. |

**Empreinte mémoire attendue**, à contrôler en tâche 9 : socle 64 Mo + jeu visible ≈12 Mo au zoom 3,3, contre 125 Mo au repos et 318 Mo au zoom 2,5 aujourd'hui.

**Empreinte disque attendue** : le même pavage appliqué à la carte 8 192 livrée pèse 22,9 Mo (neon) et 21,3 Mo (classic), socle compris. C'est un **plancher**, pas une prévision : ces chiffres viennent d'un maître de 8 192 px agrandi, et le vrai détail z6 compresse moins bien. Tabler sur 30 à 40 Mo par habillage, soit 60 à 80 Mo pour les deux — contre 15,1 Mo aujourd'hui. La tâche 9 relève le chiffre réel ; s'il dépasse 100 Mo, ne rien décider seul, remonter.

---

## File Structure

**Pipeline (`tools/basemap/`)**

| Fichier | Responsabilité |
|---|---|
| `gtavi-tiles.mjs` *(créer)* | Générateur complet : cache de tuiles source, assemblage brut sur disque, traitement par quadrants, pyramide, socle, manifeste. |
| `gtavi-transform.mjs` *(créer)* | Les 310 lignes de traitement extraites telles quelles de `gtavi-map.mjs`, paramétrées par une fenêtre et une échelle. `gtavi-map.mjs` l'appelle pour son cas entier ; `gtavi-tiles.mjs` l'appelle quatre fois. |
| `gtavi-map.mjs` *(modifier)* | Perd les lignes 156-467 au profit d'un appel à `transform()`. Son résultat doit rester identique **octet pour octet**. |
| `gtavi-transform.test.mjs` *(créer)* | Prouve que le découpage en quadrants avec halo rend la même image que le traitement d'un bloc. |
| `reduce-mapart.mjs` *(supprimer)* | Sa raison d'être — l'étage réduit — disparaît. |
| `SOURCES.md` *(modifier)* | Consigner la grille z6, le nouveau pipeline, et le moment de contacter l'auteur. |
| `package.json` *(modifier)* | Ajouter le nouveau test à `npm test`. |
| `.gitignore` *(créer)* | Ignorer `.cache/`. |

**App (`NeonCompass/Core/Map/`)**

| Fichier | Responsabilité |
|---|---|
| `MapTileManifest.swift` *(créer)* | Décrit la pyramide d'une carte : côté de tuile, niveaux, tuiles uniformes et leur couleur. Chargement depuis le paquet. |
| `MapTileSet.swift` *(créer)* | **Fonction pure** : quel niveau pour quelle échelle, quelles tuiles pour quel rectangle. Aucune dépendance UIKit. |
| `MapTileLayerView.swift` *(créer)* | `UIView` qui pose, réutilise et retire des `CALayer`. Décodage hors fil principal, mutation sur le fil principal. |
| `MapArtLoader.swift` *(modifier)* | Perd `MapArtDetail`, `MapArtDetailSelector` et le repli `-reduced`. Se réduit à « décoder le socle, hors du fil principal ». |
| `MapScrollView.swift` *(modifier)* | Conteneur commun, `viewForZooming`, transmission du viewport à la couche de tuiles, `maximumZoomScale = 3.3`. |

**Tests (`NeonCompassTests/Map/`)**

| Fichier | Responsabilité |
|---|---|
| `MapTileSetTests.swift` *(créer)* | Le cœur logique : niveau par échelle, fenêtre de tuiles, bords. |
| `MapTileResourcesTests.swift` *(créer)* | Intégrité du pavage livré : comptes, trous, définitions, cohérence du manifeste. |
| `MapArtResourcesTests.swift` *(modifier)* | Perd le contrôle de l'étage réduit, gagne celui du socle à 4 096 px. |
| `MapArtDetailTests.swift` *(supprimer)* | Son sujet disparaît. |

**Ressources**

- `NeonCompass/Resources/MapArt/island-vi.png`, `island-vi-classic.png` : passent de 8 192 à **4 096 px** (le socle).
- `NeonCompass/Resources/MapArt/island-vi-reduced.png`, `island-vi-classic-reduced.png` : **supprimés**.
- `NeonCompass/Resources/MapTiles/<nom>/<côté>/<x>_<y>.png` + `NeonCompass/Resources/MapTiles/<nom>.json` : **créés**.
- `project.yml` : ajouter `NeonCompass/Resources/MapTiles` en `type: folder`, et l'exclure du groupe `NeonCompass`.

---

## Task 1 : Cache de tuiles source z6 et assemblage brut sur disque

Le générateur actuel tient tout en mémoire : à z6 cela ferait trois tampons de 1,2 Go. On casse la chaîne en deux artefacts sur disque, tous deux reprenables.

**Files:**
- Create: `tools/basemap/gtavi-tiles.mjs`
- Create: `tools/basemap/.gitignore`

**Interfaces:**
- Consumes: rien.
- Produces: `tools/basemap/.cache/z6/<x>_<y>.png` (6 241 fichiers) et `tools/basemap/.cache/stitched-<style>.raw` (20 224 × 20 224 × 3 octets, RGB brut, sans en-tête). Le module exporte `SOURCE = { tile: 256, grid: 79, side: 20224 }` et `stitchedPath(style)`.

- [ ] **Step 1 : Sonder la grille z6 et l'écrire dans le plan de vol**

Créer `tools/basemap/gtavi-tiles.mjs` avec l'en-tête, les constantes et le sondage. Le sondage n'est pas décoratif : si le serveur change de grille, tout le reste est faux, et on veut l'apprendre en dix secondes plutôt qu'après 190 Mo de téléchargement.

```js
#!/usr/bin/env node
// Pavage haute définition de la carte communautaire de Leonida (YANIS v14).
//
// Produit, pour chaque habillage :
//   - un SOCLE de 4 096 px, image unique, dessinée en permanence ;
//   - trois niveaux de tuiles de 512 px (5 120 / 10 240 / 20 480 px) ;
//   - un manifeste décrivant les niveaux et les tuiles uniformes omises.
//
//   node tools/basemap/gtavi-tiles.mjs [--style normal] [--classic]
//
// Les deux étapes coûteuses — le téléchargement et l'assemblage — sont
// reprenables : elles sautent ce qui est déjà sur disque. C'est nécessaire et
// pas confortable : `fetch` tire 6 241 tuiles, et une coupure réseau au bout de
// 6 000 ne doit pas tout perdre. Le découpage, lui, repart de zéro — il ne
// coûte que du calcul local.

import { mkdirSync, writeFileSync, readFileSync, existsSync, statSync, openSync, readSync, writeSync, closeSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..', '..');
const CACHE = join(HERE, '.cache');

const TILE_BASE = 'https://map.stateofleonida.net/tiles';
const MAP_AUTHOR = 'YANIS';
const MAP_VERSION = 'v14';
const ZOOM = 6;
const SRC_TILE = 256;

export const SOURCE = { tile: SRC_TILE, grid: 79, side: 79 * SRC_TILE };

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i === -1 ? fallback : process.argv[i + 1];
}
const style = arg('style', 'normal');
const only = arg('only', null);

export const stitchedPath = (s) => join(CACHE, `stitched-${s}.raw`);

const tileURL = (x, y) => `${TILE_BASE}/${MAP_AUTHOR}/${MAP_VERSION}/${style}/${ZOOM}/${x}/${y}.png`;

/// Le grid YANIS ne vaut pas 2^z — on le sonde, comme gtavi-map.mjs le fait
/// déjà à z5. Un écart avec SOURCE.grid arrête tout : les côtés de niveaux, le
/// nombre de tuiles et le manifeste en découlent tous.
async function probeGrid() {
  const base = `${TILE_BASE}/${MAP_AUTHOR}/${MAP_VERSION}/${style}/${ZOOM}`;
  const mid = Math.floor(2 ** ZOOM / 2);
  async function maxCoord(axis) {
    let hi = 2 ** ZOOM - 1;
    for (let c = hi + 1; c < hi + 24; c++) {
      const url = axis === 'x' ? `${base}/${c}/${mid}.png` : `${base}/${mid}/${c}.png`;
      try { const r = await fetch(url, { method: 'HEAD' }); if (!r.ok) break; hi = c; } catch { break; }
    }
    return hi + 1;
  }
  const [gx, gy] = await Promise.all([maxCoord('x'), maxCoord('y')]);
  return { gx, gy };
}
```

- [ ] **Step 2 : Vérifier le sondage en vrai**

Run: `node -e "import('./tools/basemap/gtavi-tiles.mjs')" ` ne suffit pas (le module n'exécute rien encore). Ajouter temporairement en fin de fichier :

```js
console.log(await probeGrid());
```

Run: `node tools/basemap/gtavi-tiles.mjs`
Expected: `{ gx: 79, gy: 79 }`. Si les valeurs diffèrent, **arrêter et le signaler** : `SOURCE.grid` et tous les côtés de niveaux en dépendent. Retirer la ligne temporaire ensuite.

- [ ] **Step 3 : Le téléchargement reprenable**

Ajouter à `gtavi-tiles.mjs` :

```js
async function fetchRetry(url, { tries = 4 } = {}) {
  let lastErr;
  for (let i = 0; i < tries; i++) {
    try {
      const r = await fetch(url);
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      return Buffer.from(await r.arrayBuffer());
    } catch (e) {
      lastErr = e;
      await new Promise((r) => setTimeout(r, 250 * 2 ** i));
    }
  }
  throw new Error(`${url}: ${lastErr.message}`);
}

async function pool(jobs, limit, onDone) {
  const results = new Array(jobs.length);
  let next = 0, done = 0;
  await Promise.all(
    Array.from({ length: Math.min(limit, jobs.length) }, async () => {
      while (next < jobs.length) {
        const i = next++;
        results[i] = await jobs[i]();
        onDone?.(++done, jobs.length);
      }
    })
  );
  return results;
}

/// Une tuile absente n'est PAS une erreur : le serveur ne sert pas les carrés
/// d'océan pur en bordure de grille. Elle est marquée manquante et le collage
/// y laissera la couleur d'océan, exactement comme gtavi-map.mjs à z5.
async function fetchAll() {
  const dir = join(CACHE, `z${ZOOM}-${style}`);
  mkdirSync(dir, { recursive: true });
  const jobs = [];
  for (let y = 0; y < SOURCE.grid; y++) {
    for (let x = 0; x < SOURCE.grid; x++) {
      jobs.push(async () => {
        const path = join(dir, `${x}_${y}.png`);
        if (existsSync(path) && statSync(path).size > 0) return true;
        try {
          writeFileSync(path, await fetchRetry(tileURL(x, y)));
          return true;
        } catch {
          writeFileSync(path, Buffer.alloc(0));   // marqueur d'absence, reprenable
          return false;
        }
      });
    }
  }
  const ok = await pool(jobs, 12, (d, t) => {
    if (d % 100 === 0 || d === t) process.stdout.write(`\r  ${d}/${t} tuiles`);
  });
  console.log(`\n  ${ok.filter(Boolean).length}/${jobs.length} tuiles présentes`);
  return dir;
}
```

- [ ] **Step 4 : Lancer le téléchargement et le mesurer**

Ajouter temporairement en fin de fichier `console.log(await fetchAll());`, puis :

Run: `time node tools/basemap/gtavi-tiles.mjs --style normal`
Expected: `6241/6241 tuiles` ou un compte légèrement inférieur (tuiles d'océan de bordure absentes). Noter le poids : `du -sh tools/basemap/.cache/z6-normal`. Attendu de l'ordre de 150–250 Mo.

Relancer la même commande : elle doit se terminer en quelques secondes sans un octet réseau — c'est la reprise, et c'est ce qu'on vérifie.

- [ ] **Step 5 : Ignorer le cache dans git**

Créer `tools/basemap/.gitignore` :

```gitignore
# Artefacts du pavage : 6 241 tuiles source et deux images brutes de 1,2 Go.
# Reproductibles par `node gtavi-tiles.mjs`, jamais versionnés.
.cache/
```

Run: `git status --short tools/basemap`
Expected: aucun fichier de `.cache/` listé.

- [ ] **Step 6 : L'assemblage brut, bande de tuiles par bande de tuiles**

L'image assemblée fait 1,23 Go : elle ne tient pas dans un tampon confortable, et sharp n'a pas besoin qu'elle y tienne. On écrit une rangée de tuiles à la fois — 20 224 × 256 × 3 = 15,5 Mo en mémoire.

```js
/// Couleur d'océan, échantillonnée au centre de la tuile (0,0) — toujours de
/// l'eau. Sert de fond partout où une tuile manque, comme à z5.
async function oceanColor(dir) {
  const corner = join(dir, '0_0.png');
  if (!existsSync(corner) || statSync(corner).size === 0) throw new Error('tuile 0_0 absente : impossible d’échantillonner l’océan');
  const px = await sharp(corner).extract({ left: 100, top: 100, width: 1, height: 1 }).raw().toBuffer();
  return { r: px[0], g: px[1], b: px[2] };
}

/// Assemble en RGB brut sur disque. Aucun PNG intermédiaire : encoder puis
/// redécoder 1,2 Go ne servirait qu'à passer deux fois par zlib.
async function stitch(dir) {
  const out = stitchedPath(style);
  const expected = SOURCE.side * SOURCE.side * 3;
  if (existsSync(out) && statSync(out).size === expected) {
    console.log(`  ${out} déjà assemblé (${(expected / 2 ** 30).toFixed(2)} Gio)`);
    return out;
  }
  const ocean = await oceanColor(dir);
  const fd = openSync(out, 'w');
  for (let ty = 0; ty < SOURCE.grid; ty++) {
    const composite = [];
    for (let tx = 0; tx < SOURCE.grid; tx++) {
      const p = join(dir, `${tx}_${ty}.png`);
      if (existsSync(p) && statSync(p).size > 0) composite.push({ input: p, left: tx * SRC_TILE, top: 0 });
    }
    const strip = await sharp({
      create: { width: SOURCE.side, height: SRC_TILE, channels: 3, background: ocean },
    }).composite(composite).raw().toBuffer();
    writeSync(fd, strip);
    process.stdout.write(`\r  bande ${ty + 1}/${SOURCE.grid}`);
  }
  closeSync(fd);
  console.log(`\n  ${out}  ${(statSync(out).size / 2 ** 30).toFixed(2)} Gio`);
  return out;
}
```

- [ ] **Step 7 : Lancer l'assemblage et contrôler sa taille au coin près**

Remplacer la ligne temporaire par :

```js
const dir = await fetchAll();
await stitch(dir);
```

Run: `time node tools/basemap/gtavi-tiles.mjs --style normal`
Expected: le fichier fait **exactement** `20224 × 20224 × 3 = 1 227 030 528` octets. Vérifier :

Run: `stat -f %z tools/basemap/.cache/stitched-normal.raw`
Expected: `1227030528`

Contrôle visuel — extraire une vignette du brut et la regarder :

```sh
node -e "
import('sharp').then(async ({default: sharp}) => {
  const S = 20224;
  await sharp('tools/basemap/.cache/stitched-normal.raw', { raw: { width: S, height: S, channels: 3 } })
    .resize(1024, 1024).png().toFile('/tmp/stitched-check.png');
  console.log('ok');
});"
```

Expected: `/tmp/stitched-check.png` montre l'île entière, sans décalage ni bande noire. **Un décalage d'une rangée de tuiles se voit immédiatement ici et nulle part plus tard.**

- [ ] **Step 8 : Commit**

```bash
git add tools/basemap/gtavi-tiles.mjs tools/basemap/.gitignore
git commit -m "feat(basemap): télécharger et assembler la grille z6 hors mémoire

6 241 tuiles source mises en cache et reprenables, assemblées en RGB brut sur
disque bande par bande — 15,5 Mo en mémoire au lieu de 1,2 Go.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 2 : Extraire la transformation, et prouver le découpage en quadrants à z5

**Ce que la première rédaction de ce plan avait manqué**, et qui gouverne cette tâche : `restyle()` n'est pas la transformation de la carte, c'en est la dernière étape. `gtavi-map.mjs` fait 310 lignes de traitement sur le brut *avant* de l'appeler — effacement du panneau de légende, suppression des limites de comté en tirets, effacement de la grille de coordonnées — puis l'aplatissement d'océan après. Sauter tout cela aurait donné une carte où le panneau blanc nourrit la classification et fait exploser la boîte englobante du recadrage.

La tâche ne réécrit pas ce traitement. Elle l'**extrait** tel quel dans un module qui prend une fenêtre et sa géométrie globale, puis prouve deux choses : que l'extraction n'a rien changé, et que découper l'image en quadrants avec halo rend la même image que la traiter d'un bloc.

Trois faits mesurés fixent le cadre. Ils ne sont pas à redécouvrir.

1. **z6 est exactement le double de z5, sur la même origine.** Quatre tuiles z6 réduites de moitié rendent leur tuile z5 à un écart moyen de 0,00 à 0,02 sur 255 ; la même comparaison décalée d'une tuile donne 20 à 35. Le facteur d'échelle vaut donc **2**, pas 1,975 : la grille de 79 tuiles est une grille de 80 amputée de sa dernière colonne et de sa dernière ligne.
2. **Le z5 livré est reproductible octet pour octet.** `node tools/basemap/gtavi-map.mjs --restyle --classic --out <ailleurs>` régénère `island-vi.png` et `island-vi-classic.png` identiques à ceux du dépôt. C'est la référence de non-régression, et elle est vérifiée, pas supposée.
3. **Une seule passe est couplée globalement** : le sondage de la grille de coordonnées somme des colonnes et des lignes entières. Elle est traitée à part, par un cumul entre quadrants. Tout le reste est local et tient dans un halo.

**Files:**
- Create: `tools/basemap/gtavi-transform.mjs`
- Create: `tools/basemap/gtavi-transform.test.mjs`
- Modify: `tools/basemap/gtavi-map.mjs:156-467`
- Modify: `tools/basemap/gtavi-restyle.mjs` (paramétrer les constantes d'échelle)
- Modify: `tools/basemap/package.json` (ajouter le test à `npm test`)

**Interfaces:**
- Consumes : `restyle()` de `gtavi-restyle.mjs`, dont la signature gagne trois derniers paramètres — `scale`, `frame`, `count` (détaillés au Step 3).
- Produces :

```js
export const REF = 10240;   // La largeur du z5. Toutes les constantes du
                            // pipeline sont exprimées à cette échelle, et à
                            // cette échelle le facteur vaut 1 — ce qui rend la
                            // non-régression exacte par construction.
                            //
                            // INVARIANT : full.w doit être un MULTIPLE ENTIER de
                            // REF. scale = full.w / REF n'est pas une
                            // approximation tolérante : à 1,975 (ce que
                            // donnerait le brut 20 224 de la tâche 1 au lieu
                            // du 20 480 complété), E_PANEL tombe à 5 925 et une
                            // bande de 75 px de légende SURVIT à l'effacement,
                            // pour nourrir ensuite le classificateur.
                            // Chaque entrée du module l'affirme, plutôt que de
                            // laisser l'appelant s'en souvenir.

/// Phase A : effacer la légende, puis supprimer les tirets de limite de comté.
/// Purement locale à la fenêtre. Écrit le résultat dans `rgb` SUR PLACE.
/// @param {Buffer} rgb    RGB de la fenêtre, win.w × win.h × 3 — MUTÉ
/// @param {{x,y,w,h}} win position et taille de la fenêtre dans l'image globale
/// @param {{w,h}} full    géométrie de RÉFÉRENCE, multiple exact de REF
/// @param {{r,g,b}} ocean couleur d'effacement, échantillonnée sur la source
/// @param {{x,y,w,h}} core  la part de la fenêtre dont les COMPTEURS comptent,
///        en coordonnées globales. Le traitement porte sur toute la fenêtre.
/// @param {Buffer|null} erasedOut  si fourni, reçoit une copie de la fenêtre
///        prise APRÈS l'effacement de légende et AVANT la suppression des
///        tirets — c'est exactement l'état dont la version classic est faite.
/// @returns {{erased, dashCompsInWindow, dashTotal, dashSuppressed}}
export function eraseAndDash(rgb, win, full, ocean, core, erasedOut = null)

/// Contribution de la fenêtre au sondage de la grille de coordonnées. Ne scanne
/// que le CŒUR, sinon les halos comptent deux fois.
/// @returns {{colHits: Uint32Array(full.w), rowHits: Uint32Array(full.h)}}
export function gridProbe(rgb, win, full, core)

/// Les centres de traits, depuis les contributions sommées. Global.
/// @returns {{colCenter: Int32Array(full.w), rowCenter: Int32Array(full.h), nCols, nRows}}
export function gridCenters(colHits, rowHits, full)

/// Phase B : effacer la grille, restyler, aplatir l'océan profond. Locale à la
/// fenêtre, mais lit les centres GLOBAUX. Mute `rgb` sur place.
/// @param {{colCenter, rowCenter}} centers  le résultat de gridCenters
/// @param {{x,y,w,h}} core  la région à rendre, en coordonnées globales
/// @returns onze champs : data, ocean, bbox, stats, gridTotal, gridSuppressed,
///   flattened, labelUnified, gridErased, oceanCleaned, colorsInWindow
///   data  : RGB restylé du CŒUR seul, core.w × core.h × 3
///   ocean : Uint8Array(core.w × core.h), 1 si le pixel est de l'eau
///   bbox  : {minX, maxX, minY, maxY} des pixels non-océan du cœur, en
///           coordonnées GLOBALES, ou null si le cœur est tout océan
///   tous les compteurs sont bornés au CŒUR — c'est ce qui rend leur somme
///   sur quatre quadrants égale au traitement d'un bloc
export function gridAndStyle(rgb, win, full, core, centers)
```

**Ce bloc est le contrat réel du module livré, pas une esquisse** — la tâche 3 code contre lui. Deux pièges qu'il porte et qu'on ne devine pas : `core` n'a **pas** de valeur par défaut (le confondre avec un autre argument rendrait des compteurs nuls sans rien signaler, donc le module refuse bruyamment), et les deux phases **mutent `rgb` sur place** — c'est à l'appelant de décider où prendre ses copies.

**La version classic ne passe par aucune des deux phases.** C'est la source plus l'effacement de légende, un point c'est tout — ni tirets, ni grille, ni restylage. D'où le paramètre `erasedOut` : le seul point du pipeline où cet état existe est *à l'intérieur* de `eraseAndDash`, entre ses deux moitiés. Le prélever après coup donne un PNG de 5 220 Ko au lieu de 5 389 Ko, et c'est ainsi qu'on l'a appris.

- [ ] **Step 1 : Écrire le test du découpage, avant toute extraction**

Créer `tools/basemap/gtavi-transform.test.mjs`. Le test tourne sur une image d'épreuve réduite : il valide la **mécanique de fenêtrage**, pas le rendu. Le rendu, c'est la régénération du z5 réel qui le prouve, au Step 6.

```js
// Découper une image en quadrants avec halo et ne garder que les cœurs doit
// rendre la même image que la traiter d'un bloc. Ce n'est pas exact pour la
// passe de tirets — la confirmation par colinéarité se propage de proche en
// proche sur toute la longueur d'une limite de comté, sans borne — donc on
// MESURE l'écart au lieu de le postuler, et le plafond est dans le test.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { eraseAndDash, gridProbe, gridCenters, gridAndStyle, REF } from './gtavi-transform.mjs';

const W = 2048, H = 2048;
const FULL = { w: W, h: H };
const WHOLE = { x: 0, y: 0, w: W, h: H };
const OCEAN = { r: 44, g: 103, b: 164 };

/// Image d'épreuve. Elle contient ce qui casse un découpage naïf : un panneau
/// de légende à gauche, une LIGNE DE TIRETS traversant tout le cadre (la seule
/// figure globalement couplée), une ligne de grille assombrissant l'océan, et
/// un libellé à cheval sur la coupure horizontale.
function fixture() {
  const d = Buffer.alloc(W * H * 3);
  const put = (x, y, r, g, b) => {
    if (x < 0 || y < 0 || x >= W || y >= H) return;
    const o = (y * W + x) * 3; d[o] = r; d[o + 1] = g; d[o + 2] = b;
  };
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    if (x < 900) put(x, y, 44, 103, 164);            // océan pur, à l'ouest
    else put(x, y, 190, 180, 150);                    // terre
  }
  for (let y = 0; y < H; y++) for (let x = 0; x < 400; x++) put(x, y, 252, 252, 252); // panneau
  for (let y = 0; y < H; y++) for (let x = 700; x < 703; x++) put(x, y, 47, 95, 141); // grille sur océan
  // Tirets roses de 40 px espacés de 30, sur toute la hauteur : la limite de comté.
  for (let seg = 0; seg * 70 < H; seg++) {
    for (let y = seg * 70; y < seg * 70 + 40 && y < H; y++) {
      for (let x = 1200; x < 1206; x++) put(x, y, 238, 100, 100);
    }
  }
  // Libellé gris, centré sur la coupure y = 1024.
  for (let y = 1014; y < 1034; y++) for (let x = 1400; x < 1560; x++) {
    if ((x * 7 + y * 3) % 5 === 0) put(x, y, 208, 208, 210);
  }
  return d;
}

/// Le traitement complet d'une découpe donnée. `cores` liste les cœurs ;
/// un seul cœur couvrant tout, c'est le traitement d'un bloc.
function run(cores, halo) {
  const src = fixture();
  const win = (core) => {
    const x = Math.max(0, core.x - halo), y = Math.max(0, core.y - halo);
    return {
      x, y,
      w: Math.min(W, core.x + core.w + halo) - x,
      h: Math.min(H, core.y + core.h + halo) - y,
    };
  };
  const cut = (buf, wn) => {
    const out = Buffer.allocUnsafe(wn.w * wn.h * 3);
    for (let y = 0; y < wn.h; y++) {
      buf.copy(out, y * wn.w * 3, ((wn.y + y) * W + wn.x) * 3, ((wn.y + y) * W + wn.x + wn.w) * 3);
    }
    return out;
  };

  // Phase A sur chaque fenêtre ; on recolle les cœurs dans un intermédiaire.
  const mid = Buffer.alloc(W * H * 3);
  const colHits = new Uint32Array(W), rowHits = new Uint32Array(H);
  for (const core of cores) {
    const wn = win(core);
    const buf = cut(src, wn);
    eraseAndDash(buf, wn, FULL, OCEAN);
    const p = gridProbe(buf, wn, FULL, core);
    for (let i = 0; i < W; i++) colHits[i] += p.colHits[i];
    for (let i = 0; i < H; i++) rowHits[i] += p.rowHits[i];
    for (let y = 0; y < core.h; y++) {
      buf.copy(mid, ((core.y + y) * W + core.x) * 3,
               ((core.y - wn.y + y) * wn.w + (core.x - wn.x)) * 3,
               ((core.y - wn.y + y) * wn.w + (core.x - wn.x) + core.w) * 3);
    }
  }
  const centers = gridCenters(colHits, rowHits, FULL);

  // Phase B sur chaque fenêtre de l'intermédiaire.
  const out = Buffer.alloc(W * H * 3);
  for (const core of cores) {
    const wn = win(core);
    const r = gridAndStyle(cut(mid, wn), wn, FULL, core, centers);
    for (let y = 0; y < core.h; y++) {
      r.data.copy(out, ((core.y + y) * W + core.x) * 3, y * core.w * 3, (y + 1) * core.w * 3);
    }
  }
  return out;
}

const QUADRANTS = [
  { x: 0, y: 0, w: 1024, h: 1024 }, { x: 1024, y: 0, w: 1024, h: 1024 },
  { x: 0, y: 1024, w: 1024, h: 1024 }, { x: 1024, y: 1024, w: 1024, h: 1024 },
];

test('la référence d’échelle est le z5', () => {
  assert.equal(REF, 10240);
});

test('quatre quadrants avec halo rendent la même image qu’un bloc', () => {
  const whole = run([WHOLE], 0);
  const split = run(QUADRANTS, 256);
  let diff = 0, firstAt = -1;
  for (let i = 0; i < whole.length; i++) {
    if (whole[i] !== split[i]) { diff++; if (firstAt < 0) firstAt = i; }
  }
  const ratio = diff / whole.length;
  assert.ok(ratio <= 0.0002,
    `${diff} octets diffèrent (${(ratio * 100).toFixed(4)} %), premier en ` +
    `x=${(firstAt / 3 | 0) % W}, y=${(firstAt / 3 / W) | 0} — plafond 0,02 %`);
});

test('un halo nul, lui, casse la couture — le contrôle sait échouer', () => {
  const whole = run([WHOLE], 0);
  const naive = run(QUADRANTS, 0);
  let diff = 0;
  for (let i = 0; i < whole.length; i++) if (whole[i] !== naive[i]) diff++;
  assert.ok(diff / whole.length > 0.0002,
    `sans halo l’écart devrait dépasser le plafond, il vaut ${(100 * diff / whole.length).toFixed(4)} %`);
});
```

Le troisième test est le plus important des trois : il prouve que le deuxième sait échouer. Un contrôle de couture qui passerait aussi bien avec halo que sans ne contrôlerait rien.

- [ ] **Step 2 : Vérifier que le test échoue, faute de module**

```sh
cd tools/basemap && node --test gtavi-transform.test.mjs
```

Expected: `Cannot find module './gtavi-transform.mjs'`.

- [ ] **Step 3 : Déplacer le traitement dans `gtavi-transform.mjs`**

Créer le module et y **déplacer sans les réécrire** les blocs de `gtavi-map.mjs` :

| Bloc de `gtavi-map.mjs` | Destination |
|---|---|
| Effacement de la légende (4 boucles, du commentaire « Effacer le panneau de légende » à `console.log('  légende : …')`) | `eraseAndDash`, première moitié |
| Tirets de comté (de `const isWarm = …` à `console.log('  comtés : …')`) | `eraseAndDash`, seconde moitié |
| Sondage de grille (de `const dPure = …` à `console.log('  grille : … détectées sur l'océan')`) | `gridProbe` + `gridCenters` |
| Effacement de la grille (de `const isGridPx = …` à `console.log('  grille : … → voisin')`) | `gridAndStyle`, première partie |
| `restyle()` puis l'aplatissement d'océan (jusqu'à `console.log('  océan aplati : …')`) | `gridAndStyle`, seconde partie |

Les `console.log` ne partent pas dans le module : chaque fonction rend ses compteurs, et `gtavi-map.mjs` les journalise comme avant, au mot près.

Trois adaptations, et trois seulement.

**(a) Coordonnées globales.** Dans le code déplacé, `W` et `H` désignent la **fenêtre** (`win.w`, `win.h`) : l'indexation du tampon ne change pas. Tout test *de position* passe en coordonnées globales, `gx = win.x + x` et `gy = win.y + y`. Les quatre régions d'effacement se réduisent à un seul prédicat — leur union, qui leur est rigoureusement équivalente puisque la première couvre déjà `x < 3000` pour tout `y` :

```js
const inLegend = (gx, gy) =>
  gx < E_PANEL || gy < E_BAND || gy >= full.h - E_BAND || gx >= full.w - E_RIGHT;
```

Contrôle immédiat et suffisant : à z5, sur l'image entière, le compteur `erased` doit valoir **41 232 000**, la valeur que le générateur actuel journalise.

**(b) Échelle.** Toute constante géométrique devient une expression de `scale = full.w / REF`. À z5 `scale` vaut 1 et rien ne bouge ; à z6 il vaut 2. Trois régimes, à ne pas confondre :

| Régime | Facteur | Constantes concernées |
|---|---|---|
| Longueurs, distances, épaisseurs | `× scale` | effacement `3000`, `400`, `500` ; bornes de balayage des tirets `3005` et `3` ; épaisseur de tiret `12` ; rayon de colinéarité `130` ; tolérance perpendiculaire `9` ; halo de tiret `±2` ; portée de remplissage `d <= 15` et `bestDist = 20` (tirets **et** grille) ; fenêtres de sondage `PY0 = 420`, `PY1 = 980`, `PX0 = 3005`, `PX1 = 3400`, et les marges `505` et `405` ; étalement des centres `±5` ; décalage des références bilatérales `±8` ; dans `gtavi-restyle.mjs`, `BOX_W = 300` et les hauteurs de boîte `60` / `130` |
| Aires | `× scale²` | aire de tiret `30` et `1500`, plafond `comp.length <= 1500` ; dans `gtavi-restyle.mjs`, `AREA_MIN = 12` et `AREA_MAX = 12000` |
| Comptes le long d'un périmètre | `× scale` | dans `gtavi-restyle.mjs`, `roadTouch > 3` |
| Voisinages | rayon `× scale`, seuil **dérivé du rayon** | dans `gtavi-restyle.mjs`, les sondes de la passe « lignes de grille fines » (`±2` de part et d'autre, et la marge `y = 2 ; y < height - 2` de la boucle) et celles du nettoyage d'océan (coins `±2`, boucle 5×5) partagent un même rayon `R = Math.max(1, Math.round(2 * scale))`. Le `w < 20` du nettoyage n'est **pas** une longueur : c'est 80 % des 25 cellules du voisinage, donc `OCEAN_MIN = Math.round(0.8 * (2 * R + 1) ** 2)`, qui retombe sur 20 exactement à `scale = 1` |
| Rapports et seuils de couleur | **inchangés** | `l2 / l1 > 0.25` ; `≥ 0.9` de colinéarité ; `0.62` de remplissage ; `0.4` du sondage ; le `12` de `Math.sqrt(12 * l2)`, qui est le facteur variance-vers-largeur d'une loi uniforme et non une longueur ; tous les seuils RGB, y compris `≤ 30` d'accord bilatéral, `≥ -12` par canal et `20..150` de somme |

Arrondir avec `Math.round`, une fois, à la définition de la constante — jamais dans une boucle.

**Ce tableau ne suffit pas** : `restyle` contient aussi deux fractions de l'image *globale* — `x >= width * 0.82` et `y >= height * 0.79`, qui situent la rose des vents. Une fenêtre ne connaît pas ces bornes. Elles ne se mettent donc pas à l'échelle : elles se rapportent au cadre global, ce qui impose un paramètre de plus (voir juste après).

**(c) Le cœur.** `gridAndStyle` calcule sur toute la fenêtre puis ne recopie que `core` dans son `data` de sortie. `eraseAndDash` écrit sur place et laisse l'appelant prélever le cœur.

Dans `gtavi-restyle.mjs`, `restyle(data, width, height)` devient :

```js
export function restyle(
  data, width, height,
  scale = 1,
  frame = { x: 0, y: 0, w: width, h: height },   // position du tampon dans l'image globale
  count = { x: 0, y: 0, w: width, h: height },   // sous-rectangle compté, en coordonnées du tampon
)
```

Trois paramètres, trois rôles distincts qu'il ne faut pas confondre. `scale` mène le tableau ci-dessus. `frame` porte les deux fractions globales de la rose des vents : `frame.w * 0.82` et `frame.h * 0.79` donnent la borne en coordonnées globales, dont on retranche `frame.x` / `frame.y` pour revenir dans le tampon. `count` restreint les **compteurs** rendus — pas le calcul, qui a besoin de tout le halo — au cœur du quadrant ; sans lui, les statistiques de quatre quadrants comptent quatre fois les recouvrements et le contrôle de Task 3 ne veut plus rien dire.

Les trois valeurs par défaut ne sont pas des facilités : elles sont ce qui garantit qu'un appel existant se comporte exactement comme avant, aux octets et au journal près.

- [ ] **Step 4 : Rebrancher `gtavi-map.mjs` sur le module**

Remplacer les lignes 156-467 par l'enchaînement, cas dégénéré du découpage — une fenêtre qui est l'image entière, un cœur qui est l'image entière :

```js
const full = { w: info.width, h: info.height };
const whole = { x: 0, y: 0, w: full.w, h: full.h };
const classicRgb = flag('classic') ? Buffer.allocUnsafe(rawRgb.length) : null;

let image;
if (doRestyle) {
  // La classic reprend l'effacement (couleur océan réelle) mais pas le reste :
  // la grille de coordonnées fait partie de la source qu'elle restitue. Cet
  // état n'existe qu'À L'INTÉRIEUR de eraseAndDash, d'où le tampon de sortie.
  const a = eraseAndDash(rawRgb, whole, full, ocean, whole, classicRgb);
  console.log(`  légende : ${a.erased} pixels → océan`);
  console.log(`  comtés : ${a.dashCompsInWindow} tirets alignés, ${a.dashSuppressed} px → voisin`);

  const probe = gridProbe(rawRgb, whole, full, whole);
  const centers = gridCenters(probe.colHits, probe.rowHits, full);
  console.log(`  grille : ${centers.nCols} colonnes + ${centers.nRows} lignes détectées sur l'océan`);

  const styled = gridAndStyle(rawRgb, whole, full, whole, centers);
  console.log(`  grille : ${styled.gridTotal} détectés, ${styled.gridSuppressed} → voisin`);
  console.log(`  restylage Neon Compass — ${styled.stats}`);
  console.log(`  océan aplati : ${styled.flattened} pixels → NIGHT_SKY exact (gradient préservé)`);
  // …le recadrage et l'encodage restent où ils sont, inchangés.
```

Attention à l'ordre, et c'est **la** subtilité de cette étape : dans le code d'origine, `classicRgb.set(rawRgb)` intervient **entre** l'effacement et les tirets, alors que `eraseAndDash` fait les deux d'affilée. La première rédaction de ce plan affirmait que ce n'était pas un problème, au motif que la suppression des tirets ne touche que des pixels roses posés sur la terre. C'était faux : prendre la copie après coup donne `island-vi-classic.png` à 5 220 Ko au lieu de 5 389 Ko. D'où le tampon `erasedOut` ci-dessus — le seul instant où cet état existe est à l'intérieur de la fonction. Le contrôle du Step 6 le tranche, puisqu'il compare le fichier octet pour octet.

- [ ] **Step 5 : Lancer le test du découpage**

```sh
cd tools/basemap && node --test gtavi-transform.test.mjs
```

Expected: les trois tests passent. Relever le pourcentage d'écart annoncé par le deuxième et le noter dans le rapport — c'est la mesure du couplage résiduel des tirets, et la tâche 3 s'y réfère.

- [ ] **Step 6 : Le contrôle qui compte — régénérer le z5 et comparer octet pour octet**

```sh
cd /Users/antoine/gta_project
rm -rf /tmp/z5-check && mkdir -p /tmp/z5-check
node tools/basemap/gtavi-map.mjs --restyle --classic --out /tmp/z5-check
for f in island-vi.png island-vi-classic.png; do
  cmp /tmp/z5-check/$f NeonCompass/Resources/MapArt/$f && echo "$f : IDENTIQUE" || echo "$f : DIFFÉRENT"
done
```

Expected: **les deux fichiers identiques**, et le journal reprenant mot pour mot les valeurs de référence :

```
  légende : 41232000 pixels → océan
  comtés : 193 tirets alignés, 51596 px → voisin
  grille : 52 colonnes + 76 lignes détectées sur l'océan
  grille : 1019749 détectés, 1019609 → voisin
  restylage Neon Compass — eau 75.5%  bâti 18.7%  sable 2.7%  rues 1.2%  terre 0.7%  axes 0.6%  libellés 0.4%  sombre 0.1%
  océan aplati : 17677 pixels → NIGHT_SKY exact (gradient préservé)
  île : x=3440..9645 y=1174..9771 → crop 8758×8758 (océan ouest 1958px / est 594px)
```

Un seul compteur qui bouge signale une constante mal transposée, et le nom du compteur désigne la passe. Ne pas passer à la suite avant que les sept lignes concordent.

- [ ] **Step 7 : Prouver que ce contrôle-là aussi sait échouer**

Changer une constante d'échelle au hasard — par exemple `E_RIGHT` de `500` à `520` —, relancer le Step 6, vérifier que `island-vi.png` ressort **DIFFÉRENT**, puis remettre `500`. Consigner les deux sorties dans le rapport. Une comparaison d'images qui ne saurait qu'approuver ne vaut rien.

- [ ] **Step 8 : Ajouter le test à `npm test` et commiter**

Dans `tools/basemap/package.json`, ajouter `gtavi-transform.test.mjs` à la commande de test existante, sur le même modèle que les tests déjà listés.

```sh
cd tools/basemap && npm test
cd /Users/antoine/gta_project
git add tools/basemap/gtavi-transform.mjs tools/basemap/gtavi-transform.test.mjs \
        tools/basemap/gtavi-map.mjs tools/basemap/gtavi-restyle.mjs tools/basemap/package.json
git commit -m "$(cat <<'EOF'
refactor(basemap): extraire la transformation de carte, fenêtrable et à échelle

Les 310 lignes de traitement qui précèdent et suivent restyle() vivaient dans
gtavi-map.mjs, câblées sur une image entière et sur les constantes du z5. Le
pavage z6 en a besoin par quadrants et au double de l'échelle.

Le traitement est déplacé tel quel dans gtavi-transform.mjs, paramétré par une
fenêtre, un cœur et un facteur d'échelle valant 1 à z5. gtavi-map.mjs en devient
le cas dégénéré et régénère island-vi.png et island-vi-classic.png identiques
octet pour octet.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3 : Traiter le z6 par quadrants, en tirer la pyramide, le socle et le manifeste

La transformation est extraite et prouvée. Cette tâche l'applique au brut z6 assemblé par la tâche 1, puis en découpe ce que l'app embarquera.

**Files:**
- Modify: `tools/basemap/gtavi-tiles.mjs`

**Interfaces:**
- Consumes : `SOURCE` et `stitchedPath()` de la tâche 1 ; `eraseAndDash`, `gridProbe`, `gridCenters`, `gridAndStyle`, `REF` de la tâche 2 — **dont les signatures exactes sont dans le bloc Interfaces de la tâche 2, à lire avant d'écrire un appel**. Deux d'entre elles mutent leur tampon sur place, et `core` n'y est jamais facultatif.
- Produces aussi : `legendMask(full)`, extraite de `eraseAndDash` au Step 7 pour que la classic et la restylée partagent une seule géométrie de légende.
- Produces : `NeonCompass/Resources/MapTiles/<nom>/<côté>/<x>_<y>.png`, `NeonCompass/Resources/MapTiles/<nom>.json`, et `NeonCompass/Resources/MapArt/<nom>.png` à 4 096 px. `<nom>` vaut `island-vi` ou `island-vi-classic`. Format du manifeste :

```json
{ "tile": 512, "base": 4096, "source": "gtavi:YANIS:v14:normal:z6",
  "levels": [ { "side": 8192, "count": 16, "uniform": { "0_0": "0A081A" } } ] }
```

`base` a été oubliée à la rédaction et ajoutée après coup — la tâche 4 la
déclare pourtant `let base: Int` NON optionnel dans un `Codable`, si bien que
son absence faisait LEVER le décodage : `MapTileManifest.load` aurait rendu
nil et l'app se serait rabattue en silence sur le socle, sans jamais poser une
tuile ni signaler quoi que ce soit. Elle porte le côté du socle, qui est le
seuil sous lequel aucun niveau n'est chargé.

`count` est le nombre de tuiles **par côté** — `side / tile` —, pas le total : c'est ce dont les tâches 4 à 6 ont besoin pour indexer une grille, et le total s'en déduit. `uniform` associe le nom d'une tuile non écrite à sa couleur en hexadécimal ; le fichier PNG correspondant n'existe pas.

- [ ] **Step 1 : Compléter le brut à 20 480 px**

Le brut fait 20 224 px : 79 tuiles au lieu des 80 qu'une grille pleine aurait. Le compléter à **20 480** avec la couleur d'océan, plutôt que de recalculer toute la géométrie sur 20 224.

Ce n'est pas un arrangement. La bande manquante occupe `x ∈ [20224, 20480)` et `y ∈ [20224, 20480)`, or l'effacement de légende peint en océan tout `x ≥ full.w - 1000` et tout `y ≥ full.h - 800` : la bande ajoutée est entièrement dans une zone que le pipeline écrase de toute façon. Au prix de 25 Mo sur disque, toute la géométrie du z5 devient valable à z6 au facteur 2 exact.

```js
const REF_SIDE = 10240;                 // le z5
const SIDE = 20480;                     // 2 × REF_SIDE
const SCALE = SIDE / REF_SIDE;          // vaut 2, et le module le recalcule seul

/// Complète le brut assemblé de SOURCE.side à SIDE, en océan. Reprenable :
/// si le fichier complété existe déjà à la bonne taille, ne rien faire.
function padded(style, ocean) {
  const src = stitchedPath(style);
  const dst = join(CACHE, `padded-${style}.raw`);
  const want = SIDE * SIDE * 3;
  if (existsSync(dst) && statSync(dst).size === want) return dst;

  const row = Buffer.alloc(SIDE * 3);
  for (let x = 0; x < SIDE; x++) { row[x * 3] = ocean.r; row[x * 3 + 1] = ocean.g; row[x * 3 + 2] = ocean.b; }
  const fin = openSync(src, 'r'), fout = openSync(dst, 'w');
  const line = Buffer.allocUnsafe(SOURCE.side * 3);
  for (let y = 0; y < SIDE; y++) {
    const out = Buffer.from(row);
    if (y < SOURCE.side) {
      readSync(fin, line, 0, line.length, y * SOURCE.side * 3);
      line.copy(out, 0);
    }
    writeSync(fout, out, 0, out.length);
  }
  closeSync(fin); closeSync(fout);
  return dst;
}
```

- [ ] **Step 2 : Vérifier la complétion**

```sh
node -e 'const{statSync}=require("fs");console.log(statSync("tools/basemap/.cache/padded-normal.raw").size, 20480*20480*3)'
```

Expected: les deux nombres égaux — `1258291200`. Contrôler aussi que la dernière ligne est bien de l'océan et l'avant-dernière colonne aussi, en lisant trois pixels aux coins.

- [ ] **Step 3 : Les deux passes de quadrants**

Quatre cœurs de 10 240 px, halo de 1 024 px, donc des fenêtres de 11 264 px — environ 2,0 Go de tampons par quadrant, traités l'un après l'autre.

Deux passes, et non une, parce que le sondage de la grille somme des colonnes et des lignes **entières** : aucun quadrant ne peut le calculer seul. La première passe efface et supprime les tirets, écrit son cœur dans un intermédiaire et rend sa contribution au sondage ; les contributions sommées donnent les centres ; la seconde passe efface la grille et restyle.

```js
const HALO = 1024;
const CORE = SIDE / 2;
const CORES = [
  { x: 0, y: 0, w: CORE, h: CORE }, { x: CORE, y: 0, w: CORE, h: CORE },
  { x: 0, y: CORE, w: CORE, h: CORE }, { x: CORE, y: CORE, w: CORE, h: CORE },
];
const FULL = { w: SIDE, h: SIDE };

const windowOf = (core) => {
  const x = Math.max(0, core.x - HALO), y = Math.max(0, core.y - HALO);
  return { x, y, w: Math.min(SIDE, core.x + core.w + HALO) - x,
                 h: Math.min(SIDE, core.y + core.h + HALO) - y };
};

/// Lit une fenêtre d'un brut sur disque, ligne par ligne.
function readWindow(path, win) {
  const fd = openSync(path, 'r');
  const buf = Buffer.allocUnsafe(win.w * win.h * 3);
  for (let y = 0; y < win.h; y++) {
    readSync(fd, buf, y * win.w * 3, win.w * 3, ((win.y + y) * SIDE + win.x) * 3);
  }
  closeSync(fd);
  return buf;
}

/// Écrit un cœur dans un brut sur disque, ligne par ligne.
function writeCore(fd, core, data) {
  for (let y = 0; y < core.h; y++) {
    writeSync(fd, data, y * core.w * 3, core.w * 3, ((core.y + y) * SIDE + core.x) * 3);
  }
}

async function transformAll(style, ocean) {
  const src = padded(style, ocean);
  const mid = join(CACHE, `mid-${style}.raw`);
  const out = join(CACHE, `styled-${style}.raw`);

  // Passe A — effacement, tirets, contribution au sondage.
  // `core` est passé à eraseAndDash pour BORNER SES COMPTEURS, pas son
  // traitement : celui-ci porte sur toute la fenêtre, halo compris. Seul
  // `dashCompsInWindow` reste à portée de fenêtre — son nom le dit, et il ne
  // faut donc pas le sommer sur les quatre quadrants.
  const colHits = new Uint32Array(SIDE), rowHits = new Uint32Array(SIDE);
  const fmid = openSync(mid, 'w+');
  for (const core of CORES) {
    const win = windowOf(core);
    const buf = readWindow(src, win);
    const a = eraseAndDash(buf, win, FULL, ocean, core);
    const p = gridProbe(buf, win, FULL, core);
    for (let i = 0; i < SIDE; i++) { colHits[i] += p.colHits[i]; rowHits[i] += p.rowHits[i]; }
    // Prélever le cœur de la fenêtre avant de l'écrire.
    const cw = Buffer.allocUnsafe(core.w * core.h * 3);
    for (let y = 0; y < core.h; y++) {
      buf.copy(cw, y * core.w * 3,
               ((core.y - win.y + y) * win.w + (core.x - win.x)) * 3,
               ((core.y - win.y + y) * win.w + (core.x - win.x) + core.w) * 3);
    }
    writeCore(fmid, core, cw);
    console.log(`  quadrant ${core.x / CORE},${core.y / CORE} A : ${a.erased} effacés, ${a.dashCompsInWindow} tirets (fenêtre), ${a.dashSuppressed} px → voisin`);
  }
  closeSync(fmid);

  const centers = gridCenters(colHits, rowHits, FULL);
  console.log(`  grille : ${centers.nCols} colonnes + ${centers.nRows} lignes détectées sur l'océan`);

  // Passe B — grille, restylage, aplatissement. Et la boîte englobante, pour
  // contrôle : elle n'est pas utilisée pour recadrer, seulement pour vérifier.
  const fout = openSync(out, 'w+');
  let bb = null;
  for (const core of CORES) {
    const win = windowOf(core);
    const r = gridAndStyle(readWindow(mid, win), win, FULL, core, centers);
    writeCore(fout, core, r.data);
    if (r.bbox) {
      bb = bb ? { minX: Math.min(bb.minX, r.bbox.minX), maxX: Math.max(bb.maxX, r.bbox.maxX),
                  minY: Math.min(bb.minY, r.bbox.minY), maxY: Math.max(bb.maxY, r.bbox.maxY) } : r.bbox;
    }
    console.log(`  quadrant ${core.x / CORE},${core.y / CORE} B : ${r.gridSuppressed} px de grille, ${r.flattened} aplatis — ${r.stats}`);
  }
  closeSync(fout);
  return { path: out, bbox: bb };
}
```

- [ ] **Step 4 : Le recadrage, doublé et non recalculé**

Le z5 livré recadre en `left 1482, top 1094, 8758 × 8758`. Les coordonnées d'épingle déjà saisies désignent des points de ce cadre : le recadrage z6 est donc son double exact, pas un nouveau calcul.

```js
// Recadrage du z5 livré (relevé en régénérant island-vi.png, identique octet
// pour octet), doublé. Le RECALCULER ferait dériver le cadre de quelques
// pixels, et toutes les épingles déjà posées avec lui.
const CROP = { left: 1482 * SCALE, top: 1094 * SCALE, side: 8758 * SCALE };

/// Le nombre de pixels non-océan par LIGNE GLOBALE, cumulé sur les quatre
/// quadrants — une ligne traverse deux quadrants, il faut donc les sommer.
/// À alimenter dans la boucle de la passe B, juste après `gridAndStyle` :
///
///   for (let y = 0; y < core.h; y++) {
///     let n = 0;
///     for (let x = 0; x < core.w; x++) if (!styled.ocean[y * core.w + x]) n++;
///     rowInk[core.y + y] += n;
///   }
const rowInk = new Uint32Array(FULL.h);

/// La première ligne portant assez d'encre pour être une côte, et non un
/// éclat de classification isolé.
///
/// POURQUOI PAS `bbox.minY` : le `min()` de la boîte englobante retient le
/// PREMIER pixel non-océan, quel qu'il soit. Mesuré sur le z5 livré, ligne
/// par ligne : `minY = 1174` avec **n = 1**, un pixel unique, quand la côte
/// ne commence qu'à **1249** (n = 121) et que la première terre de la source
/// brute est à 1246. La borne nord de la boîte englobante n'a donc jamais
/// mesuré une côte — elle mesurait du bruit, aux deux échelles à la fois.
/// Le contrôle comparait du bruit à du bruit.
///
/// Le seuil suit l'échelle et non son carré : une même bande géographique
/// occupe `scale` fois plus de pixels par ligne. 64 à z5, 128 à z6.
function coastTop(ink, scale) {
  const seuil = 64 * scale;
  for (let y = 0; y < ink.length; y++) if (ink[y] >= seuil) return y;
  return -1;
}

/// Le cadre doit contenir l'île, et de peu. Le contrôle est là pour attraper
/// une constante d'échelle mal transposée en tâche 2 : si le classificateur
/// dérape, la boîte englobante déborde et on l'apprend ici plutôt qu'à l'œil.
function checkCrop(bbox, rowInk) {
  const ref = { minX: 3440 * SCALE, maxX: 9645 * SCALE, maxY: 9771 * SCALE };
  const tol = 64 * SCALE;
  for (const k of ['minX', 'maxX', 'maxY']) {
    if (Math.abs(bbox[k] - ref[k]) > tol) {
      throw new Error(`boîte englobante ${k}=${bbox[k]}, attendu ${ref[k]} ±${tol} — `
        + `une constante d'échelle est fausse, voir la table de la tâche 2`);
    }
  }
  const cote = coastTop(rowInk, SCALE);
  const planchier = CROP.top, plafond = 1249 * SCALE + 256 * SCALE;
  if (!(cote > planchier && cote < plafond)) {
    throw new Error(`côte nord à y=${cote}, attendue dans ]${planchier}, ${plafond}[ — `
      + `sous le cadre elle serait perdue au recadrage, au-delà le classificateur `
      + `a mangé la pointe de l'île`);
  }
}
```

La tolérance de `64 × 2 = 128` px z6 n'est pas un chiffre rond de confort : c'est 64 px z5, soit moins que la marge que le recadrage ajoute déjà de chaque côté. Un dérapage plus grand changerait le cadre.

**Pourquoi le nord est traité à part, et ce que ça a coûté de le découvrir.** Le contrôle a d'abord été écrit avec les quatre bords sur le même pied : `minY` doublé comme les autres, à ±128 px. Il a échoué deux fois de suite, pour deux raisons différentes, et les deux fois c'est le contrôle qui avait tort. La première, `minY` se lisait sur le premier pixel non-océan venu — un éclat isolé, aux deux échelles. Corrigé par la densité. La seconde, la mesure corrigée donne **2667** contre `1249 × 2 = 2498` attendus, et cette fois ce n'est plus une erreur de mesure. Les quatre relevés, ramenés en unités z5 :

| | source brute | après restylage |
|---|---|---|
| z5 | 1283 | 1249 — le restylage **avance** la côte de 34 px |
| z6 | ~1275 | 1333 — il la **recule** de 58 px |

La source double exactement : `1283 × 2 = 2566` prédit contre ~2550 mesuré. C'est le restylage qui diverge, d'environ 90 px z5, **et dans des sens opposés aux deux échelles**. La brume côtière ténue au nord de l'île tombe d'un côté ou de l'autre du classificateur selon la finesse. Le rendu z6, lui, est correct : côte nette, dégradé d'océan propre, aucune pointe rabotée — vérifié en vignette, pas déduit.

L'égalité inter-échelle sur ce bord n'est donc pas une propriété du pipeline, c'était une hypothèse. Le nord assure ce qu'il peut assurer, et ça reste falsifiable : la côte est au sud du cadre — rien de réel n'est perdu au recadrage — et pas absurdement loin au sud, sinon le classificateur aurait mangé la pointe. **La tolérance des trois autres bords n'a pas bougé, et ne doit pas bouger** : ils tombent à 2 px près, c'est eux qui prouvent la géométrie.

- [ ] **Step 5 : Vérifier les deux passes sur le z6**

```sh
node tools/basemap/gtavi-tiles.mjs --style normal
```

Expected: huit lignes de quadrant, puis la ligne de grille. **Relever et comparer aux valeurs z5** — c'est le seul contrôle de fond disponible à z6, faute de vérité terrain.

Tout ce tableau repose sur une propriété que la tâche 2 a dû établir explicitement : **les compteurs sont bornés au cœur, jamais à la fenêtre**. Les halos se recouvrent ; un compteur de fenêtre compterait deux à quatre fois les mêmes pixels, et la somme des quatre quadrants ne serait plus comparable à quoi que ce soit. Avec le cœur, les quatre cœurs pavent l'image exactement une fois, et la somme est la valeur de l'image entière. Si `erased` ne tombe pas pile sur son multiple, **soupçonner d'abord le périmètre du comptage, avant l'arithmétique de fenêtre** — c'est le mode de défaillance le plus probable.

| Grandeur | Attendu à z6 | Pourquoi |
|---|---|---|
| Somme des `erased` | **164 928 000** | `4 × 41 232 000` : l'effacement est positionnel, il quadruple exactement avec la surface. Tout autre nombre est un bug d'arithmétique de fenêtre, pas un effet du contenu. C'est le contrôle le plus dur du lot — égalité exacte, pas fourchette — parce qu'il ne dépend d'aucun contenu. |
| Colonnes + lignes de grille | **104 et 152**, exactement | `2 × (52, 76)`. La rédaction initiale attendait ici « 52 et 76 » en raisonnant que la grille est la même grille — c'est faux, et la mesure l'a tranché : `gridCenters` compte des **traits en pixels**, et un trait de 1 px à z5 en occupe 2 à z6, donc chaque trait est compté deux fois. La meilleure colonne totalise 1 120 hits à z6, soit 100 % de la hauteur de la fenêtre de sondage : le trait est plein, pas dédoublé par du bruit. Tout autre nombre que 104 et 152 dénonce une détection qui dérape. |
| Répartition des classes | chaque classe à **±3 points** du z5 (eau 75,5 · bâti 18,7 · sable 2,7 · rues 1,2 · terre 0,7 · axes 0,6 · libellés 0,4 · sombre 0,1) | Le classificateur est per-pixel et purement colorimétrique. La même carte, deux fois plus fine, doit se répartir presque pareil. Un écart de plus de 3 points sur une classe dénonce une constante d'aire ou de longueur mal transposée. |
| Boîte englobante | dans les `±128` px de `checkCrop`, `minY` mesuré **par densité** | Sinon le script s'arrête de lui-même. Les trois autres bords se lisent sur `bbox` ; `minY` se lit sur `rowInk`, parce que le premier pixel non-océan est du bruit et pas une côte. |

Ces quatre contrôles ne remplacent pas un regard. Extraire aussi trois vignettes de 1 024 px du brut restylé — une sur la ville dense, une sur une limite de comté, une sur une côte — les enregistrer en PNG et les regarder. Une constante d'aire fausse se voit : les libellés cessent d'être unifiés, ou des pans de bâti virent au blanc-lavande.

- [ ] **Step 6 : Découper la pyramide**

Le recadrage fait 17 516 px. Le niveau le plus fin est **16 384** (`512 × 32`) : viser 20 480 interpolerait 17 % de pixels qui n'existent pas. 16 384 garde le même rapport de rééchantillonnage que le z5 livré (8 758 → 8 192), et c'est un multiple exact de la tuile.

```js
const TILE = 512;
const LEVELS = [16384, 8192];   // du plus fin au plus grossier
const BASE = 4096;              // le socle, image unique — le palier suivant de
                                // la même chaîne, qu'il est inutile de paver
const UNIFORM_TOL = 2;          // écart max sur les trois canaux
const NIGHT_SKY = { r: 0x0A, g: 0x08, b: 0x1A };

/// Lit le recadrage depuis le brut restylé et le rend à `side` px.
async function levelBuffer(rawPath, side, background) {
  const crop = Buffer.allocUnsafe(CROP.side * CROP.side * 3);
  const fd = openSync(rawPath, 'r');
  for (let y = 0; y < CROP.side; y++) {
    readSync(fd, crop, y * CROP.side * 3, CROP.side * 3,
             ((CROP.top + y) * SIDE + CROP.left) * 3);
  }
  closeSync(fd);
  // Rendu en BRUT et non en PNG : le découpage qui suit prélève ses tuiles par
  // recopie mémoire. Rendre un PNG obligerait sharp à le redécoder à chaque
  // extraction — 1 024 décodages d'une image de 805 Mo au niveau le plus fin.
  return sharp(crop, { raw: { width: CROP.side, height: CROP.side, channels: 3 } })
    .resize(side, side, { kernel: 'lanczos3' })
    .sharpen({ sigma: 1, m1: 0.6, m2: 2 })
    .flatten({ background })
    .removeAlpha()          // `flatten` promeut en RGBA ; le brut doit rester à 3 canaux
    .raw()
    .toBuffer();
}
```

Le recadrage occupe 920 Mo, le niveau rendu 805 Mo : environ 1,8 Go en pointe, une seule fois par niveau. Libérer le recadrage avant de passer au niveau suivant — ne jamais garder deux niveaux en mémoire.

```js
/// Découpe un niveau en tuiles. Une tuile dont les trois canaux varient de
/// moins de UNIFORM_TOL n'est pas écrite : sa couleur va au manifeste, et
/// l'app peindra un calque uni. 17 % des tuiles du niveau 8 192 dans la carte
/// livrée — le gain est réel et il évite autant de décodages.
async function cutLevel(name, side, raw) {
  const dir = join(TILES_DIR, name, String(side));
  mkdirSync(dir, { recursive: true });
  const n = side / TILE;
  const uniform = {};
  let written = 0;
  const tile = Buffer.allocUnsafe(TILE * TILE * 3);

  for (let ty = 0; ty < n; ty++) {
    for (let tx = 0; tx < n; tx++) {
      // Prélèvement par recopie de lignes. Le brut est en mémoire, donc c'est
      // un memcpy de 1,5 Ko par ligne — rien à décoder.
      for (let y = 0; y < TILE; y++) {
        const from = ((ty * TILE + y) * side + tx * TILE) * 3;
        raw.copy(tile, y * TILE * 3, from, from + TILE * 3);
      }

      // Uniformité jugée sur le BRUT, avant tout encodage : c'est exact, et la
      // quantification en palette pourrait sinon rendre uniforme une tuile qui
      // ne l'est pas — ou l'inverse.
      let rMin = 255, rMax = 0, gMin = 255, gMax = 0, bMin = 255, bMax = 0;
      for (let i = 0; i < tile.length; i += 3) {
        const r = tile[i], g = tile[i + 1], b = tile[i + 2];
        if (r < rMin) rMin = r; if (r > rMax) rMax = r;
        if (g < gMin) gMin = g; if (g > gMax) gMax = g;
        if (b < bMin) bMin = b; if (b > bMax) bMax = b;
      }
      if (rMax - rMin <= UNIFORM_TOL && gMax - gMin <= UNIFORM_TOL && bMax - bMin <= UNIFORM_TOL) {
        const hex = [(rMin + rMax) >> 1, (gMin + gMax) >> 1, (bMin + bMax) >> 1]
          .map((c) => c.toString(16).padStart(2, '0').toUpperCase()).join('');
        uniform[`${tx}_${ty}`] = hex;
        continue;
      }

      writeFileSync(join(dir, `${tx}_${ty}.png`), await sharp(tile, {
        raw: { width: TILE, height: TILE, channels: 3 },
      }).png({ palette: true, colors: 256, effort: 9 }).toBuffer());
      written++;
    }
  }
  return { side, count: n, written, uniform };
}
```

- [ ] **Step 7 : Le socle et la classic**

Le socle vient du **même recadrage**, pas d'une réduction du niveau 8 192 : une seule provenance, donc aucune dérive de sous-pixel entre le socle et les tuiles posées par-dessus. Il remplace `island-vi.png` à 4 096 px, et lui seul s'encode en PNG directement plutôt qu'en brut :

```js
const base = await levelBuffer(styled.path, BASE, background);
writeFileSync(join(ART_DIR, `${name}.png`), await sharp(base, {
  raw: { width: BASE, height: BASE, channels: 3 },
}).png({ palette: true, colors: 256, effort: 9 }).toBuffer());
```

La classic ne passe par aucun quadrant. Elle est la source complétée plus l'effacement de légende, et rien d'autre — c'est exactement l'état que `erasedOut` capture dans `gtavi-map.mjs`. Produire son brut en une passe de lecture-écriture ligne par ligne sur le brut complété, puis lui appliquer le même `CROP`, les mêmes `LEVELS`, le même socle. Son fond de remplissage est la couleur d'océan échantillonnée, pas `NIGHT_SKY`.

**Ne pas récrire le prédicat d'effacement ici.** Il vit à l'intérieur de `eraseAndDash`, sur trois constantes échelonnées ; le recopier ferait deux géométries de légende qui dériveraient au premier réglage. Commencer donc par l'extraire de `eraseAndDash` — qui l'appelle désormais au lieu de le définir — et l'exporter :

```js
/// La géométrie du panneau de légende, en coordonnées GLOBALES. Une seule
/// définition, parce que la carte restylée et la classic doivent effacer
/// exactement la même chose, à jamais.
export function legendMask(full) {
  const s = scaleOf(full);
  const E_PANEL = Math.round(3000 * s), E_BAND = Math.round(400 * s), E_RIGHT = Math.round(500 * s);
  return (gx, gy) =>
    gx < E_PANEL || gy < E_BAND || gy >= full.h - E_BAND || gx >= full.w - E_RIGHT;
}
```

C'est un déplacement, pas une réécriture : le contrôle est la régénération z5 du Step 6 de la tâche 2, qui doit rester `cmp`-identique. La relancer après ce déplacement, avant d'aller plus loin.

- [ ] **Step 8 : Écrire les manifestes**

Un fichier par carte, `NeonCompass/Resources/MapTiles/<nom>.json`, aux clefs décrites plus haut. Les niveaux sont listés **du plus grossier au plus fin** — `8192` puis `16384` — pour que la tâche 5 puisse parcourir la liste dans l'ordre et s'arrêter au premier niveau assez fin.

- [ ] **Step 9 : Contrôler ce qui est produit**

```sh
for m in island-vi island-vi-classic; do
  echo "=== $m ==="
  for s in 8192 16384; do
    echo "  $s : $(ls NeonCompass/Resources/MapTiles/$m/$s | wc -l) tuiles écrites"
  done
  node -e "const m=require('./NeonCompass/Resources/MapTiles/$m.json');
    for (const l of m.levels) {
      const n = l.side / m.tile;
      console.log('  ' + l.side + ' : ' + l.count + ' par côté, ' + n + ' attendues, '
                  + Object.keys(l.uniform).length + ' uniformes sur ' + n*n);
      if (l.count !== n) throw new Error('compte incohérent au niveau ' + l.side);
    }"
  du -sh NeonCompass/Resources/MapTiles/$m
done
du -sh NeonCompass/Resources/MapTiles
```

Expected: `8192` → 16 par côté soit 256 tuiles, `16384` → 32 par côté soit 1 024 tuiles ; écrites + uniformes = le total à chaque niveau ; poids total entre 40 et 90 Mo pour les deux cartes. **S'il dépasse 100 Mo, s'arrêter et remonter** — c'est une décision de produit, pas d'implémentation.

Contrôler enfin qu'aucun trou ne s'est glissé : pour chaque niveau, chaque `x_y` de `0_0` à `(n-1)_(n-1)` doit être soit un fichier présent, soit une clef de `uniform`, jamais ni l'un ni l'autre, jamais les deux. La tâche 4 en fera un test Swift ; ici une boucle de contrôle suffit, mais elle doit tourner.

- [ ] **Step 10 : Prouver que le contrôle de trous sait échouer**

Déplacer une tuile hors du dossier, relancer le contrôle, vérifier qu'il la nomme, la remettre. Consigner les deux sorties.

- [ ] **Step 11 : Commiter**

Les tuiles sont des ressources binaires volumineuses : les commiter dans le même commit que le générateur, pour que l'un ne parte jamais sans l'autre.

```sh
git add tools/basemap/gtavi-tiles.mjs NeonCompass/Resources/MapTiles
git commit -m "$(cat <<'EOF'
feat(basemap): pyramide z6 par quadrants — deux niveaux, socle et manifeste

Le brut z6 est complété de 20 224 à 20 480 px en océan, ce qui rend toute la
géométrie du z5 valable au facteur 2 exact. Il traverse ensuite la
transformation par quatre quadrants de 10 240 px à halo de 1 024, en deux
passes — le sondage de la grille de coordonnées somme des lignes entières et
ne peut pas se calculer par quadrant.

Le recadrage est celui du z5 livré, doublé et non recalculé : les épingles déjà
posées désignent le même point. Le niveau le plus fin est 16 384 px, le détail
réel du recadrage étant de 17 516 px — viser 20 480 aurait interpolé 17 % de
pixels inventés.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4 : `MapTileManifest` — lire la pyramide, et le test d'intégrité

**Files:**
- Create: `NeonCompass/Core/Map/MapTileManifest.swift`
- Create: `NeonCompassTests/Map/MapTileResourcesTests.swift`
- Modify: `project.yml:68-74`

**Interfaces:**
- Consumes: les fichiers de la tâche 3.
- Produces:
  ```swift
  struct MapTileManifest: Codable, Equatable, Sendable {
      struct Level: Codable, Equatable, Sendable {
          let side: Int
          let count: Int
          let uniform: [String: String]
      }
      let tile: Int
      let base: Int
      let levels: [Level]                                    // triés du plus grossier au plus fin
      static func load(for name: String, from bundle: Bundle = .main) -> MapTileManifest?
      func uniformColor(level: Int, x: Int, y: Int) -> UInt32?   // 0xRRGGBB
  }
  ```

- [ ] **Step 1 : Déclarer le dossier de tuiles dans `project.yml`**

Sans cela le pavage n'entre pas dans le paquet, `Bundle.main.url` rend nil partout, et l'écran n'affiche que le socle — sans une erreur. Modifier le bloc `sources` :

```yaml
      - path: NeonCompass
        excludes:
          - "Resources/MapArt/**"
          - "Resources/MapTiles/**"
          - "Resources/POI/**"
          - "Resources/Cheats/**"
      - path: NeonCompass/Resources/MapArt
        type: folder
      # Même raison que MapArt : `type: folder` préserve l'arborescence
      # <nom>/<côté>/<x>_<y>.png, dont dépend le `subdirectory:` de
      # MapTileManifest.load. Aplatie, elle mettrait 4 200 fichiers homonymes
      # à la racine du paquet.
      - path: NeonCompass/Resources/MapTiles
        type: folder
```

Run: `xcodegen generate && xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 2 : Écrire le test d'intégrité du pavage**

Créer `NeonCompassTests/Map/MapTileResourcesTests.swift`. Il lit le dépôt et non `Bundle.main` — `NeonCompassTests` n'est pas hébergé dans le process de l'app, même contournement que `MapArtResourcesTests`.

```swift
import Testing
import Foundation
@testable import NeonCompass

/// Une tuile manquante ne se signale nulle part : la couche laisse un carré de
/// socle agrandi, ce qui ressemble à du flou et non à une panne. Ce test est le
/// seul endroit où cela se voit, et il doit nommer la tuile ET la commande à
/// relancer — sinon il ne sert qu'à faire échouer la CI.
struct MapTileResourcesTests {
    private static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("NeonCompass/Resources")

    private static let paved = ["island-vi", "island-vi-classic"]

    private static func manifest(_ name: String) throws -> MapTileManifest {
        let url = resources.appendingPathComponent("MapTiles/\(name).json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(MapTileManifest.self, from: data)
    }

    @Test func everyPavedMapShipsItsManifest() throws {
        for name in Self.paved {
            let m = try Self.manifest(name)
            #expect(m.tile == 512, "\(name) : tuile de \(m.tile) px, attendu 512")
            #expect(m.base == 4096, "\(name) : socle de \(m.base) px, attendu 4096")
            #expect(m.levels.map(\.side) == [9216, 18432], "\(name) : niveaux \(m.levels.map(\.side))")
            #expect(m.levels.map(\.count) == [18, 36], "\(name) : tuiles par côté \(m.levels.map(\.count))")
        }
    }

    /// Aucun trou hors tuiles uniformes déclarées, et réciproquement : une
    /// couleur déclarée pour une tuile qui existe ferait peindre un aplat
    /// par-dessus du contenu.
    @Test func everyTileIsEitherShippedOrDeclaredUniform() throws {
        for name in Self.paved {
            let m = try Self.manifest(name)
            for level in m.levels {
                let dir = Self.resources.appendingPathComponent("MapTiles/\(name)/\(level.side)")
                for y in 0..<level.count {
                    for x in 0..<level.count {
                        let key = "\(x)_\(y)"
                        let file = dir.appendingPathComponent("\(key).png")
                        let onDisk = FileManager.default.fileExists(atPath: file.path)
                        let declared = level.uniform[key] != nil
                        if onDisk == declared {
                            Issue.record(
                                onDisk
                                    ? "\(name)/\(level.side)/\(key).png existe ET est déclarée uniforme"
                                    : "\(name)/\(level.side)/\(key).png absente et non déclarée uniforme "
                                      + "— relancer node tools/basemap/gtavi-tiles.mjs"
                            )
                        }
                    }
                }
            }
        }
    }

    @Test func everyUniformColorIsSixHexDigits() throws {
        for name in Self.paved {
            let m = try Self.manifest(name)
            for level in m.levels {
                for (key, hex) in level.uniform {
                    #expect(
                        hex.count == 6 && hex.allSatisfy(\.isHexDigit),
                        "\(name)/\(level.side)/\(key) : couleur « \(hex) » illisible"
                    )
                }
            }
        }
    }

    /// Les deux habillages sortent du même cadrage : à niveau égal ils ont le
    /// même nombre de tuiles par côté. Sinon les épingles se décaleraient en
    /// basculant, ce que rien d'autre ne signalerait.
    @Test func bothStylesSharePyramidGeometry() throws {
        let neon = try Self.manifest("island-vi")
        let classic = try Self.manifest("island-vi-classic")
        #expect(neon.levels.map(\.side) == classic.levels.map(\.side))
        #expect(neon.levels.map(\.count) == classic.levels.map(\.count))
    }
}
```

- [ ] **Step 3 : Lancer la suite pour la voir échouer à la compilation**

Run: `xcodegen generate && xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:NeonCompassTests/MapTileResourcesTests 2>&1 | tail -20`
Expected: échec de compilation — `cannot find type 'MapTileManifest' in scope`.

- [ ] **Step 4 : Écrire `MapTileManifest`**

```swift
import Foundation

/// Décrit la pyramide de tuiles d'UNE carte : le manifeste de `MapArt/` décrit
/// l'espace de coordonnées des épingles et gouverne les deux cartes, celui-ci
/// décrit des fichiers et il y en a un par habillage.
///
/// Une carte sans manifeste n'est pas une anomalie : la carte de référence
/// (`island.png`, 4 096 px) n'a pas de pyramide et n'affiche que son socle.
/// C'est le repli normal, pas un filet — un seul chemin de rendu, une seule
/// condition.
struct MapTileManifest: Codable, Equatable, Sendable {
    struct Level: Codable, Equatable, Sendable {
        /// Côté du niveau en pixels — 8 192 ou 16 384.
        let side: Int
        /// Nombre de tuiles par côté, soit `side / tile`.
        let count: Int
        /// Tuiles d'une seule couleur, non livrées. Clé « x_y », valeur RRGGBB.
        let uniform: [String: String]
    }

    let tile: Int
    let base: Int
    /// Triés du plus grossier au plus fin — `MapTileSet` compte là-dessus pour
    /// prendre le premier niveau assez défini.
    let levels: [Level]

    static func load(for name: String, from bundle: Bundle = .main) -> MapTileManifest? {
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "MapTiles"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MapTileManifest.self, from: data)
    }

    /// La couleur d'une tuile omise, ou nil si la tuile est un fichier.
    ///
    /// Rend un entier plutôt qu'une couleur : ce type n'importe pas UIKit, ce
    /// qui le rend testable sans simulateur — et la conversion appartient à la
    /// couche, seule à savoir dans quel espace colorimétrique elle peint.
    func uniformColor(level: Int, x: Int, y: Int) -> UInt32? {
        guard let hex = levels.first(where: { $0.side == level })?.uniform["\(x)_\(y)"],
              let value = UInt32(hex, radix: 16) else { return nil }
        return value
    }
}
```

- [ ] **Step 5 : Lancer la suite et lire le compte**

Run: `xcodegen generate && xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:NeonCompassTests/MapTileResourcesTests 2>&1 | grep -E "Test run with|failed|passed"`
Expected: `Test run with 4 tests` et aucun échec. **Un compte différent de 4 vaut échec** — `-only-testing` sur une suite vide rapporte `TEST SUCCEEDED`.

- [ ] **Step 6 : Prouver que le test sait échouer**

```sh
mv NeonCompass/Resources/MapTiles/island-vi/18432/20_20.png /tmp/
```
Run: la même commande de test.
Expected: FAIL nommant `island-vi/18432/20_20.png absente et non déclarée uniforme`. Restaurer : `mv /tmp/20_20.png NeonCompass/Resources/MapTiles/island-vi/18432/`.

Si `20_20.png` n'existe pas — la tuile peut être uniforme et donc non écrite —
en choisir une autre par `ls`, et adapter les deux chemins. Ne pas se rabattre
sur la suppression d'une clef du manifeste : ce serait un autre contrôle.

- [ ] **Step 7 : Commit**

```bash
git add NeonCompass/Core/Map/MapTileManifest.swift NeonCompassTests/Map/MapTileResourcesTests.swift project.yml
git commit -m "feat(carte): manifeste de pavage et contrôle d'intégrité

Une tuile manquante ne se signale nulle part à l'exécution — la couche laisse
un carré de socle agrandi, qui ressemble à du flou. Le test nomme la tuile et
la commande à relancer, et il a été mis en échec exprès.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 5 : `MapTileSet` — la fonction pure

C'est la seule vraie logique du lot, et elle se teste entièrement hors interface.

**Files:**
- Create: `NeonCompass/Core/Map/MapTileSet.swift`
- Create: `NeonCompassTests/Map/MapTileSetTests.swift`

**Interfaces:**
- Consumes: `MapTileManifest` (tâche 4).
- Produces:
  ```swift
  struct MapTileKey: Hashable, Sendable { let level: Int; let x: Int; let y: Int }

  enum MapTileSet {
      static func displayablePixels(zoomScale: CGFloat, contentSize: CGFloat, displayScale: CGFloat) -> CGFloat
      static func level(for displayable: CGFloat, manifest: MapTileManifest) -> Int?
      static func tiles(level: Int, visibleContentRect: CGRect, contentSize: CGFloat,
                        manifest: MapTileManifest, margin: Int = 1) -> [MapTileKey]
      static func frame(for key: MapTileKey, contentSize: CGFloat, manifest: MapTileManifest) -> CGRect
  }
  ```

- [ ] **Step 1 : Écrire les tests, tous**

Créer `NeonCompassTests/Map/MapTileSetTests.swift` :

```swift
import Testing
import Foundation
import CoreGraphics
@testable import NeonCompass

/// Le choix « quel niveau, quelles tuiles » décide à la fois de la netteté et
/// de l'empreinte mémoire. C'est une fonction pure, donc c'est ici qu'il se
/// vérifie — pas à l'œil sur un simulateur.
struct MapTileSetTests {
    /// Ce manifeste n'est PAS celui qui est livré — le livré est en 9 216 /
    /// 18 432. Les puissances de deux sont choisies pour que l'arithmétique
    /// reste lisible dans les attentes : 2 048 / 32 fait 64 pt pile, là où
    /// 2 048 / 36 ferait 56,888…, et un test dont on doit vérifier la valeur
    /// attendue à la calculatrice ne prouve plus rien. Ce qui doit coller au
    /// livré est vérifié par `MapTileResourcesTests`, sur le vrai fichier.
    private static let manifest = MapTileManifest(
        tile: 512,
        base: 4096,
        levels: [
            .init(side: 8192, count: 16, uniform: [:]),
            .init(side: 16384, count: 32, uniform: ["0_0": "0A081A"]),
        ]
    )

    // MARK: - Pixels affichables

    @Test func displayablePixelsMultipliesTheThreeFactors() {
        #expect(MapTileSet.displayablePixels(zoomScale: 3.3, contentSize: 2048, displayScale: 3) == 2048 * 3.3 * 3)
    }

    /// Deux gardes qui évitent une division par zéro plus loin : une échelle
    /// d'affichage n'est jamais sous 1, un zoom jamais négatif.
    @Test func displayablePixelsClampsDegenerateInputs() {
        #expect(MapTileSet.displayablePixels(zoomScale: 1, contentSize: 2048, displayScale: 0) == 2048)
        #expect(MapTileSet.displayablePixels(zoomScale: -1, contentSize: 2048, displayScale: 3) == 0)
    }

    // MARK: - Choix du niveau

    /// Sous le socle, aucune tuile : à 4 096 px affichables le socle en a déjà
    /// autant que l'écran peut montrer, et charger un niveau ferait payer la
    /// carte entière au repos — où toute la carte est visible.
    @Test func noTilesWhileTheBaseSuffices() {
        #expect(MapTileSet.level(for: 2642, manifest: Self.manifest) == nil)   // repos iPhone
        #expect(MapTileSet.level(for: 4096, manifest: Self.manifest) == nil)   // pile le socle
    }

    /// Au-dessus, le premier niveau assez défini — jamais le plus fin par défaut.
    @Test func theCoarsestSufficientLevelWins() {
        #expect(MapTileSet.level(for: 4097, manifest: Self.manifest) == 8192)
        #expect(MapTileSet.level(for: 8192, manifest: Self.manifest) == 8192)
        #expect(MapTileSet.level(for: 8193, manifest: Self.manifest) == 16384)
        #expect(MapTileSet.level(for: 16384, manifest: Self.manifest) == 16384)
    }

    /// Au-delà du plus fin on agrandit, mais on ne rend pas nil : rendre nil
    /// ferait retomber sur le socle au zoom maximal, soit l'inverse du but.
    @Test func beyondTheFinestLevelWeUpscaleRatherThanFallBack() {
        #expect(MapTileSet.level(for: 30000, manifest: Self.manifest) == 16384)
    }

    // MARK: - Fenêtre de tuiles

    /// Une tuile de 512 px au niveau 16 384 couvre 64 pt de l'espace de
    /// contenu de 2 048 pt. Un rectangle de 100 pt en coin en touche donc deux
    /// par axe, plus une marge d'une tuile.
    @Test func theWindowCoversTheVisibleRectPlusOneTileOfMargin() {
        let keys = MapTileSet.tiles(
            level: 16384,
            visibleContentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            contentSize: 2048, manifest: Self.manifest
        )
        #expect(Set(keys.map(\.x)) == [0, 1, 2])
        #expect(Set(keys.map(\.y)) == [0, 1, 2])
        #expect(keys.count == 9)
    }

    /// Les bords ne débordent jamais de la grille — une clé hors grille
    /// désignerait un fichier absent, indiscernable d'une tuile manquante.
    @Test func theWindowIsClampedToTheGrid() {
        let keys = MapTileSet.tiles(
            level: 8192,
            visibleContentRect: CGRect(x: 1900, y: 1900, width: 300, height: 300),
            contentSize: 2048, manifest: Self.manifest
        )
        #expect(keys.allSatisfy { (0..<16).contains($0.x) && (0..<16).contains($0.y) })
        #expect(keys.contains(MapTileKey(level: 8192, x: 15, y: 15)))
    }

    /// Un rectangle hors carte ne rend rien plutôt qu'une clé négative.
    @Test func anOffMapRectYieldsNothing() {
        let keys = MapTileSet.tiles(
            level: 8192,
            visibleContentRect: CGRect(x: -5000, y: -5000, width: 100, height: 100),
            contentSize: 2048, manifest: Self.manifest
        )
        #expect(keys.isEmpty)
    }

    /// Le repos demande TOUTES les tuiles du niveau : c'est justement pourquoi
    /// `level(for:)` rend nil sous le socle, et ce test fige la raison.
    @Test func theWholeMapAtRestWouldCostTheEntireLevel() {
        let keys = MapTileSet.tiles(
            level: 8192,
            visibleContentRect: CGRect(x: 0, y: 0, width: 2048, height: 2048),
            contentSize: 2048, manifest: Self.manifest
        )
        #expect(keys.count == 256)
    }

    // MARK: - Placement

    @Test func aTileFrameTilesTheContentSpaceExactly() {
        let f0 = MapTileSet.frame(for: MapTileKey(level: 16384, x: 0, y: 0), contentSize: 2048, manifest: Self.manifest)
        #expect(f0 == CGRect(x: 0, y: 0, width: 64, height: 64))
        let last = MapTileSet.frame(for: MapTileKey(level: 16384, x: 31, y: 31), contentSize: 2048, manifest: Self.manifest)
        #expect(abs(last.maxX - 2048) < 0.001)
        #expect(abs(last.maxY - 2048) < 0.001)
    }
}
```

- [ ] **Step 2 : Lancer pour voir échouer**

Run: `xcodegen generate && xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:NeonCompassTests/MapTileSetTests 2>&1 | tail -20`
Expected: échec de compilation — `cannot find 'MapTileSet' in scope`.

- [ ] **Step 3 : Écrire `MapTileSet`**

```swift
import CoreGraphics

/// Une tuile, désignée par son niveau et sa position dans la grille de ce
/// niveau. Le niveau fait partie de la clé : deux tuiles de niveaux différents
/// couvrent la même région sans être interchangeables.
struct MapTileKey: Hashable, Sendable {
    let level: Int
    let x: Int
    let y: Int
}

/// Quel niveau pour quelle échelle, quelles tuiles pour quelle fenêtre.
///
/// Tout est ici et rien n'est ailleurs : `MapTileLayerView` ne fait que poser
/// ce que ces fonctions décident. C'est ce partage qui rend le pavage testable
/// — le comportement d'un `CATiledLayer` ne se serait vérifié qu'à l'œil.
enum MapTileSet {
    /// Combien de pixels de l'image l'écran peut montrer.
    static func displayablePixels(zoomScale: CGFloat, contentSize: CGFloat, displayScale: CGFloat) -> CGFloat {
        contentSize * max(zoomScale, 0) * max(displayScale, 1)
    }

    /// Le niveau à charger, ou nil quand le socle suffit.
    ///
    /// Nil sous `manifest.base` est la décision qui tient l'empreinte mémoire.
    /// Au repos toute la carte est visible : engager un niveau y ferait charger
    /// ses 256 tuiles, soit 256 Mo — plus cher que l'image unique qu'on
    /// remplace. Le socle a déjà 4 096 px, l'écran n'en montre que ≈2 642.
    ///
    /// Aucune constante de tolérance ici, et c'est délibéré : l'ancien
    /// `maxUpscale` de 1,5 était un jugement, celui-ci est de la géométrie.
    static func level(for displayable: CGFloat, manifest: MapTileManifest) -> Int? {
        guard displayable > CGFloat(manifest.base) else { return nil }
        for level in manifest.levels where CGFloat(level.side) >= displayable { return level.side }
        // Au-delà du plus fin on agrandit. Retomber sur le socle au zoom
        // maximal serait exactement l'inverse du but poursuivi.
        return manifest.levels.last?.side
    }

    /// Les tuiles couvrant le rectangle visible, plus une marge.
    ///
    /// La marge n'est pas du confort : un panoramique découvre la tuile
    /// suivante avant que son décodage n'aboutisse, et sans elle on verrait le
    /// socle agrandi défiler devant le doigt.
    static func tiles(
        level: Int,
        visibleContentRect: CGRect,
        contentSize: CGFloat,
        manifest: MapTileManifest,
        margin: Int = 1
    ) -> [MapTileKey] {
        guard let descriptor = manifest.levels.first(where: { $0.side == level }), descriptor.count > 0 else { return [] }
        let step = contentSize / CGFloat(descriptor.count)
        guard step > 0 else { return [] }
        let last = descriptor.count - 1
        let x0 = Int(floor(visibleContentRect.minX / step)) - margin
        let x1 = Int(floor((visibleContentRect.maxX - 0.001) / step)) + margin
        let y0 = Int(floor(visibleContentRect.minY / step)) - margin
        let y1 = Int(floor((visibleContentRect.maxY - 0.001) / step)) + margin
        guard x1 >= 0, y1 >= 0, x0 <= last, y0 <= last else { return [] }
        var keys: [MapTileKey] = []
        for y in max(0, y0)...min(last, y1) {
            for x in max(0, x0)...min(last, x1) {
                keys.append(MapTileKey(level: level, x: x, y: y))
            }
        }
        return keys
    }

    /// Où poser la tuile dans l'espace de contenu, en points.
    static func frame(for key: MapTileKey, contentSize: CGFloat, manifest: MapTileManifest) -> CGRect {
        guard let descriptor = manifest.levels.first(where: { $0.side == key.level }), descriptor.count > 0 else { return .zero }
        let step = contentSize / CGFloat(descriptor.count)
        return CGRect(x: CGFloat(key.x) * step, y: CGFloat(key.y) * step, width: step, height: step)
    }
}
```

- [ ] **Step 4 : Lancer et lire le compte**

Run: `xcodegen generate && xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:NeonCompassTests/MapTileSetTests 2>&1 | grep -E "Test run with|failed|passed"`
Expected: `Test run with 10 tests`, aucun échec.

- [ ] **Step 5 : Commit**

```bash
git add NeonCompass/Core/Map/MapTileSet.swift NeonCompassTests/Map/MapTileSetTests.swift
git commit -m "feat(carte): choix du niveau et de la fenêtre de tuiles, en pur

Le seuil d'engagement est géométrique et non un réglage : sous 4 096 pixels
affichables le socle en a déjà plus que l'écran ne montre, et engager un
niveau au repos coûterait 256 Mo puisque toute la carte est alors visible.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 6 : `MapTileLayerView` — poser les couches

**Files:**
- Create: `NeonCompass/Core/Map/MapTileLayerView.swift`

**Interfaces:**
- Consumes: `MapTileKey`, `MapTileSet` (tâche 5), `MapTileManifest` (tâche 4).
- Produces:
  ```swift
  @MainActor final class MapTileLayerView: UIView {
      init(contentSize: CGFloat)
      func setBase(_ image: CGImage?)            // le socle, sous les tuiles
      func setMap(name: String, manifest: MapTileManifest?)
      func update(visibleContentRect: CGRect, zoomScale: CGFloat, displayScale: CGFloat)
  }
  ```

⚠️ **Le socle appartient à CETTE vue, et c'est la décision structurante de la
tâche.** Aujourd'hui c'est `mapBody` qui dessine l'image de fond, plein cadre,
dans la même vue SwiftUI que les épingles — donc au-dessus de tout ce que cette
couche poserait. Un pavage glissé sous cette vue serait intégralement masqué :
la carte s'afficherait comme avant, sans une erreur, sans un trou, et le zoom
irait simplement plus loin en plus flou. C'est le seul défaut de ce plan qui
n'aurait rien fait échouer. L'empilement correct a donc trois étages et deux
vues : socle et tuiles ici, épingles dans la vue SwiftUI au-dessus. La tâche 7
retire l'image de `mapBody` en conséquence.

- [ ] **Step 1 : Écrire la vue**

```swift
import UIKit

/// Les tuiles, posées à la main dans des `CALayer` ordinaires.
///
/// **Pas de `CATiledLayer`, et c'est le point qui décide de tout ce fichier.**
/// Un `CATiledLayer` hébergé sous SwiftUI déclenche sur iOS 26 une
/// `NSInternalInconsistencyException` — « Modifications to the layout engine
/// must not be performed from a background thread » — levée depuis son fil de
/// dessin `CAImageProviderThread` à travers `_UIHostingView.layoutSubviews()`.
/// Le fil Apple 820296 la documente, un ingénieur Apple a demandé un rapport de
/// bug, et rien n'est corrigé. La même pile en UIKit pur ne reproduit pas :
/// c'est l'hébergement SwiftUI qui déclenche, et c'est exactement notre cas.
///
/// D'où la règle qui gouverne ce fichier : **le décodage sort du fil principal,
/// la mutation de l'arbre de couches jamais.** `decode` est `nonisolated`, tout
/// le reste est `@MainActor`.
///
/// Trois choses que `CATiledLayer` n'aurait pas données : le fondu nous
/// appartient (le « pop-in » était l'objection de la recherche de juillet), le
/// choix de niveau est une fonction pure donc testable (`MapTileSet`), et une
/// tuile d'une seule couleur se peint sans décoder quoi que ce soit.
@MainActor
final class MapTileLayerView: UIView {
    private let contentSize: CGFloat
    private var name: String?
    private var manifest: MapTileManifest?

    /// Le socle, plein cadre, sous toutes les tuiles. Il ne quitte jamais
    /// l'arbre : c'est lui qu'on voit là où une tuile n'est pas encore
    /// décodée, et sous le niveau où l'on n'en charge aucune.
    private let baseLayer = CALayer()

    /// Les couches actuellement dans l'arbre, par tuile.
    private var placed: [MapTileKey: CALayer] = [:]
    /// Décodages en cours — sert à ne pas relancer le même deux fois pendant un
    /// panoramique, où `update` est appelé à chaque image.
    private var decoding: Set<MapTileKey> = []
    /// Images déjà décodées, gardées au-delà de leur couche.
    ///
    /// C'est ce cache qui remplace l'hystérésis de l'ancien sélecteur d'étage :
    /// repasser un seuil de niveau pendant un pincement ne redécode rien.
    private var cache: [MapTileKey: CGImage] = [:]
    private var cacheOrder: [MapTileKey] = []
    /// 48 tuiles, soit 48 Mo. Un jeu visible en vaut 12 à 18 selon le zoom :
    /// la marge couvre un aller-retour entre deux niveaux sans redécodage.
    private static let cacheLimit = 48

    private var currentLevel: Int?

    init(contentSize: CGFloat) {
        self.contentSize = contentSize
        super.init(frame: CGRect(x: 0, y: 0, width: contentSize, height: contentSize))
        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.masksToBounds = true
        baseLayer.frame = bounds
        baseLayer.contentsGravity = .resize
        // Le socle est TOUJOURS réduit (4 096 px pour 2 048 pt) : c'est le
        // filtre de minification qui décide de son aspect, et `.trilinear`
        // remplace ici le `.interpolation(.high)` que `mapBody` posait.
        baseLayer.minificationFilter = .trilinear
        baseLayer.magnificationFilter = .linear
        baseLayer.actions = ["contents": NSNull(), "position": NSNull(), "bounds": NSNull()]
        layer.addSublayer(baseLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) n'est pas utilisé") }

    /// Le socle. Posé par le coordinateur, qui le décode déjà pour l'écran de
    /// repos — cette vue ne va pas le chercher elle-même.
    ///
    /// `addSublayer` empile : le socle étant ajouté dans `init`, toute tuile
    /// posée ensuite lui passe au-dessus sans qu'on ait à gérer d'index. Et
    /// `clear()` ne retire que les tuiles, jamais lui.
    func setBase(_ image: CGImage?) {
        baseLayer.contents = image
        baseLayer.contentsScale = image.map { CGFloat($0.width) / contentSize } ?? 1
    }

    /// Change de carte ou d'habillage. Tout est jeté : les tuiles d'un habillage
    /// ne valent rien pour l'autre, et le socle tient l'écran pendant que les
    /// premières arrivent.
    func setMap(name: String, manifest: MapTileManifest?) {
        guard name != self.name else { return }
        self.name = name
        self.manifest = manifest
        currentLevel = nil
        placed.values.forEach { $0.removeFromSuperlayer() }
        placed.removeAll()
        decoding.removeAll()
        cache.removeAll()
        cacheOrder.removeAll()
    }

    /// Appelée sur CHAQUE image de défilement et de zoom. Tout ce qui est
    /// coûteux doit donc être conditionné : ici, seul le calcul de la fenêtre
    /// est inconditionnel, et il est en O(tuiles visibles).
    func update(visibleContentRect: CGRect, zoomScale: CGFloat, displayScale: CGFloat) {
        guard let manifest, let name else { return }
        let displayable = MapTileSet.displayablePixels(
            zoomScale: zoomScale, contentSize: contentSize, displayScale: displayScale
        )
        guard let level = MapTileSet.level(for: displayable, manifest: manifest) else {
            // Le socle suffit : on rend les couches plutôt que de les garder
            // pour rien. Elles reviendront du cache si l'on rezoome.
            if !placed.isEmpty { clear() }
            currentLevel = nil
            return
        }
        if level != currentLevel {
            currentLevel = level
            clear()
        }
        let wanted = Set(MapTileSet.tiles(
            level: level, visibleContentRect: visibleContentRect,
            contentSize: contentSize, manifest: manifest
        ))
        for (key, layer) in placed where !wanted.contains(key) {
            layer.removeFromSuperlayer()
            placed[key] = nil
        }
        for key in wanted where placed[key] == nil {
            place(key, name: name, manifest: manifest)
        }
    }

    private func clear() {
        placed.values.forEach { $0.removeFromSuperlayer() }
        placed.removeAll()
    }

    private func place(_ key: MapTileKey, name: String, manifest: MapTileManifest) {
        let frame = MapTileSet.frame(for: key, contentSize: contentSize, manifest: manifest)

        // Tuile d'une seule couleur : un aplat, aucun fichier, aucun décodage.
        // 38 % des tuiles du niveau le plus fin sont dans ce cas — c'est
        // l'économie la plus rentable du pavage, et elle est exacte.
        if let rgb = manifest.uniformColor(level: key.level, x: key.x, y: key.y) {
            let layer = CALayer()
            layer.frame = frame
            layer.backgroundColor = UIColor(
                red: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255,
                alpha: 1
            ).cgColor
            self.layer.addSublayer(layer)
            placed[key] = layer
            return
        }

        // Une seule échelle, calculée une fois et employée par les DEUX chemins.
        // 512 px de tuile pour 56,9 pt de cadre au niveau le plus fin : c'est
        // 9. La poser à 1 sur le chemin du cache — et pas sur celui du décodage
        // — ferait rendre la même tuile différemment selon qu'on vient de la
        // découvrir ou d'y revenir, ce qui est exactement la netteté que cette
        // tâche existe pour obtenir.
        let scale = CGFloat(manifest.tile) / frame.width

        if let image = cache[key] {
            placed[key] = attach(image, at: frame, fade: false, scale: scale)
            return
        }

        guard !decoding.contains(key) else { return }
        decoding.insert(key)
        Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) {
                Self.decode(name: name, key: key)
            }.value
            guard let self else { return }
            self.decoding.remove(key)
            // `self.name == name` D'ABORD, et avant de mettre en cache : la clef
            // d'une tuile ne porte PAS le nom de la carte. Un décodage lancé
            // pour l'habillage néon qui aboutit après une bascule en classique
            // empoisonnerait le cache que `setMap` vient de vider, et l'on
            // peindrait des tuiles néon sur la carte classique jusqu'à leur
            // éviction. La fenêtre est courte ; le défaut, lui, est visible.
            guard let image, self.name == name else { return }
            self.remember(key, image)
            // Le zoom ou le panoramique ont pu emporter la tuile pendant le
            // décodage. La poser quand même la laisserait hors écran, et pire,
            // hors de `placed` — donc jamais retirée.
            guard self.currentLevel == key.level, self.placed[key] == nil else { return }
            self.placed[key] = self.attach(image, at: frame, fade: true, scale: scale)
        }
    }

    /// Le fondu, qui nous appartient précisément parce qu'on pose nous-mêmes.
    /// 0,18 s : assez pour que l'apparition ne clignote pas, assez court pour
    /// qu'un panoramique rapide ne traîne pas un voile derrière lui.
    /// `scale` n'a PAS de valeur par défaut : les deux appelants doivent la
    /// passer, et une omission doit être une erreur de compilation plutôt
    /// qu'une tuile posée à 1.
    private func attach(_ image: CGImage, at frame: CGRect, fade: Bool, scale: CGFloat) -> CALayer {
        let layer = CALayer()
        layer.frame = frame
        layer.contents = image
        layer.contentsScale = scale
        layer.contentsGravity = .resize
        layer.minificationFilter = .trilinear
        layer.magnificationFilter = .linear
        // Les tuiles ne s'animent pas en position : sans cela, chaque pose
        // déclencherait l'animation implicite de `frame` et la tuile
        // arriverait en glissant depuis le coin.
        layer.actions = ["contents": NSNull(), "position": NSNull(), "bounds": NSNull()]
        self.layer.addSublayer(layer)
        if fade {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 0
            animation.toValue = 1
            animation.duration = 0.18
            layer.add(animation, forKey: "fade")
        }
        return layer
    }

    private func remember(_ key: MapTileKey, _ image: CGImage) {
        if cache[key] == nil { cacheOrder.append(key) }
        cache[key] = image
        while cacheOrder.count > Self.cacheLimit {
            cache[cacheOrder.removeFirst()] = nil
        }
    }

    /// Hors MainActor : le seul endroit coûteux, et il n'a besoin d'aucun état
    /// partagé. `kCGImageSourceShouldCacheImmediately` force la rastérisation
    /// ICI plutôt qu'au premier dessin — sans lui, sortir la lecture du fil
    /// principal ne déplacerait que l'ouverture du fichier.
    private nonisolated static func decode(name: String, key: MapTileKey) -> CGImage? {
        guard let url = Bundle.main.url(
                forResource: "\(key.x)_\(key.y)", withExtension: "png",
                subdirectory: "MapTiles/\(name)/\(key.level)"
              ),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(
            source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        )
    }
}
```

Ajouter `import ImageIO` en tête du fichier.

- [ ] **Step 2 : Vérifier que le fichier compile sous concurrence stricte**

Run: `xcodegen generate && xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | grep -E "error|warning: .*concurrency|BUILD"`
Expected: `BUILD SUCCEEDED`, aucune erreur ni avertissement de concurrence. Si `CGImage` n'est pas `Sendable` dans ce contexte, **ne pas ajouter `@unchecked Sendable`** : renvoyer plutôt les octets et reconstruire le `CGImage` côté MainActor, ou marquer le retour de `decode` comme `sending`.

- [ ] **Step 3 : Commit**

```bash
git add NeonCompass/Core/Map/MapTileLayerView.swift
git commit -m "feat(carte): couche de tuiles en CALayer ordinaires

Décodage hors du fil principal, mutation de l'arbre de couches jamais — c'est
la règle qui évite par construction la classe de plantage iOS 26 de
CATiledLayer sous hébergement SwiftUI (thread Apple 820296, non corrigé).

Un cache de 48 tuiles remplace l'hystérésis de l'ancien sélecteur d'étage :
repasser un seuil pendant un pincement ne redécode rien.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 7 : Câblage dans le moteur, et zoom 3,3

**Files:**
- Modify: `NeonCompass/Core/Map/MapScrollView.swift:629-704` (`makeUIView`), `:763-813` (`updateUIView`), `:845-1012` (`Coordinator`)

**Interfaces:**
- Consumes: `MapTileLayerView` (tâche 6).
- Produces: `Coordinator.tileLayerView` et `Coordinator.contentContainer`, la vue conteneur que `viewForZooming` renvoie désormais.

- [ ] **Step 1 : Insérer le conteneur dans `makeUIView`**

Remplacer, dans `makeUIView`, le bloc qui va de la création du `hostingController` à `scrollView.addSubview(hostingController.view)` :

```swift
        let hostingController = UIHostingController(rootView: makeContent(zoom: MapRenderState(zoomScale: 1, contentSize: fullSize), coordinator: context.coordinator))
        hostingController.view.backgroundColor = .clear
        hostingController.view.frame = CGRect(x: 0, y: 0, width: fullSize, height: fullSize)

        // Un conteneur, et le zoom porte sur LUI. Socle et tuiles en dessous,
        // épingles au-dessus, dans le même espace de contenu : c'est ce qui
        // garantit qu'elles restent solidaires au pixel près pendant un
        // pincement, là où deux vues zoomées séparément dériveraient.
        //
        // L'ordre n'est correct QUE parce que l'étape 1 bis retire l'image de
        // `mapBody` : tant qu'elle y est, elle couvre le pavage entier et rien
        // ne le signale. Faire les deux, ou aucune.
        let container = UIView(frame: hostingController.view.frame)
        container.backgroundColor = .clear
        let tiles = MapTileLayerView(contentSize: fullSize)
        container.addSubview(tiles)
        container.addSubview(hostingController.view)

        scrollView.contentSize = container.frame.size
        scrollView.contentNativeSize = container.frame.size
        scrollView.addSubview(container)
```

Puis, plus bas dans la même fonction, remplacer :

```swift
        scrollView.maximumZoomScale = 2.5
```

par :

```swift
        // 2 048 pt × 3,3 × 3 = 20 275 px réclamés pour les 18 432 du niveau
        // le plus fin, soit un agrandissement de 1,10×. À 2,5 on réclamait
        // 15 360 px pour 8 192, soit 1,88× — c'était ÇA que l'on percevait
        // comme un manque de définition, pas le format. On zoome donc plus
        // loin ET plus net au point le plus tendu.
        scrollView.maximumZoomScale = 3.3
```

et remplacer :

```swift
        context.coordinator.contentView = hostingController.view
```

par :

```swift
        context.coordinator.contentView = container
        context.coordinator.tileLayerView = tiles
```

⚠️ `contentView` sert aussi de repère aux gestes (`handleLongPress` lit `gesture.location(in: contentView)`). Le conteneur et la vue hébergée ont exactement la même géométrie, donc les coordonnées sont identiques — mais il faut que ce soit le conteneur, puisque c'est lui qui est zoomé.

- [ ] **Step 1 bis : Sortir le socle de `mapBody` et le confier à la couche**

Dans `mapBody` (`MapScrollView.swift:176`), supprimer entièrement le bloc
`if let mapImage = MapArtLoader.cached(...)` et l'`Image` qu'il contient — le
`ZStack` commence désormais directement par `ForEach(clusters)`.

⚠️ **Et poser un cadre sur le `ZStack` en même temps, sinon toutes les épingles
se déplacent.** C'est l'`Image` supprimée qui portait
`.frame(width: fullSize, height: fullSize)` (ligne 191) et donnait donc sa
taille au `ZStack` ; le `.frame` de la ligne 172 appartient à la vue
enveloppante, pas à `mapBody`. Sans l'image, le `ZStack` se dimensionne sur les
seules épingles, son coin haut-gauche se déplace, et `alignment: .topLeading`
ancre alors dans le vide. Rien ne le signalerait : les épingles seraient
simplement toutes fausses. Fermer donc le `ZStack` par :

```swift
        }
        .frame(width: fullSize, height: fullSize, alignment: .topLeading)
```

Ne pas toucher à l'`alignment: .topLeading` du `ZStack` lui-même.

La vue hébergée devient donc entièrement transparente hors épingles, ce qui est
la condition pour voir le socle et les tuiles au travers.

Puis, dans `pushArt()`, poser le socle sur la couche :

```swift
        private func pushArt() {
            // Le socle passe désormais par la couche de tuiles et non par
            // SwiftUI : il doit être SOUS les tuiles, or la vue hébergée est
            // au-dessus d'elles. `cached` ne décode rien — `prepare` l'a fait.
            tileLayerView?.setBase(MapArtLoader.cached(game: artGame, style: artStyle, detail: requestedDetail)?.cgImage)
            guard var state = hostingController?.rootView.zoom else { return }
            state.artDetail = requestedDetail
            state.artGeneration = artGeneration
            hostingController?.rootView.zoom = state
        }
```

⚠️ `pushArt` n'est appelée qu'à l'ARRIVÉE d'un décodage. Si l'image est déjà
résidente, `requestArt` sort par son `guard` sans jamais appeler `pushArt`, et
le socle resterait vide. Appeler donc aussi `setBase` depuis `setArt`, juste
après `requestArt` :

```swift
        fileprivate func setArt(game: MapGame, style: MapStyle) {
            requestArt(game: game, style: style, detail: requestedDetail)
            // Cas de l'image déjà en mémoire : `requestArt` n'a rien lancé,
            // donc `pushArt` ne viendra pas. Sans cette ligne, revenir à un
            // habillage déjà visité laisserait un socle vide sous les tuiles
            // — et au repos, où aucune tuile n'est chargée, un écran noir.
            tileLayerView?.setBase(MapArtLoader.cached(game: game, style: style, detail: requestedDetail)?.cgImage)
        }
```

Run: `xcodegen generate && xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 2 : Déclarer les deux nouvelles références dans le coordinateur**

Dans `final class Coordinator`, après `weak var contentView: UIView?` :

```swift
        /// La couche de tuiles, sous les épingles. Faible comme les autres : la
        /// hiérarchie de vues la détient.
        weak var tileLayerView: MapTileLayerView?
        /// Manifeste de la carte affichée, ou nil pour une carte sans pyramide
        /// (la référence GTA V, qui n'affiche que son socle).
        private var tileManifest: MapTileManifest?
```

- [ ] **Step 3 : Charger le manifeste au changement de carte**

Dans `setArt`, qui est déjà le seul chemin par lequel carte et habillage changent :

```swift
        fileprivate func setArt(game: MapGame, style: MapStyle) {
            let name = game.resourceName(style: style)
            tileManifest = MapTileManifest.load(for: name)
            tileLayerView?.setMap(name: name, manifest: tileManifest)
            requestArt(game: game, style: style)
        }
```

- [ ] **Step 4 : Alimenter la couche depuis `sync`**

Dans `sync(_:)`, juste après le calcul de `newViewport` et avant la construction de `MapRenderState`, remplacer le bloc du sélecteur d'étage (lignes 988-995 actuelles) par :

```swift
            // La fenêtre visible en coordonnées de contenu — la même que celle
            // qui borne le dessin des épingles, ce qui garantit que les tuiles
            // chargées sont exactement celles sous ce qu'on voit.
            let visible = MapGeometry.visibleContentRect(
                bounds: scrollView.bounds.size,
                contentOffset: newViewport.contentOffset,
                zoomScale: newViewport.zoomScale
            )
            tileLayerView?.update(
                visibleContentRect: visible,
                zoomScale: newViewport.zoomScale,
                displayScale: scrollView.traitCollection.displayScale
            )
```

et réutiliser `visible` dans le `MapRenderWindow` construit juste en dessous, au lieu de rappeler `MapGeometry.visibleContentRect`.

- [ ] **Step 5 : Construire, et regarder la carte**

Run:
```sh
xcodegen generate
BUILT=$(xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2; exit}')
rm -rf "$BUILT/NeonCompass.app/MapArt" "$BUILT/NeonCompass.app/MapTiles"
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3
xcrun simctl install BD68054B-7C1F-48C8-B792-AB2C87C4B7A3 "$BUILT/NeonCompass.app"
xcrun simctl launch BD68054B-7C1F-48C8-B792-AB2C87C4B7A3 co.antoineteston.NeonCompass
```

Le `rm -rf` n'est pas optionnel : une ressource `type: folder` n'est PAS recopiée quand son contenu change, et l'app embarquerait l'ancien pavage sans un mot dans le journal.

Expected: `BUILD SUCCEEDED`, l'app se lance. Prendre une capture au repos :

Run: `xcrun simctl io BD68054B-7C1F-48C8-B792-AB2C87C4B7A3 screenshot /tmp/carte-repos.png`
Expected: la carte s'affiche, complète, sans carré noir ni décalage des épingles.

⚠️ **Automatisation du simulateur : `xcrun simctl` uniquement.** Ne jamais employer `osascript`, AppleScript, « System Events » ou un `screencapture` arbitraire pour interagir avec la fenêtre du simulateur — cela pilote le vrai bureau et a déjà capturé du contenu privé sans rapport.

- [ ] **Step 6 : Regarder au zoom, là où tout se joue**

Zoomer à fond dans le simulateur (double-tap répété, ou pincement au trackpad), puis :

Run: `xcrun simctl io BD68054B-7C1F-48C8-B792-AB2C87C4B7A3 screenshot /tmp/carte-zoom.png`

Expected, et à contrôler un par un :
1. Les libellés sont **nets**, pas interpolés. C'est le but de tout ce chantier.
2. Les tuiles apparaissent en fondu, sans clignotement ni glissement depuis un coin (si elles glissent, `layer.actions` n'a pas coupé l'animation implicite de position).
3. Aucune couture visible entre tuiles voisines.
4. Les épingles restent exactement sur leurs cibles — c'est la solidarité du conteneur.

- [ ] **Step 7 : Mesurer l'empreinte**

Run:
```sh
xcrun simctl spawn BD68054B-7C1F-48C8-B792-AB2C87C4B7A3 \
  footprint co.antoineteston.NeonCompass 2>/dev/null | tail -3
```

**Mesurer en TROIS points, et le point du milieu est le seul qui compte.**
Au repos, puis **juste au-dessus du zoom 0,67**, puis au zoom maximal.

Le pic n'est pas au zoom maximal, contrairement à ce que ce plan a d'abord
supposé. `level(for:)` engage le niveau 9 216 dès que l'écran réclame plus que
le socle, soit `2048 × zoom × 3 > 4096`, soit **zoom > 0,667** — à peine 1,6×
au-dessus du repos (0,427 sur iPhone 17). À ce zoom précis la fenêtre visible
couvre encore 603 × 1 310 pt de contenu, soit à peu près **9 × 15 = 135 tuiles**
d'un pas de 113,8 pt. Au zoom maximal, la fenêtre s'est rétrécie à 122 × 265 pt
et il n'en faut plus qu'une cinquantaine. Le pincement traverse donc son point
le plus coûteux tôt, puis redescend.

Ordres de grandeur attendus, à 1 Mio la tuile décodée plus 67 Mio de socle
(4 096² en RGBA) :

| Zoom | Niveau | Tuiles | Attendu |
|---|---|---|---|
| repos (0,427) | aucun, socle seul | 0 | ~70 Mo |
| **0,7** | 9 216 | ~135 | **~190 Mo** |
| max (3,3) | 18 432 | ~50 | ~115 Mo |

Contre 125 Mo au repos et 318 Mo au zoom 2,5 avant ce chantier : le gain tient
même au pic, mais il est bien plus mince qu'annoncé.

**Ne pas « corriger » un chiffre de cet ordre au point du milieu** — ce n'est ni
le cache ni la fenêtre qui fuient, c'est la géométrie : un niveau qui vient
d'être engagé est sur-résolu d'un facteur allant jusqu'à 2,25 et couvre tout
l'écran. Le relever, le noter dans le rapport, et me le remonter : arbitrer
entre 190 Mo au pic et une tolérance d'engagement (le `maxUpscale` de 1,5 que
ce plan a écarté) est une décision de produit, pas d'implémentation.

**En revanche, un chiffre supérieur à 150 Mo AU ZOOM MAXIMAL veut bien dire que
le cache ou la fenêtre ne se vident pas** : là, vérifier que `placed` perd ses
tuiles hors fenêtre.

**Sur les DEUX appareils, et l'iPad n'est pas une formalité ici.** `iPad Pro
13-inch (M5)` a une fenêtre bien plus grande, donc un jeu visible plus grand au
même zoom : la revue de la tâche 6 l'estime à ~140 tuiles contre ~112 sur
iPhone. Le pic s'y trouve donc plus haut, et c'est lui qui décide.

**Cette mesure porte une décision qui a été explicitement différée pour elle**
(arbitrage du 14/08 : « mesurer d'abord, décider ensuite »). La question est de
savoir si l'on garde la règle de géométrie pure — un niveau s'engage dès que
l'écran réclame plus que celui du dessous, donc jamais un pixel interpolé — ou
si l'on réintroduit une **tolérance d'engagement de 1,5×**, qui n'engagerait le
niveau 9 216 qu'à partir du zoom 1,0 au lieu de 0,667 et ferait tomber le pic
d'environ 180 à 127 Mo. Le coût de la tolérance est une bande de zoom étroite
(0,67 à 1,0) où le socle est agrandi jusqu'à 1,5× — soit ce que l'app fait déjà
aujourd'hui entre ses deux étages, et moins que le 1,88× qui a motivé ce
chantier ; au zoom maximal elle ne change rien.

Deux conséquences pratiques pour toi : **relever les trois points sur les deux
appareils et les porter dans le rapport de tâche**, et **ne rien trancher** —
ni `MapTileSet.level(for:)`, ni la valeur de `cacheLimit`, ni le comportement de
`clear()` au franchissement. Deux constats de la revue de la tâche 6 restent
ouverts en attendant ce verdict : le plafond du cache face au franchissement de
niveau, et l'écran qui redevient franchement flou un tiers de seconde à chaque
franchissement. Ce sont la même question.

Rappel des deux pièges d'instrument : `footprint` ne compte pas un raster de vignette ImageIO (sans objet ici, on ne fait plus de vignettes), et le RSS de `ps` retient longtemps les pages libérées — s'en tenir à `footprint`.

- [ ] **Step 8 : Commit**

```bash
git add NeonCompass/Core/Map/MapScrollView.swift
git commit -m "feat(carte): brancher la couche de tuiles sous les épingles

Un conteneur commun devient la cible du zoom : les tuiles dessous, les
épingles dessus, dans le même espace de contenu — donc solidaires au pixel
près pendant un pincement.

Zoom maximal 2,5 → 3,3 : au point le plus tendu on agrandit désormais de 1,10×
(20 275 px réclamés sur 18 432) au lieu de 1,88× (15 360 sur 8 192). Plus loin
et plus net à la fois.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 8 : Retirer les deux étages

C'est la contrepartie promise : le pavage n'ajoute pas une couche, il en remplace une.

**Files:**
- Modify: `NeonCompass/Core/Map/MapArtLoader.swift` (suppression de `MapArtDetail` et `MapArtDetailSelector`)
- Modify: `NeonCompass/Core/Map/MapScrollView.swift:67-78`, `:182`, `:872-923`, `:1009-1010`
- Modify: `NeonCompass/Features/Map/MapScreen.swift:83`
- Modify: `NeonCompassTests/Map/MapArtResourcesTests.swift`
- Modify: `tools/basemap/gtavi-map.mjs:248-256` (l'écriture de `manifest-vi.json`)
- Delete: `NeonCompassTests/Map/MapArtDetailTests.swift`
- Delete: `tools/basemap/reduce-mapart.mjs`
- Delete: `NeonCompass/Resources/MapArt/manifest-vi.json` — reliquat repéré à la tâche 10, faux et lu par personne
- Delete: `NeonCompass/Resources/MapArt/island-vi-reduced.png`, `island-vi-classic-reduced.png` — **déjà absents au 14/08** (la tâche 3 régénère `MapArt/` de zéro) ; le constater et passer, ne pas les recréer pour les supprimer

**Interfaces:**
- Produces: `MapArtLoader.cached(game:style:) -> UIImage?`, `isResident(game:style:) -> Bool`, `prepare(game:style:) async`. Le paramètre `detail` disparaît de partout.

- [ ] **Step 1 : Réduire `MapArtLoader`**

Supprimer `enum MapArtDetail` et `struct MapArtDetailSelector` en entier (lignes 5 à 91). Remplacer le reste par :

```swift
/// Charge le SOCLE d'une carte : une image de 4 096 px, dessinée en permanence
/// sous les tuiles.
///
/// Ce fichier portait auparavant deux étages (4 096 et 8 192 px) et un
/// sélecteur à hystérésis. Le pavage les remplace tous les deux à une
/// granularité bien plus fine — `MapTileSet` choisit un niveau parmi trois et
/// n'en charge que la fenêtre visible — et cette simplification était la
/// contrepartie annoncée du chantier, pas un effet de bord.
///
/// **Ce que coûtait l'image unique, mesuré au simulateur** (empreinte, écran
/// Carte, même code et même cadrage) : 127 Mo à 4 096 px, 208 Mo à 6 144,
/// 319 Mo à 8 192 — soit le côté au carré à 60 Mo près, ces 60 Mo étant l'app
/// elle-même. C'est ce mur des 4 octets par pixel qui interdisait d'aller
/// au-delà de 8 192 px sans pavage, et c'est lui que le pavage contourne.
///
/// UNE SEULE image en cache, délibérément : en garder deux doublerait
/// l'empreinte du socle. Le prix est un redécodage à chaque bascule
/// d'habillage, sur une action volontaire.
///
/// **Le décodage ne se fait pas dans `body`.** Il y était synchrone, sur le fil
/// principal, et coûtait 595 à 795 ms pour 8 192 px.
/// `kCGImageSourceShouldCacheImmediately` force la rastérisation DANS la tâche
/// détachée, au lieu de la laisser se déclencher au premier dessin — sans ce
/// drapeau, sortir la lecture du fil principal ne déplacerait que l'ouverture
/// du fichier et le gel resterait entier.
///
/// `@MainActor` parce que le cache est un état mutable partagé. Seul le
/// décodage s'exécute ailleurs.
@MainActor
enum MapArtLoader {
    private struct Key: Hashable {
        let game: MapGame
        let style: MapStyle
    }

    private static var cache: [Key: UIImage] = [:]
    private static var inFlight: [Key: Task<Void, Never>] = [:]

    /// Ce qui est déjà décodé, sans jamais rien décoder ici.
    ///
    /// Se rabat sur l'AUTRE habillage de la même carte plutôt que de rendre
    /// nil : les deux sortent du même cadrage, donc la substitution ne déplace
    /// pas un pixel — elle change les couleurs une fraction de seconde plus
    /// tard. Jamais l'autre CARTE, en revanche : ce serait une autre île.
    static func cached(game: MapGame, style: MapStyle) -> UIImage? {
        for style in [style] + MapStyle.allCases.filter({ $0 != style }) {
            if let image = cache[Key(game: game, style: style)] { return image }
        }
        return nil
    }

    static func isResident(game: MapGame, style: MapStyle) -> Bool {
        cache[Key(game: game, style: style)] != nil
    }

    /// Décode le socle s'il manque, hors du fil principal, puis le range.
    ///
    /// Ne rend rien : l'appelant relit `cached`. Deux appels concurrents pour la
    /// même clé partagent la même tâche.
    static func prepare(game: MapGame, style: MapStyle) async {
        let key = Key(game: game, style: style)
        if cache[key] != nil { return }
        if let running = inFlight[key] {
            await running.value
            return
        }
        let name = game.resourceName(style: style)
        let decode = Task.detached(priority: .userInitiated) { decodedImage(name: name) }
        let store = Task { @MainActor in
            if let image = await decode.value { cache = [key: image] }
            inFlight[key] = nil
        }
        // Posé avant tout point de suspension : un second appel voit la tâche
        // et l'attend au lieu de relancer le décodage.
        inFlight[key] = store
        await store.value
    }

    private nonisolated static func decodedImage(name: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "MapArt"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let decoded = CGImageSourceCreateImageAtIndex(
                  source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              )
        else { return nil }
        return UIImage(cgImage: decoded)
    }
}
```

- [ ] **Step 2 : Purger `MapScrollView`**

Quatre retraits :

1. Dans `struct MapRenderState`, supprimer `var artDetail: MapArtDetail = .overview` (ligne 72) **et** `var artGeneration: Int = 0` (ligne 78), avec leurs commentaires.

   `artGeneration` n'existait que pour faire différer l'état de rendu et forcer
   SwiftUI à rappeler `MapArtLoader.cached` — c'était un compteur écrit partout
   et lu nulle part, dont le seul lecteur réel était l'image de la ligne 182. La
   tâche 7 ayant sorti le socle de SwiftUI pour le poser en `CALayer`, il ne
   déclenche plus rien : le supprimer, pas le renommer. **Vérifier par
   `grep -rn "artGeneration" NeonCompass/` qu'il ne reste aucune occurrence.**

2. Ligne 182 : rien à faire, la tâche 7 a déjà retiré l'`Image` et son
   `MapArtLoader.cached`. Le confirmer plutôt que de le supposer — si
   l'appel est encore là, la tâche 7 est incomplète et le pavage est masqué.

3. Dans le coordinateur, supprimer `artDetailSelector` et `requestedDetail`
   (lignes 872-873) ainsi que `artGeneration` (ligne 874), et réduire :

```swift
        fileprivate func setArt(game: MapGame, style: MapStyle) {
            requestArt(game: game, style: style)
            tileLayerView?.setBase(MapArtLoader.cached(game: game, style: style)?.cgImage)
        }

        private func requestArt(game: MapGame, style: MapStyle) {
            artGame = game
            artStyle = style
            // Le garde porte sur la RÉSIDENCE, et sur elle seule. Il testait
            // d'abord « la carte demandée n'a pas changé », et c'était une
            // panne : `MapArtLoader` ne garde qu'UNE image, donc un décodage
            // lancé pour l'autre carte évince celle qui est à l'écran en
            // arrivant, sans que la carte demandée ait bougé d'un pouce. Le
            // garde sortait alors sans rien relancer et `cached` rendait nil à
            // chaque passage suivant : écran NOIR définitif, observé à la
            // tâche 7 sur un aller-retour rapide entre les deux cartes, et
            // préexistant au pavage.
            //
            // Ce garde-ci est plus bavard — tant que le socle n'est pas
            // résident, chaque passage crée une tâche. Elles sont mises en
            // commun par `inFlight` dans `prepare`, donc elles attendent le
            // même décodage au lieu d'en lancer un chacune, et elles cessent
            // dès qu'il arrive.
            guard !MapArtLoader.isResident(game: game, style: style) else { return }
            artTask?.cancel()
            artTask = Task { @MainActor [weak self] in
                await MapArtLoader.prepare(game: game, style: style)
                guard let self, game == artGame, style == artStyle else { return }
                pushArt()
            }
        }

        /// Ne pousse plus RIEN vers SwiftUI : le socle est une couche, et
        /// poser son `contents` suffit à le faire apparaître. C'est tout ce
        /// qui reste de l'aller-retour par l'état de rendu.
        private func pushArt() {
            tileLayerView?.setBase(MapArtLoader.cached(game: artGame, style: artStyle)?.cgImage)
        }
```

4. Dans `sync`, supprimer les deux lignes `state.artDetail = …` /
   `state.artGeneration = …`. Le bloc `artDetailSelector.update(…)` et l'appel
   `requestArt` par frame qui le suivait ont déjà disparu à la tâche 7 — le
   confirmer, ne pas le supposer. Le choix de niveau appartient désormais à
   `MapTileSet.level(for:manifest:)`, appelé depuis `MapTileLayerView.update`,
   et le socle est demandé par les deux appels à `setArt` (`makeUIView` ligne
   660, `updateUIView` ligne 809), jamais par frame.

- [ ] **Step 3 : Corriger l'appelant de `MapScreen`**

`NeonCompass/Features/Map/MapScreen.swift:83` :

```swift
                        Task { await MapArtLoader.prepare(game: mapGame, style: mapStyle) }
```

- [ ] **Step 4 : Supprimer les tests et fichiers devenus sans objet**

```bash
git rm NeonCompassTests/Map/MapArtDetailTests.swift
git rm tools/basemap/reduce-mapart.mjs
git rm NeonCompass/Resources/MapArt/manifest-vi.json
```

Les deux `-reduced.png` que cette étape devait supprimer ont déjà disparu
(vérifié le 14/08 — la tâche 3 régénère `MapArt/` de zéro) : le constater et
passer, surtout ne pas les recréer pour les supprimer.

`manifest-vi.json`, en revanche, est bien là et il MENT : il annonce
`pixels: 8192` et `z5` là où `island-vi.png` fait 4 096 px et sort du z6. Il
n'est lu par personne — un seul manifeste gouverne les deux cartes, et
`MapManifest.swift:9-15` le dit dans son propre commentaire. La provenance ne
se perd pas pour autant : `MapTiles/island-vi.json` porte son champ `source`.

Supprimer aussi son écriture dans `tools/basemap/gtavi-map.mjs`, sans quoi la
prochaine régénération le fait revenir. Le `writeFileSync` des lignes 248-256
emporte avec lui, et c'est vérifié plutôt que supposé :

- l'import `createHash` (ligne 16) — seul usage, ligne 253 ;
- la variable `image` (déclarée 169, assignée 229 et 244) — seule lecture,
  ligne 253. **Garder l'appel `encode(rawRgb, 'island-vi.png')` de la ligne
  244**, qui écrit le fichier : c'est l'assignation qui part, pas l'appel ;
- l'option `--size` (ligne 38) et sa mention dans le commentaire d'usage
  (ligne 5) — seule lecture, ligne 251. Elle ne gouvernait plus que ce
  manifeste.

Ce que cela ne doit PAS changer : les PNG produits, octet pour octet.
`gtavi-map.mjs` reste la référence de non-régression du z5 (Task 2, Step 8).

- [ ] **Step 5 : Réécrire le contrôle des socles**

Dans `NeonCompassTests/Map/MapArtResourcesTests.swift`, supprimer `theReducedTierIsShippedAtItsDeclaredSize` (lignes 86-123) et la remplacer par :

```swift
    /// Le socle est une image de 4 096 px, et c'est là que sa livraison se
    /// vérifie.
    ///
    /// Un socle plus grand ferait payer plus que prévu à chaque lancement — le
    /// mur des 4 octets par pixel : 4 096 px coûtent 64 Mo résidents, 8 192 en
    /// coûtent 256. Un socle plus petit se verrait au repos, où il est la SEULE
    /// chose dessinée : sous 4 096 px l'agrandissement commence avant même que
    /// les tuiles n'entrent en jeu.
    @Test func everyBaseImageIsShippedAtFourThousandNinetySix() throws {
        for game in Game.allCases {
            for style in MapStyle.allCases {
                let name = game.resourceName(style: style)
                let size = try Self.pngSize(Self.mapArt.appendingPathComponent("\(name).png"))
                #expect(size == (4096, 4096), "\(name).png fait \(size), attendu 4096 px de côté")
            }
        }
    }

    /// L'étage réduit n'existe plus : le pavage l'a remplacé. Un fichier
    /// `-reduced.png` oublié dans le dépôt ne casserait rien et ne se verrait
    /// nulle part — il ajouterait 4 Mo au paquet pour rien.
    @Test func noReducedTierSurvives() throws {
        let strays = try FileManager.default
            .contentsOfDirectory(atPath: Self.mapArt.path)
            .filter { $0.contains("-reduced") }
        #expect(strays.isEmpty, "étage réduit résiduel : \(strays.joined(separator: ", "))")
    }
```

Corriger aussi le commentaire d'en-tête de la suite, qui décrit encore trois pannes dont la troisième a changé.

- [ ] **Step 6 : Construire et lancer TOUTE la suite**

Run:
```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "Test run with|error:|failed"
```
Expected: `Test run with N tests` avec N ≥ 631 (le compte d'avant le chantier), aucun échec. Le compte a changé : `MapArtDetailTests` en enlève, `MapTileSetTests` et `MapTileResourcesTests` en ajoutent. **Noter le nouveau compte.**

Run: `git status --short NeonCompass/Resources/Localizable.xcstrings`
Expected: rien. Si le fichier apparaît modifié, restaurer : `git checkout -- NeonCompass/Resources/Localizable.xcstrings`.

- [ ] **Step 7 : Commit**

```bash
git add -A NeonCompass NeonCompassTests tools/basemap
```

Un crochet de dépôt rejette tout appel `bash` qui contient le texte d'un
message de commit : écrire le message dans un fichier avec l'outil Write, puis
`git commit -F <fichier>`.

```
refactor(carte): retirer les deux étages, remplacés par le pavage

MapArtDetail, MapArtDetailSelector, son hystérésis, les deux fichiers
-reduced.png et reduce-mapart.mjs disparaissent : MapTileSet choisit un niveau
parmi trois et n'en charge que la fenêtre visible, ce que deux étages
d'image entière ne pouvaient pas approcher.

MapArtLoader se réduit à « décoder le socle, hors du fil principal ».

En chemin, deux reliquats. Le garde de requestArt testait « la carte demandée
n'a pas changé » avant la résidence, ce qui laissait l'écran noir DÉFINITIF
après un aller-retour rapide entre les deux cartes : un seul socle tient dans
le cache, celui qui arrive évince celui qui est affiché, et plus rien ne le
redemandait. Il porte désormais sur la résidence seule. Et manifest-vi.json,
que personne ne lit, annonçait 8 192 px et z5 pour une image de 4 096 px tirée
du z6 : supprimé, avec l'écriture qui le reproduisait.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

---

## Task 9 : Mesures, documentation, PR

**Files:**
- Modify: `tools/basemap/SOURCES.md`
- Modify: `CLAUDE.md` (section Commands, si le pavage change la manœuvre de reconstruction)
- Modify: `.github/workflows/content.yml:99`

- [ ] **Step 1 : Brancher le nouveau test Node sur la CI**

`.github/workflows/content.yml`, ligne 99 :

```yaml
        run: node --test tools/basemap/gtav-poi-ids.test.mjs tools/basemap/gtavi-restyle.test.mjs tools/basemap/gtavi-transform.test.mjs
```

Run: `node --test tools/basemap/gtav-poi-ids.test.mjs tools/basemap/gtavi-restyle.test.mjs tools/basemap/gtavi-transform.test.mjs`
Expected: tout passe. Le test de découpage est le seul filet du pavage côté outil — s'il n'est pas dans la CI, une constante d'échelle mal transposée ne se verra qu'à l'œil, plusieurs mois plus tard.

- [ ] **Step 2 : Mesurer le poids livré**

Run:
```sh
du -sh NeonCompass/Resources/MapTiles NeonCompass/Resources/MapArt
find NeonCompass/Resources/MapTiles -name '*.png' | wc -l
```

Expected: relever les trois chiffres. La prévision est de 30 à 40 Mo par habillage, soit 60 à 80 Mo pour les deux, contre 15,1 Mo aujourd'hui — elle est extrapolée d'un maître agrandi, donc elle est un plancher. **Si le total des deux cartes dépasse 100 Mo**, s'arrêter et le signaler plutôt que de trancher seul : c'est une décision de produit, et la porte de sortie est Supabase Storage pour le niveau le plus fin.

**Les tuiles étant déjà livrées, cette étape MESURE au lieu de prévoir.** Au
14/08, sur le dépôt : `du -sh NeonCompass/Resources/MapTiles` donne **44 Mo**
(21 Mo pour `island-vi`, 23 pour `island-vi-classic`, 2 351 PNG), et
`NeonCompass/Resources/MapArt` **8,0 Mo** — dont 4,9 de carte GTA V, qui reste.
Un écart notable avec ces chiffres veut dire que la régénération a produit
autre chose : le chercher avant d'aller plus loin. Le seuil de produit à 100 Mo
de tuiles reste très loin ; ne pas remonter pour un binaire de cet ordre, il est
déjà accepté (décision du 14/08).

⚠️ Ne PAS mesurer le poids sur le `.app` de Debug — il pesait 109 Mo à la
tâche 4, ce qui n'est pas une taille de livraison : pas de compression de
paquet, pas d'amincissement. Le chiffre qui compte est celui des ressources
dans le dépôt, plus le rapport de taille d'App Store Connect le jour venu.

- [ ] **Step 3 : Mettre à jour `SOURCES.md`**

Ajouter une section décrivant le nouveau pipeline, et faire évoluer « Ce qui reste à trancher » :

```markdown
## Pavage z6 (depuis le 2026-08-12)

`gtavi-tiles.mjs` remplace `gtavi-map.mjs` pour la carte de Leonida. Grille
source z6 : 79 × 79 tuiles de 256 px, soit 20 224 px, complétés en océan à
20 480 px — le double exact du z5, ce qui rend toute la géométrie du pipeline
z5 valable au facteur 2. Le traitement passe par quatre quadrants de 10 240 px
avec un halo de 1 024 px, en deux passes : le sondage de la grille de
coordonnées somme des lignes entières et ne peut pas se calculer par quadrant.

Livré : un socle de 4 096 px dans `MapArt/`, et deux niveaux de tuiles de
512 px (9 216 / 18 432) dans `MapTiles/<nom>/<côté>/`. Le niveau le plus fin
s'arrête à 18 432 parce que le recadrage de la tâche 10 n'apporte que 19 068 px
de détail réel — au-delà on interpolerait, et on ferait payer le poids de pixels
inventés.

`gtavi-map.mjs` reste pour la carte de référence GTA V et comme trace du
chemin z5 ; `reduce-mapart.mjs` a été supprimé avec les deux étages.

Le socle n'est pas un niveau de plus : il est dessiné en permanence sous les
tuiles, et `level(for:)` ne rend nil que tant que l'écran ne réclame pas plus
que ses 4 096 px. Ce seuil dépend de l'ÉCRAN et non du seul zoom —
`contentSize × zoom × displayScale > 4 096`, donc zoom > 0,667 sur un appareil
3× et > 1,0 sur un 2× comme l'iPad Pro 13. Aucun document ne doit l'écrire
comme une constante.

### Ce qui reste à trancher

Les deux `*-classic.png` et leur pavage sont l'œuvre d'un tiers, sans licence
trouvée. Les trois options restent ouvertes — attribuer, ne plus embarquer que
le restylage, redessiner. **Le bon moment pour écrire à l'auteur de YANIS est
avant la v15** : la carte va être mise à jour, la question se reposera de toute
façon, et une demande faite avant vaut mieux qu'une régularisation après.
```

**Commiter la documentation avant d'aller plus loin** — le Step 7 reprend
l'arbre de `feat/carte-pavage-z6`, donc ce qui n'y est pas commité serait
perdu. Message par fichier (`git commit -F`), le crochet du dépôt rejette
`git commit -m`.

- [ ] **Step 4 : Contrôler l'iPad**

L'iPad affiche à 2× — donc son seuil d'engagement est à zoom > 1,0 et non
> 0,667 comme sur iPhone : `contentSize × zoom × displayScale > base`, le
seuil dépend de l'écran et n'est pas une constante.

**L'empreinte est déjà mesurée** (tâche 7, sur les deux appareils, trois points
de zoom chacun) : ne pas la refaire, la reprendre. Ce Step ne contrôle plus que
l'AFFICHAGE : la carte se dessine au repos et au zoom, sans carré manquant.

Run:
```sh
BUILT=$(xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2; exit}')
rm -rf "$BUILT/NeonCompass.app/MapArt" "$BUILT/NeonCompass.app/MapTiles"
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build 2>&1 | tail -3
xcrun simctl install BD8F6F17-90B0-42CD-BE05-10866A1BE21D "$BUILT/NeonCompass.app"
xcrun simctl launch BD8F6F17-90B0-42CD-BE05-10866A1BE21D co.antoineteston.NeonCompass
xcrun simctl io BD8F6F17-90B0-42CD-BE05-10866A1BE21D screenshot /tmp/carte-ipad.png
```

Expected: la carte s'affiche au repos et au zoom, sans carré manquant.

- [ ] **Step 5 : Poser une épingle, pour de vrai**

C'est l'usage qui a motivé tout le chantier — « c'est ici que tous les POI
seront soumis » — et **c'est la seule vérification qui fermerait vraiment le
correctif de visée** (I1 de la tâche 7). Ce correctif, `hostingController.safeAreaRegions = []`,
n'a jamais été prouvé à l'écran : il agit là où naissaient les 14 pt de
décalage, mais son effet sur le dessin n'a été qu'argumenté. Ici on le voit ou
on ne le voit pas.

Dans le simulateur iPhone : appui long sur la carte pour ouvrir le placement,
zoomer à fond, taper pour viser, puis **glisser l'épingle en démarrant en plein
centre** — c'est ce geste précis que le décalage refusait. Vérifier que
l'épingle tombe où le doigt l'a posée, que le glisser est accepté, et que la
carte sous elle est nette.

**Piloter le simulateur uniquement par `xcrun simctl` et `cliclick`.** Jamais
`osascript`, AppleScript, « System Events » ni `screencapture` : une tâche
antérieure a ainsi agi sur le vrai bureau et capturé du contenu privé sans
rapport. Règle absolue.

Run: `xcrun simctl io BD68054B-7C1F-48C8-B792-AB2C87C4B7A3 screenshot /tmp/carte-placement.png`
Expected: la visée `.place` cadre à un zoom d'au moins 1,28 sur iPhone — donc bien au-dessus du seuil d'engagement, donc sur des tuiles et non sur le socle. La netteté sous l'épingle est la preuve que le chantier a atteint son but.

- [ ] **Step 6 : Suite complète, une dernière fois, sur les deux appareils**

⚠️ **`xcodebuild test` se fige APRÈS avoir écrit `Test run with N tests`** — 16 minutes observées le 14/08 sans qu'il rende la main. Et **jamais deux `xcodebuild` en même temps** sur le même DerivedData : trois runs concurrents, dont un faisant `simctl shutdown` du simulateur des deux autres, ont bloqué la tâche 8 pendant une heure. Lancer en arrière-plan, sonder le journal jusqu'à la ligne de résultat, puis tuer :

```sh
run() {
  xcodebuild -scheme NeonCompass -destination "$1" test > "$2" 2>&1 &
  for i in $(seq 1 115); do grep -q "Test run with" "$2" && break; sleep 5; done
  grep -nE "Test run with|✘" "$2" | head -5
  pkill -9 -f "xcodebuild -scheme NeonCompass"
}
run 'platform=iOS Simulator,name=iPhone 17'                /tmp/t9-iphone.log
run 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'    /tmp/t9-ipad.log
git status --short
```
Expected: **642 tests / 84 suites** sur les deux, aucun échec, et `git status` ne montre pas `Localizable.xcstrings`.

- [ ] **Step 7 : Écraser les commits porteurs de tuiles**

**Décision de l'utilisateur : écraser AVANT de pousser.** Quatre commits non
contigus portent les 2 351 PNG (`2418f97`, `673274b`, `c5c281d`, `fee7f86`) et
`.git` pèse déjà 134 Mo ; les pousser tels quels ferait porter à la
télécopie chaque état intermédiaire des tuiles. `git rebase -i` n'est pas
disponible dans cet environnement : passer par une branche neuve.

```sh
git rev-parse HEAD > /tmp/t9-head            # filet : l'état à retrouver
git checkout -b feat/carte-pavage-z6-plat perf/carte-chargement-deux-etages
git checkout feat/carte-pavage-z6 -- .       # l'arbre final, en une fois
git status --short | head
```

Commiter cet arbre en **deux** commits, pas un : les tuiles d'un côté, tout le
reste de l'autre, pour qu'une relecture de code ne se noie pas dans 2 351
fichiers binaires.

```sh
git add NeonCompass/Resources/MapTiles NeonCompass/Resources/MapArt
git commit -F <fichier-message-1>
git add -A
git commit -F <fichier-message-2>
```

**Contrôle avant de continuer, non négociable** — l'arbre écrasé doit être
identique à l'original, sinon on a perdu du travail :

```sh
git diff --stat feat/carte-pavage-z6 feat/carte-pavage-z6-plat
```
Expected: **aucune sortie.** Une seule ligne de différence veut dire que
l'écrasement a mangé quelque chose : s'arrêter et le signaler.

- [ ] **Step 8 : Pousser et ouvrir la PR**

```bash
git push -u origin feat/carte-pavage-z6-plat
```

La branche est **empilée** : sa base est `perf/carte-chargement-deux-etages`
(PR #110), elle-même sur `feat/carte-vi-restylee` (PR #109), et **aucune des
deux n'est fusionnée**. Ouvrir la PR sur la base `perf/carte-chargement-deux-etages`,
jamais sur `main`.

Ce que le corps doit porter, et rien de moins — c'est la seule trace que
liront ceux qui n'ont pas vécu le chantier :

1. **Ce qui est gagné, et c'est le but tenu :** libellés lisibles à 1:1 au zoom
   maximal (`CROSSTOWN (OVERTOWN)`, `DOWNTOWN`, micro-codes `T1/40`), aucune
   couture (contraste inter-colonnes 3,9 et 2,3 aux frontières du niveau
   18 432, contre une médiane de 5,8 — les frontières sont donc MOINS marquées
   que la moyenne). Zoom maximal de 2,5 à 3,3 avec sa dérivation.
2. **La promesse mémoire est retirée, dites-le franchement.** Mesuré : iPhone
   125,9 au repos / **332,4 au pic** / 207,3 au zoom maximal ; iPad 127,2 /
   **390,5** / 309,4. Avant le chantier : 125 au repos, 318 au zoom 2,5. Le pic
   n'est pas au zoom maximal mais au MILIEU du pincement, quand un niveau
   fraîchement engagé est sur-résolu et couvre tout l'écran. Ce n'est pas une
   fuite : le raster CG retombe de 103,6 à 40,7 Mo au zoom maximal. Arbitré par
   l'utilisateur le 14/08 : on accepte.
3. **Un bogue de VISÉE préexistant est corrigé au passage, et c'est peut-être
   le plus important pour l'usage.** L'ancienne vue hôte héritait des
   `safeAreaInsets` du `UIScrollView`, donc SwiftUI décalait tout le dessin de
   (62−34)/2 = 14 pt pendant que les gestes lisaient l'espace non décalé. Or
   `placementHitRadius = 32/zoomScale` valait 12,8 pt de contenu à l'ancien zoom
   maximal — MOINS que le décalage : l'épingle de placement visible était
   entièrement hors de son propre cercle de préhension, et un glisser démarré en
   plein centre était refusé.
4. **Une panne d'écran noir permanent est corrigée**, elle aussi préexistante :
   `requestArt` sortait sur « la carte demandée n'a pas changé » avant de tester
   la résidence, or un seul socle tient dans le cache et celui qui arrive évince
   celui qui est affiché. Le garde porte désormais sur la résidence seule.
   **Résidu assumé à écrire** : au changement de carte, le socle est nil
   ~120 ms — un noir TRANSITOIRE remplace le noir définitif. Sans cette phrase,
   le premier qui le verra rouvrira la panne comme régression.
5. **Poids mesurés**, jamais estimés : 44 Mo de tuiles (2 351 PNG), 8,0 Mo de
   `MapArt/` dont 4,9 pour la carte GTA V. L'élargissement de la tâche 10 a
   coûté +1,2 Mio, pas les ~10 Mo annoncés en séance.
6. **Le seuil d'engagement n'est pas une constante** : il vaut `contentSize ×
   zoom × displayScale > base`, soit zoom > 0,667 en ×3 (iPhone) mais > 1,0 en
   ×2 (iPad Pro 13 M5). Tout document qui l'annonce comme un nombre unique est
   faux.
7. Le rejet motivé de `CATiledLayer`, et le compte de tests (642 / 84 suites).
8. **Ce qui n'est pas vérifié**, à dire plutôt qu'à taire : le PAYSAGE, sur
   aucun des deux appareils. `simctl` n'a pas de commande de rotation et la
   règle du projet interdit de piloter le simulateur autrement.

Terminer par :

```
🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

---

## Self-Review

**Couverture de la spec.** Format PNG palette-256 conservé (tâches 1 et 3) ; socle + tuiles (3, 6) ; insertion sous le `UIHostingController` (7) ; suppression de `MapArtDetail`/`MapArtDetailSelector` (8) ; socle produit par le nouveau générateur (3) ; 8 192 px hors du paquet (8) ; zoom 3,3 (7) ; tuiles uniformes omises (3, 6) ; pipeline par quadrants avec contrôle de non-régression octet pour octet (2) ; position IP et `SOURCES.md` (9) ; les trois familles de tests (4, 5) ; les trois risques (poids en 9, fondu en 7, cycle de vie en 6).

**Trois écarts assumés par rapport à la spec, tous chiffrés ici :**

1. **Deux niveaux de tuiles et non quatre, et 16 384 px et non 20 480.** La spec descendait jusqu'à z3 (2 528 px) parce qu'elle supposait que le niveau le plus grossier devait couvrir le repos. Le socle de 4 096 px le couvre mieux : au repos toute la carte est visible, donc engager un niveau y coûterait ses 256 tuiles (256 Mo), plus cher que l'image unique qu'on remplace. D'où `level(for:)` qui rend nil sous 4 096, et d'où le troisième palier de la chaîne — 4 096 — servi comme socle plutôt que pavé. Quant au plafond : le recadrage n'apporte que **17 516 px de détail réel**, donc un niveau à 20 480 aurait interpolé 17 % de pixels inventés et fait payer leur poids. 16 384 = 512 × 32 est le multiple de tuile immédiatement en dessous, et garde le même rapport de rééchantillonnage que le z5 livré (8 758 → 8 192).

   **Révisé le 14/08 par la tâche 10, et la règle est plus intéressante que le nombre.** Élargir le cadre à 19 068 px déplace le plafond, puisque c'est le cadre qui borne le détail réel. Le niveau le plus fin devient **18 432 = 512 × 36**, et il se dérive de deux contraintes plutôt que d'un choix : rester ≤ 19 068, pour ne jamais interpoler ; et être un multiple **pair** de 512, pour que sa moitié tombe elle aussi sur la grille de tuiles. 512 × 37 = 18 944 satisfait la première et viole la seconde. Les deux niveaux livrés sont donc **9 216 et 18 432**, 1 296 tuiles chacun, et l'île rendue à 11 996 px — 3 % de mieux qu'avant l'élargissement, pour **+1,2 Mio mesurés** et non les ~10 Mo annoncés en séance. L'erreur valait d'être notée : elle venait d'avoir mis à l'échelle la charge utile par le rapport de pixels (1,266) alors que ce qui grandit est la TOILE. Le surcroît de surface est de l'océan, qui devient des tuiles uniformes jamais écrites. Le socle de 4 096 px et le `level(for:) == nil` sous 4 096 sont inchangés : ils ne dépendent pas du cadre.
2. **Pavage manuel et non `CATiledLayer`** — déjà porté dans la spec (commit `6e2a628`).
3. **Un cache de 48 tuiles remplace l'hystérésis.** La spec supprimait l'hystérésis sans dire ce qui empêche un pincement de redécoder à chaque passage de seuil. Le cache le fait, et il se teste par le compte de tuiles plutôt que par un comportement temporel.

**Cohérence des types.** `MapArtLoader.cached/isResident/prepare` perdent `detail:` en tâche 8, et les trois appelants sont corrigés dans la même tâche (`MapScrollView:182`, `:902`, `:905`, `MapScreen:83`). `artGeneration` devient `baseGeneration` partout d'un coup (déclaration, `pushArt`, `sync`). `MapTileSet.level(for:manifest:)` prend des pixels affichables et non un zoom — les deux appelants (`MapTileLayerView.update`, les tests) passent bien le résultat de `displayablePixels`. `MapTileManifest.Level.side` est un `Int` partout, jamais un `CGFloat`.

**Points où l'implémenteur devra décider, et c'est normal :** la forme exacte du prélèvement de `classicRgb` (tâche 2, step 4 — à l'intérieur ou à l'extérieur de `eraseAndDash` ; le contrôle octet pour octet du step 6 tranche), et le contenu des trois vignettes de contrôle visuel (tâche 3, step 5 — le plan dit quoi regarder, pas où exactement).

**Ce qui ne se prouve nulle part, et qu'il faut savoir en entrant.** Les constantes du pipeline ont été réglées à la main contre le z5 réel. La tâche 2 prouve qu'à l'échelle 1 elles reproduisent le z5 octet pour octet, et que le découpage en quadrants est neutre. Elle **ne prouve pas** que leur transposition au facteur 2 est juste : il n'existe pas de z6 de référence à comparer. C'est pourquoi la tâche 3 empile quatre contrôles indirects — le compte d'effacement, qui doit quadrupler exactement ; le nombre de traits de grille, qui doit doubler exactement ; la répartition des classes, à ±3 points ; la boîte englobante, à ±128 px, sa borne nord mesurée par densité — et un examen à l'œil de trois vignettes. Aucun n'est une preuve, les cinq ensemble attrapent les erreurs qui comptent.

**Deux de ces quatre contrôles ont été écrits faux**, et l'exécution l'a montré : le compte de grille attendait 52 et 76 alors que `gridCenters` compte des pixels et non des traits, donc 104 et 152 ; et la borne nord de la boîte englobante se lisait sur le premier pixel non-océan venu, qui est un éclat isolé aux deux échelles — un pixel unique à `y=1174` en z5, quand la côte est à 1249. Les deux sont corrigés ci-dessus. La leçon vaut d'être gardée : **un contrôle indirect qui échoue accuse le code, mais c'est une fois sur deux le contrôle qui a tort** — et on ne le distingue qu'en allant mesurer la chose elle-même, jamais en raisonnant depuis le contrôle.

---

## Task 10 : élargir les bordures et rendre tout point centrable

**Ajoutée en cours d'exécution**, après un constat d'usage : la navigation
bute à l'extrême nord et à l'extrême sud. Deux causes distinctes, une par
bout de la chaîne.

**Cause 1, le cadrage.** Le crop est forcé en carré et se fait plaquer contre
le bord droit de la source. Il ne reste alors que `margin = 80` px d'océan au
nord et au sud, contre 594 à l'est et 1958 à l'ouest — un déséquilibre de 7×,
et 19 pt à l'écran une fois ramenés dans les 2048 pt d'espace de contenu.

**Cause 2, l'app.** `MapGeometry.centeringInsets` ne rend une marge que
lorsque le contenu mis à l'échelle est PLUS PETIT que la vue, donc uniquement
au zoom de repos. Dès qu'on zoome, l'inset retombe à 0 et le défilement bute
pile sur le bord de l'image : un POI côtier ne peut jamais être amené au
centre. C'est la précision du geste de soumission qui en dépend, pas le
confort.

**Fenêtre de tir.** Les coordonnées de POI sont normalisées SUR LE CROP.
Aujourd'hui un seul POI porte une position (`poi_sample_lighthouse`, un
échantillon) : le recadrage coûte une valeur à remapper. Dès que les vraies
épingles seront posées, il coûtera une migration de données.

**Ordre imposé.** Cette tâche s'exécute **immédiatement après la tâche 3 et
avant la tâche 4**, malgré son numéro. Après la 3, parce que recadrer change
le côté de la pyramide (19068 au lieu de 17516) et que la tâche 3 doit
d'abord prouver le pipeline sur la géométrie contre laquelle il a été réglé.
Avant la 4, parce que la tâche 4 écrirait sinon son test d'intégrité du
pavage contre des dimensions périmées.

Changer la marge change la sortie z5 de `gtavi-map.mjs` : cela invalide
**volontairement** le contrôle d'exactitude d'octets, qui est le seul filet
prouvant que le refactor de la tâche 2 n'a rien altéré. Il doit rester valide
jusqu'à ce que la tâche 3 le franchisse, et n'être re-calibré qu'ensuite
(Step 8).

**Files:**
- Modify: `tools/basemap/gtavi-map.mjs:196` (la marge)
- Modify: `tools/basemap/gtavi-tiles.mjs` (la constante `CROP`, doublée)
- Modify: `content/poi/poi_sample_lighthouse.json` (la position remappée)
- Modify: `NeonCompass/Core/Map/MapGeometry.swift` (le débord)
- Modify: `NeonCompass/Resources/MapArt/` (les sorties régénérées)
- Test: `NeonCompassTests/Map/MapGeometryTests.swift`

**Interfaces:**
- Consomme : la bbox z5 relevée par le pipeline, `x 3440..9645, y 1174..9771`
  dans une source de 10240².
- Produit : un crop de **9534×9534 en (706, 706)**, donc un `CROP` z6 doublé
  de `left 1412, top 1412, side 19068`.
- Produit, et les tâches 4 et 5 en dépendent : `LEVELS = [18432, 9216]`, soit
  **36 et 18 tuiles par côté**. Le test de la tâche 4 les assène tels quels ;
  les fixtures de la tâche 5 restent volontairement en 8 192 / 16 384, qui
  sont des nombres de lisibilité et non le livré.

- [ ] **Step 1 : dériver la marge, sans nombre magique**

`margin = 468` est un nombre magique : il vaut exactement ce que la source
autorise sous l'île, et si la bbox bougeait d'un pixel le carré serait rogné
en silence, sans rien casser de visible. L'écrire comme ce qu'il est — la
plus grande marge qui garde le nord et le sud symétriques :

```js
  // La plus grande marge qui garde nord et sud SYMÉTRIQUES. Le carré force le
  // crop contre le bord droit de la source, ce qui écrasait la marge verticale
  // à 80 px — 19 pt à l'écran, sept fois moins qu'à l'est, et pas de quoi
  // amener au centre une épingle posée sur la côte nord ou sud.
  const margin = Math.min(bMinY, H - 1 - bMaxY);   // 468 sur la source actuelle
```

- [ ] **Step 2 : relever le nouveau cadrage, sans écraser les socles**

**Attention au piège, il a failli être écrit dans ce plan.** `gtavi-map.mjs` ne produit plus les fichiers embarqués : depuis le pavage z6, `MapArt/island-vi*.png` sont les **socles de 4 096 px** que `gtavi-tiles.mjs` découpe avec la pyramide. Le lancer sur le dossier embarqué y écrirait du z5 à 8 192 px, désaccordé du pavage. Il ne sert plus qu'à *dériver* le cadrage, et sa sortie va dans `tools/basemap/out/`.

```sh
node tools/basemap/gtavi-map.mjs --restyle --classic
```

`--classic` n'est pas facultatif : c'est cette exécution que le Step 8 hache
pour re-calibrer le filet de non-régression, et il lui faut les trois
fichiers.

Attendu dans le journal, exactement :
`île : x=3440..9645 y=1174..9771 → crop 9534×9534 (océan ouest 2734px / est 594px)`

- [ ] **Step 2 bis : reporter le cadrage doublé dans le pavage**

C'est `CROP` qui gouverne ce qui est réellement livré. Dans `tools/basemap/gtavi-tiles.mjs` :

```js
const CROP = { left: 706 * SCALE, top: 706 * SCALE, side: 9534 * SCALE };
```

Soit `left 1412, top 1412, side 19068`. Mettre à jour le commentaire au-dessus : le cadrage n'est plus celui « du z5 livré », c'est celui que `gtavi-map.mjs` dérive de la bbox avec la marge maximale symétrique.

- [ ] **Step 2 ter : monter le niveau le plus fin à 18 432**

Élargir le cadre à définition constante rétrécirait l'île à l'écran : 12 410 px
de large dans 19 068 rendus à 16 384 donnent 10 663 px, contre 11 608
aujourd'hui — 8 % de moins, à rebours du but même du chantier. Décision
utilisateur du 14/08 : monter le niveau plutôt que subir la perte.

```js
// Step 6 : découper la pyramide. Le recadrage fait 19 068 px ; le niveau le
// plus fin est 18 432 (512×36) — c'est le PLUS GRAND qui satisfasse les deux
// contraintes à la fois : rester sous 19 068, donc réduire et jamais
// interpoler des pixels qui n'existent pas ; et être un multiple PAIR de 512,
// pour que sa moitié tombe elle aussi sur la grille. 512×37 = 18 944 passe la
// première et échoue la seconde (9 472 n'est pas un multiple de 512).
const TILE = 512;
const LEVELS = [18432, 9216];   // du plus fin au plus grossier
```

L'île est alors rendue à 11 996 px, soit 3 % de plus qu'avant l'élargissement :
les bordures ne coûtent plus de définition. Compter 1 296 tuiles par niveau au
lieu de 1 024, et un binaire autour de 64 Mo au lieu de 54.

Puis régénérer la pyramide entière — c'est la commande longue, en arrière-plan :

```sh
node tools/basemap/gtavi-tiles.mjs --style normal
```

Vérifier que `checkCrop` passe toujours : ses trois bords sûrs sont exprimés en coordonnées globales et ne dépendent ni du cadrage ni des niveaux, et le plancher du bord nord est `CROP.top`, qui vaut désormais 1412 — encore largement au-dessus de la côte mesurée à 2 667.

Enfin, relire le journal : `cutLevel` doit annoncer **18432** et **9216**, et le
compte de positions doit être 1 296 à chaque niveau fin. Un journal qui parle
encore de 16 384 signifie que la régénération a servi un cache ou que `LEVELS`
n'a pas été relu.

Nord et sud valent alors 468 px chacun. L'est reste à 594 : la source n'a rien
de plus, aucun recadrage ne l'élargira jamais.

**Ces 468 px sont un plancher, pas la marge réelle**, et c'est voulu. La
marge se dérive de `bMinY = 1174` et `bMaxY = 9771`, or ces deux bornes sont
posées par des éclats de classification isolés et non par la côte — mesuré au
nord : `bMinY` porte un seul pixel, la côte n'arrive qu'à 1249. L'océan
réellement visible au-dessus du rivage vaut donc `1249 - 706 = 543` px, et non
468. L'erreur va dans le bon sens : on ne peut que se retrouver avec plus
d'océan que calculé, jamais moins. Ne « corrige » pas la marge en la
recalculant depuis la densité — le recadrage doit rester dérivé de la même
`bbox` que le reste du pipeline, sous peine de dériver de quelques pixels à
chaque régénération.

- [ ] **Step 3 : remapper l'unique POI positionné**

Le point global ne bouge pas ; seule sa normalisation change de repère.
`content/poi/poi_sample_lighthouse.json` :

```json
  "position": {
    "x": 0.7531,
    "y": 0.4216
  }
```

(anciennement `0.7312` / `0.4147` — global `(7885.8, 4725.9)` dans les deux
repères, vérifier ce report avant de le croire.)

- [ ] **Step 4 : le test du débord, qui doit d'abord échouer**

```swift
@Test("Tout point de la carte peut être amené au centre, même zoomé")
func overscrollAllowsCenteringAnyPoint() {
    let content = CGSize(width: 2048, height: 2048)
    let bounds = CGSize(width: 402, height: 874)
    let insets = MapGeometry.centeringInsets(contentSize: content, zoomScale: 3.3, in: bounds)
    // Le coin supérieur gauche du contenu doit pouvoir atteindre le centre.
    #expect(insets.top >= bounds.height / 2)
    #expect(insets.left >= bounds.width / 2)
}
```

- [ ] **Step 5 : le faire échouer pour de vrai**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/MapGeometryTests
```

Attendu : ÉCHEC, `insets.top` valant 0. Lire la ligne `Test run with N tests`
— cibler un test seul ne lance rien et rapporte `TEST SUCCEEDED`.

- [ ] **Step 6 : le débord**

Le plancher de centrage s'ajoute au centrage existant, il ne le remplace pas :
au repos la carte reste centrée, une fois zoomée elle gagne de quoi amener
n'importe quel point au milieu.

```swift
    static func centeringInsets(contentSize: CGSize, zoomScale: CGFloat, in bounds: CGSize) -> ContentInsets {
        let scaledWidth = contentSize.width * zoomScale
        let scaledHeight = contentSize.height * zoomScale
        // Plancher de débord : sans lui l'inset retombe à 0 dès que le contenu
        // dépasse la vue, le défilement bute sur le bord de l'image, et une
        // épingle côtière ne peut jamais être amenée au centre. C'est la
        // précision du geste de soumission qui en dépend.
        let horizontal = max((bounds.width - scaledWidth) / 2, bounds.width / 2)
        let vertical = max((bounds.height - scaledHeight) / 2, bounds.height / 2)
        return ContentInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }
```

- [ ] **Step 7 : reprendre les tests, y compris ceux qu'on vient de changer**

`centeringInsets` a d'autres appelants et d'autres tests — le repos doit
rester centré au pixel près. Lancer la suite entière, pas la seule nouvelle :

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Vérifier `git status` avant de commiter : `xcodebuild test` réécrit parfois
`NeonCompass/Resources/Localizable.xcstrings`, qu'il ne faut pas emporter.

- [ ] **Step 8 : re-calibrer le contrôle de non-régression**

L'exactitude d'octets à z5 portait sur l'ancien cadrage : elle est désormais
caduque **par construction**, puisque le Step 1 change la marge dont ce
cadrage se dérive. La remplacer par sa version courante.

**Ne pas hacher les fichiers de `MapArt/`** : ils ne sont plus la sortie de
`gtavi-map.mjs`. Ce sont les socles de 4 096 px du pavage, et les hacher
ferait porter le filet de non-régression de `gtavi-transform.mjs` sur des
fichiers qu'il ne produit pas — un contrôle qui ne peut plus rien détecter.
Ce sont les fichiers de `out/` qui font foi, ceux que le Step 2 vient
d'écrire :

```sh
shasum -a 256 tools/basemap/out/island-vi.png \
              tools/basemap/out/island-vi-classic.png
```

**Le troisième fichier a disparu du filet, et c'est voulu.** `out/manifest-vi.json`
en faisait partie jusqu'à la tâche 8, qui supprime l'écriture qui le produisait ;
son empreinte, notée au registre, n'est plus reproductible. Le contrôle porte
donc sur DEUX fichiers — les deux PNG, c'est-à-dire les pixels, qui sont ce
qu'il existe pour protéger.

Reporter les empreintes dans le registre SDD, en une ligne chacune —
`out/` est ignoré par git, donc le registre est le seul endroit où la
référence survit. Rejouer ensuite `node tools/basemap/gtavi-map.mjs
--restyle --classic` et vérifier que les trois empreintes retombent, ce qui
prouve d'un coup que le pipeline est déterministe et que la référence notée
est la bonne.

Noter aussi, sans y toucher ici : `NeonCompass/Resources/MapArt/manifest-vi.json`
est un reliquat. Il annonce `"pixels": 8192` et `z5`, deux affirmations
fausses depuis le pavage, et **personne ne le lit** — `MapManifest.swift:9-15`
dit explicitement qu'un seul manifeste gouverne les deux cartes. Son retrait
appartient à la tâche 8, avec le reste du code mort ; l'inscrire au registre
plutôt que l'emporter ici.

- [ ] **Step 9 : commit**

Ajouter les cinq fichiers touchés, **plus les deux dossiers de ressources
régénérés** — `NeonCompass/Resources/MapArt/` (les socles) et
`NeonCompass/Resources/MapTiles/` (les ~2 000 tuiles et les deux manifestes).
Le second est facile à oublier : c'est pourtant lui qui porte la quasi-totalité
du recadrage. Avant de commiter, vérifier avec `git status --porcelain
NeonCompass/Resources/MapTiles | wc -l` que le compte de fichiers touchés est
de l'ordre du millier et non de deux ; et que `git status` ne rapporte pas
`Localizable.xcstrings` modifié par la suite de tests du Step 7.

Composer le message ainsi (sujet, puis les deux causes, puis la ligne de
co-autorat imposée par le dépôt) :

> `feat(carte): équilibrer les marges d'océan et rendre tout point centrable`
>
> Le cadrage carré se plaquait contre le bord droit de la source et ne
> laissait que 80 px d'océan au nord et au sud, contre 594 à l'est — 19 pt à
> l'écran. La marge se dérive maintenant de la source elle-même.
>
> Élargir le cadre à définition constante aurait rétréci l'île de 8 % à
> l'écran, à rebours du but du chantier. Le niveau le plus fin monte donc à
> 18 432 — le plus grand multiple pair de 512 qui reste sous les 19 068 px du
> cadre, donc sans jamais interpoler. L'île y gagne 3 % contre ~10 Mo.
>
> Côté app, l'inset de centrage retombait à 0 dès qu'on zoomait : le
> défilement butait sur le bord de l'image et une épingle côtière ne pouvait
> pas être amenée au centre.
>
> `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`
