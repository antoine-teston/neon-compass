// Les graphes des métriques Supabase, partagés par la console (Mac) et le
// moniteur (Raspberry Pi).
//
// Module de NAVIGATEUR : il ne connaît que le DOM et l'instantané qu'on lui
// passe. Aucun `fetch` ici — c'est l'appelant qui va chercher les nombres, ce
// qui laisse ce fichier vérifiable en le regardant, et surtout réutilisable
// dans deux pages qui ne vont pas les chercher au même endroit.
//
// ─────────────────────────────────────────────────────────────────────────────
// LES COULEURS ONT ÉTÉ CALCULÉES, PAS CHOISIES
//
// Chaque couleur ci-dessous sort de `scripts/validate_palette.js` contre le fond
// des panneaux (#141a28), en mode sombre. Les valeurs de départ — le cyan et le
// magenta de la console — ÉCHOUAIENT toutes les deux à la bande de clarté
// (L 0,845 et 0,697 pour une bande 0,48–0,67). Le couple retenu est le meilleur
// écart en deutéranopie parmi ceux qui passent les six contrôles :
//
//   #00a9b4 (arrivées) · #ac3b73 (approbations)
//   ΔE deutan 13,6 · ΔE normal 29,8 · contraste ≥ 3:1 · bande OK
//
// Un premier candidat, #b8006d, donnait un meilleur ΔE (15,1) mais tombait à
// 2,7:1 de contraste — un AVERTISSEMENT qui ne se congédie pas. Il est écarté.

export const SERIE_ARRIVEES = '#00a9b4';
export const SERIE_APPROBATIONS = '#ac3b73';

/** La rampe ordinale des tranches d'ancienneté, déjà validée pour l'atelier des
 *  brouillons. Réutilisée telle quelle : deux rampes pour la même grandeur
 *  obligeraient à réapprendre la lecture d'un graphe à l'autre. */
const RAMPE_AGE = ['--age-1', '--age-2', '--age-3', '--age-4', '--age-5'];

const TRANCHES = ["aujourd'hui", '1 à 3 j', '4 à 7 j', '8 à 14 j', 'plus de 14 j'];

/** Les catégories, dans l'ordre du schéma — jamais triées par valeur.
 *
 *  Trier par valeur ferait danser les colonnes d'un rafraîchissement à l'autre,
 *  et une comparaison visuelle entre deux coups d'œil deviendrait fausse. */
const CATEGORIES = [
  ['landmark', 'Lieux'],
  ['collectible', 'Collectibles'],
  ['activity', 'Activités'],
  ['safehouse', 'Planques'],
  ['vehicle', 'Véhicules'],
  ['event', 'Événements'],
];

export const esc = (s) =>
  String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

// ---------------------------------------------------------------------------
// Infobulle
// ---------------------------------------------------------------------------

let bulle = null;

/** Branche l'infobulle partagée. Appelée une fois par page. */
export function installerBulle(element) {
  bulle = element;
}

export function armerBulle(noeud, titre, exact) {
  if (!bulle) return;
  noeud.addEventListener('pointerenter', () => {
    bulle.innerHTML = `${esc(titre)}${exact ? `<span class="exact">${esc(exact)}</span>` : ''}`;
    bulle.hidden = false;
  });
  noeud.addEventListener('pointermove', (e) => {
    bulle.style.left = `${Math.min(e.clientX + 14, window.innerWidth - 340)}px`;
    bulle.style.top = `${e.clientY + 16}px`;
  });
  noeud.addEventListener('pointerleave', () => {
    bulle.hidden = true;
  });
}

function bloc(titre, sous) {
  const el = document.createElement('div');
  el.className = 'graphe';
  el.innerHTML = `<h4>${esc(titre)}</h4>${sous ? `<p class="sous">${esc(sous)}</p>` : ''}`;
  return el;
}

const pluriel = (n, mot) => `${n} ${mot}${n > 1 ? 's' : ''}`;

// ---------------------------------------------------------------------------
// Le nombre en tête
// ---------------------------------------------------------------------------

