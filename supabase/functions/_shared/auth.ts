// Socle commun aux Edge Functions : identifier l'appelant, et parler à la base
// avec les droits qu'il faut.
//
// Deux clients, et la distinction est la charnière de tout le modèle de sécurité :
//
//   - `callerClient` porte le JWT de l'appelant. RLS s'applique. C'est lui qui
//     répond à « qui es-tu ».
//   - `adminClient` porte `service_role`. RLS ne s'applique PAS. C'est lui qui
//     écrit ce que le client n'a pas le droit d'écrire — exactement ce que
//     faisaient les Cloud Functions avec l'Admin SDK.
//
// Ne jamais utiliser le second pour lire l'identité : `service_role` peut tout
// voir, donc il ne prouve rien sur l'appelant.

import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2';

/// Le `code` est ce que le client LIT ; le `message` est ce qu'un humain lit
/// dans un journal.
///
/// La distinction n'est pas décorative. Les messages d'ici sont de l'anglais en
/// dur : les afficher tels quels donnerait de l'anglais à un francophone. Le
/// client traduit donc un code machine, et le statut HTTP ne lui sert que de
/// repli — ce qui est indispensable pour les DEUX 400 de `submit-contribution`
/// (forme invalide et vocabulaire banni), que rien d'autre ne distingue.
///
/// `retryAfter` porte les secondes du cooldown, plutôt que de les laisser
/// enfouies dans une phrase anglaise où il faudrait aller les repêcher.
///
/// Les deux champs sont OPTIONNELS et n'apparaissent dans la réponse que s'ils
/// sont posés : les autres fonctions ne changent pas de contrat.
export class HttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly code?: string,
    readonly retryAfter?: number,
  ) {
    super(message);
  }
}

export function adminClient(): SupabaseClient {
  return createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );
}

/** UID de l'appelant, ou 401.
 *
 *  Le JWT est vérifié par la plateforme avant même d'atteindre ce code (sauf
 *  `verify_jwt = false`, réservé aux webhooks) ; ce qui suit ne fait que le
 *  décoder pour en tirer l'identité. */
export async function requireUser(request: Request): Promise<string> {
  const authorization = request.headers.get('Authorization');
  if (!authorization) throw new HttpError(401, 'Sign in required.');

  const caller = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authorization } }, auth: { persistSession: false } },
  );

  const { data, error } = await caller.auth.getUser();
  if (error || !data.user) throw new HttpError(401, 'Sign in required.');
  return data.user.id;
}

/** Le corps JSON d'un refus.
 *
 *  Exporté pour être testable : `serveJSON` appelle `Deno.serve`, donc il ne se
 *  vérifie pas sans lever un serveur — alors que c'est ce corps, et lui seul,
 *  que le client sait lire.
 *
 *  Les clés absentes ne sont pas sérialisées à `undefined` mais bien omises :
 *  un `retryAfter: null` obligerait le client à distinguer « pas de cooldown »
 *  de « cooldown inconnu ». */
export function errorBody(error: HttpError): Record<string, unknown> {
  const body: Record<string, unknown> = { error: error.message };
  if (error.code !== undefined) body.code = error.code;
  if (error.retryAfter !== undefined) body.retryAfter = error.retryAfter;
  return body;
}

/** Enveloppe commune : JSON en sortie, erreurs typées en statut HTTP.
 *
 *  Sans elle, chaque fonction rendrait ses erreurs à sa façon et le client
 *  devrait deviner. `HttpError` porte le statut, tout le reste est un 500 —
 *  et son message ne part PAS au client : une erreur de base peut contenir un
 *  fragment de requête, donc de schéma. */
export function serveJSON(handler: (request: Request) => Promise<unknown>): void {
  Deno.serve(async (request) => {
    try {
      const body = await handler(request);
      return new Response(JSON.stringify(body ?? {}), {
        headers: { 'Content-Type': 'application/json' },
      });
    } catch (error) {
      if (error instanceof HttpError) {
        return new Response(JSON.stringify(errorBody(error)), {
          status: error.status,
          headers: { 'Content-Type': 'application/json' },
        });
      }
      console.error(error);
      return new Response(JSON.stringify({ error: 'Internal error.' }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });
    }
  });
}
