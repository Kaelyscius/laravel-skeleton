# Audit supply chain — 2026-08-08

> ✅ **PLAN EXÉCUTÉ le 2026-08-09.** Lots A, B, C et D faits et vérifiés ; le lot E reste
> ouvert (Epic 2). **Ce fichier n'a pas été réécrit** — un instantané qu'on retouche après coup
> cesse d'être un instantané. Le compte rendu d'exécution, avec ce que le plan avait *manqué*,
> est dans [`ETAT.md`](ETAT.md), section « Supply chain — plan exécuté ».
>
> **Un défaut de ce rapport lui-même** : le §4.1 affirme que `node` est le seul `FROM` non
> épinglé. C'est faux — `docker/php/Dockerfile:101` portait `FROM composer:2`, une **majeure
> flottante**, donc un épinglage plus lâche encore. Le rapport qui traque les affirmations sans
> référent en a produit une.
>
> **Instantané daté, pas un document vivant.** Son nom porte sa date : il ne peut donc pas
> prétendre décrire l'état courant six semaines plus tard. Le précédent instantané est le bloc
> « Rafraîchissement supply chain » de [`ETAT.md`](ETAT.md) (2026-08-06).
>
> Périmètre : `HEAD` = `feb6a25`, après la Story 1.13. **Aucune modification n'a été faite** —
> toutes les commandes ci-dessous sont en lecture seule.

---

## Verdict en une ligne

**Rien d'urgent** : zéro advisory côté PHP comme côté JS, et les quatre images épinglées par
digest servent exactement ce que leur registre sert aujourd'hui. **Une anomalie de fond** : l'image
`node` est le seul `FROM` du projet non épinglé par digest, elle est en retard, et le fichier
affirme le contraire de ce qu'il fait.

---

## 1. Méthode — les commandes, pour que ce soit rejouable

```bash
# Sécurité
docker compose exec -u 1000:1000 php composer audit --format=plain
npm audit && npm audit --omit=dev                       # depuis src/

# Retard fonctionnel
docker compose exec -u 1000:1000 php composer outdated --direct
docker compose exec -u 1000:1000 php composer outdated          # + transitifs
npm outdated                                            # depuis src/

# Images : le digest épinglé est-il encore le digest du tag ?
for img in php:8.5-fpm-alpine httpd:2.4-alpine postgres:18-alpine \
           redis:8-alpine node:24-alpine3.23; do
  docker buildx imagetools inspect "$img" --format '{{.Manifest.Digest}}'
done

# Actions GitHub non épinglées par SHA — doit ne RIEN sortir
grep -rhoE "uses: [^ ]+" .github/workflows/*.yml | grep -vE "@[a-f0-9]{40}$"
```

> ⚠️ `docker buildx imagetools inspect` **résout sans télécharger**. Ne pas utiliser
> `docker pull` pour ce contrôle : il modifie l'état local, et sur une image déjà présente il peut
> répondre depuis le cache.

---

## 2. Sécurité — 0

| Contrôle | Résultat |
|---|---|
| `composer audit` | **No security vulnerability advisories found.** |
| `npm audit` (dev inclus) | **found 0 vulnerabilities** |
| `npm audit --omit=dev` | **found 0 vulnerabilities** |

Rappel de contexte : le 2026-08-06, la même commande avait rapporté **7 advisories en une seule
session**, toutes publiées dans les 48 h précédentes (`php_codesniffer` CVE-2026-67434,
`league/commonmark` × 6 DoS). Le zéro d'aujourd'hui n'est donc pas une raison d'espacer le
contrôle — c'est la démonstration qu'il tourne assez souvent.

---

## 3. Images de base — les digests épinglés sont à jour

| Image | Digest épinglé dans le dépôt | Digest courant du tag | Verdict |
|---|---|---|---|
| `php:8.5-fpm-alpine` | `9dc81f40…` | `9dc81f40…` | ✅ identique |
| `httpd:2.4-alpine` | `1b766f17…` | `1b766f17…` | ✅ identique |
| `postgres:18-alpine` | `9a8afca5…` | `9a8afca5…` | ✅ identique |
| `redis:8-alpine` | `978f0e01…` | `978f0e01…` | ✅ identique |
| `node:24.18.0-alpine3.23` | *(pas de digest)* | `24-alpine3.23` → `244cc2b5…` | 🔴 **voir §4** |

Le rafraîchissement du 2026-08-06 tient donc encore intégralement, deux jours après. Rien à
rattraper sur php / apache / postgres / redis.

**Actions GitHub** : le contrôle ne sort rien — les trois workflows sont intégralement épinglés
par SHA 40.

