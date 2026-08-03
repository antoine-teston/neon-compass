-- Stubs minimaux de ce que Supabase fournit : les rôles de l'API, le schéma
-- `auth` avec sa table `users` et `auth.uid()`, le schéma `storage` avec ses
-- buckets.
--
-- CE FICHIER N'EST PAS UN SUBSTITUT à un vrai `supabase db reset`. Il existe
-- pour une seule raison : faire tourner supabase/tests/schema_test.sql sur un
-- Postgres nu quand Docker n'est pas disponible — le cas d'une machine de
-- développement sans Docker Desktop, ou d'un runner CI qui ne veut pas payer le
-- démarrage de la pile complète.
--
-- Ce qu'il ne reproduit PAS, et qu'il faut donc vérifier sur la vraie pile :
--   - la façon dont GoTrue peuple `auth.users` (colonnes, contraintes, triggers) ;
--   - le fait que `auth.uid()` lit un JWT vérifié plutôt qu'une variable de session ;
--   - PostgREST lui-même — un GRANT manquant ne se voit qu'à travers lui ;
--   - les politiques de `storage.objects`.
--
-- Utilisation : voir Scripts/db-test.sh

create role anon nologin;
create role authenticated nologin;
create role service_role nologin;

-- ---------------------------------------------------------------------------
-- Les privilèges par défaut de Supabase — le stub le plus important du fichier
-- ---------------------------------------------------------------------------
--
-- Un Postgres nu n'accorde rien à personne sur une table neuve. Supabase, si :
-- `pg_default_acl` y donne tous les privilèges à `anon` et `authenticated` sur
-- toute table nouvellement créée dans `public` (vérifié sur le projet le
-- 2026-08-02, c'est ce qui a motivé 20260802140000_privileges.sql).
--
-- Sans ces trois lignes, le chemin sans Docker était aveugle là où le risque
-- vit : une table ajoutée par une migration postérieure à `privileges.sql`
-- arrivait ici SANS privilège — donc conforme — alors qu'en production elle
-- serait grande ouverte. Mesuré : une table sonde ajoutée après
-- `privileges.sql` passait la suite entière sans lever un seul assert.
--
-- Le rôle courant est `postgres`, celui qui exécute les migrations : c'est bien
-- son `pg_default_acl` qui décide du sort des tables qu'elles créent.
alter default privileges in schema public grant all on tables to anon, authenticated;
alter default privileges in schema public grant all on sequences to anon, authenticated;
-- Postgres accorde EXECUTE à `public` sur toute fonction neuve, partout — ce
-- n'est pas une particularité Supabase, mais ça compte autant : une fonction
-- `security definer` ajoutée sans révocation est appelable par n'importe qui.
alter default privileges in schema public grant execute on functions to anon, authenticated;

create schema auth;
create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text
);

create schema storage;
create table storage.buckets (
  id text primary key,
  name text not null,
  public boolean not null default false
);

create or replace function auth.uid() returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

grant usage on schema public to anon, authenticated, service_role;
grant usage on schema auth to anon, authenticated, service_role;
