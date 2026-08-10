# Identité et refus dans la veille — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Une URL déjà couverte n'engendre plus de seconde entrée d'actu, et un refus éditorial n'est plus rejoué au run suivant.

**Architecture:** Le verrou vit à la CONVERGENCE — `materializeNews`, qui tourne après le merge — et non à la récolte, où deux sessions concurrentes liraient toutes deux « URL non couverte ». Le registre des URL ne s'écrit pas : il est déjà l'inbox. Le seul état neuf est `content/inbox/refus.json`, écrit par le geste « Écarter » qui existe déjà (`deleteDraft`), lu par `cli.js` et passé aux modules purs.

**Tech Stack:** Node 22, ESM, `node:test` + `node:assert/strict`. Aucune dépendance nouvelle.

## Global Constraints

- Spec de référence : `docs/superpowers/specs/2026-08-10-veille-identite-et-refus-design.md`.
- **Tests : `node:test`, jamais un framework tiers.** Lancer depuis `tools/content-cli/`.
- **`facts-to-news.mjs` reste PUR** : son en-tête promet « aucune I/O ». Il reçoit le registre en paramètre, il ne le lit pas.
- **Un contrôle doit être prouvé capable d'échouer** avant qu'on lui fasse confiance : chaque garde-fou a un test qui le fait tomber en le neutralisant.
- **Français** dans les commentaires, les messages et les noms de tests, comme tout le dossier.
- Ne pas toucher à `factDiscriminant`, à l'ordonnanceur de la Routine, ni à la traduction ES/IT/DE (hors périmètre déclaré).
- Suite complète : `npm test` depuis `tools/content-cli/` (426 tests au départ, plus ceux ajoutés ici).

## Structure des fichiers

| Fichier | Responsabilité |
|---|---|
| `tools/content-cli/schemas.mjs` *(modifié)* | Les deux tables `CARDINALITE` / `HORS_CONTROLE` et l'échelle `CONFIANCE_ORDRE`, aux côtés de `KINDS` sur laquelle porte leur test d'exhaustivité |
| `tools/content-cli/schemas.test.mjs` *(créé)* | Exhaustivité, disjonction, alignement de l'échelle sur l'énumération du schéma |
| `tools/content-cli/refus.mjs` *(créé)* | Clé, comparaison de confiance, lecture et écriture du registre. Le seul module qui touche `refus.json` |
| `tools/content-cli/refus.test.mjs` *(créé)* | Registre absent, illisible, malformé ; levée par confiance |
| `tools/content-cli/facts-to-news.mjs` *(modifié)* | Le contrôle de convergence et la lecture du registre reçu en paramètre |
| `tools/content-cli/facts-to-news.test.mjs` *(modifié)* | Doublons, rejeu du réel, preuve d'échec, levée |
| `tools/content-cli/cli.js` *(modifié)* | `pull-news` lit le registre et rapporte les écarts |
| `tools/content-cli/ui/drafts.mjs` *(modifié)* | `deleteDraft` exige un motif et inscrit le refus AVANT de supprimer |
| `tools/content-cli/ui/drafts.test.mjs` *(modifié)* | Motif vide refusé, fichier survivant, ordre d'écriture |
| `tools/content-cli/ui/console.js` + `index.html` *(modifiés)* | La saisie du motif sur le bouton `#ed-delete` existant |

---

### Task 1 : Les tables de cardinalité et l'échelle de confiance

**Files:**
- Modify: `tools/content-cli/schemas.mjs` (après `export const KINDS`, ~ligne 57)
- Test: `tools/content-cli/schemas.test.mjs` (créer)

**Interfaces:**
- Consomme : `KINDS` de `schemas.mjs`, déjà exporté.
- Produit : `CARDINALITE` (objet kind → `'une' | 'multiple'`), `HORS_CONTROLE` (objet kind → raison en clair), `CONFIANCE_ORDRE` (tableau du plus FAIBLE au plus FORT).

- [ ] **Step 1: Écrire le test qui échoue**

Créer `tools/content-cli/schemas.test.mjs` :

```js
// node --test schemas.test.mjs
//
// Ces tables décident si un contrôle s'applique à un kind. Une table qui prend
// du retard sur `KINDS` ne se voit pas : le kind neuf tombe dans un défaut
// implicite au lieu d'être tranché. D'où l'exhaustivité, testée ici.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { CARDINALITE, CONFIANCE_ORDRE, HORS_CONTROLE, KINDS } from './schemas.mjs';

const ICI = dirname(fileURLToPath(import.meta.url));

test('tout kind figure dans exactement une des deux tables', () => {
  for (const kind of Object.keys(KINDS)) {
    const places = [CARDINALITE[kind] !== undefined, HORS_CONTROLE[kind] !== undefined];
    assert.equal(
      places.filter(Boolean).length,
      1,
      `kind « ${kind} » : il lui faut une cardinalité OU une exemption motivée, pas les deux ni aucune`,
    );
  }
});

test('aucune table ne cite un kind qui n’existe pas', () => {
  for (const kind of [...Object.keys(CARDINALITE), ...Object.keys(HORS_CONTROLE)]) {
    assert.ok(KINDS[kind], `kind inconnu cité dans une table : ${kind}`);
  }
});

test('une exemption dit toujours POURQUOI', () => {
  for (const [kind, raison] of Object.entries(HORS_CONTROLE)) {
    assert.ok(String(raison).length > 20, `exemption de « ${kind} » sans raison lisible`);
  }
});

test('l’échelle de confiance couvre exactement l’énumération du schéma', () => {
  // Le schéma la donne dans l'ordre INVERSE. Comparer les ensembles, pas les
  // ordres : ajouter un niveau au schéma doit faire tomber ce test plutôt que
  // de créer une comparaison muette qui rendrait toujours `false`.
  const schema = JSON.parse(
    readFileSync(join(ICI, '..', '..', 'content', 'schema', 'news.schema.json'), 'utf8'),
  );
  assert.deepEqual(
    [...CONFIANCE_ORDRE].sort(),
    [...schema.properties.confidence.enum].sort(),
  );
});

test('l’échelle va du plus faible au plus fort', () => {
  assert.equal(CONFIANCE_ORDRE[0], 'rumor');
  assert.equal(CONFIANCE_ORDRE.at(-1), 'confirmed-official');
});
```

- [ ] **Step 2: Lancer le test, vérifier qu'il échoue**

```bash
cd tools/content-cli && node --test schemas.test.mjs
```

Attendu : ÉCHEC — `SyntaxError: The requested module './schemas.mjs' does not provide an export named 'CARDINALITE'`.

- [ ] **Step 3: Écrire les tables**

Dans `tools/content-cli/schemas.mjs`, juste après le bloc `export const KINDS = { … };` :

```js
/** L'échelle de confiance, du plus FAIBLE au plus FORT.
 *
 *  L'énumération de `news.schema.json` la donne dans l'ordre inverse ; un test
 *  compare les deux ENSEMBLES, pour qu'ajouter un niveau au schéma fasse tomber
 *  la suite au lieu de créer une comparaison muette. */
export const CONFIANCE_ORDRE = ['rumor', 'single-source', 'multi-source', 'confirmed-official'];

/** Combien d'entrées une même URL source a le droit de produire, par kind.
 *
 *  `une` déclenche le contrôle de convergence ; `multiple` l'éteint. Les POI le
 *  sont parce qu'un article « toutes les localisations confirmées » en donne
 *  légitimement trois — c'est ainsi que les 537 POI sont arrivés. */
export const CARDINALITE = {
  news: 'une',
  poi: 'multiple',
  'poi-gtav': 'multiple',
  cheats: 'multiple',
  collections: 'multiple',
};

/** Les kinds que le contrôle d'URL ne juge PAS, et pourquoi.
 *
 *  Deux tables plutôt qu'un défaut : inscrire `online-events` dans
 *  `CARDINALITE` suggérerait qu'il est couvert par ce contrôle-ci alors qu'il
 *  l'est par le sien ; le taire laisserait croire à un oubli. */
export const HORS_CONTROLE = {
  'online-events':
    'identité portée par windowDiscriminant (début de fenêtre), déjà insensible au claim',
};
```

