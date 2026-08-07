// Le script de la console. Sorti d'`index.html` le 2026-08-07 : la page mêlait
// style, balisage et 500 lignes de code, et surtout il fallait pouvoir importer
// `layout.mjs` — partagé avec les tests Node, pour que la règle de
// réconciliation n'existe qu'à un seul endroit.
//
// Servi par la liste blanche de `server.mjs`, jamais par un chemin venu de la
// requête.

import {
  basculerRepli,
  colonneSous,
  deplacer,
  ecrire,
  insertionAvant,
  lire,
  oublier,
  reconcilier,
} from './layout.mjs';

const out = document.getElementById('console');
const editor = document.getElementById('editor');
let running = false;
let state = null;
let drafts = null;
let ouvert = null; // le brouillon affiché dans la boîte d'édition

const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

function log(text, cls) {
  const node = cls ? Object.assign(document.createElement('span'), { className: cls, textContent: text }) : document.createTextNode(text);
  out.appendChild(node);
  out.scrollTop = out.scrollHeight;
}

function setRunning(value) {
  running = value;
  document.querySelectorAll('button[data-action]').forEach((b) => { b.disabled = value || b.dataset.blocked === '1'; });
}

async function run(name, params = {}) {
  if (running) return;
  const action = state.actions[name];

  // La confirmation est côté client ET côté serveur : celle-ci évite un clic
  // malheureux, celle du serveur est la vraie barrière.
  if (action.destructive) {
    const args = Object.values(params).filter(Boolean).join(' ');
    const fiche = state.carnet.find((f) => f.action === name);
    const cout = fiche ? `\n\nCe que ça coûte :\n${fiche.cout}\n\nRetour arrière :\n${fiche.retour}` : '';
    if (!confirm(`Action de production.\n\n${action.label}${args ? ' — ' + args : ''}${cout}\n\nConfirmer ?`)) return;
  }

  setRunning(true);
  out.textContent = '';
  montrerLaSortie();
  log(`$ ${name} ${Object.entries(params).map(([k, v]) => `${k}=${v}`).join(' ')}\n\n`, 'cmd');

  try {
    const res = await fetch('/api/run', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ action: name, ...params, confirm: action.destructive ? true : undefined }),
    });

    if (!res.ok) {
      const { error } = await res.json().catch(() => ({ error: `HTTP ${res.status}` }));
      log(error + '\n', 'exit-bad');
      return;
    }

    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let tail = '';
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      tail += decoder.decode(value, { stream: true });
      // Le code retour arrive en dernière ligne, sous un marqueur : on l'extrait
      // pour le colorer plutôt que de le laisser passer pour de la sortie.
      const at = tail.indexOf('__EXIT__:');
      if (at === -1) { log(tail); tail = ''; continue; }
      log(tail.slice(0, at));
      const code = Number(tail.slice(at + 9).trim());
      log(code === 0 ? '\n✔ terminé\n' : `\n✘ code retour ${code}\n`, code === 0 ? 'exit-ok' : 'exit-bad');
      tail = '';
    }
    if (tail) log(tail);
  } catch (err) {
    log(String(err) + '\n', 'exit-bad');
  } finally {
    setRunning(false);
    refresh();
  }
}

// ---------------------------------------------------------------------------
// L'atelier
// ---------------------------------------------------------------------------

function itemNode(item, pile) {
  const node = document.createElement('div');
  node.className = `item ${pile}`;
  node.innerHTML = `<div>${esc(item.titre ?? item.id)}</div>
    <div class="meta">${esc(item.date ?? '')}</div>
    <div class="meta">${esc(item.kind)} · ${esc(item.id)}</div><div></div>`;
  if (item.raisons?.length) {
    const why = document.createElement('div');
    why.className = 'why';
    why.textContent = item.raisons.join(' · ');
    node.append(why);
  }
  node.onclick = () => ouvrir(item.kind, item.id);
  return node;
}

