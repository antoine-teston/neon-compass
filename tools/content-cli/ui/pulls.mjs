// Les pull requests de contenu — lister, relire, et savoir ce qu'un merge fait.
//
// ─────────────────────────────────────────────────────────────────────────────
// LA RÈGLE QUI PORTE TOUT CE FICHIER
//
// Un merge sur `main` PUBLIE si et seulement s'il touche `content/news/` ou
// `content/online-events/`, et RIEN D'AUTRE sous `content/` (hors `inbox/` et
// `cdn-versions.json`). Le code, la doc et les workflows sont invisibles à cette
// règle : une PR de code ne publie jamais.
//
// Elle n'est pas inventée ici — elle vit dans `.github/workflows/content.yml`,
// job `publish-news`, sous forme de deux `grep`. La recopier en JS crée deux
// copies d'une même règle, c'est-à-dire la panne `deploy-rules` que ce dossier
// porte en cicatrice.
//
// D'où `MOTIF_TOLERES` et `MOTIF_PUBLIABLES`, gardés en CHAÎNES et non en
// littéraux d'expression : `pulls.test.mjs` les extrait du workflow et les
// compare à ceux-ci. Si le périmètre du workflow bouge sans que ce fichier
// suive, la suite tombe.
//
// ─────────────────────────────────────────────────────────────────────────────
// CE FICHIER NE FUSIONNE PAS
//
// Il lit, il classe, il refuse. La fusion elle-même passe par la porte
// « geste » (`POST /api/run`, action `merge-pr`), comme tout ce qui lance un
// processus dans cette console. Le verdict que le serveur consulte AVANT de
// lancer quoi que ce soit est celui que `vueDeLaPR` a posé dans `refus`.
//
// Deux formes circulent ici, et les confondre a déjà coûté la fonction entière :
// la forme BRUTE de `gh` (`files`, `statusCheckRollup`), seule jugeable par
// `refusDeFusion`, et la vue PUBLIQUE de `vueDeLaPR` (`nbFichiers`, `refus`),
// qui porte le verdict mais plus de quoi le recalculer.

import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { transitionDe } from '../deliver.mjs';

const run = promisify(execFile);
const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..', '..', '..');

/** Ce qui a le droit de bouger sans faire sortir le merge du périmètre.
 *  Recopié de `content.yml` — et comparé à lui par un test. */
export const MOTIF_TOLERES = '^content/(news|online-events|inbox)/|^content/cdn-versions\\.json$';

/** Ce dont la présence déclenche une publication. */
export const MOTIF_PUBLIABLES = '^content/(news|online-events)/';

const TOLERES = new RegExp(MOTIF_TOLERES);
const PUBLIABLES = new RegExp(MOTIF_PUBLIABLES);

/**
 * Ce qu'un merge de ces fichiers ferait.
 *
 * Pure — aucun réseau, aucun disque. C'est elle qu'on teste, et c'est elle qui
 * porte la phrase affichée en tête de la boîte de relecture.
 *
 * Trois verdicts, et le deuxième est le seul surprenant : une PR qui contient
 * de l'actu ET un POI ne publie **rien du tout**. Le verrou de versions est
 * global ; publier « juste l'actu » ferait repartir des collections dont
 * l'empreinte a bougé.
 */
export function effetDuMerge(fichiers) {
  const contenu = (fichiers ?? []).filter((f) => String(f).startsWith('content/'));
  const publiables = contenu.filter((f) => PUBLIABLES.test(f));
  const hors = contenu.filter((f) => !TOLERES.test(f));

  if (!publiables.length) return { verdict: 'sans-effet', publiables, hors };
  if (hors.length) return { verdict: 'hors-perimetre', publiables, hors };
  return { verdict: 'publie', publiables, hors };
}

/** La phrase que la console affiche. Toujours un nombre ou un mot — jamais une
 *  couleur seule, comme partout ailleurs dans cette console. */
export function phraseDeLEffet(effet) {
  const n = effet.publiables.length;
  if (effet.verdict === 'publie') return `Le merge PUBLIE ${n} entrée(s) sur le CDN.`;
  if (effet.verdict === 'hors-perimetre') {
    return `Le merge ne publiera RIEN : ${n} entrée(s) publiable(s) mais ${effet.hors.length} `
      + 'fichier(s) hors périmètre dans le même lot — le workflow refuse en bloc.';
  }
  return 'Le merge ne publie rien : aucune actu ni événement en ligne.';
}

