// Le script de la console. Sorti d'`index.html` le 2026-08-07 : la page mêlait
// style, balisage et 500 lignes de code, et surtout il fallait pouvoir importer
// `layout.mjs` — partagé avec les tests Node, pour que la règle de
// réconciliation n'existe qu'à un seul endroit.
//
// Servi par la liste blanche de `server.mjs`, jamais par un chemin venu de la
// requête.

import {
  NB_COLONNES,
  ONGLETS,
  basculerRepli,
  colonneSous,
  deplacer,
  ecrire,
  insertionAvant,
  lire,
  oublier,
  reconcilier,
  toutDeplier,
} from './layout.mjs';
// Les graphes des métriques Supabase et l'infobulle viennent de `tools/monitor/`,
// PARTAGÉS tels quels avec le moniteur du Raspberry Pi. Servis par la liste
// blanche sous `/graphes.mjs`.
import { armerBulle, esc, installerBulle, renderFile, renderSante } from './graphes.mjs';
// Ce que chaque onglet dit de lui-même. Module PUR — il reçoit l'état et rend
// des objets, donc la règle « aucun indicateur ne ment par omission » se teste
// sans navigateur.
import { indicateurs } from './indicateurs.mjs';

const out = document.getElementById('console');
const editor = document.getElementById('editor');
let running = false;
let state = null;
let drafts = null;
let metriques = null; // l'instantané Supabase, ou la phrase qui dit pourquoi non
let livraison = null; // ce que la livraison ferait, ou la phrase qui dit pourquoi non
let reseau = null;    // récolte, app_config, dérive des fonctions — arrive après
let ouvert = null; // le brouillon affiché dans la boîte d'édition

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

/** L'hôte d'une URL, ou `null` si elle est illisible.
 *
 *  L'URL entière ferait trois lignes sur la carte et n'apprendrait rien de plus :
 *  ce qu'on veut savoir d'un coup d'œil, c'est DE QUI ça vient. L'adresse
 *  complète part dans l'infobulle du lien. */
function hoteDe(url) {
  try {
    return new URL(url).host.replace(/^www\./, '');
  } catch {
    return null;
  }
}

function itemNode(item, pile) {
  const node = document.createElement('div');
  node.className = `item ${pile}`;
  node.innerHTML = `<div>${esc(item.titre ?? item.id)}</div>
    <div class="meta">${esc(item.date ?? '')}</div>
    <div class="meta">${esc(item.kind)} · ${esc(item.id)}</div><div></div>`;

  // Le lien vers l'article d'origine, sur la carte. Relire une actu, c'est
  // presque toujours la comparer à ce dont elle sort ; l'atteindre demandait
  // jusqu'ici d'ouvrir l'éditeur, donc deux clics par vérification.
  const hote = item.source ? hoteDe(item.source) : null;
  if (hote) {
    const lien = document.createElement('a');
    lien.className = 'source';
    lien.href = item.source;
    lien.target = '_blank';
    lien.rel = 'noreferrer';
    lien.textContent = hote;
    lien.title = item.source;
    // Sans ça, ouvrir la source ouvrirait AUSSI la fiche derrière — la carte
    // entière est cliquable.
    lien.onclick = (e) => e.stopPropagation();
    node.lastElementChild.append(lien);
  }

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
  // Le champ est retrouvable depuis l'extérieur : « Publier » doit pouvoir
  // remettre le sélecteur de statut en accord avec ce qu'il vient d'écrire,
  // sinon la page affiche `draft` sur un item qu'elle vient de publier.
  wrap.dataset.champ = champ.field;
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
  const onChange = (field, value) => {
    ouvert.data[field] = value;
    // Changer le statut change ce que le pied doit dire — et surtout si
    // « Écarter » a encore le droit d'exister.
    if (field === 'status') majBlocages();
  };
  for (const champ of ouvert.champs) host.append(champNode(champ, ouvert.data, onChange));

  majBlocages();
  editor.showModal();
}

/** Remet le sélecteur de statut en accord avec les données.
 *
 *  Appelé après « Publier », qui écrit `published` sans passer par le sélecteur.
 *  Sans ça la page afficherait `draft` sur un item qu'elle vient de publier —
 *  et le prochain enregistrement le dépublierait sans que personne l'ait demandé. */
