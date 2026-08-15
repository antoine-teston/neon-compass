# Hub communautaire — annuaire, promotion payante et événements de communauté

**Date** : 2026-08-10
**Statut** : validé, prêt pour le plan d'implémentation
**Cible** : v1.1 (décembre 2026 – janvier 2027)
**Prolonge** : `2026-07-31-onglet-social-design.md` (piliers 1 et 2), qui posait
l'onglet sur les événements Online et le classement des contributeurs
**Côtoie** : le LFG (pilier 3, décrit dans la même spec, même horizon v1.1)

## Le problème

L'onglet Social a deux piliers : les événements hebdo Rockstar et le classement
des contributeurs. Les deux sont de la **lecture** — personne n'y construit rien
qui lui appartienne. Quand l'Online de Leonida ouvrira, un écosystème de
communautés va naître (crews officiels, serveurs RP tiers plus tard), et ces
communautés chercheront de la visibilité auprès d'une base de joueurs actifs.
Neon Compass est exactement ce panneau d'affichage.

Ce spec construit un troisième pilier dans le Social : un **annuaire de
communautés** consultable par tous, avec une **promotion payante par
abonnement mensuel** (B2B, StoreKit 2) qui donne au propriétaire un
emplacement mis en avant et le droit de poster des événements.

### Pourquoi v1.1 et pas v1

Trois raisons, dont aucune n'est la complexité technique :

1. **GTA Online V n'a pas de serveurs promotionnables.** Ses lobbys sont
   anonymes et matchmakés. L'entité promotionnable — un groupe nommé,
   persistant, avec une communauté — n'existe pleinement que dans
   l'écosystème FiveM/RedM, qu'on ne touche pas encore (risque IP), ou dans
   les crews officiels, dont le volume ne justifie pas un annuaire.
2. **L'Online de Leonida n'est pas ouvert.** Promouvoir une communauté de
   jeu dans un jeu dont le mode multijoueur n'existe pas encore est un non-
   sens produit.
3. **Le planning v1 porte déjà 21 chantiers.** Ajouter un modèle
   d'abonnement B2B, un annuaire et un système d'événements au sprint
   d'octobre surchargerait un lancement qui n'a pas de marge.

En v1.1 (décembre–janvier), l'Online sera probablement ouvert, l'app aura une
base, et la fonctionnalité sera utile dès son allumage.

## Le principe de dosage (hérité)

Le Social entier tient sur une règle : **pas de texte libre**. Ce spec la
respecte intégralement. Une fiche communauté se compose de champs contraints
(pickers, tags fermés, format validé). Un événement se compose d'un type fermé,
d'une date et d'une communauté. Le seul champ saisi par un humain est le nom de
la communauté, contraint au même format que les handles (alphanum, espaces,
tirets, 3-30 caractères).

Le lien Discord est le seul pont vers l'extérieur : c'est là que vivent les
descriptions, les règles, les détails qu'un champ structuré ne porte pas.
L'app est un panneau d'affichage, pas un outil d'organisation.

## L'objet : la Communauté

L'entité centrale n'est pas un « serveur » mais une **communauté**. C'est le
dénominateur commun entre un crew officiel Rockstar Social Club et un futur
serveur FiveM : un groupe de joueurs avec une identité, une plateforme, un
style de jeu.

### Champs

| Champ | Type | Contrainte |
|---|---|---|
| `id` | UUID | `gen_random_uuid()` |
| `owner_id` | UUID FK `auth.users` | Le créateur, qui paie la promotion |
| `name` | Texte | 3-30 chars, `^[a-zA-Z0-9 -]+$` |
| `platform` | Enum | `ps5`, `xbox`, `pc`, `cross-platform` |
| `playstyles` | Array d'enums | `rp`, `racing`, `heists`, `casual`, `competitive`, `exploration`, `creative` |
| `languages` | Array ISO 639-1 | Parmi `fr`, `en`, `es`, `it`, `de` + langues courantes |
| `discord_invite` | URL contrainte | Pattern `^https://discord\.gg/` uniquement, ou NULL |
| `member_count` | Entier | Auto-déclaré, affiché par tranches (10+, 50+, 100+, 500+) |
| `server_address` | Texte optionnel | Préparé pour FiveM (`cfx.re/join/*`), **éteint en v1.1** |
| `promoted` | Bool | Vrai si l'abonnement StoreKit est actif |
| `promoted_until` | Timestamp | Fin de la période payée courante |
| `created_at` | Timestamp | |
| `updated_at` | Timestamp | |

**Un compte = une communauté.** Pas de multi-gestion en v1.1 — le cas d'usage
est un admin qui promeut son groupe. Un champ `owner_id` unique suffit. Si la
demande apparaît, une table de jonction `community_members(role)` viendra dans
un spec ultérieur.