/**
 * L'état des contrôles d'une PR.
 *
 * `content.yml` n'a AUCUNE étape en `continue-on-error` — vérifié, et asserté
 * par `pulls.test.mjs`. Son statut est donc digne de foi, contrairement à celui
 * de la Récolte, dont `runs.mjs` doit relire le journal. Si une étape tolérante
 * y apparaissait un jour, cette fonction deviendrait fausse en silence : c'est
 * l'assertion du test qui l'empêche.
 */
export function verdictDesControles(rollup) {
  const checks = rollup ?? [];
  if (!checks.length) return { etat: 'inconnu', detail: 'aucun contrôle rapporté' };

  const etatDe = (c) => c.status ?? c.state ?? null;
  const issueDe = (c) => c.conclusion ?? c.state ?? null;

  const enCours = checks.filter((c) => ['IN_PROGRESS', 'QUEUED', 'PENDING', 'WAITING'].includes(etatDe(c)));
  if (enCours.length) return { etat: 'en cours', detail: `${enCours.length} contrôle(s) en cours` };

  const rates = checks.filter((c) => !['SUCCESS', 'NEUTRAL', 'SKIPPED'].includes(issueDe(c)));
  if (rates.length) {
    return { etat: 'rouge', detail: rates.map((c) => c.name ?? c.context ?? '?').join(', ') };
  }
  return { etat: 'vert', detail: `${checks.length} contrôle(s) au vert` };
}

/**
 * Pourquoi cette PR ne peut PAS être fusionnée depuis la console, ou `null`.
 *
 * Appelée par le serveur AVANT de lancer `gh` — pas par la page. Le bouton
 * grisé est un confort ; ceci est la barrière. La console n'a aucune
 * authentification, et une requête forgée fusionnerait sinon n'importe quoi.
 *
 * C'est aussi ce qui règle la course « CI verte au chargement, commit arrivé
 * depuis » : le contrôle a lieu au moment du geste, pas à l'affichage.
 */
export function refusDeFusion(pr) {
  if (!pr) return { code: 404, message: 'pull request introuvable' };

  // La forme AVANT le fond. `files` absent n'est pas « zéro fichier » : c'est
  // qu'on nous a passé la vue publique (`nbFichiers`, `controles`, `refus`) au
  // lieu de la réponse de `gh`. Le `?? []` d'avant confondait les deux et
  // répondait « cette PR ne change aucun fichier » à une PR de huit ajouts —
  // un refus au motif FAUX, qui envoie chercher une PR vide qui n'existe pas.
  //
  // 500 et non 422 : ce n'est pas un état de la PR, c'est une panne de code.
  if (!Array.isArray(pr.files)) {
    return {
      code: 500,
      message: 'forme inattendue : cette PR ne porte pas ses fichiers bruts. '
        + '`refusDeFusion` attend la réponse de `gh`, pas la vue rendue par `vueDeLaPR`.',
    };
  }

  const fichiers = pr.files.map((f) => f.path);
  const horsContenu = fichiers.filter((f) => !String(f).startsWith('content/'));
  if (horsContenu.length) {
    return {
      code: 422,
      message:
        `cette PR touche ${horsContenu.length} fichier(s) hors de content/ — la console ne fusionne `
        + `que du contenu. Passer par GitHub. Premier : ${horsContenu[0]}`,
    };
  }
  if (!fichiers.length) return { code: 422, message: 'cette PR ne change aucun fichier' };

  const controles = verdictDesControles(pr.statusCheckRollup);
  if (controles.etat !== 'vert') {
    return {
      code: 412,
      message: `contrôles ${controles.etat} — ${controles.detail}. La fusion attend le vert.`,
    };
  }
  return null;
}

// ---------------------------------------------------------------------------
// Les appels `gh`
// ---------------------------------------------------------------------------

const CHAMPS = 'number,title,url,createdAt,headRefName,headRefOid,files,statusCheckRollup,isDraft';