function synchroniserStatut() {
  const select = document.querySelector('#ed-champs [data-champ="status"] select');
  if (select) select.value = ouvert.data.status;
}

function majBlocages() {
  const msg = document.getElementById('ed-msg');
  const publier = document.getElementById('ed-publish');
  const ecarter = document.getElementById('ed-delete');

  // Un item publié ne s'écarte pas : son fragment est déjà servi aux clients, et
  // supprimer le fichier n'enlèverait que la trace de ce qu'on a publié. Le
  // serveur refuse aussi — ce bouton n'est que la politesse d'avance.
  ecarter.disabled = ouvert.data.status !== 'draft';
  ecarter.title = ecarter.disabled
    ? 'Un item publié ne s’écarte pas : le repasser en `draft`, republier, puis écarter.'
    : 'Supprime le fichier. La suppression apparaît dans la Livraison, donc dans une PR relue.';

  if (ouvert.data.status === 'published') {
    msg.className = 'msg good';
    msg.textContent = 'Publié.';
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
  synchroniserStatut();
  majBlocages();
  msg.className = 'msg good';
  msg.textContent = publier
    ? 'Publié dans le dépôt — reste à commiter.'
    : `Enregistré en \`${data.status}\`.`;
  await chargerDrafts();
  // Publier un brouillon change ce qui partirait : la livraison le voit tout de suite.
  chargerLivraison();
  if (publier) editor.close();
}

/** Écarte le brouillon ouvert.
 *
 *  La confirmation nomme le TITRE et pas l'identifiant : `news_4c5bfa38` ne dit
 *  rien, et c'est exactement dans ce vide qu'on confirme la suppression du
 *  mauvais item. */
async function ecarter() {
  const msg = document.getElementById('ed-msg');
  const titre = ouvert.data.title?.fr ?? ouvert.data.title?.en ?? ouvert.id;
  if (!confirm(`Écarter ce brouillon ?\n\n« ${titre} »\n\nLe fichier est supprimé du dépôt. `
    + 'La suppression apparaîtra dans la Livraison, donc dans une pull request relue.')) return;

  const res = await fetch(`/api/draft/${encodeURIComponent(ouvert.kind)}/${encodeURIComponent(ouvert.id)}`, {
    method: 'DELETE',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ fingerprint: ouvert.fingerprint }),
  });
  const body = await res.json();
  if (!res.ok) {
    msg.className = 'msg bad';
    msg.textContent = body.error;
    return;
  }
  editor.close();
  await chargerDrafts();
  chargerLivraison();
}

document.getElementById('ed-close').onclick = () => editor.close();
document.getElementById('ed-save').onclick = () => enregistrer(false);
document.getElementById('ed-publish').onclick = () => enregistrer(true);
document.getElementById('ed-delete').onclick = ecarter;

// ---------------------------------------------------------------------------
// La référence des fonctions
//
// Le même texte que `cli.js doc`, servi par `/api/doc` et rendu en HTML côté
// serveur — la page ne convertit pas de markdown, elle affiche ce qu'on lui
// donne. Une seule source, deux sorties.
// ---------------------------------------------------------------------------

const reference = document.getElementById('reference');
/** Chargée une fois par session. Le fichier ne bouge pas pendant qu'on lit. */
let referenceChargee = false;

