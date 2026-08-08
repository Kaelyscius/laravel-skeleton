# État du projet — 2026-08-08 (branche `main`)

> Point d'entrée de reprise. **Un seul fichier, écrasé à chaque session, jamais accumulé.**
> Il n'a aucune autorité : il pointe vers `epics.md` et `sprint-status.yaml`, jamais l'inverse.

---

## Où j'en suis

L'appareil de vérification est réparé — 3 workflows CI verts, **149 tests** + **29 tests
navigateur**, ratchet ECS/PHPStan 0/0/0. **Un navigateur affiche désormais ce projet** : le spike
runner est fait, `make test-browser` existe et son rouge a été observé. Epic 1 : stories 1.1 → 1.8,
1.11 et 1.13 `done`, **1.12 `review`**, 1.9 · 1.10a `backlog`, Epics 2 à 11 non démarrés.

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

## Prochaine action — Story 1.9 (self-hosting IBM Plex).

👉 **`1.13 ✅ → 1.12 ✅ → 1.9 → 1.10a`.** L'inversion `1.13` avant `1.12`,
décidée le 2026-08-08 en amendement à
[ADR-0011 §1](adr/ADR-0011-observation-avant-composition.md), a produit ce
qu'elle promettait : le rafraîchissement client de la 1.12 a été **observé dans
un navigateur**, pas déclaré.

**La 1.12 est en `review`** (revue de code non faite au moment où ces lignes sont
écrites). Elle a livré les 4 composants `<x-time-*>`, `Alpine.data('timeRelative')`,
la table de non-dérive serveur ↔ client, et l'élargissement du scanner
« zéro expression JS » à tous les templates.

**Ce que la 1.12 rend enfin possible pour la 1.9** : `--font-mono` est désormais
*consommé* par du code de production et **mesuré** dans le navigateur (mutation
du token à chaud). Le jour où la 1.9 posera les `@font-face`, un test existe déjà
pour dire si la police résolue a changé.

### Commande d'ouverture de la prochaine session

```bash
make up-local && make test && make quality-ratchet && make npm-build && make test-browser
# attendu : 149 tests exit 0 · ratchet 0/0/0 · 29 tests navigateur verts
```

Puis, **dans cet ordre** :

```
/bmad-code-review                # la 1.12 attend sa revue — en fenêtre NEUVE
/bmad-create-story 1.9
/bmad-dev-story _bmad-output/implementation-artifacts/1-9-*.md
```