- [ ] **Step 4: Lancer le test, vérifier qu'il passe**

```bash
cd tools/content-cli && node --test schemas.test.mjs
```

Attendu : `# pass 5`, `# fail 0`.

- [ ] **Step 5: Prouver que l'exhaustivité sait échouer**

Retirer temporairement la ligne `cheats: 'multiple',` de `CARDINALITE`, relancer :

```bash
cd tools/content-cli && node --test schemas.test.mjs
```

Attendu : ÉCHEC sur `kind « cheats » : il lui faut une cardinalité OU une exemption motivée`. **Remettre la ligne** et relancer pour retrouver `# pass 5`.

- [ ] **Step 6: Commit**

```bash
git add tools/content-cli/schemas.mjs tools/content-cli/schemas.test.mjs
git commit -m "feat(veille): la cardinalité par kind et l'échelle de confiance, en tables

Deux tables plutôt qu'un défaut implicite : un kind neuf doit se voir
attribuer une cardinalité ou une exemption MOTIVÉE, sinon la suite tombe.
L'échelle de confiance est comparée à l'énumération du schéma, qui la
donne dans l'ordre inverse.

Exhaustivité prouvée capable d'échouer en retirant \`cheats\`."
```

---

### Task 2 : Le registre des refus

**Files:**
- Create: `tools/content-cli/refus.mjs`
- Test: `tools/content-cli/refus.test.mjs`

**Interfaces:**
- Consomme : `CONFIANCE_ORDRE` de `schemas.mjs` (Task 1).
- Produit :
  - `CHEMIN_REFUS` — `'content/inbox/refus.json'`, chemin relatif à la racine du dépôt
  - `cleDeRefus(kind, url) → string`
  - `confianceSuperieure(candidate, reference) → boolean`
  - `lireRefus(chemin) → object` (lève si illisible)
  - `inscrireRefus(chemin, { kind, sources, motif, entree, confiance, le }) → object`

- [ ] **Step 1: Écrire le test qui échoue**

Créer `tools/content-cli/refus.test.mjs` :

```js
// node --test refus.test.mjs
//
// Le registre porte des décisions ÉDITORIALES. Un registre qu'on ne sait pas
// lire ne vaut pas un registre vide : se dégrader en « aucun refus » ferait
// revenir en silence tout ce qui a été écarté. D'où le test du fichier illisible.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { cleDeRefus, confianceSuperieure, inscrireRefus, lireRefus } from './refus.mjs';

const tmp = () => join(mkdtempSync(join(tmpdir(), 'refus-')), 'refus.json');

test('un registre absent est un registre vide', () => {
  assert.deepEqual(lireRefus(tmp()), {});
});

test('un registre illisible LÈVE, il ne se dégrade pas en vide', () => {
  const chemin = tmp();
  writeFileSync(chemin, '{ ceci n’est pas du JSON');
  assert.throws(() => lireRefus(chemin), /illisible/);
});

test('un registre qui n’est pas un objet est refusé', () => {
  const chemin = tmp();
  writeFileSync(chemin, '["une", "liste"]');
  assert.throws(() => lireRefus(chemin), /malformé/);
});

test('la clé n’emprunte rien au claim', () => {
  // C'est tout le point : `processedFrom` contient le claim rédigé, donc une
  // reformulation aurait ressuscité l'entrée écartée.
  assert.equal(cleDeRefus('news', 'https://x.test/a'), 'news|https://x.test/a');
});

test('un refus est inscrit pour CHAQUE source de l’entrée', () => {
  const chemin = tmp();
  const registre = inscrireRefus(chemin, {
    kind: 'news',
    sources: ['https://x.test/a', 'https://y.test/b'],
    motif: 'rumeur non confirmée',
    entree: 'news_abc',
    confiance: 'rumor',
    le: '2026-08-09',
  });
  assert.equal(Object.keys(registre).length, 2);
  assert.equal(registre['news|https://x.test/a'].motif, 'rumeur non confirmée');
  assert.equal(registre['news|https://y.test/b'].entree, 'news_abc');
  assert.deepEqual(lireRefus(chemin), registre, 'ce qui est rendu doit être ce qui est écrit');
});

test('inscrire n’écrase pas les refus déjà là', () => {
  const chemin = tmp();
  inscrireRefus(chemin, { kind: 'news', sources: ['https://x.test/a'], motif: 'm1', entree: 'news_1', confiance: 'rumor', le: '2026-08-01' });
  const registre = inscrireRefus(chemin, { kind: 'news', sources: ['https://x.test/b'], motif: 'm2', entree: 'news_2', confiance: 'rumor', le: '2026-08-02' });
  assert.equal(Object.keys(registre).length, 2);
});

test('la levée exige une confiance STRICTEMENT supérieure', () => {
  assert.equal(confianceSuperieure('multi-source', 'rumor'), true);
  assert.equal(confianceSuperieure('rumor', 'rumor'), false, 'égale ne lève pas');
  assert.equal(confianceSuperieure('rumor', 'multi-source'), false, 'inférieure ne lève pas');
  assert.equal(confianceSuperieure('confirmed-official', 'multi-source'), true);
});

test('une confiance inconnue ne lève JAMAIS', () => {
  // Dans le doute, le refus tient. Un contrôle qui approuve quand il ne sait pas
  // n'est pas un contrôle.
  assert.equal(confianceSuperieure('inventée', 'rumor'), false);
  assert.equal(confianceSuperieure('confirmed-official', 'inventée'), false);
});
```

- [ ] **Step 2: Lancer le test, vérifier qu'il échoue**

```bash
cd tools/content-cli && node --test refus.test.mjs
```

Attendu : ÉCHEC — `Cannot find module './refus.mjs'`.

- [ ] **Step 3: Écrire le module**

Créer `tools/content-cli/refus.mjs` :

