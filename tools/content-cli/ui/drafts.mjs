// La porte « édition » de la console — lire, trier et réécrire un fichier de
// contenu.
//
// SON INVARIANT, et il tient en une phrase : **cette porte n'exécute aucun
// processus.** Il n'y a pas de `spawn`, pas d'`execFile`, pas de `child_process`
// dans ce fichier ni dans ce qu'il importe. Il n'y a donc rien à injecter — pas
// « rien d'exploitable », rien du tout, par construction.
//
// Ce qu'elle s'autorise est encadré par trois contraintes :
//
//   1. `kind` appartient à une liste fermée ;
//   2. `id` passe ID_PATTERN, qui exclut déjà `/`, `.` et l'espace ;
//   3. le fichier DOIT DÉJÀ EXISTER — l'atelier corrige, il ne crée pas. La
//      création reste à `pull-news`, qui sait frapper une clé d'identité stable.
//      Une porte qui ne sait qu'écraser un fichier existant se raisonne bien
//      mieux qu'une porte qui sait en créer.

import { createHash } from 'node:crypto';
import { existsSync, readFileSync, readdirSync, statSync, unlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { CONTENT, rawSchemas, schemaProblemsFor } from '../schemas.mjs';
import { problemsFor, problemsIfPublished } from '../publishable.mjs';
import { ID_PATTERN } from './actions.mjs';

/** Les seuls kinds que l'atelier ouvre. Les POI n'y sont pas : leur schéma
 *  demande des coordonnées, donc une carte pour les vérifier — un autre
 *  chantier, nommé hors périmètre dans la spec plutôt que laissé à demi fait. */
export const EDITABLE_KINDS = ['news', 'online-events'];

/** Les faits, à gauche de l'écran, jamais éditables.
 *
 *  Ce n'est pas de la mise en page : le fait cite ses sources MOT POUR MOT,
 *  marques déposées comprises, et la contrainte IP du projet interdit qu'il se
 *  retrouve recopié dans la prose. Les rendre non éditables rend le geste
 *  impossible par inadvertance. */
export const FACT_FIELDS = ['sourceClaim', 'sources', 'processedFrom'];

/** Les champs que l'atelier rend en formulaire, par kind. Tout le reste — les
 *  structures imbriquées d'un événement en ligne, par exemple — reste éditable
 *  en JSON brut, validé par le même schéma. */
export const EDITABLE_FIELDS = {
  news: [
    { field: 'title', type: 'localized' },
    { field: 'body', type: 'localized' },
    { field: 'category', type: 'enum' },
    { field: 'confidence', type: 'enum' },
    // Ajouté le 2026-08-08. Le statut était déjà écrivable par cette porte —
    // `writeDraft` n'a pas de chemin de publication à part — mais l'éditeur ne
    // le MONTRAIT pas : le seul geste possible était le bouton « Publier », donc
    // un aller sans retour. Dépublier demandait d'ouvrir le fichier à la main.
    { field: 'status', type: 'enum' },
  ],
  'online-events': [
    { field: 'title', type: 'localized' },
    { field: 'confidence', type: 'enum' },
    { field: 'status', type: 'enum' },
  ],
};

const SCHEMA_OF = { news: 'news', 'online-events': 'online-events' };

/** Les valeurs possibles d'un champ à énumération, lues dans le schéma —
 *  jamais recopiées ici, sinon elles divergeraient au premier ajout. */
export function enumValuesFor(kind, field) {
  return rawSchemas[SCHEMA_OF[kind]]?.properties?.[field]?.enum ?? null;
}

class RefusedError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.status = status;
  }
}