⛔ **`make npm-build` AVANT chaque `make test-browser`** dès que `app.js` ou la
CSS bouge — y compris entre deux mutations. Le runner ne construit rien.

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
| **`vite@latest webpack@latest`** | Cible mouvante dans une image figée — même fragilité que le `npm@latest` déjà corrigé. `docker/node/Dockerfile`. |
| **Node dans l'image PHP de production** | `docker/php/Dockerfile` installe `nodejs` → binaire de **52,5 Mo** embarqué dans l'image de prod. Surface d'attaque et poids non justifiés côté runtime PHP. Reliquat ou besoin réel de build ? Trouvé le 2026-07-31, **toujours ouvert**. |
| ✅ **Dérive Node — quasi résorbée le 2026-08-06** | Était : image PHP v22.22.2 vs conteneur `node` v24.18, **deux majeures d'écart**. Alpine 3.24 fournit désormais v24.18.1, contre v24.18.0 côté `node`. Effet de bord du rafraîchissement du digest PHP, pas d'une correction ciblée. |
| ✅ **Épinglage supply chain — COMPLÉTÉ le 2026-08-06** | `docker.yml` et `security.yml` utilisaient **9 tags mutables** (`@v6`, `@v4`, `@v2`…) alors que seul `ci.yml` était épinglé. Tout est désormais en SHA. Contrôle : `grep -rhoE "uses: [^ ]+" .github/workflows/*.yml \| grep -vE "@[a-f0-9]{40}$"` doit ne rien sortir. |
| 🔴 **`SetCurrentStreamer` : « fail-loud » qui échoue en silence** | `firstOrFail()` lève `ModelNotFoundException` → Laravel rend **404**, indiscernable d'une page inexistante. Le docblock du middleware promet pourtant « an explicit error rather than a silent empty tenant ». Vérifié par mutation : base vide → `/` = 404 ; après `db:seed` → 200. Aucun test ne l'attrape (tous sèment avant). En prod : site entier en 404 silencieux si la base n'est pas semée. Détail + piste de correction dans `deferred-work.md`. |
| ✅ **7 advisories — CORRIGÉES le 2026-08-06** | `squizlabs/php_codesniffer` 3.13.5 → **3.13.6** (CVE-2026-67434, OS command injection, transitive d'ECS) et `league/commonmark` 2.8.3 → **2.9.0** (6 advisories DoS, transitive de `laravel/framework`). Toutes publiées les 5–6 août, détectées par `composer audit` pendant le spike. `composer audit` = 0, `npm audit` = 0. *Leçon : le seul fait de lancer `composer audit` régulièrement a rapporté 7 trouvailles en une session.* |
| **CSP installée, câblée au groupe `web`, et ÉTEINTE** | *Ligne réécrite le 2026-08-08 (Story 1.13) : la précédente disait « CSP non configurée » et annonçait que la 1.13 serait « la première story à confronter `spatie/laravel-csp` à de vraies balises ». **C'était faux**, et la vérification tient en une commande : `curl -skS -o /dev/null -D - https://localhost/ \| grep -i content-security` ne renvoie rien.* État réel, établi par lecture du code : (1) **éteinte** — `src/.env:107` → `CSP_ENABLED=false`, motif en commentaire ; (2) le middleware **est** câblé (`bootstrap/app.php:41`) mais rend la main aussitôt — `AddCspHeaders` : `if (! config('csp.enabled')) return $response;` ; (3) le scoping « groupe `web` » **ne protège rien** — `horizon.php:85`, `pulse.php:122`, `telescope.php:94` attachent tous `'web'`. **Deux verrous techniques avant de l'allumer** : la build Alpine par défaut de Livewire contient `new Function(` (donc exigerait `'unsafe-eval'` ; la build CSP `dist/livewire.csp.js` n'est servie que si `config('livewire.csp_safe')` vaut `true`, et `config/livewire.php` n'est pas publié) ; et **le nonce n'est branché nulle part** — Livewire lit `Vite::cspNonce()`, Spatie expose `app('csp-nonce')`, rien ne relie les deux. Modèle de menace (2 pages) à écrire avant l'Epic 4 — sinon la CSP sera calibrée au moment où elle cassera l'embed Twitch, c'est-à-dire desserrée sous pression. ⚠️ **Le runner navigateur ne pourra pas aider** : `bypassCSP => true` est codé en dur dans le plugin (ADR-0013). Il faudra un test HTTP sur les en-têtes. ✅ **Le trou ne se creuse plus** : l'AC8 de la 1.13 impose Alpine sans expression inline dès maintenant (`toast.blade.php` ne porte que des références nues, toute la logique est dans `resources/js/app.js`, bundlée donc servie depuis l'origine), avec un test qui rougit si une expression réapparaît. Le jour de l'allumage, rien à réécrire. |
| ✅ **CI navigateur : câblée ET son rouge PROUVÉ** | Job `browser` dans `ci.yml`, **bloquant**. Rouge observé sur une exécution réelle avec le token muté ([run 31203127602](https://github.com/Kaelyscius/laravel-skeleton/actions/runs/31203127602)) : `❌ Tests navigateur en échec — 1 test(s), 2 assertion(s), 1 échec(s)`. Vert confirmé après restauration ([run 31203881004](https://github.com/Kaelyscius/laravel-skeleton/actions/runs/31203881004)), 5 jobs verts. **C'est le premier garde-fou du projet livré avec son rouge démontré en CI, pas seulement en local.** |
| **Blocage résiduel du runner** | `pest-plugin-browser` ne rend pas la main ~1 run sur 2. Cause partielle : `Process::fromShellCommandline()` fait survivre le `node` au SIGTERM. Mitigé par lecture du rapport JUnit, pas corrigé. Rouvrir à chaque montée du plugin ; **retirer la mitigation dès que l'amont est corrigé**. Voir ADR-0013. |
| **`POSTGRES_CONTAINER` est faux** | `docker ps -qf "name=laravel-app_postgres"` filtre par sous-chaîne et matche **aussi** `laravel-app_postgres_pulse` : la variable résout vers 2 identifiants. Dormant — elle n'est utilisée nulle part. Même piège évité pour le conteneur de test (d'où `_test_browser`). |
| **`_bmad-output/` n'est ni versionné ni sauvegardé** | Gitignoré volontairement (`.gitignore:219`) — décision PO du 2026-07-30 : le dépôt est **public**, le planning ne doit pas l'être. Mais `scripts/ops/backup-local.sh` ne fait qu'un `pg_dump` : **le plan-of-record (epics.md, sprint-status.yaml, deferred-work.md, stories) n'existe qu'à un seul endroit, sur le disque.** Un plan sans référent durable, c'est le motif du projet appliqué à lui-même. Options : dépôt git privé séparé, ou élargir le périmètre de `backup-local.sh`. Non tranché. |
| **À vérifier avant story (ADR-0012)** | Quotas YouTube Data API v3 en 2026 · conditions d'utilisation sur le rehosting des miniatures · état réel des API Instagram / TikTok. Marqués « non vérifiés » dans l'ADR plutôt qu'affirmés. |

## Commandes utiles

```bash
make up-local              # démarrer la stack
make test                  # 98 tests, exit 0 attendu (Unit + Feature)
make test-browser          # 8 tests navigateur, conteneur dédié profil `test``test`
make test-browser-down     # arrêter le runner navigateur
make quality-ratchet       # plafond de dette — exit 0 attendu
make hooks-check           # hooks versionnés actifs ?
./scripts/assert-tracked-files.sh
gh run list --limit 5
```
