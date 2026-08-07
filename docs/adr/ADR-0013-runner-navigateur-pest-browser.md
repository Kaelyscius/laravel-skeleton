# ADR-0013 — Runner navigateur : `pest-plugin-browser` sur Chromium natif Alpine

> **Statut** : ✅ Accepted — 2026-08-06
> **Décideurs** : Alex (PO), exécution du spike préparé par [ADR-0011](ADR-0011-observation-avant-composition.md)
> **Supersède** : le « plan B Playwright TS » de `docs/spike-runner-navigateur.md`, retenu par défaut avant le spike
> **Voir aussi** : [ADR-0007](ADR-0007-postgresql-17-over-mariadb.md), [ADR-0011](ADR-0011-observation-avant-composition.md)

---

## Contexte

ADR-0011 a figé quatre critères d'acceptation **avant** toute installation, précisément pour
qu'ils ne se renégocient pas en séance. Le spike a été exécuté le 2026-08-06. Verdict :

| # | Critère | Résultat |
|---|---|---|
| 1 | Installe sur PHP 8.5.4 sans `--ignore-platform-reqs` | ✅ `pest-plugin-browser` v4.3.1, 21 paquets. Le conflit `symfony/process ^7.4` redouté au pré-vol **n'existe pas**. |
| 2 | Le navigateur ne contamine pas l'image de production | ✅ via un stage Docker dédié, au prix d'un contournement (§ *Chromium sur musl*) |
| 3 | Un test minimal lit `getComputedStyle(document.body).fontFamily` | ✅ vert en 2,26 s |
| 4 | **Le même test rougit quand on casse la source** | ✅ **rouge observé**, exit 1, valeur calculée affichée |

**Le doute qui justifiait ADR-0011 est levé.** Le token `--font-sans` gouverne bien la cascade
réelle : l'invariant « `tokens.css` importé sans `layer()` » de la Story 1.8 tient dans un vrai
navigateur. Le cycle complet a été observé : vert → mutation → rouge → restauration → vert.

## Décision

**Le runner navigateur est `pestphp/pest-plugin-browser` v4.3.1**, exécuté dans un conteneur
dédié `test-browser` (profil Compose `test`) bâti sur un stage `test` du `docker/php/Dockerfile`,
pilotant le **Chromium natif d'Alpine**.

Le plan B (Playwright TypeScript) est **écarté**, malgré le critère d'abandon d'ADR-0011.

### Pourquoi le critère d'abandon n'a pas été appliqué mécaniquement

ADR-0011 prévoyait : *« deux contournements documentés sur le plugin Pest, puis bascule
Playwright sans re-débat. »* Les deux contournements ont bien eu lieu (§ suivant), et le compteur
est donc littéralement atteint.

Il n'a pas été appliqué parce que le spike a produit **un fait qui n'était pas connu quand le
critère a été écrit**, et qui inverse la comparaison :

> `Pest\Browser\Drivers\LaravelHttpServer` est un serveur Amp **in-process**, qui appelle
> directement le `Kernel` Laravel du processus de test. Les tests navigateur héritent donc de
> `RefreshDatabase`, de la base `laravel_test` et des factories.

**Playwright TS ne peut structurellement pas offrir ça** : il pilote un navigateur qui tape un
serveur HTTP externe, donc l'application servie par Apache, donc la base de **développement**.
Ce serait réintroduire par construction la classe de défaut corrigée le 2026-07-31 — « toute la
suite tournait sur la base de dev et la vidait à chaque run ».

Le critère d'abandon existait pour empêcher le sunk cost, pas pour imposer un résultat pire une
fois l'information acquise. La décision a été portée au PO, qui a tranché pour Pest.

## Les deux contournements, documentés comme l'exigeait ADR-0011

### 1. Chromium de Playwright dans un conteneur Alpine — ÉCHEC

Playwright ne distribue que des builds `linux64` liés à la **glibc**. Les images PHP et Node du
projet sont Alpine (**musl**). Le binaire téléchargé est un ELF x86-64 valide, mais son
interpréteur `ld-linux-x86-64.so.2` est absent : le noyau répond `not found` à l'exécution.

Aucune variante musl n'est publiée. Ce n'est pas contournable côté Playwright.

### 2. Chromium natif d'Alpine, lié dans le cache Playwright — SUCCÈS

`apk add chromium` fournit un Chromium compilé contre musl. Playwright sait le piloter.

Le plugin **ne permet pas** de passer `executablePath` : les options de
`BrowserFactory::launch()` sont codées en dur. La seule voie est donc de placer un lien vers le
Chromium d'Alpine à l'emplacement versionné que Playwright calcule.

`docker/php/scripts/link-alpine-chromium.sh` le fait, et **dérive la révision** depuis
`node_modules/playwright-core/browsers.json` plutôt que de l'écrire en dur : coder « 1217 »
créerait un couplage muet qu'une montée de version de Playwright romprait sans le dire.

## Conséquences — trois défauts assumés

### 🔴 Le runner ne rend pas la main, environ une fois sur deux

**Mesuré** : 6 blocages sur 10 exécutions, sur des runs verts comme rouges. Le test rend le bon
verdict en 2–6 s, puis le processus reste vivant indéfiniment.