async function gh(args) {
  const { stdout } = await run('gh', args, { cwd: ROOT, maxBuffer: 32 * 1024 * 1024 });
  return stdout;
}

/**
 * La réponse de `gh` traduite en ce que la console affiche.
 *
 * Pure, exportée, et surtout NOMMÉE : c'est ici que la forme brute devient la
 * forme publique, et cette frontière est la seule chose que ce fichier avait
 * laissée sans nom ni test. Le refus est calculé ICI, du côté où les fichiers
 * bruts existent encore — quiconque tient la vue publique tient déjà le verdict
 * et n'a pas à le recalculer.
 */
export function vueDeLaPR(pr) {
  const fichiers = (pr.files ?? []).map((f) => f.path);
  const effet = effetDuMerge(fichiers);
  return {
    numero: pr.number,
    titre: pr.title,
    url: pr.url,
    creeLe: pr.createdAt,
    branche: pr.headRefName,
    brouillon: Boolean(pr.isDraft),
    nbFichiers: fichiers.length,
    controles: verdictDesControles(pr.statusCheckRollup),
    effet: { ...effet, phrase: phraseDeLEffet(effet) },
    // `null` = fusionnable. La page grise le bouton ; le serveur relit cette
    // valeur-ci au moment du geste, il ne la recalcule pas.
    refus: refusDeFusion(pr),
  };
}

/** Les PR ouvertes, chacune avec son effet de merge et son refus éventuel.
 *
 *  Un SEUL appel : `gh pr list --json files,…` rend déjà les fichiers, ce qui
 *  évite la boucle par PR qu'on croyait nécessaire. */
export async function pullRequestsOuvertes({ limite = 20 } = {}) {
  const brut = await gh(['pr', 'list', '--state', 'open', '--limit', String(limite), '--json', CHAMPS]);
  const prs = JSON.parse(brut);
  return prs.map(vueDeLaPR);
}

/** Une PR par son numéro, telle que `pullRequestsOuvertes` la rend. */
export async function pullRequestOuverte(numero) {
  const toutes = await pullRequestsOuvertes({ limite: 50 });
  return toutes.find((p) => p.numero === Number(numero)) ?? null;
}

// ---------------------------------------------------------------------------
// La relecture, lue en git LOCAL
//
// Un seul appel réseau (`git fetch`), puis tout est local : pas de quota d'API,
// et `transitionDe` de `deliver.mjs` s'applique tel quel.
//
// Le fetch ne touche ni `HEAD` ni l'arbre de travail — il pose une référence
// sous un espace de noms à nous, effaçable par `git update-ref -d`.
// ---------------------------------------------------------------------------

const refDe = (numero) => `refs/console/pr/${Number(numero)}`;

async function git(args) {
  const { stdout } = await run('git', args, { cwd: ROOT, maxBuffer: 64 * 1024 * 1024 });
  return stdout;
}

/** Le contenu d'un fichier à une révision, ou `undefined` s'il n'y existe pas.
 *
 *  `undefined` et « illisible » sont DEUX choses — `transitionDe` s'en sert pour
 *  distinguer un item écarté d'un item cassé, et les confondre afficherait
 *  « draft → null » à un humain. */
async function contenuA(revision, chemin) {
  try {
    return JSON.parse(await git(['show', `${revision}:${chemin}`]));
  } catch (err) {
    // Le fichier n'existe pas à cette révision — le cas normal d'un ajout ou
    // d'une suppression, pas une panne.
    if (/exists on disk, but not in|does not exist|invalid object name|unknown revision/i.test(err.message)) {
      return undefined;
    }
    return null; // il existe mais ne se lit pas
  }
}

/**
 * Tout ce que la boîte de relecture affiche.
 *
 * `items` porte la lecture éditoriale — ce que le merge SIGNIFIE. `diff` porte
 * le texte brut, SANS filtre de chemin : un fichier inattendu dans la PR est
 * précisément ce qu'il faut voir, et la vue éditoriale ne le montrerait pas.
 */
