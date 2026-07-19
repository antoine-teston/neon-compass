# Neon Compass — App compagnon non officielle pour GTA VI

**Date** : 2026-07-19 · **Statut** : validé en brainstorming, en attente de relecture finale

## 1. Vision produit

App iOS compagnon pour la sortie de GTA VI (19 novembre 2026), publiée sur l'App Store, gratuite et financée par la publicité. Quatre piliers au lancement : carte interactive stylisée, guide cheats & astuces, suivi de progression, contributions communautaires sur la carte. Le modèle publicitaire impose une app à usage quotidien pendant les semaines post-sortie : la rétention (progression, contenu frais) est un objectif produit de premier rang, pas un bonus.

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
- **UGC (Apple 1.2)** : signalement de contenu, blocage d'utilisateur, modération réactive, conditions d'utilisation.
- **RGPD minimal by design** : auth anonyme, progression stockée en local uniquement, aucune donnée personnelle collectée hors identifiant anonyme et consentements pub.

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
- Contributions : Firestore `contributions` avec statut `pending` → modération → `approved` → visibles. Auth anonyme, aucun compte requis.
- Firebase est isolé derrière des protocoles dans `Core/` : les features sont testables sans I/O.

**Moteur de carte** (pièce technique principale) : illustration originale découpée en tuiles de zoom, rendue dans un viewer zoom/pan custom (SwiftUI wrappant `CATiledLayer`). POI positionnés en **coordonnées normalisées (0-1), indépendantes de l'artwork** — on peut remplacer le dessin sans toucher aux données.

**Remote Config pilote** : version du contenu, fréquence des pubs, kill-switch de la feature communautaire.

## 5. Features

**Carte** (onglet principal). Zoom/pan, filtres par catégorie (collectibles, activités, planques, véhicules rares, événements), recherche. Fiche POI : description, astuce, bouton « Trouvé » alimentant la progression. Contribution : appui long → proposer un spot (catégorie, titre, note ≤ 280 caractères, position) ; spots approuvés badgés communauté, votes ▲▼, signalement. Les spots très votés sont promouvables en contenu éditorial.

**Guides & cheats.** Cheat codes avec recherche et filtre plateforme (PS5/Xbox), séquences en glyphes manette. Guides Markdown rendus nativement, chapitres : histoire, side content, débutant, argent. Lisible hors-ligne après cache.

**Progression.** Checklists auto-générées depuis le contenu, pourcentages global et par catégorie, anneau de progression néon. Même enregistrement SwiftData que le « Trouvé » de la carte.

**Publicité.** Bannière adaptative en bas des écrans de liste — jamais sur la carte en interaction. Interstitiel plafonné (max 1/session, jamais pendant une contribution), fréquence via Remote Config.

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

### Tuyauterie de publication

- Le contenu vit dans un **repo git `content/`** : JSON (POI, cheats) + Markdown (guides), versionné et relisible.
- Un **script CLI d'admin** valide le schéma, **génère les traductions manquantes par IA (EN/ES/IT/DE)**, pousse vers Firestore et incrémente `contentVersion` dans Remote Config ; l'app ne relit que le delta. Pas de back-office en v1.
- Objectif du sprint jour J : carte schématique + premiers POI utilisables en 72 h, enrichissement continu ensuite.

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

Fil social complet, upload de photos/screenshots, Mac, Android/web (sauf plan B), comptes utilisateurs nommés, synchronisation cloud de la progression, mode clair.
