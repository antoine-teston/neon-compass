# La console de pilotage en conteneur

**Date : 2026-08-08.** Pour qu'elle soit toujours là, sans avoir à la relancer.

---

## Avant de commencer : ce que ça coûte

Deux choses, et aucune ne se rattrape après coup.

**1. Le trousseau.** Sur le Mac, `gh` s'authentifie par le trousseau macOS : le
jeton n'existe nulle part en clair. Un conteneur ne l'atteint pas — il faut donc
l'en sortir, et il vivra dans `tools/content-cli/docker/.env`. Un secret dans un
fichier est moins bien gardé qu'un secret dans un trousseau. Ce qui limite les
dégâts : créer un jeton **dédié**, portées `repo` et `workflow`, plutôt que de
recopier celui qui sert à toutes vos machines.

**2. L'arbre partagé.** Le dépôt est monté en écriture. Le conteneur voit la
branche sur laquelle **vous** êtes et écrit dedans. En changer pendant qu'il
tourne change ce qu'il voit, sans qu'il le sache.

Si l'un des deux gêne, `npm run ui` reste là, et n'a ni l'un ni l'autre.

## Ce conteneur est l'opposé de celui du Pi

| | Moniteur (Pi) | Console (Mac) |
|---|---|---|
| Contenu de l'image | 5 fichiers | node + git + gh |
| Dépendances npm | aucune | celles du CLI |
| Écoute sur | toutes les interfaces | **127.0.0.1, et rien d'autre** |
| Détient | un jeton qui sait compter | `service_role`, un jeton GitHub |
| Peut écrire | **non** | le dépôt, le CDN, la base |

Le moniteur est sûr parce qu'il n'y a rien à appeler. La console, elle, n'est
défendable **que** parce qu'elle est liée à `127.0.0.1`. Écrire `"4321:4321"` au
lieu de `"127.0.0.1:4321:4321"` est la faute d'un caractère, ne casse rien,
n'affiche aucune erreur — et met une chaîne de publication sans authentification
sur le réseau local. `docker.test.mjs` échoue si elle est commise.

---

## Mise en service

```sh
cp tools/content-cli/docker/.env.example tools/content-cli/docker/.env
# remplir : GH_TOKEN, GIT_AUTHOR_*, SUPABASE_*
docker compose -f tools/content-cli/docker/compose.yml up -d --build
```

> `docker compose` (plugin) ou `docker-compose` (binaire séparé) selon
> l'installation. Sous Colima on a souvent le second.

Puis **le contrôle qui compte**, une fois, et à chaque changement de moteur
Docker :

```sh
sh tools/content-cli/docker/verifier-exposition.sh
```

Il essaie d'atteindre la console **depuis l'adresse LAN de la machine**. Il ne
lit pas un fichier de configuration : il mesure. Une chaîne de publication ne se
protège pas par une lecture de YAML.

Vérifié le 2026-08-08 sous **Colima 0.10.3** : l'adresse de publication est bien
honorée — le forwarder n'écoute que sur `127.0.0.1:4321`, et le port est refusé
depuis le réseau local. Mais c'est une propriété du **moteur**, pas du code, et
elle peut changer avec lui. D'où le script.

### Deux consoles à la fois

`CONSOLE_PORT` dans le `.env` déplace le port hôte — utile pour essayer le
conteneur pendant qu'un `npm run ui` occupe déjà 4321.

---

## Si ça ne démarre pas

L'entrée refuse plutôt que de démarrer à moitié, parce qu'une console à moitié
démarrée affiche « 0 brouillon en attente » et laisse croire que tout va bien.

| Message | Cause |
|---|---|
| `le dépôt n'est pas monté sur /depot` | volume absent ou mauvais chemin |
| `ne contient pas content/` | monté au mauvais niveau |
| `GIT_AUTHOR_* absents` | « Livrer » échouerait au commit, après avoir créé la branche |
| `GH_TOKEN présent mais refusé` | jeton expiré, ou portées insuffisantes |
| `could not lock config file //.gitconfig` | ne devrait plus arriver — `HOME` est posé dans l'image ; si ça revient, c'est qu'il a été retiré |

Trois pièges déjà rencontrés et corrigés, pour mémoire :

- **`HOME` inexistant.** Le conteneur tourne sous l'uid du Mac (501), qui n'a pas
  de répertoire personnel dans l'image. `git config --global` échouait, l'entrée
  sortait, le conteneur redémarrait en boucle — avec pour seule trace un
  « Permission denied » qui ne nommait pas la cause.
- **`safe.directory`.** Sans lui, git refuse *toute* commande sur un dépôt dont
  le propriétaire n'est pas le sien, et la console rapporte « git muet ».
- **`.git` fichier et non répertoire.** Dans un worktree git, `.git` est un
  fichier. Un test `-d` refusait de démarrer ; c'est `-e`.

---

## Ce que le conteneur ne change pas

Les invariants de la console sont les mêmes qu'en local, et c'est voulu : liste
blanche d'argv, porte d'édition sans processus, confirmation exigée pour les
actions de production. Le conteneur n'ajoute aucune permission — il déplace
seulement l'endroit où le processus tourne.

## Une remarque qui dépasse ce chantier

En vérifiant l'exposition, mesuré sur cette machine le 2026-08-08 : la **pile
Supabase locale** (`supabase start`) publie ses ports sur `0.0.0.0`. Kong
(54321), Postgres (**54322**) et Studio (54323) acceptent des connexions depuis
le réseau local. Ce n'est pas lié au conteneur de la console, c'est le défaut de
`supabase start` — et ça vaut d'être su avant de travailler depuis un Wi-Fi
public.
