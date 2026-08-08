# Le moniteur sur un Raspberry Pi

**Date : 2026-08-08.** Ce qu'il faut faire une fois, dans l'ordre, pour qu'un Pi
affiche la file de modération et la santé de la production en continu.

---

## Ce qui part sur le Pi, et ce qui n'y va pas

La console de pilotage (`npm run ui`) **reste sur le Mac**, sur `127.0.0.1`.
C'est elle qui publie, lance des workflows, pousse des branches, applique des
migrations — et sa seule protection est que personne d'autre ne peut l'atteindre.

Ce qui part sur le Pi est **la moitié lisible**, et rien d'autre :

| | Console (Mac) | Moniteur (Pi) |
|---|---|---|
| Écoute sur | `127.0.0.1` | toutes les interfaces |
| Peut lancer un processus | oui | **non** |
| Peut écrire un fichier | oui | **non** |
| A le dépôt git | oui | **non** |
| Détient `service_role` | oui | **non** |
| Détient | les vraies clés | un jeton qui sait demander « combien » |

Un service joignable sur le réseau local et sans authentification n'est
défendable que si **il n'y a rien à appeler**. C'est vérifié par
`tools/monitor/imports.test.mjs`, qui échoue si une source du dossier importe de
quoi lancer un processus, écrire sur le disque, ou parler à Postgres — et si le
serveur mentionne autre chose qu'un GET.

## Pourquoi une Edge Function plutôt qu'un accès à la base

Trois façons de donner des chiffres au Pi :

1. **la clé `service_role` sur la carte SD** — elle contourne RLS. Perdre le Pi,
   c'est perdre la base. Écarté ;
2. **un rôle Postgres en lecture seule** — mieux, mais il lit encore des
   *lignes* : titres, pseudonymes, identifiants d'auteurs ;
3. **la fonction `metrics`**, qui agrège côté serveur et ne rend que des
   décomptes.

C'est la troisième. Le Pi ne reçoit jamais un nom ni un titre — la promesse est
tenue par `fuitesDe` dans `supabase/functions/metrics/aggregate.test.ts`, qui
parcourt un instantané complet et échoue si une chaîne apparaît là où on
attendait un nombre.

