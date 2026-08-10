// Les titres de la carte de référence ne se traduisent pas : ils se COMPOSENT.
//
// ─────────────────────────────────────────────────────────────────────────────
// POURQUOI UNE TABLE PLUTÔT QU'UN MODÈLE
//
// Les 537 POI de la carte de référence sont massivement gabarités —
// `Gas Station` 157 fois, `Under the Bridge #N` 50 fois, `Nuclear Waste #N`
// 30 fois — et le suffixe est toujours un numéro et un nom de lieu, qui restent
// identiques dans les cinq langues.
//
// Confier ces 2454 champs à un modèle paierait cher une variabilité dont on ne
// veut pas : deux passes donneraient deux formulations de « Gas Station », et
// rien ne le rattraperait. Une table les rend déterministes ET relisibles.
//
// Ce n'est pas une exception dans ce dépôt, c'est le cas qui MARCHE : le seul
// item complet dans les cinq langues avant ce chantier était l'unique
// `online-event`, et il n'a jamais été traduit — `weekly-hub.mjs` compose ses
// libellés depuis un vocabulaire figé. Là où une machine assemble, les cinq
// langues sont là depuis le premier jour.
//
// ─────────────────────────────────────────────────────────────────────────────
// L'ORACLE, QUI EST CE QUI REND LA CHOSE SÛRE
//
// Une table peut décrire faussement la structure d'un titre, et écrire alors
// trois langues fausses sans que rien ne le voie. D'où la règle que
// `titresComposables` applique : le FRANÇAIS EXISTE DÉJÀ pour ces 537 items, il
// a été relu, et il sert de contrôle. Si la table ne sait pas reproduire le `fr`
// d'un item, elle n'a pas le droit d'écrire ses `es`/`it`/`de` — l'item part à
// la rédaction.
//
// Pur — aucune I/O.

/** Le marqueur de numéro par défaut, celui de la quasi-totalité des données. */
const MARQUEUR = '#';

/**
 * Les familles de titres, et leur préfixe dans les cinq langues.
 *
 * Le singulier ici et le pluriel dans `content/collections` désignent la même
 * chose — « Fragment de lettre #36 » appartient à la collection « Fragments de
 * lettre ». Les deux ont été écrits ensemble et doivent le rester.
 */
export const GABARITS = [
  { en: 'Letter Scrap', fr: 'Fragment de lettre', es: 'Fragmento de carta', it: 'Frammento di lettera', de: 'Brieffetzen' },
  { en: 'Spaceship Part', fr: 'Pièce de vaisseau', es: 'Pieza de nave', it: 'Parte di astronave', de: 'Raumschiffteil' },
  { en: 'Stunt Jump', fr: 'Saut cascade', es: 'Salto acrobático', it: 'Salto acrobatico', de: 'Stuntsprung' },
  { en: 'Under the Bridge', fr: 'Passage sous pont', es: 'Paso bajo puente', it: 'Passaggio sotto il ponte', de: 'Brückenunterquerung' },
  { en: 'Nuclear Waste', fr: 'Déchets nucléaires', es: 'Residuos nucleares', it: 'Scorie nucleari', de: 'Atommüll' },
  { en: 'Knife Flight', fr: 'Vol en rase-mottes', es: 'Vuelo rasante', it: 'Volo radente', de: 'Tiefflug' },
  // La seule famille dont le FR écrit « n° » là où toutes les autres écrivent
  // « # ». Irrégularité des données existantes : on la reproduit pour que
  // l'oracle valide, sans la propager aux langues neuves.
  { en: 'Hidden Package', fr: 'Magot caché', es: 'Paquete oculto', it: 'Pacco nascosto', de: 'Verstecktes Paket', marqueurFr: 'n°' },
  { en: 'Epsilon Tract', fr: 'Tract Epsilon', es: 'Panfleto Epsilon', it: 'Volantino Epsilon', de: 'Epsilon-Flugblatt' },
  { en: 'Gas Station', fr: 'Station-service', es: 'Gasolinera', it: 'Stazione di servizio', de: 'Tankstelle' },
];

/**
 * Le titre composé dans une langue, ou `null` si aucune famille ne le couvre.
 *
 * Tout ce qui suit le préfixe — numéro, tiret, nom de lieu — est recopié TEL
 * QUEL. Traduire « Grand Senora Desert » inventerait un lieu qui n'existe pas
 * dans le jeu, et le joueur ne le retrouverait pas sur sa carte.
 */
export function composer(titreEn, langue) {
  const gabarit = GABARITS.find((g) => titreEn === g.en || titreEn.startsWith(`${g.en} `));
  if (!gabarit) return null;

  let reste = titreEn.slice(gabarit.en.length);
  if (langue === 'fr' && gabarit.marqueurFr) {
    reste = reste.replace(MARQUEUR, gabarit.marqueurFr).replace(`${gabarit.marqueurFr} `, gabarit.marqueurFr);
  }
  return `${gabarit[langue]}${reste}`;
}

/**
 * Ce que la composition peut écrire, et ce qu'elle refuse.
 *
 * Deux façons d'être composable, et une seule d'être ignoré :
 *
 * - **nom propre** — `en` et `fr` sont identiques, donc le titre est un nom que
 *   personne ne traduit (« Pegassi Vacca », « Adder »). Il se recopie tel quel
 *   dans les trois langues, comme `GTA$` l'est déjà cinq fois dans le catalogue.
 * - **gabarit** — une famille le couvre ET la composition redonne exactement le
 *   `fr` existant. C'est l'oracle : une table qui déforme le français décrit mal
 *   la structure, donc elle n'écrira rien.
 * - **ignoré** — tout le reste, c'est-à-dire les titres descriptifs uniques
 *   (« Michaels mansion », « Meth lab »). Ils relèvent de la rédaction, pas
 *   d'une table, et `raison` le dit.
 */
export function titresComposables(entries, langues = ['es', 'it', 'de']) {
  const composables = [];
  const ignores = [];

  for (const { file, data } of entries) {
    const { en, fr } = data?.title ?? {};
    if (!en) continue;
    // Déjà fait : ne jamais réécrire ce qui existe, ici comme dans `--apply`.
    if (langues.every((l) => data.title[l])) continue;

    if (fr && en === fr) {
      composables.push({ file, en, raison: 'nom propre', langues: Object.fromEntries(langues.map((l) => [l, en])) });
      continue;
    }

    const versFr = composer(en, 'fr');
    if (versFr === null) {
      ignores.push({ file, en, raison: 'aucun gabarit — titre à rédiger' });
      continue;
    }
    if (versFr !== fr) {
      ignores.push({ file, en, raison: `le gabarit ne redonne pas le FR existant (${versFr} ≠ ${fr})` });
      continue;
    }

    composables.push({
      file,
      en,
      raison: 'gabarit',
      langues: Object.fromEntries(langues.map((l) => [l, composer(en, l)])),
    });
  }

  return { composables, ignores };
}
