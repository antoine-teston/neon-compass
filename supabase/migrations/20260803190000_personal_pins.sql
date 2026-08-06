-- Le carnet d'épingles, synchronisé pour les abonnés Pro.
--
-- Une ligne par épingle, jamais un blob unique : le dernier-écrivain-gagne se
-- fait PAR ÉPINGLE, sinon un appareil resté hors ligne longtemps écraserait tout
-- le carnet de l'autre en se resynchronisant. Même raisonnement que
-- `progression`, et la clé primaire a la même forme.
--
-- `id` vient du CLIENT : l'épingle a déjà un UUID local qui est son identité,
-- et le serveur l'adopte au lieu d'en fabriquer un second. Sans ça il faudrait
-- une table de correspondance, ou un aller-retour avant de pouvoir écrire — et
-- une épingle posée hors ligne n'aurait pas d'identité stable.
create table public.personal_pins (
  uid uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id uuid not null,

  game text not null check (game in ('leonida', 'gtav')),

  -- Bornées au carré unitaire : ce sont des coordonnées normalisées, et rien
  -- au-dehors ne désigne un point de la carte.
  x double precision not null check (x >= 0 and x <= 1),
  y double precision not null check (y >= 0 and y <= 1),

  -- LES BORNES DE LONGUEUR SONT NOUVELLES, et nécessaires.
  --
  -- `progression` ne portait aucun texte libre : un identifiant, un booléen, une
  -- date. Cette table est la PREMIÈRE où le client écrit de la prose. Sans
  -- borne, un compte pourrait y stocker des mégaoctets — RLS l'autorise, ce sont
  -- ses propres lignes.
  title text not null default '' check (length(title) <= 200),
  note  text not null default '' check (length(note) <= 2000),

  -- PAS de CHECK sur la valeur, et c'est un choix — contrairement à `game`.
  --
  -- Les deux sont des ensembles fermés côté client, mais ils ne changent pas au
  -- même rythme. Ajouter une carte est un évènement délibéré qui s'accompagne
  -- d'une migration ; ajouter une septième icône est une simple mise à jour
  -- d'app, et un CHECK ferait alors du serveur le goulot : les clients à jour se
  -- verraient refuser leurs épingles jusqu'à ce que la migration passe.
  -- `PersonalPinIcon.from(rawValue:)` retombe déjà sur `marker` pour l'inconnu.
  -- Seule la longueur est bornée.
  icon text not null default 'marker' check (length(icon) <= 32),

  is_done boolean not null default false,
  created_at timestamptz not null,
  updated_at timestamptz not null,

  -- PIERRE TOMBALE. Un `delete` local ne se propage pas : sans cette colonne,
  -- une épingle effacée sur l'iPhone reviendrait depuis l'iPad à la
  -- resynchronisation suivante, puisque l'iPad la possède encore et que rien ne
  -- lui dirait qu'elle a été retirée.
  --
  -- On ne purge JAMAIS ces lignes, et c'est délibéré : purger rouvre le danger
  -- classique — un appareil resté hors ligne au-delà de la fenêtre n'a pas vu la
  -- tombe et RESSUSCITE l'épingle. Le coût de tout garder est dérisoire, une
  -- ligne d'environ deux cents octets.
  deleted_at timestamptz,

  primary key (uid, id)
);

-- Le client relit son carnet entier au lancement, filtré sur son uid seul : la
-- clé primaire couvre déjà ce chemin. Pas d'index supplémentaire.

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.personal_pins enable row level security;

-- Un carnet est strictement personnel : ni lecture ni écriture d'autrui, à
-- aucune condition. Rien à voir avec `contributions`, qui a une face publique.
create policy personal_pins_all_own on public.personal_pins
  for all to authenticated
  using (auth.uid() = uid)
  with check (auth.uid() = uid);

-- ---------------------------------------------------------------------------
-- Privilèges — la révocation que cette migration porte elle-même
-- ---------------------------------------------------------------------------
--
-- `20260802140000_privileges.sql` n'est plus le dernier fichier de migration :
-- ses REVOKE ont été joués AVANT que cette table n'existe, et `pg_default_acl`
-- vient d'accorder SELECT/INSERT/UPDATE/DELETE à `anon` ET `authenticated`
-- dessus. Sans le bloc ci-dessous, le premier verrou serait grand ouvert pour un
-- client anonyme et RLS serait seule à tenir.

revoke all on public.personal_pins from anon, authenticated;

-- Écriture connectée, bornée par RLS à ses propres lignes. La quatrième table
-- où le client écrit directement.
grant select, insert, update, delete on public.personal_pins to authenticated;

grant all on public.personal_pins to service_role;
