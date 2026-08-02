-- Version des fragments communautaires, et planification.
--
-- Remplace les deux Functions planifiées de Firebase (`rebuildLeaderboard`,
-- `rebuildCommunityBundles`) et le déclencheur horaire qu'elles portaient.

-- La version des fragments vit en base plutôt que d'être relue depuis le
-- manifeste servi par le CDN : la reconstruction doit pouvoir décider seule,
-- sans dépendre d'une lecture réseau qui pourrait rendre un cache périmé et
-- faire reculer la version — ce qui laisserait les clients sur leur cache pour
-- toujours, la garde `remoteVersion > localVersion` ne mordant plus jamais.
alter table public.community_bundle_state add column if not exists version integer not null default 0;

-- ---------------------------------------------------------------------------
-- Planification
-- ---------------------------------------------------------------------------

-- `pg_cron` et `pg_net` sont fournis par la plateforme. Sur un Postgres nu —
-- le harnais sans Docker de Scripts/db-test.sh — ils n'existent pas, et un
-- `create extension` échouerait en emportant toute la migration.
--
-- D'où la garde. Elle ne masque rien : sur la plateforme les extensions sont
-- toujours disponibles, et hors plateforme le `raise notice` dit exactement ce
-- qui n'a pas été posé. Un silence aurait été inacceptable — une planification
-- absente ne se voit pas, elle se constate des semaines plus tard à un
-- classement qui n'a jamais bougé.
do $$
begin
  if not exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    raise notice 'pg_cron indisponible : planification NON posée. Attendu hors plateforme Supabase.';
    return;
  end if;

  create extension if not exists pg_cron with schema extensions;
  create extension if not exists pg_net with schema extensions;

  -- Classement : toutes les heures. C'était une Function planifiée ; ce n'est
  -- plus qu'un rafraîchissement de vue matérialisée, sans code à déployer.
  perform cron.schedule('refresh-leaderboard', '7 * * * *', 'select public.refresh_leaderboard();');

  -- Les fragments communautaires restent une Edge Function : ils écrivent des
  -- fichiers sur Storage, ce que du SQL ne sait pas faire. La tâche ne fait que
  -- l'appeler ; la fonction décide elle-même s'il y a lieu de reconstruire
  -- (drapeau `dirty`, ou plus d'une heure depuis la dernière passe).
  --
  -- L'URL et la clé viennent de `vault` plutôt que d'être écrites ici : ce
  -- fichier est versionné, une clé `service_role` ne doit pas l'être. Les deux
  -- secrets se posent une fois, à la main :
  --
  --   select vault.create_secret('https://<ref>.supabase.co', 'project_url');
  --   select vault.create_secret('<service_role>', 'service_role_key');
  perform cron.schedule(
    'rebuild-community-bundles',
    '*/5 * * * *',
    $cron$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
             || '/functions/v1/rebuild-community-bundles',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key')
      )
    );
    $cron$
  );

  -- Vidange de la file de notifications, toutes les minutes. Une file plutôt
  -- qu'un appel depuis le trigger : un envoi raté se rejoue, et une transaction
  -- d'écriture ne dépend pas de la disponibilité d'APNs.
  perform cron.schedule(
    'send-push',
    '* * * * *',
    $cron$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
             || '/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key')
      )
    );
    $cron$
  );
end $$;
