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
// Ce que la source donnait (payload RSC de la page, mesuré le 2026-08-02) :
//
//   { "currentPhaseEndsAt": "2026-08-05T23:59:59+00:00",
//     "bonuses":   [ { "activityName", "multiplierLabel", "details" } ],
//     "discounts": [ { "itemName", "discountLabel", "details" } ] }
//
// Ce qu'elle ne donnait pas : le DÉBUT de la fenêtre. Il venait de la date de
// publication de l'article lié, lue dans le flux — donc sans parcourir le site,
// ce que le registre interdit (source-policy.mjs).
//
// ─────────────────────────────────────────────────────────────────────────────
// REFONTE DE LA SOURCE, mesurée le 2026-08-06 à 19:00 UTC.
//
// La donnée n'a pas quitté le payload RSC : elle a changé de NATURE. Elle n'y est
// plus comme objet de données, elle y est comme arbre React rendu —
//
//   ["$","section","bonus-A Superyacht Life missions-2026-08-12T23:59:59+00:00",{…}]
//
// Tous les ancrages ci-dessus ont disparu : `hub`, `currentPhaseEndsAt`,
// `activityName`, `multiplierLabel`, `itemName`, `discountLabel`, la section
// `id="weekly-rewards"`, et le libellé `Read the news story`.
//
// Ce fichier est au TEMPS 1 de la reprise (spec 2026-08-06-hub-hebdo-verdicts) :
// la façade d'extraction rend un verdict honnête, et rien de plus. Elle ne sait
// PAS lire une semaine vivante sous le nouveau design — le balisage d'une semaine
// vivante n'était pas observable le jour où elle a été écrite, la source n'en
// ayant publié aucune. Les transformations en aval (`hubToFact` et les analyses
// d'étiquettes) sont intactes : c'est le temps 2 qui les réalimentera.
//
// SUITE, mesurée le 2026-08-15 (run Récolte 31859751817) : la semaine vivante
// est arrivée… sans tableau. La page publie un RÉCIT (« Latest GTA Online
// weekly story »), déclare elle-même que le tableau structuré n'est pas
// disponible, et son payload RSC ne contient plus un seul horodatage. Deux runs
// de suite sont tombés en `page-meconnaissable` — faux : la page se lisait très
// bien, c'est une ancre de décor qui avait disparu. D'où le réancrage des
// PAGE_ANCHORS ci-dessous et le verdict `sans-structure`. Le temps 2 complet —
// relire un tableau vivant — reste suspendu au retour du tableau chez la
// source ; `hubToFact` et les analyses d'étiquettes restent prêtes.
// ─────────────────────────────────────────────────────────────────────────────
//
import { notANominativeName } from './nominative-fields.mjs';

// Discipline générale, la même que `OnlineEvent.init(from:)` côté app : une
// structure qu'on ne reconnaît pas LÈVE. Un repli silencieux produirait un
// compte à rebours faux, ce qui est pire qu'une absence.

/** Langues cibles hors `en`, alignées sur `LANGS` (cli.js). Les étiquettes sont
 *  COMPOSÉES dans les cinq langues plutôt que traduites : elles ne portent
 *  qu'un nombre et un mot, et la source les écrit avec une marque (« 2x GTA$ »)
 *  qu'on ne peut de toute façon pas recopier. */
export const HUB_URL = 'https://www.gtaboom.com/gta-online-weekly-updates';

/** Les deux ancres qui identifient la page. Deux `id` de section : ce qui a le
 *  plus de chances de survivre à un coup de peinture, et jamais une classe
 *  Tailwind. Les DEUX sont exigées — reconnaître à moitié, c'est ne pas
 *  reconnaître.
 *
 *  Réancré le 2026-08-15 : le `<nav aria-label="Weekly event sections">` du
 *  design du 06/08 a disparu de la page vivante (run Récolte 31859751817), et
 *  la page tombait en `page-meconnaissable` deux runs de suite. Les deux `id`
 *  retenus existent dans les DEUX générations — la fixture `sans-semaine` du
 *  06/08 les porte déjà — ce qui confirme la doctrine : les id sémantiques
 *  survivent aux refontes, les attributs de décor non. */