export function heroModeration(hote, moderation) {
  const hero = document.createElement('div');
  hero.innerHTML = `<div class="hero"><span class="n">${moderation.enAttente}</span>
      <span class="quoi">contribution${moderation.enAttente > 1 ? 's' : ''} en attente de modération</span></div>`;

  const sous = document.createElement('p');
  sous.className = 'hero-sous';
  const morceaux = [];
  if (moderation.plusAncienJours !== null) {
    morceaux.push(
      moderation.plusAncienJours === 0
        ? 'La plus ancienne est arrivée aujourd’hui.'
        : `La plus ancienne attend depuis ${pluriel(moderation.plusAncienJours, 'jour')}.`,
    );
  }
  // Les signalées d'abord dans la phrase : le suivi de vélocité les marque sans
  // bloquer personne, donc elles restent VISIBLES des joueurs pendant qu'elles
  // attendent. Les noyer dans le total reviendrait à ne pas les avoir marquées.
  if (moderation.signales > 0) {
    const n = moderation.signales;
    morceaux.push(
      n > 1
        ? `${n} sont signalées pour un regard prioritaire.`
        : 'Une est signalée pour un regard prioritaire.',
    );
  }
  sous.textContent = morceaux.join(' ') || 'La file est vide.';
  hero.append(sous);
  hote.append(hero);
}

// ---------------------------------------------------------------------------
// Ancienneté — ORDINAL, une seule teinte
// ---------------------------------------------------------------------------

export function grapheTranches(hote, moderation) {
  if (!moderation.enAttente) return;
  const el = bloc('Depuis quand elles attendent', 'Contributions en attente, par ancienneté.');
  const max = Math.max(...moderation.parTranche, 1);

  const cols = document.createElement('div');
  cols.className = 'colonnes';
  moderation.parTranche.forEach((n, i) => {
    const cel = document.createElement('div');
    const val = document.createElement('span');
    val.className = n ? 'val' : 'val zero';
    val.textContent = String(n);
    const fut = document.createElement('div');
    fut.className = 'fut';
    fut.style.height = n ? `${Math.max(6, (n / max) * 78)}px` : '2px';
    fut.style.background = n ? `var(${RAMPE_AGE[i]})` : 'var(--line)';
    armerBulle(cel, `${pluriel(n, 'contribution')} — ${TRANCHES[i]}`);
    cel.append(val, fut);
    cols.append(cel);
  });

  const axe = document.createElement('div');
  axe.className = 'axe-x';
  axe.innerHTML = TRANCHES.map((t) => `<span>${esc(t)}</span>`).join('');
  el.append(cols, axe);
  hote.append(el);
}

// ---------------------------------------------------------------------------
// Catégories — barres horizontales, une seule teinte
// ---------------------------------------------------------------------------

export function grapheCategories(hote, moderation) {
  if (!moderation.enAttente) return;
  const el = bloc('Ce qui attend, par catégorie');
  const valeurs = CATEGORIES.map(([cle, label]) => [label, moderation.parCategorie?.[cle] ?? 0]);

  // Une catégorie hors schéma est AJOUTÉE plutôt que tue : la voir apparaître
  // est le seul signal qu'on aura qu'un vocabulaire a bougé côté base.
  for (const [cle, n] of Object.entries(moderation.parCategorie ?? {})) {
    if (!CATEGORIES.some(([c]) => c === cle)) valeurs.push([`${cle} (inconnue)`, n]);
  }

  const max = Math.max(...valeurs.map(([, n]) => n), 1);
  for (const [label, n] of valeurs) {
    const ligne = document.createElement('div');
    ligne.className = 'motif';
    ligne.innerHTML = `<span class="nom">${esc(label)}</span><span class="val">${n}</span>
      <span class="piste"><span style="width:${(n / max) * 100}%;background:${SERIE_ARRIVEES}"></span></span>`;
    armerBulle(ligne, `${pluriel(n, 'contribution')} — ${label}`);
    el.append(ligne);
  }
  hote.append(el);
}

// ---------------------------------------------------------------------------
// Flux — la seule vraie série temporelle dont on dispose
// ---------------------------------------------------------------------------

const L = { w: 640, h: 150, g: 26, d: 8, ht: 10, bs: 26 };

