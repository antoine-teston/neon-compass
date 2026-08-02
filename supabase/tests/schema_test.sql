-- Tests du schéma, des triggers et des politiques RLS.
--
-- Sans pgTAP, délibérément : de simples blocs `do $$ … assert … $$`. Même
-- raison que pour tools/basemap/gtav-poi-ids.test.mjs, qui n'a aucune
-- dépendance — ces tests portent les invariants les plus coûteux du dépôt (qui
-- voit quoi), donc rien ne doit pouvoir les rendre inexécutables.
--
--   supabase db reset && psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/schema_test.sql
--
-- Un échec lève une exception et `ON_ERROR_STOP=1` arrête tout : pas de sortie
-- verte trompeuse.

\set ON_ERROR_STOP on

begin;

-- ---------------------------------------------------------------------------
-- Jeu d'essai : trois comptes. Le trigger d'inscription crée les profils.
-- ---------------------------------------------------------------------------

insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'),
  ('22222222-2222-2222-2222-222222222222'),
  ('33333333-3333-3333-3333-333333333333');

do $$
declare
  n integer;
  h text;
begin
  select count(*) into n from public.profiles;
  assert n = 3, format('le trigger d''inscription doit créer 3 profils, il en a créé %s', n);

  select handle into h from public.profiles where uid = '11111111-1111-1111-1111-111111111111';
  assert h ~ '^[A-Z]+-[A-Z]+-[0-9]{2}$', format('pseudonyme mal formé : %s', h);

  select count(distinct handle) into n from public.profiles;
  assert n = 3, 'les pseudonymes doivent être uniques';
end $$;

-- ---------------------------------------------------------------------------
-- Colonne générée `level` — portage de functions/src/xp.ts
-- ---------------------------------------------------------------------------

do $$
declare
  expected constant integer[] := array[0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5];
  inputs   constant integer[] := array[0, 49, 50, 149, 150, 399, 400, 899, 900, 1999, 2000, 999999];
  got integer;
begin
  for i in 1..array_length(inputs, 1) loop
    update public.profiles set xp = inputs[i] where uid = '11111111-1111-1111-1111-111111111111';
    select level into got from public.profiles where uid = '11111111-1111-1111-1111-111111111111';
    assert got = expected[i],
      format('xp=%s doit donner level=%s, obtenu %s', inputs[i], expected[i], got);
  end loop;
  update public.profiles set xp = 0 where uid = '11111111-1111-1111-1111-111111111111';
end $$;

-- ---------------------------------------------------------------------------
-- Compteurs de votes — portage de functions/src/vote.ts (applyVoteDelta)
-- ---------------------------------------------------------------------------

insert into public.contributions (id, author_uid, author_handle, category, title, language_code, position_x, position_y, status)
values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        'NEON-FALCON-01', 'landmark', 'Un spot', 'fr', 0.5, 0.5, 'approved');

do $$
declare
  up integer; down integer; xp integer;
begin
  -- premier vote positif d'un tiers : +1 haut, et +2 XP à l'auteur
  insert into public.votes (contribution_id, uid, direction)
  values ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'up');
  select upvotes, downvotes into up, down from public.contributions where id = 'aaaaaaaa-0000-0000-0000-000000000001';
  select p.xp into xp from public.profiles p where uid = '11111111-1111-1111-1111-111111111111';
  assert up = 1 and down = 0, format('premier vote haut : attendu 1/0, obtenu %s/%s', up, down);
  assert xp = 2, format('un premier vote haut doit donner 2 XP à l''auteur, obtenu %s', xp);

  -- revoter dans le MÊME sens ne change rien (spec : « revoter réécrit le même
  -- document »), et surtout ne redonne pas d'XP
  update public.votes set direction = 'up'
   where contribution_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and uid = '22222222-2222-2222-2222-222222222222';
  select upvotes, downvotes into up, down from public.contributions where id = 'aaaaaaaa-0000-0000-0000-000000000001';
  select p.xp into xp from public.profiles p where uid = '11111111-1111-1111-1111-111111111111';
  assert up = 1 and down = 0, format('revote identique : attendu 1/0, obtenu %s/%s', up, down);
  assert xp = 2, format('revote identique : l''XP ne doit pas bouger, obtenu %s', xp);

  -- basculer déplace une voix
  update public.votes set direction = 'down'
   where contribution_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and uid = '22222222-2222-2222-2222-222222222222';
  select upvotes, downvotes into up, down from public.contributions where id = 'aaaaaaaa-0000-0000-0000-000000000001';
  assert up = 0 and down = 1, format('bascule haut→bas : attendu 0/1, obtenu %s/%s', up, down);

  -- rebasculer bas→haut NE REDONNE PAS d'XP : c'est la boucle par laquelle un
  -- voteur pourrait farmer l'XP de l'auteur à l'infini (castVote.ts,
  -- `isGenuineFirstUpvote`).
  update public.votes set direction = 'up'
   where contribution_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and uid = '22222222-2222-2222-2222-222222222222';
  select p.xp into xp from public.profiles p where uid = '11111111-1111-1111-1111-111111111111';
  assert xp = 2, format('bascule bas→haut ne doit pas redonner d''XP, obtenu %s', xp);

  -- voter pour soi-même ne donne pas d'XP
  insert into public.votes (contribution_id, uid, direction)
  values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'up');
  select p.xp into xp from public.profiles p where uid = '11111111-1111-1111-1111-111111111111';
  assert xp = 2, format('voter pour soi ne doit pas donner d''XP, obtenu %s', xp);

  -- retirer un vote décrémente
  delete from public.votes
   where contribution_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and uid = '11111111-1111-1111-1111-111111111111';
  select upvotes, downvotes into up, down from public.contributions where id = 'aaaaaaaa-0000-0000-0000-000000000001';
  assert up = 1 and down = 0, format('après retrait : attendu 1/0, obtenu %s/%s', up, down);
