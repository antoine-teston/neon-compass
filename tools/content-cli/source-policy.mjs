// La liste blanche de sources du spec (§7), sous forme de code plutôt que de
// paragraphe.
//
// Pourquoi : la règle « jamais un site dont le robots.txt exclut les bots IA »
// vivait uniquement dans le prompt de `data-scout`. Un run de juillet a malgré
// tout cité `rockstargames.com` comme source — dont le robots.txt nomme
// explicitement `ClaudeBot: Disallow: /`. Une règle qu'un modèle doit se
// rappeler n'est pas une règle ; une règle qui lève une exception en est une.
//
// État vérifié le 2026-07-29, robots.txt lu domaine par domaine :
//
//   www.gtaboom.com     User-Agent: * / Allow: /            -> autorisé
//   leonidaverse.com    ClaudeBot nommé, puis Allow: /      -> autorisé
//   gta6.gg             *, seuls des chemins WooCommerce    -> autorisé
//   gta.fandom.com      HTML derrière un défi Cloudflare,
//                       mais /api.php répond                -> via API
//   www.rockstargames.com  ClaudeBot: Disallow: /           -> INTERDIT
//   www.reddit.com      User-agent: * / Disallow: /         -> INTERDIT
//   gtacodes.io         redirige vers un domaine au TLS
//                       cassé (SSL_ERROR_SYSCALL)           -> hors service
//
// Le 403 qu'ont signalé les deux runs de juillet n'était PAS un blocage de
// politique : gtaboom autorise tout le monde, et les cinq URLs qui avaient
// échoué répondent 200. C'était transitoire. D'où le repli de `fetch-source`
// sur des réessais, plutôt que sur un contournement.

const POLICIES = {
  'www.gtaboom.com': {
    mode: 'allow',
    feed: 'https://www.gtaboom.com/feed.xml',
    note: 'robots.txt : User-Agent: * / Allow: /',
  },
  'leonidaverse.com': {
    mode: 'allow',
    feed: 'https://leonidaverse.com/news-sitemap.xml',
    note: 'robots.txt : ClaudeBot explicitement autorisé (Allow: /)',
  },
  'gta6.gg': {
    mode: 'allow',
    feed: null,
    note: 'robots.txt : seuls des chemins WooCommerce sont exclus',
  },
  'gta.fandom.com': {
    mode: 'api',
    api: 'https://gta.fandom.com/api.php',
    note: 'le HTML est derrière un défi Cloudflare ; api.php répond normalement',
  },
  'www.rockstargames.com': {
    mode: 'forbidden',
    reason:
      'robots.txt nomme ClaudeBot avec Disallow: / — la veille est un agent Claude. ' +
      'Les annonces officielles nous parviennent de toute façon par la presse spécialisée.',
  },
  'www.reddit.com': {
    mode: 'forbidden',
    reason:
      'robots.txt : User-agent: * / Disallow: / — tout parcours automatique est exclu. ' +
      "La voie sanctionnée est l'API Data officielle (identifiants OAuth) ; son usage " +
      "commercial est à trancher avant de l'ouvrir, l'app étant financée par la publicité.",
  },
  'gtacodes.io': {
    mode: 'forbidden',
    reason: 'redirige vers gtacheatcodes.net, dont le certificat TLS est cassé — source hors service',
  },
};

/** Les hôtes qui désignent la même politique. Sans ça, `old.reddit.com`
 *  contournerait l'interdiction de `www.reddit.com` par simple orthographe. */
const HOST_ALIASES = {
  'reddit.com': 'www.reddit.com',
  'old.reddit.com': 'www.reddit.com',
  'new.reddit.com': 'www.reddit.com',
  'np.reddit.com': 'www.reddit.com',
  'out.reddit.com': 'www.reddit.com',
  'rockstargames.com': 'www.rockstargames.com',
  'gtaboom.com': 'www.gtaboom.com',
  'www.leonidaverse.com': 'leonidaverse.com',
  'www.gta6.gg': 'gta6.gg',
  'www.gtacodes.io': 'gtacodes.io',
};

const UNKNOWN = {
  mode: 'forbidden',
  reason:
    "domaine hors de la liste blanche du registre de sources (spec §7). L'ajouter " +
    'suppose de lire son robots.txt et de trancher, pas de le fetcher pour voir.',
};

/** Politique applicable à une URL. Ne lève jamais : un appelant qui veut une
 *  exception utilise `assertAllowed`. */
export function policyFor(url) {
  let host;
  try {
    host = new URL(url).hostname.toLowerCase();
  } catch {
    return { mode: 'forbidden', reason: `URL illisible : ${url}` };
  }
  const canonical = HOST_ALIASES[host] ?? host;
  return POLICIES[canonical] ?? UNKNOWN;
}

/** Lève si l'URL n'est pas fetchable. Le message porte la raison : un refus
 *  qu'on ne peut pas expliquer se contourne au run suivant. */
