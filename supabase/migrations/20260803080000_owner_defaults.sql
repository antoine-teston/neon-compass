-- `uid` par défaut sur les trois tables où le client écrit.
--
-- Trouvé en exerçant l'API réelle : un INSERT qui omet `uid` laisse la colonne à
-- NULL, donc `with check (auth.uid() = uid)` compare à NULL, donc la politique
-- refuse — un 403 dont le message ne dit pas que c'est une colonne manquante.
--
-- Côté Firestore, l'identité était portée par le CHEMIN du document
-- (`profiles/{uid}/progression/…`) : l'oublier était impossible. Ici elle est
-- une colonne comme une autre, et rien n'oblige à la renseigner. Le défaut
-- rétablit la propriété perdue : ne pas la fournir donne le bon résultat au lieu
-- d'un refus.
--
-- Cela n'affaiblit RIEN. La politique continue de vérifier `auth.uid() = uid` :
-- un appelant qui écrit délibérément l'uid d'un autre se fait toujours refuser.
-- Le défaut ne s'applique qu'en l'absence de valeur.
alter table public.progression   alter column uid set default auth.uid();
alter table public.push_tokens   alter column uid set default auth.uid();
alter table public.editor_drafts alter column author_uid set default auth.uid();
