-- La date d'APPARITION sur la carte, distincte de la date de soumission.
--
-- `created_at` existe déjà mais date du dépôt : un lieu resté trois jours en
-- modération arriverait déjà enterré dans la section « À découvrir » du volet
-- Social, ce qui viderait de son sens la seule raison pour laquelle cette
-- section existe — que chaque proposition passe sous les yeux au moins une fois.
alter table public.contributions add column approved_at timestamptz;

-- Rétro-remplissage : pour l'existant, la date de soumission est la meilleure
-- approximation disponible, et elle est juste tant que la modération suit.
update public.contributions set approved_at = created_at where status = 'approved';

-- Un TRIGGER ici, là où `20260802170000_contribution_xp.sql` en a délibérément
-- refusé un pour l'XP. La différence n'est pas de goût : l'XP est une
-- RÉCOMPENSE, et une reprise de migration qui repasserait une ligne à
-- `approved` en attribuerait deux fois. Un horodatage est DÉRIVÉ, et la garde
-- `approved_at is null` le rend idempotent — une réapprobation ne réécrit rien.
create or replace function public.stamp_contribution_approval()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status = 'approved' and new.approved_at is null then
    new.approved_at := now();
  end if;
  return new;
end;
$$;

create trigger contributions_stamp_approval
  before insert or update of status on public.contributions
  for each row execute function public.stamp_contribution_approval();

-- Révocation obligatoire : `pg_default_acl` accorde EXECUTE à `anon` et
-- `authenticated` sur toute fonction nouvellement créée. Une fonction de
-- trigger n'a aucune raison d'être appelable directement, et
-- `supabase/tests/privileges_test.sql` la signalerait — il fonctionne par liste
-- de refus, donc l'oubli est attrapé sans qu'on ait à l'y déclarer.
revoke all on function public.stamp_contribution_approval() from public, anon, authenticated;