function renderAtelier() {
  const host = document.getElementById('atelier');
  host.textContent = '';

  if (!drafts) { host.innerHTML = '<p class="dim">chargement…</p>'; return; }

  const piles = [
    ['attend', 'attendent ta décision', 'Schéma valide, aucune règle ne s’y oppose.'],
    ['retenu', 'retenus par une règle', 'La règle est nommée. La lever est une décision éditoriale, pas un clic.'],
    ['casse', 'cassés', 'Ne valident pas leur schéma.'],
  ];

  for (const [cle, titre, aide] of piles) {
    const items = Object.values(drafts.parKind).flatMap((t) => t[cle]);
    if (!items.length && cle === 'casse') continue;
    const bloc = document.createElement('div');
    bloc.className = 'pile';
    bloc.innerHTML = `<h3><b>${items.length}</b> ${titre}</h3><p class="dim" style="margin:-4px 0 8px;font-size:12.5px">${aide}</p>`;
    if (!items.length) {
      bloc.insertAdjacentHTML('beforeend', '<p class="dim" style="margin:0">aucun</p>');
    } else {
      for (const item of items) bloc.append(itemNode(item, cle));
    }
    host.append(bloc);
  }

  const t = drafts.totaux;
  document.getElementById('atelier-count').textContent =
    `${t.attend} en attente · ${t.retenu} retenus${t.casse ? ' · ' + t.casse + ' cassés' : ''}`;
}

function champNode(champ, data, onChange) {
  const wrap = document.createElement('div');
  wrap.className = 'champ';
  wrap.innerHTML = `<label>${esc(champ.field)}</label>`;

  if (champ.type === 'localized') {
    // `en` d'abord : c'est la langue de base et le repli de toutes les autres.
    const langs = ['en', 'fr', ...Object.keys(data[champ.field] ?? {}).filter((l) => l !== 'en' && l !== 'fr')];
    for (const lang of langs) {
      const ligne = document.createElement('div');
      ligne.className = 'lang';
      const area = document.createElement('textarea');
      area.rows = champ.field === 'body' ? 6 : 2;
      area.value = data[champ.field]?.[lang] ?? '';
      area.oninput = () => {
        const bloc = { ...(data[champ.field] ?? {}) };
        if (area.value) bloc[lang] = area.value; else delete bloc[lang];
        onChange(champ.field, bloc);
      };
      ligne.innerHTML = `<span>${lang}</span>`;
      ligne.append(area);
      wrap.append(ligne);
    }
  } else if (champ.values) {
    const select = document.createElement('select');
    for (const v of champ.values) {
      const opt = document.createElement('option');
      opt.value = v; opt.textContent = v;
      if (data[champ.field] === v) opt.selected = true;
      select.append(opt);
    }
    select.onchange = () => onChange(champ.field, select.value);
    wrap.append(select);
  } else {
    const input = document.createElement('input');
    input.value = data[champ.field] ?? '';
    input.oninput = () => onChange(champ.field, input.value);
    wrap.append(input);
  }
  return wrap;
}

async function ouvrir(kind, id) {
  const res = await fetch(`/api/draft/${encodeURIComponent(kind)}/${encodeURIComponent(id)}`);
  if (!res.ok) { alert((await res.json()).error); return; }
  ouvert = await res.json();

  document.getElementById('ed-title').textContent = `${ouvert.kind} · ${ouvert.id}`;

  const faits = document.getElementById('ed-faits');
  faits.innerHTML = '';
  if (ouvert.faits.sourceClaim) {
    faits.insertAdjacentHTML('beforeend', `<p>${esc(ouvert.faits.sourceClaim)}</p>`);
  }
  for (const url of ouvert.faits.sources ?? []) {
    faits.insertAdjacentHTML('beforeend', `<p><a href="${esc(url)}" target="_blank" rel="noreferrer">${esc(url)}</a></p>`);
  }
  faits.insertAdjacentHTML('beforeend',
    '<p class="dim" style="font-size:12px;margin-top:14px">Le fait cite ses sources mot pour mot, marques comprises. '
    + 'Il ne se recopie jamais dans la prose — c’est pourquoi il n’est pas éditable ici.</p>');

  const host = document.getElementById('ed-champs');
  host.textContent = '';
  const onChange = (field, value) => { ouvert.data[field] = value; };
  for (const champ of ouvert.champs) host.append(champNode(champ, ouvert.data, onChange));

  majBlocages();
  editor.showModal();
}

