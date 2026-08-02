// Pont vers Supabase — n'est importé que par les commandes qui écrivent
// (`deploy-cdn`, `set-config`), jamais par validate/check-publishable/translate,
// qui restent utilisables sans credentials.
//
// La clé `service_role` contourne RLS. Elle est lue dans l'environnement,
// jamais committée, et ne doit jamais atterrir dans le binaire de l'app — celui-ci
// n'emporte que la clé anonyme, dont tout le pouvoir est ce que les politiques
// RLS lui laissent.

import { createClient } from '@supabase/supabase-js';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';

/** Bucket public qui sert le contenu. Doit rester aligné sur la migration qui
 *  le crée (`20260802120000_initial_schema.sql`). */
export const BUCKET = 'cdn';

let clientInstance = null;

export function client() {
  if (clientInstance) return clientInstance;
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    throw new Error(
      'SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY doivent être définis — impossible de publier sans credentials'
    );
  }
  clientInstance = createClient(url, key, { auth: { persistSession: false } });
  return clientInstance;
}

function walk(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) out.push(...walk(full));
    else out.push(full);
  }
  return out;
}

/** En-têtes par objet.
 *
 *  Ils vivaient dans `firebase.json`, qui les posait par motif d'URL. Storage
 *  n'a pas d'équivalent : chaque objet porte les siens, posés au téléversement.
 *  C'est la seule différence de fond avec un hébergeur statique.
 *
 *  Les fragments sont sous un chemin qui porte leur version : leur contenu ne
 *  change JAMAIS pour une URL donnée, d'où `immutable` et un an de cache. Le
 *  manifeste est le seul qui bouge, d'où soixante secondes. */
function headersFor(objectPath) {
  if (objectPath.endsWith('.json.z')) {
    return {
      // DEFLATE brut : aucun type MIME ne le décrit, et surtout pas
      // `application/json`, qui inviterait un intermédiaire à essayer de le
      // lire. `content-encoding` serait le bon outil, mais Storage ne permet
      // pas de le poser (supabase-js#1883) — c'est l'app qui décompresse.
      contentType: 'application/octet-stream',
      cacheControl: '31536000, immutable',
    };
  }
  return { contentType: 'application/json', cacheControl: '60' };
}

/**
 * Téléverse l'arborescence produite par `build-cdn`.
 *
 * Ordre volontaire : les FRAGMENTS d'abord, le manifeste en DERNIER. Le
 * manifeste est ce qui fait basculer les clients sur la nouvelle version ; le
 * publier avant ses fragments ouvrirait une fenêtre pendant laquelle les
 * clients demandent des objets qui n'existent pas encore. Les fragments, eux,
 * sont sous une URL que personne ne connaît tant que le manifeste ne la nomme
 * pas — les téléverser tôt ne coûte rien.
 *
 * @param dist chemin du répertoire construit
 * @returns nombre d'objets téléversés
 */
export async function uploadSite(dist) {
  const supabase = client();
  const files = walk(dist).map((absolute) => ({
    absolute,
    // Les clés d'objet utilisent toujours `/`, y compris quand la publication
    // tourne sous Windows.
    objectPath: relative(dist, absolute).split(sep).join('/'),
  }));

  const manifests = files.filter((f) => f.objectPath.endsWith('manifest.json'));
  const fragments = files.filter((f) => !f.objectPath.endsWith('manifest.json'));

  let uploaded = 0;
  for (const file of [...fragments, ...manifests]) {
    const { error } = await supabase.storage
      .from(BUCKET)
      .upload(file.objectPath, readFileSync(file.absolute), {
        ...headersFor(file.objectPath),
        upsert: true,
      });
    if (error) throw new Error(`téléversement de ${file.objectPath} : ${error.message}`);
    uploaded++;
  }
  return uploaded;
}

/** Lit un paramètre d'`app_config`. `undefined` = aucune ligne. */
export async function getConfig(key) {
  const { data, error } = await client().from('app_config').select('value').eq('key', key).maybeSingle();
  if (error) throw new Error(`lecture de ${key} : ${error.message}`);
  return data?.value;
}

/** Pose un paramètre d'`app_config`. */
export async function setConfig(key, value) {
  const { error } = await client()
    .from('app_config')
    .upsert({ key, value, updated_at: new Date().toISOString() }, { onConflict: 'key' });
  if (error) throw new Error(`écriture de ${key} : ${error.message}`);
}

// ---------------------------------------------------------------------------
// Modération
// ---------------------------------------------------------------------------

