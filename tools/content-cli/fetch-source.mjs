#!/usr/bin/env node
// Accès réseau de la veille. Commandes :
//   policy                  affiche la politique par domaine (autorisé / API / interdit)
//   feed <url|hôte>         liste les entrées récentes du flux d'un domaine
//   page <url>              rend le texte d'un article
//   wiki <titre>            rend l'extrait d'une page du wiki, via l'API
//   weekly [--write]        la semaine du mode en ligne, normalisée en fait
//                           d'inbox structuré (weekly-hub.mjs)
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
    } catch (err) {
      lastError = err;
      if (err.message?.startsWith('HTTP 4') && !/(403|429)/.test(err.message)) throw err;
    }
    if (attempt < ATTEMPTS) await sleep(BACKOFF_MS * attempt);
  }
  throw new Error(`${lastError?.message ?? 'échec'} — après ${ATTEMPTS} tentatives`);
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

  const { hub, articlePath } = parseWeeklyHub(await fetchWithRetry(HUB_URL));
  const articleURL = new URL(articlePath, HUB_URL).toString();
  const feedURL = feedURLFor(HUB_URL);
  if (!feedURL) throw new Error(`${new URL(HUB_URL).hostname} n’a plus de flux au registre — le début de fenêtre en dépend`);
  const articleDate = resolveArticleDate(articlePath, parseFeed(await fetchWithRetry(feedURL)));

  const { fact, skipped } = hubToFact({ hub, articleURL, articleDate });

  console.error(`fenêtre ${fact.starts_at} → ${fact.ends_at}`);
  console.error(`  ${fact.bonuses.length} bonus, ${fact.discounts.length} remise(s) retenus`);
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
    default:
      console.error('usage: fetch-source.mjs <policy|feed|page|wiki|weekly> [cible] [--write]');
      process.exit(2);
  }
} catch (err) {
  console.error(err.message);
  process.exit(1);
}
