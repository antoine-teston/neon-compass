#!/usr/bin/env node
// Accès réseau de la veille. Commandes :
//   policy                  affiche la politique par domaine (autorisé / API / interdit)
//   feed <url|hôte>         liste les entrées récentes du flux d'un domaine
//   page <url>              rend le texte d'un article
//   wiki <titre>            rend l'extrait d'une page du wiki, via l'API
//   weekly [--write]        la semaine du mode en ligne, normalisée en fait
//                           d'inbox structuré (weekly-hub.mjs)
//   preflight               sonde chaque source autorisée et dit QUI refuse
//
// Pourquoi ce script existe plutôt qu'un `WebFetch` direct :
//
// 1. Il APPLIQUE la liste blanche au lieu de la rappeler. `source-policy.mjs`
//    lève sur un domaine interdit ; aucun prompt à respecter, aucune tentation
//    de « juste vérifier » rockstargames.com.
// 2. Il réessaie. Les deux runs de juillet ont conclu à un blocage permanent en
//    403 sur des domaines qui, vérification faite le 29/07, répondent 200 sur
//    les cinq URLs concernées, y compris avec l'UA par défaut de curl. Le
//    problème était transitoire ; la réponse est un réessai, pas un
//    contournement.
// 3. Il préfère les flux. Un flux donne titres et dates structurés sans lire
//    une seule page — c'est-à-dire sans parcourir le site, ce que le registre
//    de sources interdit de toute façon.
// 4. Il DIAGNOSTIQUE ses 403 au lieu de les rapporter bruts. Voir plus bas.

import { setTimeout as sleep } from 'node:timers/promises';
import {
  policyFor,
  assertAllowed,
  parseFeed,
  htmlToText,
  feedURLFor,
  allowedHosts,
  forbiddenHosts,
} from './source-policy.mjs';

// Identification honnête plutôt qu'un UA de navigateur emprunté. Les domaines
// qu'on interroge nous autorisent explicitement — se déguiser n'apporterait
// rien et retirerait aux éditeurs le moyen de nous reconnaître et de nous
// contacter.
const USER_AGENT = 'NeonCompassBot/1.0 (compagnon non officiel; +https://github.com/antoine-teston/neon-compass)';

const TIMEOUT_MS = 25_000;
const ATTEMPTS = 3;
/** Palier de base du repli exponentiel. Un 403 transitoire de bouclier
 *  anti-bot se dissipe en quelques secondes ; inutile d'attendre plus. */
const BACKOFF_MS = 2_000;

// ---------------------------------------------------------------------------
// Qui a refusé : la source, ou nous ?
//
// Un 403 ne dit pas d'où il vient. C'est la troisième fois que le projet paie
// cette ambiguïté : deux runs de juillet ont conclu à un blocage permanent des
// sources (à tort — elles répondaient 200), et le run du 3 août a pris un 403
// sur les QUATRE domaines à la fois, cette fois parce que la passerelle de
// sortie de la session refusait le CONNECT. Même code, deux causes opposées,
// deux actions opposées : retirer une source du registre, ou débloquer notre
// propre réseau.
//
// Un témoin tranche. On sonde une URL neutre, hors du registre éditorial —
// elle ne sert JAMAIS de source, uniquement de preuve que la sortie réseau
// fonctionne. Si le témoin répond, le 403 vient de la source. S'il tombe lui
// aussi, c'est nous : quatre domaines indépendants ne se ferment pas la même
// seconde, mais une passerelle, si.
const EGRESS_CONTROL_URL = 'https://example.com/';

const PROXY_ENV_VARS = ['HTTPS_PROXY', 'https_proxy', 'HTTP_PROXY', 'http_proxy', 'ALL_PROXY', 'all_proxy'];

/** Les proxys déclarés dans l'environnement. À signaler dans le diagnostic :
 *  `fetch` de Node 22 les IGNORE, donc un proxy configuré ici ne fait pas ce
 *  qu'un opérateur croit qu'il fait — le trafic part en direct et se fait
 *  couper par le filtre en amont. */
