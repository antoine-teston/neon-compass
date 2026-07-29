# Neon Compass — App compagnon non officielle pour GTA VI

**Date** : 2026-07-19 · **Statut** : validé en brainstorming, en attente de relecture finale

## 1. Vision produit

App iOS/iPadOS compagnon pour la sortie de GTA VI (19 novembre 2026), publiée sur l'App Store, gratuite, financée par la publicité et un achat unique « Pro » (confort et outils — jamais les faits). Quatre piliers au lancement : carte interactive stylisée, guide cheats & astuces, suivi de progression, contributions communautaires sur la carte. Le modèle publicitaire impose une app à usage quotidien pendant les semaines post-sortie : la rétention (progression, contenu frais) est un objectif produit de premier rang, pas un bonus.

**Critères de succès** : app approuvée par Apple et disponible avant le 19 novembre ; carte utilisable (schématique + premiers POI) dans les 72 h suivant la sortie ; contributions modérées en < 24 h.

## 2. Cadre juridique

Fondement : **les faits ne sont pas protégés par le droit d'auteur** (cheat codes, emplacements, noms de missions, stats). C'est la base légale des wikis et apps compagnon existants. Les règles qui en découlent :

- **Marques** : aucune marque Rockstar/Take-Two (GTA, Grand Theft Auto, Vice City, Leonida, Rockstar) dans le nom, l'icône, le sous-titre App Store ou le bundle ID. Usage nominatif autorisé uniquement dans la description : « Guide compagnon non officiel pour Grand Theft Auto VI ».
- **Assets** : zéro asset Rockstar — pas de logos, artworks, screenshots, audio, ni données extraites des fichiers du jeu (le data-mining est une violation). Toute la DA est originale/générée.
- **Rédaction** : les faits agrégés depuis des sources publiques (wikis, Reddit) sont systématiquement reformulés — les faits sont libres, leur rédaction ne l'est pas.
- **Disclaimer** : premier lancement + page À propos : « Application non officielle, non affiliée à Rockstar Games ni Take-Two Interactive ».
- **Carte** : illustration originale schématique/stylisée, jamais une reproduction pixel-accurate de la carte officielle.
- **Preuves** : prompts et fichiers sources de toutes les images générées archivés comme preuve d'originalité.

**Posture** : le risque principal est la review Apple (guideline 5.2.1), pas Take-Two. En cas de contact de Take-Two : conformité immédiate (le kill-switch Remote Config permet de retirer un contenu en minutes).

## 3. Identité & conformité

