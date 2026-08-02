-- Rapprochement entre un achat App Store et un profil.
--
-- `appAccountToken` est l'UUID que le client attache à une transaction StoreKit ;
-- c'est la seule chose qui relie une notification serveur d'Apple à un compte
-- chez nous. Sans lui, la notification est parfaitement valide et parfaitement
-- inutilisable.
--
-- **Miroir d'affichage, jamais une source d'autorisation.** Le droit Pro est
-- vérifié sur l'appareil par StoreKit, et cette colonne ne fait qu'alimenter le
-- badge du Profil. Si le webhook est en panne, mal configuré, ou si aucun profil
-- ne porte le jeton, le pire résultat est un badge périmé — jamais une
-- fonctionnalité cassée. C'est ce qui autorise à ne pas la traiter comme une
-- donnée critique.
alter table public.profiles add column if not exists app_account_token uuid;

-- Index unique partiel : deux profils ne peuvent pas revendiquer le même achat,
-- et les innombrables profils sans jeton ne pèsent rien dans l'index.
create unique index if not exists profiles_app_account_token_idx
  on public.profiles (app_account_token)
  where app_account_token is not null;
