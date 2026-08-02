-- Tests de la couche communautaire : RPC de vote et de signalement, monitoring
-- de vélocité, drapeau de péremption des fragments, file de notifications.
--
--   psql "$DB_URL" -f supabase/tests/community_test.sql

\set ON_ERROR_STOP on

begin;

insert into auth.users (id) values
  ('aaaa1111-1111-1111-1111-111111111111'),
  ('bbbb2222-2222-2222-2222-222222222222');

insert into public.contributions
  (id, author_uid, author_handle, category, title, language_code, position_x, position_y, status)
values
  ('cccc0000-0000-0000-0000-000000000001', 'aaaa1111-1111-1111-1111-111111111111',
   'NEON-FALCON-01', 'landmark', 'Un spot', 'fr', 0.5, 0.5, 'approved');

-- ---------------------------------------------------------------------------
-- cast_vote — portage de castVote.ts
-- ---------------------------------------------------------------------------

do $$
declare
  up integer; down integer; author_xp integer;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', 'bbbb2222-2222-2222-2222-222222222222', true);

  select c.upvotes, c.downvotes into up, down
    from public.cast_vote('cccc0000-0000-0000-0000-000000000001', 'up') c;
  assert up = 1 and down = 0, format('premier vote : attendu 1/0, obtenu %s/%s', up, down);

  -- Revoter dans le même sens ne change rien. La RPC exécute quand même
  -- l'UPDATE ; c'est le trigger qui voit `new.direction = old.direction` et
  -- n'applique aucun delta.
  select c.upvotes, c.downvotes into up, down
    from public.cast_vote('cccc0000-0000-0000-0000-000000000001', 'up') c;
  assert up = 1 and down = 0, format('revote identique : attendu 1/0, obtenu %s/%s', up, down);

  select c.upvotes, c.downvotes into up, down
    from public.cast_vote('cccc0000-0000-0000-0000-000000000001', 'down') c;
  assert up = 0 and down = 1, format('bascule : attendu 0/1, obtenu %s/%s', up, down);

  reset role;

  select xp into author_xp from public.profiles where uid = 'aaaa1111-1111-1111-1111-111111111111';
  assert author_xp = 2, format('un seul premier vote haut = 2 XP, obtenu %s', author_xp);
end $$;

-- Une direction inventée est refusée, et un spot inexistant aussi.
do $$
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', 'bbbb2222-2222-2222-2222-222222222222', true);

  begin
    perform public.cast_vote('cccc0000-0000-0000-0000-000000000001', 'sideways');
    assert false, 'une direction inconnue doit être refusée';
  exception when others then null;
  end;

  begin
    perform public.cast_vote('dddd9999-9999-9999-9999-999999999999', 'up');
    assert false, 'voter sur un spot inexistant doit être refusé';
  exception when others then null;
  end;
  reset role;
end $$;

-- Un anonyme ne vote pas : la RPC exige une identité, elle ne la déduit pas.
do $$
begin
  set local role anon;
  perform set_config('request.jwt.claim.sub', '', true);
  begin
    perform public.cast_vote('cccc0000-0000-0000-0000-000000000001', 'up');
    assert false, 'un anonyme ne doit pas pouvoir voter';
  exception when others then null;
  end;
  reset role;
end $$;

-- ---------------------------------------------------------------------------
-- report_contribution
-- ---------------------------------------------------------------------------

do $$
declare
  n integer;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', 'bbbb2222-2222-2222-2222-222222222222', true);

  perform public.report_contribution('cccc0000-0000-0000-0000-000000000001', 'contenu douteux');
  -- Signaler deux fois ne crée pas deux lignes : la contrainte d'unicité rend
  -- le rejeu inoffensif au lieu de gonfler la file de modération.
  perform public.report_contribution('cccc0000-0000-0000-0000-000000000001', 'encore');

  begin
    perform public.report_contribution('cccc0000-0000-0000-0000-000000000001', repeat('x', 281));
    assert false, 'un motif de plus de 280 caractères doit être refusé';
  exception when sqlstate '22023' then null;
  end;
  reset role;

  select count(*) into n from public.reports
   where contribution_id = 'cccc0000-0000-0000-0000-000000000001';
  assert n = 1, format('un seul signalement par personne et par spot, obtenu %s', n);
end $$;

-- ---------------------------------------------------------------------------
-- Monitoring de vélocité — ne bloque jamais, marque puis escalade
-- ---------------------------------------------------------------------------