```js
// Le registre des refus éditoriaux — le seul état neuf de ce chantier.
//
// Pourquoi il ne se dérive de rien, contrairement au registre des URL récoltées
// (qui EST l'inbox) : un fait écarté n'a plus d'entrée, donc plus rien à lire.
// Sans ce fichier, `pull-news` recrée au run suivant ce qu'un humain vient
// d'écarter — constaté sur `news_9bd3ef15`, écartée le 2026-08-09 et que
// `pull-news --dry-run` voulait réécrire le 2026-08-10.
//
// Ce module est le SEUL à toucher `refus.json`. `facts-to-news.mjs` le reçoit
// en paramètre : son en-tête promet « aucune I/O », et cette promesse est ce
// qui le rend testable sans disque.

import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { CONFIANCE_ORDRE, CONTENT } from './schemas.mjs';

/** Le chemin réel, absolu, construit depuis `CONTENT` comme tout le reste du
 *  dossier. Absolu et non relatif : deux appelants qui le résoudraient chacun
 *  de leur côté finiraient par diverger d'un `join` près, et le refus serait
 *  écrit dans un fichier que la lecture ne regarde pas.
 *
 *  Les fonctions prennent malgré tout le chemin en PARAMÈTRE : sans ça, les
 *  tests écriraient dans le vrai registre du dépôt à chaque exécution. */
export const CHEMIN_REFUS = join(CONTENT, 'inbox', 'refus.json');

/** La clé d'un refus : `kind` et URL.
 *
 *  Alignée sur celle du contrôle de convergence, et NON sur `processedFrom` —
 *  ce discriminant contient le claim rédigé, donc une simple reformulation
 *  aurait suffi à ressusciter l'entrée écartée. */
export const cleDeRefus = (kind, url) => `${kind}|${url}`;

/** Vrai si `candidate` est STRICTEMENT plus forte que `reference`.
 *
 *  C'est la levée automatique : le 2026-08-09 n'a pas écarté un sujet, il a
 *  écarté une rumeur. Une confiance inconnue ne lève jamais — dans le doute, le
 *  refus tient. */
export function confianceSuperieure(candidate, reference) {
  const a = CONFIANCE_ORDRE.indexOf(candidate);
  const b = CONFIANCE_ORDRE.indexOf(reference);
  if (a === -1 || b === -1) return false;
  return a > b;
}

/** Lit le registre.
 *
 *  Absent = vide, l'état initial légitime. ILLISIBLE = on lève : un registre
 *  qu'on ne sait pas lire ne vaut pas un registre vide, qui laisserait repasser
 *  en silence tout ce qui a été écarté. */
export function lireRefus(chemin) {
  if (!existsSync(chemin)) return {};
  let data;
  try {
    data = JSON.parse(readFileSync(chemin, 'utf8'));
  } catch (err) {
    throw new Error(`registre des refus illisible (${chemin}) : ${err.message}`);
  }
  if (data === null || typeof data !== 'object' || Array.isArray(data)) {
    throw new Error(`registre des refus malformé (${chemin}) : un objet est attendu`);
  }
  return data;
}

/** Inscrit un refus, une entrée par source.
 *
 *  Une entrée à plusieurs sources en pose autant : le refus doit mordre quelle
 *  que soit celle qui la re-signale. */
export function inscrireRefus(chemin, { kind, sources, motif, entree, confiance, le }) {
  const registre = lireRefus(chemin);
  for (const url of sources) {
    registre[cleDeRefus(kind, url)] = { motif, entree, confiance, le };
  }
  writeFileSync(chemin, `${JSON.stringify(registre, null, 2)}\n`);
  return registre;
}
```

- [ ] **Step 4: Lancer le test, vérifier qu'il passe**

```bash
cd tools/content-cli && node --test refus.test.mjs
```

Attendu : `# pass 8`, `# fail 0`.

- [ ] **Step 5: Prouver que le refus de lecture sait échouer**

Remplacer temporairement le corps du `catch` de `lireRefus` par `return {};`, relancer :

```bash
cd tools/content-cli && node --test refus.test.mjs
```

Attendu : ÉCHEC sur « un registre illisible LÈVE ». **Remettre le `throw`** et relancer.

- [ ] **Step 6: Commit**

```bash
git add tools/content-cli/refus.mjs tools/content-cli/refus.test.mjs
git commit -m "feat(veille): le registre des refus, et sa levée par confiance

Le seul état neuf du chantier : un fait écarté n'a plus d'entrée, donc
plus rien dont on puisse dériver le refus.

La clé est \`kind|url\`, pas \`processedFrom\` — ce discriminant contient le
claim rédigé, donc une reformulation aurait ressuscité l'entrée écartée.

Un registre illisible LÈVE au lieu de se dégrader en vide, ce qui ferait
revenir en silence tout ce qui a été écarté. Prouvé en le faisant tomber."
```

---

### Task 3 : Le contrôle de convergence

**Files:**
- Modify: `tools/content-cli/facts-to-news.mjs` (`materializeNews`, lignes 71-160)
- Test: `tools/content-cli/facts-to-news.test.mjs` (ajouts en fin de fichier)

**Interfaces:**
- Consomme : `CARDINALITE` de `schemas.mjs` (Task 1).
- Produit : `materializeNews(facts, existing)` rend désormais une sortie de plus, `ecartes: Array<{url: string, claim: string, raison: string, par: string}>`. Les cinq sorties existantes (`writes`, `alreadyMaterialized`, `covered`, `skipped`, `conflicts`) sont inchangées.

- [ ] **Step 1: Écrire les tests qui échouent**

Ajouter à la fin de `tools/content-cli/facts-to-news.test.mjs` :

```js
// ---------------------------------------------------------------------------
// Le contrôle de convergence
//
// Il tourne ICI, après le merge, et pas à la récolte : deux sessions
// concurrentes liraient toutes deux « URL non couverte » avant que l'une
// n'écrive. Constaté les 08, 09 et 10 août 2026.
// ---------------------------------------------------------------------------

test('deux lectures du même article ne produisent qu’une entrée', () => {
  // La panne exacte de la PR #83 : deux sessions, deux claims, un seul article.
  const a = newsFact({ claim: 'Le PDG a déclaré que les précommandes dépassaient les prévisions.' });
  const b = newsFact({ claim: 'Lors de ses résultats, l’éditeur a indiqué que les précommandes dépassaient ses prévisions.' });
  const { writes, ecartes } = materializeNews([a, b], []);

  assert.equal(writes.length, 1, 'un article, une entrée');
  assert.equal(ecartes.length, 1);
  assert.equal(ecartes[0].url, a.source_url);
  assert.match(ecartes[0].raison, /déjà couverte/);
});

test('un écart NOMME le claim qu’il jette', () => {
  // Une URL peut légitimement porter deux sujets. Le contrôle en sacrifie un ;
  // il ne doit pas le perdre en silence.
  const a = newsFact({ claim: 'Sony a réinscrit le jeu sur sa page éditoriale.' });
  const b = newsFact({ claim: 'Un ancien animateur juge le jeu achevé à 80-90 %.' });
  const { ecartes } = materializeNews([a, b], []);

  assert.equal(ecartes.length, 1);
  assert.match(ecartes[0].claim, /ancien animateur/);
});

test('une URL déjà portée par une entrée EXISTANTE écarte le fait', () => {
  const existant = existingItem({ id: 'news_deja', sources: ['https://example.test/article-a'] });
  const { writes, ecartes } = materializeNews([newsFact()], [existant]);

  assert.equal(writes.length, 0);
  assert.equal(ecartes[0].par, 'news_deja', 'le rapport nomme l’entrée qui la portait déjà');
});

test('deux articles DIFFÉRENTS produisent bien deux entrées', () => {
  const a = newsFact({ source_url: 'https://example.test/un' });
  const b = newsFact({ source_url: 'https://example.test/deux', claim: 'Un autre fait.' });
  const { writes, ecartes } = materializeNews([a, b], []);

  assert.equal(writes.length, 2);
  assert.equal(ecartes.length, 0);
});

test('rejeu du réel : aucune URL n’est matérialisée deux fois', () => {
  // Les vrais faits du dépôt, pas une reconstitution. 12 URLs y sont dupliquées
  // par les doubles runs des 08, 09 et 10 août, plus quatre doublons INTRA-run
  // des 06 et 07 — l'agent se répète aussi tout seul.
  const inbox = join(ICI, '..', '..', 'content', 'inbox');
  const facts = readdirSync(inbox)
    .filter((f) => f.endsWith('.facts.json'))
    .sort()
    .flatMap((f) => JSON.parse(readFileSync(join(inbox, f), 'utf8')).facts ?? []);

  const { writes } = materializeNews(facts, []);
  const urls = writes.map((w) => w.data.sources[0]);
  assert.equal(new Set(urls).size, urls.length, 'deux entrées produites pour une même URL');
});
```

Ajouter les imports manquants en tête du fichier de test, après les imports existants :

```js
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ICI = dirname(fileURLToPath(import.meta.url));
```

