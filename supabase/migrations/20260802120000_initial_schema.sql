-- Schéma initial — portage de firestore.rules + functions/src/*.ts
-- Spec : docs/superpowers/specs/2026-08-02-migration-supabase-design.md
--
-- Trois invariants qui étaient des conventions applicatives côté Firestore
-- deviennent ici des contraintes que la base fait respecter : un vote par
-- personne (clé primaire), le niveau dérivé de l'XP (colonne générée), les
-- compteurs de votes (trigger). Voir les commentaires à chaque endroit.

-- ---------------------------------------------------------------------------
-- Profils
-- ---------------------------------------------------------------------------

create table public.profiles (
  uid uuid primary key references auth.users (id) on delete cascade,
  handle text not null unique,
  xp integer not null default 0,

  -- Portage de functions/src/xp.ts (LEVEL_THRESHOLDS). Une colonne générée
  -- supprime les DEUX copies actuelles de `levelForXP` : celle de la Function
  -- et celle que tools/content-cli duplique faute d'être compilée avec
  -- functions/ — duplication que le commentaire de xp.ts documente comme un
  -- pis-aller. Les noms de grades restent côté client : c'est de l'affichage
  -- localisé, pas une règle métier.
  level integer generated always as (
    case
      when xp >= 2000 then 5
      when xp >= 900 then 4
      when xp >= 400 then 3
      when xp >= 150 then 2
      when xp >= 50 then 1
      else 0
    end
  ) stored,

  is_premium boolean not null default false,

  -- Déposé par le rafraîchissement du classement. Nul tant qu'il n'a pas
  -- tourné — le Profil n'affiche alors pas de ligne de rang, plutôt qu'un zéro
  -- faux (même sémantique qu'aujourd'hui).
  rank integer,

  -- Anti-abus (spec §7, couche 5). `is_shadow_banned` porte sur l'auteur,
  -- `shadow_hidden` sur la contribution : c'est ce dernier que lisent le
  -- classement et les fragments publics, donc un ban se propage par une
  -- réécriture des contributions, jamais par une jointure sur le profil.
  is_shadow_banned boolean not null default false,
  flagged_burst_count integer not null default 0,

  -- Cooldown de soumission (spec §7, couche 3).
  last_submission_at timestamptz,

  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Progression synchronisée
-- ---------------------------------------------------------------------------

-- Un enregistrement par item, pas un blob unique : le dernier-écrivain-gagne
-- se fait par item, sinon un appareil resté hors-ligne longtemps écraserait
-- tout l'historique de l'autre. La clé primaire composite remplace la
-- convention d'identifiant `{kind}_{itemID}` de Firestore.
create table public.progression (
  uid uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('poi', 'trophy')),
  item_id text not null,
  found boolean not null,
  updated_at timestamptz not null,
  primary key (uid, kind, item_id)
);

-- ---------------------------------------------------------------------------
-- Contributions communautaires
-- ---------------------------------------------------------------------------

create table public.contributions (
  id uuid primary key default gen_random_uuid(),

  -- Nullable : la suppression de compte ANONYMISE les contributions approuvées
  -- au lieu de les supprimer (la donnée cartographique est préservée, seuls les
  -- champs identifiants sautent). `on delete set null` fait donc partie du
  -- contrat, pas d'un relâchement.
  author_uid uuid references auth.users (id) on delete set null,
  author_handle text not null,

  category text not null check (
    category in ('landmark', 'collectible', 'activity', 'safehouse', 'vehicle', 'event')
  ),
  title text not null check (length(btrim(title)) between 1 and 280),
  language_code text not null check (language_code in ('en', 'fr', 'es', 'it', 'de')),

  -- Coordonnées normalisées [0,1] sur l'image de carte — pas une projection
  -- géographique, d'où la distance euclidienne simple de la déduplication.
  position_x double precision not null check (position_x between 0 and 1),
  position_y double precision not null check (position_y between 0 and 1),

  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  shadow_hidden boolean not null default false,
  flagged_for_review boolean not null default false,

  upvotes integer not null default 0,
  downvotes integer not null default 0,

  created_at timestamptz not null default now()
);

create index contributions_author_idx on public.contributions (author_uid);
create index contributions_public_idx on public.contributions (category, status)
  where status = 'approved' and not shadow_hidden;
create index contributions_velocity_idx on public.contributions (author_uid, created_at);

-- ---------------------------------------------------------------------------
-- Votes
-- ---------------------------------------------------------------------------

-- « Un vote par personne » cesse d'être une convention d'identifiant composite
-- (`{spotId}_{uid}`) pour devenir une clé primaire. Revoter est un UPDATE, pas
-- un second enregistrement : l'invariant ne peut plus être contourné par un
-- appelant qui écrirait un identifiant différent.
create table public.votes (
  contribution_id uuid not null references public.contributions (id) on delete cascade,
  uid uuid not null references auth.users (id) on delete cascade,
  direction text not null check (direction in ('up', 'down')),
  updated_at timestamptz not null default now(),
  primary key (contribution_id, uid)
);

create index votes_uid_idx on public.votes (uid);

-- ---------------------------------------------------------------------------
-- Signalements
-- ---------------------------------------------------------------------------

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  contribution_id uuid not null references public.contributions (id) on delete cascade,
  reporter_uid uuid not null references auth.users (id) on delete cascade,
  reason text check (reason is null or length(reason) <= 280),
  created_at timestamptz not null default now(),
  -- Nouveau par rapport à Firestore, qui laissait un même utilisateur signaler
  -- en boucle : un signalement par personne et par spot suffit à alerter.
  unique (contribution_id, reporter_uid)
);

-- ---------------------------------------------------------------------------
-- Configuration applicative (remplace Remote Config)
-- ---------------------------------------------------------------------------

-- « Absent » est ici l'absence de ligne, ce qui rend les deux défauts opposés
-- de docs/ops/2026-07-27-sans-blaze.md lisibles sans contorsion :
-- backendFeaturesEnabled absent vaut FAUX (capacité qui n'existe pas encore),
-- communityContributionsEnabled absent vaut VRAI (coupe-circuit sur une
-- capacité qui existe). Côté Remote Config il fallait inspecter
-- `ConfigValue.source == .static` pour distinguer les deux.
create table public.app_config (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Jetons de notification (remplace les topics FCM)
-- ---------------------------------------------------------------------------

create table public.push_tokens (
  token text primary key,
  uid uuid not null references auth.users (id) on delete cascade,
  categories text[] not null default '{}',
  updated_at timestamptz not null default now()
);

create index push_tokens_categories_idx on public.push_tokens using gin (categories);

-- ---------------------------------------------------------------------------
-- Mode éditeur interne (build debug seulement)
-- ---------------------------------------------------------------------------

-- firestore.rules réservait `editor_drafts` à un UID écrit en dur
-- (`REMPLACER_PAR_UID_EDITEUR`), jamais renseigné. Une table conserve le même
-- défaut fermé — vide, personne ne passe — mais se renseigne par un INSERT au
-- lieu d'un redéploiement de règles.
create table public.editors (
  uid uuid primary key references auth.users (id) on delete cascade,
  note text,
  created_at timestamptz not null default now()
);

create table public.editor_drafts (
  id uuid primary key default gen_random_uuid(),
  author_uid uuid not null references auth.users (id) on delete cascade,
  payload jsonb not null,
  created_at timestamptz not null default now(),
  applied_at timestamptz
);

-- ---------------------------------------------------------------------------
-- Génération de pseudonyme (portage de functions/src/handle.ts)
-- ---------------------------------------------------------------------------

-- Listes originales à thème synthwave, jamais un terme Rockstar/GTA. Petites et
-- curées délibérément : aucune n'est tirée d'un dictionnaire qui pourrait
-- laisser fuiter une marque. À étendre à la main.
create or replace function public.generate_handle()
returns text
language sql
volatile
as $$
  select (array['NEON','CHROME','RETRO','ULTRA','MIDNIGHT','ELECTRIC','TURBO','CRIMSON'])[floor(random() * 8) + 1]
      || '-'
      || (array['FALCON','MIRAGE','DRIFTER','HORIZON','CIRCUIT','PANTHER','VORTEX','RUNNER'])[floor(random() * 8) + 1]
      || '-'
      || lpad(floor(random() * 100)::text, 2, '0');
$$;

-- ---------------------------------------------------------------------------
-- Création du profil à l'inscription (remplace createUserProfile)
-- ---------------------------------------------------------------------------

-- Là où Firebase utilisait un déclencheur d'authentification asynchrone — d'où
-- la fenêtre documentée dans submitContribution.ts où le profil n'existe pas
-- encore juste après l'inscription — un trigger Postgres s'exécute dans la
-- MÊME transaction que la création de l'utilisateur. La fenêtre disparaît, et
-- avec elle l'erreur « Profile not ready yet ».
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  candidate text;
begin
  -- `handle` est unique ; une collision sur 6 400 combinaisons est rare mais
  -- certaine à l'échelle. On réessaie plutôt que de faire échouer l'inscription.
  for _ in 1..10 loop
    candidate := public.generate_handle();
    begin
      insert into public.profiles (uid, handle) values (new.id, candidate);
      return new;
    exception when unique_violation then
      -- suffixe supplémentaire au prochain tour
      null;
    end;
  end loop;
  insert into public.profiles (uid, handle)
    values (new.id, public.generate_handle() || '-' || substr(new.id::text, 1, 4));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Compteurs de votes (remplace applyVoteDelta + la transaction de castVote)
-- ---------------------------------------------------------------------------

-- Portage exact de functions/src/vote.ts : revoter dans le même sens ne change
-- rien (UPDATE sans changement de direction), basculer déplace une voix d'un
-- compteur à l'autre, un premier vote en ajoute une.
--
-- L'XP est attribuée ici et pas dans la RPC, pour la même raison que la clé
-- primaire porte l'unicité : l'invariant devient impossible à contourner par un
-- appelant. Conditions reprises telles quelles de castVote.ts — seulement au
-- PREMIER vote positif (jamais sur une bascule bas→haut, qui laisserait un
-- voteur farmer de l'XP en boucle) et jamais pour soi-même.
create or replace function public.sync_vote_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_author uuid;
begin
  if tg_op = 'INSERT' then
    update public.contributions set
      upvotes = upvotes + (case when new.direction = 'up' then 1 else 0 end),
      downvotes = downvotes + (case when new.direction = 'down' then 1 else 0 end)
    where id = new.contribution_id
    returning author_uid into target_author;

    if new.direction = 'up' and target_author is not null and target_author <> new.uid then
      update public.profiles set xp = xp + 2 where uid = target_author;
    end if;

  elsif tg_op = 'UPDATE' then
    if new.direction is distinct from old.direction then
      update public.contributions set
        upvotes = upvotes + (case when new.direction = 'up' then 1 else -1 end),
        downvotes = downvotes + (case when new.direction = 'down' then 1 else -1 end)
      where id = new.contribution_id;
    end if;

  elsif tg_op = 'DELETE' then
    update public.contributions set
      upvotes = upvotes - (case when old.direction = 'up' then 1 else 0 end),
      downvotes = downvotes - (case when old.direction = 'down' then 1 else 0 end)
    where id = old.contribution_id;
  end if;

  return null;
end;
$$;

create trigger votes_sync_counts
  after insert or update or delete on public.votes
  for each row execute function public.sync_vote_counts();

-- ---------------------------------------------------------------------------
-- Classement (remplace leaderboard.ts + rebuildLeaderboard.ts)
-- ---------------------------------------------------------------------------

-- Classé sur l'XP et non sur le décompte : l'XP se gagne aussi par les votes
-- reçus, donc elle récompense ce que les autres ont jugé utile, pas le volume
-- produit. Départage par uid à XP égale, sinon l'ordre bougerait sans raison
-- d'un rafraîchissement à l'autre.
--
-- `shadow_hidden` est filtré ici comme dans les fragments publics : un auteur
-- shadow-banni voit son décompte tomber à zéro et disparaît du classement sans
-- qu'aucune règle ne le nomme.
create materialized view public.leaderboard as
select
  p.uid,
  p.handle,
  p.xp,
  c.approved_count,
  (row_number() over (order by p.xp desc, p.uid asc))::integer as rank
from public.profiles p
join lateral (
  select count(*)::integer as approved_count
  from public.contributions
  where author_uid = p.uid
    and status = 'approved'
    and not shadow_hidden
) c on true
where c.approved_count > 0
order by p.xp desc, p.uid asc
limit 100;

create unique index leaderboard_uid_idx on public.leaderboard (uid);

-- Rafraîchit le classement et redescend le rang sur les profils, d'un bloc.
-- `concurrently` exige l'index unique ci-dessus et évite de bloquer les
-- lectures pendant la reconstruction.
create or replace function public.refresh_leaderboard()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  refresh materialized view concurrently public.leaderboard;
  update public.profiles p
     set rank = l.rank
    from public.leaderboard l
   where p.uid = l.uid
     and p.rank is distinct from l.rank;
  update public.profiles p
     set rank = null
   where p.rank is not null
     and not exists (select 1 from public.leaderboard l where l.uid = p.uid);
end;
$$;

-- ---------------------------------------------------------------------------
-- Stockage : le bucket public qui sert le contenu
-- ---------------------------------------------------------------------------

-- Nommé `cdn` et pas `content` : les objets portent déjà un préfixe `content/`
-- (l'arborescence du site, volontairement indépendante de l'hébergeur), et un
-- bucket homonyme donnerait des URL en `.../public/content/content/manifest.json`.
insert into storage.buckets (id, name, public)
values ('cdn', 'cdn', true)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Valeurs de configuration initiales
-- ---------------------------------------------------------------------------

-- Ni `contentVersion` ni `communitySpotsVersion` : les deux viennent désormais
-- de manifestes servis par le CDN — un par producteur, ce qui supprime la
-- course à la clé entre la publication éditoriale et la reconstruction des
-- spots. Il ne reste ici que ce qui doit être modifiable à la main.
insert into public.app_config (key, value) values
  ('contentBaseURL', '""'::jsonb),
  ('backendFeaturesEnabled', 'false'::jsonb),
  ('communityContributionsEnabled', 'true'::jsonb)
on conflict (key) do nothing;
