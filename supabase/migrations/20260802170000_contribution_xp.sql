-- XP d'une contribution approuvée — portage de
-- `XP_PER_APPROVED_CONTRIBUTION` et `awardXP` (functions/src/xp.ts).
--
-- Une fonction et pas un trigger sur `status = 'approved'` : approuver est un
-- geste humain délibéré, pas un effet de bord de n'importe quelle écriture qui
-- ferait passer une ligne à `approved`. Un trigger attribuerait aussi de l'XP à
-- une correction de données ou à une reprise de migration.
--
-- Le NIVEAU n'est pas touché : c'est une colonne générée. C'est tout l'intérêt
-- d'avoir sorti `levelForXP` du code — il n'y a plus qu'un seul endroit où
-- écrire l'XP, et zéro endroit où recalculer le niveau.
create or replace function public.award_contribution_xp(author uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.profiles set xp = xp + 20 where uid = author;
$$;

revoke all on function public.award_contribution_xp(uuid) from public, anon, authenticated;
grant execute on function public.award_contribution_xp(uuid) to service_role;