async function ouvrirReference() {
  const texte = document.getElementById('ref-texte');
  const sommaire = document.getElementById('ref-sommaire');
  const msg = document.getElementById('ref-msg');

  // Ouvrir D'ABORD : sur un premier appel, attendre la réponse avant d'ouvrir
  // laisse le bouton sans effet visible pendant tout le chargement, ce qui se
  // lit comme un clic perdu et invite à recliquer.
  reference.showModal();
  if (referenceChargee) return;

  texte.textContent = 'Chargement…';
  try {
    const r = await fetch('/api/doc');
    const d = await r.json();
    if (d.indisponible) {
      // Comme les cartes du tableau de bord : dire pourquoi, jamais rester vide.
      texte.textContent = '';
      msg.textContent = d.indisponible;
      return;
    }

    texte.innerHTML = d.html;
    sommaire.textContent = '';
    for (const s of d.sections) {
      const a = document.createElement('a');
      a.textContent = s.titre;
      a.href = '#';
      a.onclick = (e) => {
        e.preventDefault();
        // Le titre porte son numéro : on retrouve le `h2` par son texte plutôt
        // que par un identifiant qu'il faudrait fabriquer des deux côtés.
        const cible = [...texte.querySelectorAll('h2')].find((h) => h.textContent.trim() === s.titre);
        cible?.scrollIntoView({ behavior: 'smooth', block: 'start' });
      };
      sommaire.append(a);
    }
    msg.textContent = '';
    referenceChargee = true;
  } catch (err) {
    texte.textContent = '';
    msg.textContent = `référence injoignable — ${err.message}`;
  }
}

document.getElementById('reference-ouvrir').onclick = ouvrirReference;
document.getElementById('ref-close').onclick = () => reference.close();

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
  for (const group of ['checks', 'local', 'livraison', 'prod', 'moderation']) {
    const host = document.getElementById('g-' + group);
    host.textContent = '';
    for (const [name, action] of Object.entries(state.actions)) {
      if (action.group === group) host.append(actionRow(name, action));
    }
  }
  setRunning(running);
}


// ---------------------------------------------------------------------------
// Les graphes de la file de revue
//
// La forme suit le TRAVAIL de la donnée, pas l'inverse :
//
//   - « combien attendent »  → un NOMBRE, pas un graphe à une barre ;
//   - « comment ça se répartit » → part-à-tout, donc barre empilée ;
//   - « depuis quand »       → tranches d'âge, ORDINALES : une seule teinte en
//     rampe monotone, jamais des couleurs d'identité ;
//   - « pourquoi retenus »   → catégories NOMINALES : toutes la même teinte.
//     Les colorer par leur valeur dépenserait le canal d'identité pour re-dire
//     ce que la longueur de la barre montre déjà.
//
// Les trois couleurs de statut (attend/retenu/cassé) sont à ΔE 6,6 en
// deutéranopie — dans la bande plancher, autorisée UNIQUEMENT avec un encodage
// secondaire. D'où des étiquettes directes toujours présentes, jamais au survol :
// elles ne sont pas décoratives, elles sont la condition de légalité.
// ---------------------------------------------------------------------------

const RAMPE_AGE = ['--age-1', '--age-2', '--age-3', '--age-4', '--age-5'];
const PILES = [
  { cle: 'attend', label: 'attendent ta décision', couleur: 'var(--lime)' },
  { cle: 'retenu', label: 'retenus par une règle', couleur: 'var(--amber)' },
  { cle: 'casse', label: 'cassés', couleur: 'var(--red)' },
];

// L'infobulle est partagée par les deux familles de graphes — celle des
// brouillons, ci-dessous, et celle des métriques, dans `graphes.mjs`. Une seule
// implémentation, celle du module partagé.
installerBulle(document.getElementById('bulle'));