Cause partielle établie : le plugin démarre son serveur via
`Process::fromShellCommandline()`, donc sous un `sh -c 'node …'`. Son `stop()` envoie SIGTERM au
**shell** ; le `node` enfant y survit et se fait réparenter à PID 1. Huit serveurs orphelins ont
été relevés, un par exécution. Les supprimer **réduit** le taux de blocage mais ne l'annule pas :
la cause résiduelle est en amont (cf. `pestphp/pest#1638`).

**Écartés après mesure** : `ipc: host` + `init: true` + `shm_size: 1gb` (conservés, mais sans
effet sur le blocage) ; un `afterEach` appelant `Playwright::close()` (aggravait, retiré).
Aucune version corrective disponible : v4.3.1 est la dernière 4.x, et la v5 exige Pest 5,
verrouillé par `phploc` (voir `docs/ETAT.md`).

**Mitigation retenue** : le verdict **ne vient pas du code de sortie de pest**, mais du rapport
JUnit, que PHPUnit écrit *avant* le teardown qui se bloque — complet et clos dans 10 cas sur 10,
blocages compris. `docker/php/scripts/browser-verdict.php` le lit et refuse de conclure au vert
faute de preuve : rapport absent, vide, invalide, tronqué, ou **zéro test exécuté** ⇒ échec.

> Ce script est lui-même un garde-fou, donc soumis à la règle d'admission du projet. Les six
> voies de refus **ont été observées rouges**, et le témoin vert observé vert, avant qu'il ne
> soit déclaré livré.

### 🟠 Ce runner ne pourra jamais valider une CSP

`BrowserFactory::launch()` fixe `bypassCSP => true` en dur. Conséquence directe sur la dette
« CSP non configurée » : le modèle de menace à écrire avant l'Epic 4 ne pourra pas s'appuyer sur
un test navigateur pour vérifier la politique. Il faudra un test HTTP sur les en-têtes.

*(À l'inverse, `ignoreHttpsErrors => true` est aussi codé en dur, ce qui règle sans effort la
question du certificat auto-signé du vhost.)*

### 🟠 Le plugin écrit dans `vendor/` à chaque exécution

`Plugin::terminate()` appelle `ServerManager->playwright()`, qui construit et **persiste** un
état de serveur même si aucun test navigateur n'a tourné. Sur un `vendor/` non inscriptible par
l'utilisateur qui lance les tests, cela produit deux warnings PHP à chaque `make test`.
Inoffensif tant que `vendor/` appartient à l'uid 1000 — c'est-à-dire tant que composer est lancé
via `make composer`, jamais en root.

## Ce qui a été mis en place

| Artefact | Rôle |
|---|---|
| `docker/php/Dockerfile`, stage `test` | `FROM development AS test` + `apk add chromium`. **Ni `production` ni `development` ne portent Chromium.** |
| `docker-compose.yml`, service `test-browser` | Profil `test` : jamais démarré par `make up-local` ni `make up-prod`. |
| `docker/php/scripts/link-alpine-chromium.sh` | Lie le Chromium d'Alpine, révision dérivée, jamais codée en dur. |
| `docker/php/scripts/run-browser-tests.sh` | Table rase des orphelins, borne dure, délègue le verdict. |
| `docker/php/scripts/browser-verdict.php` | Établit le verdict depuis JUnit. Refuse de conclure sans preuve. |
| `make test-browser` / `make test-browser-down` | Point d'entrée. |
| `src/tests/Browser/CascadeSmokeTest.php` | L'assertion du spike. |

**`tests/Browser` n'est délibérément PAS déclaré comme testsuite dans `phpunit.xml`.** Le
déclarer suffirait à ce que `php artisan test` le lance, donc à exiger un Chromium là où il n'y
en a pas. Les tests navigateur se lancent par chemin explicite.

> ⚠️ Piège évité, à ne pas réintroduire : le conteneur ne peut pas s'appeler `<projet>_php_test`.
> Le Makefile résout le conteneur PHP par `docker ps -qf "name=$(COMPOSE_PROJECT_NAME)_php"`,
> qui filtre par **sous-chaîne** — `docker exec` recevrait deux identifiants et toutes les cibles
> `make` casseraient. D'où `<projet>_test_browser`. *(La même collision existe déjà, dormante,
> entre `POSTGRES_CONTAINER` et `laravel-app_postgres_pulse` : la variable est fausse mais
> n'est utilisée nulle part.)*

## Ce qui reste ouvert

- Le blocage résiduel n'est pas expliqué. À rouvrir à chaque montée du plugin, et à retirer la
  mitigation dès que l'amont sera corrigé — un contournement qu'on oublie de retirer devient
  une complexité permanente.
- **CI câblée le 2026-08-06, mais son rouge n'est pas encore prouvé.** Job `browser` séparé,
  bloquant. Il n'a jamais tourné : un job qu'on n'a pas vu échouer ne garde rien. Le rouge doit
  être observé sur une exécution réelle avant de considérer ce point clos.
- **Divergence local ↔ CI, assumée** : le runner GitHub est Ubuntu (glibc), donc la CI utilise le
  Chrome for Testing de Playwright, sans aucun contournement ; en local c'est le Chromium
  d'Alpine. Deux moteurs valident la même cascade. Couverture plus large, mais un échec présent
  d'un seul côté est probablement une différence de moteur avant d'être une régression.
- Le stage `test` alourdit l'image de test d'environ 1,5 Go (Chromium + dépendances graphiques).
  Acceptable puisqu'elle n'est ni déployée ni tirée en dev courant.
