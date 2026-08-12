# Provenance des fonds de carte

Ce fichier existe pour la même raison que l'archivage des prompts d'images
génératives demandé par `CLAUDE.md` : pouvoir dire, des mois plus tard et sans
relire le code, d'où vient chaque pixel embarqué dans l'app et ce que nous en
avons fait. Il décrit l'état réel, y compris ce qui n'est pas réglé.

## `island.png` / `island-classic.png` — carte de référence (GTA V)

- Source : tuiles slippy `s3-eu-west-1.amazonaws.com/gtavmap/tiles`, style
  `atlas`, z6 (576 tuiles, 6 144 px). Générateur : `gtav-map.mjs`.
- `island.png` est restylée (`gtav-restyle.mjs`) : classification par pixel puis
  remplacement complet par la palette Neon Compass.
- `island-classic.png` est la carte source, recadrée et redimensionnée. Les
  couleurs sont celles de l'auteur d'origine.

## `island-vi.png` / `island-vi-classic.png` — carte de Leonida (GTA VI)

- Source : tuiles slippy `map.stateofleonida.net/tiles/YANIS/v14/normal`, z5
  (1 600 tuiles, 10 240 px). Carte communautaire de fans, dite « YANIS », dont
  la v14 est la version utilisée ici. Générateur : `gtavi-map.mjs --restyle
  --classic`.
- `island-vi.png` est restylée (`gtavi-restyle.mjs`) : classification par pixel,
  palette Neon Compass, effacement de la grille et des lignes de comté,
  uniformisation des libellés, recadrage. Aucun pixel source ne subsiste tel
  quel.
- `island-vi-classic.png` est la carte source : panneau de légende effacé,
  recadrée, redimensionnée à 8 192 px. **Les couleurs et le dessin sont ceux de
  l'auteur d'origine.**

## `island-vi-reduced.png` / `island-vi-classic-reduced.png` — étage réduit

- Dérivés des deux fichiers ci-dessus, réduits à 4 096 px par
  `reduce-mapart.mjs`. Aucune source nouvelle : un seul saut de provenance
  depuis un fichier déjà décrit ici, et la même situation IP que son parent.
- Existent pour la mémoire, pas pour l'image : l'app décode celui-ci au repos et
  le natif seulement au zoom (`MapArtDetail`). À régénérer après toute
  régénération du parent — `MapArtResourcesTests` le rappelle en échouant.
- La carte de référence n'en a pas : ses 4 096 px SONT déjà l'étage réduit.

## Ce qui reste à trancher

Les deux fichiers `*-classic.png` ne sont **pas** un travail transformatif de
notre part : ce sont des cartes de fans tierces, recadrées. `CLAUDE.md` exige
que tout contenu soit original ou clairement transformatif, et aucune
attribution n'accompagne ces images dans l'app.

Trois issues, à choisir explicitement plutôt que par défaut :

1. **Attribuer** — créditer les auteurs dans un écran « Crédits » et vérifier la
   licence de chaque source (celle de YANIS n'a pas été retrouvée).
2. **Ne plus embarquer que le restylage** — les deux `*-classic.png` sortent du
   binaire ; l'habillage « classic » disparaît, ainsi que le bouton qui bascule.
3. **Redessiner** un fond classic à partir de nos propres primitives.

Tant que rien n'est tranché, ces deux fichiers sont le risque IP le plus concret
du dépôt, et ils étaient déjà présents pour la V avant la carte VI.