function majBlocages() {
  const msg = document.getElementById('ed-msg');
  const publier = document.getElementById('ed-publish');
  if (ouvert.data.status === 'published') {
    msg.className = 'msg good';
    msg.textContent = 'Déjà publié.';
    publier.disabled = true;
  } else if (ouvert.blocages.length) {
    msg.className = 'msg warn';
    msg.textContent = 'Retenu : ' + ouvert.blocages.join(' · ');
    publier.disabled = true;
  } else {
    msg.className = 'msg good';
    msg.textContent = 'Publiable.';
    publier.disabled = false;
  }
}

async function enregistrer(publier) {
  const msg = document.getElementById('ed-msg');
  const data = publier ? { ...ouvert.data, status: 'published' } : ouvert.data;
  const res = await fetch(`/api/draft/${encodeURIComponent(ouvert.kind)}/${encodeURIComponent(ouvert.id)}`, {
    method: 'PUT',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ data, fingerprint: ouvert.fingerprint }),
  });
  const body = await res.json();
  if (!res.ok) {
    // L'erreur du validateur s'affiche TELLE QUELLE : elle est plus précise que
    // ce qu'on écrirait à sa place.
    msg.className = 'msg bad';
    msg.textContent = body.error;
    return;
  }
  ouvert.data = data;
  ouvert.fingerprint = body.fingerprint;
  msg.className = 'msg good';
  msg.textContent = publier ? 'Publié dans le dépôt — reste à commiter.' : 'Enregistré.';
  await chargerDrafts();
  if (publier) editor.close();
}

document.getElementById('ed-close').onclick = () => editor.close();
document.getElementById('ed-save').onclick = () => enregistrer(false);
document.getElementById('ed-publish').onclick = () => enregistrer(true);

// ---------------------------------------------------------------------------
// La Récolte
// ---------------------------------------------------------------------------

function renderRecolte(reseau) {
  const host = document.getElementById('recolte');
  host.textContent = '';

  const lancer = document.createElement('div');
  lancer.className = 'row narrow';
  lancer.innerHTML = '<label class="dim" style="align-self:center;font-size:12.5px">fenêtre (j)</label>';
  const since = Object.assign(document.createElement('input'), { value: state.actions.recolte.params.since.default });
  const max = Object.assign(document.createElement('input'), { value: state.actions.recolte.params.max.default });
  const bouton = document.createElement('button');
  bouton.textContent = 'Lancer la Récolte';
  bouton.dataset.action = 'recolte';
  bouton.onclick = () => run('recolte', { since: since.value.trim(), max: max.value.trim() });
  lancer.append(since, Object.assign(document.createElement('label'), { className: 'dim', style: 'align-self:center;font-size:12.5px', textContent: 'plafond' }), max, bouton);
  host.append(lancer);

  const etat = document.createElement('div');
  const r = reseau?.recolte;
  const badge = document.getElementById('recolte-verdict');

  if (!r) {
    etat.innerHTML = '<p class="dim">état du dernier run : chargement…</p>';
    badge.textContent = '—';
  } else if (r.indisponible) {
    // Une carte ne ment JAMAIS par omission : elle dit ce qui manque.
    etat.innerHTML = `<p class="warn">${esc(r.indisponible)}</p>`;
    badge.textContent = 'indisponible';
    badge.className = 'warn';
  } else {
    const couleur = { 'complète': 'good', partielle: 'warn', 'échec': 'bad', 'indéterminé': 'warn', 'en cours': 'dim' }[r.verdict] ?? 'dim';
    badge.textContent = r.verdict;
    badge.className = couleur;
    const etapes = (r.etapes ?? [])
      .map((e) => `<tr><td>${e.vu ? '<span class="good">✔</span>' : '<span class="bad">✘</span>'}</td>
        <td>${esc(e.etape)}</td><td class="dim">${esc(e.resume ?? 'muette')}</td></tr>`)
      .join('');
    etat.innerHTML = `
      <p style="margin:0"><span class="${couleur}">${esc(r.verdict)}</span>
        <span class="dim">· ${esc(r.run?.createdAt?.slice(0, 16).replace('T', ' ') ?? '')}
        · <a href="${esc(r.run?.url ?? '#')}" target="_blank" rel="noreferrer" style="color:var(--cyan)">le run</a></span></p>
      <table style="margin-top:8px">${etapes}</table>
      <p class="dim" style="font-size:12px;margin:10px 0 0">
        Le verdict vient du JOURNAL, pas du statut : une étape en continue-on-error
        est rapportée « success » même sortie en code 1.</p>`;
  }
  host.append(etat);
}

