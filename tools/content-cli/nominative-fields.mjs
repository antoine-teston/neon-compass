// Les champs qui ne portent qu'un NOM, et ce qu'on exige d'eux en échange.
//
// Pourquoi ce fichier existe plutôt que deux listes recopiées : deux contrôles
// distincts s'appuient sur la même notion, et l'un ACCORDE une permission que
// l'autre justifie.
//
//  - `check-publishable` (cli.js) refuse les marques déposées dans les champs
//    d'interface. Il fait une exception pour les champs nominatifs : nommer le
//    produit d'un tiers pour en parler est l'usage référentiel, celui qui permet
//    à la presse spécialisée d'écrire « GTA Online ». La contrainte IP du projet
//    (CLAUDE.md) porte sur l'IDENTITÉ de l'app — nom, icône, sous-titre App
//    Store, bundle ID — pas sur le contenu éditorial.
//  - `check-originality` refuse les reprises littérales de la source. Un nom
//    propre y échappe forcément : « Fleeca Heist Finale » figure dans la prose
//    dont il est tiré, et le déformer pour le faire passer serait mentir.
//
// Les deux exceptions reposent sur le même pari, et il n'en vaut rien sans sa
// contrepartie : **ces champs doivent rester des noms.** C'est pour ça que
// `notANominativeName` vit ici et que `check-publishable` l'applique LUI-MÊME au
// moment d'accorder l'exception, au lieu de compter sur un autre script pour le
// faire. Sans ça, on pourrait glisser un slogan déposé dans un champ « nom » et
// les deux contrôles se renverraient la responsabilité.

/** Champs localisés dont la valeur entière est un nom propre, par kind. */
export const NOMINATIVE_FIELDS = {
  'online-events': ['podiumVehicle'],
};

/** Idem, portés par une liste : `[champ de liste, champ texte]`. */
export const NOMINATIVE_LIST_FIELDS = {
  'online-events': [
    ['bonuses', 'activity'],
    ['discounts', 'item'],
    ['rewards', 'item'],
  ],
};

/** Textes RÉDIGÉS portés par une liste — soumis à tous les contrôles, eux.
 *  `label` est composé par nous (weekly-hub.mjs) : rien ne justifie qu'il porte
 *  une marque, et il n'est pas un nom. */
export const REDACTED_LIST_FIELDS = {
  'online-events': [['bonuses', 'label']],
};

/** Au-delà, ce n'est plus un nom mais une phrase. Le plus long relevé sur une
 *  semaine réelle en fait cinq (« Galaxy Super Yacht and modifications ») ;
 *  huit laisse de la marge sans laisser passer une description. */
export const MAX_NAME_WORDS = 8;

/** Doit rester le miroir de `TRADEMARKS` (cli.js), qui reste l'autorité. */
const TRADEMARKS = /\b(GTA|Grand Theft Auto|Rockstar|Vice City|Leonida|Take-Two)\b/gi;

export function nominativeFieldsFor(kind) {
  return NOMINATIVE_FIELDS[kind] ?? [];
}

export function nominativeListFieldsFor(kind) {
  return NOMINATIVE_LIST_FIELDS[kind] ?? [];
}

export function redactedListFieldsFor(kind) {
  return REDACTED_LIST_FIELDS[kind] ?? [];
}

/**
 * Ce champ tient-il la promesse qui lui vaut ses deux exceptions ?
 *
 * @returns la description du problème, ou `null` si c'est bien un nom.
 */
export function notANominativeName(value) {
  if (typeof value !== 'string' || !value.trim()) return 'valeur vide';
  if (/[.!?;:]/.test(value)) return `PONCTUATION DE PHRASE : ${value}`;
  const words = value.trim().split(/\s+/).length;
  if (words > MAX_NAME_WORDS) return `${words} mots — un nom en fait au plus ${MAX_NAME_WORDS} : ${value}`;
  // Une marque NUE n'est pas un usage référentiel : « GTA » ne désigne aucun
  // produit en particulier, il ne fait que porter la marque. « Rockstar Editor »
  // désigne un outil, et c'est ça qu'on autorise. La distinction se vérifie en
  // retirant les marques : ce qui reste doit encore nommer quelque chose.
  const withoutMarks = value.replace(TRADEMARKS, ' ').replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
  if (!withoutMarks) return `MARQUE NUE : « ${value} » ne nomme rien d’autre que la marque elle-même`;
  return null;
}