end $$;

-- Un vote par personne, garanti par la clé primaire et non par une convention
-- d'identifiant : un second INSERT du même couple doit échouer.
do $$
begin
  begin
    insert into public.votes (contribution_id, uid, direction)
    values ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'down');
    assert false, 'un second vote du même utilisateur sur le même spot doit être refusé';
  exception when unique_violation then
    null; -- attendu
  end;
end $$;

-- ---------------------------------------------------------------------------
-- Classement
-- ---------------------------------------------------------------------------

do $$
declare
  n integer; r integer;
begin
  perform public.refresh_leaderboard();
  select count(*) into n from public.leaderboard;
  assert n = 1, format('un seul auteur a une contribution approuvée, obtenu %s lignes', n);

  select rank into r from public.profiles where uid = '11111111-1111-1111-1111-111111111111';
  assert r = 1, format('le rang doit redescendre sur le profil, obtenu %s', r);

  -- un auteur shadow-banni disparaît du classement sans qu'aucune règle ne le
  -- nomme : son décompte de contributions visibles tombe à zéro
  update public.contributions set shadow_hidden = true where id = 'aaaaaaaa-0000-0000-0000-000000000001';
  perform public.refresh_leaderboard();
  select count(*) into n from public.leaderboard;
  assert n = 0, format('un spot masqué doit sortir son auteur du classement, obtenu %s', n);

  select rank into r from public.profiles where uid = '11111111-1111-1111-1111-111111111111';
  assert r is null, format('le rang doit être effacé quand on sort du classement, obtenu %s', r);

  update public.contributions set shadow_hidden = false where id = 'aaaaaaaa-0000-0000-0000-000000000001';
  perform public.refresh_leaderboard();
end $$;

-- ---------------------------------------------------------------------------
-- RLS — qui voit quoi
-- ---------------------------------------------------------------------------

insert into public.progression (uid, kind, item_id, found, updated_at) values
  ('11111111-1111-1111-1111-111111111111', 'poi', 'spot-a', true, now()),
  ('22222222-2222-2222-2222-222222222222', 'poi', 'spot-b', true, now());

insert into public.contributions (id, author_uid, author_handle, category, title, language_code, position_x, position_y, status)
values
  ('aaaaaaaa-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222',
   'CHROME-VORTEX-42', 'collectible', 'En attente', 'fr', 0.1, 0.1, 'pending'),
  ('aaaaaaaa-0000-0000-0000-000000000003', '22222222-2222-2222-2222-222222222222',
   'CHROME-VORTEX-42', 'collectible', 'Masqué', 'fr', 0.9, 0.9, 'approved');
update public.contributions set shadow_hidden = true where id = 'aaaaaaaa-0000-0000-0000-000000000003';

do $$
declare
  n integer;
begin
  -- ---- utilisateur 1, authentifié ----
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);

  select count(*) into n from public.progression;
  assert n = 1, format('un utilisateur ne doit voir QUE sa progression, il en voit %s', n);

  select count(*) into n from public.profiles;
  assert n = 1, format('un utilisateur ne doit voir QUE son profil, il en voit %s', n);

  -- approuvé non masqué : visible. En attente d'autrui : invisible. Masqué
  -- d'autrui : invisible.
  select count(*) into n from public.contributions;
  assert n = 1, format('utilisateur 1 doit voir 1 contribution, il en voit %s', n);

  -- ---- utilisateur 2 : voit les siennes, même en attente et même masquées ----
  perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
  select count(*) into n from public.contributions;
  assert n = 3, format('l''auteur doit voir ses propres contributions en attente et masquées (3 attendu), obtenu %s', n);

  -- ---- anonyme : que le public ----
  set local role anon;
  perform set_config('request.jwt.claim.sub', '', true);
  select count(*) into n from public.contributions;
  assert n = 1, format('un anonyme ne doit voir que l''approuvé non masqué, il en voit %s', n);

  -- Trois clés, et aucune version de contenu parmi elles : celles-ci vivent
  -- dans les manifestes servis par le CDN, un par producteur.
  select count(*) into n from public.app_config;
  assert n = 3, format('la configuration doit être lisible sans connexion, obtenu %s lignes', n);

  select count(*) into n from public.app_config where key like '%ersion%';
  assert n = 0, 'aucune version de contenu ne doit vivre dans app_config';

  reset role;
