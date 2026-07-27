// Transformation pure « brouillon d'éditeur → fichier content/poi ». Aucune I/O,
// aucun Firestore : tout ce qui décide vit ici, et `cli.js` ne fait qu'écrire ce
// qu'on lui rend. C'est ce qui rend cette pièce testable sans émulateur, comme
// `gtav-poi-ids.mjs` dont elle réutilise la frappe d'identifiants.

import { identityKey, mintId } from '../basemap/gtav-poi-ids.mjs';

/** Source d'identité des entrées nées de l'éditeur — partie stable de la clé
 *  écrite dans `processedFrom`, et ce sur quoi un run suivant se réapparie. */
export const EDITOR_SOURCE = 'editor';

/** L'éditeur ne pose que sur la carte du jeu à venir (spec D2). */
const GAME = 'leonida';

const CATEGORY_LABELS = {
  landmark: 'Lieu',
  collectible: 'Collectible',
  activity: 'Activité',
  safehouse: 'Planque',
  vehicle: 'Véhicule',
  event: 'Événement',
};

function generatedTitle(category, capturedOn) {
  return `${CATEGORY_LABELS[category] ?? category} sans titre — ${capturedOn}`;
}

/**
 * @param drafts     brouillons non appliqués, tels que lus dans `editor_drafts`
 * @param existing   [{ path, data }] — les fichiers actuels de content/poi
 * @param capturedOn date ISO courte, injectée pour que la fonction reste pure
 * @returns {{
 *   writes: Array<{path: string, data: object}>,  fichiers à écrire ou réécrire
 *   deletes: string[],                            chemins à supprimer
 *   applied: string[],                            brouillons à marquer appliqués
 *   skipped: Array<{id: string, reason: string}>, sans effet, mais classés
 *   conflicts: Array<{id: string, reason: string}> si non vide, N'ÉCRIRE RIEN
 * }}
 */
export function materialize(drafts, existing, { capturedOn }) {
  const byID = new Map(existing.map((entry) => [entry.data.id, entry]));
  const byProcessedFrom = new Map(
    existing.filter((entry) => entry.data.processedFrom).map((entry) => [entry.data.processedFrom, entry])
  );

  const writes = [];
  const deletes = [];
  const applied = [];
  const skipped = [];
  const conflicts = [];

  for (const draft of drafts) {
    if (draft.kind === 'create') {
      const category = draft.category;
      const key = identityKey(EDITOR_SOURCE, category, draft.id);

      // Déjà matérialisé — par un run précédent, ou par une entrée plus haut
      // dans CE lot. On se réapparie, on n'écrit pas une seconde entrée. Toute
      // l'idempotence tient là, et elle vient de la clé, pas d'un drapeau.
      if (byProcessedFrom.has(key)) {
        applied.push(draft.id);
        continue;
      }

      const id = mintId(GAME, category, key);
      if (byID.has(id)) {
        conflicts.push({ id: draft.id, reason: `l'id frappé ${id} existe déjà avec un autre processedFrom` });
        continue;
      }

      const sources = [`observation directe en jeu, ${capturedOn}`];
      if (draft.sourceContributionID) {
        sources.push(`contribution communautaire ${draft.sourceContributionID}`);
      }

      const data = {
        id,
        category,
        position: draft.position,
        title: { en: draft.title || generatedTitle(category, capturedOn) },
        status: 'draft',
        sources,
        processedFrom: key,
      };
      const entry = { path: `content/poi/${id}.json`, data };

      writes.push(entry);
      // Tenir les deux index à jour au fil du lot : sans ça, deux brouillons du
      // même run pourraient produire deux fichiers de même id sans que rien ne
      // le signale.
      byID.set(id, entry);
      byProcessedFrom.set(key, entry);
      applied.push(draft.id);
      continue;
    }

    if (draft.kind !== 'move' && draft.kind !== 'delete') {
      conflicts.push({ id: draft.id, reason: `kind inconnu : ${draft.kind}` });
      continue;
    }

    const target = byID.get(draft.targetPOIID);
    if (!target) {
      // Le POI a disparu du dépôt depuis la capture. Rien à faire, mais le
      // brouillon est classé : le laisser en attente le ferait resurgir à chaque
      // run, indéfiniment.
      skipped.push({ id: draft.id, reason: `POI introuvable : ${draft.targetPOIID}` });
      applied.push(draft.id);
      continue;
    }

    if (draft.kind === 'move') {
      writes.push({ path: target.path, data: { ...target.data, position: draft.position } });
      applied.push(draft.id);
      continue;
    }

    if (target.data.status === 'published') {
      // Pierre tombale : le socle embarqué ne se décompile pas du binaire, donc
      // supprimer le fichier laisserait l'entrée bien vivante chez tous les
      // clients qui l'ont déjà.
      writes.push({ path: target.path, data: { ...target.data, deleted: true } });
    } else {
      deletes.push(target.path);
    }
    applied.push(draft.id);
  }

  // Un conflit invalide le lot entier : appliquer la moitié d'un run laisserait
  // le dépôt dans un état que personne ne peut raisonner, et le brouillon fautif
  // reviendrait au run suivant sans qu'on sache ce qui a déjà été fait.
  if (conflicts.length) {
    return { writes: [], deletes: [], applied: [], skipped: [], conflicts };
  }

  return { writes, deletes, applied, skipped, conflicts };
}