/** Refuse plutôt que de deviner. Rend le chemin absolu du fichier. */
export function resolvePath(kind, id) {
  if (!EDITABLE_KINDS.includes(kind)) throw new RefusedError(`kind non éditable : ${kind}`, 404);
  if (typeof id !== 'string' || !ID_PATTERN.test(id)) throw new RefusedError(`identifiant refusé : ${id}`, 400);
  const path = join(CONTENT, kind, `${id}.json`);
  // La ceinture APRÈS les bretelles : ID_PATTERN exclut déjà `/` et `.`, donc
  // ceci ne devrait jamais mordre. Il mord si quelqu'un élargit le motif un jour
  // sans repenser à ce fichier — et c'est exactement à ça que sert une ceinture.
  const expected = join(CONTENT, kind);
  if (!path.startsWith(`${expected}/`)) throw new RefusedError(`chemin refusé : ${id}`, 400);
  if (!existsSync(path)) throw new RefusedError(`aucun ${kind} nommé ${id}`, 404);
  return path;
}

/** L'empreinte du fichier tel qu'il est SUR LE DISQUE.
 *
 *  Sert à refuser une écriture qui écraserait une édition faite au terminal
 *  entre l'ouverture de la page et l'enregistrement. Sans elle, la console
 *  perdrait un travail en silence — la classe de panne que ce dépôt traque
 *  partout ailleurs. */
export function fingerprintOf(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex').slice(0, 16);
}

/** La date qui donne son âge à un brouillon. Les deux kinds ne la rangent pas
 *  au même endroit ; à défaut, la date du fichier, qui existe toujours. */
function dateOf(data, path) {
  return data.publishedAt ?? data.startsAt ?? statSync(path).mtime.toISOString().slice(0, 10);
}

/**
 * Le tri en trois piles — la raison d'être du tableau de bord.
 *
 * LE PIÈGE, et il vaut d'être écrit ici parce qu'il est invisible à la lecture :
 * presque toutes les règles de `problemsFor` ne mordent que sur
 * `status === 'published'`. Interroger un BROUILLON avec elles le déclare
 * publiable à tous les coups. Les six rumeurs du 2026-08-07 atterriraient dans
 * « attend ta décision », c'est-à-dire exactement le bruit que cette console
 * existe pour supprimer.
 *
 * D'où `problemsIfPublished`, qui les évalue COMME SI elles l'étaient.
 */
export function triage(kind) {
  const dir = join(CONTENT, kind);
  if (!existsSync(dir)) return { attend: [], retenu: [], casse: [] };

  const attend = [];
  const retenu = [];
  const casse = [];

  for (const file of readdirSync(dir).filter((f) => f.endsWith('.json'))) {
    const path = join(dir, file);
    const id = file.slice(0, -'.json'.length);

    let data;
    try {
      data = JSON.parse(readFileSync(path, 'utf8'));
    } catch (err) {
      casse.push({ kind, id, date: null, raisons: [`JSON illisible — ${err.message}`] });
      continue;
    }

    if (data.status !== 'draft') continue;

    const item = {
      kind,
      id,
      date: dateOf(data, path),
      titre: data.title?.fr ?? data.title?.en ?? id,
      // La première source, pour ouvrir l'article d'origine sans ouvrir la fiche.
      // Relire une actu, c'est presque toujours la comparer à ce dont elle sort ;
      // obliger à ouvrir l'éditeur pour atteindre le lien ajoutait deux clics à
      // chaque vérification.
      //
      // Une seule — les autres restent dans le volet « faits » de l'éditeur. La
      // carte répond à « d'où ça sort », pas à « toutes les sources ».
      source: Array.isArray(data.sources) ? data.sources[0] ?? null : null,
    };

    const schemaProblems = schemaProblemsFor(SCHEMA_OF[kind], data);
    if (schemaProblems.length) {
      casse.push({ ...item, raisons: schemaProblems });
      continue;
    }

    const blocages = problemsIfPublished({ kind, data });
    if (blocages.length) retenu.push({ ...item, raisons: blocages });
    else attend.push({ ...item, raisons: [] });
  }

  const parDate = (a, b) => String(a.date ?? '').localeCompare(String(b.date ?? ''));
  return { attend: attend.sort(parDate), retenu: retenu.sort(parDate), casse: casse.sort(parDate) };
}

/** Le triage de tous les kinds éditables, plus le total qui attend une
 *  décision — le seul chiffre qui mérite d'être gros sur la page. */