// ---------------------------------------------------------------------------
// Le carnet
// ---------------------------------------------------------------------------

function renderCarnet() {
  const host = document.getElementById('carnet');
  host.textContent = '';
  for (const fiche of state.carnet) {
    const action = state.actions[fiche.action];
    const node = document.createElement('div');
    node.className = 'fiche';
    node.innerHTML = `<div class="head"><div class="name">${esc(fiche.label)}</div></div>
      <p style="margin:6px 0 0;font-size:13px">${esc(fiche.quoi)}</p>
      <dl>
        <dt>coûte</dt><dd>${esc(fiche.cout)}</dd>
        <dt>vérifier</dt><dd>${esc(fiche.verification)}</dd>
        <dt>revenir</dt><dd>${esc(fiche.retour)}</dd>
      </dl>`;

    const head = node.querySelector('.head');
    const params = Object.keys(action.params ?? {});
    if (params.length) {
      const ligne = document.createElement('div');
      ligne.className = 'row';
      const input = document.createElement('input');
      input.placeholder = params[0];
      input.style.width = '190px';
      const bouton = document.createElement('button');
      bouton.textContent = 'Appliquer';
      bouton.className = 'danger';
      bouton.dataset.action = fiche.action;
      bouton.onclick = () => {
        const v = input.value.trim();
        if (!v) { input.focus(); return; }
        run(fiche.action, { [params[0]]: v });
      };
      ligne.append(input, bouton);
      head.append(ligne);
    } else {
      const bouton = document.createElement('button');
      bouton.textContent = 'Appliquer';
      if (action.destructive) bouton.className = 'danger';
      bouton.dataset.action = fiche.action;
      bouton.onclick = () => run(fiche.action);
      head.append(bouton);
    }
    host.append(node);
  }
}

// ---------------------------------------------------------------------------
// Le reste
// ---------------------------------------------------------------------------

function actionRow(name, action) {
  const row = document.createElement('div');
  row.className = 'action';

  const tags = [
    action.writesRepo ? '<span class="tag repo">dépôt</span>' : '',
    action.destructive ? '<span class="tag prod">prod</span>' : '',
    action.slow ? '<span class="tag slow">long</span>' : '',
  ].join('');
  row.innerHTML = `<div class="name">${esc(action.label)}${tags}</div>`;

  const blocked = action.needsCredentials && !state.credentials;

  if (action.needsID) {
    const wrap = document.createElement('div');
    wrap.className = 'row';
    wrap.style.gridColumn = '1 / -1';
    const input = document.createElement('input');
    input.placeholder = 'identifiant';
    input.spellcheck = false;
    const button = document.createElement('button');
    button.textContent = action.label;
    button.className = 'danger';
    button.dataset.action = name;
    if (blocked) button.dataset.blocked = '1';
    button.onclick = () => {
      const id = input.value.trim();
      if (!id) { input.focus(); return; }
      run(name, { id });
    };
    wrap.append(input, button);
    row.append(wrap);
  } else {
    const button = document.createElement('button');
    button.textContent = 'Lancer';
    button.dataset.action = name;
    if (action.destructive) button.className = 'danger';
    if (blocked) button.dataset.blocked = '1';
    button.onclick = () => run(name);
    row.append(button);
  }

  if (action.hint || blocked) {
    const hint = document.createElement('div');
    hint.className = 'hint';
    hint.textContent = blocked ? state.credentialsMessage : action.hint;
    row.append(hint);
  }
  return row;
}