function chemin(valeurs, max) {
  const pas = (L.w - L.g - L.d) / Math.max(valeurs.length - 1, 1);
  const haut = L.h - L.ht - L.bs;
  return valeurs
    .map((v, i) => {
      const x = L.g + i * pas;
      const y = L.ht + haut - (v / max) * haut;
      return `${i ? 'L' : 'M'}${x.toFixed(1)} ${y.toFixed(1)}`;
    })
    .join(' ');
}

/**
 * Deux courbes sur UN seul axe. Jamais deux échelles : arrivées et approbations
 * se comptent dans la même unité, et un second axe rendrait leur croisement
 * arbitraire — c'est justement ce croisement qu'on regarde.
 */
export function grapheFlux(hote, flux) {
  if (!flux?.length) return;
  const el = bloc(
    'Arrivées et approbations',
    'Trente jours. Un refus ne laisse aucune date en base : la courbe compte ce '
      + 'qui a été approuvé, pas tout ce qui a été traité. Le décompte en attente, lui, est exact.',
  );

  const arrivees = flux.map((j) => j.arrivees);
  const approbations = flux.map((j) => j.approbations);
  const max = Math.max(...arrivees, ...approbations, 1);

  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', `0 0 ${L.w} ${L.h}`);
  svg.setAttribute('class', 'flux');
  svg.setAttribute('preserveAspectRatio', 'none');
  svg.setAttribute('role', 'img');
  svg.setAttribute(
    'aria-label',
    `Arrivées et approbations sur trente jours, du ${flux[0].jour} au ${flux.at(-1).jour}`,
  );

  // Grille RÉCESSIVE : trois repères, l'encre au service de la donnée. Les
  // graduations sont des entiers — une demi-contribution n'existe pas.
  const pasY = Math.max(1, Math.ceil(max / 3));
  let fond = '';
  for (let v = 0; v <= max; v += pasY) {
    const y = L.ht + (L.h - L.ht - L.bs) * (1 - v / max);
    fond += `<line x1="${L.g}" x2="${L.w - L.d}" y1="${y.toFixed(1)}" y2="${y.toFixed(1)}" class="grille"/>`
      + `<text x="${L.g - 6}" y="${(y + 3.5).toFixed(1)}" class="axe-y">${v}</text>`;
  }
  svg.insertAdjacentHTML('beforeend', fond);

  for (const [valeurs, couleur] of [[arrivees, SERIE_ARRIVEES], [approbations, SERIE_APPROBATIONS]]) {
    svg.insertAdjacentHTML(
      'beforeend',
      `<path d="${chemin(valeurs, max)}" fill="none" stroke="${couleur}" stroke-width="2"
         stroke-linecap="round" stroke-linejoin="round"/>`,
    );
  }

  // Étiquettes de temps aux DEUX bouts seulement. Trente dates lisibles
  // n'existent pas à cette largeur, et la question posée est « ça monte ou ça
  // descend », pas « quel jour exactement » — l'infobulle répond à celle-là.
  const jourCourt = (iso) => iso.slice(8, 10) + '/' + iso.slice(5, 7);
  svg.insertAdjacentHTML(
    'beforeend',
    `<text x="${L.g}" y="${L.h - 8}" class="axe-x-svg">${jourCourt(flux[0].jour)}</text>`
      + `<text x="${L.w - L.d}" y="${L.h - 8}" class="axe-x-svg" text-anchor="end">${jourCourt(flux.at(-1).jour)}</text>`,
  );

  // Le viseur : une ligne verticale et la valeur des deux séries au même
  // instant. Sans lui, deux courbes proches sont illisibles.
  const viseur = document.createElementNS('http://www.w3.org/2000/svg', 'line');
  viseur.setAttribute('class', 'viseur');
  viseur.setAttribute('y1', String(L.ht));
  viseur.setAttribute('y2', String(L.h - L.bs));
  viseur.setAttribute('opacity', '0');
  svg.append(viseur);

  const cadre = document.createElement('div');
  cadre.className = 'cadre-flux';
  cadre.append(svg);

  const pas = (L.w - L.g - L.d) / Math.max(flux.length - 1, 1);
  cadre.addEventListener('pointermove', (e) => {
    const boite = cadre.getBoundingClientRect();
    const x = ((e.clientX - boite.left) / boite.width) * L.w;
    const i = Math.max(0, Math.min(flux.length - 1, Math.round((x - L.g) / pas)));
    viseur.setAttribute('x1', String(L.g + i * pas));
    viseur.setAttribute('x2', String(L.g + i * pas));
    viseur.setAttribute('opacity', '1');
    if (bulle) {
      const j = flux[i];
      bulle.innerHTML = `${esc(j.jour)}<span class="exact">${j.arrivees} arrivée${j.arrivees > 1 ? 's' : ''}`
        + ` · ${j.approbations} approbation${j.approbations > 1 ? 's' : ''}</span>`;
      bulle.style.left = `${Math.min(e.clientX + 14, window.innerWidth - 340)}px`;
      bulle.style.top = `${e.clientY + 16}px`;
      bulle.hidden = false;
    }
  });
  cadre.addEventListener('pointerleave', () => {
    viseur.setAttribute('opacity', '0');
    if (bulle) bulle.hidden = true;
  });

  // La légende porte le TOTAL de chaque série : l'identité ne repose jamais sur
  // la seule couleur, et le chiffre répond à la question suivante sans un clic.
  const legende = document.createElement('div');
  legende.className = 'legende';
  const somme = (v) => v.reduce((a, b) => a + b, 0);
  legende.innerHTML =
    `<span><i style="background:${SERIE_ARRIVEES}"></i><b>${somme(arrivees)}</b> arrivées</span>`
    + `<span><i style="background:${SERIE_APPROBATIONS}"></i><b>${somme(approbations)}</b> approbations</span>`;

  el.append(cadre, legende);
  hote.append(el);
}