> Note : `apk upgrade --no-cache` tourne à chaque build dans les trois Dockerfiles custom, donc les
> CVE de paquets Alpine sont rattrapées même quand l'image de base est figée. Cet arbitrage est
> documenté dans `docker/node/Dockerfile:33-38` et vaut pour php et apache également.

---

## 4. 🔴 Le défaut : `docker/node/Dockerfile`

### 4.1 Le seul `FROM` sans digest

```
docker/php/Dockerfile:2      # php 8.5.9 / alpine 3.24.1 — épinglé par digest (le tag reste mutable).
docker/apache/Dockerfile:1   # httpd 2.4.68 / alpine 3.24.1 — épinglé par digest (le tag reste mutable).
docker/node/Dockerfile:17    FROM node:24.18.0-alpine3.23          ← ni commentaire, ni digest
```

[ADR-0007 § « Épinglage par digest »](adr/ADR-0007-postgresql-17-over-mariadb.md) énonce la règle
pour `docker-compose.yml` et la CI ; php et apache l'ont appliquée à leurs Dockerfiles de leur
propre initiative. **Node est le seul à ne pas l'avoir.** Un tag de version exacte
(`24.18.0-alpine3.23`) est *presque* immuable — mais « presque » est exactement ce que
l'épinglage par digest existe pour supprimer, et c'est le raisonnement écrit dans les deux autres
fichiers.

### 4.2 Le fichier affirme un invariant qu'il ne tient pas

`docker/node/Dockerfile:33-38`, en justifiant `apk upgrade` :

> *« la reproductibilité de la BASE reste assurée par l'épinglage de l'image »*

**C'est faux pour ce fichier.** La base y est épinglée par tag, pas par digest. L'affirmation est
vraie de php et d'apache, et elle a été recopiée ici sans que son référent existe — la forme
canonique du motif que ce projet traque, au dernier endroit de la chaîne d'approvisionnement qui
y échappait encore.

### 4.3 Et l'image est effectivement en retard

```
node:24.18.0-alpine3.23  →  sha256:595398b0081eacda8e1c4c5b97b76cd1020e4d58a8ebcb4843b9bca1e79e7436
node:24-alpine3.23       →  sha256:244cc2b53f46f9e876304391d17682b0ddae9ac33491f4857e25e35a36ba7995
```

Digests différents ⇒ un **24.x plus récent existe** sur `alpine3.23`. Personne ne le voit :
Watchtower exclut délibérément les images custom, et le contrôle par digest ne peut pas signaler
une image qui n'a pas de digest à comparer.

⚠️ **Ce n'est pas une invitation à monter de majeure.** Node 26 reste refusé jusqu'au
**2026-10-28** (raisonnement complet en tête du Dockerfile : v24 est Active LTS jusqu'au
2026-10-20, v26 ne devient LTS que le 28). Il s'agit du dernier **24.x**, rien d'autre.

### 4.4 Dette adjacente, même fichier

`docker/node/Dockerfile:57` et `:73` :

```dockerfile
corepack prepare pnpm@latest --activate
RUN npm install -g vite@latest webpack@latest webpack-cli@latest
```

Trois cibles mouvantes dans une image censée être figée. Le commentaire des lignes 62-66 raconte
que **ce mécanisme exact a déjà cassé le workflow Docker Build** — `npm@latest` était passé en
12.0.1, qui exige un node que l'image ne fournissait pas. Le symptôme a été corrigé en retirant
`npm@latest` ; la cause est restée en place trois lignes plus bas. Elle repartira au prochain
`vite` ou `webpack` majeur, et le build cassera un jour où personne n'aura touché au projet.

---

## 5. Composer

### 5.1 Dépendances directes — 10 montées, aucune majeure, aucune advisory

| Paquet | Actuel | Disponible | Nature |
|---|---|---|---|
| `laravel/framework` | 13.23.0 | 13.24.0 | mineure |
| `laravel/pulse` | 1.7.4 | **1.8.0** | mineure — lire le changelog, Pulse touche `config/pulse.php` et ADR-0004 n'est pas encore câblé (Story 3.2) |
| `livewire/livewire` | 4.3.3 | 4.3.5 | patch — **porte Alpine**, donc concerne directement la 1.12 et la 1.13 |
| `laravel/telescope` | 5.21.0 | 5.22.0 | mineure |
| `laravel/horizon` | 5.48.1 | 5.48.2 | patch |
| `laravel/nightwatch` | 1.28.5 | 1.28.6 | patch |
| `laravel/boost` | 2.4.13 | 2.5.3 | mineure (outillage IA, hors runtime) |
| `fruitcake/laravel-debugbar` | 4.4.0 | 4.4.1 | patch (dev) |
| `rector/rector` | 2.5.9 | 2.6.1 | mineure (dev, **informatif en CI** — Rector plante déjà, dette connue) |
| `spatie/laravel-health` | 1.40.1 | 1.40.2 | patch |