/** Contributions en attente, les signalées d'abord.
 *
 *  L'ordre n'est pas cosmétique : `flagged_for_review` est posé par le
 *  monitoring de vélocité, qui ne bloque jamais personne mais demande un regard
 *  humain en priorité. Les noyer au milieu du reste reviendrait à ne pas les
 *  avoir marquées. */
export async function listPendingContributions() {
  const { data, error } = await client()
    .from('contributions')
    .select('id,category,title,author_handle,flagged_for_review,created_at')
    .eq('status', 'pending')
    .order('flagged_for_review', { ascending: false })
    .order('created_at', { ascending: true });
  if (error) throw new Error(`lecture des contributions en attente : ${error.message}`);
  return (data ?? []).map((row) => ({
    id: row.id,
    category: row.category,
    title: row.title,
    authorHandle: row.author_handle,
    flaggedForReview: row.flagged_for_review,
  }));
}

/** Approuve, et attribue l'XP de contribution approuvée.
 *
 *  L'XP est incrémentée ici et pas par un trigger : approuver est un geste
 *  humain, pas un effet de bord d'une écriture. Le NIVEAU, lui, se recalcule
 *  seul — c'est une colonne générée, il n'y a rien à écrire.
 *
 *  Le passage à `approved` fait par ailleurs deux choses via les triggers :
 *  il périme les fragments communautaires, et il dépose une notification dans
 *  la file pour ceux qui suivent la catégorie. */
export async function approveContribution(id) {
  const supabase = client();
  const { data: row, error } = await supabase
    .from('contributions')
    .update({ status: 'approved' })
    .eq('id', id)
    .select('author_uid')
    .single();
  if (error) throw new Error(`approbation de ${id} : ${error.message}`);

  if (row?.author_uid) {
    const { error: xpError } = await supabase.rpc('award_contribution_xp', { author: row.author_uid });
    if (xpError) throw new Error(`attribution d'XP à ${row.author_uid} : ${xpError.message}`);
  }
}

export async function rejectContribution(id) {
  const { error } = await client().from('contributions').update({ status: 'rejected' }).eq('id', id);
  if (error) throw new Error(`rejet de ${id} : ${error.message}`);
}

/** Shadow-ban, avec masquage RÉTROACTIF.
 *
 *  Un ban qui ne vaudrait que pour l'avenir laisserait publiquement visible tout
 *  ce qui a déjà été approuvé. Les deux écritures vont ensemble, toujours. */
export async function shadowBanUser(uid) {
  const supabase = client();
  const { error: profileError } = await supabase
    .from('profiles')
    .update({ is_shadow_banned: true })
    .eq('uid', uid);
  if (profileError) throw new Error(`shadow-ban de ${uid} : ${profileError.message}`);

  const { error: spotsError } = await supabase
    .from('contributions')
    .update({ shadow_hidden: true })
    .eq('author_uid', uid);
  if (spotsError) throw new Error(`masquage des spots de ${uid} : ${spotsError.message}`);
}

export async function liftShadowBan(uid) {
  const supabase = client();
  const { error: profileError } = await supabase
    .from('profiles')
    .update({ is_shadow_banned: false, flagged_burst_count: 0 })
    .eq('uid', uid);
  if (profileError) throw new Error(`levée du ban de ${uid} : ${profileError.message}`);

  const { error: spotsError } = await supabase
    .from('contributions')
    .update({ shadow_hidden: false })
    .eq('author_uid', uid);
  if (spotsError) throw new Error(`réaffichage des spots de ${uid} : ${spotsError.message}`);
}

// ---------------------------------------------------------------------------
// Coupe-circuit
// ---------------------------------------------------------------------------

/** Défaut OUVERT : pas de ligne = activé. Même sémantique que côté app. */
export async function getCommunityContributionsEnabled() {
  return (await getConfig('communityContributionsEnabled')) !== false;
}

export async function setCommunityContributionsEnabled(enabled) {
  await setConfig('communityContributionsEnabled', enabled);
}

// ---------------------------------------------------------------------------
// Brouillons du mode éditeur
// ---------------------------------------------------------------------------

export async function listEditorDrafts() {
  const { data, error } = await client()
    .from('editor_drafts')
    .select('id,payload')
    .is('applied_at', null)
    .order('created_at', { ascending: true });
  if (error) throw new Error(`lecture des brouillons : ${error.message}`);
  return (data ?? []).map((row) => ({ ...row.payload, id: row.id }));
}

export async function markEditorDraftsApplied(ids) {
  if (!ids?.length) return;
  const { error } = await client()
    .from('editor_drafts')
    .update({ applied_at: new Date().toISOString() })
    .in('id', ids);
  if (error) throw new Error(`archivage des brouillons : ${error.message}`);
}