- **Nom de travail** : Neon Compass (critère : évocateur Miami/néon, sans citer l'univers). Projet Xcode `NeonCompass` (le CLAUDE.md est mis à jour en conséquence).
- **Classement** : 17+.
- **Publicité** : AdMob avec prompt ATT + consentement UMP (UE), politique de confidentialité hébergée. Sans opt-in IDFA, AdMob sert des pubs contextuelles — le revenu repose sur le volume du pic de sortie.
- **UGC (Apple 1.2)** : les quatre exigences couvertes — pré-modération (plus forte que le filtrage exigé), signalement de contenu, **blocage d'utilisateur par l'utilisateur** (masquer tous les spots d'un contributeur : liste de blocage locale + filtre à l'affichage, réversible dans les réglages), conditions d'utilisation acceptées avant la première contribution.
- **RGPD sobre by design** : progression stockée en local uniquement ; côté serveur, uniquement l'identifiant Sign in with Apple (e-mail masquable), le pseudo choisi et les données de contribution/niveau. Suppression de compte in-app = effacement complet. Consentements pub (ATT/UMP) à part.

## 4. Architecture technique

Client conforme au CLAUDE.md : Swift 6 (strict concurrency), SwiftUI + `@Observable`, SwiftData, **iOS/iPadOS 26+**, iPhone + iPad. Le minimum iOS 26 est un choix délibéré : à la sortie (nov. 2026), iOS 26 aura plus d'un an, le public gamer est massivement à jour, et cela donne Liquid Glass natif partout sans fallback à maintenir.

**iPad — cas d'usage prioritaire** : la tablette posée à côté de la télé pendant qu'on joue sur console est le scénario naturel d'une app compagnon ; l'iPad est donc traité en première classe, pas en portage. Concrètement : mêmes features, layouts adaptatifs — `TabView` en `.sidebarAdaptable` (sidebar Liquid Glass native sur iPadOS 26), et sur la carte la fiche POI s'affiche en panneau latéral persistant plutôt qu'en sheet, pour garder la carte visible en permanence. Le viewer de carte tuilé est dimensionné pour les résolutions iPad dès sa conception. Une seule app universelle, pas de code spécifique par plateforme au-delà des layouts adaptatifs (`horizontalSizeClass`). Backend : **Firebase** (Firestore, Auth anonyme, Remote Config, Analytics) + **AdMob**. Dérogation assumée à la règle « pas de dépendance tierce » : la monétisation pub impose le SDK Google, autant capitaliser sur l'écosystème.

```
NeonCompass/
  App/                  # entrée, NavigationStack racine, onboarding (disclaimer, ATT/UMP)
  Features/
    Map/                # carte + contributions communautaires
    Guides/             # cheats, guides, tips
    Progress/           # checklists, stats
  Core/
    Content/            # sync Firestore → cache SwiftData, versionnement
    Ads/                # wrapper AdMob (bannières, interstitiels plafonnés)
    DesignSystem/       # palette synthwave, typo, composants
```

**Flux de données**
- Contenu éditorial (POI, guides, cheats) : Firestore → cache SwiftData local. Lecture réseau en delta seulement (champ `contentVersion` piloté par Remote Config). L'app est pleinement utilisable hors-ligne.
- Progression utilisateur : SwiftData local uniquement, une seule source de vérité partagée entre carte et checklists. Jamais envoyée au serveur.
- Contributions et votes : **jamais d'écriture directe du client** — tout passe par des Cloud Functions callable (`submitContribution`, `castVote`), les Security Rules interdisant l'écriture directe sur ces collections. Statuts : `pending` → modération → `approved` → visibles. Cloud Functions ⇒ plan Firebase Blaze (pay-as-you-go).
- Authentification : **Sign in with Apple, requis uniquement pour contribuer, voter et avoir un profil/niveau** — l'identité stable rend les bans définitifs et porte le système de points. Toute la consultation (carte, cheats, guides, actu) fonctionne sans compte. Seule option de connexion proposée. Suppression de compte in-app (guideline Apple 5.1.1).
- Firebase est isolé derrière des protocoles dans `Core/` : les features sont testables sans I/O.

**Moteur de carte** (pièce technique principale) : illustration originale découpée en tuiles de zoom, rendue dans un viewer zoom/pan custom (SwiftUI wrappant `CATiledLayer`). POI positionnés en **coordonnées normalisées (0-1), indépendantes de l'artwork** — on peut remplacer le dessin sans toucher aux données.

**Remote Config pilote** : version du contenu, fréquence des pubs, kill-switch de la feature communautaire.

## 5. Features

### Navigation

Navbar basse à 5 emplacements avec la **carte en bouton central proéminent** (cercle en verre teinté magenta, légèrement surélevé — `glassEffect` dans le `GlassEffectContainer` de la barre) :

**[ Actu ] [ Cheats & Guides ] [ ● CARTE ] [ Progression ] [ Profil ]**

L'Actu est l'écran d'accueil par défaut ; les réglages sont une icône dans l'Actu. Sur iPad, la barre devient la sidebar adaptative (`.sidebarAdaptable`) — le bouton central est un concept iPhone uniquement.

**Actu (feed).** Flux chronologique alimenté par Firestore (même pipeline que le reste du contenu) : nouveaux POI et guides publiés, actualités officielles reformulées (annonces Rockstar, patchs/title updates, événements in-game), spots communautaires les plus votés de la semaine. C'est le moteur de rétention quotidienne — et l'emplacement publicitaire principal (bannière + cellules sponsorisées natives plafonnées).

### Les features

**Carte** (bouton central). Zoom/pan, filtres par catégorie (collectibles, activités, planques, véhicules rares, événements), recherche. Fiche POI : description, astuce, bouton « Trouvé » alimentant la progression. Contribution : appui long → proposer un spot (catégorie, titre, note ≤ 280 caractères, position) ; spots approuvés badgés communauté, votes ▲▼, signalement, et **« masquer les spots de ce contributeur »** (blocage utilisateur, exigence Apple 1.2 — liste locale, gérable dans les réglages). Les spots très votés sont promouvables en contenu éditorial.

**Cheats & Guides** (un onglet, deux sections — les cheats d'abord : le cas d'usage est « je suis en jeu, il me faut ce code en 5 secondes »).

*Format de lecture des cheats* :
- **Carte par code** : nom + effet en une ligne, séquence en **chips de glyphes manette** (SF Symbols PlayStation/Xbox), toggle global PS5/Xbox qui bascule toutes les séquences, badge « bloque les trophées » (flag par cheat), recherche et catégories, favoris épinglés en tête.
- **Mode lecture plein écran** : tap sur une carte → glyphes énormes sur 2-3 lignes lisibles à 2 m, fond assombri, **écran maintenu allumé** (`isIdleTimerDisabled`) pendant la saisie manette, swipe horizontal vers le cheat suivant de la catégorie.
- **Modèle en tokens abstraits** : séquence stockée `["circle","l1","triangle",…]`, rendue en glyphes selon la plateforme — indépendant de la langue. Champ `type` extensible : `sequence` (boutons), `phoneNumber` (numéro in-game façon GTA V, affiché en gros), `text` — on ne parie pas sur le mécanisme exact avant la sortie du jeu.

*Guides* : Markdown rendu nativement, chapitres : histoire, side content, débutant, argent. Lisible hors-ligne après cache.

**Progression.** Checklists auto-générées depuis le contenu, pourcentages global et par catégorie, anneau de progression néon. Même enregistrement SwiftData que le « Trouvé » de la carte.

**Profil & leveling.** Accessible après Sign in with Apple : **handle auto-généré à consonance synthwave** (ex. « NEON-FALCON-88 », regénérable — jamais de pseudo libre : supprime la modération des noms, le risque d'usurpation type « Rockstar_Official » et du data personnel), XP gagnée par contribution approuvée et par vote reçu, grades à thème synthwave **originaux** (jamais les rangs de GTA), badges, historique de mes contributions avec leurs statuts, badge premium, réglages (langue, plateforme manette par défaut, suppression de compte). Le niveau est calculé côté serveur (Cloud Function à l'approbation) — jamais par le client.

**Monétisation.**
- **Publicité** : bannière adaptative en bas des écrans de liste et du feed — jamais sur la carte en interaction. Interstitiel plafonné (max 1/session, jamais pendant une contribution), fréquence via Remote Config.
- **Pro (achat unique ~5-6 €, StoreKit 2)** — principe : le premium vend du confort et des outils, **jamais des faits** (cheats, données de carte et guides restent intégralement gratuits — paywaller des infos disponibles sur les wikis pousserait les utilisateurs ailleurs et ruinerait la réputation de l'app ; option « limiter certains cheats » examinée et écartée volontairement) et **jamais d'XP** (un ranking achetable ne vaut rien). Contenu du pack :
  - Suppression des pubs.
  - **Sync cloud de la progression iPhone↔iPad** (nécessite le compte).
  - **Planificateur d'itinéraire de collecte** : route optimisée par proximité sur les collectibles restants (tri glouton sur les coordonnées normalisées).
  - **Mode « reste à faire »** : toggle qui masque tout le déjà-trouvé sur la carte.
  - **Widgets** écran d'accueil/verrouillé : anneau de progression, cheat favori épinglé (rendu accented Liquid Glass).
  - **Notifications suivies** : push quand un spot est publié dans une catégorie/zone suivie (FCM topics — les notifications générales restent gratuites).
  - Icônes d'app et thèmes néon exclusifs + badge profil.
  - L'entitlement StoreKit signé par Apple est la **source de vérité locale** ; le compte n'en est qu'un miroir serveur (App Store Server API) pour le badge et les features liées au compte. L'achat ne requiert jamais de connexion.
  - V1.1+ : **Live Activity « session de jeu »** — au démarrage d'une session, l'utilisateur choisit un objectif (catégorie de checklist ou route du planificateur Pro) ; écran verrouillé : objectif, progression, prochain POI, chrono ; Dynamic Island étendue : bouton « Trouvé ✓ » interactif (`LiveActivityIntent` écrivant dans le même enregistrement SwiftData que la carte) — cocher sans déverrouiller. Mises à jour locales, fin auto à la complétion (limite système 8 h). Également v1.1+ : app Apple Watch cheats, export d'image de sa carte annotée.

**Trophées & succès.** V1 : **checklists manuelles** intégrées à la Progression — la liste des trophées est un fait librement reproductible, le cochage manuel couvre l'essentiel du besoin. V1.2 : exploration de l'auto-cochage **Xbox uniquement** (OAuth Microsoft via service établi type OpenXBL, consentement explicite). **PSN : écarté** — pas d'API officielle, et les endpoints non officiels (violation des ToS Sony, token NPSSO utilisateur, risque Apple 5.2.2) cumuleraient une zone grise de trop pour cette app. Décision : réévalué uniquement si Sony publie un jour une API officielle.

**Localisation (FR, EN, ES, IT, DE).** Cinq langues dès la v1 — le pic de sortie est mondial, c'est un multiplicateur d'audience direct pour un coût contenu maîtrisé :
- **UI** : String Catalogs Xcode (`.xcstrings`), anglais comme langue de développement, traductions relues.
- **Contenu éditorial** : champs localisés dans le modèle Firestore (`title.fr`, `title.en`, …) avec **fallback anglais** si une langue manque. La rédaction source se fait en FR ou EN ; le script d'admin intègre une étape de **traduction automatique par IA vers les autres langues** au moment de la publication (relecture par sondage). Pendant le sprint jour J, l'anglais peut être publié seul, les autres langues suivent en heures.
- **Contributions communautaires** : affichées dans la langue de l'auteur avec un tag de langue, pas de traduction en v1.
- **App Store** : fiche localisée dans les cinq langues.

## 6. Direction artistique

**Principe directeur : le néon est le contenu, le verre est le chrome.** Deux couches strictement séparées :
- **Couche contenu (rétro)** : fonds en dégradés sunset magenta→violet→orange sur nuit bleu-noir, illustrations synthwave générées, typo display 80s open source (licence OFL, type Orbitron — jamais Pricedown) réservée aux titres d'écran, SF Pro partout ailleurs. Mode sombre uniquement.
- **Couche interface (Liquid Glass, iOS 26)** : toutes les surfaces de contrôle — tab bar, toolbars, fiche POI, boutons flottants de la carte — sont en Liquid Glass et laissent transparaître le néon en dessous. C'est ce qui donne le côté **épuré** : l'UI n'ajoute presque aucune couleur propre, elle réfracte celles du fond.

**Sobriété rétro assumée** : pas de skeuomorphisme chargé (pas de scanlines/CRT généralisés), le glow est réservé à trois accents — l'anneau de progression, le POI sélectionné, l'action principale. Beaucoup d'air, listes sobres sur verre.

**Implémentation Liquid Glass** :
- Tab bar et navigation : composants système standard — le Liquid Glass y est natif sur iOS 26, zéro code.
- Contrôles flottants de la carte (filtres, recentrage, contribution) : grappe de boutons `.glassEffect(.regular.interactive())` dans un `GlassEffectContainer` — le morphing natif (via `glassEffectID`) anime l'ouverture du panneau de filtres depuis le bouton.
- Fiche POI : sheet en `.glassEffect(.regular, in: .rect(cornerRadius:))`, teinte magenta/cyan très légère uniquement pour les états (sélectionné, communautaire).
- Règles : `.interactive()` seulement sur l'interactif ; jamais de fond opaque derrière un verre ; pas de verre sur verre ; contraste AA vérifié sur les artworks les plus chargés (si le fond est trop actif sous un texte, on assombrit la teinte du verre, pas le texte).

**Design system d'abord** : `Core/DesignSystem` (tokens sémantiques, styles de glow, extensions de teintes glass, fiche POI, boutons, anneau de progression) construit avant les features.

**Pipeline d'images générées** : illustrations d'ambiance, en-têtes de catégories, onboarding, icône (palmier/soleil néon, unicité vérifiée). La carte n'est pas générée d'un bloc : **layout vectoriel schématique** (routes, quartiers, littoral d'après la géographie factuelle du jeu) habillé de textures générées. Aucun prompt ne cite GTA/Rockstar/personnages ; prompts et sources archivés.

## 7. Acquisition des données & opérations

### D'où viennent les données

**Avant la sortie** (dès maintenant) :
- **Sources officielles publiques** : Rockstar Newswire, site officiel GTA VI, posts sociaux officiels → personnages, lieux, activités annoncés, en faits reformulés.
- **Presse et communauté** : previews presse, r/GTA6, et les projets communautaires de reconstitution de la carte depuis les trailers — utilisés comme **référence factuelle** pour dessiner notre layout vectoriel ; on ne copie jamais leur artwork (leur dessin leur appartient, la géographie non).
- **Préparation structurelle** : le schéma de contenu (catégories de POI, format guide, format cheat) est défini et testé avant la sortie avec des données factices — au jour J on ne remplit que des cases déjà prêtes.

**À partir du jour J** :
- **Jeu en main (source primaire)** : sessions de jeu dédiées à la collecte. Outil clé : un **mode éditeur intégré à l'app** (builds debug/TestFlight interne uniquement) — console d'un côté, iPhone de l'autre : appui long sur la carte → formulaire de saisie (catégorie, titre, note) → écriture directe en Firestore. Le placement se fait par repères visuels (landmarks) sur notre carte schématique. C'est le chemin le plus rapide entre « je découvre un spot en jeu » et « il est publié ».
- **Veille communautaire (exhaustivité)** : wikis (GTA Wiki/Fandom), Reddit, guides YouTube, sites spécialisés — veille quotidienne semi-manuelle pendant le premier mois. Les faits sont repris, la rédaction est toujours originale ; l'IA sert à reformuler et structurer en masse.
- **Cheat codes** : découverts et publiés par la communauté dans les premiers jours ; des séquences de touches sont des faits, librement réutilisables.
- **Contributions utilisateurs** : appoint une fois la base amorcée — jamais le plan A du démarrage.

**Interdits** : datamining/extraction des fichiers du jeu, scraping automatisé massif d'un site tiers (veille manuelle/semi-manuelle uniquement), copier-coller de textes de wikis ou de guides.

### Registre des sources (audit 20 juillet 2026, révisé 29 juillet 2026)

Principe : un **fait** (emplacement, séquence de cheat, nom, stat) est libre ; une **rédaction, un artwork, une base structurée** ne le sont pas. Une seule source est réutilisable directement ; tout le reste est référence factuelle à recouper (≥ 2 sources) puis réécrire.

**Révision du 29 juillet 2026** — robots.txt relus domaine par domaine avant d'automatiser la veille. Trois sources en sont sorties : `rockstargames.com` (nous exclut nommément), r/GTA6 (exclut tout le monde, et son API est non commerciale), GTACodes.io (hors service). Cette table décrit l'intention ; l'autorité opérationnelle est `tools/content-cli/source-policy.mjs`, qui l'applique et lève sur un domaine interdit — une règle qu'un agent doit se rappeler a déjà été enfreinte une fois. Détail dans `docs/ops/2026-07-29-fil-actu-et-veille-automatique.md`.

| Source | Donnée | Licence / statut | Usage |
|---|---|---|---|
| **OpenStreetMap** (extrait Floride, Geofabrik) | Littoral, routes, plans d'eau réels | ODbL 1.0 — attribution « © OpenStreetMap contributors » obligatoire ; share-alike sur la base dérivée, pas sur le rendu illustré | ✅ **Seule réutilisation directe** : trame du layout vectoriel du fond de carte |
| Trailers, site officiel, Rockstar Newswire | Lieux, personnages, activités, annonces | Assets protégés Rockstar ; **robots.txt de `rockstargames.com` : `ClaudeBot Disallow: /`** (relevé 29 juillet 2026) | ⚠️ Observation **humaine** → faits reformulés, jamais l'asset. ❌ **Interdit à la veille automatique** : elle tourne sous un agent Claude. Les annonces nous parviennent relayées par la presse spécialisée |
| Jeu en main (dès le 19 nov.) | POI, collectibles, cheats vérifiés | — | ✅ Source primaire n°1, via le mode éditeur intégré |
| GTA Wiki Fandom (`gta.fandom.com`) | Personnages, véhicules, armes, radio | CC BY-SA (texte) | ✅ Exhaustivité factuelle ; rédaction refaite systématiquement |
| Cartes communautaires (State of Leonida, gta6map.*, gtamaps.io) | Landmarks localisés | Artwork + base = propriété des auteurs ; robots.txt de SoL : `ai-train=no`, bots IA bannis | ⚠️ Référence factuelle uniquement — jamais leur artwork, leurs tuiles ni leur base de markers |
| Repos GitHub de cartes (`gta6map/gta6map.github.io`, etc.) | Landmarks, reconstitution 3D | **`license: null` = tous droits réservés** — « open sur GitHub » ≠ réutilisable | ⚠️ Référence factuelle uniquement |
| Sites cheats (GTABOOM, Leonidaverse, GTA6.gg) | Cheat codes post-lancement (aucun code réel avant) | Séquences = faits libres ; rédaction protégée. robots.txt vérifiés le 29 juillet 2026 : les trois nous autorisent, Leonidaverse nomme même `ClaudeBot` en `Allow` | ✅ Agrégation recoupée, libellés réécrits. Flux d'abord (`feed.xml`, `news-sitemap.xml`) plutôt que parcours de pages |
| ~~GTACodes.io~~ | — | Redirige vers `gtacheatcodes.net`, **certificat TLS cassé** (29 juillet 2026) | ❌ Source hors service |
| OpenXBL (`xbl.io`) | Succès Xbox : listes, progression, rareté | API non officielle, free tier 150 req/h, OAuth Microsoft | ✅ v1.2 auto-cochage Xbox (consentement explicite) |
| IGDB (API Twitch) | Métadonnées jeu (dates, éditions) | Gratuit **non-commercial** uniquement — or l'app est ad-funded | ❌ **Écarté en prod** ; outil interne de préparation au plus |
| Endpoints PSN non officiels | Trophées PSN | Violation ToS Sony, risque Apple 5.2.2 | ❌ Écarté (décision §« Trophées ») |
| YouTube, GTAForums, presse spécialisée | Veille, découvertes | Textes protégés ; ToS des plateformes | ✅ Veille semi-manuelle, faits recoupés puis réécrits |
| ~~r/GTA6~~ | Veille communautaire | robots.txt : `User-agent: * Disallow: /`. API Data : gratuite **non commerciale** et sur pré-approbation manuelle depuis nov. 2025 — or l'app est ad-funded ; tier commercial ~12 k$/mois. Endpoints non authentifiés en 403 depuis mai 2026 | ❌ **Écarté** (décision 29 juillet 2026). Même raisonnement qu'IGDB : gratuit mais non commercial. Ses faits seraient de confiance `rumor`, que le pipeline refuse de publier |

### Tuyauterie de publication

- Le contenu vit dans un **repo git `content/`** : JSON (POI, cheats) + Markdown (guides), versionné et relisible.
- Un **script CLI d'admin** valide le schéma, **génère les traductions manquantes par IA (EN/ES/IT/DE)**, pousse vers Firestore et incrémente `contentVersion` dans Remote Config ; l'app ne relit que le delta. Pas de back-office en v1.
- Objectif du sprint jour J : carte schématique + premiers POI utilisables en 72 h, enrichissement continu ensuite.

### Anti-spam & anti-abus

Défense en couches sur les soumissions et votes :

1. **App Check (App Attest)** : toute requête doit prouver qu'elle vient du binaire signé sur un vrai appareil — élimine scripts et bots hors app.
2. **Chemin d'écriture unique** : Cloud Functions callable avec validation serveur — schéma, longueurs, filtre de vocabulaire, **déduplication géographique** (rejet si un spot approuvé de même catégorie existe à proximité).
3. **Cooldown court** entre deux soumissions (ordre de la minute) — pas de plafond journalier ni de limite de contributions en attente : un contributeur légitime prolifique n'est jamais bridé, c'est la ressource la plus précieuse au pic de sortie.
4. **Votes uniques par construction** : ID de document `{spotId}_{uid}` — revoter réécrit le même document. Compteurs agrégés côté serveur uniquement.
5. **Monitoring de vélocité au lieu de caps** : un burst anormal (volume, régularité machinale, doublons proches) marque les soumissions pour revue prioritaire et peut déclencher un **shadow-ban** — jamais un blocage automatique d'utilisateur légitime. L'identité Sign in with Apple rend les bans définitifs : réinstaller ne crée pas une nouvelle identité.
6. **Filets** : rien de public avant modération, kill-switch Remote Config, alertes de budget Firebase.

### Modération

Notification par contribution `pending`, traitement < 24 h, votes communautaires comme pré-filtre, kill-switch Remote Config si débordement.

## 8. Planning

| Période | Livrable |
|---|---|
| Fin juillet → août | Scaffolding, design system, moteur de carte (viewer + POI, carte placeholder), modèles de contenu + cache |
| Septembre | Guides/cheats, progression, sync Firestore + Remote Config, script d'admin (traductions IA incluses), mode éditeur interne |
| Octobre | Communautaire, pub (AdMob + ATT/UMP), UI traduite en 5 langues + fiches App Store localisées, polish + QA des layouts iPad, bêta TestFlight, **soumission App Store fin octobre** |
| Novembre | Release visée ~15 nov, sprint contenu à partir du 19 |

La soumission fin octobre est la marge de sécurité pour encaisser un rejet et resoumettre. Si Rockstar redécale la sortie, seul le sprint contenu glisse.

## 9. Tests

Niveau retenu : **pragmatique ciblé** (Swift Testing). Unitaires sur la logique critique : sync/versionnement du contenu, modèle de progression (source de vérité unique), conversion de coordonnées du viewer, plafonnement des interstitiels. Un test UI de fumée sur la navigation. Firebase mocké via les protocoles de `Core/`. Filet réel : bêta TestFlight d'octobre.

## 10. Risques

| Risque | Parade |
|---|---|
| Rejet Apple 5.2.1 (PI) | Zéro marque dans nom/icône/bundle, art original, disclaimer, soumission fin octobre. **Si refus persistant** : resoumission ajustée puis appel au Review Board ; en dernier recours, bascule **PWA** (carte + guides fonctionnent en web, pub AdSense) — peu coûteuse grâce au backend Firebase |
| Courrier Take-Two | App factuelle sans assets ; conformité immédiate si contact, retrait de contenu en minutes via Remote Config |
| Carte réelle inconnue avant sortie | Coordonnées découplées de l'artwork : carte schématique v0 au jour J, raffinée ensuite |
| Modération débordée (solo) | Texte court uniquement, votes en pré-filtre, kill-switch |
| Revenus dépendants de l'ATT | Pubs contextuelles sans IDFA ; le volume du pic de sortie est le moteur principal |

## 11. Hors périmètre v1 (explicitement)

Fil social complet, upload de photos/screenshots, Mac, Android/web (sauf plan B), mode clair, Live Activity, Apple Watch, auto-cochage Xbox (v1.2), trophées PSN (écarté sauf API officielle).

## 12. Marketing & marque

**Naming.** Contrainte structurante : le nom ne peut porter aucune marque Rockstar, donc la découvrabilité ne viendra pas du nom. Process : shortlist (« Neon Compass » en tête, alternatives à générer sur les critères Miami/néon/boussole-guide), vérification systématique EUIPO/USPTO + recherche App Store avant de trancher, et dépôt du nom retenu si le budget le permet. Champ mots-clés App Store : uniquement des termes factuels (« carte, guide, cheats, companion ») — y glisser « GTA » est une pratique répandue mais c'est un motif de rejet documenté ; on s'en abstient pour la review de lancement, réévaluation ensuite.

**Identité marketing.** L'icône (palmier/soleil néon) est l'actif n°1 — testée en A/B sur les fiches produit si possible. Screenshots App Store : mockups synthwave montrant carte → cheats plein écran → progression, textes courts dans les 5 langues. Vidéo preview 30 s centrée sur le geste signature (appui long → contribution). Ton de voix : années 80, second degré, jamais le vocabulaire maison de Rockstar.

**Acquisition.** Dans l'ordre de rendement attendu : (1) **pré-commande App Store** ouverte 2-3 semaines avant la sortie — elle cumule l'intention pendant le pic de hype et convertit le jour J ; (2) **créateurs de contenu** : accès TestFlight anticipé à des youtubeurs/streamers GTA francophones et anglophones — une vidéo « la meilleure app compagnon » vaut tout le reste ; (3) **présence authentique** sur r/GTA6 et TikTok (format « spot du jour » : 15 s de carte + découverte) ; (4) **site vitrine one-page** (SEO « carte interactive GTA VI », capture d'e-mails « préviens-moi », fondation du plan B PWA) ; (5) communiqué presse spécialisée à la sortie. Aucun budget pub payant en v1 — le pic organique est l'opportunité, l'ASO et les créateurs sont les multiplicateurs.

## 13. Stratégie de revenus & projections

**Sources v1** : (1) AdMob — bannières, interstitiels plafonnés, natives dans le feed ; (2) Pro one-shot 5,99 € (commission Apple 15 % via Small Business Program, net ≈ 5,09 €). **Sources futures** (v1.1+) : packs cosmétiques additionnels (thèmes/icônes), version web financée par la pub (si plan B activé ou en complément), tip jar. **Écartés** : abonnement (churn post-pic rédhibitoire), affiliation/sponsoring (dilue la confiance), vente de données (jamais).

**Projections à 3 mois post-sortie** — hypothèses transparentes, variance énorme assumée (tout dépend du classement ASO et d'un éventuel relais créateur) :

| Scénario | Installs cumulés | DAU moyen | Pub (ARPDAU 0,015-0,025 €) | Conversion Pro (1,5-2,5 %) | Total ~3 mois |
|---|---|---|---|---|---|
| Pessimiste | 50 k | 4 k | ≈ 5 k€ | ≈ 4 k€ | **≈ 9 k€** |
| Médian | 250 k | 20 k | ≈ 36 k€ | ≈ 25 k€ | **≈ 60 k€** |
| Optimiste | 1 M | 80 k | ≈ 180 k€ | ≈ 127 k€ | **≈ 300 k€** |

Lecture honnête : le pic de revenus dure 6-10 semaines puis décroît fortement ; la longue traîne dépendra du mode online de GTA VI et du rythme de nos mises à jour. À anticiper côté admin : statut (micro-entreprise vs société — au scénario médian, le plafond micro-BNC est dépassé), TVA sur services électroniques, inscription au Small Business Program avant la sortie.

## 14. Données, tracking, sécurité & RGPD

**Principe : minimisation.** Inventaire exhaustif des données :

| Donnée | Où | Base légale | Rétention |
|---|---|---|---|
| Progression de jeu | Appareil (SwiftData) ; Firestore si Pro sync | Contrat | Locale ; effacée avec le compte |
| Compte (Apple user ID, e-mail relay optionnel, handle auto-généré) | Firestore | Contrat | Jusqu'à suppression du compte |
| Contributions, votes, XP | Firestore | Contrat | Jusqu'à suppression (voir ci-dessous) |
| Analytics produit (événements agrégés, sans IDFA) | Firebase Analytics | Intérêt légitime | 14 mois |
| Pub personnalisée (IDFA) | AdMob | **Consentement** (ATT + UMP) | Géré par Google |
| Crash & performance | Crashlytics | Intérêt légitime | 90 jours |

**Droits & suppression.** Suppression de compte in-app (Cloud Function en cascade) : profil et votes effacés ; les contributions approuvées sont **anonymisées** (« auteur supprimé ») plutôt qu'effacées — l'anonymisation irréversible sort la donnée du champ RGPD tout en préservant la carte communautaire. Politique de confidentialité dans les 5 langues ; App Privacy labels App Store déclarés en conséquence ; registre de traitement simple tenu dans le repo (`docs/privacy/`). Pas de DPO requis à cette échelle.

**Tracing & observabilité.** Crashlytics + Firebase Performance côté client ; logs structurés des Cloud Functions (request ID, jamais de PII dans les logs), rétention 30 jours ; alertes sur taux d'erreur des Functions et taux de crash. Export BigQuery : plus tard, seulement si un besoin analytique le justifie.

**Sécurité.** Deny-by-default sur toutes les Security Rules ; App Check exigé sur Firestore, Functions et Hosting ; tokens en Keychain uniquement ; secrets du CLI admin dans le trousseau macOS, jamais dans le repo ; comptes de service au moindre privilège ; chiffrement at-rest et TLS gérés par Firebase ; revue des dépendances SPM à chaque ajout (politique : Google/Apple uniquement en v1).

## 15. Infrastructure & flux

**Composants** : Firestore (multi-région **eur3** — posture RGPD et proximité du cœur d'audience UE), Cloud Functions (europe-west1), Remote Config, App Check, FCM, Firebase Hosting comme CDN d'assets, App Store Server Notifications V2 → Function (miroir premium).

**Flux principaux** :
- Lecture : client → App Check → Firestore (contenu + communauté `approved`) ; tuiles de carte et images → Hosting/CDN (fichiers à nom hashé, cache long).
- Écriture : client → Functions callable (`submitContribution`, `castVote`, `deleteAccount`) → Firestore. Aucune écriture directe.
- Publication : repo git `content/` → CLI admin (validation, traductions IA) → Firestore + bump `contentVersion` (Remote Config).
- Premium : App Store → Server Notification → Function → champ `isPremium` du profil.

**Dimensionnement & coûts.** Profil read-heavy avec un poste dominant : l'egress des tuiles de carte. Mitigation structurante : **le jeu de tuiles de base est embarqué dans le binaire** (pas de téléchargement initial), le CDN ne sert que les mises à jour d'artwork. Lectures Firestore maîtrisées par la sync delta (`contentVersion`) — un client à jour ne lit quasi rien. Au scénario médian (20 k DAU), coût Firebase estimé < 100 €/mois ; alerte de budget à 50 €, plafonds configurés — une attaque ou un bug de boucle ne peut pas générer une facture surprise.

**Environnements & sauvegardes.** Deux projets Firebase (`dev`, `prod`), `GoogleService-Info` par environnement via xcconfig. Le contenu éditorial est reconstructible depuis le repo git (source de vérité) ; la seule donnée irremplaçable est communautaire (profils, contributions) → **export Firestore hebdomadaire** vers Cloud Storage + PITR activé. CI : Xcode Cloud plus tard, build locale + TestFlight en v1.

## 16. Dossier de review App Store

Objectif unique : **éviter le rejet** — chaque élément ci-dessous ferme un motif de rejet documenté.

**Guidelines critiques et réponses** :

| Guideline | Risque | Notre réponse |
|---|---|---|
| 5.2.1/5.2.2 (PI) | Le mur principal pour une app fan | Zéro asset Rockstar, nom/icône/screenshots originaux, usage nominatif limité à la description, disclaimer, archive des prompts comme preuve d'originalité |
| 4.1 (Copycats) | Confusion avec la marque | DA genre synthwave, jamais le style signature Rockstar (pas de Pricedown) |
| 1.2 (UGC) | Checklist mécanique du reviewer | Pré-modération + signalement + **blocage utilisateur** (masquer les spots d'un contributeur, liste locale) + CGU avant première contribution. Dossier renforcé par : pas de messagerie, pas de pseudo libre (handles auto-générés), texte pré-modéré uniquement |
| 5.1.1(v) | Compte sans suppression | Suppression in-app en cascade |
| 5.1.1 | Compte exigé abusivement | Consultation intégralement sans compte |
| 5.1.2/ATT | Labels privacy inexacts avec AdMob | Labels alignés sur les SDK réels, prompt ATT + UMP |
| 3.1.1 (IAP) | Achat hors StoreKit, restauration absente | StoreKit 2 uniquement, bouton « Restaurer les achats » visible |
| 2.1/4.2 | App « vide » soumise avant la sortie du jeu | Chaque onglet fonctionnel avec le contenu pré-sortie — jamais d'écran « coming soon » |
| DSA (UE) | Statut de commerçant non déclaré | Déclaré dans App Store Connect avant soumission |

**Notes au reviewer** (rédigées avec le binaire) : caractère non officiel et disclaimer, absence totale d'assets Rockstar (artwork 100 % original, preuve disponible), nature factuelle du contenu, fonctionnement de la pré-modération, où trouver blocage/signalement/suppression de compte. Un reviewer qui comprend en 30 secondes ne sur-escalade pas.

**Checklist de soumission (fin octobre)** : classement 17+ honnête · labels App Privacy vérifiés contre les SDK · statut commerçant DSA · politique de confidentialité et CGU en ligne (5 langues) · bouton restaurer les achats · suppression de compte testée · signalement + blocage testés · aucun « GTA » hors description · pré-commande demandée tôt · notes au reviewer jointes. En cas de rejet : corriger et resoumettre d'abord ; **appel au Review Board** si le rejet est infondé ; un rejet métadonnées se corrige sans re-review du binaire.
