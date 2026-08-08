#!/usr/bin/env node
// Livrer : brancher, commiter, pousser, ouvrir la PR — en un geste.
//
//   node deliver.mjs            livre pour de vrai
//   node deliver.mjs --dry-run  montre ce qui partirait, n'écrit rien
//
// ─────────────────────────────────────────────────────────────────────────────
// POURQUOI AUCUN TEXTE LIBRE N'ENTRE ICI
//
// La console appelle cette commande sans le moindre paramètre. Titre, message et
// corps de PR sont COMPOSÉS depuis le diff réel — pas saisis. Deux raisons, et
// la seconde compte plus que la première :
//
//   1. L'invariant de la porte « geste » tient : rien de la requête n'atteint
//      une ligne de commande. Un titre de PR libre serait du texte arbitraire
//      dans un `argv`, sans motif capable de le valider.
//   2. Un message écrit depuis le diff est PLUS JUSTE qu'un message saisi. Il
//      nomme ce qui a réellement changé, y compris ce qu'on avait oublié avoir
//      touché — et c'est précisément ce que la relecture doit voir.
//
// ─────────────────────────────────────────────────────────────────────────────
// CE QUE CETTE COMMANDE NE FAIT PAS : fusionner. La PR s'ouvre, elle ne se
// referme pas toute seule. Pour l'actu et les événements en ligne, le merge sur
// `main` déclenche la publication CDN — le diff relu est donc le dernier
// garde-fou avant les utilisateurs, et rien ici ne doit le contourner.

import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ROOT } from './schemas.mjs';

/** Les kinds dont la publication est AUTOMATIQUE au merge sur `main`
 *  (`.github/workflows/content.yml`, job `publish-news`). Les nommer dans le
 *  corps de la PR n'est pas décoratif : c'est ce qui dit au relecteur que son
 *  approbation vaut mise en ligne. */
const AUTO_PUBLIES = new Set(['news', 'online-events']);

/**
 * Lit `git status --porcelain` et rend les changements de contenu.
 *
 * Le format porcelain v1 est `XY <chemin>`, deux colonnes d'état puis un espace.
 * On ne garde que `content/<kind>/<id>.json` : un fichier d'inbox ou un script
 * modifié en même temps n'a rien à faire dans une livraison de contenu, et
 * l'emporter ferait échouer le garde-fou de périmètre du workflow.
 */
export function changementsDe(porcelain) {
  const changements = [];
  for (const ligne of String(porcelain ?? '').split('\n')) {
    // Le chemin est ANCRÉ en fin de ligne, et l'état est ce qui précède.
    //
    // Découper par position (`slice(0, 2)`, `slice(3)`) serait plus fidèle au
    // format… et plus fragile : la première ligne d'un `git status` de fichier
    // seulement modifié commence par une ESPACE (` M chemin`), qu'un `.trim()`
    // en amont fait disparaître. Les colonnes glissent alors d'un cran et plus
    // rien ne correspond — panne silencieuse constatée le 2026-08-07, où la
    // livraison annonçait « rien à livrer » avec un fichier modifié sous les
    // yeux. Ancrer sur le chemin rend la lecture indifférente à ce détail.
    const m = ligne.match(/^(.{0,3}?)\s*content\/([a-z-]+)\/([A-Za-z0-9_-]+)\.json$/);
    if (!m) continue;
    const [, etat, kind, id] = m;
    if (kind === 'inbox' || kind === 'schema') continue;
    changements.push({
      kind,
      id,
      chemin: `content/${kind}/${id}.json`,
      neuf: etat.includes('?') || etat.includes('A'),
    });
  }
  return changements.sort((a, b) => a.chemin.localeCompare(b.chemin));
}