### Le nom est le seul risque de modération

Même approche que les handles : format contraint (pas d'unicode exotique, pas
de caractères spéciaux, longueur bornée). Le signalement par les utilisateurs
et le shadow-ban du système existant couvrent les cas d'abus. Au volume
attendu en v1.1 (dizaines, pas milliers), le traitement manuel est tenable.

## La promotion payante — Community Spotlight

### Le produit StoreKit 2

Un **abonnement auto-renouvelable mensuel**, dans un groupe d'abonnement
**séparé du Pro**. Un utilisateur peut être Pro ET promouvoir sa communauté —
ce sont deux achats orthogonaux.

| | Détail |
|---|---|
| **Identifiant produit** | `community_spotlight_monthly` |
| **Groupe d'abonnement** | `community_spotlight` (distinct de `pro`) |
| **Prix** | 4,99 €/mois (palier Apple) |
| **Commission Apple** | 30 % en année 1, 15 % ensuite (Small Business + rétention) |
| **Net estimé** | ~3,49 €/mois en Y1, ~4,24 €/mois en Y2+ |

### Ce que la promotion donne

| Gratuit | Promu (Spotlight) |
|---|---|
| Fiche visible dans l'annuaire | Fiche visible **+ badge Spotlight + slot en tête** |
| Recherche et filtres | Idem |
| Pas d'événements | Jusqu'à **3 événements actifs simultanément** |
| Pas de mise en avant | Carrousel « Communautés en vedette » en haut du volet |

### Qui peut souscrire

N'importe quel utilisateur connecté qui a créé une communauté. La création est
gratuite. Le bouton « Promouvoir » apparaît sur la fiche de sa propre
communauté et déclenche le flux d'achat StoreKit standard.

### Architecture du statut de promotion

Le client ne fait jamais confiance au statut local. La source de vérité est la
table `communities.promoted` dans Supabase, mise à jour par une Edge Function
déclenchée par les **App Store Server Notifications V2**.

L'Edge Function existante (spec revenus, `2026-08-07`) gère déjà les
notifications Pro. Elle est étendue pour reconnaître le
`subscriptionGroupID` de `community_spotlight` :

- `SUBSCRIBED`, `DID_RENEW` → `promoted = true`, `promoted_until` = fin de période
- `EXPIRED`, `REVOKE`, `DID_FAIL_TO_RENEW` (grâce épuisée) → `promoted = false`

Le client lit `promoted` et `promoted_until` depuis la table lors du chargement
du volet communautés. Aucun cache long : la donnée est lue à chaque ouverture
et au pull-to-refresh, comme le classement.

## Les événements de communauté

### Un bonus de la promotion, pas un produit à part

Les événements communautaires ne sont postables que par les communautés
promues. C'est ce qui donne de la valeur à l'abonnement au-delà du badge et
du positionnement.

### Champs

| Champ | Type | Contrainte |
|---|---|---|
| `id` | UUID | |
| `community_id` | UUID FK | La communauté |
| `event_type` | Enum | `tournament`, `themed_night`, `recruitment`, `launch`, `training`, `other` |
| `platform` | Enum | Hérité de la communauté ou override |
| `starts_at` | Timestamp | |
| `ends_at` | Timestamp optionnel | Un recrutement n'a pas de fin fixe |
| `slots` | Entier optionnel | Places disponibles |
| `created_at` | Timestamp | |

**Pas de titre, pas de description.** Le type + la communauté + la date
suffisent. Le lien Discord de la communauté est le chemin naturel vers les
détails. Zéro texte libre, zéro modération.

### Plafond

3 événements actifs (`starts_at` dans le futur ou `ends_at` non dépassé) par
communauté. Vérifié par un trigger `BEFORE INSERT` sur `community_events`.
Quand la promotion expire, les événements existants restent visibles
jusqu'à leur `ends_at` mais aucun nouveau ne peut être créé.

## L'annuaire dans le Social

### Troisième volet

`SocialScreen` gagne un troisième cas dans son `Panel` : `.communities`.
Même logique que `.proposals` : le volet n'apparaît que si
`serverFeatures.isEnabled` **ET** si `app_config` l'a allumé. Double garde :
la première est technique (Supabase déployé), la seconde est éditoriale
(décision de montrer la section).

### Disposition