Deux serrures protègent la fonction : `verify_jwt` reste **activé** (le trafic
anonyme n'atteint jamais notre code), et `X-Monitor-Token` est comparé en temps
constant. La clé publiable étant dans le binaire de l'app, la première ne prouve
rien seule.

---

## Les quatre étapes

### 1. Poser le jeton, côté serveur

```sh
openssl rand -base64 32          # garder la sortie, elle sert deux fois
supabase secrets set MONITOR_TOKEN='<la sortie>'
```

Sans ce secret la fonction répond **503**, jamais 200 : un secret manquant
n'ouvre pas la porte « en attendant ».

### 2. Déployer la fonction

```sh
supabase functions deploy metrics
```

Ou depuis la console : *Pilotage → Redéployer une edge function → `metrics`*.
La carte « dérive des fonctions » la listera désormais — **une fonction non
déployée ne casse rien, elle rend l'ancienne réponse**, et ici l'ancienne
réponse est un 404.

### 3. Vérifier depuis le Mac AVANT de toucher au Pi

C'est l'étape qu'on est tenté de sauter, et c'est celle qui fait gagner l'heure.
Poser les trois variables dans l'environnement du Mac, puis relancer la console :

```sh
export SUPABASE_URL=https://<ref>.supabase.co
export SUPABASE_ANON_KEY=<la clé publiable>
export MONITOR_TOKEN=<le jeton de l'étape 1>
npm --prefix tools/content-cli run ui
```

Les sections **File communautaire** (onglet Revue) et **Santé de la production**
(onglet Contrôles) doivent afficher des chiffres. Si ce n'est pas le cas, la
phrase affichée dit quoi faire — elle distingue le 401 (jeton différent du
secret déployé), le 503 (secret jamais posé) et le 404 (fonction non déployée).

La console passe par **le même chemin que le Pi**, délibérément : c'est ce qui
fait qu'une régression se voit sur le Mac au lieu d'être découverte sur une
étagère à l'autre bout de la maison.

### 4. Installer sur le Pi

Sur le Pi, avec Docker installé :

```sh
git clone <ce dépôt> neon-compass && cd neon-compass
cp tools/monitor/.env.example tools/monitor/.env
# remplir SUPABASE_URL, SUPABASE_ANON_KEY, MONITOR_TOKEN
docker compose -f tools/monitor/compose.yml up -d
```

Puis `http://<ip-du-pi>:4322` depuis n'importe quel appareil du réseau.

> Le clone n'est là que pour disposer des fichiers ; le conteneur, lui, n'en
> emporte que cinq — `metrics.mjs`, `graphes.mjs`, `graphes.css`, `index.html`,
> `server.mjs`. Pas de `git`, pas de `node_modules`, aucune dépendance npm.

Depuis un Mac Apple Silicon, construire l'image et l'envoyer marche aussi : le
Pi 64 bits est de la même architecture (arm64), il n'y a rien à émuler.

```sh
docker build -t neon-moniteur tools/monitor
docker save neon-moniteur | ssh pi@<ip> 'docker load'
```

Un Pi **32 bits** (Zero, ou Pi 3 sous Raspberry Pi OS 32 bits) demande un
croisement explicite et lent : `docker buildx build --platform linux/arm/v7`.

---

## Ce que le moniteur montre

**La file** — combien de contributions attendent, depuis quand, dans quelle
catégorie, et combien sont signalées. Une contribution signalée reste **visible
des joueurs** pendant qu'elle attend : c'est pourquoi elle est comptée à part
plutôt que noyée dans le total.

**Arrivées et approbations, sur trente jours.** ⚠️ La courbe compte les
*approbations*, pas les *décisions* : un refus ne laisse aucune date en base
(`contributions` porte `approved_at`, il n'y a pas de `rejected_at`). Une
contribution refusée quitte donc la file sans trace datée, et la courbe
sous-estime le travail fait. **Le décompte en attente, lui, est exact** — c'est
lui qui fait foi. Ajouter un `rejected_at` réglerait la question ; ce n'est pas
fait.

**Ce qui pourrait être bloqué** — deux pannes qui ne réveillent personne :

- *fragments communautaires périmés* : `rebuild-community-bundles` se force
  toutes les heures même sans changement. Au-delà de deux heures avec du sale en
  attente, la tâche planifiée ne tourne plus, et **une contribution approuvée
  n'apparaît chez personne** ;
- *file de notifications coincée* : au-delà de trois tentatives, un quatrième
  essai n'y changera rien.

## Ce qu'il ne montre pas

**L'évolution du backlog éditorial.** Rien ne journalise les transitions des
brouillons : il n'existe que l'état courant, et une courbe serait inventée. La
seule série temporelle réelle est celle des contributions, parce que
`created_at` et `approved_at` existent en base.

**Les brouillons éditoriaux.** Ils vivent dans `content/`, dans le dépôt, que le
Pi n'a pas. Ils restent dans la console.

## Les couleurs

Toutes calculées par `scripts/validate_palette.js` contre le fond des panneaux
(`#141a28`), jamais choisies à l'œil. Les teintes d'origine de la console
(`#35e6f0`, `#ff4fa8`) **échouaient** toutes les deux à la bande de clarté du
mode sombre. Le couple retenu, `#00a9b4` / `#ac3b73`, passe les six contrôles :
ΔE 13,6 en deutéranopie, 29,8 en vision normale, contraste ≥ 3:1.

Les trois couleurs de statut de la console sont à ΔE 6,6 en deutéranopie —
ambre et citron y sont quasi indiscernables. C'est pourquoi chaque état porte
**une icône et un mot**, jamais une couleur seule.

## Si quelque chose cloche

| Ce qu'affiche la page | Ce qui se passe |
|---|---|
| `metrics n'est pas déployée` | étape 2 non faite |
| `metrics n'a pas de MONITOR_TOKEN` | étape 1 non faite (503) |
| `metrics refuse le jeton` | le `.env` et le secret diffèrent (401) |
| `metrics répond hors contrat` | la fonction déployée est plus ancienne que la page — redéployer |
| `metrics injoignable` | réseau, ou `SUPABASE_URL` faux |
| `relevé il y a 12 min` en ambre | le moniteur tourne mais n'obtient plus de réponse |

Le dernier cas est le plus important : **un tableau de bord figé et un tableau
de bord calme ont exactement la même tête.** L'âge du dernier relevé réussi est
affiché en permanence en haut à droite pour cette raison.