- [ ] **Step 2: Lancer les tests, vérifier qu'ils échouent**

```bash
cd tools/content-cli && node --test facts-to-news.test.mjs
```

Attendu : ÉCHEC — `ecartes` est `undefined`, donc `Cannot read properties of undefined (reading 'length')`, et « deux lectures du même article » rend 2 écritures au lieu d'1.

- [ ] **Step 3: Implémenter le contrôle**

Dans `tools/content-cli/facts-to-news.mjs`, ajouter l'import en tête :

```js
import { CARDINALITE } from './schemas.mjs';
```

Ajouter la constante sous les autres, vers la ligne 30 :

```js
/** Le kind que ce module matérialise. Sa cardinalité est lue dans la table
 *  plutôt que supposée : la basculer sur `multiple` éteint le contrôle, ce qui
 *  est exactement ce que la table est censée décider. */
const KIND = 'news';
```

Mettre à jour le bloc de documentation de `materializeNews` en ajoutant la sortie :

```js
 *   ecartes: Array<{url, claim, raison, par}>,          jetés, et pourquoi
```

Dans le corps, après la construction de `byProcessedFrom` (ligne 87) :

```js
  // L'index des URL déjà portées. C'est le « registre des URL récoltées » de la
  // spec — il ne s'écrit nulle part : il EST le contenu déjà là.
  const parSource = new Map();
  for (const entry of existing) {
    for (const url of entry.data.sources ?? []) {
      if (!parSource.has(url)) parSource.set(url, entry.data.id);
    }
  }
```

Déclarer la sortie à côté des autres (ligne ~93) :

```js
  const ecartes = [];
```

Insérer le contrôle APRÈS le bloc `byProcessedFrom` (ligne 119, juste avant `const id = mintNewsId(key);`) :

```js
    // LE CONTRÔLE DE CONVERGENCE.
    //
    // Après `byProcessedFrom` et pas avant : un fait qui se réapparie à SON
    // entrée est « déjà matérialisé », pas « écarté ». Les confondre dirait
    // qu'on a jeté quelque chose alors qu'on a reconnu.
    //
    // Le claim n'entre pas dans la décision — c'est ce qui rend le contrôle
    // insensible à la reformulation, donc capable de voir deux sessions
    // concurrentes là où `factDiscriminant` voyait deux faits distincts.
    if (CARDINALITE[KIND] === 'une') {
      const deja = parSource.get(fact.source_url);
      if (deja) {
        ecartes.push({
          url: fact.source_url,
          claim: fact.claim,
          raison: 'URL déjà couverte',
          par: deja,
        });
        continue;
      }
    }
```

Après `covered.push({ fact, key, id });` (ligne 149), tenir l'index à jour :

```js
    // Sans cette ligne, deux faits du MÊME lot portant la même URL passeraient
    // tous les deux : l'index ne connaîtrait que les entrées d'avant le run.
    parSource.set(fact.source_url, id);
```

Enfin, les deux `return` (lignes 156 et 159) :

```js
  if (conflicts.length) {
    return { writes: [], alreadyMaterialized: [], covered: [], skipped: [], ecartes: [], conflicts };
  }

  return { writes, alreadyMaterialized, covered, skipped, ecartes, conflicts };
```

- [ ] **Step 4: Lancer les tests, vérifier qu'ils passent**

```bash
cd tools/content-cli && node --test facts-to-news.test.mjs
```

Attendu : tous verts, dont les cinq nouveaux.

- [ ] **Step 5: Prouver que le contrôle sait échouer**

Commenter le bloc `if (CARDINALITE[KIND] === 'une') { … }`, relancer :

```bash
cd tools/content-cli && node --test facts-to-news.test.mjs
```

Attendu : ÉCHEC de « rejeu du réel » avec « deux entrées produites pour une même URL », et de « deux lectures du même article ». **Décommenter** et relancer.

- [ ] **Step 6: Commit**

```bash
git add tools/content-cli/facts-to-news.mjs tools/content-cli/facts-to-news.test.mjs
git commit -m "feat(veille): une URL déjà couverte n'engendre plus de seconde entrée

Le verrou vit à la CONVERGENCE. Un contrôle posé à la récolte ne peut pas
régler la concurrence : deux sessions liraient « URL non couverte » avant
que l'une n'écrive — c'est ce qui s'est produit les 08, 09 et 10 août.

Le claim n'entre pas dans la décision, et c'est précisément ce qui rend le
contrôle insensible à la reformulation.

Il écarte sans fusionner, et NOMME le claim qu'il jette : une URL peut
légitimement porter deux sujets, le cas existe dans les données, et le
rapport laisse la décision à un humain.

Rejeu des vrais faits du dépôt en test. Contrôle prouvé capable d'échouer."
```

---

### Task 4 : La levée par confiance supérieure

**Files:**
- Modify: `tools/content-cli/facts-to-news.mjs` (`materializeNews`)
- Test: `tools/content-cli/facts-to-news.test.mjs`

**Interfaces:**
- Consomme : `cleDeRefus`, `confianceSuperieure` de `refus.mjs` (Task 2).
- Produit : `materializeNews(facts, existing, refus = {})` — troisième paramètre optionnel. Sortie supplémentaire `leves: Array<{url, de, a, le}>`.

- [ ] **Step 1: Écrire les tests qui échouent**

Ajouter à `tools/content-cli/facts-to-news.test.mjs` :

```js
// ---------------------------------------------------------------------------
// Le registre des refus, vu du matérialiseur
// ---------------------------------------------------------------------------

const registreRefusant = (confiance = 'rumor') => ({
  'news|https://example.test/article-a': {
    motif: 'ne tient qu’à un message du support client',
    entree: 'news_9bd3ef15',
    confiance,
    le: '2026-08-09',
  },
});

test('un fait refusé ne produit rien', () => {
  const { writes, ecartes } = materializeNews([newsFact({ confidence: 'rumor' })], [], registreRefusant());

  assert.equal(writes.length, 0);
  assert.match(ecartes[0].raison, /refus du 2026-08-09/);
  assert.equal(ecartes[0].par, 'news_9bd3ef15');
});

test('le refus tient à confiance ÉGALE', () => {
  const { writes } = materializeNews([newsFact({ confidence: 'rumor' })], [], registreRefusant('rumor'));
  assert.equal(writes.length, 0);
});

test('une confiance STRICTEMENT supérieure lève le refus', () => {
  const { writes, leves, ecartes } = materializeNews(
    [newsFact({ confidence: 'multi-source' })],
    [],
    registreRefusant('rumor'),
  );

  assert.equal(writes.length, 1, 'le sujet revient quand il se confirme');
  assert.equal(ecartes.length, 0);
  assert.deepEqual(leves, [{ url: 'https://example.test/article-a', de: 'rumor', a: 'multi-source', le: '2026-08-09' }]);
});

test('sans registre, rien ne change', () => {
  const { writes, leves } = materializeNews([newsFact()], []);
  assert.equal(writes.length, 1);
  assert.deepEqual(leves, []);
});
```

- [ ] **Step 2: Lancer les tests, vérifier qu'ils échouent**

```bash
cd tools/content-cli && node --test facts-to-news.test.mjs
```

Attendu : ÉCHEC — « un fait refusé ne produit rien » écrit quand même, `leves` est `undefined`.

- [ ] **Step 3: Implémenter la levée**

Dans `tools/content-cli/facts-to-news.mjs`, ajouter l'import :

```js
import { cleDeRefus, confianceSuperieure } from './refus.mjs';
```

Changer la signature :

```js
export function materializeNews(facts, existing, refus = {}) {
```

Ajouter à la documentation de la fonction :

