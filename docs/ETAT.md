# État du projet — 2026-08-09 (branche `main`)

> ✅ **Epic 1 terminé — 13/13 `done` le 2026-08-20.** La 1.10a, seule story de niveau **C**, a
> passé les trois revues prescrites (`/bmad-code-review` passe 2, `/security-review`,
> `/bmad-review` adversariale). **255 tests · 34 navigateur · ratchet 0/0/0 · PHPStan niveau 10 ·
> `composer audit` 0 · `npm audit` 0.**
>
> ⚠️ La même faille de confiance aux proxys a dû être corrigée **trois fois** : `*`, puis
> `REMOTE_ADDR` (qui désigne le CLIENT sous FastCGI), puis le tableau vide (falsy, donc lu comme
> « jamais configuré », donc joker sur un `Host:` forgé). Défaut final : `TRUST_NOBODY =
> ['0.0.0.0/32']`. Chaque correctif portait une justification confiante et fausse écrite à côté.
>
> **Rétrospective faite le 2026-08-20** → `_bmad-output/implementation-artifacts/epic-1-retro-2026-08-20.md`.
> Verdict : **`accepted-with-open-items`**, critères déclarés. 15 actions inscrites au sprint status.
>
> ⚠️ **FR-Scaff-6 (Pennant) n'a jamais été construit** et Epic 1 le comptait comme couvert : les FR
> déclarés se lisent **9 sur 10**. Reporté en W13 vers Epic 9. Et **cinq garde-fous ont été prouvés
> incapables de rougir** (mutation appliquée, pas déduite) — c'est une dette de *détection*, pas de
> fonctionnement : le comportement livré est correct.
>
> **Prochaine étape : Epic 2** (`2-1-refactor-scripts-lib-common-sh`). Fenêtre à surveiller : A4,
> le scan de couplage aveugle aux FQCN, doit être refait **avant Epic 4** — le premier epic à
> écrire du code métier dans deux modules.

> Point d'entrée de reprise. **Un seul fichier, écrasé à chaque session, jamais accumulé.**
> Il n'a aucune autorité : il pointe vers `epics.md` et `sprint-status.yaml`, jamais l'inverse.

---

## Où j'en suis

> ✅ **LE VERT CI PARLE BIEN DU CODE CI-DESSOUS.** `origin/main` = **`d17964b`**, poussé le
> 2026-08-09, et les **trois workflows sont verts** : `Laravel CI/CD Pipeline` (5 jobs, dont
> **Tests navigateur — 34 tests, 1798 assertions**), `Security Audit`, `Docker Build & Validation`
> (5 jobs, déclenché par la modification du vhost, désormais dans les `paths:`).
>
> **Le risque qu'ADR-0013 nommait est levé** : l'AC8 (`initiatorType`) est vert sur le Chrome for
> Testing d'Ubuntu (**glibc**) comme sur le Chromium d'Alpine (**musl**). C'est la seule assertion
> de la story qui dépend de ce que le moteur *rapporte* plutôt que de ce qu'il *fait* — elle
> tenait des deux côtés, ce qui n'était pas acquis.
>
> ⚠️ **DEUX NOTES PÉRIMÉES, CORRIGÉES ICI.** (1) « 3 commits non poussés » était **faux** :
> `origin` était déjà à `810d3ad`. (2) « `origin` injoignable depuis les sessions d'agent » est
> **faux aussi** — le remote est en SSH, mais le push passe par `gh` en HTTPS :
> `git -c credential.helper='!f() { echo username=x-access-token; echo "password=$(gh auth token)"; }; f' push https://github.com/Kaelyscius/laravel-skeleton.git main:main`
> (scopes `repo` + `workflow` requis ; `--force-with-lease` ne marche PAS par cette voie).
> ⚠️ La règle de fond ne change pas : `refs/remotes/origin/main` est un **cache local**, et c'est
> exactement lui qui a fait vivre ces deux affirmations fausses pendant trois sessions. **`git fetch`
> avant toute affirmation sur `origin`** — et par HTTPS, puisque le `fetch` SSH échoue ici.

L'appareil de vérification est réparé — 3 workflows CI verts sur le dernier état poussé,
**179 tests** + **34 tests navigateur**, ratchet ECS/PHPStan 0/0/0. **Un navigateur affiche désormais ce projet** : le spike
runner est fait, `make test-browser` existe et son rouge a été observé. Epic 1 : stories 1.1 → 1.8,
1.11, 1.12 et 1.13 `done`, **1.9 `done`** (implémentée le 2026-08-09, puis **DEUX passes de revue**
le même jour : 21 correctifs + 5 reports à la première, 21 correctifs + 6 reports à la seconde),
**1.10a `review` — implémentée les 2026-08-09/10, revues de niveau C à faire**, Epics 2 à 11 non
démarrés. Le squelette a désormais **une porte** : `/admin`, authentifiée, refusée par défaut,
et qui s'éteint avec `MODULE_ADMIN_ENABLED=false`.

**La typographie a un corps.** Les quatre faces IBM Plex sont self-hostées, servies depuis le
domaine de l'application, et un navigateur a **constaté** qu'elles sont chargées — pas déclarées.

Le roundtable du 2026-07-30 a **réordonné le reliquat d'Epic 1** et arbitré la conception de
l'écran offline : voir [ADR-0011](adr/ADR-0011-observation-avant-composition.md) et
[ADR-0012](adr/ADR-0012-ecran-offline-et-module-media.md). L'ancienne note `RESUME-1.9.md`
prescrivait une séquence désormais fausse : elle a été supprimée.

## ⛔ Règle de cadrage — décidée le 2026-07-31

> **Plus aucun roundtable party-mode jusqu'à ce que l'Epic 1 soit terminé.**
>
> Motif : 132 stories au plan, **8 `done` (6 %)**, dernière story livrée le **25 juillet**, et
> **trois sessions consécutives sans qu'une seule story avance**. La dérive est identifiable :
> l'ADR-0012 a conçu en détail l'écran offline — job, hiérarchie, sources, module `Media`,
> table `media_items` — c'est-à-dire du **travail d'Epic 4 fait pendant l'Epic 1**, alors qu'il
> reste 5 stories à livrer.
>
> Le mécanisme n'est pas accidentel : convoquer des agents qui font correctement leur métier
> produit nécessairement plus de décisions que de code. Un PM à qui on demande un avis instruira
> le produit, pas la livraison.
>
> Ce qui reste autorisé : une question ponctuelle à un agent unique sur un point bloquant.
> Ce qui ne l'est plus : une table de 3-5 voix sur plusieurs tours.
>
> **Levée de la règle : quand `epic-1: done`.**

## Pest 5 — instruit et REFUSÉ le 2026-07-31 (ne pas rejouer)

Pest 5.0.2 est sorti. La montée **ne résout pas** sur cette stack :

```
pestphp/pest 5  →  brianium/paratest ^7.23  →  phpunit/php-file-iterator ^7
nunomaduro/phpinsights  →  cmgmyr/phploc 8.0.7  →  php-file-iterator ^3|^4|^5|^6
```

`cmgmyr/phploc` plafonne à `^6`. Vérifié en copie jetable, hors du projet : **en retirant
phpinsights, Pest 5.0.2 + PHPUnit 13.2.6 + php-file-iterator 7.0.0 résolvent proprement.**

**Décision PO : on reste en Pest 4 et on garde PHP Insights.** Le spike vise donc
`pest-plugin-browser` **v4.3.1**. À rouvrir quand `nunomaduro/phpinsights` aura monté `phploc` —
c'est le seul verrou.

> ⚠️ Piège rencontré en instruisant ce point : `composer remove --no-update` lancé dans le
> conteneur **modifie le vrai `src/composer.json`** (bind mount). Pour tout test de résolution,
> copier `composer.json` dans un dossier hors projet et utiliser un conteneur `composer:2`
> jetable.

## ✅ Spike runner navigateur — FAIT le 2026-08-06 ([ADR-0013](adr/ADR-0013-runner-navigateur-pest-browser.md))

