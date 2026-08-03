-- Les DEUX verrous, en LECTURE PURE — la version exécutable en production.
--
-- ## Pourquoi ce fichier existe à côté de `schema_test.sql`
--
-- `schema_test.sql` porte les mêmes assertions de privilèges, mais il est
-- inséparable de ses fixtures : il insère dans `auth.users`, `contributions`,
-- `votes`, `progression`, `editor_drafts` et modifie l'XP des profils. C'est
-- ce qu'il faut pour tester RLS, et c'est fait pour une base JETABLE
-- (`Scripts/db-test.sh`, pile locale ou Postgres nu avec `_stubs.sql`).
--
-- Le lancer sur la production y injecterait des données de test. Le 2026-08-03,
-- le workflow `Migrations` a failli le faire : une étape le lançait dès que
-- `SUPABASE_DB_URL` serait posé. L'erreur venait d'une confusion entre « le test
-- qui vérifie les privilèges » et « le fichier qui le contient ».
--
-- Ce fichier ne contient donc QUE ce qui se lit : deux requêtes sur
-- `information_schema`, zéro écriture, sûr contre n'importe quelle base — y
-- compris celle qui sert les clients.
--
-- ## Ce qu'il garantit
--
-- `pg_default_acl` accorde SELECT/INSERT/UPDATE/DELETE à `anon` et
-- `authenticated` sur toute table nouvellement créée dans `public`, et Postgres
-- accorde EXECUTE à `public` sur toute fonction nouvellement créée. RLS seule
-- protégerait les données, mais un `disable row level security` de trop
-- exposerait tout. `20260802140000_privileges.sql` reprend puis rend — sauf
-- qu'il n'est plus le dernier fichier de migration. C'est donc ici que se
-- vérifie l'état RÉSULTANT.
--
-- Toute table ou fonction ajoutée après coup doit apparaître dans une des
-- listes ci-dessous, en connaissance de cause. C'est le prix, et c'est le point.

-- ---------------------------------------------------------------------------
-- Verrou 1 — les TABLES
-- ---------------------------------------------------------------------------
do $$
declare
  leaked text;
begin
  -- Aucune écriture directe, nulle part, sauf les quatre tables où le client
  -- n'écrit que ses propres lignes.
  select string_agg(table_name || ':' || privilege_type, ', ')
    into leaked
    from information_schema.role_table_grants
   where grantee in ('anon', 'authenticated')
     and table_schema = 'public'
     and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER')
     and table_name not in ('progression', 'push_tokens', 'editor_drafts', 'personal_pins');
  assert leaked is null, format('écriture accordée là où elle ne devrait pas : %s', leaked);

  -- Les tables entièrement fermées le sont aussi au niveau du privilège.
  select string_agg(distinct table_name, ', ')
    into leaked
    from information_schema.role_table_grants
   where grantee in ('anon', 'authenticated')
     and table_schema = 'public'
     and table_name in ('reports', 'editors', 'community_bundle_state', 'push_outbox');
  assert leaked is null, format('tables censées être fermées mais accordées : %s', leaked);

  -- `anon` ne lit que ce qui est public. Notamment pas les profils.
  --
  -- `leaderboard` n'a PAS à figurer dans cette liste, et ce n'est pas parce
  -- qu'elle serait fermée : `anon` a bien SELECT dessus (le classement est
  -- public par conception). C'est qu'elle est INVISIBLE ici — voir le verrou 3.
  select string_agg(distinct table_name, ', ')
    into leaked
    from information_schema.role_table_grants
   where grantee = 'anon'
     and table_schema = 'public'
     and table_name not in ('app_config', 'contributions');
  assert leaked is null, format('anon a accès à des tables non publiques : %s', leaked);

  -- Et la lecture connectée est bornée elle aussi. Les assertions précédentes
  -- laissaient passer une table neuve accordée en SELECT seul à
  -- `authenticated` : la liste ci-dessous est donc exhaustive.
  select string_agg(distinct table_name, ', ')
    into leaked
    from information_schema.role_table_grants
   where grantee = 'authenticated'
     and table_schema = 'public'
     and table_name not in ('app_config', 'contributions', 'leaderboard', 'profiles',
                            'votes', 'progression', 'push_tokens', 'editor_drafts',
                            'personal_pins');
  assert leaked is null, format('authenticated lit des tables non prévues : %s', leaked);
end $$;

-- ---------------------------------------------------------------------------
-- Verrou 2 — les FONCTIONS
-- ---------------------------------------------------------------------------
--
-- Une fonction `security definer` ajoutée sans révocation est appelable par
-- n'importe qui, avec les droits de son propriétaire : c'est le chemin le plus
-- court entre une migration distraite et une élévation de privilège.
do $$
declare
  leaked text;
begin
  select string_agg(distinct routine_name || ' → ' || grantee, ', ')
    into leaked
    from information_schema.role_routine_grants
   where routine_schema = 'public'
     and grantee in ('anon', 'authenticated', 'PUBLIC')
     and privilege_type = 'EXECUTE'
     -- Les seules ouvertes au client, et à `authenticated` uniquement : les deux
     -- RPC que l'app appelle, plus `is_editor()` qu'une politique évalue avec
     -- les droits de l'appelant.
     and not (grantee = 'authenticated'
              and routine_name in ('cast_vote', 'report_contribution', 'is_editor'));
  assert leaked is null, format('fonctions exécutables par le client sans l''avoir décidé : %s', leaked);
end $$;

-- ---------------------------------------------------------------------------
-- Verrou 3 — les VUES MATÉRIALISÉES, que `information_schema` NE VOIT PAS
-- ---------------------------------------------------------------------------
--
-- Le verrou 1 est aveugle à ce relkind, et c'est le piège que
-- `20260802140000_privileges.sql` documente déjà pour les GRANTs : `ALL TABLES
-- IN SCHEMA` couvre tables, vues et tables distantes, mais pas les vues
-- matérialisées. Ce qui n'avait pas été vu, c'est que le TEST hérite du même
-- angle mort — `information_schema.tables` ne les référence pas non plus.
--
-- Constaté sur la production le 2026-08-03 : `public.leaderboard` est en
-- `relkind = 'm'`, son ACL réel accorde SELECT à `anon` et `authenticated`, et
-- les quatre assertions du verrou 1 passaient sans jamais la regarder. Une
-- future vue matérialisée oubliée resterait donc invisible au vert.
--
-- D'où la lecture directe de `pg_class.relacl`. Un `relacl` NULL n'est pas une
-- faille : il signifie « aucun GRANT explicite », donc propriétaire seul.
do $$
declare
  leaked text;
begin
  select string_agg(format('%s → %s:%s', c.relname, a.grantee::regrole::text, a.privilege_type), ', ')
    into leaked
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    cross join lateral aclexplode(c.relacl) a
   where n.nspname = 'public'
     and c.relkind = 'm'
     and a.grantee::regrole::text in ('anon', 'authenticated')
     -- Le classement est public par décision : lecture seule, et rien d'autre.
     and not (c.relname = 'leaderboard' and a.privilege_type = 'SELECT');
  assert leaked is null, format('vue matérialisée exposée au client : %s', leaked);
end $$;

select 'les trois verrous : OK' as resultat;