export function assertAllowed(url) {
  const policy = policyFor(url);
  if (policy.mode === 'forbidden') {
    throw new Error(`source refusée — ${url}\n  ${policy.reason}`);
  }
  return policy;
}

/** URL du flux d'un domaine, ou null s'il n'en publie pas. */
export function feedURLFor(url) {
  const policy = policyFor(url);
  return policy.mode === 'allow' ? (policy.feed ?? null) : null;
}

/** Domaines effectivement interrogeables, pour le compte-rendu de run. */
export function allowedHosts() {
  return Object.entries(POLICIES)
    .filter(([, p]) => p.mode !== 'forbidden')
    .map(([host, p]) => ({ host, mode: p.mode, feed: p.feed ?? null }));
}

export function forbiddenHosts() {
  return Object.entries(POLICIES)
    .filter(([, p]) => p.mode === 'forbidden')
    .map(([host, p]) => ({ host, reason: p.reason }));
}

const ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', '#39': "'" };

function decodeEntities(text) {
  return text.replace(/&(#\d+|#x[0-9a-f]+|\w+);/gi, (match, name) => {
    if (ENTITIES[name.toLowerCase()]) return ENTITIES[name.toLowerCase()];
    if (name.startsWith('#x') || name.startsWith('#X')) return String.fromCodePoint(parseInt(name.slice(2), 16));
    if (name.startsWith('#')) return String.fromCodePoint(Number(name.slice(1)));
    return match;
  });
}

function tagText(block, ...names) {
  for (const name of names) {
    const match = block.match(new RegExp(`<${name}[^>]*>([\\s\\S]*?)</${name}>`, 'i'));
    if (!match) continue;
    const cdata = match[1].match(/<!\[CDATA\[([\s\S]*?)\]\]>/);
    return decodeEntities((cdata ? cdata[1] : match[1]).trim());
  }
  return null;
}

/** Normalise une date de flux en ISO courte. Les trois formats rencontrés —
 *  RFC 822 (RSS), ISO (Atom), ISO avec décalage (sitemap) — sont tous compris
 *  par `Date`, ce qui évite un parseur maison de plus. */
function isoDate(raw) {
  if (!raw) return null;
  const parsed = new Date(raw);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString().slice(0, 10);
}

/**
 * Lit un flux RSS 2.0, Atom ou news-sitemap et rend `[{title, link, date}]`.
 *
 * Extraction par expressions régulières et non par un vrai parseur XML : ces
 * trois formats sont plats et bien formés, et la dépendance qu'un parseur
 * imposerait pèserait plus que ce qu'elle apporte. En contrepartie, un flux
 * malformé rend un tableau vide plutôt que de lever — un format qui change ne
 * doit pas faire tomber le run entier, seulement priver la veille d'une source.
 */
export function parseFeed(xml) {
  if (!xml || typeof xml !== 'string') return [];
  try {
    const items = [];

    for (const block of xml.match(/<item[\s>][\s\S]*?<\/item>/gi) ?? []) {
      items.push({
        title: tagText(block, 'title'),
        link: tagText(block, 'link'),
        date: isoDate(tagText(block, 'pubDate', 'dc:date')),
      });
    }

    for (const block of xml.match(/<entry[\s>][\s\S]*?<\/entry>/gi) ?? []) {
      const href = block.match(/<link[^>]*href=["']([^"']+)["']/i);
      items.push({
        title: tagText(block, 'title'),
        link: href ? decodeEntities(href[1]) : tagText(block, 'id'),
        date: isoDate(tagText(block, 'updated', 'published')),
      });
    }

    for (const block of xml.match(/<url[\s>][\s\S]*?<\/url>/gi) ?? []) {
      items.push({
        title: tagText(block, 'news:title', 'title') ?? tagText(block, 'loc'),
        link: tagText(block, 'loc'),
        date: isoDate(tagText(block, 'news:publication_date', 'lastmod')),
      });
    }

    return items.filter((item) => item.link);
  } catch {
    return [];
  }
}

/** Réduit une page HTML au texte qu'un humain y lirait. Suffisant pour donner
 *  un article à lire à la veille — ce n'est pas un extracteur de contenu
 *  principal, et ça n'a pas à l'être : elle n'extrait que des faits. */
export function htmlToText(html) {
  if (!html || typeof html !== 'string') return '';
  return decodeEntities(
    html
      .replace(/<(script|style|noscript|svg)[\s>][\s\S]*?<\/\1>/gi, ' ')
      .replace(/<!--[\s\S]*?-->/g, ' ')
      .replace(/<\/(p|div|section|article|li|h[1-6]|tr|br)>/gi, '\n')
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<[^>]+>/g, ' '),
  )
    .replace(/[ \t ]+/g, ' ')
    .replace(/ *\n */g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}
