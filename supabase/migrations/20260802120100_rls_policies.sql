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
-- **Le premier verrou est OUVERT par défaut, et c'est contre-intuitif.** Vérifié
-- sur le projet le 2026-08-02 : `pg_default_acl` accorde `arwdDxtm` — donc
-- SELECT, INSERT, UPDATE et DELETE — à `anon` ET `authenticated` sur toute
-- nouvelle table du schéma `public`. Un `grant select` posé par-dessus ne retire
-- rien : c'est une non-opération sur des privilèges déjà complets.
--
-- Sans le bloc de REVOKE de cette dernière migration, RLS serait la SEULE chose entre
-- un client anonyme et l'intégralité des données. Ça tient — une table avec RLS
-- et sans politique refuse tout — mais ça ne tient qu'à ça : un
-- `alter table … disable row level security` de trop, ou une politique
-- permissive ajoutée sans y penser, et tout est exposé, en écriture comprise.
--
-- Les politiques ci-dessous décrivent QUI voit QUOI. Les privilèges — qui a le
-- droit de poser la question — vivent dans `20260802140000_privileges.sql`,
-- seul et en dernier : `revoke … on all tables` ne peut porter que sur les
-- tables qui existent DÉJÀ, et les migrations suivantes en créent.
--
-- (`auto_expose_new_tables` dans supabase/config.toml documente l'inverse comme
-- nouveau défaut cloud, le réglage disparaissant au 2026-10-30. Ce projet est
-- encore sous l'ancien régime. Les REVOKE explicites sont corrects sous les
-- deux — c'est précisément pourquoi ils sont écrits.)
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

-- ---------------------------------------------------------------------------
-- Politiques
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;

create policy profiles_select_own on public.profiles
  for select to authenticated
  using (auth.uid() = uid);

-- Aucune politique d'écriture cliente : handle, XP, niveau et rang sont
-- calculés serveur (spec : « le niveau est calculé serveur, jamais par le
-- client »).

alter table public.progression enable row level security;

-- Le seul endroit où le client écrit vraiment.
create policy progression_all_own on public.progression
  for all to authenticated
  using (auth.uid() = uid)
  with check (auth.uid() = uid);

alter table public.contributions enable row level security;

-- Même condition que firestore.rules. Elle sert de filet : le chemin de lecture
-- normal passe par les fragments publiés sur Storage, où `shadow_hidden` est
-- filtré à la construction.
create policy contributions_select_public_or_own on public.contributions
  for select to anon, authenticated
  using (
    (status = 'approved' and not shadow_hidden)
    or (auth.uid() is not null and author_uid = auth.uid())
  );

alter table public.votes enable row level security;

create policy votes_select_own on public.votes
  for select to authenticated
  using (auth.uid() = uid);

-- `reports` : RLS active, AUCUNE politique. Y compris en lecture pour l'auteur
-- du signalement — firestore.rules refusait déjà `read, write`.
alter table public.reports enable row level security;

alter table public.app_config enable row level security;

-- `anon` compris : la configuration doit être lisible AVANT toute connexion,
-- puisqu'elle porte l'URL du contenu et les portails de fonctionnalités.
create policy app_config_select_all on public.app_config
  for select to anon, authenticated
  using (true);

alter table public.push_tokens enable row level security;

create policy push_tokens_all_own on public.push_tokens
  for all to authenticated
  using (auth.uid() = uid)
  with check (auth.uid() = uid);

-- `editors` : RLS active, aucune politique. La table se remplit par
-- `service_role` (CLI d'admin). Tant qu'elle est vide, `is_editor()` rend faux
-- et personne n'atteint les brouillons — même défaut fermé que l'UID en dur de
-- firestore.rules, mais renseignable sans redéployer quoi que ce soit.
alter table public.editors enable row level security;

alter table public.editor_drafts enable row level security;

create policy editor_drafts_all_editors on public.editor_drafts
  for all to authenticated
  using (public.is_editor())
  with check (public.is_editor() and author_uid = auth.uid());