function renderGraphes() {
  const host = document.getElementById('graphes');
  const note = document.getElementById('graphes-note');
  host.textContent = '';

  if (!drafts?.stats) { host.innerHTML = '<p class="dim">chargement…</p>'; return; }
  const s = drafts.stats;
  const total = PILES.reduce((n, p) => n + (s.totaux[p.cle] ?? 0), 0);
  note.textContent = `${total} brouillon${total > 1 ? 's' : ''}`;

  if (total === 0) {
    host.innerHTML = '<p class="dim">Aucun brouillon : la file est vide.</p>';
    return;
  }

  // --- Le nombre que la vue met en avant. Un seul par écran. ---------------
  const hero = document.createElement('div');
  const a = s.totaux.attend ?? 0;
  hero.innerHTML = `<div class="hero"><span class="n">${a}</span>
      <span class="quoi">attendent ta décision</span></div>`;
  const sous = document.createElement('p');
  sous.className = 'hero-sous';
  sous.textContent = s.plusAncien
    ? `Le plus ancien depuis le ${s.plusAncien.date} — ${s.plusAncien.jours} jour${s.plusAncien.jours > 1 ? 's' : ''}.`
    : 'Aucun n’est daté.';
  hero.append(sous);
  host.append(hero);

  // --- Répartition : part-à-tout, donc barre empilée ------------------------
  const rep = document.createElement('div');
  rep.className = 'graphe';
  rep.innerHTML = '<h4>Répartition</h4>';
  const barre = document.createElement('div');
  barre.className = 'empilee';
  for (const p of PILES) {
    const n = s.totaux[p.cle] ?? 0;
    if (!n) continue;
    const seg = document.createElement('span');
    seg.style.cssText = `flex:${n};background:${p.couleur}`;
    armerBulle(seg, `${n} ${p.label}`);
    barre.append(seg);
  }
  rep.append(barre);

  // La légende est TOUJOURS là dès deux séries : c'est le canal d'identité
  // fiable. Le chiffre y est écrit — l'encodage secondaire qu'exige l'écart CVD.
  const legende = document.createElement('div');
  legende.className = 'legende';
  legende.innerHTML = PILES
    .map((p) => `<span><i style="background:${p.couleur}"></i><b>${s.totaux[p.cle] ?? 0}</b> ${p.label}</span>`)
    .join('');
  rep.append(legende);
  host.append(rep);

  // --- Âge : tranches ORDINALES, rampe à une seule teinte -------------------
  if (a > 0) {
    const age = document.createElement('div');
    age.className = 'graphe';
    age.innerHTML = '<h4>Depuis quand ils attendent</h4>'
      + '<p class="sous">Brouillons prêts à publier, par ancienneté.</p>';
    const max = Math.max(...s.tranches.map((t) => t.n), 1);
    const cols = document.createElement('div');
    cols.className = 'colonnes';
    s.tranches.forEach((t, i) => {
      const cel = document.createElement('div');
      const val = document.createElement('span');
      val.className = t.n ? 'val' : 'val zero';
      val.textContent = String(t.n);
      const fut = document.createElement('div');
      fut.className = 'fut';
      // La hauteur part de la ligne de base et se termine par un bout arrondi de
      // 4 px ; une tranche vide garde 2 px pour que sa place reste lisible.
      fut.style.height = t.n ? `${Math.max(6, (t.n / max) * 78)}px` : '2px';
      fut.style.background = t.n ? `var(${RAMPE_AGE[i]})` : 'var(--line)';
      armerBulle(cel, `${t.n} brouillon${t.n > 1 ? 's' : ''} — ${t.label}`);
      cel.append(val, fut);
      cols.append(cel);
    });
    const axe = document.createElement('div');
    axe.className = 'axe-x';
    axe.innerHTML = s.tranches.map((t) => `<span>${esc(t.label)}</span>`).join('');
    age.append(cols, axe);
    host.append(age);
  }

  // --- Motifs : catégories NOMINALES, toutes la même teinte ----------------
  if (s.motifs.length) {
    const mot = document.createElement('div');
    mot.className = 'graphe';
    mot.innerHTML = '<h4>Pourquoi les autres sont retenus</h4>'
      + '<p class="sous">Un item peut l’être pour plusieurs motifs.</p>';
    const max = Math.max(...s.motifs.map((m) => m.n), 1);
    for (const m of s.motifs) {
      const ligne = document.createElement('div');
      ligne.className = 'motif';
      ligne.innerHTML = `<span class="nom">${esc(m.motif)}</span><span class="val">${m.n}</span>
        <span class="piste"><span style="width:${(m.n / max) * 100}%"></span></span>`;
      armerBulle(ligne, `${m.n} item${m.n > 1 ? 's' : ''} — ${m.motif}`, m.exemples[0]);
      mot.append(ligne);
    }
    host.append(mot);
  }
}

async function chargerDrafts() {
  drafts = await (await fetch('/api/drafts')).json();
  renderAtelier();
  renderGraphes();
  majIndicateurs();
}