Les quatre critères d'ADR-0011 sont satisfaits, **le (4) compris : le rouge a été observé**.
`make test-browser` existe. Le doute qui justifiait tout le réordonnancement est levé —
**le token `--font-sans` gouverne bien la cascade réelle**, l'invariant « import sans `layer()` »
de la Story 1.8 tient dans un vrai navigateur.

Trois choses à savoir avant d'y retoucher :

1. **Le verdict ne vient pas du code de sortie de `pest`.** Le plugin ne rend pas la main
   ~1 fois sur 2 (mesuré : 6 blocages / 10 runs), verts comme rouges. Le verdict est lu dans le
   rapport JUnit, écrit avant le teardown qui se bloque. Si `make test-browser` affiche
   « ⚠️ Le runner n'a pas rendu la main », **ce n'est pas un échec** — c'est le défaut amont.
2. **Chromium ne peut pas être celui de Playwright** : builds glibc, images Alpine musl.
   C'est le Chromium natif d'Alpine, lié dans le cache Playwright par un script qui *dérive* la
   révision au lieu de l'écrire en dur.
3. **`tests/Browser` n'est pas une testsuite `phpunit.xml`**, délibérément — sinon
   `php artisan test` l'exécuterait et exigerait un Chromium en CI et en prod.

> ⚠️ Pièges de démarrage, toujours valables :
> 1. `/usr/bin/docker` est un lien vers `/mnt/wsl/docker-desktop/cli-tools/…`, **cible absente
>    tant que Docker Desktop ne tourne pas** côté Windows.
> 2. Des conteneurs redémarrés après un redémarrage de Docker Desktop peuvent avoir des **bind
>    mounts vides** (`/var/www/html` sans `artisan`). Correctif : `make down` puis `make up-local`
>    — recréer, pas redémarrer.
> 3. **Base de dev non semée → `/` répond 404** (voir la dette ci-dessous). `php artisan db:seed`.

> ✅ **Livewire déclaré le 2026-07-31** : `"livewire/livewire": "^4"` est désormais une
> dépendance directe de `src/composer.json` (v4.3.3). **Ne PAS ajouter `alpinejs` via npm** :
> Livewire 4 embarque déjà Alpine dans son bundle, et deux Alpine enregistrés en parallèle est
> un bug classique. Alpine arrive donc avec `@livewireScripts` — à câbler dans le layout
> (Story 1.13), pas avant.

## Rafraîchissement supply chain — 2026-08-06

**Les 7 branches distantes ouvertes ont été fermées, aucune n'était mergeable.** Toutes datent
d'avant l'épinglage par digest du 2026-07-27 : les fusionner aurait **remplacé un digest par un
tag mutable**, donc annulé la décision d'architecture §7.1. Leur intention était juste, leur
forme non — le rattrapage s'est fait en rafraîchissant les épinglages.

| | Avant | Après |
|---|---|---|
| PHP | 8.5.4 / Alpine 3.22 | **8.5.9 / Alpine 3.24.1** |
| Redis | 8.8.1 | **8.10.0** |
| Apache | 2.4.68 | inchangé — le digest était déjà à jour |
| Actions GitHub | 9 tags mutables + 6 SHA périmés | **tout en SHA, versions courantes** |

> ⚠️ Rupture silencieuse évitée au passage : `codecov-action` a **supprimé** l'entrée `file`
> en v5 au profit de `files`. Une entrée inconnue est ignorée sans erreur — la couverture aurait
> cessé d'être envoyée sans que rien ne rougisse.

> ⚠️ Le commentaire de version du `FROM` PHP annonçait « 8.5.8 » pendant que le digest servait
> **8.5.4**. Un commentaire n'est contredit par rien : il se vérifie dans l'image
> (`docker run --rm <image> php -r 'echo PHP_VERSION;'`), il ne se recopie pas du tag.

## Supply chain — plan exécuté le 2026-08-09

Le plan §8 de [`supply-chain-2026-08-08.md`](supply-chain-2026-08-08.md) a été exécuté.
**Lots A, B, C, D faits. Lot E toujours ouvert.** Baseline rejouée avant de toucher quoi que ce
soit : `composer audit` 0, `npm audit` 0, et les deux listes de retard identiques à celles du
rapport — **rien n'avait été absorbé en silence** par un `composer update` / `npm install` nu.

| Lot | Fait | Preuve |
|---|---|---|
| **A** — digest node | `FROM node:24.19.0-alpine3.23@sha256:244cc2b5…` | build + `node --version` → **v24.19.0**, `npm` → **11.17.0** |
| **A bis** — digest composer | `FROM composer:2@sha256:4d71c3c2…` (= 2.10.2) | `composer --version` dans le conteneur → **2.10.2** |
| **B** — composer | les 10 paquets du §5.1, `update` **ciblé** | **149 tests** verts · ratchet **0/0/0** · `composer audit` **0** |
| **C** — npm | `vite` 8.2.1 puis `playwright` 1.62.1, **un par un** | `npm run build` OK · **29 tests navigateur** verts · `npm audit` **0** |
| **D** — refus | revérifiés, pas recopiés | ci-dessous |
| **E** — `@latest` du Dockerfile node | **non fait**, chantier séparé | → Epic 2 |

### 🔴 Ce que le rapport avait manqué : `composer:2`

Le §4.1 affirmait que `docker/node/Dockerfile` était **le seul** `FROM` non épinglé. C'était
faux. `docker/php/Dockerfile:101` portait `FROM composer:2` — une **majeure flottante**, donc un
épinglage strictement plus lâche que celui de node (qui avait au moins une version exacte). Le
binaire qui résout et installe **toutes** les dépendances PHP du projet pouvait changer entre
deux builds sans qu'aucun fichier du dépôt ne bouge.

C'est le motif du projet appliqué au document qui le traque : **le rapport qui recense les
affirmations sans référent en a produit une.** Corrigé dans le même passage.

### La phrase fausse du Dockerfile node — corrigée, et datée

`docker/node/Dockerfile` justifiait `apk upgrade` par « la reproductibilité de la BASE reste
assurée par l'épinglage de l'image », alors qu'il n'épinglait que par tag. La phrase est
désormais vraie, **et elle dit depuis quand elle l'est** (fausse du 2026-07-27 au 2026-08-09) et
à quoi elle est suspendue : si le `@sha256:` disparaît, la justification disparaît avec.

### ✅ Le blocage ADR-0013 : 0/10 après la montée de playwright

Mesuré le 2026-08-09, 10 runs consécutifs de `make test-browser` :
**0 blocage, 10/10 verts, 29 tests à chaque fois.** Référence d'août : **6 blocages / 10**.

Deux choses à savoir avant d'en conclure quoi que ce soit :

1. **La mesure isole bien `playwright`.** L'image du runner (`docker/php/Dockerfile` cible
   `test`) **n'a pas été rebâtie** — vérifié : image de 27 h, Chromium **150.0.7871.181**
   inchangé, `apk upgrade` non rejoué. La seule variable qui a bougé dans l'environnement du
   runner est `playwright` 1.59.1 → 1.62.1, via le bind mount de `node_modules`.
2. **Ce n'est PAS une comparaison contrôlée.** Le 6/10 d'août portait sur **8** tests navigateur
   et une autre image ; le 0/10 porte sur **29**. Charge, durée et ordonnancement diffèrent.
   → **Le bras témoin manque** : 10 runs à `playwright@1.59.1` *aujourd'hui*, même image, même
   suite. Tant qu'il n'est pas fait, on a une **observation encourageante, pas une preuve que
   l'amont est réparé** — et **la mitigation JUnit reste en place**. ADR-0013 dit déjà que la
   retirer est un chantier à part entière ; ce chantier commence par ce bras témoin.

> ⚠️ Au passage, un garde-fou a prouvé sa valeur : la révision Chromium attendue par Playwright
> est passée de **1217 à 1234**. `link-alpine-chromium.sh` la **dérive** de `browsers.json` au
> lieu de la coder en dur — la suite navigateur serait rouge à l'instant si le spike avait écrit
> « 1217 ».

