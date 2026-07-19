# content/

Contenu éditorial versionné (spec §7) : POI, cheats, guides + inbox des agents.

- `inbox/` : faits bruts sourcés (data-scout) + rapports QA — jamais shippé
- `poi/ cheats/ guides/` : contenu au schéma, poussé vers Firestore par le CLI
- `schema/` : JSON Schemas (à écrire en août, cf. plan pipeline)

Chaîne : data-scout → content-editor → content-qa → review humaine → CLI publish.