// ---------------------------------------------------------------------------
// La livraison
//
// Le panneau MONTRE ce que le bouton ferait, avant qu'on appuie. Un bouton dont
// l'effet ne se voit qu'après est un bouton qu'on n'appuie pas — et celui-ci
// pousse une branche et ouvre une pull request.
//
// Il montre surtout ce que la livraison N'EMPORTE PAS. Jusqu'au 2026-08-08, une
// modification de code en attente restait dans l'arbre de travail sans qu'une
// ligne le dise : on ouvrait une PR en croyant l'arbre propre.
// ---------------------------------------------------------------------------

function renderLivraison() {
  const hote = document.getElementById('livraison-apercu');
  const note = document.getElementById('livraison-note');
  hote.textContent = '';

  if (!livraison) {
    note.textContent = '—';
    hote.innerHTML = '<p class="dim">chargement…</p>';
    return;
  }
  if (livraison.indisponible) {
    note.textContent = 'indisponible';
    hote.innerHTML = `<p class="indispo">${esc(livraison.indisponible)}</p>`;
    return;
  }

  const { changements, details, reste, titre, branche, enAvance } = livraison;
  const morceaux = [];

  if (!changements.length) {
    note.textContent = 'rien à livrer';
    morceaux.push('<p class="dim">Aucun fichier de contenu modifié. '
      + 'Publier un brouillon depuis l’atelier, puis revenir.</p>');
  } else {
    note.textContent = `${changements.length} fichier${changements.length > 1 ? 's' : ''}`;
    morceaux.push(
      `<p class="dim" style="margin:0 0 8px">Branche <code>${esc(branche)}</code><br>`
      + `Titre <code>${esc(titre)}</code></p>`,
    );
    for (const c of changements) {
      morceaux.push(
        `<div class="item attend"><span class="name">${esc(c.id)}</span>`
        + `<span class="meta">${esc(details[c.chemin] ?? '')}</span>`
        + `<span class="meta" style="grid-column:1/-1">${esc(c.chemin)}</span></div>`,
      );
    }
  }

  // Ce qui reste. En AMBRE et non en gris : ce n'est pas un détail, c'est la
  // question « ai-je oublié quelque chose ».
  if (reste?.laisse?.length) {
    morceaux.push(
      `<p class="warn" style="margin:12px 0 0">⚠ ${reste.laisse.length} modification`
      + `${reste.laisse.length > 1 ? 's' : ''} ne part${reste.laisse.length > 1 ? 'ent' : ''} pas :</p>`
      // Trois noms, puis un décompte. Le SIGNAL est « il en reste », pas la
      // liste : huit lignes repoussaient le bouton sous la ligne de flottaison
      // d'un écran de portable, ce qui rendait la section moins utile que le
      // détail qu'elle affichait. La liste complète est dans la répétition.
      + `<p class="dim" style="margin:2px 0 0;font-size:12.5px">`
      + reste.laisse.slice(0, 3).map((c) => esc(c)).join('<br>')
      + (reste.laisse.length > 3 ? `<br>… et ${reste.laisse.length - 3} autres` : '')
      + '<br>Elles restent dans l’arbre de travail — à commiter à part si c’est voulu.</p>',
    );
  }
  // L'inbox est une RÈGLE tenue, pas un oubli : elle ne prend pas la couleur de
  // l'avertissement, sinon on apprendrait à ignorer l'avertissement.
  if (reste?.exclu?.length) {
    morceaux.push(
      `<p class="dim" style="margin:8px 0 0;font-size:12.5px">${reste.exclu.length} `
      + 'fichier(s) d’inbox exclus à dessein : du texte tiers, jamais commité.</p>',
    );
  }
  if (enAvance?.length) {
    morceaux.push(
      '<p class="warn" style="margin:12px 0 0">⚠ la branche courante a des commits que '
      + '<code>main</code> n’a pas — ils seront DANS la pull request :</p>'
      + `<p class="dim" style="margin:2px 0 0;font-size:12.5px">`
      + enAvance.slice(0, 3).map((l) => esc(l)).join('<br>')
      + (enAvance.length > 3 ? `<br>… et ${enAvance.length - 3} autres` : '')
      + '</p>',
    );
  }

  hote.innerHTML = morceaux.join('');
}

async function chargerLivraison() {
  try {
    livraison = await (await fetch('/api/livraison')).json();
  } catch (err) {
    livraison = { indisponible: `la console ne répond pas — ${err.message}` };
  }
  renderLivraison();
  majIndicateurs();
}

