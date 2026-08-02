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