/**
 * Ce que la livraison N'EMPORTE PAS.
 *
 * Ajouté le 2026-08-08, et c'est une correction de fond. `main()` demandait à git
 * l'état de `content/` **et de rien d'autre** : une modification de code en
 * attente restait donc dans l'arbre de travail sans qu'une seule ligne le dise.
 * On ouvrait une pull request en croyant l'arbre propre.
 *
 * C'est exactement la panne que cette console existe pour supprimer — **mentir
 * par omission** — et elle était dans le geste le plus conséquent de tous.
 *
 * Deux catégories, parce qu'elles ne se lisent pas pareil :
 *
 *   - `exclu` : `content/inbox/` porte du TEXTE TIERS, jamais commité. Son
 *     absence est une règle tenue, pas un oubli ;
 *   - `laisse` : tout le reste. Là, c'est peut-être un oubli, et seul un humain
 *     peut le dire — donc on le montre plutôt que d'en décider.
 */
export function resteDeCote(porcelainComplet) {
  const exclu = [];
  const laisse = [];
  for (const ligne of String(porcelainComplet ?? '').split('\n')) {
    const chemin = cheminDe(ligne);
    if (!chemin) continue;
    // Ce que la livraison emporte déjà : même définition que `changementsDe`,
    // sinon un fichier serait annoncé livré ET laissé de côté.
    if (/^content\/(?!inbox\/|schema\/)[a-z-]+\/[A-Za-z0-9_-]+\.json$/.test(chemin)) continue;
    (chemin.startsWith('content/inbox/') ? exclu : laisse).push(chemin);
  }
  return { exclu: exclu.sort(), laisse: laisse.sort() };
}

/** Le chemin d'une ligne de `git status --porcelain`, ou `null`.
 *
 *  Le format v1 est `XY<espace>chemin` : deux colonnes d'état, dont l'une est
 *  une espace pour un fichier seulement modifié. D'où les deux lectures — la
 *  seconde rattrape une entrée dont on aurait mangé l'espace de tête en amont,
 *  ce qui est précisément la panne du 2026-08-07 et qui, ici, produirait un
 *  chemin `M content/news/…` que plus aucun motif ne reconnaîtrait. */
function cheminDe(ligne) {
  const brut = /^(..) (.+)$/.exec(ligne)?.[2] ?? /^[MADRCU?!]{1,2}\s+(.+)$/.exec(ligne)?.[1];
  // `R ancien -> nouveau` : c'est la destination qui compte.
  return brut ? brut.trim().split(' -> ').at(-1) : null;
}

/** Ce que le changement fait au statut de l'item : c'est LA information qui
 *  intéresse un relecteur, et elle ne se lit pas dans la liste des fichiers. */
export function transitionDe(avant, apres) {
  const a = avant?.status ?? null;
  const b = apres?.status ?? null;
  if (a === b) return a ? `reste ${a}` : 'modifié';
  if (!a) return `créé ${b}`;
  return `${a} → ${b}`;
}

/** Le titre du commit et de la PR. Court, et il dit le nombre — un relecteur qui
 *  voit « 12 actualités » se prépare autrement qu'à « 1 ». */
export function titreDe(changements) {
  const parKind = {};
  for (const c of changements) parKind[c.kind] = (parKind[c.kind] ?? 0) + 1;
  const morceaux = Object.entries(parKind)
    .sort()
    .map(([kind, n]) => `${n} ${kind}`);
  return `content(livraison): ${morceaux.join(', ')}`;
}

/** Le corps : une ligne par item, plus l'avertissement de publication
 *  automatique quand il s'applique. */
