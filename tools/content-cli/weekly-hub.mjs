// Extraction du hub hebdomadaire du mode en ligne, et normalisation en fait
// d'inbox. Aucune I/O — `fetch-source.mjs` fournit le HTML, `cli.js` écrit.
//
// Pourquoi un extracteur déterministe plutôt qu'un fait rédigé par `data-scout` :
// un événement hebdomadaire n'est pas une phrase, c'est un tableau (huit bonus,
// onze remises, des pourcentages, une fenêtre horaire). Le faire traverser une
// reformulation en langage naturel puis une re-structuration par
// `content-editor`, c'est deux passages de modèle sur des nombres. La source
// publie déjà la structure : on la prend telle quelle.
//
// Ce que la source donne (payload RSC de la page, mesuré le 2026-08-02) :
//
//   { "currentPhaseEndsAt": "2026-08-05T23:59:59+00:00",
//     "bonuses":   [ { "activityName", "multiplierLabel", "details" } ],
//     "discounts": [ { "itemName", "discountLabel", "details" } ] }
//
// Ce qu'elle ne donne pas : le DÉBUT de la fenêtre. Il vient de la date de
// publication de l'article lié, lue dans le flux — donc sans parcourir le site,
// ce que le registre interdit (source-policy.mjs).
//
// Discipline générale, la même que `OnlineEvent.init(from:)` côté app : une
// structure qu'on ne reconnaît pas LÈVE. Un repli silencieux produirait un
// compte à rebours faux, ce qui est pire qu'une absence.

/** Langues cibles hors `en`, alignées sur `LANGS` (cli.js). Les étiquettes sont
 *  COMPOSÉES dans les cinq langues plutôt que traduites : elles ne portent
 *  qu'un nombre et un mot, et la source les écrit avec une marque (« 2x GTA$ »)
 *  qu'on ne peut de toute façon pas recopier. */
export const HUB_URL = 'https://www.gtaboom.com/gta-online-weekly-updates';

/** Le libellé du bouton qui pointe l'article de la semaine. C'est notre seule
 *  accroche vers la date de DÉBUT ; s'il disparaît, le run doit échouer bruyamment
 *  plutôt que dater la fenêtre au hasard. */
const ARTICLE_CTA = 'Read the news story';
/** Fenêtre de recherche du `href` autour du libellé. Large parce que le payload
 *  RSC intercale les props du composant entre les deux ; bornée parce qu'au-delà
 *  on attraperait le lien d'un article voisin. */
const CTA_WINDOW = 2_000;

/**
 * Recolle le payload RSC d'une page Next.js. Il arrive en morceaux —
 * `self.__next_f.push([1,"<littéral JS>"])` — et un objet JSON peut être coupé
 * en travers de deux morceaux : d'où la concaténation AVANT toute recherche.
 */