export async function relectureDe(numero) {
  const pr = await pullRequestOuverte(numero);
  if (!pr) throw new Error(`pull request ${numero} introuvable ou déjà fermée`);

  const ref = refDe(numero);
  await git(['fetch', 'origin', `refs/pull/${Number(numero)}/head:${ref}`, '--force']);

  const base = await git(['merge-base', 'origin/main', ref]).then((s) => s.trim());
  const diff = await git(['diff', `${base}..${ref}`]);

  const chemins = (await git(['diff', '--name-only', `${base}..${ref}`]))
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean);

  const items = [];
  for (const chemin of chemins) {
    if (!/^content\/(news|online-events)\//.test(chemin)) continue;
    const avant = await contenuA(base, chemin);
    const apres = await contenuA(ref, chemin);
    items.push({
      chemin,
      kind: chemin.split('/')[1],
      id: chemin.split('/').pop().replace(/\.json$/, ''),
      transition: transitionDe(avant, apres),
      // `apres` peut être `undefined` (écarté) ou `null` (illisible) : la page
      // doit pouvoir dire lequel plutôt que d'afficher un bloc vide.
      illisible: apres === null,
      ecarte: apres === undefined,
      apercu: apres ? apercuEditorial(apres) : null,
    });
  }

  // La référence a servi : on l'efface. Sans ça le dépôt accumule une référence
  // par PR relue — constaté après trois relectures, `refs/console/pr/80` restant
  // là indéfiniment. Rouvrir la même PR refait un fetch, ce qui coûte un appel
  // et garantit qu'on relit l'état COURANT de la branche plutôt qu'un instantané
  // vieux d'une heure.
  await oublierLaReference(numero);

  return { pr, items, diff, chemins };
}

/** Ce qu'un relecteur lit vraiment : le texte, pas la structure. */
function apercuEditorial(data) {
  return {
    titre: data.title?.fr ?? data.title?.en ?? null,
    corps: data.body?.fr ?? data.body?.en ?? null,
    statut: data.status ?? null,
    confiance: data.confidence ?? null,
    categorie: data.category ?? null,
    sources: Array.isArray(data.sources) ? data.sources : [],
  };
}

/** Efface la référence posée par la relecture. Le dépôt n'a pas à garder une
 *  branche par PR relue. */
export async function oublierLaReference(numero) {
  try {
    await git(['update-ref', '-d', refDe(numero)]);
  } catch {
    /* déjà absente — rien à faire */
  }
}

// ---------------------------------------------------------------------------
// Le verdict de publication, APRÈS la fusion
//
// Le statut du run ne suffit pas, et pour une raison qui n'a rien à voir avec
// `continue-on-error` : `publish-news` reste VERT quand les identifiants
// Supabase manquent de l'environnement `production`. Il écrit un avertissement
// et s'arrête. Un « ✔ » lu sans le journal dirait « publié » à un contenu resté
// sur `main`.
// ---------------------------------------------------------------------------

/** Les quatre issues, dans l'ordre où on les cherche. Chaque motif est une
 *  chaîne réellement imprimée par `content.yml` ou par `cli.js`. */
export const MARQUEURS_PUBLICATION = [
  { verdict: 'identifiants absents', motif: /Publication automatique : impossible|Identifiants Supabase absents/ },
  { verdict: 'hors périmètre', motif: /sort du périmètre de la veille/ },
  { verdict: 'publié', motif: /publish: (\d+) objet\(s\) téléversé\(s\)/ },
  { verdict: 'rien à publier', motif: /Publication automatique : non/ },
];

/**
 * Le verdict tiré du seul journal.
 *
 * `indéterminé` n'est PAS un succès : c'est ce qu'on rend quand le journal ne
 * prouve rien. Un contrôle qui, dans le doute, approuve, ne contrôle rien.
 */
export function verdictDePublication(log) {
  const texte = String(log ?? '');
  if (!texte.trim()) return { verdict: 'indéterminé', detail: 'journal vide — rien à lire' };

  for (const { verdict, motif } of MARQUEURS_PUBLICATION) {
    const m = texte.match(motif);
    if (!m) continue;
    const detail = verdict === 'publié' ? `${m[1]} objet(s) téléversé(s)` : null;
    return { verdict, detail };
  }
  return { verdict: 'indéterminé', detail: 'aucun marqueur reconnu dans le journal' };
}