// ---------------------------------------------------------------------------
// Ce qui est bloqué — des ÉTATS, pas des grandeurs
// ---------------------------------------------------------------------------

/** Un état porte toujours une icône ET un mot, jamais une couleur seule : les
 *  trois teintes de statut de cette console sont à ΔE 6,6 en deutéranopie, donc
 *  ambre et citron y sont quasi indiscernables. */
function ligneEtat(niveau, titre, detail) {
  const icones = { bon: '●', attention: '▲', grave: '■' };
  const div = document.createElement('div');
  div.className = `etat etat-${niveau}`;
  div.innerHTML = `<span class="pastille">${icones[niveau]}</span>
    <span class="quoi"><b>${esc(titre)}</b><span>${esc(detail)}</span></span>`;
  return div;
}

const enClair = (minutes) => {
  if (minutes === null) return 'jamais';
  if (minutes < 60) return `il y a ${pluriel(minutes, 'minute')}`;
  const h = Math.floor(minutes / 60);
  if (h < 48) return `il y a ${pluriel(h, 'heure')}`;
  return `il y a ${pluriel(Math.floor(h / 24), 'jour')}`;
};

/** Le seuil au-delà duquel des fragments périmés cessent d'être normaux.
 *
 *  `rebuild-community-bundles` se force toutes les heures même sans changement.
 *  Deux heures sans reconstruction alors qu'il y a du sale, c'est donc que la
 *  tâche planifiée ne tourne plus — et le symptôme visible est qu'une
 *  contribution approuvée n'apparaît chez personne. */
export const FRAGMENTS_EN_RETARD_MIN = 120;

export function blocages(hote, b) {
  const el = bloc(
    'Ce qui pourrait être bloqué',
    'Des pannes qui ne réveillent personne : elles ne cassent rien, elles servent l’ancienne réponse.',
  );

  const salesDepuis = b.fragmentsDepuisMinutes;
  if (b.fragmentsSales && (salesDepuis === null || salesDepuis > FRAGMENTS_EN_RETARD_MIN)) {
    el.append(
      ligneEtat(
        'grave',
        'Fragments communautaires périmés',
        `Dernière reconstruction ${enClair(salesDepuis)} — une contribution approuvée n’apparaît chez personne tant qu’elle n’a pas eu lieu.`,
      ),
    );
  } else if (b.fragmentsSales) {
    el.append(ligneEtat('attention', 'Fragments à reconstruire', `En attente, dernière ${enClair(salesDepuis)}. La reconstruction se force toutes les heures.`));
  } else {
    el.append(ligneEtat('bon', 'Fragments communautaires à jour', `Dernière reconstruction ${enClair(salesDepuis)}.`));
  }

  if (b.pushCoinces > 0) {
    el.append(ligneEtat('grave', 'File de notifications coincée', `${pluriel(b.pushCoinces, 'envoi')} après trois tentatives ou plus. Un quatrième essai n’y changera rien.`));
  } else if (b.pushEnAttente > 0) {
    el.append(ligneEtat('attention', 'Notifications en attente', `${pluriel(b.pushEnAttente, 'envoi')}, la plus ancienne ${enClair(b.pushPlusAncienMinutes)}.`));
  } else {
    el.append(ligneEtat('bon', 'File de notifications vide', 'Rien n’attend d’être envoyé.'));
  }

  hote.append(el);
}