// ---------------------------------------------------------------------------
// Les métriques de production
// ---------------------------------------------------------------------------

function renderMetriquesConsole() {
  renderFile(document.getElementById('communaute'), metriques);
  renderSante(document.getElementById('sante'), metriques);

  // L'en-tête de section porte le chiffre, pour qu'il se lise sans déplier ni
  // changer d'onglet. Une section repliée doit dire ce qu'elle cache.
  const note = document.getElementById('communaute-note');
  if (!metriques) note.textContent = '—';
  else if (metriques.indisponible) note.textContent = 'indisponible';
  else {
    const m = metriques.instantane.moderation;
    note.textContent = m.enAttente
      ? `${m.enAttente} en attente${m.signales ? ` · ${m.signales} signalée${m.signales > 1 ? 's' : ''}` : ''}`
      : 'file vide';
  }
}

async function chargerMetriques() {
  try {
    metriques = await (await fetch('/api/state/supabase')).json();
  } catch (err) {
    // Le serveur local injoignable, pas Supabase : la distinction compte, et
    // rendre un instantané vide ici afficherait des graphes à zéro.
    metriques = { indisponible: `la console ne répond pas — ${err.message}` };
  }
  renderMetriquesConsole();
  majIndicateurs();
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
  renderMetriquesConsole();
  renderLivraison();
  majIndicateurs();
  chargerDrafts();
  chargerLivraison();

  // Puis le réseau, carte par carte. Une carte lente ne retarde plus rien.
  chargerMetriques();
  fetch('/api/state/network').then((r) => r.json()).then((recu) => {
    reseau = recu;
    renderPills(reseau);
    renderRecolte(reseau);
    majIndicateurs();
  }).catch((err) => {
    document.getElementById('recolte-verdict').textContent = 'illisible';
  });
}

// ---------------------------------------------------------------------------
// La disposition : onglets, rangement, repli
// ---------------------------------------------------------------------------

const panneaux = new Map(
  [...document.querySelectorAll('section[data-panneau]')].map((s) => [s.dataset.panneau, s]),
);
// La Sortie est repliable mais pas déplaçable : elle vit hors des onglets.
const rangeables = [...panneaux.entries()].filter(([, s]) => !s.hasAttribute('data-fixe'));
const IDS_RANGEABLES = rangeables.map(([id]) => id);

// Le CODE fait autorité sur ce qui EXISTE, le rangement mémorisé seulement sur
// l'ORDRE. Sans ça, une section ajoutée un jour resterait invisible chez qui a
// déjà rangé sa page — et rien ne le signalerait.
let disposition = lire(localStorage, IDS_RANGEABLES);
let ongletActif = ONGLETS[0].id;

/** Construit la barre d'onglets et les vues. Fait en JS depuis `ONGLETS` pour
 *  qu'ajouter un onglet ne demande pas de toucher au balisage. */
const barre = document.getElementById('onglets');
const vues = document.getElementById('vues');
const colonnesDe = new Map();

for (const { id, label } of ONGLETS) {
  const bouton = document.createElement('button');
  bouton.className = 'onglet';
  bouton.dataset.onglet = id;
  // Trois choses, dans cet ordre : le nom, ce que l'onglet a à dire, et le
  // nombre de ses sections repliées. Les deux dernières répondent à des
  // questions différentes — « qu'y a-t-il à faire » et « qu'est-ce que je me
  // cache » — donc elles ne se confondent pas dans une seule pastille.
  bouton.innerHTML = `${label}<span class="indic" hidden></span><span class="compte" hidden></span>`;
  bouton.onclick = () => activer(id);
  barre.append(bouton);

  const vue = document.createElement('div');
  vue.className = 'vue';
  vue.dataset.onglet = id;
  const cols = [];
  for (let c = 0; c < NB_COLONNES; c++) {
    const colonne = document.createElement('div');
    colonne.className = 'colonne';
    colonne.dataset.colonne = String(c);
    vue.append(colonne);
    cols.push(colonne);
  }
  colonnesDe.set(id, cols);
  vues.append(vue);
}