```js
 * @param refus     le registre des refus, LU PAR L'APPELANT — ce module reste
 *                  pur. `{}` par défaut : sans registre, rien ne change.
 *   leves: Array<{url, de, a, le}>,                     refus levés, et par quoi
```

Déclarer la sortie :

```js
  const leves = [];
```

Insérer APRÈS le contrôle de convergence, avant `const id = mintNewsId(key);` :

```js
    // Le refus, et sa levée.
    //
    // Après le contrôle d'URL : si une entrée porte déjà cette URL, le refus
    // est sans objet — un item écarté a été supprimé, donc rien ne la porte.
    const refuse = refus[cleDeRefus(KIND, fact.source_url)];
    if (refuse) {
      if (!confianceSuperieure(fact.confidence, refuse.confiance)) {
        ecartes.push({
          url: fact.source_url,
          claim: fact.claim,
          raison: `refus du ${refuse.le} — ${refuse.motif}`,
          par: refuse.entree,
        });
        continue;
      }
      // Le 2026-08-09 n'a pas écarté un sujet, il a écarté une rumeur.
      leves.push({ url: fact.source_url, de: refuse.confiance, a: fact.confidence, le: refuse.le });
    }
```

Mettre à jour les deux `return` :

```js
  if (conflicts.length) {
    return { writes: [], alreadyMaterialized: [], covered: [], skipped: [], ecartes: [], leves: [], conflicts };
  }

  return { writes, alreadyMaterialized, covered, skipped, ecartes, leves, conflicts };
```

- [ ] **Step 4: Lancer les tests, vérifier qu'ils passent**

```bash
cd tools/content-cli && node --test facts-to-news.test.mjs
```

Attendu : tous verts.

- [ ] **Step 5: Prouver que le refus sait échouer**

Remplacer temporairement `if (!confianceSuperieure(fact.confidence, refuse.confiance))` par `if (false)`, relancer :

```bash
cd tools/content-cli && node --test facts-to-news.test.mjs
```

Attendu : ÉCHEC de « un fait refusé ne produit rien ». **Remettre la condition** et relancer.

- [ ] **Step 6: Commit**

```bash
git add tools/content-cli/facts-to-news.mjs tools/content-cli/facts-to-news.test.mjs
git commit -m "feat(veille): un refus éditorial tient, et se lève quand l'info se confirme

Le registre est LU PAR L'APPELANT et passé en paramètre : ce module
promet « aucune I/O » dans son en-tête, et c'est cette promesse qui le
rend testable sans disque.

La levée est automatique et strictement supérieure — l'échelle existait
déjà, ordonnée, dans l'énumération du schéma. Le refus du 09/08 ne visait
pas un sujet mais une rumeur ; il doit tomber si un second média confirme.

Refus prouvé capable d'échouer."
```

---

### Task 5 : `pull-news` lit le registre et rapporte les écarts

**Files:**
- Modify: `tools/content-cli/cli.js` (case `pull-news`, lignes 597-637)

**Interfaces:**
- Consomme : `lireRefus`, `CHEMIN_REFUS` (Task 2) ; `materializeNews(facts, existing, refus)` (Task 4).
- Produit : rien de nouveau pour les autres tâches.

- [ ] **Step 1: Câbler le registre et le rapport**

Dans `tools/content-cli/cli.js`, case `'pull-news'`, remplacer la ligne 599 :

```js
      const { materializeNews } = await import('./facts-to-news.mjs');
```

par :

```js
      const { materializeNews } = await import('./facts-to-news.mjs');
      const { lireRefus, CHEMIN_REFUS } = await import('./refus.mjs');
```

Remplacer la ligne 620 :

```js
      const result = materializeNews(facts, existing);
```

par :

```js
      // Le registre est lu ICI : `facts-to-news.mjs` est pur et ne touche pas au
      // disque. Une lecture qui échoue ARRÊTE la commande — un registre illisible
      // traité comme vide ferait revenir en silence tout ce qui a été écarté.
      const refus = lireRefus(CHEMIN_REFUS);
      const result = materializeNews(facts, existing, refus);
```

Juste après le bloc `if (result.conflicts.length) { … }` (après la ligne 627), insérer le rapport :

```js
      // Écarts et levées se rapportent dans les DEUX modes : un `--dry-run` qui
      // les tairait donnerait une répétition mensongère de la vraie commande.
      result.ecartes.forEach((e) => {
        console.log(`  écarté  ${e.url}`);
        console.log(`          ${e.raison}, déjà porté par ${e.par}`);
        console.log(`          « ${String(e.claim ?? '').slice(0, 100)}… »`);
      });
      result.leves.forEach((l) => {
        console.log(`  refus du ${l.le} levé — confiance passée de ${l.de} à ${l.a} (${l.url})`);
      });
```

Dans le résumé du `--dry-run` (lignes 631-634), ajouter le compte :

```js
        console.log(
          `pull-news --dry-run: ${result.writes.length} squelette(s), ` +
            `${result.ecartes.length} écarté(s), ` +
            `${result.alreadyMaterialized.length} déjà matérialisé(s), aucune écriture`,
        );
```

- [ ] **Step 2: Vérifier sur les données réelles du dépôt**

```bash
cd tools/content-cli && node cli.js pull-news --dry-run
```

Attendu : le compte d'écartés est **non nul** (les doublons intra-run des 06 et 07 août), et `news_9bd3ef15` figure encore dans les squelettes — le registre est vide à ce stade, c'est la Task 6 qui l'alimentera.

- [ ] **Step 3: Vérifier qu'un registre illisible arrête la commande**

```bash
cd tools/content-cli && echo 'pas du json' > ../../content/inbox/refus.json && node cli.js pull-news --dry-run; echo "code de sortie: $?"
```

Attendu : message `registre des refus illisible`, code de sortie **1**. Puis nettoyer :

```bash
rm ../../content/inbox/refus.json
```

- [ ] **Step 4: Lancer la suite complète**

```bash
cd tools/content-cli && npm test
```

Attendu : `# fail 0`, et la chaîne `check` verte.

- [ ] **Step 5: Commit**

```bash
git add tools/content-cli/cli.js
git commit -m "feat(veille): pull-news lit le registre et dit ce qu'il écarte

Le registre est lu ici parce que \`facts-to-news.mjs\` promet « aucune
I/O ». Une lecture qui échoue arrête la commande : un registre illisible
traité comme vide ferait revenir en silence tout ce qui a été écarté.

Écarts et levées sont rapportés dans les DEUX modes — un --dry-run qui
les tairait serait une répétition mensongère."
```

---

### Task 6 : `deleteDraft` exige un motif et inscrit le refus

**Files:**
- Modify: `tools/content-cli/ui/drafts.mjs` (`deleteDraft`, lignes 341-361)
- Test: `tools/content-cli/ui/drafts.test.mjs`

**Interfaces:**
- Consomme : `inscrireRefus`, `lireRefus`, `cleDeRefus`, `CHEMIN_REFUS` (Task 2).
- Produit : `deleteDraft(kind, id, { fingerprint, motif, cheminRefus = CHEMIN_REFUS })`. Rend `{ kind, id, ecarte: true, titre, refus: <nombre de clés inscrites> }`.

**Deux contraintes que le fichier de test existant impose — les lire avant d'écrire :**

