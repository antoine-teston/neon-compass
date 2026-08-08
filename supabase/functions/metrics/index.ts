// La porte des nombres — ce que le moniteur a le droit de savoir.
//
// ─────────────────────────────────────────────────────────────────────────────
// POURQUOI CETTE FONCTION EXISTE PLUTÔT QU'UN ACCÈS DIRECT À LA BASE
//
// Le moniteur tourne sur un Raspberry Pi, sur le réseau local. La question n'est
// donc plus « qui peut l'atteindre » mais « que trouve-t-on dessus le jour où on
// le prend ». Trois réponses étaient possibles :
//
//   1. la clé `service_role` sur la carte SD — elle contourne RLS, donc perdre
//      le Pi c'est perdre la base. Écarté.
//   2. un rôle Postgres dédié en SELECT — mieux, mais il lit encore des LIGNES :
//      titres, pseudonymes, identifiants d'auteurs.
//   3. cette fonction, qui agrège côté serveur et ne rend que des décomptes.
//
// C'est la troisième. Le Pi ne détient qu'un jeton dont tout le pouvoir est de
// demander « combien ». Il ne peut rien écrire, et il ne peut lire le titre de
// personne.
//
// ─────────────────────────────────────────────────────────────────────────────
// DEUX SERRURES, PAS UNE
//
//   1. `verify_jwt` reste ACTIVÉ (le défaut). La plateforme exige une clé
//      d'API du projet avant que la moindre ligne d'ici ne s'exécute : le trafic
//      anonyme d'Internet n'atteint jamais ce code.
//   2. `X-Monitor-Token`, comparé en temps constant. La clé publiable étant dans
//      le binaire de l'app, la première serrure ne prouve rien à elle seule —
//      c'est celle-ci qui distingue le moniteur d'un client quelconque.
//
// Le jeton se pose avec `supabase secrets set MONITOR_TOKEN=…`. Sans lui, la
// fonction REFUSE tout : un secret manquant ne doit jamais ouvrir la porte,
// même « en attendant ».

import { timingSafeEqual } from 'node:crypto';
import { HttpError, adminClient, serveJSON } from '../_shared/auth.ts';
import { FENETRE_JOURS, assembler, type Brut } from './aggregate.ts';

const JOUR_MS = 24 * 60 * 60 * 1000;

/** Comparaison à temps constant.
 *
 *  Un `===` sur une chaîne s'arrête au premier caractère différent, ce qui rend
 *  le temps de réponse dépendant du préfixe et permet de deviner le jeton
 *  caractère par caractère. La longueur, elle, fuite de toute façon — on la
 *  compare donc franchement plutôt que de faire semblant. */
function memeJeton(fourni: string, attendu: string): boolean {
  const a = new TextEncoder().encode(fourni);
  const b = new TextEncoder().encode(attendu);
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

function exigerLeJeton(request: Request): void {
  const attendu = Deno.env.get('MONITOR_TOKEN');
  if (!attendu) throw new HttpError(503, 'Monitoring is not configured.');
  const fourni = request.headers.get('X-Monitor-Token');
  if (!fourni || !memeJeton(fourni, attendu)) throw new HttpError(401, 'Monitoring token required.');
}

/** Un décompte sans transfert de lignes (`head: true`), donc sans jamais faire
 *  entrer un titre ou un pseudonyme dans la mémoire de cette fonction.
 *
 *  Rend `null` en cas d'erreur plutôt que de lever : un compteur illisible ne
 *  doit pas emporter tout l'instantané. Le moniteur affiche « indisponible »
 *  pour celui-là et les autres restent lisibles — la même règle que les cartes
 *  de la console. */
// deno-lint-ignore no-explicit-any
async function compter(query: any): Promise<number | null> {
  const { count, error } = await query;
  return error ? null : (count ?? 0);
}

serveJSON(async (request: Request) => {
  exigerLeJeton(request);

  const admin = adminClient();
  const maintenant = Date.now();
  const aujourdhui = new Date(maintenant).toISOString().slice(0, 10);
  const depuis = new Date(maintenant - (FENETRE_JOURS - 1) * JOUR_MS)
    .toISOString()
    .slice(0, 10);

  // ⚠️ Les `select` ci-dessous sont VOLONTAIREMENT étroits. Pas de `title`, pas
  // d'`author_handle`, pas d'`author_uid`, pas d'`id`. Élargir l'un d'eux, c'est
  // faire entrer du nominatif dans une fonction dont c'est tout l'intérêt qu'il
  // n'y en ait pas — `aggregate.test.ts` le vérifie sur la sortie.
  const [attente, arrivees, approbations, bundle, push] = await Promise.all([
    admin
      .from('contributions')
      .select('created_at,category,flagged_for_review')
      .eq('status', 'pending')
      .order('created_at', { ascending: true }),
    admin
      .from('contributions')
      .select('created_at')
      .gte('created_at', `${depuis}T00:00:00Z`),
    admin
      .from('contributions')
      .select('approved_at')
      .gte('approved_at', `${depuis}T00:00:00Z`),
    admin.from('community_bundle_state').select('dirty,built_at').eq('id', true).maybeSingle(),
    admin.from('push_outbox').select('created_at,sent_at,attempts').is('sent_at', null),
  ]);

  const brut: Brut = {
    attente: attente.data ?? [],
    arrivees: (arrivees.data ?? []).map((r) => r.created_at),
    approbations: (approbations.data ?? []).map((r) => r.approved_at).filter(Boolean),
    bundle: bundle.data ?? null,
    push: push.data ?? [],
    totaux: {
      profils: await compter(admin.from('profiles').select('*', { count: 'exact', head: true })),
      approuvees: await compter(
        admin.from('contributions').select('*', { count: 'exact', head: true }).eq('status', 'approved'),
      ),
      rejetees: await compter(
        admin.from('contributions').select('*', { count: 'exact', head: true }).eq('status', 'rejected'),
      ),
      votes: await compter(admin.from('votes').select('*', { count: 'exact', head: true })),
      signalements: await compter(admin.from('reports').select('*', { count: 'exact', head: true })),
    },
  };

  return assembler(brut, aujourdhui, maintenant);
});