function activer(id) {
  ongletActif = id;
  for (const vue of vues.children) vue.hidden = vue.dataset.onglet !== id;
  for (const b of barre.children) b.classList.toggle('actif', b.dataset.onglet === id);
}

/** Pose l'indicateur de chaque onglet.
 *
 *  Appelée à chaque arrivée de données — instantanées, puis réseau, puis
 *  métriques — parce qu'un indicateur qui resterait sur « ? » après le
 *  chargement serait pire que pas d'indicateur du tout. */
function majIndicateurs() {
  const tous = indicateurs({ state, metriques, reseau, livraison });
  for (const b of barre.children) {
    const el = b.querySelector('.indic');
    const i = tous[b.dataset.onglet];
    el.hidden = !i;
    if (!i) continue;
    el.textContent = i.texte;
    el.className = `indic n-${i.niveau}`;
    el.title = i.titre;
  }
}

function appliquerDisposition() {
  for (const { id: onglet } of ONGLETS) {
    disposition.onglets[onglet].forEach((ids, index) => {
      const colonne = colonnesDe.get(onglet)[index];
      // `append` DÉPLACE un nœud déjà présent : réordonner ne détruit donc rien,
      // et les écouteurs comme l'état de défilement des sections survivent.
      for (const id of ids) colonne.append(panneaux.get(id));
    });
  }
  for (const [id, section] of panneaux) {
    section.classList.toggle('repliee', disposition.replies.includes(id));
  }

  // Une section repliée est une OMISSION, et une omission doit toujours avoir
  // une sortie visible. Sans ce compteur, neuf clics escamotaient les
  // vingt-sept boutons de la console sans que rien ne le dise.
  const deplier = document.getElementById('deplier');
  const n = disposition.replies.length;
  deplier.hidden = n === 0;
  deplier.textContent = `${n} section${n > 1 ? 's' : ''} repliée${n > 1 ? 's' : ''} — tout déplier`;

  // Et sur chaque onglet, le nombre de ses sections repliées : sans ça, une
  // section masquée dans un onglet qu'on ne regarde pas resterait invisible.
  for (const b of barre.children) {
    const caches = disposition.onglets[b.dataset.onglet]
      .flat()
      .filter((id) => disposition.replies.includes(id)).length;
    const pastille = b.querySelector('.compte');
    pastille.hidden = caches === 0;
    pastille.textContent = String(caches);
  }

  document.getElementById('reinit').hidden = estLeDefaut();
}

function estLeDefaut() {
  return JSON.stringify(disposition) === JSON.stringify(reconcilier(null, IDS_RANGEABLES));
}

function enregistrerDisposition(suivante) {
  disposition = suivante;
  ecrire(localStorage, disposition);
  appliquerDisposition();
}