const PAGE_ANCHORS = ['id="weekly-updates-heading"', 'id="weekly-reset"'];

/** L'ancre du bandeau où la page déclare son propre état. */
const HEADING_ANCHOR = 'id="weekly-updates-heading"';

/** Fenêtre de lecture après le titre, pour attraper le paragraphe de statut qui
 *  le suit. Bornée : au-delà on lirait la prose de la section suivante. */
const STATUS_WINDOW = 4_000;

/**
 * Les déclarations qui signifient « aucune semaine publiée en ce moment ».
 *
 * ÉNUMÉRATION FERMÉE, et c'est tout l'intérêt. Une formulation hors liste ne
 * devient pas « pas de semaine » par défaut : elle LÈVE. Sans quoi, le jour où la
 * source publierait une semaine vivante sous un balisage qu'on ne sait pas lire,
 * on la classerait « rien à récolter » et personne ne le saurait jamais.
 *
 * Absence de donnée et absence de compréhension sont deux verdicts distincts, et
 * un seul des deux est silencieux.
 *
 * Comparé en minuscules sur le titre ET le paragraphe qui le suit.
 */
const PHASE_ENDED_DECLARATIONS = ['the current weekly bonus phase has ended'];

/**
 * Les déclarations qui signifient « le récit de la semaine existe, mais la
 * source ne publie pas (ou plus) son tableau structuré ». Relevé le 2026-08-15 :
 * « The latest weekly story is available. A structured current-phase bonus
 * breakdown is not available yet. »
 *
 * Même discipline d'énumération FERMÉE que ci-dessus, et troisième état à part
 * entière : ce n'est ni « pas de semaine » (il y en a une, en prose — la veille
 * d'actu la couvre par les articles) ni une page qu'on ne comprend pas. Sans ce
 * verdict, l'état tombait en `page-meconnaissable` et chaque run passait pour
 * une panne — deux jours de suite avant que la distinction soit écrite.
 */
const SANS_STRUCTURE_DECLARATIONS = ['bonus breakdown is not available'];

/** Le libellé du lien vers le récit de la semaine, sur la page du 2026-08-15.
 *  Même technique que `ARTICLE_CTA` : trouver le libellé dans le payload,
 *  remonter au `href` qui le précède. */
const STORY_CTA = 'Read the latest story';

/** Erreur porteuse d'un verdict. Le code de sortie ne distingue pas trois issues
 *  différentes ; l'appelant a besoin du verdict pour l'écrire dans sa capture. */