### Lot D — vérifié, refusé, et le motif

| Sujet | Verdict | Motif, **revérifié le 2026-08-09** |
|---|---|---|
| **Pest 5** (+ `pest-plugin-*`) | refusé | `composer show cmgmyr/phploc` → toujours **8.0.7**, toujours `php-file-iterator ^3\|^4\|^5\|^6`. Le verrou n'a pas bougé. Décision PO inchangée : Pest 4 + PHP Insights. |
| **guzzle 8** | refusé | Installé **7.15.3** (monté en transitif). Le forcer, c'est sortir du périmètre testé par `laravel/framework`. Arrivera quand l'amont élargira. |
| **Node 26** | refusé | v24 Active LTS jusqu'au **2026-10-20**, v26 LTS seulement le **2026-10-28**. Nous sommes le 2026-08-09. Raisonnement complet en tête de `docker/node/Dockerfile`. |

**Et un refus qui s'est levé tout seul** : `laravel/roster` est passé **v0.5.1 → v1.0.0**. Le
§5.3 le listait parmi les majeures « à ne pas forcer » — il n'a pas été forcé : `laravel/boost`
2.5.3 exige désormais `^1.0.0`. C'est exactement le mécanisme que le §5.3 décrivait, observé.

### ⚠️ Effet de bord à trancher : `composer update` a réécrit `src/CLAUDE.md`

`laravel/boost` 2.5.3 lance `boost:update` en script post-update, qui a réécrit
`src/CLAUDE.md` — un fichier **versionné**. Deux changements de sens opposé :

- ✅ **Il supprime la liste de versions en dur** (« laravel/framework v13, pest v4… ») au profit
  de « vérifie la version installée, ne la suppose pas ». C'est une assertion qui dérivait,
  retirée.
- 🔴 **Il ajoute une consigne impérative pointant vers `.ai/rules`, qui n'existe pas ici**
  (vérifié : ni `.ai/rules`, ni `src/.ai/rules`). La consigne se termine par « si le répertoire
  n'existe pas, continue » — donc inoffensive, mais c'est **une instruction sans référent
  introduite par un outil dans un fichier du dépôt**, au neuvième exemplaire du motif.

## Laravel Boost — cadré le 2026-08-09 (l'effet de bord ci-dessus, tranché)

**Décision PO : on garde Boost, on le cadre.** Trois changements, plus un garde-fou.

**1. `boost:update` ne tourne plus automatiquement.** Il était dans `post-update-cmd` de
`src/composer.json` : il réécrivait `src/CLAUDE.md`, **fichier versionné**, à chaque
`composer update`, hors de toute revue. Retiré. Point d'entrée unique : `make boost-update`,
qui rappelle de relire le diff et de relancer `make test`.

**2. Les guidelines sont enfin LUES.** `boost:update` écrit dans `src/CLAUDE.md`, mais une
session ouverte à la racine du dépôt ne charge que le `CLAUDE.md` **racine**. Elles étaient
donc versionnées, tenues à jour… et jamais dans le contexte. Le `CLAUDE.md` racine porte
désormais `@src/CLAUDE.md`.

**3. Le bloc `.ai/rules` est retiré.** Boost 2.5.3 y imposait de lire `.ai/rules/index.md`
avant toute écriture de code — répertoire inexistant ici. L'ajouter aurait créé une
**cinquième couche documentaire sans autorité définie**, alors que la hiérarchie est fixée
(ADR > epics.md + sprint-status.yaml > ETAT.md). Remplacé par un pointeur vers les vrais
emplacements.

**4. 🛡️ Le garde-fou : `src/tests/Unit/BoostGuidelinesTest.php`** — parce que rien de ce qui
précède ne tient si le prochain `boost:update` réinjecte autre chose. Deux invariants :
*tout import `@chemin` d'un fichier de consignes résout sur disque* · *le `CLAUDE.md` racine
importe bien `src/CLAUDE.md`*. **Les trois assertions ont été observées ROUGES** — les deux
premières sur les défauts réels avant correction, la troisième (anti-vacuité) par mutation.

> ⚠️ **Un piège Pest rencontré en écrivant ce test, et déjà catalogué** : `toContain()` est
> **variadique**. `expect($a)->toContain('x', 'mon message')` cherche **deux** valeurs dans le
> tableau — l'assertion devient impossible à satisfaire. La Story 1.8 avait rencontré la
> version symétrique (des `toContain()` qui ne pouvaient pas *échouer*). Pour une appartenance
> avec message : `expect(in_array($v, $a, true))->toBeTrue($message)`.

### 🔌 Et le MCP Boost : il n'était pas chargé, et on sait pourquoi

`claude mcp list` répond `laravel-boost … ✔ Connected`, mais **aucun de ses 12 outils n'était
atteignable** dans la session du 2026-08-09. Cause : le serveur est déclaré comme
`docker exec -i laravel-app_php php artisan boost:mcp`, et **Docker Desktop ne tournait pas au
démarrage de la session**. Le serveur a échoué à l'initialisation ; le registre d'outils est
figé à ce moment-là. Un `mcp list` lancé plus tard refait un contrôle neuf et réussit — d'où
l'apparence trompeuse.

👉 **Démarrer Docker Desktop AVANT `claude`.** Les 12 outils apparaissent alors :
`ApplicationInfo` · `Tinker` · `DatabaseSchema` · `DatabaseQuery` · `DatabaseConnections` ·
`SearchDocs` · `LastError` · `ReadLogEntries` · `BrowserLogs` · `GetAbsoluteUrl` · `RecordRule`.

Trois d'entre eux tapent exactement dans le mode de défaut du projet, parce qu'ils **résolvent
un référent au lieu de le supposer** : `DatabaseSchema`/`DatabaseQuery` (le défaut du 31 juillet
— `laravel_test` à 0 table — se voyait en une requête), `Tinker` (c'est ce qui a démenti l'AC1
de la 1.12), `SearchDocs` (documentation versionnée des paquets réellement installés).

## Boucle qualité par story — écrite le 2026-08-07

👉 **[`docs/process/03-boucle-qualite.md`](process/03-boucle-qualite.md)** est
désormais le document opérationnel à ouvrir à chaque story. Il classe la story
en **S / R / C** et n'applique la cérémonie que si le niveau l'appelle — une
boucle qu'on applique intégralement à tout est une boucle qu'on contourne.

La règle sans exception : **aucun garde-fou n'est livré sans avoir été VU rouge.**
Et pas de seuil de couverture en CI — il aurait été vert pendant tout ce que
cette session a trouvé.

## ✅ Story 1.11 — LIVRÉE le 2026-08-08 (première vraie story depuis le 25 juillet)

6 composants Blade anonymes (`button`, `card`, `badge`, `icon-button`, `divider`,
`toast`), la migration `social_links` et une galerie de démonstration gardée par
l'environnement. **98 tests** (67 → 98) et **8 tests navigateur** (1 → 8),
ratchet **0/0/0**, PHPStan niveau 10.

**21 garde-fous, tous VUS ROUGES** en 6 lots de mutation — aucun déclaré opérant
sur supposition. Détail dans le Debug Log de la story.

Trois choses à retenir, qui resserviront :

1. **`:active` s'observe sans hack** : focaliser l'élément puis MAINTENIR la barre
   d'espace (`withKeyDown`). Chromium applique alors `:active` comme sur un vrai
   appui — un `dispatchEvent` ne l'aurait jamais fait.
2. **Muter le token à chaud est la seule assertion qui distingue « c'est orange »
   de « c'est lava »** : `document.documentElement.style.setProperty('--accent-lava', …)`
   doit déplacer la valeur calculée. Un `#FF5722` en dur passe tout le reste.
3. **`outline-offset` sur un `outline-none` ne décale rien.** En Tailwind 4,
   `outline-none` pose `outline-style: none` ; l'anneau visible est une
   box-shadow, donc `outline-offset` est calculé à 2px et ne peint rien. Le
   décalage réel vient de `ring-offset-*`, et `outline-hidden` (et non
   `outline-none`) conserve un indicateur en contrastes forcés. **Trouvé par la
   revue de code, pas par les tests** — l'assertion, elle, était verte.