/** Prépare chaque en-tête : chevron pour replier, reste de l'en-tête pour glisser. */
function armerLesEntetes() {
  for (const [id, section] of panneaux) {
    const h2 = section.querySelector(':scope > h2');
    const fixe = section.hasAttribute('data-fixe');

    // Le titre part dans un conteneur précédé du chevron — mais SANS le `<em>`
    // compteur, qui doit rester à droite : l'en-tête est un flex en
    // `space-between`, et tout emballer ensemble collerait le compteur au titre.
    const compteur = h2.querySelector(':scope > em');
    const titre = document.createElement('span');
    titre.className = 'titre';
    const chevron = Object.assign(document.createElement('span'), {
      className: 'chevron',
      textContent: '▾',
      title: 'Replier ou déplier cette section',
    });
    titre.append(chevron);
    for (const noeud of [...h2.childNodes]) {
      if (noeud !== compteur) titre.append(noeud);
    }
    h2.prepend(titre);

    // LE CHEVRON SEUL replie. L'en-tête entier le faisait jusqu'au 2026-08-07,
    // et c'était une faute : on annonce l'en-tête comme la poignée, l'utilisateur
    // clique dessus, et la section disparaît. Une cible large pour un geste qui
    // masque est une mauvaise cible.
    chevron.addEventListener('pointerdown', (e) => e.stopPropagation());
    chevron.addEventListener('click', () => enregistrerDisposition(basculerRepli(disposition, id)));

    if (!fixe) h2.addEventListener('pointerdown', (e) => saisir(e, id, section, h2));
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
// Ici : en dessous de SEUIL pixels, rien ne se passe. Au-delà, c'est un
// rangement. Le repli, lui, ne dépend plus du tout du glissement — il a son
// chevron.
// ---------------------------------------------------------------------------

const SEUIL = 5;

function effacerLesReperes() {
  for (const n of document.querySelectorAll('.cible-avant, .cible-fin')) {
    n.classList.remove('cible-avant', 'cible-fin');
  }
  for (const c of document.querySelectorAll('.colonne, .onglet')) c.classList.remove('survol');
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

/** L'onglet survolé pendant un glissement, ou `null`. Déposer une section sur un
 *  onglet la déménage : c'est le seul geste qui traverse les onglets, et il doit
 *  se voir — d'où la classe `survol` sur le bouton. */
function ongletSurvole(x, y) {
  for (const b of barre.children) {
    const r = b.getBoundingClientRect();
    if (x >= r.left && x <= r.right && y >= r.top && y <= r.bottom) return b.dataset.onglet;
  }
  return null;
}

/** L'index de la colonne sous le pointeur. La géométrie vit dans `layout.mjs`,
 *  où elle se teste sans navigateur. */
function colonneVisee(x) {
  return colonneSous(x, colonnesDe.get(ongletActif).map((c) => c.getBoundingClientRect()));
}

/** Où la section tomberait si on relâchait maintenant. */
function destination(e) {
  const surOnglet = ongletSurvole(e.clientX, e.clientY);
  if (surOnglet) return { onglet: surOnglet, colonne: 0, avant: null, surOnglet: true };
  const colonne = colonneVisee(e.clientX);
  const avant = cibleDans(colonnesDe.get(ongletActif)[colonne], e.clientY);
  return { onglet: ongletActif, colonne, avant: avant?.dataset.panneau ?? null, cible: avant };
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
    const d = destination(e);
    if (d.surOnglet) {
      [...barre.children].find((b) => b.dataset.onglet === d.onglet)?.classList.add('survol');
      return;
    }
    const colonne = colonnesDe.get(d.onglet)[d.colonne];
    colonne.classList.add('survol');
    if (d.cible) d.cible.classList.add('cible-avant');
    else colonne.querySelector(':scope > section:last-of-type')?.classList.add('cible-fin');
  };

  const lacher = (e) => {
    h2.removeEventListener('pointermove', bouger);
    h2.removeEventListener('pointerup', lacher);
    h2.removeEventListener('pointercancel', lacher);
    h2.releasePointerCapture?.(depart.pointerId);
    section.classList.remove('glisse');
    // Un simple clic sur l'en-tête ne fait plus RIEN : replier a son chevron.
    if (!glisse) { effacerLesReperes(); return; }

    const d = destination(e);
    effacerLesReperes();
    enregistrerDisposition(deplacer(disposition, id, d.onglet, d.colonne, d.avant));
    // Suivre la section qu'on vient de déménager : la voir partir sans savoir où
    // elle atterrit serait un rangement à l'aveugle.
    if (d.onglet !== ongletActif) activer(d.onglet);
  };

  h2.addEventListener('pointermove', bouger);
  h2.addEventListener('pointerup', lacher);
  // Un pointeur perdu (fenêtre qui perd le focus, geste interrompu) doit relâcher
  // proprement, sinon la section reste fantôme et la page à moitié en glissement.
  h2.addEventListener('pointercancel', lacher);
}

document.getElementById('reinit').onclick = () => {
  oublier(localStorage);
  disposition = lire(localStorage, IDS_RANGEABLES);
  appliquerDisposition();
};
document.getElementById('deplier').onclick = () => enregistrerDisposition(toutDeplier(disposition));

/**
 * La Sortie se déplie et vient sous les yeux quand une commande part.
 *
 * Sans ça, on clique un bouton et le résultat s'écrit ailleurs, parfois hors
 * écran. Un résultat qu'on ne voit pas est un résultat qu'on n'a pas.
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
activer(ongletActif);
appliquerDisposition();

refresh();