### 5.2 Le verrou Pest 5 — revérifié, **inchangé**

`composer outdated` complet liste une trentaine de « majeures disponibles ». Elles sont presque
toutes **la même chaîne** : `pest 5` → `paratest ^7.23` → `php-file-iterator ^7`, plus toute la
famille `phpunit/*` et `sebastian/*` qui suit.

Vérification faite ce jour, pas supposée :

```
cmgmyr/phploc   versions : 8.0.x-dev, * 8.0.7, 8.0.6, …
                requires : phpunit/php-file-iterator ^3.0|^4.0|^5.0|^6.0
```

`cmgmyr/phploc` (transitif de `nunomaduro/phpinsights`) est **toujours à 8.0.7** et plafonne
**toujours** à `php-file-iterator ^6`. Le seul verrou identifié le 2026-07-31 n'a pas bougé.

> **Décision PO en vigueur : rester en Pest 4, garder PHP Insights. Ne pas rejouer l'instruction.**
> À rouvrir quand `phpinsights` aura monté `phploc` — et le contrôle tient en la commande
> `composer show cmgmyr/phploc` ci-dessus.

### 5.3 Majeures hors chaîne Pest — à ne pas forcer

`guzzlehttp/guzzle` 7.15.2 → 8.0.2 (et `promises`, `psr7`, `uri-template`), `brick/math`,
`hamcrest`, `logiscape/mcp-sdk-php`, `laravel/roster`. Toutes transitives. Elles arriveront quand
`laravel/framework` élargira ses contraintes ; les forcer à la main, c'est se placer hors du
périmètre testé par l'amont.

---

## 6. npm — 2 paquets

| Paquet | Actuel | Disponible | Remarque |
|---|---|---|---|
| `vite` | 8.2.0 | 8.2.1 | patch |
| `playwright` | 1.59.1 | **1.62.1** | 3 mineures de retard |

**Ce sont les deux seuls périmés, et ce sont les deux qui touchent le runner navigateur.**

`playwright` mérite un traitement à part : [ADR-0013](adr/ADR-0013-runner-navigateur-pest-browser.md)
documente que le runner **ne rend pas la main ~1 run sur 2**, et que la mitigation (lecture du
rapport JUnit) doit être **retirée dès que l'amont est corrigé**. Une montée de 3 mineures est
donc à la fois le premier endroit où regarder si le défaut est réparé, et le premier endroit où
un comportement observé peut changer sous les pieds d'une story en cours.

⚠️ Rappel : `pest-plugin-browser` reste en **4.3.1**. La v5.0.0 exige Pest 5, verrouillé par
`phploc` (§5.2). Monter `playwright` seul est possible — c'est une dépendance npm, pas le plugin.

---

## 7. Dette structurelle, non urgente

- **6 images `:latest` en compose** — `mailpit`, `adminer`, `it-tools`, `dozzle`, `watchtower`
  (`docker-compose.yml`), `redis-commander` (`docker-compose.dev.yml`). Tous en profils `dev` /
  `tools` / `dev-extra`, donc **absents de la production**. Watchtower les met à jour
  automatiquement — mais **watchtower lui-même est en `:latest`**, ce qui veut dire que le
  composant qui décide des mises à jour est celui dont la version est la moins maîtrisée.
  Impact réel : nul en prod, non nul en reproductibilité de l'environnement de dev d'un
  fork-streamer.
- **Rector plante toujours** (`Container::databasePath()` — `rector.php` lie `phpstan.neon`, qui
  inclut Larastan, qui exige une app bootée). Informatif en CI, donc non bloquant. C'est aussi
  l'origine de l'annotation « exit code 1 » visible sur les runs verts : **pas une régression.**

---

## 8. Plan d'exécution — après la Story 1.12

**Ordre choisi par risque croissant. Chaque lot se valide seul avant que le suivant commence.**