export function corpsDe(changements, details = {}) {
  const lignes = [];
  const kinds = [...new Set(changements.map((c) => c.kind))].sort();

  const auto = kinds.filter((k) => AUTO_PUBLIES.has(k));
  const manuels = kinds.filter((k) => !AUTO_PUBLIES.has(k));

  if (auto.length) {
    lignes.push(
      `**Le merge de cette PR PUBLIE** : \`${auto.join('`, `')}\` partent sur le CDN`,
      'automatiquement au merge sur `main` (workflow Contenu, job `publish-news`).',
      'La relecture de ce diff est le dernier garde-fou avant les utilisateurs.',
      '',
    );
  }
  if (manuels.length) {
    lignes.push(
      `\`${manuels.join('`, `')}\` ne se publient PAS au merge : ils sont embarqués dans`,
      'les socles de l’app et attendent le bouton de publication.',
      '',
      '> Attention : un merge qui touche AUSSI ces kinds fait refuser `publish-news`',
      '> en entier — l’actu ne partira pas non plus. Livrer séparément.',
      '',
    );
  }

  lignes.push('| Item | Kind | Statut |', '|---|---|---|');
  for (const c of changements) {
    lignes.push(`| \`${c.id}\` | ${c.kind} | ${details[c.chemin] ?? (c.neuf ? 'nouveau' : 'modifié')} |`);
  }
  lignes.push('', '🤖 Livré depuis la console de pilotage (`npm run ui`)');
  return lignes.join('\n');
}

/** Un nom de branche libre. La date suffit presque toujours ; le suffixe existe
 *  pour la deuxième livraison du même jour, qui arrive dès qu'on corrige. */
export function nomDeBranche(jour, existantes = []) {
  const prises = new Set(existantes);
  const base = `content/livraison-${jour}`;
  if (!prises.has(base)) return base;
  for (let n = 2; n < 100; n += 1) {
    if (!prises.has(`${base}-${n}`)) return `${base}-${n}`;
  }
  throw new Error(`cent livraisons le ${jour} — quelque chose ne tourne pas rond`);
}

// ---------------------------------------------------------------------------
// L'exécution
// ---------------------------------------------------------------------------

/** `brut: true` conserve la sortie telle quelle.
 *
 *  `git status --porcelain` commence chaque ligne par DEUX colonnes d'état, et
 *  celle d'un fichier seulement modifié est une espace. Un `.trim()` global la
 *  mange — c'est ce qui faisait annoncer « rien à livrer » avec des fichiers
 *  modifiés sous les yeux, le 2026-08-07. */
function git(args, { silencieux = false, brut = false } = {}) {
  try {
    const sortie = execFileSync('git', args, { cwd: ROOT, encoding: 'utf8' });
    return brut ? sortie : sortie.trim();
  } catch (err) {
    if (silencieux) return '';
    throw new Error(`git ${args[0]} : ${err.stderr?.trim() || err.message}`);
  }
}

function contenuA(ref, chemin) {
  const brut = git(['show', `${ref}:${chemin}`], { silencieux: true });
  if (!brut) return null;
  try {
    return JSON.parse(brut);
  } catch {
    return null;
  }
}

function contenuLocal(chemin) {
  try {
    return JSON.parse(readFileSync(join(ROOT, chemin), 'utf8'));
  } catch {
    return null;
  }
}

/**
 * Tout ce qu'il faut savoir AVANT de livrer, sans rien écrire.
 *
 * Exporté pour que la console l'affiche en permanence au lieu de le révéler
 * seulement à qui pense à lancer la répétition. Un bouton dont on ne voit pas
 * l'effet avant d'appuyer est un bouton qu'on n'appuie pas.
 *
 * N'exécute que des LECTURES git. Aucune écriture, aucun réseau.
 */
export function apercu() {
  const changements = changementsDe(git(['status', '--porcelain', '--', 'content/'], { brut: true }));
  // Un SECOND appel, sans filtre de chemin, pour voir ce qu'on n'emporte pas.
  // Deux appels plutôt qu'un filtrage : le premier garde exactement le
  // comportement éprouvé de la livraison, et le second n'y touche pas.
  const reste = resteDeCote(git(['status', '--porcelain'], { brut: true, silencieux: true }));

  const details = {};
  // La transition de statut se lit en comparant à HEAD, pas au disque seul.
  for (const c of changements) {
    details[c.chemin] = transitionDe(contenuA('HEAD', c.chemin), contenuLocal(c.chemin));
  }

  return {
    changements,
    details,
    reste,
    titre: changements.length ? titreDe(changements) : null,
    branche: changements.length
      ? nomDeBranche(
          new Date().toISOString().slice(0, 10),
          git(['branch', '--format=%(refname:short)']).split('\n'),
        )
      : null,
    // La branche courante part-elle de `main` ? Sinon la PR emportera aussi les
    // commits d'avant. On ne bloque pas — on le DIT, c'est parfois voulu.
    enAvance: git(['log', '--oneline', 'origin/main..HEAD'], { silencieux: true })
      .split('\n')
      .filter(Boolean)
      .slice(0, 5),
  };
}

