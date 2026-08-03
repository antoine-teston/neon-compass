# Migration Firebase → Supabase

**Date** : 2026-08-02
**Statut** : validé, non implémenté
**Branche** : à créer

## Problème

Firebase impose une complexité que le projet ne consomme pas, et qui bloque la moitié des
fonctionnalités écrites.

L'inventaire du 2026-08-02 donne la mesure exacte :

| Surface | État réel |
|---|---|
| Auth (Sign in with Apple) | déployé, porte la sync de progression |
| Firestore `profiles/{uid}/progression` | déployé |
| Firestore, collections de contenu | déployé, mais **repli seulement** — le CDN est primaire |
| Remote Config | déployé, 4 clés |
| Hosting | déployé, sert le CDN de contenu |
| App Check (App Attest) | configuré |
| **Cloud Functions (12, 1 106 lignes de source + 304 de tests)** | **jamais déployées** |

`docs/ops/2026-07-27-sans-blaze.md` documente le blocage : les Cloud Functions exigent le plan
Blaze, l'API n'a jamais été activée sur `neoncompass-gt-vi` (403 vérifié le 2026-07-27), et la v1
part donc avec les contributions, votes, signalements, pseudo/XP et notifications de catégorie
éteints — gouvernés par `backendFeaturesEnabled`. La suppression de compte, exigée par Apple, passe
par un contournement client (`FirebaseClientAccountDeletion`) faute de fonction serveur.

Le coût de cette complexité est donc payé deux fois : en configuration console non scriptable
(App Attest, clés APNs, comptes de service, alertes de budget, émulateurs), et en fonctionnalités
que le plan tarifaire retient en otage.

## Prémisse

**Aucune donnée de production n'existe.** L'app n'est pas publiée — il reste le Plan 7 Release. Ce
qui suit est une migration de code, pas de données : le scénario le moins risqué qui existe, et une
fenêtre qui se referme à la publication.

Supabase inclut les Edge Functions dans son offre gratuite (500 000 invocations par mois). Le verrou
Blaze disparaît, et avec lui la raison pour laquelle cinq surfaces de l'app sont éteintes.

## Décisions

### D1 — Périmètre : suppression totale de Firebase, Functions comprises

Les 12 Cloud Functions sont portées en Edge Functions, RPC Postgres et triggers dans le cadre de
cette migration, pas plus tard. Laisser 1 100 lignes écrites pour `firebase-functions` dans un dépôt
qui n'a plus Firebase serait une dette dont personne ne se souviendrait au moment d'allumer le
social.

Ne bougent pas : Google Mobile Ads, User Messaging Platform, StoreKit, SwiftData, tout le contenu,
tous les écrans.

### D2 — Le CDN de contenu va sur Supabase Storage, bucket public

**Décision prise en connaissance du risque, chiffré ci-dessous.** L'argument retenu est le
fournisseur unique : un jeu de credentials, un tableau de bord, un secret en CI.

Volumes mesurés le 2026-08-02 sur le contenu publiable :

| Collection | Fichiers | Octets |
|---|---:|---:|
| poi-gtav | 537 | 327 006 |
| news | 32 | 39 373 |
| cheats | 36 | 36 349 |
| poi | 11 | 10 336 |
| online-events | 1 | 5 766 |
| collections | 15 | 4 658 |
| **Total** | **632** | **423 488 (70 499 gzippés)** |

Le plan gratuit accorde **5 Go d'egress non-caché et 5 Go caché**, compteurs indépendants, et
l'egress est *unifié* : base, Auth, Storage, Edge Functions et Realtime tirent sur le même quota.
Au dépassement, la Fair Use Policy renvoie **402 sur tout le projet** — Auth et base comprises.

Projection, avec `coût ≈ MAU × bumps × charge + MAU × sessions × manifeste` :

| Hypothèse | Egress/mois | vs 5 Go |
|---|---:|---|
| 10 000 MAU, contenu actuel | ~3,1 Go | passe, 62 % du quota |
| 100 000 MAU, contenu actuel | ~31 Go | 6× au-dessus |
| 100 000 MAU, contenu ×10 (base POI réelle, 5 langues) | ~280 Go | dépasse les 250 Go inclus du plan Pro (25 $/mois), puis 0,09 $/Go |