end $$;

-- Les signalements sont fermés dans les deux sens, y compris à leur auteur.
do $$
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  begin
    perform count(*) from public.reports;
    assert false, 'reports ne doit être lisible par personne côté client';
  exception when insufficient_privilege then
    null; -- attendu : aucun GRANT
  end;
  reset role;
end $$;

-- ---------------------------------------------------------------------------
-- Les DEUX verrous — privilèges, pas seulement politiques
-- ---------------------------------------------------------------------------

-- Ce bloc a été écrit APRÈS avoir découvert, sur le vrai projet, que
-- `pg_default_acl` accorde SELECT/INSERT/UPDATE/DELETE à `anon` et
-- `authenticated` sur toute table nouvellement créée. RLS suffisait à protéger
-- les données, mais le second verrou n'était pas là où on le croyait, et rien
-- ne l'aurait signalé : une suite qui ne teste que « combien de lignes je vois »
-- passe aussi bien avec un seul verrou qu'avec deux.
do $$
declare
  leaked text;
begin
  -- Aucune écriture directe, nulle part, sauf les trois tables où le client
  -- n'écrit que ses propres lignes.
  select string_agg(table_name || ':' || privilege_type, ', ')
    into leaked
    from information_schema.role_table_grants
   where grantee in ('anon', 'authenticated')
     and table_schema = 'public'
     and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER')
     and table_name not in ('progression', 'push_tokens', 'editor_drafts');
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
  select string_agg(distinct table_name, ', ')
    into leaked
    from information_schema.role_table_grants
   where grantee = 'anon'
     and table_schema = 'public'
     and table_name not in ('app_config', 'contributions');
  assert leaked is null, format('anon a accès à des tables non publiques : %s', leaked);
end $$;

-- Et le second verrou mord vraiment : une écriture directe est refusée par le
-- PRIVILÈGE, avant même que RLS n'ait son mot à dire.
do $$
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  begin
    update public.profiles set xp = 999999 where uid = '11111111-1111-1111-1111-111111111111';
    assert false, 'un client ne doit pas pouvoir écrire son XP';
  exception when insufficient_privilege then
    null; -- attendu
  end;
  reset role;
end $$;

-- Le mode éditeur est fermé tant que la table `editors` est vide, et s'ouvre
-- par un INSERT — là où firestore.rules exigeait de redéployer des règles.
do $$
declare
  n integer;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
  select count(*) into n from public.editor_drafts;
  assert n = 0, 'aucun brouillon visible tant que personne n''est éditeur';

  begin
    insert into public.editor_drafts (author_uid, payload)
    values ('33333333-3333-3333-3333-333333333333', '{}'::jsonb);
    assert false, 'un non-éditeur ne doit pas pouvoir écrire un brouillon';
  exception when insufficient_privilege then
    null; -- attendu : la politique WITH CHECK refuse
  end;
  reset role;

  insert into public.editors (uid) values ('33333333-3333-3333-3333-333333333333');

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
  insert into public.editor_drafts (author_uid, payload)
  values ('33333333-3333-3333-3333-333333333333', '{"kind":"poi"}'::jsonb);
  select count(*) into n from public.editor_drafts;
  assert n = 1, format('un éditeur doit voir son brouillon, obtenu %s', n);
  reset role;
end $$;

-- ---------------------------------------------------------------------------
-- Suppression de compte : anonymisation plutôt que perte de la donnée
-- ---------------------------------------------------------------------------

-- `on delete set null` sur author_uid fait partie du contrat : la contribution
-- approuvée survit à la suppression du compte, dépouillée de son auteur.
do $$
declare
  remaining integer;
  orphan_author uuid;
begin
  delete from auth.users where id = '22222222-2222-2222-2222-222222222222';

  select count(*) into remaining from public.contributions where id = 'aaaaaaaa-0000-0000-0000-000000000002';
  assert remaining = 1, 'la contribution survit à la suppression du compte (anonymisation par l''Edge Function)';

  select author_uid into orphan_author from public.contributions where id = 'aaaaaaaa-0000-0000-0000-000000000002';
  assert orphan_author is null, 'author_uid doit tomber à null, pas emporter la ligne';

  select count(*) into remaining from public.progression where uid = '22222222-2222-2222-2222-222222222222';
  assert remaining = 0, 'la progression, elle, part en cascade';

  select count(*) into remaining from public.votes where uid = '22222222-2222-2222-2222-222222222222';
  assert remaining = 0, 'les votes partent en cascade';
end $$;

rollback;

\echo 'schema_test.sql : tous les tests passent'
