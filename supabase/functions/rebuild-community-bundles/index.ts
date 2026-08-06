// Reconstruction des fragments de spots communautaires — portage de
// functions/src/rebuildCommunityBundles.ts + communityBundles.ts.
//
// Les fragments partent sur Storage, pas en base : c'est le même chemin que le
// contenu éditorial, et pour la même raison — de la distribution de fichiers,
// pas une charge de base. Ils ont en revanche LEUR PROPRE manifeste, parce que
// leurs producteurs sont distincts : ceux-ci se reconstruisent au fil des
// approbations, l'éditorial se publie à la main. Deux producteurs sur un même
// fichier, c'est une course à la clé ; deux fichiers n'en ont aucune.

import { adminClient, serveJSON } from '../_shared/auth.ts';

/** Valeur du champ `collection` des fragments, et clé du cache client. Doit
 *  rester identique à `CommunityBundleVersionProvider.collectionName` côté
 *  Swift — la valeur est dupliquée des deux côtés d'une frontière réseau. */
const BUNDLE_COLLECTION = 'community_spots';

/** Aligné sur `ContentBundle.chunkSize` côté Swift. */
const CHUNK_SIZE = 500;

/** Reconstruction forcée passé ce délai, même si rien n'est « sale ».
 *
 *  Sans elle les compteurs de votes seraient figés à jamais : un vote ne salit
 *  délibérément pas les fragments (voir le trigger
 *  `flag_community_bundles_dirty`), sinon le pic de votes déclencherait une
 *  reconstruction en continu — précisément au moment où on ne peut pas se le
 *  permettre. */
const FORCED_REBUILD_INTERVAL_MS = 60 * 60 * 1000;

const BUCKET = 'cdn';

function chunked<T>(items: T[], size = CHUNK_SIZE): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  // Une collection vide produit UN fragment vide plutôt qu'aucun : sinon le
  // dernier fragment d'une collection qui se vide resterait servi, et les
  // clients continueraient de lire des spots retirés.
  return out.length ? out : [[]];
}

/** DEFLATE brut (RFC 1951) — exactement ce que `NSData.decompressed(using:
 *  .zlib)` attend côté iOS, et ce que produit `zlib.deflateRawSync` côté
 *  outillage. Storage ne compresse pas à la volée et ne permet pas de poser
 *  `Content-Encoding` (supabase-js#1883), donc l'app décompresse elle-même. */
async function deflateRaw(text: string): Promise<Uint8Array> {
  const stream = new Blob([text]).stream().pipeThrough(new CompressionStream('deflate-raw'));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

serveJSON(async () => {
  const admin = adminClient();

  const { data: state, error: stateError } = await admin
    .from('community_bundle_state')
    .select('dirty,built_at,version')
    .eq('id', true)
    .single();
  if (stateError) throw stateError;

  const builtAtMs = state.built_at ? new Date(state.built_at).getTime() : 0;
  const stale = Date.now() - builtAtMs >= FORCED_REBUILD_INTERVAL_MS;
  if (!state.dirty && !stale) return { rebuilt: false };

  // `shadow_hidden` est filtré ICI, côté application. Le client ne lit plus la
  // table `contributions` sur ce chemin, donc la politique RLS qui portait ce
  // filtre n'y protège plus rien. C'est le point de vigilance du chantier — et
  // ce n'est pas le seul endroit qui applique la règle : la vue `leaderboard`
  // l'applique aussi, sur son propre chemin d'agrégation. Un troisième chemin
  // devrait rejoindre cette liste plutôt que la contredire en silence.
  const { data: spots, error: spotsError } = await admin
    .from('contributions')
    .select('id,author_uid,author_handle,category,title,language_code,position_x,position_y,status,upvotes,downvotes,approved_at')
    .eq('status', 'approved')
    .eq('shadow_hidden', false)
    .order('id', { ascending: true });
  if (spotsError) throw spotsError;

  // Projection EXPLICITE vers ce qu'un fragment porte, et vers les clés exactes
  // que `Contribution` décode côté Swift — `position` y est un objet imbriqué,
  // là où la table stocke deux scalaires. Un `...row` laisserait partir vers les
  // clients tout champ ajouté côté serveur.
  const items = (spots ?? []).map((row) => ({
    id: row.id,
    authorUid: row.author_uid,
    authorHandle: row.author_handle,
    category: row.category,
    title: row.title,
    languageCode: row.language_code,
    position: { x: row.position_x, y: row.position_y },
    status: row.status,
    upvotes: row.upvotes ?? 0,
    downvotes: row.downvotes ?? 0,
    // La date d'APPARITION sur la carte, sur laquelle le volet Social trie sa
    // section « À découvrir ». Publiée en chaîne ISO 8601 telle que Postgres la
    // sérialise ; `Contribution` la parse à la main côté client, parce que tout
    // le décodage de contenu passe par un `JSONDecoder()` nu, dont la stratégie
    // par défaut refuse une chaîne ISO 8601.
    //
    // Nulle sur les lignes approuvées avant l'ajout de la colonne dont le
    // rétro-remplissage n'aurait pas abouti : le client les range en fin de
    // section plutôt que d'échouer.
    approvedAt: row.approved_at ?? null,
  }));

  const version = state.version + 1;
  const chunks = chunked(items);

  // Les FRAGMENTS d'abord, le manifeste en DERNIER : c'est le manifeste qui fait
  // basculer les clients sur la nouvelle version, le publier avant ses fragments
  // ouvrirait une fenêtre où ils demandent des objets qui n'existent pas encore.
  for (const [index, chunkItems] of chunks.entries()) {
    const body = await deflateRaw(
      `${JSON.stringify({ collection: BUNDLE_COLLECTION, chunk: index, items: chunkItems })}\n`,
    );
    const { error } = await admin.storage
      .from(BUCKET)
      .upload(`content/${BUNDLE_COLLECTION}/v${version}/${index}.json.z`, body, {
        contentType: 'application/octet-stream',
        cacheControl: '31536000, immutable',
        upsert: true,
      });
    if (error) throw error;
  }

  const manifest = JSON.stringify({ version, chunks: chunks.length, count: items.length });
  const { error: manifestError } = await admin.storage
    .from(BUCKET)
    .upload(`content/${BUNDLE_COLLECTION}/manifest.json`, new TextEncoder().encode(`${manifest}\n`), {
      contentType: 'application/json',
      cacheControl: '60',
      upsert: true,
    });
  if (manifestError) throw manifestError;

  const { error: markError } = await admin
    .from('community_bundle_state')
    .update({ dirty: false, built_at: new Date().toISOString(), version })
    .eq('id', true);
  if (markError) throw markError;

  return { rebuilt: true, version, chunks: chunks.length, count: items.length };
});
