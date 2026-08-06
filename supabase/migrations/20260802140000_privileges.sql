-- Privilèges — le fichier qui fait autorité, et le dernier à s'exécuter.
--
-- ## Pourquoi il est séparé
--
-- `revoke … on all tables in schema public` ne porte que sur les tables qui
-- existent DÉJÀ. Écrit au milieu des migrations, il laisse intactes celles
-- créées par les migrations suivantes — qui arrivent donc avec les privilèges
-- par défaut, c'est-à-dire tous. Un seul fichier, et le privilège effectif de
-- chaque objet se lit à un seul endroit.
--
-- ## Ce fichier N'EST PLUS le dernier — et ce n'est plus lui qui garantit
--
-- Il l'était quand il a été écrit. Quatre migrations l'ont suivi depuis
-- (`scheduling`, `app_account_token`, `contribution_xp`, `owner_defaults`), et
-- rien n'empêche la prochaine d'arriver. Le rang d'un fichier dans un dossier
-- ne se défend pas tout seul.
--
-- Ce qui garantit désormais, c'est `supabase/tests/schema_test.sql` §« Les DEUX
-- verrous » : il énumère les privilèges effectifs de `anon`, `authenticated` et
-- `public` sur les tables ET les fonctions de `public`, et les compare à une
-- liste explicite. Une table ou une fonction ajoutée après ce fichier sans sa
-- révocation fait tomber la suite en la NOMMANT. `supabase/tests/_stubs.sql`
-- reproduit `pg_default_acl` pour que ce soit vrai aussi sans Docker — sans
-- quoi le test passait à côté du seul cas qu'il devait attraper.
--
-- Donc : **une migration postérieure qui crée une table ou une fonction doit
-- porter sa propre révocation**, comme `contribution_xp` le fait déjà pour
-- `award_contribution_xp`. La liste ci-dessous reste la référence de ce qui est
-- ouvert ; le test est ce qui empêche d'en sortir sans le vouloir.
--
-- ## Le fait qui rend ce fichier nécessaire
--
-- Vérifié sur le projet le 2026-08-02 : `pg_default_acl` accorde `arwdDxtm` —
-- SELECT, INSERT, UPDATE, DELETE — à `anon` ET `authenticated` sur toute
-- nouvelle table du schéma `public`. Poser un `grant select` par-dessus ne
-- retire rien ; c'est une non-opération sur des privilèges déjà complets.
--
-- Sans ce fichier, RLS serait donc la SEULE chose entre un client anonyme et
-- l'intégralité des données. Ça tient — une table avec RLS et sans politique
-- refuse tout — mais ça ne tient qu'à ça : un `disable row level security` de
-- trop, ou une politique permissive ajoutée sans y penser, et tout est exposé,
-- en écriture comprise. Deux verrous, pas un.
--
-- ## Le piège des vues matérialisées
--
-- `ALL TABLES IN SCHEMA` couvre les tables, les vues et les tables distantes —
-- **mais PAS les vues matérialisées**. `public.leaderboard` est donc nommée
-- explicitement, deux fois : une pour reprendre, une pour rendre.

-- ---------------------------------------------------------------------------
-- Tout reprendre
-- ---------------------------------------------------------------------------

revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema public from anon, authenticated;
-- `public` est le pseudo-rôle dont tout le monde hérite, et Postgres accorde
-- EXECUTE à `public` sur toute fonction nouvellement créée.
revoke all on all functions in schema public from public;
revoke all on public.leaderboard from anon, authenticated, public;

-- ---------------------------------------------------------------------------
-- Rendre exactement ce qu'il faut
-- ---------------------------------------------------------------------------

-- Lecture sans connexion : la configuration doit être lisible AVANT toute
-- authentification, puisqu'elle porte l'URL du contenu et les portails.
grant select on public.app_config to anon, authenticated;
grant select on public.contributions to anon, authenticated;
grant select on public.leaderboard to anon, authenticated;

-- Lecture connectée : son profil, ses votes. RLS borne aux siens.
grant select on public.profiles to authenticated;
grant select on public.votes to authenticated;

-- Écriture connectée, bornée par RLS à ses propres lignes. C'étaient les trois
-- seuls endroits où un client écrit directement ; `personal_pins` s'y ajoute
-- depuis le 2026-08-03, et porte sa propre révocation dans sa propre migration —
-- ce fichier n'est plus le dernier.
grant select, insert, update, delete on public.progression to authenticated;
grant select, insert, update, delete on public.push_tokens to authenticated;
grant select, insert, update, delete on public.editor_drafts to authenticated;

-- Rien pour `reports`, `editors`, `community_bundle_state` ni `push_outbox` :
-- ni privilège, ni politique. Les deux verrous fermés, pas un seul.

-- ---------------------------------------------------------------------------
-- Fonctions
-- ---------------------------------------------------------------------------

-- Les deux RPC que l'app appelle. `security definer`, donc elles écrivent ce que
-- l'appelant n'a pas le droit d'écrire — c'est tout leur intérêt, et c'est
-- pourquoi elles valident l'identité elles-mêmes.
grant execute on function public.cast_vote(uuid, text) to authenticated;
grant execute on function public.report_contribution(uuid, text) to authenticated;

-- Appelée DANS une politique, donc évaluée avec les droits de l'appelant :
-- sans ce droit, la politique d'`editor_drafts` échouerait pour tout le monde.
grant execute on function public.is_editor() to authenticated;

-- Réservées au serveur. `generate_handle` ouverte à `authenticated` laisserait
-- n'importe qui tirer des noms sans passer par le compteur de tentatives de
-- l'Edge Function ; `refresh_leaderboard` est coûteuse.
grant execute on function public.generate_handle() to service_role;
grant execute on function public.refresh_leaderboard() to service_role;
grant execute on function public.is_editor() to service_role;

-- ---------------------------------------------------------------------------
-- service_role
-- ---------------------------------------------------------------------------

-- Tout, y compris sur les tables fermées au client. C'est la clé des Edge
-- Functions et de la CI — jamais celle embarquée dans l'app, qui ne porte que
-- la clé anonyme.
grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;
grant select on public.leaderboard to service_role;