function renderPills(reseau) {
  const { credentials, socles, git, brouillons } = state;
  const pills = [];

  if (brouillons.indisponible) pills.push([esc(brouillons.indisponible), 'bad']);
  else pills.push([`<b>${brouillons.totaux.attend}</b> attendent ta décision`, brouillons.totaux.attend ? 'warn' : 'ok']);

  if (git.indisponible) pills.push([esc(git.indisponible), 'bad']);
  else {
    pills.push([`branche <b>${esc(git.branche)}</b> · ${esc(git.commit)}`, '']);
    pills.push([git.modifies ? `<b>${git.modifies}</b> fichier(s) non committé(s)` : 'arbre propre', git.modifies ? 'warn' : 'ok']);
  }

  if (socles.indisponible) pills.push([esc(socles.indisponible), 'bad']);
  else pills.push([socles.aJour ? 'socles à jour' : 'socles en retard sur content/', socles.aJour ? 'ok' : 'bad']);

  pills.push([credentials ? 'credentials Supabase' : 'pas de credentials', credentials ? 'ok' : 'warn']);

  const f = reseau?.fonctions;
  if (f && !f.indisponible) pills.push([f.derivees.length ? `<b>${f.derivees.length}</b> fonction(s) dérivée(s)` : 'fonctions à jour', f.derivees.length ? 'bad' : 'ok']);

  document.getElementById('pills').innerHTML = pills.map(([html, cls]) => `<span class="pill ${cls}">${html}</span>`).join('');
}

function renderInventory() {
  const inv = state.inventaire;
  const host = document.getElementById('inventory');
  if (inv.indisponible) { host.innerHTML = `<p class="bad">${esc(inv.indisponible)}</p>`; return; }

  const rows = Object.entries(inv.kinds)
    .map(([kind, k]) => `<tr><td>content/${esc(kind)}</td><td class="num">${k.total}</td>
      <td class="num">${k.published}</td><td class="num ${k.draft ? '' : 'dim'}">${k.draft}</td></tr>`)
    .join('');

  const challenges = inv.collections.filter((c) => c.isChallenge);
  const withTotal = challenges.filter((c) => c.expectedCount != null);
  const collectionRows = inv.collections
    .map((c) => {
      const kind = !c.isChallenge
        ? '<span class="dim">calque</span>'
        : c.expectedCount != null
          ? `défi · ${c.expectedCount}`
          : '<span class="warn">défi · total inconnu</span>';
      return `<tr><td>${esc(c.id)}</td><td>${esc(c.title.fr ?? c.title.en)}</td><td>${kind}</td></tr>`;
    })
    .join('');

  host.innerHTML = `
    <table>
      <thead><tr><th>Répertoire</th><th class="num">Total</th><th class="num">Publiés</th><th class="num">Brouillons</th></tr></thead>
      <tbody>${rows}</tbody>
    </table>
    <p class="dim" style="margin:14px 0 6px;font-size:13px">
      ${inv.collections.length} collections · ${challenges.length} défis, dont ${withTotal.length} à total connu
    </p>
    <table>
      <thead><tr><th>Collection</th><th>Titre</th><th>Nature</th></tr></thead>
      <tbody>${collectionRows}</tbody>
    </table>`;
}

function renderActions() {
  for (const group of ['checks', 'local', 'prod', 'moderation']) {
    const host = document.getElementById('g-' + group);
    host.textContent = '';
    for (const [name, action] of Object.entries(state.actions)) {
      if (action.group === group) host.append(actionRow(name, action));
    }
  }
  setRunning(running);
}

async function chargerDrafts() {
  drafts = await (await fetch('/api/drafts')).json();
  renderAtelier();
}