// ---------------------------------------------------------------------------
// Les totaux — des tuiles, pas un graphe
// ---------------------------------------------------------------------------

/** Cinq grandeurs sans rapport les unes avec les autres : les mettre en barres
 *  inviterait à les comparer, ce qui n'a aucun sens (des votes contre des
 *  profils). Un chiffre et son nom suffisent. */
export function tuilesCommunaute(hote, c) {
  const el = bloc('La communauté à ce jour');
  const grille = document.createElement('div');
  grille.className = 'tuiles';
  const items = [
    ['Profils', c.profils],
    ['Contributions approuvées', c.approuvees],
    ['Refusées', c.rejetees],
    ['Votes', c.votes],
    ['Signalements', c.signalements],
  ];
  grille.innerHTML = items
    .map(
      ([nom, v]) =>
        // `null` veut dire « le compteur n'a pas répondu ». Afficher 0 serait le
        // mensonge exact que tout ce tableau de bord existe pour supprimer.
        `<div class="tuile"><span class="n">${v === null || v === undefined ? '—' : v}</span>
         <span class="nom">${esc(nom)}</span></div>`,
    )
    .join('');
  el.append(grille);
  hote.append(el);
}

// ---------------------------------------------------------------------------
// L'assemblage
// ---------------------------------------------------------------------------

/** Vide l'hôte et rend l'état d'attente ou d'indisponibilité s'il y a lieu.
 *
 *  Rend `null` quand il n'y a rien à dessiner — l'appelant s'arrête là. C'est
 *  ce petit préambule qui garantit qu'aucune vue ne dessine un zéro faute de
 *  réponse : il n'y a pas de chemin qui saute l'étape. */
function preambule(hote, resultat) {
  hote.textContent = '';
  if (!resultat) {
    hote.innerHTML = '<p class="dim">chargement…</p>';
    return null;
  }
  if (resultat.indisponible) {
    const p = document.createElement('p');
    p.className = 'indispo';
    p.textContent = resultat.indisponible;
    hote.append(p);
    return null;
  }
  return resultat.instantane;
}

function releveLe(hote, instant) {
  const pied = document.createElement('p');
  pied.className = 'pris-le';
  pied.textContent = `Relevé le ${instant.prisLe.slice(0, 10)} à ${instant.prisLe.slice(11, 16)} UTC.`;
  hote.append(pied);
}

/** La FILE : ce qui attend une décision. */
export function renderFile(hote, resultat) {
  const i = preambule(hote, resultat);
  if (!i) return;
  heroModeration(hote, i.moderation);
  grapheTranches(hote, i.moderation);
  grapheCategories(hote, i.moderation);
  grapheFlux(hote, i.flux);
}

/** La SANTÉ : ce qui tourne, ou pas, sans que personne ne soit prévenu. */
export function renderSante(hote, resultat) {
  const i = preambule(hote, resultat);
  if (!i) return;
  blocages(hote, i.blocages);
  tuilesCommunaute(hote, i.communaute);
  releveLe(hote, i);
}

/** Tout d'un bloc — ce que le moniteur affiche, sur une seule colonne.
 *
 *  @param {HTMLElement} hote vidé avant de rendre
 *  @param {{instantane?: object, indisponible?: string}} resultat
 */
export function renderMetriques(hote, resultat) {
  const i = preambule(hote, resultat);
  if (!i) return;
  heroModeration(hote, i.moderation);
  grapheTranches(hote, i.moderation);
  grapheCategories(hote, i.moderation);
  grapheFlux(hote, i.flux);
  blocages(hote, i.blocages);
  tuilesCommunaute(hote, i.communaute);
  releveLe(hote, i);
}
