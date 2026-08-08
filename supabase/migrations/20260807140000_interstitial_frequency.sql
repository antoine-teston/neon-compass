-- Le coupe-circuit de l'interstitiel, lu par `SupabaseInterstitialFrequencyGate`.
--
-- Zéro éteint le format entièrement, sans mise à jour de l'app. Un vaut
-- « éligible », sous réserve du plafond d'un par session porté par
-- `InterstitialCapPolicy`. Les valeurs supérieures à 1 sont réservées à un futur
-- schéma « un sur N moments éligibles » qui n'existe pas encore et sont
-- aujourd'hui traitées comme 1.
--
-- **La valeur semée est 1, c'est-à-dire ALLUMÉ.** Le défaut côté client l'est
-- déjà : cette porte-là éteint une capacité qui EXISTE, contrairement à
-- `backendFeaturesEnabled` qui décrit une capacité pas encore déployée et échoue
-- donc fermé. Semer 0 « par prudence » créerait un format muet dont personne ne
-- saurait pourquoi il ne s'affiche pas.
--
-- Aucune table ni fonction créée ici, donc aucune révocation de privilèges à
-- porter — `app_config` a les siennes depuis `20260802140000_privileges.sql`.
insert into public.app_config (key, value) values
  ('interstitialFrequency', '1'::jsonb)
on conflict (key) do nothing;