> `tokens.css` RÈGLE 2 a été **amendée dans le même commit** : l'anneau de focus
> lava sur tout élément focusable y est désormais inscrit comme exemption (c'est
> un état, pas une 5ᵉ surface). Le code la commentait sans que le document le
> dise — forme exacte du motif dominant.

## ✅ Story 1.10a — IMPLÉMENTÉE les 2026-08-09/10 (le squelette a une porte)

**Livré** : `filament/filament ^5` (v5.7.6, 30 installs, `composer audit` 0, `npm audit` 0), un
panel `/admin` **vide** monté dans le module `Admin`, `User implements FilamentUser` +
`HasRoles`, un `RoleSeeder` idempotent, et **38 tests neufs** (179 → **217**). Ratchet **0/0/0**,
PHPStan niveau 10, 34 tests navigateur toujours verts.

**Quatre helpers de tests extraits**, tous pour le motif déjà écrit par `RouteTable` (« dupliquer
des lignes délicates garantit qu'une des deux copies dérive ») : `Tests\Support\ModuleBoot` (la
mécanique de boot d'application jetable, sortie de `ModuleActivationTest` pour qu'un autre fichier
puisse tourner **seul**) et `Tests\Support\HttpProbe` (requête HTTP typée à travers le noyau —
dans une closure Pest, PHPStan résout `$this` en `TestCall`, ce qui coûtait 49 erreurs au niveau 10).

### Les cinq choses qu'elle a trouvées, toutes mesurées