**Carrousel en vedette** (en-tête) — les communautés promues, en scroll
horizontal. Cartes de la taille d'`OnlineEventCard`, portant : nom, tags
playstyle, plateforme, badge Spotlight. 5 max visibles (au-delà, tri par `promoted_until` décroissant — les
abonnements les plus récents d'abord, ce qui donne de la visibilité aux
nouveaux arrivants et évite qu'un seul ancien monopolise la tête).

**Liste complète** (en-dessous) — toutes les communautés, promues mélangées
aux gratuites (les promues n'apparaissent pas deux fois — elles sont dans le
carrousel ET dans la liste). Triable/filtrable par :

- Playstyle (filtre multi-tag)
- Plateforme
- Langue
- Tranche de membres

Chaque ligne : nom, icônes playstyle, icône plateforme, lien Discord si
présent, badge Spotlight si promu.

### Fiche communauté (sheet)

Même motif que `OnlineEventDetailSheet` : une sheet modale.

- Nom (titre)
- Plateforme + tags playstyle
- Tranche de membres
- Section événements à venir (si promu et événements actifs)
- Bouton « Rejoindre sur Discord » (ouvre `discord.gg/*` via `openURL`)
- Bouton « Signaler » (même `ReportingModel` que les contributions)
- Si `owner_id == auth.uid()` : boutons « Modifier » et « Promouvoir » (ou « Gérer l'abonnement »)

### Section événements dans le volet principal

Sous le carrousel et au-dessus de la liste, une section **« Événements à
venir »** agrège les événements de toutes les communautés promues, triés par
`starts_at`. Chaque ligne : icône type, nom de la communauté, date/heure,
plateforme. Tap → fiche de la communauté.

Limitée aux 5 prochains événements ; « Voir tout » ouvre une liste complète
filtrée par les mêmes critères que la liste de communautés.

## Backend Supabase

### Tables

```sql
create table communities (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null references auth.users(id) unique,
  name            text not null
                  check (length(name) between 3 and 30)
                  check (name ~ '^[a-zA-Z0-9 -]+$'),
  platform        text not null
                  check (platform in ('ps5','xbox','pc','cross-platform')),
  playstyles      text[] not null default '{}',
  languages       text[] not null default '{}',
  discord_invite  text check (discord_invite ~ '^https://discord\.gg/'),
  member_count    int not null default 1 check (member_count >= 1),
  server_address  text,
  promoted        bool not null default false,
  promoted_until  timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create table community_events (
  id             uuid primary key default gen_random_uuid(),
  community_id   uuid not null references communities(id) on delete cascade,
  event_type     text not null
                 check (event_type in (
                   'tournament','themed_night','recruitment',
                   'launch','training','other'
                 )),
  platform       text not null
                 check (platform in ('ps5','xbox','pc','cross-platform')),
  starts_at      timestamptz not null,
  ends_at        timestamptz,
  slots          int check (slots > 0),
  created_at     timestamptz not null default now()
);
```

### RLS

```sql
-- Lecture publique
alter table communities enable row level security;
create policy "communities_read" on communities
  for select using (true);

create policy "communities_insert" on communities
  for insert with check (auth.uid() = owner_id);

create policy "communities_update" on communities
  for update using (auth.uid() = owner_id);

create policy "communities_delete" on communities
  for delete using (auth.uid() = owner_id);

-- Événements : lecture publique, écriture propriétaire + promu
alter table community_events enable row level security;
create policy "events_read" on community_events
  for select using (true);

create policy "events_insert" on community_events
  for insert with check (
    exists (
      select 1 from communities
      where id = community_id
        and owner_id = auth.uid()
        and promoted = true
    )
  );

create policy "events_delete" on community_events
  for delete using (
    exists (
      select 1 from communities
      where id = community_events.community_id
        and owner_id = auth.uid()
    )
  );
```

### Révocation de privilèges

Chaque migration qui crée `communities` ou `community_events` porte sa propre
révocation, sur le patron de `20260802140000_privileges.sql`. Le test
`privileges_test.sql` est étendu pour couvrir les nouvelles tables.

### Trigger de plafond d'événements

```sql
create or replace function enforce_event_limit()
returns trigger as $$
begin
  if (
    select count(*) from community_events
    where community_id = NEW.community_id
      and (ends_at is null or ends_at > now())
  ) >= 3 then
    raise exception 'event_limit_reached';
  end if;
  return NEW;
end;
$$ language plpgsql;

create trigger trg_event_limit
  before insert on community_events
  for each row execute function enforce_event_limit();
```

### Edge Function — extension de la notification StoreKit

L'Edge Function `storekit-webhook` (spec revenus) reçoit déjà les
notifications V2. Elle gagne un `switch` sur le `subscriptionGroupID` :

- `pro` → comportement existant
- `community_spotlight` → mise à jour de `communities` pour le
  `originalTransactionId` associé à l'`owner_id`

Le lien entre `originalTransactionId` et `owner_id` est posé à la première
souscription : l'app envoie le `Transaction.id` signé à une Edge Function
`activate-spotlight` qui vérifie la signature Apple et inscrit le mapping.

## Architecture Swift

### Modèles

- `Community` — `Codable`, décodé depuis Supabase. Pas de SwiftData : les
  communautés sont du contenu serveur, pas du contenu hébergé en Storage.
  Lecture directe via le client Supabase.
- `CommunityEvent` — `Codable`, même approche.
- `CommunityPromotionModel` — `@Observable`, gère l'état d'abonnement via
  `StoreKit.Transaction.currentEntitlements` et expose `isPromoted`.
  Indépendant de `ProEntitlementModel`.
- `CommunitiesModel` — `@Observable`, porte la liste chargée, les filtres, le
  tri, et le carrousel promu.

### Écrans

- `CommunitiesPanel` — le contenu du volet `.communities` dans
  `SocialScreen`, structuré comme `ContributionsPanel`.
- `CommunityCard` — la carte du carrousel en vedette.
- `CommunityRow` — la ligne de la liste complète.
- `CommunityDetailSheet` — la fiche modale.
- `CommunityEventRow` — la ligne d'événement.
- `CreateCommunitySheet` — le formulaire de création (Pickers structurés).

### Localisation

Toutes les clés suivent le préfixe `social.communities.*`. Les types
d'événements et les tags de playstyle ont chacun une clé localisée dans les
cinq langues. Le nom de la communauté et le lien Discord ne sont pas
localisés — ce sont des données utilisateur, pas du contenu éditorial.

## Tests

- **`CommunityTests`** — décodage de `Community` depuis du JSON Supabase,
  validation du format de nom (accepte/refuse), filtrage par playstyle et
  plateforme.
- **`CommunityEventTests`** — décodage, plafond de 3 événements actifs,
  visibilité d'un événement périmé.
- **`CommunityPromotionModelTests`** — transitions `promoted` ↔ non promu
  sur les notifications StoreKit simulées.
- **`CommunitiesModelTests`** — tri du carrousel (promus d'abord, puis par
  `promoted_until`), filtres combinés, état vide.
- **Supabase** — `communities_test.sql` : RLS (lecture anon, écriture
  authentifié propriétaire, refus d'écriture non-propriétaire), trigger de
  plafond, contraintes de format.
- **`LocalizationCoverageTests`** — couvre les nouvelles clés dans les cinq
  langues.

## Livraison

| Palier | Contenu | Dépend de |
|---|---|---|
| **C1** | Tables, RLS, trigger, migration, tests Supabase | Supabase déployé (acquis) |
| **C2** | Modèles Swift, `CommunitiesPanel`, liste + filtres, fiche, création | C1 |
| **C3** | `CommunityPromotionModel`, flux StoreKit, extension du webhook | C2 + webhook StoreKit existant |
| **C4** | Carrousel promu, événements, intégration `SocialScreen` | C2 + C3 |

**C1 + C2 donnent un annuaire fonctionnel sans promotion.** Si le flux
StoreKit prend du retard, l'annuaire sort quand même — la promotion
s'allume après.

## Risques

| Risque | Parade |
|---|---|
| **Spam de communautés** | Un compte = une communauté. App Check à la création. Signalement + shadow-ban |
| **Communautés fantômes** | Pas de nettoyage auto en v1.1. Un `updated_at` permet un futur tri par fraîcheur |
| **Noms abusifs / usurpation** | Format contraint, signalement, volume gérable manuellement |
| **FiveM et risque IP** | `server_address` préparé mais éteint. Aucune mention de FiveM dans l'UI tant que le champ est éteint par `app_config` |
| **Trop peu de communautés au lancement** | Le volet est éteint dans `app_config` tant que le contenu ne le justifie pas. Un annuaire vide n'apparaît jamais |
| **Apple 3.1.1** | Abonnement via StoreKit 2, aucun lien de paiement externe |
| **Apple 3.1.2 (abonnement)** | L'abonnement donne un avantage clair (badge, position, événements) documenté dans la page produit. Pas de dark pattern |
| **Le revenu B2B reste marginal** | C'est un revenu additionnel, pas un remplacement. Si zéro admin souscrit, le coût est nul — les tables existent, l'UI est éteinte |

## Ce qui n'est pas fait ici

- Multi-gestion de communautés (un admin, plusieurs groupes)
- Serveurs FiveM/RedM (champ préparé, décision IP reportée)
- Avis et notation (UGC lourd, Apple 1.2)
- Dashboard web pour les admins (tout passe par l'app)
- Recherche de coéquipiers — spec existante, même horizon v1.1, spec séparée
- Médiation de paiement Stripe
- Widget de communautés (v1.2+ si l'annuaire prend)
- Notifications push pour les événements communautaires (le volume ne le
  justifie pas en v1.1 ; les notifications locales sont réservées aux
  événements hebdo Rockstar)