/** Les lignes « ce qui reste » qu'on imprime et que la console affiche. Une
 *  seule formulation pour les deux, sinon elles divergent. */
function direLeReste({ exclu, laisse }) {
  const lignes = [];
  if (laisse.length) {
    lignes.push(
      `⚠ ${laisse.length} modification(s) NE partent pas dans cette livraison :`,
      ...laisse.slice(0, 8).map((c) => `    ${c}`),
      ...(laisse.length > 8 ? [`    … et ${laisse.length - 8} autres`] : []),
      '  Elles restent dans l’arbre de travail. À commiter à part si c’est voulu.',
    );
  }
  if (exclu.length) {
    lignes.push(
      `  (${exclu.length} fichier(s) d’inbox exclus à dessein : du texte tiers, jamais commité.)`,
    );
  }
  return lignes;
}

async function main() {
  const dryRun = process.argv.includes('--dry-run');
  const { changements, details, reste, titre, branche, enAvance } = apercu();

  if (!changements.length) {
    console.log('rien à livrer : aucun fichier de contenu modifié.');
    console.log('Publier un brouillon depuis l’atelier, puis relancer.');
    for (const l of direLeReste(reste)) console.log(l);
    return true;
  }

  const corps = corpsDe(changements, details);

  console.log(`branche  : ${branche}`);
  console.log(`titre    : ${titre}`);
  console.log(`fichiers : ${changements.length}`);
  for (const c of changements) console.log(`  ${c.chemin.padEnd(44)} ${details[c.chemin]}`);

  const resteDit = direLeReste(reste);
  if (resteDit.length) {
    console.log('');
    for (const l of resteDit) console.log(l);
  }

  if (enAvance.length) {
    console.log('');
    console.log('⚠ la branche courante a des commits que `main` n’a pas :');
    for (const l of enAvance) console.log(`    ${l}`);
    console.log('  ils seront DANS la pull request. Repartir de `main` si ce n’est pas voulu.');
  }

  if (dryRun) {
    console.log('');
    console.log('--dry-run : rien n’a été écrit.');
    return true;
  }

  git(['switch', '-c', branche]);
  // `commit -- <chemins>` commite EXACTEMENT ces fichiers depuis l'arbre de
  // travail, en ignorant l'index : d'autres modifications en attente ne peuvent
  // pas se glisser dans la livraison.
  git(['commit', '-m', titre, '--', ...changements.map((c) => c.chemin)]);
  git(['push', '-u', 'origin', branche]);

  // `--body-file` plutôt que `--body` : le corps est un tableau multi-ligne, et
  // le faire transiter par un argument de ligne de commande finit toujours par
  // se casser sur une apostrophe.
  const fichier = join(mkdtempSync(join(tmpdir(), 'livraison-')), 'corps.md');
  writeFileSync(fichier, corps);
  const url = execFileSync(
    'gh',
    ['pr', 'create', '--base', 'main', '--head', branche, '--title', titre, '--body-file', fichier],
    { cwd: ROOT, encoding: 'utf8' },
  ).trim();

  console.log('');
  console.log(`pull request ouverte : ${url}`);
  console.log('Elle n’est PAS fusionnée — c’est la relecture du diff qui décide.');
  return true;
}

// Exécuté seulement en ligne de commande : les tests importent les fonctions
// pures sans rien déclencher.
if (process.argv[1] && process.argv[1].endsWith('deliver.mjs')) {
  main()
    .then((ok) => process.exit(ok ? 0 : 1))
    .catch((err) => {
      console.error(err.message);
      process.exit(1);
    });
}
