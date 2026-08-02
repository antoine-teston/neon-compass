-- Couche communautaire — portage de castVote.ts, reportContribution.ts,
-- flagSuspiciousContribution.ts, flagCommunityBundlesDirty.ts et
-- notifyFollowedCategory.ts.
--
-- Ce qui était une Cloud Function callable devient une RPC quand elle n'est
-- qu'une écriture validée : l'app appelle une fonction SQL au lieu de faire un
-- aller-retour HTTP vers un runtime qui aurait de toute façon fini par écrire
-- ici. Ce qui était un déclencheur Firestore devient un trigger Postgres, dans
-- la même transaction que l'écriture qui le provoque — donc sans la fenêtre
-- pendant laquelle Firestore avait déjà écrit mais pas encore réagi.

-- ---------------------------------------------------------------------------
-- Voter
-- ---------------------------------------------------------------------------

-- Portage de castVote.ts. La transaction explicite disparaît : un INSERT … ON
-- CONFLICT DO UPDATE est atomique, et le trigger `votes_sync_counts` tient les
-- compteurs et l'XP. Il ne reste ici que ce que la Function faisait vraiment —
-- valider, écrire, relire les compteurs.
--
-- Revoter dans le même sens exécute quand même l'UPDATE : le trigger voit alors
-- `new.direction = old.direction`, ne bouge rien, et n'attribue aucune XP. C'est
-- exactement `applyVoteDelta(previous, next)` quand les deux sont égaux.
create or replace function public.cast_vote(spot_id uuid, vote_direction text)
returns table (upvotes integer, downvotes integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  voter uuid := auth.uid();
begin
  if voter is null then
    raise exception 'Sign in required.' using errcode = '42501';
  end if;
  if vote_direction not in ('up', 'down') then
    raise exception 'direction must be up or down.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.contributions c where c.id = spot_id) then
    raise exception 'Contribution not found.' using errcode = 'P0002';
  end if;

  insert into public.votes (contribution_id, uid, direction)
       values (spot_id, voter, vote_direction)
  on conflict (contribution_id, uid)
    do update set direction = excluded.direction, updated_at = now();

  return query
    select c.upvotes, c.downvotes from public.contributions c where c.id = spot_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Signaler
-- ---------------------------------------------------------------------------

-- Portage de reportContribution.ts. Apple 1.2 (contenu généré par les
-- utilisateurs) exige que le mécanisme existe avant même qu'une file de
-- modération le lise.
create or replace function public.report_contribution(spot_id uuid, report_reason text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  reporter uuid := auth.uid();
begin
  if reporter is null then
    raise exception 'Sign in required.' using errcode = '42501';
  end if;
  if report_reason is not null and length(report_reason) > 280 then
    raise exception 'reason must be at most 280 characters.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.contributions c where c.id = spot_id) then
    raise exception 'Contribution not found.' using errcode = 'P0002';
  end if;

  -- Un signalement par personne et par spot. Firestore laissait signaler en
  -- boucle ; la contrainte d'unicité rend le rejeu inoffensif au lieu de
  -- gonfler la file de modération.
  insert into public.reports (contribution_id, reporter_uid, reason)
       values (spot_id, reporter, report_reason)
  on conflict (contribution_id, reporter_uid) do nothing;
end;
$$;

-- ---------------------------------------------------------------------------
-- Monitoring de vélocité (portage de flagSuspiciousContribution.ts)
-- ---------------------------------------------------------------------------

-- Ne rejette JAMAIS et ne bloque JAMAIS automatiquement (spec §7, couche 5 :
-- « jamais un blocage automatique d'utilisateur légitime »). Il marque pour
-- revue prioritaire, et n'escalade en shadow-ban qu'à la RÉPÉTITION.
create or replace function public.flag_suspicious_contribution()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  recent_count integer;
  bursts integer;
begin
  if new.author_uid is null then return null; end if;

  select count(*) into recent_count
    from public.contributions
   where author_uid = new.author_uid
     and created_at >= now() - interval '5 minutes';

  if recent_count <= 5 then return null; end if;

  update public.contributions set flagged_for_review = true where id = new.id;

  select flagged_burst_count into bursts from public.profiles where uid = new.author_uid;

  if coalesce(bursts, 0) >= 1 then
    update public.profiles
       set is_shadow_banned = true, flagged_burst_count = coalesce(bursts, 0) + 1
     where uid = new.author_uid;
    -- Masquage RÉTROACTIF. Un shadow-ban qui ne vaudrait que pour l'avenir
    -- laisserait publiquement visible tout ce qui a déjà été approuvé, ce qui
    -- contredirait la garantie que cette fonction est censée porter.
    update public.contributions set shadow_hidden = true where author_uid = new.author_uid;
  else
    update public.profiles
       set flagged_burst_count = coalesce(bursts, 0) + 1
     where uid = new.author_uid;
  end if;

  return null;
end;
$$;

create trigger contributions_flag_suspicious
  after insert on public.contributions
  for each row execute function public.flag_suspicious_contribution();

-- ---------------------------------------------------------------------------
-- Fragments communautaires : le drapeau « périmé »
-- ---------------------------------------------------------------------------

-- Ligne unique. `id boolean primary key check (id)` est le motif singleton le
-- plus court qui interdise vraiment une seconde ligne.
create table public.community_bundle_state (
  id boolean primary key default true check (id),
  dirty boolean not null default true,
  built_at timestamptz
);
insert into public.community_bundle_state (id) values (true);

alter table public.community_bundle_state enable row level security;
-- Aucune politique cliente : c'est de l'état de production, pas du contenu.

-- Champs dont un changement modifie ce que les clients voient. `upvotes` et
-- `downvotes` en sont volontairement ABSENTS : un vote ne doit pas salir les
-- fragments, sinon le pic de votes déclencherait une reconstruction complète en
-- continu — précisément au moment où on ne peut pas se le permettre. Une heure
-- de fraîcheur sur un compteur est acceptable, d'autant que le client applique
-- déjà ses propres votes de façon optimiste.
create or replace function public.flag_community_bundles_dirty()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE'
     and new.status is not distinct from old.status
     and new.shadow_hidden is not distinct from old.shadow_hidden
     and new.position_x is not distinct from old.position_x
     and new.position_y is not distinct from old.position_y
     and new.title is not distinct from old.title
     and new.category is not distinct from old.category
     and new.author_handle is not distinct from old.author_handle then
    return null;
  end if;

  update public.community_bundle_state set dirty = true where id;
  return null;
end;
$$;

create trigger contributions_flag_bundles_dirty
  after insert or update or delete on public.contributions
  for each row execute function public.flag_community_bundles_dirty();

-- ---------------------------------------------------------------------------
-- Notifications de catégorie suivie (portage de notifyFollowedCategory.ts)
-- ---------------------------------------------------------------------------

-- **Une file, pas un appel sortant.** La Function appelait FCM directement
-- depuis le déclencheur. Le portage naïf serait `pg_net` depuis le trigger, ce
-- qui obligerait à loger une clé de service dans du SQL, rendrait l'envoi
-- non rejouable, et ferait dépendre une transaction d'écriture de la
-- disponibilité d'APNs.
--
-- Le trigger dépose donc une ligne, et une fonction planifiée vide la file.
-- Aucun secret ici, un rejeu gratuit, et une trace de ce qui a été envoyé.
create table public.push_outbox (
  id uuid primary key default gen_random_uuid(),
  contribution_id uuid references public.contributions (id) on delete cascade,
  category text not null,
  title text not null,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  attempts integer not null default 0
);

create index push_outbox_pending_idx on public.push_outbox (created_at) where sent_at is null;

alter table public.push_outbox enable row level security;
-- Aucune politique cliente.

create or replace function public.enqueue_followed_category_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Uniquement la TRANSITION vers approuvé, et jamais pour un spot masqué.
  if old.status = 'approved' or new.status <> 'approved' then return null; end if;
  if new.shadow_hidden then return null; end if;

  insert into public.push_outbox (contribution_id, category, title)
       values (new.id, new.category, new.title);
  return null;
end;
$$;

create trigger contributions_enqueue_push
  after update on public.contributions
  for each row execute function public.enqueue_followed_category_push();

