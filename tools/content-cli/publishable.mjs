// Les règles éditoriales qui décident si un item peut être publié.
//
// Extrait de `cli.js` le 2026-08-07. Le découpage n'est pas cosmétique : la
// console doit pouvoir demander « cet item PASSERAIT-IL s'il était publié ? »
// sans lancer de processus, et sans dupliquer une règle — une règle dupliquée
// finit par diverger, et c'est la copie oubliée qui décide.
//
// `problemsFor` est le cœur, pur et sans effet de bord. `checkPublishable` n'est
// que sa boucle de rapport pour la ligne de commande ; `cli.js` continue de
// l'appeler exactement comme avant.

import {
  notANominativeName,
  nominativeFieldsFor,
  nominativeListFieldsFor,
  redactedListFieldsFor,
} from './nominative-fields.mjs';

// Champs affichés dans l'UI : jamais de marque déposée (CLAUDE.md, spec §1).
export const TRADEMARKS = /\b(GTA|Grand Theft Auto|Rockstar|Vice City|Leonida|Take-Two)\b/i;
export const UI_FIELDS = ['title', 'note', 'effect', 'shortEffect', 'body'];

/** Les hôtes distincts cités par `sources[]`, `www.` replié. Une URL
 *  imparsable compte pour elle-même plutôt que de faire planter le contrôle :
 *  un item mal formé doit échouer sur SA règle, pas emporter la vérification. */
function distinctSourceHosts(sources) {
  return new Set(
    sources.map((url) => {
      try {
        return new URL(url).hostname.toLowerCase().replace(/^www\./, '');
      } catch {
        return url;
      }
    }),
  );
}

/**
 * Les raisons pour lesquelles cet item ne peut pas être publié. Tableau vide =
 * publiable.
 *
 * ATTENTION, et c'est le piège de tout le dispositif : la plupart de ces règles
 * ne mordent que sur `data.status === 'published'`. Un BROUILLON les passe donc
 * toutes trivialement. Pour savoir si un brouillon serait publiable, il faut
 * l'évaluer comme s'il l'était — c'est ce que fait `problemsIfPublished`.
 */
export function problemsFor({ kind, data }) {
  const problems = [];

  if (kind === 'cheats' && data.status === 'published' && (data.verifiedBy?.length ?? 0) < 2) {
    problems.push('published cheat requires verifiedBy >= 2 sources');
  }
  // Un squelette de `pull-news` porte encore son texte d'attente. Publier
  // « À rédiger » dans le fil est un accident que seule une machine peut
  // attraper de façon fiable — c'est exactement ce qui arriverait à un run
  // hebdomadaire dont l'étape de rédaction a échoué en silence.
  if ((kind === 'news' || kind === 'online-events') && data.status === 'published' && data.needsRewrite) {
    problems.push('published news item is still an unwritten skeleton (needsRewrite)');
  }
  // Une rumeur ne part pas dans le fil. L'app est un compagnon non officiel :
  // sa crédibilité tient à ne jamais présenter une spéculation de presse comme
  // une actualité. Une rumeur peut vivre en `draft` (elle garde sa trace et
  // son id), elle ne franchit pas la publication. Assouplir cette règle est
  // une décision éditoriale, pas un détail de pipeline.
  if ((kind === 'news' || kind === 'online-events') && data.status === 'published' && data.confidence === 'rumor') {
    problems.push('published entry cannot rest on a rumor (confidence: rumor)');
  }
  // La confiance se PROUVE. Jusqu'au 2026-08-15, `multi-source` était un
  // jugement du modèle que rien ne vérifiait : les neuf items du fil qui le
  // portaient citaient chacun UNE seule URL. Le mot n'a de valeur que si
  // `sources[]` porte la corroboration — au moins deux hôtes distincts, parce
  // que deux URL du même site sont la même voix (et `www.` ne fabrique pas un
  // deuxième hôte).
  if (
    (kind === 'news' || kind === 'online-events') &&
    data.status === 'published' &&
    data.confidence === 'multi-source' &&
    distinctSourceHosts(data.sources ?? []).size < 2
  ) {
    problems.push('published entry claims multi-source confidence but its sources do not span 2 distinct hosts');
  }
  for (const field of UI_FIELDS) {
    for (const [lang, text] of Object.entries(data[field] ?? {})) {
      const m = text.match(TRADEMARKS);
      if (m) problems.push(`trademark "${m[0]}" in ${field}.${lang}`);
    }
  }
  // Une carte affiche aussi des textes que `UI_FIELDS` ne voit pas — ceux que
  // portent les listes. Ils ne rejoignent pas `UI_FIELDS` pour autant : celui-ci
  // sert aussi à `translate`, qui réclamerait alors une traduction pour des
  // noms propres.
  //
  // Deux régimes, et la frontière est celle de l'usage référentiel :
  //
  //  - un texte RÉDIGÉ par nous (`bonuses[].label`) n'a aucune raison de porter
  //    une marque. Il est scanné comme `title`.
  //  - un champ NOMINATIF ne fait que nommer le produit d'un tiers pour en
  //    parler. C'est l'usage que la presse spécialisée fait tous les jours, et
  //    la contrainte IP du projet (CLAUDE.md) porte sur l'IDENTITÉ de l'app —
  //    nom, icône, sous-titre App Store, bundle ID — pas sur le contenu.
  //    L'exception n'est PAS gratuite : ces champs doivent prouver qu'ils sont
  //    bien des noms, et c'est vérifié ICI même. Déléguer cette vérification à
  //    `check-originality` aurait laissé les deux contrôles se renvoyer la
  //    responsabilité d'une permission qu'aucun des deux n'aurait justifiée.
  for (const [listField, textField] of redactedListFieldsFor(kind)) {
    (data[listField] ?? []).forEach((item, index) => {
      for (const [lang, text] of Object.entries(item?.[textField] ?? {})) {
        const m = text.match(TRADEMARKS);
        if (m) problems.push(`trademark "${m[0]}" in ${listField}[${index}].${textField}.${lang}`);
      }
    });
  }
  for (const field of nominativeFieldsFor(kind)) {
    for (const [lang, text] of Object.entries(data[field] ?? {})) {
      const problem = notANominativeName(text);
      if (problem) problems.push(`${field}.${lang} n'est pas un nom — ${problem}`);
    }
  }
  for (const [listField, textField] of nominativeListFieldsFor(kind)) {
    (data[listField] ?? []).forEach((item, index) => {
      for (const [lang, text] of Object.entries(item?.[textField] ?? {})) {
        const problem = notANominativeName(text);
        if (problem) problems.push(`${listField}[${index}].${textField}.${lang} n'est pas un nom — ${problem}`);
      }
    });
  }

  return problems;
}

/**
 * Ce que donnerait `problemsFor` si l'item était publié — la seule question qui
 * intéresse un brouillon.
 *
 * La copie est superficielle et JETABLE : on ne veut surtout pas que « demander
 * si ça passerait » ait le moindre effet sur le fichier. C'est une simulation,
 * pas une promotion.
 */
export function problemsIfPublished({ kind, data }) {
  return problemsFor({ kind, data: { ...data, status: 'published' } });
}

/** La boucle de rapport de la ligne de commande. Comportement inchangé. */
export function checkPublishable(entries) {
  let failures = 0;
  for (const { kind, file, data } of entries) {
    const problems = problemsFor({ kind, data });
    if (problems.length) {
      failures++;
      console.error(`FAIL ${file}`);
      problems.forEach((p) => console.error(`     ${p}`));
    }
  }
  console.log(`check-publishable: ${entries.length - failures}/${entries.length} OK`);
  return failures === 0;
}