function declaredProxies() {
  return PROXY_ENV_VARS.filter((name) => process.env[name]).map((name) => `${name}=${process.env[name]}`);
}

/** Sondé une seule fois par exécution : le verdict ne change pas en cours de
 *  run, et on ne veut pas transformer un diagnostic en trafic. */
let egressVerdict;

async function egressIsOpen() {
  if (egressVerdict !== undefined) return egressVerdict;
  try {
    const response = await fetch(EGRESS_CONTROL_URL, {
      headers: { 'User-Agent': USER_AGENT, Accept: '*/*' },
      redirect: 'follow',
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    egressVerdict = response.ok;
  } catch {
    egressVerdict = false;
  }
  return egressVerdict;
}

/**
 * Le message d'échec, augmenté de ce que le témoin a appris. C'est la seule
 * sortie que lira l'opérateur (ou l'agent de veille) : elle doit porter
 * l'ACTION, pas seulement le symptôme — les deux causes d'un 403 appellent des
 * gestes opposés, et se tromper de geste coûte une source retirée à tort.
 *
 * Pure et exportée à dessein : c'est la conclusion du diagnostic, donc la seule
 * chose qui mérite un test. Le reste n'est que du réseau.
 */
export function diagnosis({ message, egressOpen, proxies = [] }) {
  if (egressOpen) {
    return (
      `${message}\n` +
      `  Sortie réseau OK (${EGRESS_CONTROL_URL} répond) — le refus vient de la source, pas de nous.\n` +
      '  Action : vérifier le robots.txt du domaine et son état au registre (source-policy.mjs).'
    );
  }
  return (
    `${message}\n` +
    `  SORTIE RÉSEAU BLOQUÉE : le témoin ${EGRESS_CONTROL_URL} échoue lui aussi.\n` +
    "  Ce 403 n'est PAS un refus des sources — c'est notre passerelle de sortie qui coupe.\n" +
    (proxies.length
      ? `  Proxy déclaré : ${proxies.join(', ')} — or le fetch de Node 22 ignore ces variables.\n`
      : "  Aucun proxy déclaré dans l'environnement.\n") +
    '  Action : relancer hors du bac à sable réseau (runner CI, ou shell sans filtrage), pas toucher au registre.'
  );
}

async function explain(message) {
  return diagnosis({ message, egressOpen: await egressIsOpen(), proxies: declaredProxies() });
}

/** Erreur déjà diagnostiquée : `fetchWithRetry` la relance telle quelle au lieu
 *  de la réessayer trois fois pour rien. */
class EgressBlocked extends Error {}

async function fetchWithRetry(url) {
  assertAllowed(url);

  let lastError;
  for (let attempt = 1; attempt <= ATTEMPTS; attempt++) {
    try {
      const response = await fetch(url, {
        headers: { 'User-Agent': USER_AGENT, Accept: '*/*' },
        redirect: 'follow',
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
      if (response.ok) return await response.text();
      // 4xx hors 403/429 : la ressource n'existe pas ou ne nous est pas
      // destinée. Réessayer ne changerait rien et masquerait l'erreur.
      if (response.status < 500 && response.status !== 403 && response.status !== 429) {
        throw new Error(`HTTP ${response.status} sur ${url}`);
      }
      lastError = new Error(`HTTP ${response.status} sur ${url}`);
      // Le témoin passe AVANT les réessais. Si c'est notre passerelle qui
      // coupe, trois tentatives et six secondes de repli ne feront que retarder
      // le bon diagnostic — et le run de veille entier attend derrière.
      if (response.status === 403 && !(await egressIsOpen())) {
        throw new EgressBlocked(await explain(lastError.message));
      }
    } catch (err) {
      if (err instanceof EgressBlocked) throw err;
      lastError = err;
      if (err.message?.startsWith('HTTP 4') && !/(403|429)/.test(err.message)) throw err;
    }
    if (attempt < ATTEMPTS) await sleep(BACKOFF_MS * attempt);
  }
  throw new Error(await explain(`${lastError?.message ?? 'échec'} — après ${ATTEMPTS} tentatives`));
}

function normalizeTarget(target) {
  if (/^https?:\/\//i.test(target)) return target;
  return `https://${target.replace(/^\/+/, '')}`;
}

async function commandPolicy() {
  console.log('Sources interrogeables :');
  for (const { host, mode, feed } of allowedHosts()) {
    console.log(`  ${host.padEnd(24)} ${mode}${feed ? `  flux: ${feed}` : ''}`);
  }
  console.log('\nSources refusées :');
  for (const { host, reason } of forbiddenHosts()) {
    console.log(`  ${host}`);
    console.log(`      ${reason}`);
  }
}

/** URL de sonde d'une source : son flux s'il en publie un, son API si elle
 *  passe par là, sa racine sinon. Une seule requête par domaine — c'est un
 *  contrôle de joignabilité, pas une visite. */
function probeURLFor({ host, mode, feed }) {
  if (feed) return feed;
  if (mode === 'api') return `${policyFor(`https://${host}/`).api}?action=query&format=json&meta=siteinfo`;
  return `https://${host}/`;
}

/**
 * Sonde chaque source autorisée et rend compte, source par source.
 *
 * Sa raison d'être est la cadence quotidienne : un run qui ne rapporte rien
 * peut être une journée calme (normal, et fréquent en quotidien) ou une veille
 * aveugle. Sans cette étape, les deux se ressemblent — vert, aucune PR — et
 * c'est exactement ainsi qu'on ne remarque pas qu'on ne couvre plus rien.
 * Placée AVANT les étapes qui appellent un modèle, elle échoue gratuitement.
 */
async function commandPreflight() {
  const sources = allowedHosts();
  const results = [];

  for (const source of sources) {
    const url = probeURLFor(source);
    try {
      await fetchWithRetry(url);
      results.push({ host: source.host, ok: true });
      console.log(`  OK       ${source.host.padEnd(24)} ${url}`);
    } catch (err) {
      results.push({ host: source.host, ok: false, message: err.message });
      console.log(`  ÉCHEC    ${source.host.padEnd(24)} ${url}`);
    }
  }

  const failed = results.filter((r) => !r.ok);
  if (!failed.length) {
    console.log(`\n${sources.length} source(s) joignable(s) — la veille peut tourner.`);
    return;
  }

  console.error('');
  // Toutes tombées d'un coup : ce n'est pas quatre sources qui se ferment la
  // même seconde. Un seul message vaut mieux que quatre fois le même.
  if (failed.length === sources.length && !(await egressIsOpen())) {
    console.error(await explain(`${failed.length} source(s) sur ${sources.length} injoignables`));
  } else {
    for (const { host, message } of failed) console.error(`${host} :\n${message}`);
  }
  process.exit(1);
}

/**
 * Réduit une URL à un nom de fichier lisible et SANS COLLISION.
 *
 * Le chemin entier, pas seulement son dernier segment : leonidaverse publie le
 * même article sous `/en/news/<slug>` et `/fr/news/<slug>`, et ne garder que la
 * fin ferait silencieusement écraser une version par l'autre — donc perdre une
 * page sur deux sans que rien ne le signale.
 */
export function harvestSlug(url) {
  const { hostname, pathname } = new URL(url);
  const path = pathname.replace(/^\/+|\/+$/g, '') || 'index';
  return `${hostname.replace(/^www\./, '')}__${path}`.replace(/[^a-z0-9._-]+/gi, '-').slice(0, 150);
}

/** Les entrées de flux publiées dans la fenêtre, les plus récentes d'abord.
 *  Pure : c'est la seule décision de la récolte qui mérite un test. */
export function recentEntries(items, { since, today, max }) {
  const floor = new Date(`${today}T00:00:00Z`);
  floor.setUTCDate(floor.getUTCDate() - since);
  const cutoff = floor.toISOString().slice(0, 10);

  const kept = items
    .filter((item) => item.date && item.date >= cutoff && item.link)
    .sort((a, b) => (a.date < b.date ? 1 : -1));

  return { kept: kept.slice(0, max), dropped: kept.slice(max) };
}

/**
 * Récolte déterministe : les flux, puis le texte des articles de la fenêtre.
 *
 * Pourquoi cette commande existe — et pourquoi elle n'écrit PAS dans content/ :
 *
 * La veille a besoin de deux choses qui ne vivent pas au même endroit. Le
 * RÉSEAU n'est ouvert que sur un runner CI ; le JUGEMENT (quel titre mérite un
 * fait) n'existe que dans une session de modèle, laquelle tourne derrière une
 * passerelle qui refuse ces domaines. Aucune des deux ne peut faire le travail
 * de l'autre. Cette commande est la moitié déterministe : zéro modèle, zéro
 * clé d'API, juste des octets rapportés dans un répertoire.
 *
 * Le texte des articles est du TEXTE DE TIERS. Il sort en artefact éphémère,
 * jamais en commit : le dépôt ne doit contenir que nos reformulations. C'est
 * l'appelant (le workflow) qui garantit cette éphémérité, mais la règle se
 * décide ici, sinon personne ne la relit.
 */
async function commandHarvest({ out, since, max, today }) {
  const { mkdirSync, writeFileSync, readFileSync } = await import('node:fs');
  const { join } = await import('node:path');

  mkdirSync(join(out, 'pages'), { recursive: true });

  const feeds = {};
  const fetched = [];
  const skipped = [];
  const candidates = [];

  // Tous les flux d'abord, les pages ensuite : le plafond doit être GLOBAL.
  // Appliqué source par source, `--max 15` en rapporterait trente sur deux
  // sources — et un opérateur lit « max » comme un total.
  for (const source of allowedHosts()) {
    if (!source.feed) continue;
    try {
      const items = parseFeed(await fetchWithRetry(source.feed));
      feeds[source.host] = items;
      candidates.push(...items);
    } catch (err) {
      // Une source qui tombe ne doit pas emporter les autres — mais elle doit
      // SE VOIR, sinon la veille rétrécit sans que personne le remarque.
      skipped.push({ host: source.host, reason: err.message.split('\n')[0] });
      console.error(`flux en échec — ${source.host} : ${err.message}`);
    }
  }

  const { kept, dropped } = recentEntries(candidates, { since, today, max });
  for (const entry of dropped) skipped.push({ url: entry.link, reason: `au-delà du plafond de ${max} pages` });

  for (const entry of kept) {
    try {
      const text = htmlToText(await fetchWithRetry(entry.link));
      writeFileSync(join(out, 'pages', `${harvestSlug(entry.link)}.txt`), text);
      fetched.push({ url: entry.link, title: entry.title, date: entry.date });
    } catch (err) {
      skipped.push({ url: entry.link, reason: err.message.split('\n')[0] });
    }
  }

  writeFileSync(join(out, 'feeds.json'), `${JSON.stringify(feeds, null, 2)}\n`);
  writeFileSync(join(out, 'harvest.json'), `${JSON.stringify({ today, since, max, fetched, skipped }, null, 2)}\n`);

  // Le même contenu, en UN fichier, textes des pages inclus.
  //
  // Pourquoi ce doublon : la veille lit sa récolte depuis une session dont la
  // passerelle de sortie n'autorise que `api.github.com`. Les artefacts
  // d'Actions n'y suffisent pas — leur téléchargement redirige vers un CDN
  // Azure, refusé au CONNECT (constaté le 2026-08-03). Le transport passe donc
  // par l'API `contents`, qui rend le fichier dans sa réponse ; et un seul
  // appel vaut mieux qu'un par page.
  writeFileSync(
    join(out, 'recolte.json'),
    `${JSON.stringify({
      today,
      since,
      max,
      fetched,
      skipped,
      feeds,
      pages: Object.fromEntries(fetched.map((entry) => [entry.url, readFileSync(join(out, 'pages', `${harvestSlug(entry.url)}.txt`), 'utf8')])),
    })}\n`,
  );

  console.log(`récolte du ${today} — fenêtre de ${since} jour(s)`);
  console.log(`  ${fetched.length} page(s) rapportée(s), ${Object.keys(feeds).length} flux lu(s)`);
  for (const entry of skipped) console.log(`  écarté : ${entry.url ?? entry.host} — ${entry.reason}`);
}

async function commandFeed(target) {
  const url = normalizeTarget(target);
  const feedURL = feedURLFor(url) ?? (url.match(/\.(xml|rss|atom)$/i) ? url : null);
  if (!feedURL) {
    const policy = policyFor(url);
    if (policy.mode === 'forbidden') throw new Error(`source refusée — ${url}\n  ${policy.reason}`);
    throw new Error(`${new URL(url).hostname} ne publie pas de flux connu — utiliser « page <url> »`);
  }

  const items = parseFeed(await fetchWithRetry(feedURL));
  if (!items.length) {
    throw new Error(`flux lu mais aucune entrée reconnue : ${feedURL} — le format a peut-être changé`);
  }
  console.log(JSON.stringify(items, null, 2));
}

async function commandPage(target) {
  const url = normalizeTarget(target);
  const text = htmlToText(await fetchWithRetry(url));
  if (!text) throw new Error(`page vide après extraction : ${url}`);
  console.log(text);
}

async function commandWiki(title) {
  const policy = policyFor('https://gta.fandom.com/');
  const params = new URLSearchParams({
    action: 'query',
    prop: 'revisions',
    rvprop: 'content',
    rvslots: 'main',
    format: 'json',
    formatversion: '2',
    redirects: '1',
    titles: title,
  });
  const raw = await fetchWithRetry(`${policy.api}?${params}`);
  const page = JSON.parse(raw)?.query?.pages?.[0];
  if (!page || page.missing) throw new Error(`page de wiki introuvable : ${title}`);
  // Le wikitext est rendu tel quel : la veille en extrait des faits, elle n'a
  // pas besoin d'un rendu propre, et le dégrader coûterait des informations
  // (modèles, infobox) qu'un rendu HTML aplatirait.
  console.log(page.revisions[0].slots.main.content);
}

/**
 * Récupère la semaine du mode en ligne et l'écrit comme fait d'inbox structuré.
 *
 * Deux appels réseau, tous deux sur des sources du registre : le hub (qui porte
 * bonus, remises et fin de fenêtre) et le flux (qui datte l'article lié, d'où
 * vient le début de fenêtre). Aucune page de plus — le registre interdit de
 * parcourir un site, et le flux existe pour ça.
 *
 * Pourquoi cette commande écrit, alors que les autres ne font qu'afficher : elle
 * n'a pas de modèle en aval. Un fait déjà structuré n'a rien à faire relire par
 * `data-scout` pour être recopié — c'est justement ce détour qu'on supprime.
 */
async function commandWeekly({ write }) {
  const { HUB_URL, parseWeeklyHub, resolveArticleDate, hubToFact } = await import('./weekly-hub.mjs');

  const { hub, articlePath, rewards, rewardsSkipped } = parseWeeklyHub(await fetchWithRetry(HUB_URL));
  const articleURL = new URL(articlePath, HUB_URL).toString();
  const feedURL = feedURLFor(HUB_URL);
  if (!feedURL) throw new Error(`${new URL(HUB_URL).hostname} n’a plus de flux au registre — le début de fenêtre en dépend`);
  const articleDate = resolveArticleDate(articlePath, parseFeed(await fetchWithRetry(feedURL)));

  // Le seul endroit de la chaîne qui lit l'horloge. `hubToFact` refuse une
  // fenêtre déjà close — c'est ce qui empêche un hub cessant d'être tenu à jour
  // de faire republier la semaine dernière en silence, indéfiniment.
  const { fact, skipped } = hubToFact({ hub, articleURL, articleDate, rewards, rewardsSkipped, now: new Date() });

  console.error(`fenêtre ${fact.starts_at} → ${fact.ends_at}`);
  console.error(`  ${fact.bonuses.length} bonus, ${fact.discounts.length} remise(s), ${fact.rewards.length} récompense(s) retenus`);
  // Écarté ≠ absent. Une catégorie que la source publie et que le schéma ne peut
  // pas porter doit se VOIR, sinon elle disparaît sans que personne le remarque.
  for (const entry of skipped) {
    console.error(`  écarté : ${entry.name} [${entry.label ?? 'sans étiquette'}] — ${entry.reason}`);
  }

  if (!write) {
    console.log(JSON.stringify({ run: { date: articleDate, sources_visited: [HUB_URL, articleURL] }, facts: [fact] }, null, 2));
    return;
  }

  const { writeFileSync, existsSync, readFileSync } = await import('node:fs');
  const { fileURLToPath } = await import('node:url');
  const { dirname, join } = await import('node:path');
  const inbox = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'content', 'inbox');
  const path = join(inbox, `${articleDate}-gtav-weekly.facts.json`);

  // Réécrire le fichier de la semaine est sans danger : l'idempotence ne vient
  // pas de l'inbox mais de `processedFrom` (facts-to-online-event.mjs). En
  // revanche on ne PERD pas le drapeau `processed` d'un fait déjà matérialisé,
  // sans quoi `data-scout` le re-signalerait à chaque run.
  const previous = existsSync(path) ? JSON.parse(readFileSync(path, 'utf8')) : null;
  const wasProcessed = previous?.facts?.[0]?.claim === fact.claim && previous.facts[0].processed === true;
  const payload = {
    run: { date: articleDate, sources_visited: [HUB_URL, articleURL] },
    facts: [wasProcessed ? { ...fact, processed: true } : fact],
  };
  writeFileSync(path, `${JSON.stringify(payload, null, 2)}\n`);
  console.log(`écrit content/inbox/${articleDate}-gtav-weekly.facts.json — enchaîner sur « cli.js pull-online-events »`);
}

async function main() {
  const argv = process.argv.slice(2).filter((arg) => arg !== '--write');
  const write = process.argv.includes('--write');
  const [command, ...rest] = argv;
  const target = rest.join(' ');

  try {
    switch (command) {
      case 'policy':
        await commandPolicy();
        break;
      case 'feed':
        if (!target) throw new Error('usage: fetch-source.mjs feed <url|hôte>');
        await commandFeed(target);
        break;
      case 'page':
        if (!target) throw new Error('usage: fetch-source.mjs page <url>');
        await commandPage(target);
        break;
      case 'wiki':
        if (!target) throw new Error('usage: fetch-source.mjs wiki <titre de page>');
        await commandWiki(target);
        break;
      case 'weekly':
        await commandWeekly({ write });
        break;
      case 'preflight':
        await commandPreflight();
        break;
      case 'harvest': {
        const flag = (name, fallback) => {
          const at = process.argv.indexOf(`--${name}`);
          return at === -1 ? fallback : process.argv[at + 1];
        };
        await commandHarvest({
          out: flag('out', 'harvest'),
          since: Number(flag('since', 2)),
          max: Number(flag('max', 15)),
          today: flag('today', new Date().toISOString().slice(0, 10)),
        });
        break;
      }
      default:
        console.error('usage: fetch-source.mjs <policy|feed|page|wiki|weekly|preflight|harvest> [cible] [--write]');
        process.exit(2);
    }
  } catch (err) {
    console.error(err.message);
    process.exit(1);
  }
}

// Le bloc CLI ne s'exécute que si le fichier est LANCÉ, pas s'il est importé :
// `diagnosis` doit être testable sans que `node --test` déclenche un run de
// veille — donc sans requête réseau sur les sources.
const { fileURLToPath } = await import('node:url');
const { resolve } = await import('node:path');
if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) await main();