1. **`drafts.test.mjs:420`** assert que `deleteDraft(kind, id)` sans options échoue avec `err.status === 409`. Le contrôle du motif doit donc venir **APRÈS** ceux du statut et de l'empreinte, sinon ce test bascule en 400 et tombe.
2. **`drafts.test.mjs:379`** (« un brouillon s'écarte ») appelle `deleteDraft` **sans motif et attend un succès**. Ce test DOIT être mis à jour dans cette tâche — c'est une modification légitime du contrat, pas un dégât collatéral à cacher.

Les helpers existants s'appellent `unBrouillon(pile)`, `unItem(statut)` et `surUneCopie(kind, id, fn)` — ce dernier restaure le fichier après coup. **Ne pas en écrire de nouveaux.**

- [ ] **Step 1: Écrire les tests qui échouent**

D'abord compléter les imports en tête de `tools/content-cli/ui/drafts.test.mjs` :

```js
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { cleDeRefus, lireRefus } from '../refus.mjs';

/** Un registre jetable. Sans ça, chaque exécution des tests écrirait dans le
 *  vrai `content/inbox/refus.json` du dépôt. */
const registreJetable = () => join(mkdtempSync(join(tmpdir(), 'refus-')), 'refus.json');
```

Mettre à jour le test existant de la ligne 379 :

```js
test('un brouillon s’écarte', () => {
  const item = unBrouillon('attend') ?? unBrouillon('retenu');
  assert.ok(item, 'aucun brouillon dans le dépôt pour ce test');
  surUneCopie(item.kind, item.id, (path) => {
    const r = deleteDraft(item.kind, item.id, {
      fingerprint: fingerprintOf(path),
      motif: 'essai automatisé',
      cheminRefus: registreJetable(),
    });
    assert.equal(r.ecarte, true);
    assert.equal(existsSync(path), false);
  });
});
```

Puis ajouter les nouveaux tests à la suite :

```js
test('écarter sans motif est refusé, et le fichier SURVIT', () => {
  const item = unBrouillon('attend') ?? unBrouillon('retenu');
  assert.ok(item, 'aucun brouillon dans le dépôt pour ce test');
  surUneCopie(item.kind, item.id, (path) => {
    assert.throws(
      () => deleteDraft(item.kind, item.id, {
        fingerprint: fingerprintOf(path),
        motif: '   ',
        cheminRefus: registreJetable(),
      }),
      (err) => err.status === 400 && /motif/.test(err.message),
    );
    // Un refus qui aurait quand même supprimé serait pire que pas de refus.
    assert.equal(existsSync(path), true);
  });
});

test('écarter inscrit le refus, avec la confiance du moment', () => {
  const item = unBrouillon('attend') ?? unBrouillon('retenu');
  assert.ok(item, 'aucun brouillon dans le dépôt pour ce test');
  const chemin = registreJetable();
  surUneCopie(item.kind, item.id, (path) => {
    const data = JSON.parse(readFileSync(path, 'utf8'));
    deleteDraft(item.kind, item.id, {
      fingerprint: fingerprintOf(path),
      motif: 'ne tient qu’à un message du support client',
      cheminRefus: chemin,
    });

    const registre = lireRefus(chemin);
    assert.equal(Object.keys(registre).length, (data.sources ?? []).length);
    for (const url of data.sources ?? []) {
      const inscrit = registre[cleDeRefus(item.kind, url)];
      assert.equal(inscrit.entree, data.id);
      assert.equal(inscrit.confiance, data.confidence);
      assert.match(inscrit.motif, /support client/);
    }
  });
});

test('si le registre ne peut pas s’écrire, le brouillon RESTE', () => {
  // L'ordre inverse laisserait un fichier supprimé sans refus enregistré — la
  // panne qu'on corrige, reproduite par son propre correctif.
  const item = unBrouillon('attend') ?? unBrouillon('retenu');
  assert.ok(item, 'aucun brouillon dans le dépôt pour ce test');
  surUneCopie(item.kind, item.id, (path) => {
    assert.throws(() => deleteDraft(item.kind, item.id, {
      fingerprint: fingerprintOf(path),
      motif: 'un motif valable',
      // Un répertoire qui n'existe pas : l'écriture échoue à coup sûr.
      cheminRefus: join(tmpdir(), 'ce-dossier-n-existe-pas-refus', 'refus.json'),
    }));
    assert.equal(existsSync(path), true, 'le registre s’écrit AVANT la suppression');
  });
});
```

- [ ] **Step 2: Lancer les tests, vérifier qu'ils échouent**

```bash
cd tools/content-cli && node --test ui/drafts.test.mjs
```

Attendu : ÉCHEC — `deleteDraft` accepte l'absence de motif et supprime.

- [ ] **Step 3: Implémenter**

Dans `tools/content-cli/ui/drafts.mjs`, ajouter l'import en tête :

```js
import { CHEMIN_REFUS, inscrireRefus } from '../refus.mjs';
```

Remplacer `deleteDraft` (lignes 341-361) :

```js
/**
 * Écarte un brouillon : inscrit le refus, PUIS supprime le fichier.
 *
 * L'ordre n'est pas un détail. L'inverse laisserait, si l'écriture du registre
 * échouait, un fichier supprimé sans refus enregistré — c'est-à-dire exactement
 * la panne que ce registre corrige, reproduite par son propre correctif.
 *
 * Le motif est obligatoire parce qu'il est la seule chose que le geste du
 * 2026-08-09 avait perdue : la phrase existait, mais dans un message de commit,
 * donc invisible à `pull-news` qui a voulu recréer l'entrée le lendemain.
 */
export function deleteDraft(kind, id, { fingerprint, motif, cheminRefus = CHEMIN_REFUS } = {}) {
  const path = resolvePath(kind, id);
  const data = JSON.parse(readFileSync(path, 'utf8'));

  if (data.status !== 'draft') {
    throw new RefusedError(
      `\`${id}\` est en \`${data.status}\` — un item publié ne s'écarte pas : son fragment est déjà `
      + 'servi aux clients. Le repasser en `draft`, republier, puis écarter.',
      409,
    );
  }
  if (fingerprintOf(path) !== fingerprint) {
    throw new RefusedError(
      'le fichier a changé sur le disque depuis son ouverture — recharger avant de l’écarter',
      409,
    );
  }
  // Le motif EN DERNIER des trois contrôles, et ce n'est pas arbitraire :
  // `drafts.test.mjs:420` assert qu'un appel sans options échoue en 409 sur
  // l'empreinte. Le passer devant ferait basculer ce test en 400.
  if (!String(motif ?? '').trim()) {
    throw new RefusedError(
      'écarter demande un motif : c’est lui qui empêchera le prochain `pull-news` de recréer l’entrée',
      400,
    );
  }

  const registre = inscrireRefus(cheminRefus, {
    kind,
    sources: data.sources ?? [],
    motif: String(motif).trim(),
    entree: data.id,
    confiance: data.confidence ?? null,
    le: new Date().toISOString().slice(0, 10),
  });

  unlinkSync(path);
  return {
    kind,
    id,
    ecarte: true,
    titre: data.title?.fr ?? data.title?.en ?? id,
    refus: Object.keys(registre).length,
  };
}
```

*Vérifié : `join` et `unlinkSync` sont déjà importés en tête de `drafts.mjs` (lignes 19-20). `ROOT` ne l'est pas et n'a pas à l'être — `CHEMIN_REFUS` est déjà absolu.*

- [ ] **Step 4: Lancer les tests, vérifier qu'ils passent**

```bash
cd tools/content-cli && node --test ui/drafts.test.mjs
```

Attendu : tous verts.

- [ ] **Step 5: Prouver que l'ordre est le bon**

Intervertir temporairement `unlinkSync(path);` et le bloc `inscrireRefus(...)`, relancer :

```bash
cd tools/content-cli && node --test ui/drafts.test.mjs
```

Attendu : ÉCHEC de « si le registre ne peut pas s’écrire, le brouillon reste ». **Remettre l'ordre** et relancer.

- [ ] **Step 6: Commit**

```bash
git add tools/content-cli/ui/drafts.mjs tools/content-cli/ui/drafts.test.mjs
git commit -m "feat(console): écarter un brouillon inscrit le refus, motif obligatoire