do $$
declare
  flagged integer; bursts integer; banned boolean;
begin
  -- Six soumissions en rafale : au-delà de cinq dans la fenêtre, la sixième est
  -- marquée pour revue. Aucune n'est rejetée.
  for i in 1..6 loop
    insert into public.contributions
      (author_uid, author_handle, category, title, language_code, position_x, position_y, status)
    values ('bbbb2222-2222-2222-2222-222222222222', 'CHROME-VORTEX-42', 'collectible',
            'Rafale ' || i, 'fr', 0.1 + i * 0.01, 0.1, 'pending');
  end loop;

  select count(*) into flagged from public.contributions
   where author_uid = 'bbbb2222-2222-2222-2222-222222222222' and flagged_for_review;
  assert flagged >= 1, 'la rafale doit être marquée pour revue';

  select flagged_burst_count, is_shadow_banned into bursts, banned
    from public.profiles where uid = 'bbbb2222-2222-2222-2222-222222222222';
  assert bursts >= 1, format('le compteur de rafales doit monter, obtenu %s', bursts);

  select count(*) into flagged from public.contributions
   where author_uid = 'bbbb2222-2222-2222-2222-222222222222' and status = 'rejected';
  assert flagged = 0, 'aucun rejet automatique — la spec l''interdit explicitement';
end $$;

-- ---------------------------------------------------------------------------
-- Péremption des fragments : un vote ne salit PAS, une approbation si
-- ---------------------------------------------------------------------------

do $$
declare
  is_dirty boolean;
begin
  update public.community_bundle_state set dirty = false where id;

  -- Un vote ne touche que les compteurs, volontairement absents des champs
  -- d'appartenance : sinon le pic de votes déclencherait une reconstruction en
  -- continu, précisément quand on ne peut pas se le permettre.
  update public.contributions set upvotes = upvotes + 1
   where id = 'cccc0000-0000-0000-0000-000000000001';
  select dirty into is_dirty from public.community_bundle_state where id;
  assert is_dirty = false, 'un vote ne doit pas périmer les fragments';

  -- Un changement de statut, si.
  update public.contributions set status = 'rejected'
   where id = 'cccc0000-0000-0000-0000-000000000001';
  select dirty into is_dirty from public.community_bundle_state where id;
  assert is_dirty = true, 'une approbation ou un rejet doit périmer les fragments';
end $$;

-- ---------------------------------------------------------------------------
-- File de notifications : seulement la TRANSITION vers approuvé
-- ---------------------------------------------------------------------------

do $$
declare
  n integer;
begin
  delete from public.push_outbox;

  insert into public.contributions
    (id, author_uid, author_handle, category, title, language_code, position_x, position_y, status)
  values ('cccc0000-0000-0000-0000-000000000002', 'aaaa1111-1111-1111-1111-111111111111',
          'NEON-FALCON-01', 'vehicle', 'À approuver', 'fr', 0.8, 0.8, 'pending');

  select count(*) into n from public.push_outbox;
  assert n = 0, 'créer un spot en attente ne notifie personne';

  update public.contributions set status = 'approved'
   where id = 'cccc0000-0000-0000-0000-000000000002';
  select count(*) into n from public.push_outbox;
  assert n = 1, format('la transition vers approuvé doit déposer une notification, obtenu %s', n);

  -- Une modification ultérieure d'un spot DÉJÀ approuvé ne renotifie pas.
  update public.contributions set title = 'Titre corrigé'
   where id = 'cccc0000-0000-0000-0000-000000000002';
  select count(*) into n from public.push_outbox;
  assert n = 1, format('un spot déjà approuvé ne doit pas renotifier, obtenu %s', n);

  -- Un spot masqué ne notifie jamais.
  insert into public.contributions
    (id, author_uid, author_handle, category, title, language_code, position_x, position_y, status, shadow_hidden)
  values ('cccc0000-0000-0000-0000-000000000003', 'aaaa1111-1111-1111-1111-111111111111',
          'NEON-FALCON-01', 'event', 'Masqué', 'fr', 0.2, 0.7, 'pending', true);
  update public.contributions set status = 'approved'
   where id = 'cccc0000-0000-0000-0000-000000000003';
  select count(*) into n from public.push_outbox;
  assert n = 1, format('un spot masqué ne doit jamais notifier, obtenu %s', n);
end $$;

rollback;

\echo 'community_test.sql : tous les tests passent'
