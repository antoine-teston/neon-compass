# Pipeline de données — ébauche d'implémentation (pseudocode)

> Ébauche du 20 juillet 2026. Couvre les 4 briques du flux de données du spec (§7) :
> fond de carte, repo de contenu, CLI d'admin, sync app. Pseudocode — pas de code
> définitif ; les noms de types sont indicatifs. Le registre des sources et leurs
> licences vivent dans le spec (§7, « Registre des sources »).

## Vue d'ensemble

```
[OSM Floride (ODbL)]──┐
[Références factuelles]─┤→ (A) Basemap pipeline → tuiles PNG z0..z5 → bundle app
                        │
[Rédaction humaine + IA]→ (B) content/ (git) → (C) CLI admin → Firestore
                                                     │              │
                                              Remote Config     (D) Sync app
                                              contentVersion → SwiftData cache
```

Deux chemins indépendants : la **carte** (artwork + tuiles, embarquée dans le binaire,
mise à jour par release App Store) et le **contenu** (POI/cheats/guides, poussé par
Firestore, mis à jour sans release).

---

## (A) Basemap pipeline — `tools/basemap/`

L'OSM n'est PAS transformé automatiquement en carte : c'est un **calque de référence**
sous un dessin vectoriel manuel (le monde du jeu est une Floride fictive — seule la
trame géographique générale est reprise). La partie automatisée est en aval :
rendu + découpage en tuiles.

```
# A1. Préparer le calque de référence (une fois)
osm = download("geofabrik.de/.../florida-latest.osm.pbf")        # ODbL
ref = filter(osm, keep=[coastline, water, primary_roads])
ref_svg = simplify(ref, tolerance=high) |> project(bbox → unit_square)
save("reference/florida-underlay.svg")                            # jamais shippé
# ATTRIBUTION.md : « © OpenStreetMap contributors » + lien ODbL   # obligation licence

# A2. Dessin manuel (humain, éditeur vectoriel)
# leonida.svg : littoral/routes/quartiers dessinés par-dessus l'underlay,
# recalés sur les références factuelles (trailers, cartes communautaires
# en OBSERVATION seule). Coordonnées normalisées 0-1. Sources archivées (spec §6).

# A3. Rendu stylisé + tuiles (automatisé, relançable à chaque version d'artwork)
for zoom in 0...maxZoom:                                          # maxZoom ≈ 5
    img = render(leonida.svg, size=256 * 2^zoom, style=synthwave)
    for (x, y) in grid(2^zoom):
        write(crop(img, x, y, 256), "Tiles/\(zoom)/\(x)/\(y).png")
emit_manifest(bounds, maxZoom, checksum)                          # lu par le viewer
```

Invariant clé (spec §4) : les POI sont en coordonnées normalisées **indépendantes de
l'artwork** — regénérer les tuiles ne touche jamais aux données.

## (B) Repo de contenu — `content/`

```
content/
  poi/*.json          # 1 fichier = 1 POI
  cheats/*.json
  guides/*.md         # frontmatter YAML + corps Markdown par langue
  schema/*.schema.json
```

```jsonc
// poi/vice-beach-lighthouse.json — champs localisés avec fallback EN (spec §3)
{
  "id": "poi_lighthouse_001",          // stable, jamais réutilisé
  "category": "landmark",              // enum fermé (schema)
  "position": { "x": 0.7312, "y": 0.4147 },   // normalisé 0-1
  "title":  { "en": "…", "fr": "…" },  // ES/IT/DE générés par le CLI si absents
  "note":   { "en": "…" },
  "sources": ["trailer2@01:23", "gta.fandom.com/wiki/…"],  // interne, jamais shippé
  "status": "draft" | "published"
}
```

```jsonc
// cheats/*.json — format du spec §3 (toggle PS5/Xbox, flag trophées)
{
  "id": "cheat_invincibility",
  "effect":   { "en": "…" },           // libellé réécrit, jamais copié
  "sequence": { "ps5": ["circle","l1","…"], "xbox": ["b","lb","…"] },
  "blocksTrophies": true,
  "verifiedBy": ["gtaboom", "leonidaverse"],   // ≥ 2 sources avant published
  "status": "draft"
}
```

## (C) CLI d'admin — `tools/content-cli/` (`push.js` ou Swift CLI)

```
cmd publish(dry_run=false):
    files = glob("content/**")
    for f in files: validate(f, schema)               # échec = stop, rien ne part
    for f in files:
        for lang in [es, it, de] where f.title[lang] is missing:
            f.title[lang] = ai_translate(f.title.en → lang)   # relecture par sondage
    diff = compare(files, firestore.snapshot())        # add / update / remove
    if dry_run: print(diff); return
    firestore.batch_write(diff)                        # que le delta
    remote_config.increment("contentVersion")          # déclenche la sync app
    git.tag("content-v\(version)")                     # traçabilité

cmd verify_cheat(id):                                  # garde-fou éditorial
    require(len(entry.verifiedBy) >= 2, "recoupement ≥ 2 sources requis")
```

## (D) Sync côté app — `Core/Content/` (Swift, derrière protocole)

```swift
protocol ContentSyncing {                    // Firebase jamais importé en Features/
    func syncIfNeeded() async throws
}

actor ContentSyncService: ContentSyncing {
    func syncIfNeeded() async throws {
        let remote = remoteConfig.contentVersion
        let local  = store.contentVersion            // SwiftData
        guard remote > local else { return }         // rien à faire, 0 lecture réseau

        let changes = try await firestore.fetch(since: local)   // delta seulement
        try store.transaction {                       // upsert atomique
            changes.upserts.forEach(store.upsert)
            changes.deletes.forEach(store.tombstone)  // soft-delete: la progression
            store.contentVersion = remote             // liée à un POI supprimé survit
        }
    }
}
// Déclenchement : app launch + retour foreground, jamais bloquant pour l'UI.
// Hors-ligne : l'app sert le cache SwiftData, pleinement utilisable (spec §3).
```

## Ordre de construction (s'insère dans la roadmap §8)

1. **Août** — (B) schémas + données factices ; (A) A3 avec un SVG placeholder ; (D) sync.
2. **Septembre** — (C) CLI complet (traductions IA incluses) ; A1-A2 en parallèle (artwork).
3. **Jour J** — le mode éditeur écrit dans Firestore via le même chemin validé que le CLI.

## Hors périmètre (rappel des interdits, spec §7)

Pas de scraper de sites tiers dans ce pipeline. `tools/map-inspector/` (Playwright)
reste un outil d'**audit ponctuel** (vérifier l'origine/licence d'une source), pas un
collecteur. La collecte est humaine ; l'IA reformule et traduit, elle ne copie pas.