Aucune action nouvelle : le geste existait déjà (#ed-delete, DELETE
/api/draft/:kind/:id). Lui adjoindre un jumeau sur la porte « geste »
aurait donné deux façons d'écarter, dont une seule inscrirait le refus.

Le registre s'écrit AVANT le unlinkSync : l'inverse laisserait, si
l'écriture échouait, un fichier supprimé sans refus enregistré — la panne
qu'on corrige, reproduite par son correctif. Ordre prouvé par un test qui
rend le registre non inscriptible.

Le motif est obligatoire parce qu'il est ce que le geste du 09/08 avait
perdu : la phrase existait, dans un message de commit."
```

---

### Task 7 : La saisie du motif dans la page

**Files:**
- Modify: `tools/content-cli/ui/console.js` (le gestionnaire de `#ed-delete`)
- Modify: `tools/content-cli/ui/index.html` (si un champ de saisie s'avère préférable au `prompt`)

**Interfaces:**
- Consomme : `DELETE /api/draft/:kind/:id` acceptant `{ fingerprint, motif }` (Task 6).

- [ ] **Step 1: Trouver le gestionnaire actuel**

```bash
cd tools/content-cli && grep -n "ed-delete" ui/console.js
```

Noter la fonction qui envoie le `DELETE` et le corps qu'elle construit aujourd'hui (`{ fingerprint }`).

- [ ] **Step 2: Ajouter la saisie du motif**

Dans le gestionnaire, avant l'appel `fetch`, remplacer la confirmation existante par une saisie :

```js
  // Le motif n'est pas une politesse : sans lui, le serveur refuse en 400, et
  // c'est lui qui empêchera le prochain `pull-news` de recréer l'entrée.
  const motif = prompt(
    `Écarter « ${ouvert.data.title?.fr ?? ouvert.data.id} » ?\n\n`
    + 'Pourquoi ? Ce motif est inscrit au registre des refus et empêchera la veille '
    + 'de recréer cette entrée.\n\nLa levée reste automatique si la confiance monte.',
  );
  if (motif === null) return;            // annulé
  if (!motif.trim()) {
    msg.className = 'msg warn';
    msg.textContent = 'Écarter demande un motif.';
    return;
  }
```

Puis ajouter `motif` au corps envoyé :

```js
    body: JSON.stringify({ fingerprint: ouvert.fingerprint, motif }),
```

- [ ] **Step 3: Vérifier à l'écran**

```bash
cd tools/content-cli && npm run ui
```

Ouvrir `http://127.0.0.1:4321`, ouvrir un brouillon d'actu, cliquer « Écarter » :
- annuler → rien ne se passe, le brouillon reste ;
- valider avec un motif vide → message « Écarter demande un motif. », rien n'est supprimé ;
- valider avec un motif → le brouillon disparaît, et `content/inbox/refus.json` existe et contient la clé `news|<url>`.

```bash
cd tools/content-cli && cat ../../content/inbox/refus.json
```

Puis annuler ces essais :

```bash
git checkout -- content/ && rm -f ../../content/inbox/refus.json
```

- [ ] **Step 4: Lancer la suite complète**

```bash
cd tools/content-cli && npm test
```

Attendu : `# fail 0` et la chaîne `check` verte.

- [ ] **Step 5: Commit**

```bash
git add tools/content-cli/ui/console.js tools/content-cli/ui/index.html
git commit -m "feat(console): la saisie du motif au moment d'écarter

Le bouton ne bouge pas, le geste non plus. Ce qui change est qu'il
demande POURQUOI, et que la réponse part au registre.

Le libellé dit la levée automatique : écarter une rumeur n'enterre pas le
sujet, il attend qu'il se confirme."
```

---

### Task 8 : Le critère d'acceptation vivant

**Files:** aucun — vérification de bout en bout.

- [ ] **Step 1: Reproduire l'état du jour**

```bash
cd tools/content-cli && node cli.js pull-news --dry-run | grep news_9bd3ef15
```

Attendu : la ligne `écrirait content/news/news_9bd3ef15.json  [rumor] 2026-08-07` — le symptôme d'origine, registre encore vide.

- [ ] **Step 2: Inscrire le refus réellement prononcé le 2026-08-09**

Créer `content/inbox/refus.json` avec le motif d'origine, repris du commit `8da9ccb` :

```json
{
  "news|https://www.gtaboom.com/what-to-expect-when-gta-6-hits-netflix-on-august-27-c2f7": {
    "motif": "ne tient qu'à un message du support client relayé sans confirmation",
    "entree": "news_9bd3ef15",
    "confiance": "rumor",
    "le": "2026-08-09"
  }
}
```

- [ ] **Step 3: Vérifier que le refus tient**

```bash
cd tools/content-cli && node cli.js pull-news --dry-run | grep -E "9bd3ef15|refus du"
```

Attendu : plus aucune ligne `écrirait … news_9bd3ef15`, et une ligne `refus du 2026-08-09`.

- [ ] **Step 4: Vérifier que la levée fonctionne**

Passer temporairement `"confiance": "rumor"` à `"confiance": "single-source"` dans le registre — non : modifier plutôt la confiance du FAIT, dans `content/inbox/2026-08-08-gta6-veille.facts.json`, en passant le fait de cette URL de `rumor` à `multi-source`. Relancer :

```bash
cd tools/content-cli && node cli.js pull-news --dry-run | grep -E "9bd3ef15|levé"
```

Attendu : une ligne `refus du 2026-08-09 levé — confiance passée de rumor à multi-source`, et l'entrée revient dans les squelettes.

**Restaurer le fait** :

```bash
git checkout -- ../../content/inbox/2026-08-08-gta6-veille.facts.json
```

- [ ] **Step 5: Lancer la suite complète une dernière fois**

```bash
cd tools/content-cli && npm test
```

Attendu : `# fail 0`, `validate` et `check-publishable` verts.

- [ ] **Step 6: Commit du registre**

```bash
git add content/inbox/refus.json
git commit -m "content(veille): inscrire au registre le refus du 2026-08-09

Le motif est repris mot pour mot du commit 8da9ccb, qui l'avait écrit là
où aucune machine ne pouvait le lire.

Vérifié de bout en bout : pull-news ne veut plus recréer news_9bd3ef15,
et le veut à nouveau si la confiance du fait monte à multi-source."
```

---

### Task 9 : Aligner les agents de la Routine sur les nouveaux mécanismes

**Files:**
- Modify: `.claude/agents/data-scout.md` (bloc lignes 137-145)
- Modify: `.claude/agents/content-editor.md`

**Pourquoi cette tâche existe.** Le prompt de la Routine quotidienne vit hors du dépôt, mais les agents qu'elle exécute sont ici. Livrer les mécanismes sans corriger leurs contrats laisserait la Routine travailler sur des règles périmées : `data-scout.md:139` avertit encore l'agent qu'il doit ÉVITER une collision d'identité que le code empêche désormais lui-même, et rien ne lui dit qu'un registre des refus existe.

**Angle mort de CI à connaître** : `content.yml` ne se déclenche que sur `content/**`, `tools/**` et les POI — une modification de `.claude/agents/*` passe **sans aucune CI**. Relire à la main.

- [ ] **Step 1: Corriger l'avertissement périmé de `data-scout.md`**

Le bloc actuel (lignes 137-145) dit à l'agent que son fait et celui de l'outil « porteraient deux identités pour la MÊME semaine ». Remplacer la justification par le mécanisme, sans changer la consigne :

```markdown
  Danger concret si tu en écris un quand même : l'identité d'un fait reste le
  hachage de `source_url + claim`, donc ton fait et celui de l'outil porteraient
  deux identités pour la MÊME semaine. Depuis le 2026-08-10, `materializeNews`
  écarte le second au lieu de créer une carte concurrente — mais il l'ÉCARTE,
  c'est-à-dire qu'une lecture est perdue et rapportée comme telle. Le contrôle
  te rattrape ; il ne te dispense pas.
```

- [ ] **Step 2: Dire au data-scout que le registre des refus existe**

Ajouter à la fin de la même section :

```markdown
- **Un sujet écarté par un humain ne se re-signale pas en le reformulant.**
  `content/inbox/refus.json` porte les refus éditoriaux, avec leur motif et la
  confiance qu'avait le fait au moment du refus. Une URL qui y figure a été
  jugée. Tu peux la re-signaler UNIQUEMENT si ta source lui donne une confiance
  strictement supérieure à celle inscrite — c'est exactement ce que la chaîne
  vérifiera, et le refus tiendra si tu te contentes de réécrire la phrase.
- **Une URL déjà présente dans `content/inbox/*.facts.json` a déjà été
  récoltée.** La re-extraire n'est pas une faute — la chaîne écarte le doublon —
  mais c'est un appel réseau et une rédaction pour rien. Les 06 et 07 août, un
  run UNIQUE a produit deux faits pour un même article, quatre fois.
```

- [ ] **Step 3: Signaler la ligne des langues, sans la retourner ici**

`content-editor.md:15-16` dit aujourd'hui :

> « Langues : EN (référence) + FR. ES/IT/DE sont générés par le CLI — ne les remplis pas. »

C'est **faux depuis toujours** : `cli.js:370` déclare que `translate` n'a que son `--dry-run` et que « l'appel IA reste à câbler ». L'agent ne traduit pas parce que le CLI s'en charge ; le CLI ne s'en charge pas ; les 78 actus sont bilingues. Chaque moitié délègue à l'autre.

**Décision du 2026-08-10 : c'est la ROUTINE qui traduira, pas le CLI.** L'appel IA n'a donc jamais à être câblé dans `cli.js` — la Routine écrit déjà `title` et `body` en EN et FR depuis le `claim`, et écrire les cinq langues est le même geste, avec le même modèle, dans la même passe. Aucune clé d'API nouvelle, aucun coût nouveau, aucun secret nouveau. `translate --dry-run` reste ce qu'il est déjà et devient enfin utile : le **contrôle** qui nomme les champs manquants, pas un producteur en attente.

La ligne bascule donc dans le chantier traduction, avec le contrat de la Routine — même fichier, même commit. Elle ne bascule pas ici parce que les vraies questions restantes sont à trancher là-bas : une traduction manquante bloque-t-elle la publication, et que fait-on des 78 entrées déjà publiées.

Ajouter un commentaire au-dessus, pour que la prochaine lecture ne prenne pas cette ligne pour un état de fait :

```markdown
<!-- ATTENTION : « générés par le CLI » n'a jamais été vrai. `cli.js` case
     'translate' n'implémente que `--dry-run` ; aucune des 78 actus n'a
     d'ES/IT/DE. Tranché le 2026-08-10 : c'est LA ROUTINE qui traduira — même
     modèle, même passe que EN/FR — et `translate --dry-run` reste le CONTRÔLE.
     Cette ligne bascule dans le chantier traduction, avec le reste du contrat. -->
```

- [ ] **Step 4: Relire à la main, puisque la CI ne le fera pas**

```bash
cd /Users/antoine/gta_project && git diff .claude/agents/
```

Vérifier : aucune consigne contradictoire avec les mécanismes livrés en Tasks 1-8, et la ligne des langues inchangée.

- [ ] **Step 5: Commit**

```bash
git add .claude/agents/data-scout.md .claude/agents/content-editor.md
git commit -m "docs(agents): aligner la Routine quotidienne sur les mécanismes livrés

Le prompt de la Routine vit hors du dépôt, mais les agents qu'elle exécute
sont ici. Les livrer inchangés la laisserait travailler sur des règles
périmées.

data-scout croyait devoir éviter seul une collision d'identité que le code
empêche désormais — la consigne reste, sa justification devient exacte : le
contrôle le rattrape, il ne l'en dispense pas. Et il apprend que
\`refus.json\` existe, donc qu'un sujet écarté ne se re-signale pas en le
reformulant.

Un commentaire posé sur la ligne des langues de content-editor, qui
annonce depuis toujours que « ES/IT/DE sont générés par le CLI » alors que
cli.js:370 déclare l'appel IA non câblé. Chaque moitié déléguait à l'autre
et 78 actus sur 78 sont restées bilingues. La ligne ne bascule qu'avec le
câblage, dans le même commit — c'est la leçon du dossier.

Aucune CI ne couvre .claude/agents/ : relu à la main."
```

---

## Auto-revue

**Couverture de la spec.** § « contrôle de convergence » → Task 3. § « cardinalité en un seul endroit » → Task 1. § « registre des refus et sa levée » → Tasks 2 et 4. § « geste Écarter » → Tasks 6 et 7. § « Erreurs » : motif vide (Task 6), `published` et empreinte (inchangés, couverts par les tests existants), échec d'écriture du registre (Task 6 step 5), registre illisible (Tasks 2 et 5), registre absent (Task 2). § « Tests » : rejeu du réel (Task 3), preuve d'échec (Tasks 1, 2, 3, 4, 6), faits multiples légitimes (Task 1 par la cardinalité `multiple`), écart nommant son claim (Task 3), levée (Task 4), critère d'acceptation vivant (Task 8).

**Un écart assumé entre spec et plan.** La spec évoque un test « les trois `poi` d'un même article produisent trois entrées ». Il n'existe pas de matérialiseur de POI depuis l'inbox (`draft-to-poi.mjs` a un autre chemin) : la garantie est donnée par `CARDINALITE.poi === 'multiple'`, testé en Task 1, et non par un test de bout en bout qui n'aurait rien à exécuter.

**Cohérence des types.** `ecartes` porte `{url, claim, raison, par}` en Tasks 3 et 4, et c'est ce que lit Task 5. `leves` porte `{url, de, a, le}` en Task 4, lu identiquement en Task 5. `materializeNews(facts, existing, refus = {})` — le troisième paramètre est optionnel, donc `facts-to-online-event.mjs` et les tests existants qui appellent à deux arguments continuent de passer. `deleteDraft(kind, id, { fingerprint, motif })` étend l'objet d'options sans en changer la forme.

**Ordre des tâches.** 1 → 2 (les tables avant le module qui les lit), 2 → 4, 3 → 4 (même fonction, deux contrôles empilés), 4 → 5, 2 → 6, 6 → 7, tout → 8. La Task 9 ne dépend que des Tasks 3, 4 et 6 étant livrées : elle décrit à l'agent ce qui existe désormais.

**Deux conflits avec le code existant, trouvés en écrivant le plan et traités dans la Task 6** : `drafts.test.mjs:420` assert un 409 sur un appel sans options — d'où le contrôle du motif placé en dernier des trois ; et `drafts.test.mjs:379` appelle `deleteDraft` sans motif en attendant un succès — d'où sa mise à jour explicite, dans la tâche qui change le contrat.

**Ce que le plan ne fait PAS, et qui mérite d'être dit** : la ligne `content-editor.md:15` reste fausse à l'issue de ce chantier, signalée par un commentaire (Task 9 step 3) et retournée dans le chantier traduction. La retourner ici obligerait à trancher au passage ce qu'on fait des 78 entrées déjà publiées et si une traduction manquante bloque la publication — deux décisions qui n'ont rien à voir avec l'identité et le refus.