async function refresh() {
  // Les cartes instantanées d'abord : elles ne demandent que le disque, et
  // c'est ce qu'on veut voir sans attendre un jeton ou un réseau.
  state = await (await fetch('/api/state')).json();
  renderPills(null);
  renderInventory();
  renderActions();
  renderCarnet();
  renderRecolte(null);
  chargerDrafts();

  // Puis le réseau, carte par carte. Une carte lente ne retarde plus rien.
  fetch('/api/state/network').then((r) => r.json()).then((reseau) => {
    renderPills(reseau);
    renderRecolte(reseau);
  }).catch((err) => {
    document.getElementById('recolte-verdict').textContent = 'illisible';
  });
}

// ---------------------------------------------------------------------------
// La disposition : ranger les sections, les replier, s'en souvenir
// ---------------------------------------------------------------------------

const colonnes = [...document.querySelectorAll('.colonne')];
const panneaux = new Map(
  [...document.querySelectorAll('section[data-panneau]')].map((s) => [s.dataset.panneau, s]),
);

// Le CODE fait autorité sur ce qui EXISTE, le rangement mémorisé seulement sur
// l'ORDRE. Sans ça, une section ajoutée un jour resterait invisible chez qui a
// déjà rangé sa page — et rien ne le signalerait.
let disposition = lire(localStorage, [...panneaux.keys()]);

function appliquerDisposition() {
  disposition.colonnes.forEach((ids, index) => {
    const colonne = colonnes[index];
    // `append` DÉPLACE un nœud déjà présent : réordonner ne détruit donc rien,
    // et les écouteurs comme l'état de défilement des sections survivent.
    for (const id of ids) colonne.append(panneaux.get(id));
  });
  for (const [id, section] of panneaux) {
    section.classList.toggle('repliee', disposition.replies.includes(id));
  }
  document.getElementById('reinit').hidden = estLeDefaut();
}

function estLeDefaut() {
  return JSON.stringify(disposition) === JSON.stringify(reconcilier(null, [...panneaux.keys()]));
}

function enregistrerDisposition(suivante) {
  disposition = suivante;
  ecrire(localStorage, disposition);
  appliquerDisposition();
}

/** Prépare chaque en-tête : chevron, poignée, repli. */
function armerLesEntetes() {
  for (const [id, section] of panneaux) {
    const h2 = section.querySelector(':scope > h2');

    // Le titre part dans un conteneur précédé du chevron — mais SANS le `<em>`
    // compteur, qui doit rester à droite : l'en-tête est un flex en
    // `space-between`, et tout emballer ensemble collerait le compteur au titre.
    const compteur = h2.querySelector(':scope > em');
    const titre = document.createElement('span');
    titre.className = 'titre';
    titre.append(Object.assign(document.createElement('span'), { className: 'chevron', textContent: '▾' }));
    for (const noeud of [...h2.childNodes]) {
      if (noeud !== compteur) titre.append(noeud);
    }
    h2.prepend(titre);

    h2.addEventListener('pointerdown', (e) => saisir(e, id, section, h2));
  }
}

// ---------------------------------------------------------------------------
// Le glissement, aux ÉVÉNEMENTS DE POINTEUR et non au glisser-déposer HTML5
//
// Le natif a été essayé le 2026-08-07 et écarté, pour trois raisons dont une
// seule aurait suffi :
//
//   1. Il n'est pas pilotable. Sous Chromium, un `dragstart` déclenché par des
//      événements synthétiques part puis rend la main à la boucle de glissement
//      de l'OS, qui ne reçoit jamais les mouvements : on observe `dragstart` puis
//      `dragend`, sans le moindre `dragover`. Un contrôle qu'on ne peut pas
//      exercer est un contrôle auquel on ne peut pas se fier.
//   2. Il oblige à poser puis retirer `draggable` autour de chaque appui, sans
//      quoi le texte des sections devient insélectionnable.
//   3. Il fait dépendre la distinction clic/glissement d'un détail — « aucun
//      `click` n'est émis après un `dragstart` » — au lieu d'un seuil qu'on
//      choisit.
//
// Ici : en dessous de SEUIL pixels, c'est un clic, donc un repli. Au-delà, c'est
// un rangement. La règle est explicite, et elle se teste.
// ---------------------------------------------------------------------------