1. 🔴 **`MODULE_ADMIN_ENABLED=false` servait `/admin` en 302.** `filament:install --panels`
   enregistre son `PanelProvider` dans `bootstrap/providers.php`, qui est **inconditionnel**.
   ADR-0009 §Conséquences promettait l'inverse. Corrigé : le provider vit sous
   `App\Modules\Admin\Providers\Filament\` et c'est `AdminServiceProvider::register()` qui
   l'enregistre. `/admin` répond désormais **404** module éteint — vu rouge avant correction.

2. 🔴 **Le rate limiting du login ne limitait rien, et la cause était ailleurs.**
   `TRUSTED_PROXIES` valait `*`, que Laravel traduit par
   `setTrustedProxies(['0.0.0.0/0', '::/0'])` — *toute* adresse d'Internet devient un proxy de
   confiance. Symfony remonte alors `X-Forwarded-For` jusqu'à l'entrée **la plus à gauche**,
   écrite par le client. Mesuré sous la topologie réelle : `X-Forwarded-For: 198.51.100.42,
   203.0.113.9` → `request()->ip()` = **198.51.100.42**. La clé de seau en dérivant, un attaquant
   obtenait **un seau neuf par tentative**.
   **Défaut passé à `REMOTE_ADDR`** (le pair immédiat, et lui seul) : la détection HTTPS continue
   de marcher sans configuration, et le préfixe forgé est ignoré. `*` écrit explicitement reste
   honoré — le neutraliser en douce ferait mentir le fichier de configuration.
   ⚠️ **La story se trompait sur un point** : elle disait `TRUSTED_PROXIES` « absente de `.env`
   **et** de `.env.example` ». Elle était bien dans `.env.example:90`, avec un commentaire qui la
   **justifiait** (« safe quand l'app est TOUJOURS derrière un reverse-proxy » — faux : Apache
   *ajoute* à `X-Forwarded-For`, il ne remplace pas).

3. ⛔ **`make test-drift` est DESTRUCTIF, et le dépôt le documentait à l'envers.**
   `pestphp/pest-plugin-drift` n'est **pas** un outil de mutation ni de couverture : c'est le
   **migrateur PHPUnit → Pest**. Un seul appel a **réécrit 7 fichiers de tests**, supprimé
   l'invariant délibéré de `tests/Unit/ExampleTest.php` *avec toute sa justification*, et injecté
   des imports cassés dans deux autres. La cible `make test-drift` affiche désormais un
   avertissement et n'exécute plus rien (`make test-drift-force` pour forcer) ; `CLAUDE.md` est
   corrigé aux trois endroits où il l'annonçait comme une analyse.
   ⚠️ **Conséquence pour la boucle qualité** : l'étape 5 du niveau C nommait `make test-drift`
   « la mutation plutôt que la couverture ». Cette exigence reposait sur une prémisse fausse. Ce
   qui l'a remplacée : une **campagne de mutation manuelle de 15 mutations, 15 rouges observés**.

4. ⛔ **`filament:install` a réécrit `composer.json` en entier** (indentation 2 → 4 espaces),
   noyant son unique ajout de fond dans un diff de 153 lignes. C'est le motif qui avait fait
   retirer `boost:update` de `post-update-cmd` le 2026-08-09, en pire : l'outil masquait sa propre
   modification. Mise en forme restaurée à la main ; diff ramené à **3 insertions**.

5. **La CSP ne touche pas le panel, et la mise en garde était sans objet.** Mesuré, CSP forcée :
   `/_layouts` porte l'en-tête, `/admin/login` non — Filament construit sa propre pile et ne
   traverse pas le groupe `web`. Le commentaire de `bootstrap/app.php` qui annonçait le contraire
   est corrigé dans le même commit.

### Les deux questions ouvertes, tranchées

- **Q1 — `TRUSTED_PROXIES` restreint, ou clé de seau indépendante du client ?** → **(a)**, la
  cause. Le correctif vaut pour toutes les limitations à venir (`api/*`, `register`,
  `comment.store`) et pour la protection de `/pulse` (Story 3.2).
- **Q2 — `filament:upgrade` en `post-autoload-dump` ?** → **oui, par nécessité.** Les assets
  publiés étant gitignorés (AC8), un `composer install --no-dev` en production servirait sinon un
  panel **sans CSS ni JS**. L'exclusion et la republication sont un seul choix et sa conséquence.

### Ce qu'elle n'a délibérément PAS fait

Aucune ressource Filament (la `SettingsResource` de la 1.10b est en **Epic 5**) · aucun
`vendor:publish` Sanctum (il reste **inerte**, sa table n'existe pas) · aucun thème · la CSP
**n'est pas allumée** (`CSP_ENABLED=false` reste la valeur du dépôt) · le `firstOrFail()` de
`SetCurrentStreamer` **n'est pas corrigé** — entrée toujours **ouverte** de `deferred-work.md`,
elle touche la couche tenancy et demande son propre rouge d'abord.

## Prochaine action — les **revues de la 1.10a**, puis la clôture d'Epic 1

> ✅ **La 1.10a est implémentée** (2026-08-09/10) et passée en `review`. **Elle n'est PAS `done`** :
> c'est la seule story de **niveau C — Critique** du projet, et sa boucle qualité impose des
> revues que le développement ne peut pas se donner à lui-même.

> ⚠️ **CETTE SECTION A CHANGÉ LE 2026-08-20.** Elle annonçait **trois** revues à faire. C'est
> faux sur les deux moitiés : la première est **déjà passée** (le 2026-08-10, `/bmad-code-review`
> en mode `full`, 25 fichiers / 2 640 lignes, 3 décisions + 10 correctifs + 3 reports), et il n'y
> en aura pas trois — **le plafond est désormais de DEUX passes de revue de code par story**
> (`docs/process/03-boucle-qualite.md` §Étape 3, décidé sur mesure le 2026-08-20).

### Ce qu'il reste, dans l'ordre

**1. Traiter les 13 constats de la passe 1** — ils sont **tous non cochés** dans la story.
Vérifiés sur disque le 2026-08-20, toujours ouverts : `P2` (SHA `3f345f2` figé en dur,
`FilamentPublishedAssetsTest.php:117` — rouge garanti dès que ce commit n'est plus HEAD),
`P3` (`src/public/fonts/filament` n'existe pas — un tiers du garde-fou d'assets ne garde rien),
`P4` (`canAccessPanel()` : muter en `return $this->hasRole('super-admin')` laisse toute la suite
verte), `P8` (nom de test énonçant l'inverse de son assertion), `P9` (`HttpProbe::html()` sans
consommateur). **`D1` fait exception** : son correctif est **sur disque**
(`App\Core\Exceptions\NoStreamerConfiguredException`) et `deferred-work.md` le déclare résolu —
**seule la case de la story n'est pas cochée.** Écart code ↔ document = le motif du projet.

**2. La passe 2 — et c'est la DERNIÈRE.** Elle doit porter sur **ce que les correctifs P1→P10
auront écrit**, pas relire Filament une troisième fois. C'est la différence mesurée entre la
passe 2 de la 1.9 (21 correctifs, elle relisait du code neuf) et celle de la 1.3 (0 correctif,
elle relisait du code déjà lu).

```
/bmad-code-review _bmad-output/implementation-artifacts/1-10a-install-filament-v5-sanctum-permission.md
```

⚠️ **Passer le fichier de story en argument** : sans lui, le champ `context:` n'est pas lu et les
trois ADR (0009, 0010, 0002) ne sont pas embarqués.

**3. `/security-review` + `composer audit && npm audit` + `make security-scan`** — **hors quota**,
obligatoires en niveau C. Un scanner ne fabrique pas de la confiance, il constate.

**4. Commit.** 34 entrées non commitées portent la story, dont la couche d'authentification et
`bootstrap/app.php`. **Aucune CI ne les a vues** : le vert des 3 workflows parle de `3f345f2`.

**5. `1-10a-…` → `done`, puis `epic-1-retrospective`** — les 13 stories d'Epic 1 livrées.

### 6. 🔀 PUIS FUSIONNER LA READING ROOM — ne pas l'oublier ici

Une documentation globale interactive a été construite le 2026-08-20 **dans un worktree isolé**,
précisément pour ne pas perturber la 1.10a en cours. Elle attend la clôture de la story.

```bash
git worktree list                       # /home/alex/myLaravelSkeleton-reading-room [docs/reading-room]
git merge --no-ff docs/reading-room     # depuis main, une fois la 1.10a commitée
git worktree remove ../myLaravelSkeleton-reading-room && git branch -d docs/reading-room
```

**Le merge a été éprouvé à blanc le 2026-08-20**, contre un `main` simulé portant la 1.10a
commitée : **propre**, aucun conflit, et `docs/process/03-boucle-qualite.md` conserve **les deux**
modifications (le plafond de revues côté branche, la correction `test-drift` côté `main`). Suite
Unit dans l'état fusionné : **20 verts**.

Ce qu'elle apporte : `docs/reading-room/index.html` (page autonome, hors ligne, sans CDN) +
`src/tests/Unit/ReadingRoomReferentsTest.php`. ⚠️ **Elle n'a AUCUNE autorité** — la hiérarchie
reste ADR > `epics.md` + `sprint-status.yaml` > `ETAT.md`, et elle se range dessous. Elle le
déclare sur elle-même. Ce qu'elle garantit en revanche : **chaque fichier qu'elle cite existe**,
gardé par 3 assertions, dont une mutation qui a **survécu** au premier jet (19ᵉ instance du motif,
cette fois dans le garde-fou lui-même) puis une campagne rejouée — **5 mutations, 5 rouges**.

### Créer le premier administrateur — la commande à connaître

Aucun compte administrateur n'est semé, **délibérément** : un `super-admin` semé porterait un mot
de passe connu du dépôt, et `db:seed` tourne dans `make fresh`, en CI et au déploiement. Le seeder
pose le **rôle**, l'opérateur pose l'**utilisateur** :

```bash
make artisan cmd="db:seed"     # crée le rôle super-admin (idempotent)
make filament-user             # crée le compte — INTERACTIF, d'où une cible dédiée
```

Puis assigner le rôle, dans un tinker interactif :

```bash
make artisan cmd="tinker"
# >>> App\Models\User::query()->where('email', 'vous@exemple.test')->firstOrFail()->assignRole('super-admin');
```

> ⚠️ **`make artisan cmd="make:filament-user"` NE FONCTIONNE PAS**, et la recette recopiée ici
> auparavant ne pouvait pas marcher : `make artisan` lance `docker compose exec` **sans `-i` ni
> `-t`**, donc une commande qui pose des questions n'a ni stdin ni terminal. Relevé en revue le
> 2026-08-20 (finding Q16) — sur le chemin de création du **premier** administrateur, c'est-à-dire
> la toute première chose qu'un fork-streamer exécute. La cible `make filament-user` alloue le TTY ;
> `make artisan-it cmd="…"` fait la même chose pour n'importe quelle autre commande interactive.
> Le `tinker --execute` d'origine, avec ses guillemets doubles échappés à travers Make et deux
> shells, était fragile pour la même raison : il est remplacé par un tinker interactif.

Sans le rôle, le compte existe mais `/admin` répond **403** — c'est le comportement voulu :
appartenir à la table `users` n'accorde rien.

### Commande d'ouverture de la prochaine session

```bash
make up-local && make test && make quality-ratchet && make npm-build && make test-browser
# attendu : 255 tests exit 0 · ratchet 0/0/0 · 34 tests navigateur verts
#            (179 → 255 : +61 tests apportés par la 1.10a et sa revue)
#
# ⚠️ Le chiffre a été FAUX en trois endroits jusqu'au 2026-08-20 : le dossier
#    annonçait 217 quand la suite en comptait 226, puis 240 après les correctifs
#    de revue. C'est le motif que T10 signale — « compter ce qu'on rejoue
#    vraiment » — appliqué à la commande d'ouverture de session elle-même, qui
#    énonçait donc un attendu impossible à atteindre.
```

⛔ **`make npm-build` AVANT chaque `make test-browser`** dès que `app.js`, la CSS **ou
`resources/fonts.json`** bouge — y compris entre deux mutations. Le runner ne construit rien, et
depuis la 1.9 il lit aussi `public/fonts/`, qui est produit par le build.

### Ce que la 1.9 a livré, et les deux choses qu'elle a trouvées

**Livré** : `resources/fonts.json` (la table unique — 4 faces, 2 licences), un plugin Vite
**inline** qui copie depuis `node_modules` vers `public/fonts/` au `buildStart` (aucun paquet npm
ajouté, `/public/fonts` gitignoré), `<x-font-preloads />` — qui rend **les preloads ET les quatre
`@font-face`**, les deux côtés dérivant de la table et passant par `asset()`, donc solidaires sous
un déploiement en sous-chemin —, `config/fonts.php`, la page `/_fonts` doublement gardée, et
**33 tests neufs** (28 Feature + 5 navigateur).

⚠️ **Il n'y a PAS de `resources/css/fonts.css`, et `app.css` n'est pas modifié.** Une feuille
statique ne peut interpoler aucun préfixe de déploiement : elle imposait `url('/fonts/…')` en
racine absolue, donc quatre 404 muets chez un fork-streamer sous sous-chemin. Supprimée à la
première passe de revue.

**⚖️ L'arbitrage tenu** : **4 faces servies, 3 préchargées**. La face 500 existe pour que
`font-medium` — employé 8 fois, dont 4 dans des composants `done` — ait un référent ; elle n'est
pas préchargée parce qu'elle n'est pas garantie au-dessus de la ligne de flottaison. Aucun Blade
n'a été modifié.

**Trouvaille n°1 — l'AC8 était écrit avec un repli, et le repli n'a pas servi.** L'AC prévoyait
que Chromium puisse ne pas distinguer un téléchargement déclenché par le `<link rel="preload">`
d'un téléchargement déclenché par la découverte du `@font-face`. **Mesuré avant d'asserter**
(Chromium 150 d'Alpine, 2026-08-09) : il les distingue proprement — les trois faces préchargées
rapportent `initiatorType: "link"`, la face 500 rapporte `"css"`. L'assertion est donc écrite sur
l'observable réel, et **bilatéralement** : c'est la moitié « les faces NON préchargées valent
`css` » qui rougit si quelqu'un ajoute un preload sans le décider.

**Trouvaille n°2 — une mutation a SURVÉCU, et c'était le motif du projet une fois de plus.**
Basculer un `preload` de `true` à `false` dans `resources/fonts.json` ne faisait rougir personne :
le composant **dérivait** son rendu de la table, et le test qui le vérifiait **dérivait** ses
attentes de la même table. Les deux côtés se calculaient l'un l'autre — le compte restait
cohérent, le preload disparaissait, la page restait jolie. C'est mot pour mot la réserve écrite
en tête de `tests/Fixtures/RelativeTimeCases.php` (« une table que les deux côtés liraient pour se
calculer l'un l'autre ne prouverait rien »), et elle n'avait pas été appliquée ici.

> **Correctif** : un test écrit **en dur** le jeu servi (4) et le jeu préchargé (3) — il ne
> décrit pas la table, il décrit la **décision** dont la table est l'exécution (UX-DR-42 +
> arbitrage PO du 2026-08-09). Mutation rejouée **dans les deux sens**, rouge observé.
>
> 📌 **Règle qui se généralise** : dès qu'une donnée est lue à la fois par le code de production
> et par son test, le test ne garde plus rien. Il faut un second référent, écrit à la main, qui
> dise ce que la donnée est *censée* valoir.

**Ce que la rédaction avait trouvé, et qui s'est confirmé** : l'AC de preuve d'origine
(`getComputedStyle(document.body).fontFamily` contient `IBM Plex Sans`) **était déjà vert** —
12ᵉ instance du motif dominant, dans l'énoncé même de la story censée le produire.
`CascadeSmokeTest` reste en place et reste vert : il garde l'invariant de cascade d'ADR-0013, pas
cette story. Son en-tête a été réécrit pour le dire.

### Campagne de mutation — 8 mutations, rejouées séparément

| # | Mutation | Rouge observé |
|---|---|---|
| MF-A | un `target` renommé d'**une lettre** dans `fonts.json` | Feature AC4 + navigateur AC6 (`unloaded`) + AC7 |
| MF-B | `crossorigin` retiré du composant de preload | Feature AC5 + navigateur AC7 (**second téléchargement observé**) + AC8 |
| MF-C | `font-display: swap` retiré d'**une seule** règle | Feature AC4 |
| MF-D | une entrée `preload` basculée à `false` | ⚠️ **SURVIVANTE** → garde-fou ajouté, puis rouge |
| MF-D2 | la même, **en sens inverse** (`false` → `true`) | Feature AC5 (nouveau garde-fou) |
| MF-E | plugin de copie Vite désactivé | navigateur AC3 + AC6 |
| MF-F | `font-light` introduit dans un template | Feature AC9 (scanner de graisses) |
| MF-G | un `source` pointant un fichier absent | `npm run build` **exit 1**, message nommant l'entrée |

*MF-E a aussi montré qu'un rouge peut être illisible : `scandir()` d'un dossier absent produisait
une **erreur** PHP anonyme au lieu d'un échec nommé. Corrigé — un garde-fou dont le rouge ne se
lit pas se fait désarmer au premier run pressé.*

### Deux réserves honnêtes, à porter en revue

1. **Un run navigateur complet a échoué une fois** sur `TimeAsTextureTest:116`, puis est repassé
   vert seul **et** en suite complète (34/34, deux fois). C'est l'instabilité connue d'ADR-0013,
   pas une régression de cette story — mais elle est écrite plutôt que tue.
2. **Le renvoi `epics.md` → fichier de story n'existait pour AUCUNE story.** Le T13 demandait de
   l'ajouter « comme l'ont fait 1.11/1.12/1.13 » : `grep implementation-artifacts epics.md` ne
   rendait rien. Celui de la 1.9 est le **premier**. Les trois autres restent à faire.

### Ce que la 1.12 a appris, et qui vaut pour la suite

1. **Un `grep` restreint au mauvais répertoire fabrique un AC faux.** L'AC1
   exigeait `Carbon::setLocale(config('app.locale'))` dans
   `AppServiceProvider::boot()`, sur la foi d'un `grep LocaleUpdated` limité à
   `vendor/laravel/framework/`. La campagne de mutation a montré que retirer la
   ligne ne faisait rougir **aucun** test : **Carbon embarque son propre provider
   Laravel** (`vendor/nesbot/carbon/src/Carbon/Laravel/ServiceProvider.php`), qui
   écoute `LocaleUpdated` et fait déjà le travail — mieux, puisqu'il suit aussi
   les changements à chaud. La ligne a été **retirée** ; les tests, eux, sont
   restés et gardent désormais le vrai mécanisme (vus rouges via
   `extra.laravel.dont-discover`). *Le référent existait un répertoire plus loin
   que là où on avait regardé.*
2. **Deux implémentations d'une même règle divergent, et la première dérive est
   invisible.** `Intl.RelativeTimeFormat` sépare le nombre de son unité par une
   **espace insécable** (`il y a 1 h`, U+00A0) là où Carbon emploie une espace
   ordinaire. Rendu identique à l'écran, chaînes différentes. Seule la table de
   cas partagée pouvait le voir.
3. **Un compteur peut compter la mauvaise chose.** Le compteur de ticks
   d'Alpine comptait les *réécritures* : la mutation « plafond des 7 jours
   retiré » lui a survécu, parce qu'un intervalle programmé qui s'arrête à son
   premier tir ne réécrit rien. Il compte désormais les *déclenchements*.

### Pièges qui coûteront cher si oubliés

> ⚠️ **Le « piège n°1 » a été RETIRÉ le 2026-08-08.** Il affirmait que la 1.13
> serait « la première story à confronter `spatie/laravel-csp` à de vraies
> balises ». La prémisse était fausse : la CSP est **éteinte**
> (`CSP_ENABLED=false`) et le middleware rend la main immédiatement. Voir la
> ligne « CSP installée, câblée au groupe `web`, et ÉTEINTE » du tableau de
> dette. Un piège fondé sur une prémisse fausse coûte plus cher que pas de
> piège du tout : il fait chercher au mauvais endroit.

1. **⛔ `make test-browser` NE CONSTRUIT PAS les assets.**
   `docker/php/scripts/run-browser-tests.sh` lance `pest` et rien d'autre, et
   `src/public/build/` est gitignoré. Dès que `resources/js/app.js` ou la CSS
   bouge : **`make npm-build` AVANT `make test-browser`**, sinon Chromium exécute
   l'ancien bundle. La CI, elle, construit (`ci.yml:458`) — le décalage ne se
   voit donc qu'en local. *Piège le plus coûteux de la Story 1.13.*
2. ✅ **Rendez-vous du toast — TENU le 2026-08-08 (Story 1.13).** Le test daté de
   `BladeComponentsTest.php` (« ne livre AUCUN comportement d'auto-fermeture »)
   a été **remplacé**, pas supprimé : le scan « zéro expression JS dans
   `toast.blade.php` » (AC8) + la fermeture différée et le bouton de fermeture
   observés dans un navigateur (AC6).
3. **Ne PAS ajouter `alpinejs` via npm** : Livewire 4 l'embarque. Deux Alpine
   enregistrés en parallèle est un bug classique.
4. **Le `<body>` ne se sélectionne pas par `'body'` dans les tests navigateur.**
   `GuessLocator` ne traite une chaîne comme du CSS que si elle commence par
   `#`, `.`, `[`, `internal:` ou contient un caractère spécial CSS. `body` part
   donc en recherche de TEXTE et échoue sur un « Timeout 5000ms exceeded » qui
   ne nomme rien. Écrire `html > body`. *Trouvé en Story 1.13.*

## Ce qui a changé depuis la dernière fois

- **Epic 1 réordonné.** L'AC3 de la Story 1.9 nommait `<x-layouts.public>`, créé par la
  Story 1.13 — AC sans référent, faux-vert garanti. La 1.13 citait réciproquement les preload
  fonts de la 1.9 : les deux se citaient mutuellement.
- **Story 1.10 scindée.** 1.10a (Filament v5 + Sanctum + Permission) reste en Epic 1, après la
  1.13. 1.10b (`SettingsResource`) part en Epic 5, auprès de son consommateur. `cta_text` /
  `cta_url` remontent en 1.11.
- **Écran offline conçu** (ADR-0012) : vignettes + liens sortants, **jamais d'embed** ; Twitch
  seul comme source d'API ; nouveau module `Media` ; PostgreSQL source de vérité, Redis cache ;
  le mot « Hors ligne » supprimé au profit de « Dernier stream il y a X ».
- **Le job de l'écran offline nommé par le PO** (ADR-0012 §1bis) : ni « convertir vers un
  article », ni « gagner des abonnés » — **prouver que ça vit**. Le contenu affiché date le
  projet. Conséquence : la **fraîcheur** prime sur l'exhaustivité ; un flux périmé dessert
  l'objectif et vaut mieux masqué.
- **YouTube retenu en principe, différé en implémentation** (§2bis) : seul réseau qui *notifie*
  au prochain live, donc seul cas où une sortie crée un canal de retour. **v1 = lien manuel,
  aucune clé API.** Instagram / TikTok / Twitter passent par `social_links[]` — **l'objectif
  « faire grandir les réseaux » ne requiert aucune API.**
- **Sortie ≠ retour** : `social_links[]` = sortie (profils) ; `discord_url` = retour, au rang du
  CTA, jamais dans la liste. Marqueur de source **textuel** sur les vignettes, jamais un logo de
  marque (problème juridique gratuit pour chaque forkeur).
- **NFR-Metric-7 (>25 %) reclassée en hypothèse datée** — plus un critère d'acceptation.
- **Audit time-as-texture avancé** de l'Epic 10 aux écrans de référence, coupe portée à −50 %.
- **`docs/RESUME-1.9.md` supprimé**, remplacé par ce fichier. Hiérarchie documentaire fixée :
  ADR > `epics.md` + `sprint-status.yaml` > `ETAT.md` > `roundtable-decisions.md` (aucune
  autorité). Règle : quand une décision contredit un document, on modifie le document **dans le
  même commit**.

## Passe de relecture des AC 1.9 → 1.13 — FAITE le 2026-07-30

Résultat : **5 `PROUVABLE`, 5 `SANS-RÉFÉRENT`, 4 `AMBIGU`**, plus un défaut transverse. Le détail
et les corrections sont dans `epics.md` (bloc en tête d'Epic 1 + notes `> Requalifié` par story).
Les trois trouvailles qui comptent :

1. **Livewire n'est pas une dépendance déclarée** — voir ci-dessus. Une affirmation
   d'architecture (`CLAUDE.md`, ADR-0008) sans référent dans le manifeste : forme nouvelle du
   motif dominant.
2. **La dépendance circulaire s'est retournée, pas éteinte.** La 1.13 cite désormais les preload
   fonts de la 1.9. Inoffensif cette fois (un layout peut naître sans preload), mais l'AC devait
   le dire — sinon il se valide sur un `<head>` vide.
3. **Contradiction sur `--accent-lava`** : l'AC de la 1.11 dit « réservé LIVE uniquement »,
   `tokens.css` RÈGLE 2 (Story 1.8, `done`) dit « exactement 4 usages ». Le token fait foi.

**Et une conclusion de séquence** : 7 AC sur 14 exigent une **valeur calculée**. Le spike ne
conditionne pas la seule Story 1.9 — il conditionne la moitié du reliquat d'Epic 1.

## 🔴 Le défaut le plus grave trouvé jusqu'ici — CORRIGÉ le 2026-07-31

**Toute la suite de tests tournait sur la base de DÉVELOPPEMENT et la vidait à chaque
exécution.** `laravel_test` contenait **0 table** : elle n'avait jamais servi, depuis le début du
projet — pendant que 55 tests passaient au vert.

C'est aussi l'explication du « `/` répond 404 » diagnostiqué la veille : la base n'était pas
« jamais semée », elle était **vidée par le dernier `make test`**.

**Cause racine, établie par sonde et non supposée.** `phpunit.xml` déclarait bien
`DB_DATABASE=laravel_test`, mais :

1. sans `force="true"`, PHPUnit n'écrase pas une variable déjà définie ;
2. **et même avec `force="true"`, ça ne suffit pas** — PHPUnit peuple `getenv()` et `$_ENV`,
   mais **pas `$_SERVER`**, or le helper `Env` de Laravel consulte `$_SERVER` **en premier**.

Sonde du 2026-07-31 :

```
getenv   → laravel_test      $_SERVER → laravel
$_ENV    → laravel_test      env()    → laravel      APP_ENV → local
```

**Correctif** : `<env force="true">` **et** un bloc `<server force="true">` miroir dans
`src/phpunit.xml`. Les deux sont nécessaires et doivent rester synchronisés.

**Vérifié par mutation** : base de dev semée à 1 streamer → `make test` → toujours 1 streamer,
et `laravel_test` passe de 0 à **22 tables**. Garde-fou permanent :
`src/tests/Feature/TestDatabaseSentinelTest.php` (3 tests, groupe `sentinel`) — il porte sur la
**connexion réellement active**, pas sur le contenu d'un fichier de configuration.

*Reliquat* : le `-e TELESCOPE_ENABLED=false` du Makefile était un contournement du même
mécanisme, traité en symptôme. Il est désormais redondant — inoffensif, à retirer un jour.

## Ce que je vais oublier

- **`toContain()` de Pest est variadique sur les needles.** `->not->toContain('foo', 'msg')` nie
  « contient foo ET msg » → **passe toujours**. Deux garde-fous de la 1.8 sont morts ainsi.
  Utiliser `str_contains()` + `toBeFalse($message)`.
- **`--font-sans` porte le même nom que la variable de thème Tailwind qu'elle alimente** →
  `@theme inline` émet `--font-sans: var(--font-sans)`. Ça ne tient que parce que `tokens.css`
  est importé **sans `layer()`**. Si le spike révèle un autre ordre de cascade, c'est un bug de
  la Story 1.8, pas un ajustement de la 1.9.
- **`max-w-prose` est banni par un test** (built-in Tailwind à 65ch, non surchargeable) →
  utiliser `max-w-measure`, alimenté par le token `--max-prose`.
- **Definition-of-ready** : une story ne passe `backlog` → `in-progress` que si chaque nom cité
  dans ses AC résout vers un chemin existant ou une story `done`.
- **Critère de sortie front** : un test qui ne peut pas rougir en cassant ce qu'il teste n'est
  pas un test. Le rouge doit être **observé**, pas supposé.
- **`MODULE_*_ENABLED=false` n'a jamais été exécuté ni observé**, alors que la Story 1.7 est
  `done` et que c'est la promesse centrale du produit.
  `src/tests/Feature/ModuleActivationTest.php` existe — reste à établir s'il peut rougir.
- **Node 26 : ne pas bumper avant le 2026-10-28** (LTS). Raisonnement en tête de
  `docker/node/Dockerfile`.
- `~/.local/bin` doit être dans le `PATH` (`gh`, `gitleaks`).

## Dette connue, non traitée

| Sujet | Détail |
|---|---|
| **Rector plante** | `Container::databasePath()`. Pas une régression de version : `src/rector.php:47` lie `phpstan.neon`, qui inclut l'extension Larastan, laquelle exige une app Laravel bootée. Rector est **informatif** en CI, donc non bloquant. |
| **Sémantique `/health`** | Trois définitions coexistent : route Laravel tenant-gated, `<Location /health>` Apache mod_status, et docs/installeur qui promettent du JSON Laravel. Le critère go/no-go S7 en dépend. → Epic 3. |
| **ADR-0004 non câblé** | `config/pulse.php` attend `PULSE_DB_CONNECTION`, jamais défini, et aucune connexion `pulse` n'existe dans `config/database.php`. Le conteneur `postgres-pulse` tourne pour rien. → Story 3.2. |
| **PHPStan : 9 erreurs** | Toutes dans `config/*` (scaffolding vendor). Plafonnées par le ratchet, pas résorbées. |
| **`vite@latest webpack@latest`** | Cible mouvante dans une image figée — même fragilité que le `npm@latest` déjà corrigé. `docker/node/Dockerfile:57,73` (+ `pnpm@latest`). **= Lot E du plan supply chain, délibérément non fait le 2026-08-09** : ce n'est pas une montée, c'est supprimer une cible mouvante qui a déjà cassé le build une fois. → Epic 2 (quality gates / installeur). |
| **Node dans l'image PHP de production** | `docker/php/Dockerfile` installe `nodejs` → binaire de **52,5 Mo** embarqué dans l'image de prod. Surface d'attaque et poids non justifiés côté runtime PHP. Reliquat ou besoin réel de build ? Trouvé le 2026-07-31, **toujours ouvert**. |
| ✅ **Dérive Node — quasi résorbée le 2026-08-06** | Était : image PHP v22.22.2 vs conteneur `node` v24.18, **deux majeures d'écart**. Alpine 3.24 fournit désormais v24.18.1, contre v24.18.0 côté `node`. Effet de bord du rafraîchissement du digest PHP, pas d'une correction ciblée. |
| ✅ **Épinglage supply chain — COMPLÉTÉ le 2026-08-06** | `docker.yml` et `security.yml` utilisaient **9 tags mutables** (`@v6`, `@v4`, `@v2`…) alors que seul `ci.yml` était épinglé. Tout est désormais en SHA. Contrôle : `grep -rhoE "uses: [^ ]+" .github/workflows/*.yml \| grep -vE "@[a-f0-9]{40}$"` doit ne rien sortir. |
| 🔴 **`SetCurrentStreamer` : « fail-loud » qui échoue en silence** | `firstOrFail()` lève `ModelNotFoundException` → Laravel rend **404**, indiscernable d'une page inexistante. Le docblock du middleware promet pourtant « an explicit error rather than a silent empty tenant ». Vérifié par mutation : base vide → `/` = 404 ; après `db:seed` → 200. Aucun test ne l'attrape (tous sèment avant). En prod : site entier en 404 silencieux si la base n'est pas semée. Détail + piste de correction dans `deferred-work.md`. |
| ✅ **7 advisories — CORRIGÉES le 2026-08-06** | `squizlabs/php_codesniffer` 3.13.5 → **3.13.6** (CVE-2026-67434, OS command injection, transitive d'ECS) et `league/commonmark` 2.8.3 → **2.9.0** (6 advisories DoS, transitive de `laravel/framework`). Toutes publiées les 5–6 août, détectées par `composer audit` pendant le spike. `composer audit` = 0, `npm audit` = 0. *Leçon : le seul fait de lancer `composer audit` régulièrement a rapporté 7 trouvailles en une session.* |
| **CSP installée, câblée au groupe `web`, et ÉTEINTE** | *Ligne réécrite le 2026-08-08 (Story 1.13) : la précédente disait « CSP non configurée » et annonçait que la 1.13 serait « la première story à confronter `spatie/laravel-csp` à de vraies balises ». **C'était faux**, et la vérification tient en une commande : `curl -skS -o /dev/null -D - https://localhost/ \| grep -i content-security` ne renvoie rien.* État réel, établi par lecture du code : (1) **éteinte** — `src/.env:107` → `CSP_ENABLED=false`, motif en commentaire ; (2) le middleware **est** câblé (`bootstrap/app.php:41`) mais rend la main aussitôt — `AddCspHeaders` : `if (! config('csp.enabled')) return $response;` ; (3) le scoping « groupe `web` » **ne protège rien** — `horizon.php:85`, `pulse.php:122`, `telescope.php:94` attachent tous `'web'`. **Deux verrous techniques avant de l'allumer** : la build Alpine par défaut de Livewire contient `new Function(` (donc exigerait `'unsafe-eval'` ; la build CSP `dist/livewire.csp.js` n'est servie que si `config('livewire.csp_safe')` vaut `true`, et `config/livewire.php` n'est pas publié) ; et **le nonce n'est branché nulle part** — Livewire lit `Vite::cspNonce()`, Spatie expose `app('csp-nonce')`, rien ne relie les deux. Modèle de menace (2 pages) à écrire avant l'Epic 4 — sinon la CSP sera calibrée au moment où elle cassera l'embed Twitch, c'est-à-dire desserrée sous pression. ⚠️ **Le runner navigateur ne pourra pas aider** : `bypassCSP => true` est codé en dur dans le plugin (ADR-0013). Il faudra un test HTTP sur les en-têtes. ✅ **Le trou ne se creuse plus** : l'AC8 de la 1.13 impose Alpine sans expression inline dès maintenant (`toast.blade.php` ne porte que des références nues, toute la logique est dans `resources/js/app.js`, bundlée donc servie depuis l'origine), avec un test qui rougit si une expression réapparaît. Le jour de l'allumage, rien à réécrire. |
| ✅ **CI navigateur : câblée ET son rouge PROUVÉ** | Job `browser` dans `ci.yml`, **bloquant**. Rouge observé sur une exécution réelle avec le token muté ([run 31203127602](https://github.com/Kaelyscius/laravel-skeleton/actions/runs/31203127602)) : `❌ Tests navigateur en échec — 1 test(s), 2 assertion(s), 1 échec(s)`. Vert confirmé après restauration ([run 31203881004](https://github.com/Kaelyscius/laravel-skeleton/actions/runs/31203881004)), 5 jobs verts. **C'est le premier garde-fou du projet livré avec son rouge démontré en CI, pas seulement en local.** |
| 🟡 **Blocage résiduel du runner — 0/10 le 2026-08-09, mais sans bras témoin** | Était : `pest-plugin-browser` ne rend pas la main ~1 run sur 2 (6/10 en août). Cause partielle : `Process::fromShellCommandline()` fait survivre le `node` au SIGTERM. **Après `playwright` 1.59.1 → 1.62.1 : 0 blocage sur 10 runs, image du runner inchangée** (Chromium 150.0.7871.181, non rebâtie — donc la mesure isole bien playwright). **Mais le 6/10 portait sur 8 tests et le 0/10 sur 29** : ce n'est pas un A/B. **La mitigation JUnit RESTE en place.** Prochain pas concret : 10 runs à `playwright@1.59.1` aujourd'hui, même image, même suite. Voir ADR-0013 et la section « Supply chain — plan exécuté ». |
| **`POSTGRES_CONTAINER` est faux** | `docker ps -qf "name=laravel-app_postgres"` filtre par sous-chaîne et matche **aussi** `laravel-app_postgres_pulse` : la variable résout vers 2 identifiants. Dormant — elle n'est utilisée nulle part. Même piège évité pour le conteneur de test (d'où `_test_browser`). |
| **`_bmad-output/` n'est ni versionné ni sauvegardé** | Gitignoré volontairement (`.gitignore:219`) — décision PO du 2026-07-30 : le dépôt est **public**, le planning ne doit pas l'être. Mais `scripts/ops/backup-local.sh` ne fait qu'un `pg_dump` : **le plan-of-record (epics.md, sprint-status.yaml, deferred-work.md, stories) n'existe qu'à un seul endroit, sur le disque.** Un plan sans référent durable, c'est le motif du projet appliqué à lui-même. Options : dépôt git privé séparé, ou élargir le périmètre de `backup-local.sh`. Non tranché. |
| **À vérifier avant story (ADR-0012)** | Quotas YouTube Data API v3 en 2026 · conditions d'utilisation sur le rehosting des miniatures · état réel des API Instagram / TikTok. Marqués « non vérifiés » dans l'ADR plutôt qu'affirmés. |

## Commandes utiles

```bash
make up-local              # démarrer la stack
make test                  # 151 tests, exit 0 attendu (Unit + Feature)
make test-browser          # 29 tests navigateur, conteneur dédié profil `test`
make test-browser-down     # arrêter le runner navigateur
make quality-ratchet       # plafond de dette — exit 0 attendu
make hooks-check           # hooks versionnés actifs ?
./scripts/assert-tracked-files.sh
gh run list --limit 5
```
