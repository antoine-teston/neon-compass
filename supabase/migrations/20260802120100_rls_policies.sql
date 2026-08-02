-- Politiques RLS et droits — portage de firestore.rules.
--
-- Principe repris tel quel : le client ne fait qu'ÉCRIRE là où il ne peut nuire
-- qu'à lui-même (sa progression, son jeton de push). Tout le reste —
-- contributions, votes, signalements, profils, configuration — n'a AUCUNE
-- politique d'écriture, donc aucune écriture cliente n'est possible. Les Edge
-- Functions et les RPC `security definer` sont le seul chemin, comme les Cloud
-- Functions l'étaient.
--
-- DEUX verrous, pas un. C'est le piège de cette plateforme, et il ne ressemble
-- à rien de ce que faisait Firestore :
--
--   1. les GRANT décident si le rôle peut TOUCHER la table ;
--   2. les politiques RLS décident QUELLES LIGNES il voit.
--
-- Depuis que `auth_expose_new_tables` est éteint par défaut (voir
-- supabase/config.toml), une table nouvellement créée n'est exposée à AUCUN
-- rôle de l'API tant qu'on ne l'a pas accordée explicitement. Une politique
-- parfaite sur une table sans GRANT donne « permission denied », pas un
-- résultat vide — et le message ne dit pas lequel des deux verrous a mordu.
-- D'où les GRANT écrits ici table par table, à côté de leurs politiques.
--
-- Rappel : `service_role` contourne RLS mais PAS les GRANT.

-- ---------------------------------------------------------------------------
-- Aide : cet utilisateur est-il éditeur ?
-- ---------------------------------------------------------------------------

-- `security definer` parce qu'une politique s'évalue avec les droits de
-- l'appelant : un `exists (select 1 from editors …)` écrit directement dans la
-- politique d'`editor_drafts` se ferait refuser par la RLS d'`editors`
-- elle-même, et personne ne passerait jamais — un défaut fermé, mais pour la
-- mauvaise raison, et impossible à diagnostiquer.
create or replace function public.is_editor()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.editors where uid = auth.uid());
$$;

revoke all on function public.is_editor() from public;
grant execute on function public.is_editor() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- profiles — lecture de son seul profil
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;

create policy profiles_select_own on public.profiles
  for select to authenticated
  using (auth.uid() = uid);

grant select on public.profiles to authenticated;
grant all on public.profiles to service_role;

-- Aucune politique d'écriture cliente : handle, XP, niveau et rang sont
-- calculés serveur (spec : « le niveau est calculé serveur, jamais par le
-- client »).

-- ---------------------------------------------------------------------------
-- progression — le seul endroit où le client écrit vraiment
-- ---------------------------------------------------------------------------

alter table public.progression enable row level security;

create policy progression_all_own on public.progression
  for all to authenticated
  using (auth.uid() = uid)
  with check (auth.uid() = uid);

grant select, insert, update, delete on public.progression to authenticated;
grant all on public.progression to service_role;

-- ---------------------------------------------------------------------------
-- contributions — approuvées et non masquées, plus les siennes
-- ---------------------------------------------------------------------------

alter table public.contributions enable row level security;

-- Même condition que firestore.rules. Elle sert de filet : le chemin de lecture
-- normal passe désormais par les fragments publiés sur Storage, où
-- `shadow_hidden` est filtré à la construction.
create policy contributions_select_public_or_own on public.contributions
  for select to anon, authenticated
  using (
    (status = 'approved' and not shadow_hidden)
    or (auth.uid() is not null and author_uid = auth.uid())
  );

grant select on public.contributions to anon, authenticated;
grant all on public.contributions to service_role;

-- ---------------------------------------------------------------------------
-- votes — chacun voit les siens
-- ---------------------------------------------------------------------------

alter table public.votes enable row level security;

create policy votes_select_own on public.votes
  for select to authenticated
  using (auth.uid() = uid);

grant select on public.votes to authenticated;
grant all on public.votes to service_role;

-- ---------------------------------------------------------------------------
-- reports — aucun accès client, dans les deux sens
-- ---------------------------------------------------------------------------

alter table public.reports enable row level security;
-- Ni GRANT ni politique. Y compris en lecture pour l'auteur du signalement :
-- firestore.rules refusait déjà `read, write` sur `reports`.
grant all on public.reports to service_role;

-- ---------------------------------------------------------------------------
-- app_config — lecture publique
-- ---------------------------------------------------------------------------

alter table public.app_config enable row level security;

-- `anon` compris : la configuration doit être lisible AVANT toute connexion,
-- puisqu'elle porte l'URL du contenu et les portails de fonctionnalités.
create policy app_config_select_all on public.app_config
  for select to anon, authenticated
  using (true);

grant select on public.app_config to anon, authenticated;
grant all on public.app_config to service_role;

-- ---------------------------------------------------------------------------
-- push_tokens — chacun gère les siens
-- ---------------------------------------------------------------------------

alter table public.push_tokens enable row level security;

create policy push_tokens_all_own on public.push_tokens
  for all to authenticated
  using (auth.uid() = uid)
  with check (auth.uid() = uid);

grant select, insert, update, delete on public.push_tokens to authenticated;
grant all on public.push_tokens to service_role;

-- ---------------------------------------------------------------------------
-- editors / editor_drafts — mode éditeur interne, build debug
-- ---------------------------------------------------------------------------

alter table public.editors enable row level security;
-- Ni GRANT ni politique : la table se remplit par `service_role` (CLI d'admin).
-- Tant qu'elle est vide, `is_editor()` rend faux et personne n'atteint les
-- brouillons — le défaut est fermé, comme l'UID en dur de firestore.rules,
-- mais renseignable sans redéployer quoi que ce soit.
grant all on public.editors to service_role;

alter table public.editor_drafts enable row level security;

create policy editor_drafts_all_editors on public.editor_drafts
  for all to authenticated
  using (public.is_editor())
  with check (public.is_editor() and author_uid = auth.uid());

grant select, insert, update, delete on public.editor_drafts to authenticated;
grant all on public.editor_drafts to service_role;

-- ---------------------------------------------------------------------------
-- leaderboard — vue matérialisée, publique
-- ---------------------------------------------------------------------------

-- Une vue matérialisée ne porte pas de RLS : elle s'ouvre ou se ferme par les
-- seuls droits. Publique ici, comme `leaderboards` l'était dans
-- firestore.rules — elle ne contient aucune donnée personnelle, le handle étant
-- généré par nous et jamais saisi.
revoke all on public.leaderboard from public;
grant select on public.leaderboard to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Fonctions internes — jamais appelables depuis l'API
-- ---------------------------------------------------------------------------

-- Ces quatre-là ne sont invoquées que par des triggers ou par `service_role`.
-- Les laisser exécutables par `anon`/`authenticated` exposerait un
-- rafraîchissement de classement (coûteux) et un générateur de pseudonyme à
-- n'importe quel appelant.
revoke all on function public.generate_handle() from public;
revoke all on function public.handle_new_user() from public;
revoke all on function public.sync_vote_counts() from public;
revoke all on function public.refresh_leaderboard() from public;

-- `service_role` seulement. `generate_handle` est appelée par l'Edge Function
-- de régénération de pseudonyme ; l'ouvrir à `authenticated` laisserait
-- n'importe qui tirer des noms sans passer par le compteur de tentatives.
grant execute on function public.generate_handle() to service_role;
grant execute on function public.refresh_leaderboard() to service_role;