export class HubVerdictError extends Error {
  constructor(verdict, message) {
    super(message);
    this.name = 'HubVerdictError';
    this.verdict = verdict;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HORS DU CHEMIN COURANT depuis la refonte du 2026-08-06, et conservés exprès.
//
// `ARTICLE_CTA` visait un libellé qui n'existe plus : la source dit désormais
// « Read the event story », et le lien pointe un article d'ÉVÉNEMENT
// (`/gta-online-summer-heist-event-july-2026`), plus l'article de la semaine.
// Le réancrer à l'aveugle sur ce seul constat serait deviner — le temps 2 le fera
// sur du balisage réel. La TECHNIQUE, elle, reste bonne et directement
// réutilisable : trouver le libellé, remonter au `href` qui le précède.
//
// `objectAfterKey` découpe un objet JSON noyé dans du non-JSON. Le nouveau payload
// n'en contient plus, mais l'équilibrage d'accolades sur un flux RSC est le genre
// de code qu'on n'a pas envie de réécrire de mémoire.
// ─────────────────────────────────────────────────────────────────────────────
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

/** Chemin d'un article, à partir du libellé de son bouton dans le payload. */
function articlePathFrom(flight, cta = ARTICLE_CTA) {
  const at = flight.indexOf(cta);
  if (at < 0) return null;
  const window = flight.slice(Math.max(0, at - CTA_WINDOW), at);
  const hrefs = [...window.matchAll(/"href":"(\/[^"]+)"/g)];
  return hrefs.length ? hrefs[hrefs.length - 1][1] : null;
}

/**
 * Le bandeau où la page déclare son propre état : son titre, et le paragraphe qui
 * le suit. On lit ce que la source DIT d'elle-même plutôt que d'inférer son état
 * de ce qu'elle ne contient pas.
 *
 * @returns {{heading: string, statement: string} | null}
 */
function statusDeclaration(html) {
  if (typeof html !== 'string') return null;
  const at = html.indexOf(HEADING_ANCHOR);
  if (at < 0) return null;
  const open = html.lastIndexOf('<h1', at);
  const close = html.indexOf('</h1>', at);
  if (open < 0 || close < 0) return null;

  const heading = tagText(html.slice(open, close));
  const after = html.slice(close, close + STATUS_WINDOW);
  const paragraph = after.match(/<p\b[^>]*>([\s\S]*?)<\/p>/i);
  return { heading, statement: paragraph ? tagText(paragraph[1]) : '' };
}

/** La page déclare-t-elle que la phase hebdomadaire est close ? */
function declaresPhaseEnded({ heading, statement }) {
  const said = `${heading} ${statement}`.toLowerCase();
  return PHASE_ENDED_DECLARATIONS.some((declaration) => said.includes(declaration));
}

/** La page déclare-t-elle publier le récit sans le tableau structuré ? */
function declaresSansStructure({ heading, statement }) {
  const said = `${heading} ${statement}`.toLowerCase();
  return SANS_STRUCTURE_DECLARATIONS.some((declaration) => said.includes(declaration));
}

/**
 * Lit une page de hub hebdomadaire et rend un VERDICT.
 *
 * Cinq issues, dans cet ordre — chacune suppose la précédente écartée, et chaque
 * message nomme l'ancrage qui a lâché, sans quoi le diagnostic se referait à la
 * main dans 430 ko de HTML :
 *
 *   `payload-absent`        aucun morceau RSC                         → lève
 *   `page-meconnaissable`   payload présent, ancres de page absentes  → lève
 *   `declaration-inconnue`  page reconnue, déclaration hors liste     → lève
 *   `sans-semaine`          page reconnue, phase déclarée close       → rend
 *   `sans-structure`        page reconnue, récit publié mais tableau
 *                           déclaré absent — avec le chemin du récit  → rend
 *
 * Il n'y a toujours PAS de branche « semaine vivante » : une semaine STRUCTURÉE
 * vivante tombe en `declaration-inconnue`, donc en échec bruyant. C'est le
 * comportement correct tant qu'on ne sait pas la lire — mieux vaut un run rouge
 * qu'une semaine avalée en silence. `sans-structure` n'y déroge pas : il ne
 * s'applique que parce que la source DÉCLARE elle-même l'absence du tableau.
 *
 * @returns {{ verdict: 'sans-semaine', declaration: string, statement: string }
 *         | { verdict: 'sans-structure', declaration: string, statement: string, storyPath: string|null }}
 * @throws  {HubVerdictError}
 */
export function parseWeeklyHub(html) {
  const flight = rscFlight(html);
  if (!flight) {
    throw new HubVerdictError(
      'payload-absent',
      'payload RSC introuvable — la page n’est plus rendue par Next.js, ou son HTML n’a pas été récupéré en entier',
    );
  }

  const missing = PAGE_ANCHORS.filter((anchor) => !html.includes(anchor));
  const status = statusDeclaration(html);
  if (missing.length || !status) {
    throw new HubVerdictError(
      'page-meconnaissable',
      `page de hub non reconnue — ancres manquantes : ${(missing.length ? missing : ['bandeau de statut illisible']).join(', ')}`,
    );
  }

  if (declaresPhaseEnded(status)) {
    return { verdict: 'sans-semaine', declaration: status.heading, statement: status.statement };
  }

  if (declaresSansStructure(status)) {
    return {
      verdict: 'sans-structure',
      declaration: status.heading,
      statement: status.statement,
      // La seule piste exploitable que la page offre : le récit, que la veille
      // d'actu couvre déjà par les articles du flux. Nullable — un verdict ne
      // devient pas une erreur parce qu'un bouton a changé de libellé.
      storyPath: articlePathFrom(flight, STORY_CTA),
    };
  }

  throw new HubVerdictError(
    'declaration-inconnue',
    `la page se déclare « ${status.heading} », formulation hors de l’énumération connue — ` +
      'c’est le cas d’une semaine VIVANTE, que cette version ne sait pas encore lire. ' +
      'Ne pas la classer « pas de semaine » : ce serait avaler une semaine en silence',
  );
}

/**
 * Les récompenses de la semaine, lues dans le MARQUAGE et non dans le payload —
 * la source ne les publie pas en JSON, contrairement aux bonus et aux remises.
 *
 * Conséquence assumée : cette extraction est fragile là où l'autre est solide.
 * Elle s'accroche donc à ce qui a le plus de chances de survivre à un
 * redesign — l'`id` de section, la balise `<article>`, l'attribut
 * `data-variant="overline"` — et jamais à une classe Tailwind, qui change à
 * chaque coup de peinture.
 *
 * Et surtout : **elle ne lève jamais.** Une carte sans ses récompenses reste
 * utile ; une semaine entière perdue parce qu'un `<article>` est devenu un
 * `<li>` ne l'est pas. L'appelant reçoit un tableau vide et le signale.
 */
const REWARD_KINDS = {
  'challenge reward': 'challenge',
  'login reward': 'login',
  'free vehicle': 'vehicle',
  'cash bonus': 'cash',
};

/** Le texte d'une balise, dépouillé de tout marquage imbriqué (les cartes
 *  contiennent des `<svg>` et des `<span>`). */
function tagText(html) {
  return html
    .replace(/<[^>]*>/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&#39;|&apos;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&nbsp;/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/** Découpe la section `id="<name>"` jusqu'à la section suivante. */
function sectionSlice(html, name) {
  if (typeof html !== 'string') return null;
  const at = html.indexOf(`id="${name}"`);
  if (at < 0) return null;
  const next = html.indexOf('<section id="', at + 1);
  return html.slice(at, next < 0 ? undefined : next);
}

/**
 * HORS DU CHEMIN COURANT depuis la refonte du 2026-08-06 : la section
 * `id="weekly-rewards"` qu'elle vise n'existe plus. La page l'a remplacée par
 * `#qualified-rewards`, référencée par sa navigation mais ABSENTE du DOM tant
 * qu'aucune semaine n'est publiée — donc non observable le jour de l'écriture.
 * Réancrage au temps 2, sur du balisage réel. La stratégie d'ancrage, elle, s'est
 * vérifiée : `id` de section, balise sémantique et `data-variant` ont survécu à la
 * refonte, là où les classes Tailwind ont toutes changé.
 *
 * @returns {{ rewards: Array<{kind: string, item: {en: string}}>, skipped: Array<{name: string, label: string|null, reason: string}> }}
 */
export function parseRewards(html) {
  const rewards = [];
  const skipped = [];
  const slice = sectionSlice(html, 'weekly-rewards');
  if (!slice) return { rewards, skipped };

  for (const [, article] of [...slice.matchAll(/<article[\s>]([\s\S]*?)<\/article>/gi)]) {
    const overline = article.match(/data-variant="overline"[^>]*>([\s\S]*?)<\/p>/i);
    const heading = article.match(/<h3[^>]*>([\s\S]*?)<\/h3>/i);
    const label = overline ? tagText(overline[1]).toLowerCase() : null;
    const name = heading ? tagText(heading[1]) : null;

    if (!name) continue; // une carte sans titre n'est pas une récompense
    const kind = label ? REWARD_KINDS[label] : undefined;
    if (!kind) {
      skipped.push({
        name,
        label,
        reason: `nature de récompense inconnue — l'énumération du schéma est fermée, « Autre » n'apprendrait rien sur une carte étroite`,
      });
      continue;
    }
    // Le nom doit tenir la promesse qui vaut aux champs nominatifs leur
    // exception aux marques (nominative-fields.mjs). Une source qui met une
    // phrase dans son titre ferait sinon échouer `check-publishable` sur la
    // semaine ENTIÈRE — un aller-retour manuel chaque jeudi.
    const problem = notANominativeName(name);
    if (problem) {
      skipped.push({ name, label, reason: `le titre n'est pas un nom — ${problem}` });
      continue;
    }
    rewards.push({ kind, item: { en: name } });
  }

  return { rewards, skipped };
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

/**
 * Extrait la date de fin PROPRE à un bonus depuis la prose de la source.
 *
 * C'est la seule information exploitable que cette prose contienne : le reste est
 * une reformulation de ce qu'on a déjà en structuré, et une date est un FAIT — on
 * peut la reprendre sans reprendre une phrase. Certains bonus courent une semaine
 * de plus que la fenêtre (« pays double GTA$ and RP through August 12 » quand la
 * semaine finit le 5), et la carte le cachait.
 *
 * Ne rend une date que si elle DÉPASSE la fin de fenêtre : la plupart des détails
 * répètent la fin de la semaine, ce qui n'apprend rien et ferait afficher une
 * mention redondante sur chaque ligne.
 *
 * @param endsAt fin de fenêtre, `AAAA-MM-JJTHH:MM:SSZ`
 * @returns `AAAA-MM-JJ`, ou `null`
 */
export function parseBonusUntil(details, endsAt) {
  if (typeof details !== 'string' || typeof endsAt !== 'string') return null;
  const match = details.match(/through\s+([A-Z][a-z]+)\s+(\d{1,2})\b/);
  if (!match) return null;
  const month = MONTHS[match[1]];
  if (month === undefined) return null;

  // L'année n'est pas dans la phrase. Elle vient de la fenêtre — et si la date
  // ainsi formée tombe AVANT elle, c'est que la source parle de l'année suivante
  // (une semaine à cheval sur le 31 décembre).
  const windowYear = Number(endsAt.slice(0, 4));
  const day = String(match[2]).padStart(2, '0');
  const mm = String(month).padStart(2, '0');
  let candidate = `${windowYear}-${mm}-${day}`;
  if (candidate < endsAt.slice(0, 10)) candidate = `${windowYear + 1}-${mm}-${day}`;

  return candidate > endsAt.slice(0, 10) ? candidate : null;
}

const MONTHS = {
  January: 1, February: 2, March: 3, April: 4, May: 5, June: 6,
  July: 7, August: 8, September: 9, October: 10, November: 11, December: 12,
};

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
export function hubToFact({ hub, articleURL, articleDate, now, rewards = [], rewardsSkipped = [], hubURL = HUB_URL, game = 'gtav' }) {
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

  // Ce que `parseRewards` a écarté remonte dans le MÊME compte-rendu que le
  // reste : une catégorie perdue doit se voir au même endroit, quelle que soit
  // l'étape qui l'a perdue.
  const skipped = [...rewardsSkipped];
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
    const until = parseBonusUntil(entry.details, endsAt);
    bonuses.push({
      activity: localizedName(entry.activityName),
      ...(parsed.times !== undefined ? { multiplier: parsed.times } : { percentBonus: parsed.percentBonus }),
      includesRP: parsed.rp,
      ...(until ? { until } : {}),
    });
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

  // La carte reste utile sans récompenses ; elle ne l'est pas sans bonus ni
  // remise. Le seuil d'échec ne porte donc que sur le cœur.
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
      rewards,
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