export function rscFlight(html) {
  if (typeof html !== 'string') return '';
  let flight = '';
  for (const match of html.matchAll(/self\.__next_f\.push\(\[1,("(?:[^"\\]|\\.)*")\]\)/g)) {
    try {
      flight += JSON.parse(match[1]);
    } catch {
      // Un morceau illisible n'invalide pas les autres : c'est l'absence de la
      // clé `hub` en aval qui décidera, avec un message utile.
    }
  }
  return flight;
}

/** Découpe l'objet JSON qui suit une clé, par équilibrage d'accolades — le
 *  payload est du JSON valide LOCALEMENT, noyé dans du non-JSON. */
function objectAfterKey(flight, key) {
  const at = flight.indexOf(`"${key}":{`);
  if (at < 0) return null;
  const open = flight.indexOf('{', at);
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let i = open; i < flight.length; i++) {
    const char = flight[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char === '\\') {
      escaped = true;
      continue;
    }
    if (char === '"') {
      inString = !inString;
      continue;
    }
    if (inString) continue;
    if (char === '{') depth++;
    else if (char === '}' && --depth === 0) {
      try {
        return JSON.parse(flight.slice(open, i + 1));
      } catch {
        return null;
      }
    }
  }
  return null;
}

/** Chemin de l'article de la semaine, à partir du libellé de son bouton. */
function articlePathFrom(flight) {
  const at = flight.indexOf(ARTICLE_CTA);
  if (at < 0) return null;
  const window = flight.slice(Math.max(0, at - CTA_WINDOW), at);
  const hrefs = [...window.matchAll(/"href":"(\/[^"]+)"/g)];
  return hrefs.length ? hrefs[hrefs.length - 1][1] : null;
}

/**
 * Lit une page de hub hebdomadaire.
 *
 * @returns {{ hub: {currentPhaseEndsAt: string, bonuses: object[], discounts: object[]}, articlePath: string }}
 * @throws  si la structure n'est plus celle qu'on connaît — chaque message dit
 *          LEQUEL des trois ancrages a lâché, sans quoi le diagnostic se ferait
 *          à la main dans 600 ko de HTML.
 */
export function parseWeeklyHub(html) {
  const flight = rscFlight(html);
  if (!flight) {
    throw new Error('payload RSC introuvable — la page n’est plus rendue par Next.js, ou son HTML n’a pas été récupéré en entier');
  }

  const hub = objectAfterKey(flight, 'hub');
  if (!hub) {
    throw new Error('clé « hub » absente du payload RSC — structure de page changée côté source');
  }
  if (typeof hub.currentPhaseEndsAt !== 'string') {
    throw new Error('hub.currentPhaseEndsAt absent — c’est la fin de fenêtre, sans elle il n’y a pas de compte à rebours');
  }
  if (!Array.isArray(hub.bonuses) || !Array.isArray(hub.discounts)) {
    throw new Error('hub.bonuses / hub.discounts ne sont plus des tableaux — structure de payload changée');
  }

  const articlePath = articlePathFrom(flight);
  if (!articlePath) {
    throw new Error(
      `lien vers l’article de la semaine introuvable (libellé « ${ARTICLE_CTA} ») — ` +
        'c’est la seule source du DÉBUT de fenêtre ; la deviner produirait un compte à rebours faux',
    );
  }

  return { hub, articlePath };
}

/** Normalise un instant en l'horodatage UTC que le schéma impose
 *  (`AAAA-MM-JJTHH:MM:SSZ`). La source publie `+00:00` ; un jour elle publiera
 *  peut-être un autre décalage, et `Date` s'en occupe. */
export function normalizeInstant(raw) {
  const parsed = new Date(raw);
  if (Number.isNaN(parsed.getTime())) {
    throw new Error(`horodatage illisible : ${raw}`);
  }
  return `${parsed.toISOString().slice(0, 19)}Z`;
}

/** Date de publication de l'article lié, prise DANS LE FLUX. Le flux donne
 *  titres et dates sans lire une page de plus. */
export function resolveArticleDate(articlePath, feedItems) {
  const match = (feedItems ?? []).find((item) => {
    try {
      return new URL(item.link).pathname === articlePath;
    } catch {
      return false;
    }
  });
  if (!match?.date) {
    throw new Error(
      `article ${articlePath} absent du flux (ou sans date) — le début de fenêtre en dépend. ` +
        'Un article plus vieux que la profondeur du flux sort de portée : relancer le run plus tôt dans la semaine',
    );
  }
  return match.date;
}

/**
 * Analyse une étiquette de multiplicateur. On ne la RECOPIE jamais : elle porte
 * une marque (« 2x GTA$ »), et `TRADEMARKS` (cli.js) a raison de les refuser.
 *
 * @returns {{times?: number, percentBonus?: number, rp: boolean} | null} `null`
 *          si l'entrée n'annonce aucun bonus chiffré — auquel cas ce n'est pas
 *          un bonus, et le schéma exige un `label`.
 */
export function parseMultiplier(label) {
  if (typeof label !== 'string') return null;
  const times = label.match(/^(\d+)\s*x\s+GTA\$(\s+and\s+RP)?$/i);
  if (times) return { times: Number(times[1]), rp: Boolean(times[2]) };
  const bonus = label.match(/^(\d+)%\s+bonus\s+cash$/i);
  if (bonus) return { percentBonus: Number(bonus[1]), rp: false };
  return null;
}

/** Compose l'étiquette dans les cinq langues. Aucune marque, aucun segment
 *  repris de la source : `check-originality.mjs` la compare à la prose source. */
export function localizedMultiplier(parsed) {
  if (parsed.percentBonus !== undefined) {
    const n = parsed.percentBonus;
    return {
      en: `+${n}% cash`,
      fr: `+${n} % d’argent`,
      es: `+${n}% de dinero`,
      it: `+${n}% di denaro`,
      de: `+${n} % Geld`,
    };
  }
  const n = parsed.times;
  return parsed.rp
    ? {
        en: `${n}× cash & RP`,
        fr: `${n}× argent & RP`,
        es: `${n}× dinero y RP`,
        it: `${n}× denaro e RP`,
        de: `${n}× Geld & RP`,
      }
    : { en: `${n}× cash`, fr: `${n}× argent`, es: `${n}× dinero`, it: `${n}× denaro`, de: `${n}× Geld` };
}

/**
 * Analyse une étiquette de remise.
 *
 * @returns {{percent: number, requires?: 'membership'} | null} `null` pour ce
 *          que le schéma ne peut pas porter — une remise en montant fixe
 *          (« GTA$1,000,000 off ») n'est pas un pourcentage, et `percent` est un
 *          entier 1-100. L'appelant la classe en écartée plutôt que de la tordre.
 */
export function parseDiscount(label) {
  if (typeof label !== 'string') return null;
  const plain = label.match(/^(\d+)%\s+off$/i);
  if (plain) return { percent: Number(plain[1]) };
  const members = label.match(/^(\d+)%\s+off\s+for\s+GTA\+\s+members$/i);
  if (members) return { percent: Number(members[1]), requires: 'membership' };
  return null;
}

// Un nom d'activité ou de bien passe tel quel, MARQUE COMPRISE. « GTA+ Shark
// Cards » désigne un produit de l'éditeur ; le nommer pour en parler est l'usage
// référentiel, et la contrainte IP du projet porte sur l'identité de l'app, pas
// sur son contenu éditorial (CLAUDE.md). L'exception et sa contrepartie — rester
// un nom, ne jamais être une marque nue — sont portées par
// `nominative-fields.mjs`, que `check-publishable` applique.
//
// L'extracteur n'a donc aucun filtre de marque : il en avait un, qui écartait
// « GTA+ Shark Cards » et privait la carte d'un bonus réel, alors que la remise
// « Hao's Special Works (abonnés) » du même abonnement passait déjà. L'incohérence
// venait du filtre, pas de la donnée.

/** Suffixe de condition. Le NOM du bien reste tel quel — c'est un nom propre,
 *  pas une rédaction — mais la condition doit se lire, sinon la carte annonce
 *  à tout le monde une remise réservée aux abonnés. */
const MEMBERSHIP_SUFFIX = {
  en: ' (members)',
  fr: ' (abonnés)',
  es: ' (suscriptores)',
  it: ' (abbonati)',
  de: ' (Abonnenten)',
};

/** Un nom propre ne se traduit pas : seul `en` est rempli, et `LocalizedText`
 *  côté app se replie déjà dessus. La condition, elle, est localisée. */
export function localizedName(name, requires) {
  if (requires !== 'membership') return { en: name };
  return Object.fromEntries(Object.entries(MEMBERSHIP_SUFFIX).map(([lang, suffix]) => [lang, `${name}${suffix}`]));
}

const TITLE = {
  en: 'Weekly update',
  fr: 'Mise à jour hebdomadaire',
  es: 'Actualización semanal',
  it: 'Aggiornamento settimanale',
  de: 'Wochen-Update',
};

/** Titre localisé, daté en ISO — une date ISO se lit dans les cinq langues et
 *  n'oblige pas à formater par locale ici. Il distingue deux semaines dans une
 *  liste ; ce qui porte l'information, c'est le compte à rebours. */
export function localizedTitle(startDate) {
  return Object.fromEntries(Object.entries(TITLE).map(([lang, text]) => [lang, `${text} — ${startDate}`]));
}

/**
 * Normalise un hub en fait d'inbox `kind: "online-event"`.
 *
 * @returns {{ fact: object, skipped: Array<{name: string, label: string|null, reason: string}> }}
 *          `skipped` n'est pas du bruit : c'est ce que la source publie et que
 *          nous ne montrons pas. Le compte-rendu de run l'affiche, faute de quoi
 *          une catégorie entière disparaîtrait sans que personne le remarque.
 */
export function hubToFact({ hub, articleURL, articleDate, now, hubURL = HUB_URL, game = 'gtav' }) {
  // `now` est TOUJOURS injecté, jamais lu depuis `new Date()` — même discipline
  // qu'`OnlineEvent.isActive(at:)` côté app. Sans paramètre obligatoire, l'appel
  // du run pourrait l'omettre et perdre le contrôle de péremption sans que rien
  // ne le signale ; c'est exactement le genre d'oubli silencieux qu'on chasse.
  if (!(now instanceof Date) || Number.isNaN(now.getTime())) {
    throw new Error('now est obligatoire (Date) — le contrôle de péremption du hub en dépend');
  }
  const endsAt = normalizeInstant(hub.currentPhaseEndsAt);
  // Début de fenêtre : le jour de publication de l'article, à minuit UTC. On
  // n'invente PAS l'heure du reset (la spec interdit d'en dépendre, et la
  // cadence de Leonida est inconnue). Minuit est au plus tôt : la carte peut
  // s'afficher quelques heures avant l'heure réelle, jamais après — l'erreur
  // tolérable est dans ce sens, puisque `remaining()` ne dépend que d'`endsAt`.
  const startsAt = `${articleDate}T00:00:00Z`;
  if (startsAt >= endsAt) {
    throw new Error(
      `fenêtre incohérente : début ${startsAt} au-delà de la fin ${endsAt} — ` +
        'le hub annonce probablement une phase déjà passée, ou l’article lié n’est pas celui de la semaine',
    );
  }

  // **Le mode de panne le plus dangereux de toute la chaîne**, et le seul qui ne
  // se voit pas : si la source cesse de tenir son hub à jour, la page continue de
  // répondre 200, le payload continue de s'analyser, et rien ne casse. On
  // republierait la semaine dernière indéfiniment — un compte à rebours sur une
  // fenêtre déjà close, ce qui est pire qu'une carte absente.
  //
  // Une fenêtre expirée est donc un ÉCHEC, pas une donnée. Cas le plus probable
  // en pratique, et le message le dit : le run du jeudi est passé avant que la
  // source ait publié la nouvelle semaine.
  if (endsAt <= normalizeInstant(now)) {
    throw new Error(
      `fenêtre déjà expirée : elle finissait le ${endsAt} et il est ${normalizeInstant(now)} — ` +
        'la source n’a pas encore publié la semaine en cours, ou son hub n’est plus tenu à jour. ' +
        'Republier cette fenêtre afficherait un compte à rebours sur une semaine close',
    );
  }

  const skipped = [];
  const bonuses = [];
  for (const entry of hub.bonuses) {
    const parsed = parseMultiplier(entry.multiplierLabel);
    if (!parsed) {
      skipped.push({
        name: entry.activityName ?? '(sans nom)',
        label: entry.multiplierLabel ?? null,
        reason: 'aucun bonus chiffré reconnu — le schéma exige un label, et une activité sans multiplicateur n’en est pas un',
      });
      continue;
    }
    if (!entry.activityName) {
      skipped.push({ name: '(sans nom)', label: entry.multiplierLabel, reason: 'bonus sans activityName' });
      continue;
    }
    bonuses.push({ activity: localizedName(entry.activityName), label: localizedMultiplier(parsed) });
  }

  const discounts = [];
  for (const entry of hub.discounts) {
    const parsed = parseDiscount(entry.discountLabel);
    if (!parsed) {
      skipped.push({
        name: entry.itemName ?? '(sans nom)',
        label: entry.discountLabel ?? null,
        reason: 'remise non exprimée en pourcentage — `percent` est un entier 1-100',
      });
      continue;
    }
    if (!entry.itemName) {
      skipped.push({ name: '(sans nom)', label: entry.discountLabel, reason: 'remise sans itemName' });
      continue;
    }
    discounts.push({ item: localizedName(entry.itemName, parsed.requires), percent: parsed.percent });
  }

  if (!bonuses.length && !discounts.length) {
    throw new Error(
      'ni bonus ni remise retenus — les étiquettes de la source ont changé de forme, ' +
        `${skipped.length} entrée(s) écartée(s)`,
    );
  }

  const startDate = startsAt.slice(0, 10);
  return {
    fact: {
      // Reformulé, et daté : `factDiscriminant` (facts-to-news.mjs) hache
      // `source_url + claim`, et l'URL du hub ne change JAMAIS. Sans la
      // fenêtre dans le claim, la semaine 2 se réapparierait à la semaine 1 et
      // ne serait jamais matérialisée.
      //
      // La fenêtre, et RIEN d'autre. Y compter les bonus retenus — ce que faisait
      // la première version — refrappe un id à chaque fois qu'on change ce qui
      // est retenu, et orpheline l'entrée déjà relue et publiée de la semaine en
      // cours. C'est arrivé deux fois avant que la leçon soit tirée.
      claim: `Fenêtre du mode en ligne du ${startDate} au ${endsAt.slice(0, 10)}, relevée sur le hub hebdomadaire de la source.`,
      kind: 'online-event',
      game,
      source_url: hubURL,
      source_date: articleDate,
      // Une seule rédaction, un seul éditeur : la confiance honnête est
      // `single-source` tant qu'aucune autre source du registre n'a corroboré
      // la semaine. `check-publishable` l'accepte — il ne refuse que `rumor`.
      confidence: 'single-source',
      starts_at: startsAt,
      ends_at: endsAt,
      sources: [hubURL, articleURL],
      title: localizedTitle(startDate),
      bonuses,
      discounts,
      // La prose de la source, conservée telle quelle : c'est le CORPUS auquel
      // `check-originality.mjs` compare les champs rédigés. La remplacer par un
      // résumé viderait le contrôle de sa substance.
      source_prose: [
        ...hub.bonuses.map((b) => [b.activityName, b.multiplierLabel, b.details].filter(Boolean).join(' — ')),
        ...hub.discounts.map((d) => [d.itemName, d.discountLabel, d.details].filter(Boolean).join(' — ')),
      ].join('\n'),
    },
    skipped,
  };
}