export function triageAll() {
  const parKind = Object.fromEntries(EDITABLE_KINDS.map((k) => [k, triage(k)]));
  const somme = (pile) => EDITABLE_KINDS.reduce((n, k) => n + parKind[k][pile].length, 0);
  return {
    parKind,
    totaux: { attend: somme('attend'), retenu: somme('retenu'), casse: somme('casse') },
  };
}

// ---------------------------------------------------------------------------
// Statistiques de la file de revue
//
// Calculées ici, pures, testables — le rendu n'a plus qu'à dessiner. Un graphe
// dont les chiffres sont calculés dans la page est un graphe qu'on ne peut pas
// vérifier autrement qu'à l'œil.
// ---------------------------------------------------------------------------

/** Les tranches d'âge. ORDINALES, pas nominales : leur ordre porte du sens, donc
 *  elles prennent une rampe à une seule teinte et jamais des couleurs d'identité.
 *  Cinq bornes, cinq pas de rampe. */
export const TRANCHES = [
  { label: "aujourd'hui", max: 0 },
  { label: '1 à 3 j', max: 3 },
  { label: '4 à 7 j', max: 7 },
  { label: '8 à 14 j', max: 14 },
  { label: 'plus de 14 j', max: Infinity },
];

/**
 * Un motif court pour l'axe. Le message complet reste disponible — il est plus
 * précis que ce qu'on écrirait, et c'est lui qui part dans l'infobulle.
 *
 * L'axe a besoin d'une étiquette lisible ; le diagnostic a besoin du texte exact.
 * Les deux, pas l'un OU l'autre.
 */