Trois contre-mesures, toutes dans le périmètre de cette migration :

1. **Fragments pré-compressés, décompressés par l'app.** Mesuré à l'implémentation : 423 Ko → 60 Ko,
   soit ÷7.

   *Corrigé en cours de route.* Le design initial disait « upload gzippé avec
   `contentEncoding: 'gzip'` ». **Supabase Storage ne permet pas de poser `Content-Encoding` au
   téléversement** — seuls `contentType` et `cacheControl` existent, et le reste est une demande de
   fonctionnalité ouverte ([supabase-js#1883](https://github.com/supabase/supabase-js/issues/1883)).
   La décompression transparente par `URLSession` est donc hors d'atteinte.

   Les fragments partent en **DEFLATE brut** (RFC 1951) sous `.json.z`, décompressés par
   `ContentCDN.inflate`. Brut et pas gzip parce que c'est exactement ce qu'attend
   `NSData.decompressed(using: .zlib)` — dont le nom trompe : c'est du DEFLATE brut, pas le format
   zlib de la RFC 1950 — et exactement ce que produit `zlib.deflateRawSync` côté Node, sans en-tête
   à retirer de part et d'autre. Cet accord vit des deux côtés d'une frontière réseau, donc un test
   le fige à partir d'une charge réellement produite par Node.

   Ce qu'on perd : le `curl | jq` direct sur un fragment. Le manifeste, lui, reste en clair — c'est
   celui qu'on inspecte à la main. Et un fragment reste lisible partout : zlib est universel, un
   navigateur a `DecompressionStream('deflate-raw')`.
2. **Version par collection** dans le manifeste (voir D7). Facteur ÷10 environ.
3. **`contentBaseURL` reste piloté à distance.** Changer d'hébergeur ne demandera jamais une mise à
   jour de l'app. C'est la porte de sortie, et elle existe déjà dans l'architecture.

Le bucket s'appelle **`cdn`** et non `content` : les objets portent déjà un préfixe `content/` —
l'arborescence du site, volontairement indépendante de l'hébergeur — et un bucket homonyme donnerait
des URL en `.../public/content/content/manifest.json`.

À réévaluer sur des chiffres réels après lancement. Le seuil d'alarme est le passage au plan Pro :
s'il devient nécessaire *à cause de l'egress statique* et non de la charge applicative, sortir les
fichiers vers un hébergeur statique à egress illimité est le bon geste.

### D3 — App Check est abandonné

Supabase n'a pas d'équivalent, et porter la vérification App Attest en Deno (chaîne de certificats
Apple, nonce, compteur, gestion de clés, ~300 lignes sans bibliothèque) est exactement la complexité
que cette migration cherche à supprimer.

La spec §7 décrit six couches anti-abus. App Check en est **une**. Les cinq autres portent sans
perte : chemin d'écriture unique validé serveur, cooldown, votes uniques par construction,
monitoring de vélocité avec shadow-ban, kill-switch. S'y ajoutent RLS — qui interdit structurellement
d'écrire ailleurs que sous son propre `uid` — et un quota par `uid` en Postgres.

Le vrai coût d'entrée d'un spammeur reste l'identité Sign in with Apple, comme l'énonce déjà la
spec : « réinstaller ne crée pas une nouvelle identité ».

### D4 — Le push passe par APNs en direct, sans FCM

Table `push_tokens(token, uid, categories[])`. Une Edge Function signe un JWT ES256 avec la clé
`.p8` APNs (Web Crypto natif en Deno) et poste vers `api.push.apple.com`. Les topics FCM deviennent
une requête SQL.

Environ 120 lignes, aucune dépendance, et un intermédiaire de moins : la clé APNs va dans un secret
Supabase au lieu d'être téléversée dans la console Firebase.

Conséquence côté app : l'`AppDelegate` doit appeler `registerForRemoteNotifications()` et remonter le
device token via `didRegisterForRemoteNotificationsWithDeviceToken` — là où FCM le faisait pour nous.

### D5 — Le CDN devient la seule source de contenu

`ChunkedContentRepository` et `FirestoreContentRepository` sont supprimés, pas portés. Aucune table
Postgres ne stocke de contenu — **y compris les fragments de spots communautaires**, qui vont eux
aussi sur Storage, écrits par `rebuildCommunityBundles`.

Leur version reste **séparée** de celle du contenu éditorial. Écarté : les faire entrer dans le
manifeste comme une collection ordinaire de D7. C'était tentant, mais le manifeste serait alors
écrit par deux producteurs à des cadences différentes — la CI de publication et une tâche planifiée
à cinq minutes — avec une course à la clé.

Ils ont donc **leur propre manifeste** sur le CDN, `content/community_spots/manifest.json`, écrit par
`rebuildCommunityBundles`. Un fichier par producteur, aucune course. C'est le même raisonnement qui
avait donné un document de version distinct côté Firestore ; il se porte tel quel, et rien de tout
ça n'atterrit dans `app_config` — qui ne contient plus aucune version de contenu.

Le repli réseau n'est pas remplacé, il est **rendu inutile** par un filet meilleur, déjà en place :
le socle embarqué dans le binaire (`seed-poi.json`, `seed-cheats.json`) fusionné avec le cache
SwiftData de la dernière synchronisation. Une panne CDN dégrade vers « le contenu d'hier », pas vers
des écrans vides — ce que le repli Firestore ne garantissait pas mieux.

Gain : trois fichiers Swift (`ChunkedContentRepository`, `FirestoreContentRepository` et, combiné à
D7, `RemoteConfigVersionProvider`), un chemin de publication, et zéro octet de contenu sur le quota
Supabase que D2 demande justement de ménager.

### D6 — Migration par couche, derrière les protocoles existants

Le CLAUDE.md pose que « Firebase stays behind protocols in `Core/` — features never import it
directly ». Ce travail est fait et payé : la migration consiste largement à écrire treize nouvelles
implémentations et à changer les sites de construction.

Écarté : le big-bang (l'app ne compile pas pendant l'essentiel d'un chantier de ~3 000 lignes, rien
n'est vérifiable avant la fin) et la coexistence des deux SDK derrière un drapeau d'exécution
(justifiée pour migrer des données de production — il n'y en a pas, on paierait deux SDK dans le
binaire pour une garantie sans objet).

### D7 — La version de contenu devient par collection

Aujourd'hui `ContentManifest.version` est globale et `ContentStore.sync` (`ContentStore.swift:83`)
compare cette version unique. **Une publication d'actu fait donc retélécharger les 327 Ko de POI à
tous les clients.**

`CollectionInfo` gagne un champ `version`. `ContentStore` compare la version de *sa* collection.
`cdn-build.mjs` la calcule par collection, à partir d'une empreinte du contenu (clés triées, pour
qu'un simple réenregistrement ne fasse pas avancer la version), et la mémorise dans un verrou
versionné `content/cdn-versions.json` — déterministe, hors ligne, et le diff se relit en PR.

**Règle exacte**, apprise d'un défaut trouvé à l'implémentation : une collection dont l'empreinte
change prend `max(nombre de commits, version précédente + 1)`. Le `+ 1` n'est pas décoratif — sans
lui, deux publications depuis le même commit avec un contenu différent donnaient la même version,
donc le même chemin, servi `immutable` pour un an. Le nouveau contenu n'aurait jamais atteint un
client déjà passé par là, et la garde `remoteVersion > localVersion` n'aurait rien vu non plus.

C'est le principal levier sur l'egress de D2, et une correction de fond indépendamment : le portillon
de version prétendait déjà être un delta. Vérifié de bout en bout : modifier une seule actu ne fait
avancer que `news`, les 327 Ko de POI gardant leur URL.

## Architecture cible

### Correspondance des services

| Firebase | Supabase |
|---|---|
| Auth, Sign in with Apple | Auth, provider Apple, flux ID-token natif |
| Firestore `profiles/{uid}/progression` | table `progression`, PK `(uid, kind, item_id)` |
| Firestore `contributions`, `votes`, `reports` | tables homonymes |
| Firestore `leaderboards` | vue matérialisée, `pg_cron` |
| Firestore, collections de contenu | *supprimé* (D5) |
| `firestore.rules` | politiques RLS dans `supabase/migrations/*.sql` |
| Remote Config | table `app_config(key, value jsonb)` |
| Hosting | Storage, bucket public `content` |
| Cloud Functions ×12 | 6 Edge Functions, 2 RPC, 4 triggers, 1 tâche planifiée |
| App Check | *supprimé* (D3) |
| FCM par topics | APNs direct + `push_tokens` (D4) |

### Schéma Postgres

```sql
progression   (uid, kind, item_id) PK, found, updated_at
profiles      uid PK → auth.users, handle unique, xp, shadow_hidden, created_at,
              level integer generated always as (
                case when xp >= 2000 then 5 when xp >= 900 then 4
                     when xp >= 400  then 3 when xp >= 150 then 2
                     when xp >= 50   then 1 else 0 end) stored
contributions id PK, author_uid, category, title, position_x, position_y,
              language_code, status, shadow_hidden, upvotes, downvotes, created_at
votes         (contribution_id, uid) PK, direction, created_at
reports       id PK, contribution_id, reporter_uid, reason, created_at,
              unique (contribution_id, reporter_uid)
app_config    key PK, value jsonb, updated_at
              -- clés : contentBaseURL, backendFeaturesEnabled,
              --        communityContributionsEnabled, communitySpotsVersion
              -- contentVersion disparaît : elle vient du manifeste (D7)
push_tokens   token PK, uid, categories text[], updated_at
editor_drafts id PK, author_uid, payload jsonb, created_at, applied_at
editors       uid PK
leaderboard   MATERIALIZED VIEW
```

Trois invariants qui étaient des conventions Firestore deviennent des contraintes que la base fait
respecter :

- **Un vote par personne** : la clé primaire `(contribution_id, uid)`, au lieu de la convention d'ID
  composite `{spotId}_{uid}`.
- **Le niveau dérive de l'XP** : colonne générée à partir des seuils
  `[0, 50, 150, 400, 900, 2000]` de `functions/src/xp.ts`. Cela supprime les **deux** copies
  actuelles de `levelForXP` — celle de la Function et celle que `tools/content-cli` duplique faute
  d'être compilée avec `functions/`, duplication que le commentaire de `xp.ts` documente comme un
  pis-aller. Les noms de grades (`SIGNAL`, `PULSE`, `DRIFT`, `CIRCUIT`, `OVERDRIVE`,
  `SYNTHWAVE ICON`) restent côté client : c'est de l'affichage localisé, pas une règle métier.
- **Les compteurs de votes** : trigger sur `votes` maintenant `contributions.upvotes/downvotes`,
  atomique, au lieu d'un recalcul dans `castVote`.

### Politiques RLS

Reprise de `firestore.rules` ligne pour ligne :

| Table | Lecture | Écriture |
|---|---|---|
| `app_config`, `leaderboard` | publique | `service_role` |
| `progression` | `auth.uid() = uid` | `auth.uid() = uid` |
| `profiles` | `auth.uid() = uid` | `service_role` |
| `contributions` | `(status = 'approved' and not shadow_hidden) or author_uid = auth.uid()` | `service_role` |
| `votes` | `auth.uid() = uid` | `service_role` |
| `reports` | aucune | `service_role` |
| `editor_drafts` | `exists (select 1 from editors where uid = auth.uid())` | idem |

Le dernier point corrige une dette : `firestore.rules` porte aujourd'hui
`request.auth.uid == 'REMPLACER_PAR_UID_EDITEUR'` — un UID en dur, jamais renseigné. La table
`editors` garde le même défaut fermé, mais se renseigne sans redéployer de règles.

### Côté Swift

Vingt-et-un fichiers importent Firebase : dix-sept disparaissent, quatre sont recâblés. Rien
au-dessus de `Core/` n'est touché — aucun écran, aucun `@Observable` de feature.

**Créés** — quinze fichiers, dont treize implémentations de protocoles existants :

```
Core/Supabase/SupabaseClientProvider.swift           (infra) remplace FirebaseApp.configure()
                                                     + FirebaseAvailability
Core/Config/SupabaseAppConfig.swift                  (infra) lecture unique par session d'app_config
Core/Auth/SupabaseAuthProvider.swift                 AuthProviding
Core/Auth/SupabaseProfileRepository.swift            ProfileRepository
Core/Auth/SupabaseAccountFunctions.swift             AccountFunctionsCalling
Core/Auth/SupabaseAccountDeletion.swift              AccountDeleting
Core/Sync/SupabaseProgressionSync.swift              ProgressionSyncing
Core/Config/SupabaseServerFeatureGate.swift          ServerFeatureGateProviding
Core/Community/SupabaseCommunityGateProvider.swift   CommunityGateProviding
Core/Community/SupabaseContributionRepository.swift  ContributionRepository
Core/Community/SupabaseLeaderboardRepository.swift   LeaderboardRepository
Core/Community/SupabaseContributionFunctions.swift   ContributionFunctionsCalling
Core/Community/SupabaseCommunityBundleVersionProvider.swift  ContentVersionProviding
Core/Notifications/APNsFollowedCategoryNotifier.swift        FollowedCategoryNotifying
Core/Editor/SupabaseEditorDraftStore.swift           EditorDraftStore
```

**Supprimés** — dix-sept fichiers. Treize ont un remplaçant dans la liste ci-dessus
(`FirebaseAuthProvider`, `FirebaseAccountFunctions`, `FirebaseClientAccountDeletion`,
`FirestoreProfileRepository`, `FirestoreProgressionSync`, `RemoteConfigServerFeatureGate`,
`RemoteConfigCommunityGateProvider`, `FirestoreContributionRepository`,
`FirestoreLeaderboardRepository`, `FirebaseContributionFunctions`, `CommunityBundleVersionProvider`,
`FirestoreEditorDraftStore`, `FirebaseFollowedCategoryNotifier`). Quatre partent sans remplacement :
`FirebaseAvailability` (absorbé par `SupabaseClientProvider`), `ChunkedContentRepository` et
`FirestoreContentRepository` (D5), `RemoteConfigVersionProvider` — la version du contenu éditorial ne
vient plus que du manifeste, `CDNContentVersionProvider` perdant son paramètre de repli.

**Modifiés** — huit :

| Fichier | Changement |
|---|---|
| `App/NeonCompassApp.swift` | `FirebaseApp.configure()` + App Check → construction du client Supabase |
| `App/AppDelegate.swift` | `Messaging.messaging().apnsToken = …` → upsert du device token dans `push_tokens` (D4) |
| `App/RootView.swift` | `configureFromRemoteConfig()` → `configureFromAppConfig()` |
| `Core/Content/ContentStore+Live.swift` | câblage et `ContentSourceConfigurator` |
| `Core/Content/CDNContentRepository.swift` | perd son repli (D5) |
| `Core/Content/ContentCDN.swift` | version par collection (D7) |
| `Core/Editor/EditorRemoteAvailability.swift` | `Auth.auth().currentUser` → session Supabase ; la garde de configuration disparaît |
| `project.yml` | paquets et dépendances |

`AppleSignInCoordinator` ne change pas : il produit déjà `idToken` et `nonce`, exactement la
signature de `signInWithIdToken(OpenIDConnectCredentials(provider: .apple, …))`. Vérifié dans
`supabase-swift` le 2026-08-02, qui maintient par ailleurs la conformité `Sendable` pour Swift 6
strict concurrency.

Deux simplifications tombent au passage :

- `SupabaseClient` ne plante pas d'une erreur fatale non rattrapable s'il est construit avant sa
  configuration. Toutes les précautions documentées autour de ce piège disparaissent —
  `FirebaseAvailability`, les propriétés calculées de `FirebaseClientAccountDeletion`, la garde de
  `ContentSourceConfigurator`.
- `RemoteConfigCommunityGateProvider` doit distinguer « clé absente » de « clé à faux » via
  `value.source == .static`, contournement d'API commenté sur huit lignes. Avec une table, « absent »
  c'est « pas de ligne » : le fail-open et le fail-closed s'écrivent chacun en une ligne. Les
  sémantiques opposées voulues par `docs/ops/2026-07-27-sans-blaze.md` sont conservées —
  `backendFeaturesEnabled` absent vaut faux, `communityContributionsEnabled` absent vaut vrai.

### Côté serveur

Les 12 Cloud Functions deviennent **6 Edge Functions, 2 RPC Postgres, 4 triggers et 1 tâche
planifiée** — treize objets pour douze fonctions, parce que `notifyFollowedCategory` se scinde en un
trigger et la fonction d'envoi.

| Cloud Function | Devient |
|---|---|
| `createUserProfile` | trigger Postgres sur `auth.users` |
| `castVote` | RPC `security definer` |
| `reportContribution` | RPC `security definer` |
| `flagSuspiciousContribution` | trigger Postgres |
| `flagCommunityBundlesDirty` | trigger Postgres |
| `rebuildLeaderboard` | `refresh materialized view` par `pg_cron` |
| `rebuildCommunityBundles` | Edge Function planifiée — écrit les fragments sur Storage et upserte `communitySpotsVersion` (D5) |
| `regenerateHandle` | Edge Function |
| `deleteAccount` | Edge Function (`service_role`) |
| `submitContribution` | Edge Function |
| `appStoreServerNotification` | Edge Function publique (`verify_jwt: false`) |
| `notifyFollowedCategory` | trigger + `pg_net` → Edge Function `sendPush` |

`deleteAccount` en Edge Function règle la dette de conformité de `sans-blaze.md` : suppression en
cascade par contrainte FK puis `auth.admin.deleteUser()`, au lieu du chemin client à l'ordre critique
qui échoue sur session ancienne.

### Outillage et CI

`tools/content-cli/firestore-client.js` → `supabase-client.js` :

| Fonction actuelle | Devient |
|---|---|
| `pushDocuments`, `pushBundles` | *supprimées* (D5) |
| `incrementContentVersion` | écrit les versions par collection dans le manifeste (D7) — plus aucune clé de version côté base pour le contenu éditorial |
| `getRemoteConfigParameter`, `setRemoteConfigParameter` | select / upsert `app_config` |
| `fetchFirestoreRules`, `deployFirestoreRules` | *supprimées* — RLS dans les migrations, `supabase db push` |
| `listEditorDrafts`, `markEditorDraftsApplied`, `listPendingContributions`, modération | PostgREST |
| *(nouveau)* | upload Storage gzippé, `cacheControl` par objet |

Les règles d'accès cessent d'être un fichier poussé par une API pour devenir du SQL versionné, relu
en pull request. `.firebaserc`, `firebase.json` et `firestore.rules` disparaissent.

`.github/workflows/content.yml`, job `publish` : `FIREBASE_SERVICE_ACCOUNT` cède la place à
`SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY`, et la séquence devient `cdn-build` → gzip → upload
Storage → `supabase db push`. Le job `check` ne change pas.
`.github/workflows/veille.yml` ne touche pas à Firebase et ne change pas.

Les en-têtes de cache aujourd'hui déclarés dans `firebase.json` se posent objet par objet à
l'upload : `max-age=31536000, immutable` sur `content/v{N}/…`, `max-age=60` sur
`content/manifest.json`.

## Bascule

Six étapes. Chacune compile, passe les tests, et laisse l'app fonctionnelle si le chantier
s'interrompt là.

1. **Socle** — projet Supabase, migrations SQL (schéma + RLS), package SPM, `SupabaseClientProvider`.
   Firebase toujours en place. *C'est ici qu'on découvre un éventuel problème
   `supabase-swift` × Swift 6, et c'est pour ça que cette étape est la première.*
2. **Config** — `app_config`, les trois portails, suppression de Remote Config.
3. **CDN** — bucket Storage, `cdn-build` gzippé, version par collection (D7), suppression du repli
   contenu (D5).
4. **Auth et sync** — `SupabaseAuthProvider`, `SupabaseProgressionSync`, Edge Function
   `deleteAccount`.
5. **Social** — Edge Functions restantes, RPC, triggers, APNs (D4).
6. **Suppression** — dépendances Firebase de `project.yml`, `firebase.json`, `.firebaserc`,
   `firestore.rules`, `functions/`, `GoogleService-Info.plist`. `xcodegen generate`, build, tests.

Retour arrière : tant que l'étape 6 n'est pas faite, `contentBaseURL` et les sites de construction
permettent de revenir à Firebase. Après, c'est un `git revert`.

## Tests

Les sept fichiers de test qui mentionnent Firebase ne le font qu'en commentaires et en doublures de
protocole — **ils passent sans modification**. C'est la vérification que l'abstraction tenait.

S'ajoutent :

- Politiques RLS, en pgTAP sous `supabase/tests/` — notamment qu'un `uid` ne lit pas la progression
  d'un autre, et que `contributions` masque bien `pending` et `shadowHidden`.
- Edge Functions, en `deno test`, en reprenant les cas des `*.test.ts` existants
  (`contribution.test.ts`, `vote.test.ts`, `handle.test.ts`, `leaderboard.test.ts`,
  `communityBundles.test.ts`, `xp.test.ts` — ce dernier devenant un test de la colonne générée).
- `SupabaseAppConfig` : fail-closed sur `backendFeaturesEnabled` absent, fail-open sur
  `communityContributionsEnabled` absent.
- `cdn-build.test.mjs` : versions par collection, et fichiers effectivement gzippés.

`supabase start` (Docker) remplace les émulateurs Firebase pour le développement local.

## Environnements

Deux projets Supabase, dev et prod — exactement la limite du plan gratuit.

Piège à connaître : un projet gratuit est **mis en pause après 7 jours sans requête**, avec un
réveil de 20 à 30 secondes. Le projet de dev en pâtira, la prod non une fois l'app lancée.

## Risques

1. **Egress Storage** — chiffré en D2, mitigé par le gzip, la version par collection et la porte de
   sortie `contentBaseURL`. À réévaluer sur des chiffres réels après lancement.
2. **`supabase-swift` sous strict concurrency** — premier point de rupture possible, traité à
   l'étape 1.
3. **Pause du projet gratuit** — gêne de développement, pas de production.
4. **`appStoreServerNotification` change d'URL** — à mettre à jour dans App Store Connect au moment
   de la bascule, sinon les notifications d'abonnement Pro tombent dans le vide **sans erreur
   visible**. Point de contrôle explicite dans le plan d'implémentation.
5. **Perte de l'attestation d'appareil** — accepté en D3.

Inchangée par cette migration, mais toujours ouverte : `aps-environment` reste à basculer en
`production` avant une soumission (`docs/ops/2026-07-23-widgets-and-push-setup.md` §3).

## Documents à mettre à jour à l'implémentation

- `CLAUDE.md` — la ligne « Firebase (Firestore, Anonymous Auth, Remote Config, Analytics) et Google
  Mobile Ads sont approuvés » et « Firebase stays behind protocols in `Core/` ».
- `docs/ops/2026-07-23-firebase-console-manual-steps.md` — devient sans objet (App Check, alertes de
  budget, coupe-circuit Remote Config).
- `docs/ops/2026-07-27-sans-blaze.md` — devient sans objet : la contrainte qu'il documente disparaît.
- `docs/ops/2026-07-23-widgets-and-push-setup.md` §2 et §4 — la clé APNs va dans un secret Supabase,
  le test de push ne passe plus par la console Firebase.
- `docs/ops/2026-07-27-content-publishing.md` et `2026-07-27-contenu-sur-cdn.md` — nouvelle cible de
  publication.
- `docs/superpowers/specs/2026-07-19-neon-compass-companion-design.md` §7 — la couche 1 (App Check)
  tombe, les cinq autres restent.