const SEUIL = 5;

function effacerLesReperes() {
  for (const n of document.querySelectorAll('.cible-avant, .cible-fin')) {
    n.classList.remove('cible-avant', 'cible-fin');
  }
  for (const c of colonnes) c.classList.remove('survol');
}

/** Devant quelle section le pointeur veut-il déposer ? `null` = à la fin.
 *
 *  La section en cours de glissement est exclue : elle servirait sinon de repère
 *  à elle-même, et le geste bloquerait sur sa propre position. */
function cibleDans(colonne, y) {
  const visibles = [...colonne.querySelectorAll(':scope > section')]
    .filter((s) => !s.classList.contains('glisse'));
  const at = insertionAvant(y, visibles.map((s) => s.getBoundingClientRect()));
  return at === null ? null : visibles[at];
}

/** L'index de la colonne sous le pointeur. La géométrie vit dans `layout.mjs`,
 *  où elle se teste sans navigateur. */
function colonneVisee(x) {
  return colonneSous(x, colonnes.map((c) => c.getBoundingClientRect()));
}

function saisir(depart, id, section, h2) {
  // Bouton gauche seul : un clic droit ouvre le menu contextuel, il ne range rien.
  if (depart.button !== 0) return;
  depart.preventDefault();

  let glisse = false;
  h2.setPointerCapture(depart.pointerId);

  const bouger = (e) => {
    if (!glisse) {
      if (Math.hypot(e.clientX - depart.clientX, e.clientY - depart.clientY) < SEUIL) return;
      glisse = true;
      section.classList.add('glisse');
    }
    effacerLesReperes();
    const colonne = colonnes[colonneVisee(e.clientX)];
    colonne.classList.add('survol');
    const avant = cibleDans(colonne, e.clientY);
    if (avant) avant.classList.add('cible-avant');
    else colonne.querySelector(':scope > section:last-of-type')?.classList.add('cible-fin');
  };

  const lacher = (e) => {
    h2.removeEventListener('pointermove', bouger);
    h2.removeEventListener('pointerup', lacher);
    h2.removeEventListener('pointercancel', lacher);
    h2.releasePointerCapture?.(depart.pointerId);
    section.classList.remove('glisse');

    if (!glisse) {
      effacerLesReperes();
      enregistrerDisposition(basculerRepli(disposition, id));
      return;
    }
    const index = colonneVisee(e.clientX);
    const avant = cibleDans(colonnes[index], e.clientY);
    effacerLesReperes();
    enregistrerDisposition(deplacer(disposition, id, index, avant?.dataset.panneau ?? null));
  };

  h2.addEventListener('pointermove', bouger);
  h2.addEventListener('pointerup', lacher);
  // Un pointeur perdu (fenêtre qui perd le focus, geste interrompu) doit relâcher
  // proprement, sinon la section reste fantôme et la page à moitié en glissement.
  h2.addEventListener('pointercancel', lacher);
}

document.getElementById('reinit').onclick = () => {
  oublier(localStorage);
  disposition = lire(localStorage, [...panneaux.keys()]);
  appliquerDisposition();
};

/**
 * La Sortie se déplie et vient sous les yeux quand une commande part.
 *
 * Sans ça, on clique un bouton dans une colonne et le résultat s'écrit dans
 * l'autre, parfois hors écran — la page fait 3 600 px de haut. Un résultat qu'on
 * ne voit pas est un résultat qu'on n'a pas.
 *
 * Le repli n'est PAS mémorisé au passage : déplier pour montrer un résultat est
 * un geste de la console, pas une préférence de l'utilisateur. L'écraser dans
 * `localStorage` reviendrait à décider à sa place.
 */
function montrerLaSortie() {
  const sortie = panneaux.get('sortie');
  if (!sortie) return;
  sortie.classList.remove('repliee');
  sortie.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}

armerLesEntetes();
appliquerDisposition();

refresh();