export function motifCourt(raison) {
  const r = String(raison ?? '');
  if (/rumor/i.test(r)) return 'rumeur';
  if (/needsRewrite|unwritten skeleton/i.test(r)) return 'rédaction non faite';
  if (/trademark/i.test(r)) return 'marque déposée';
  if (/verifiedBy/i.test(r)) return 'cheat non corroboré';
  if (/n’est pas un nom|n'est pas un nom/i.test(r)) return 'champ nominatif douteux';
  // Rien d'inventé : un motif inconnu garde son texte, tronqué pour l'axe.
  return r.length > 34 ? `${r.slice(0, 33)}…` : r || 'motif inconnu';
}

/** Le nombre de jours entre deux dates ISO (aaaa-mm-jj). Négatif ramené à 0 :
 *  un item daté de demain n'a pas un âge négatif, il est simplement neuf. */
export function ageEnJours(date, aujourdHui) {
  if (!date) return null;
  const jours = Math.floor((Date.parse(aujourdHui) - Date.parse(date)) / 86400000);
  return Number.isNaN(jours) ? null : Math.max(0, jours);
}

/**
 * Ce que le panneau de graphes affiche.
 *
 * @param {{parKind: object, totaux: object}} triage sortie de `triageAll`
 * @param {string} aujourdHui date ISO — paramètre plutôt qu'horloge interne,
 *   pour que le calcul se teste sans dépendre du jour où on le lance.
 */
export function statistiques(triage, aujourdHui) {
  const attend = Object.values(triage.parKind).flatMap((t) => t.attend);
  const retenu = Object.values(triage.parKind).flatMap((t) => t.retenu);

  const tranches = TRANCHES.map((t) => ({ label: t.label, n: 0 }));
  let plusAncien = null;
  for (const item of attend) {
    const age = ageEnJours(item.date, aujourdHui);
    if (age === null) continue;
    tranches[TRANCHES.findIndex((t) => age <= t.max)].n += 1;
    if (!plusAncien || age > plusAncien.jours) plusAncien = { jours: age, date: item.date, id: item.id };
  }

  // Un item peut être retenu pour PLUSIEURS motifs : on les compte tous, sinon le
  // total des motifs ne dirait pas ce qu'il y a à corriger.
  const parMotif = new Map();
  for (const item of retenu) {
    for (const raison of item.raisons ?? []) {
      const court = motifCourt(raison);
      const entree = parMotif.get(court) ?? { motif: court, n: 0, exemples: [] };
      entree.n += 1;
      if (entree.exemples.length < 3) entree.exemples.push(raison);
      parMotif.set(court, entree);
    }
  }

  return {
    totaux: triage.totaux,
    plusAncien,
    tranches,
    motifs: [...parMotif.values()].sort((a, b) => b.n - a.n || a.motif.localeCompare(b.motif)),
  };
}

/** Ce que l'écran d'un item a besoin de savoir. */
export function readDraft(kind, id) {
  const path = resolvePath(kind, id);
  const data = JSON.parse(readFileSync(path, 'utf8'));
  return {
    kind,
    id,
    data,
    fingerprint: fingerprintOf(path),
    faits: Object.fromEntries(FACT_FIELDS.filter((f) => f in data).map((f) => [f, data[f]])),
    champs: (EDITABLE_FIELDS[kind] ?? []).map((c) => ({ ...c, values: enumValuesFor(kind, c.field) })),
    // Ce que l'item deviendrait s'il était publié. Vide = le bouton « Publier »
    // s'active ; sinon la page affiche pourquoi il ne s'active pas.
    blocages: problemsIfPublished({ kind, data }),
  };
}

/**
 * Réécrit un brouillon. Refuse plutôt que d'écrire à moitié : la validation est
 * ENTIÈREMENT faite avant le premier octet écrit.
 *
 * La publication n'a pas de chemin à part — il suffit de passer `status:
 * 'published'` dans les données. `problemsFor` applique alors ses règles pour de
 * bon, et refuse une rumeur ou un squelette non rédigé. Un seul chemin d'écriture
 * signifie un seul endroit où se tromper.
 */
export function writeDraft(kind, id, { data, fingerprint }) {
  const path = resolvePath(kind, id);

  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw new RefusedError('corps attendu : { data: {...}, fingerprint }', 400);
  }
  if (fingerprintOf(path) !== fingerprint) {
    throw new RefusedError(
      'le fichier a changé sur le disque depuis son ouverture — recharger avant de réécrire',
      409,
    );
  }
  // Renommer un item par la porte d'édition reviendrait à en créer un autre et à
  // abandonner le premier. `pull-news` frappe ces identifiants sur le CONTENU du
  // fait pour être idempotent ; les laisser bouger ici casserait cette propriété.
  if (data.id !== id) throw new RefusedError(`l'identifiant ne peut pas changer (${data.id} ≠ ${id})`, 400);

  const problems = [
    ...schemaProblemsFor(SCHEMA_OF[kind], data),
    ...problemsFor({ kind, data }),
  ];
  if (problems.length) throw new RefusedError(problems.join('\n'), 422);

  writeFileSync(path, `${JSON.stringify(data, null, 2)}\n`);
  return { kind, id, fingerprint: fingerprintOf(path), status: data.status };
}

/**
 * Écarte un brouillon — supprime son fichier.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * TROIS REFUS, ET LE PREMIER EST LE SEUL QUI COMPTE VRAIMENT
 *
 *   1. **jamais un `published`.** Son fragment vit déjà sur le CDN : supprimer
 *      le fichier ne le retire pas de chez les clients, ça retire seulement la
 *      trace de ce qui a été publié. Pour retirer une actu en ligne il faut la
 *      repasser en `draft` PUIS republier — ce que le sélecteur de statut permet
 *      désormais, et ce que la suppression ne remplace pas ;
 *   2. l'empreinte, comme pour l'écriture : supprimer un fichier que quelqu'un
 *      vient de modifier, c'est jeter son travail sans le lui dire ;
 *   3. le fichier doit exister, sinon `resolvePath` a déjà refusé.
 *
 * Aucun processus lancé ici non plus — `unlinkSync`, rien d'autre. L'invariant
 * de la porte « édition » tient.
 *
 * La suppression n'est pas silencieuse pour autant : elle apparaît dans
 * `git status`, donc dans le panneau Livraison, donc dans une PR relue. Rien ne
 * disparaît du dépôt sans passer par là.
 */
export function deleteDraft(kind, id, { fingerprint } = {}) {
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

  unlinkSync(path);
  return { kind, id, ecarte: true, titre: data.title?.fr ?? data.title?.en ?? id };
}

export { RefusedError };