> **Ce rapport ne se rappelle pas à votre bon souvenir tout seul — il a été câblé.** Le fichier de
> la Story 1.12 le déclare dans le champ `context:` de son frontmatter, que
> `bmad-code-review` charge à l'étape 1 dès lors que la revue tourne **avec la story passée en
> spec** (`steps/step-01-gather-context.md`, point 5). La tâche **T13** de la story dit quoi en
> faire : rejouer les deux `audit`, vérifier qu'aucune montée n'a été absorbée en silence par un
> `composer update` / `npm install` nu, et ne pas re-signaler ce qui est déjà tracé.
>
> ⚠️ **La revue constate, elle ne monte pas.** Aucun lot ci-dessous ne s'exécute pendant la revue
> de la 1.12.
>
> ⚠️ **Ce câblage tient à un fichier gitignoré.** La story vit sous `_bmad-output/`
> (`.gitignore:219`), donc le lien rapport → revue existe sur une seule machine. C'est la dette
> « `_bmad-output/` n'est ni versionné ni sauvegardé » déjà inscrite dans [`ETAT.md`](ETAT.md),
> rencontrée ici sous une forme neuve : **le plan de rattrapage est moins durable que la dette
> qu'il rattrape.** Le rapport, lui, est versionné.

### Lot A — le digest node *(risque nul, aucune montée de version)*

1. `docker/node/Dockerfile:17` → `FROM node:24.18.0-alpine3.23@sha256:595398b0…`, avec le
   commentaire de php/apache.
2. Puis, séparément, monter au dernier 24.x et réépingler.
3. Corriger la phrase des lignes 33-38, qui devient vraie une fois (1) fait.

*Comment savoir que ça a marché* : `docker compose build node` puis
`docker compose run --rm node node --version`. Et le contrôle de §1 doit désormais montrer un
digest **égal** entre le `FROM` et le tag visé.

### Lot B — composer, patch et mineures *(risque faible)*

Les 10 du §5.1 en une passe, `composer update` **ciblé sur ces paquets** (jamais nu).

*Comment savoir que ça a marché* : `make test` (**149**, chiffre remis à jour à la revue de la 1.12
— « 113+ » était le seuil de trois stories plus tôt, et un seuil périmé ne détecte plus une
régression : 113 verts sur 149 attendus l'auraient passé) · `make quality-ratchet` (0/0/0) ·
`composer audit` (0). Lire le changelog de `pulse` 1.8.0 avant, c'est le seul non-trivial.

### Lot C — npm, **un paquet à la fois** *(risque réel)*

1. `vite` 8.2.1 → `make npm-build` → `make test-browser`.
2. **Puis seulement** `playwright` 1.62.1, **seul**, et en profitant pour mesurer si le blocage
   d'ADR-0013 est réparé : 10 runs de `make test-browser`, compter les « n'a pas rendu la main »
   (référence : 6/10 en août). S'il tombe à 0, **retirer la mitigation JUnit** est un chantier à
   part entière, pas un effet de bord de cette montée.

*Comment savoir que ça a marché* : **29** tests navigateur verts (chiffre remis à jour à la revue de
la 1.12 ; « 20 » datait d'avant cette story), et le compte de blocages consigné.

### Lot D — rien à faire, et c'est une décision

Pest 5 (§5.2), guzzle 8 (§5.3), Node 26 (avant le 2026-10-28). **Écrire « vérifié, refusé, motif
X » vaut mieux que laisser croire que personne n'a regardé.**

### Lot E — la dette du Dockerfile node *(chantier séparé)*

Remplacer `vite@latest webpack@latest webpack-cli@latest` et `pnpm@latest` par des versions
épinglées. Ce n'est pas une montée : c'est supprimer une cible mouvante qui a déjà cassé le build
une fois. À traiter avec l'Epic 2 (quality gates / installeur), pas en marge d'une story front.

---

## 9. Ce que ce rapport ne dit pas

- **Il ne dit rien de Snyk.** `make security-scan` n'a pas été lancé (il exige un jeton et sort du
  périmètre lecture seule). La CI le fait chaque nuit.
- **Il ne dit rien des CVE de paquets Alpine** dans les images construites : `apk upgrade` tourne
  à chaque build, donc l'état dépend de la date du dernier build, pas du contenu du dépôt.
- **Il ne prouve pas qu'une montée est sûre.** Il dit ce qui est disponible et ce qui est
  vulnérable. La preuve, c'est `make test` + `make test-browser` après coup — et pour
  `playwright`, une mesure du taux de blocage.
- **Ce n'est pas un garde-fou.** Aucune de ces vérifications ne rougit toute seule. Les seules qui
  le font sont `composer audit` / `npm audit` en CI nocturne, et le contrôle d'épinglage SHA des
  actions. Le reste est une **relecture** — au même titre que le `grep` de l'audit
  time-as-texture, et il faut le dire pour ne pas confondre les deux.
