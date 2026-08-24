# État du projet — 2026-08-24 (branche `main`)

> 🔴 **CLÔTURE DE LA STORY 2.4 — LE NIGHTLY AVAIT RAISON : LE SQUELETTE N'ÉTAIT PAS
> INSTALLABLE DEPUIS UN CLONE PROPRE.** Deux runs rouges (`32654512271`, `32688766596`),
> étiquetés INSTALLEUR. Cause **mesurée** dans le conteneur `laravel-app_php` :
> `docker/php/scripts/docker-entrypoint.sh` décidait « Laravel est installé » sur
> `[ -f artisan ]`, or **`src/artisan` est versionné et `src/vendor` ne l'est pas**. La branche
> « installé » était donc prise sans autoloader, `php artisan config:clear` sortait en **255**,
> `set -e` tuait l'entrypoint, `restart: unless-stopped` bouclait — et `make install-laravel`,
> qui s'exécute DANS ce conteneur, n'avait jamais d'hôte où tourner. Poule et œuf : le correctif
> ne pouvait être **que** dans l'entrypoint.
>
> ✅ **SIX blocages levés** — trois n'étaient encore que des PRÉDICTIONS de lecture, et les deux
> derniers ont été trouvés par AUDIT, après coup :
> 1. **entrypoint php** — sonde à **CINQ états** (`absent` / `sans-vendor` / `non-bootable` /
>    `non-bootable-timeout` / `bootable`), dont un compte que `PhpEntrypointStateTest` DÉRIVE du
>    code : la sonde, le `case` en aval et l'en-tête doivent énumérer les mêmes, sinon il rougit. ⛔ La sonde n'a **pas** été inversée vers `[ -f vendor/autoload.php ]` :
>    un `vendor/` partiel l'aurait satisfaite et la branche production aurait figé
>    `config:cache`/`route:cache` depuis un état cassé (rationale D7). La bootabilité est
>    **mesurée** (`php artisan --version`), pas devinée. `proxies:check` reste fatal hors
>    `local`/`testing` — un clone neuf en `staging`/`preprod`/APP_ENV vide **refuse de démarrer**
>    et nomme la variable.
> 2. **module 10** — `ensure_composer_dependencies` : sur un clone neuf `is_laravel_installed` est
>    **vrai** (les quatre `LARAVEL_CORE_FILES` sont versionnés), donc aucune des trois portes
>    d'installation de dépendances n'était atteinte et `key:generate` — la première commande
>    artisan — exigeait déjà `vendor/`. L'installation des dépendances est désormais
>    **inconditionnelle, après le patch du `composer.json` et avant toute commande artisan**, avec
>    une post-condition mesurée (autoloader présent **et** application bootable).
> 3. **Makefile** — `setup-ssl` passe **avant** tout `up*` dans les chaînes d'installation :
>    l'entrypoint apache sort en `1` sans certificats, et `setup-ssl` en était le **dernier**
>    prérequis. Le script est purement hôte, rien ne justifiait qu'il vienne après les conteneurs.
> 4. **l'instrument lui-même** — le job `alert` du nightly n'a **jamais** ouvert d'issue : il n'a
>    aucun `actions/checkout`, donc `gh` sortait sur « fatal: not a git repository » (reproduit sur
>    l'hôte WSL2 dans un répertoire non-git ; `GH_REPO=<owner>/<repo>` la fait sortir en 0). Ajout
>    de `GH_REPO`, **filtrage d'issue côté client** au lieu de `--search` (index GitHub asynchrone →
>    une issue neuve chaque nuit), et le job devient **déclenchable hors `schedule`** — sans quoi
>    son correctif n'était pas validable. Et le diagnostic du test Bats, jeté par
>    `tail … 2> /dev/null >&2` (redirections appliquées de gauche à droite), est **réparé et
>    extrait en fonction éprouvée**, avec un **repli** `docker logs` — repli, jamais substitution —
>    qui **NOMME sa source** pour qu'une panne réseau ne soit pas réétiquetée INSTALLEUR.
>
> 5. **Et le retrait de la restriction au cron est désormais VERROUILLÉ** (constat d'audit).
>    Rien ne l'empêchait d'être remis : aucun test ne rougissait, et on serait retombé dans un
>    correctif d'alerte invalidable autrement qu'en perdant une nuit — le garde-fou silencieux
>    appliqué au correctif qui venait d'être fait. Le garde neuf pose la question **d'intention**
>    (« si je lance ce workflow à la main et que l'installation échoue, l'alerte part-elle ? ») en
>    **évaluant** la condition `if:` dans un contexte simulé, plutôt qu'en recopiant son texte ; sa
>    moitié anti-vacuité vérifie qu'une installation RÉUSSIE ne déclenche rien.
>
> 🔴 **6. UN SIXIÈME BLOCAGE, TROUVÉ PAR AUDIT APRÈS COUP — ET IL PASSAIT POUR UN SUCCÈS.**
> La ligne de matrice « après `install-laravel`, les caches/clears sont joués » n'était **pas**
> satisfaite : php démarre en `sans-vendor`, saute la branche `bootable`, `install-laravel` peuple
> `vendor/`… et **rien ne redémarrait le conteneur**. Or `php artisan storage:link` n'existe qu'à
> **un seul endroit du dépôt** — cette branche `bootable`. Aucun module d'installation ne le joue.
> Une install de clone neuf ne créait donc **jamais** `public/storage`, et comme `/health` ne le
> regarde pas, **le nightly pouvait conclure VERT sur une application incomplète** : la classe de
> défaut exacte que cet epic existe pour interdire.
> ✅ Correctif : `make post-install-restart-php`, inséré après l'installateur Laravel et **avant**
> `npm-install` dans les cinq chaînes. On redémarre plutôt que de dupliquer `storage:link` dans un
> module — la promesse déjà imprimée par l'entrypoint devient vraie, et la logique reste à un seul
> endroit. La cible attend une **post-condition** (le lien), pas un délai ; elle rejoue son
> sondage ; elle **échoue** si le lien n'apparaît pas.
>
> 🔴 **PASSE DE REVUE DU 2026-08-24 — TROIS GARDE-FOUS NE GARDAIENT RIEN, ET C'ÉTAIT MESURÉ.**
> Le relecteur n'a pas argumenté : il a MUTÉ. (1) L'appel à `ensure_composer_dependencies` remplacé
> par un no-op → **449/449 verts**, alors que la mutation restaure l'échec de clone neuf ; le seul
> garde était un ratchet qui compte du TEXTE. (2) `local -a _probe=(a b)` dans `detect_laravel_state`
> → **11/11 verts** sous `bash`, alors que le script meurt en « syntax error » sous le `sh` de
> l'image (BusyBox) : **le garde mesurait le mauvais interpréteur**, motif de la 2.3 reproduit dans
> le garde censé le clore. (3) `env.ISSUE_TITLE` → `"$ISSUE_TITLE"` dans le filtre jq → **9/9 verts**,
> et une issue neuve chaque nuit.
> ✅ Les trois sont corrigés, et **les trois mutations ont été rejouées : elles rougissent**.
>
> 🎁 **Et le bon interpréteur a trouvé un défaut du jour même** : `timeout` rend **124** sous GNU
> coreutils mais **143** sous BusyBox. L'état de dépassement de la sonde de boot, écrit quelques
> heures plus tôt, était donc **inatteignable en production**. C'est la troisième fois de l'epic que
> GNU-vs-BusyBox décide d'un verdict — et la première où c'est un test qui le dit, pas une revue.
>
> 🔴 **2ᵉ PASSE DE REVUE — LA POST-CONDITION DU REDÉMARRAGE N'ÉTAIT VRAIE QUE QUAND TOUT ALLAIT
> DÉJÀ BIEN.** La cible relevait le témoin d'avant pour le comparer ; quand ce relevé échouait,
> l'attendu devenait vide et n'importe quel vestige passait pour neuf — or il échoue **précisément
> quand le conteneur boucle**, la panne qu'elle existe pour attraper. ✅ On **efface** le témoin
> avant de redémarrer, et l'échec de l'effacement est fatal : on refuse de mesurer plutôt que de
> mesurer faux. Le témoin est aussi passé de la fin de BRANCHE à la **dernière ligne avant `exec`**
> — `mkdir -p` du répertoire supervisor, fatal, vivait entre les deux.
>
> 🔴 **ET LE BRAS `143` N'ÉTAIT ÉPROUVÉ NULLE PART OÙ LA CI MESURE.** La sonde déclenchait un vrai
> dépassement, donc lisait le `timeout` de la machine : 124 sur le runner, 143 sous BusyBox. Le code
> de la PRODUCTION n'était couvert que par la boucle locale. **L'interpréteur était épinglé, le
> binaire ne l'était pas** — il l'est maintenant, par un stub, et les deux bras sont exercés partout.
>
> 🎁 **Une mutation est restée VERTE, et c'était sa trouvaille** : « le témoin repart en fin de
> branche ». Rien n'assertait que le témoin soit **écrit**. Deux sondes ajoutées, mutation rejouée
> dans les deux sens, rouge.
>
> ✅ **PREMIER NIGHTLY RÉELLEMENT ABOUTI (run `32742873104`, runner GitHub nu).** L'installation
> Laravel PASSE sur un clone neuf pour la première fois de l'histoire du dépôt : 11 modules,
> Laravel 13.24.0, PHP 8.5.9, **4m02**. Le redémarrage a rendu « ✓ témoin renouvelé » en conditions
> réelles, et le diagnostic des 80 lignes s'affiche enfin.
>
> 🔴 **MAIS LE RUN EST ROUGE, ET LA CAUSE EST UN CORRECTIF DE CETTE STORY.** Échec à
> `install-lockfile` : `mktemp` refusé dans `src/.install-state/`. Ce script tourne **sur l'hôte** ;
> l'hôte d'un runner est **1001** ; et le bloc de permissions de l'entrypoint confisquait TOUT
> l'arbre vers `www-data` = **1000**. L'hôte perdait la propriété de son propre arbre.
> **Sixième fois dans cet epic que l'environnement de mesure décide du verdict** — après BusyBox/GNU,
> `bash`/`ash`, `timeout` 124/143, `jq` absent, un relecteur en root. Cette fois : **1000 contre
> 1001**, invisible sur WSL2 où l'hôte EST 1000.
> ✅ Le `chown` récursif de l'arbre est supprimé : seuls `storage/` et `bootstrap/cache/` sont
> ajustés. Le code, la configuration et `.install-state/` restent à l'hôte.
>
> 🎁 **Et le garde écrit contre ce travers l'a d'abord reproduit** : il ne stubait que `chown`, alors
> que le défaut passe par `find -not -user www-data -exec chown` — prédicat évalué sur les inodes
> réels, donc inerte sous un test tournant en uid 1000. `find` est stubé lui aussi, et la mutation
> rougit.
>
> 🔴 **MON CORRECTIF PRÉCÉDENT ÉTAIT UNE NON-CORRECTION — À ÉCRIRE NOIR SUR BLANC.** Restreindre le
> `chown` à `storage/` + `bootstrap/cache/` n'a pas corrigé le défaut, il l'a **déplacé** : run
> `32745286801`, l'installation meurt **plus tôt** qu'avant, dès l'étape 1/5. Le `chown` large
> n'était pas un confort, il était **porteur**. `./src` est bind-monté et écrit par DEUX écrivains —
> le conteneur (`docker exec -u 1000:1000` en dur) et l'hôte (`install-lockfile.sh`, sans `docker
> exec`). Le `chown` donnait l'arbre au conteneur ; le retirer l'a rendu à l'hôte. **Un seul des deux
> peut le posséder**, et les deux pansements se contredisent.
>
> ✅ **LA CORRECTION EST DANS LES UID** : `HOST_UID`/`HOST_GID` exportés par le Makefile, `UID:
> ${HOST_UID:-1000}` sur les **quatre** services qui portent l'arg, et les **44** `-u 1000:1000`
> remplacés par `-u $(DOCKER_USER)`. Le conflit disparaît par construction. Défaut 1000 partout :
> sur un hôte en uid 1000, comportement **strictement inchangé**, images existantes valides.
>
> 🎁 **ET LA BOUCLE DE RETOUR EST RÉPARÉE — c'était le vrai sujet.** Trois allers-retours en CI
> aujourd'hui parce que « hôte uid ≠ uid conteneur » n'existe pas sur cette machine. La condition est
> désormais reproductible **localement et sans privilèges** (`sudo -n` indisponible, mesuré) : *root
> dans un conteneur peut `chown` un bind-mount*. Verdict en une seconde — arbre à 1001 + conteneur
> figé à 1000 → `mktemp: Permission denied`, l'échec EXACT du run ; conteneur dérivé de l'hôte → OK ;
> et l'arbre reste à 1001, donc les deux écrivains coexistent.
>
> ⚠️ **Reconstruction d'image** : nécessaire seulement si l'uid hôte ≠ 1000 (l'uid est figé au
> build) — les chaînes commencent par `build`, le nightly la fait seul. Aucune collision d'uid dans
> Alpine (`www-data` = 82, rien en 1000–1019, mesuré), et l'image php a été **réellement construite**
> avec `UID=1001` : elle démarre, `www-data` y vaut 1001.
>
> ⚠️ **DEUX AC RESTENT OUVERTES, ET AUCUNE N'A ÉTÉ FERMÉE SUR UNE LECTURE DE CODE.**
> Le verdict de cette story est **un run réel**, et aucun n'a pu être lancé : le travail n'est pas
> poussé, `workflow_dispatch` n'exécute que la version présente sur la branche par défaut. Restent
> donc à observer, **dans cet ordre**, après merge :
> `gh workflow run nightly.yml` → **vert observé**, fenêtre du lockfile < 15 min, numéro consigné ;
> puis `gh workflow run nightly.yml -f mutate_module=20-database` → **rouge observé**, module nommé,
> numéro consigné ; puis `gh issue list --label nightly` → l'issue existe **sur le dépôt**
> (le label `nightly` n'existe toujours pas : vérifié le 2026-08-24 via l'API). La bascule de
> `nightly-freshness` en bloquant (geste 2, plus bas) **n'a pas été faite** : la faire avant un
> premier vert installerait dans le verdict global le rouge permanent que cette section décrit.
>
> 🧪 **Campagne de mutation — 73 rouges observés, 11 témoins neutres verts.**
> **Environnements nommés** (règle désormais ÉCRITE dans `docs/process/03-boucle-qualite.md`
> §Étape 5, elle ne vivait que dans ce journal et dans `ADR-0013`) :
> les 25 mutations Pest ont été appliquées sur l'arbre hôte et **exécutées dans le conteneur
> `laravel-app_php`** ; les 8 mutations Bats ont été **exécutées sur l'hôte nu (WSL2, bash 5.2,
> GNU coreutils, GNU Make 4.4.1)**, où `make test-bats` tourne. Les cinq témoins neutres — un
> libellé de log du module 10, un commentaire de `e2e.bash`, la couleur du label `nightly`, le
> libellé du redémarrage, et une **reformulation équivalente** de la condition `if:` de l'alerte —
> sont restés **verts**. Ce dernier est le plus parlant : il prouve que le garde de l'alerte porte
> sur l'INTENTION et non sur le texte, puisqu'il survit à une réécriture de la condition.
>
> 🔴 **ET LA CAMPAGNE A EU UNE TROUVAILLE — SUR ELLE-MÊME.** La mutation « la post-condition n'est
> plus vérifiée » a d'abord été écrite en insérant `@exit 0` avant la boucle d'attente, et elle est
> restée **VERTE**. Ce n'était pas un garde muet : **chaque ligne de recette `make` est un shell
> distinct**, donc `@exit 0` terminait sa propre ligne et make enchaînait sur la suivante — la
> mutation ne mutait rien. Réécrite en retirant le **bloc entier** de vérification, elle rougit.
> Corollaire à retenir : dans un `Makefile`, une mutation doit porter sur une LIGNE DE RECETTE
> entière, jamais sur une instruction glissée avant elle.
>
> 🔴 **ET UNE SECONDE TROUVAILLE, SUR UN GARDE CETTE FOIS.** La mutation « l'évaluateur de
> conditions rend `true` par défaut au lieu de refuser un identifiant inconnu » est restée
> **VERTE** : le test « il refuse ce qu'il ne sait pas lire » n'exerçait que des expressions
> MAL FORMÉES, qui mouraient toutes dans le découpage en jetons — jamais dans la résolution
> d'identifiant qu'il prétendait garder. Un cas bien formé nommant un contexte absent
> (`github.actor == '…'`) a été ajouté ; la mutation rougit. Le motif est constant dans ce
> projet : **un garde ne vaut que par le chemin que son test emprunte réellement.**
>
> 📊 **487 tests Pest · 49 tests Bats · ratchet 0/0/0.**

> 🆕 **Story 2.4 implémentée, revues 1 et 2 traitées (≈60 + 31 constats).**
> **423 tests Pest · 40 tests Bats · ratchet 0/0/0 · 87 mutations rejouées (60 + 27), toutes rouges
> observées sauf les deux inatteignables-par-construction, dites comme telles.**
>
> 🔴 **LA REVUE 2 A TROUVÉ QUE LE CORRECTIF DU « TEST QUI ÉVITAIT LE VRAI MODE DE PANNE »
> ÉVITAIT LE VRAI MODE DE PANNE.** Le fixture `…​.invalid` est mesuré à **0,0149 s** — NXDOMAIN
> immédiat, RFC 2606 — et non aux 3,13 s d'un conteneur arrêté ; l'assertion temporelle passait
> avec ou sans portillon (38 ms contre 506 ms), et seul le LIBELLÉ du résumé faisait rougir. Le
> test asserte désormais le **nombre de tentatives d'ouverture de PDO** (0 avec portillon), comme
> `DatabaseHealthCheckTest` : déterministe, indépendant de l'horloge et du libellé.
>
> 🔴 **ET LA CAMPAGNE DE MUTATION ELLE-MÊME AVAIT DEUX FAUX VERTS**, tous deux corrigés :
> un test à `->hourly()` était vrai **59 minutes sur 60** (la mutation est passée pendant la
> minute 0), et deux mutations visaient des fichiers dont les gardes vivent dans une suite que le
> script n'exécutait pas. Un test qu'on croit vert reste le défaut de tête de ce projet.
>
> 🎁 **La cause des « ~7,5 s inexpliquées » est trouvée : Telescope.** Bascule des drapeaux, redis
> arrêté : `TELESCOPE=on` **13,77 s** · `TELESCOPE=off` **6,39 s**. Il rejoue vers les dépendances
> que la route vient de déclarer injoignables. `health` est dans `telescope.ignore_paths` ; effet
> mesuré en HTTP : **13,74 s → 9,59 s**. ⚠️ Il reste **~3,2 s non localisées**, et c'est dit.
>
> ⚖️ **Décision d'Alex (revue 2) : `nightly-freshness` est HORS des `needs` de `CI Summary`** tant
> que le premier nightly n'existe pas — un rouge attendu en permanence masquerait une régression
> réelle. Il lit désormais aussi la **conclusion** du dernier run : « il tourne » n'est pas « il
> passe ». La bascule en bloquant est une étape écrite, section « La bascule à faire JUSTE APRÈS le
> premier nightly ».

> 🆕 **Story 2.3 implémentée, revues 1 et 2 traitées (19 + 19 constats).**
> **ratchet 0/0/0.** Mutations rejouées et rouges observés — ⚠️ **avec UNE exception consignée** :
> la mutation du garde « `.env` jamais écrasé sans sauvegarde » ne rougit **pas dans le conteneur**
> (le `cp` de BusyBox refuse l'écrasement de lui-même, donc `.env` survit pour une raison
> étrangère au garde) ; elle rougit sur GNU coreutils, donc en CI. Report ouvert dans
> `deferred-work.md`. Le compte « toutes rouges » n'est donc vrai que hors cette sonde-là. `--dry-run` descend au grain de la
> COMMANDE, ne pose plus aucun effet de bord, et `make` expose enfin les deux drapeaux.
> ⚠️ Pas encore poussée : la CI ne se déclenche que sur `main`/`develop`, le verdict n'existe
> qu'au merge.
>
> ✅ **Story 2.2 `done` — Epic 2 à 2/13.** `main` = **`eb397f4`**, poussé, **5 jobs CI verts**
> (run 32593920247). **333 tests · ratchet 0/0/0 · `composer audit` 0 · `npm audit` 0.**
> `ensure_idempotent`, livrée testée par la 2.1 **sans aucun appelant**, a enfin son lecteur de
> production : l'orchestrateur source `runtime.sh` et enveloppe chaque module au grain module.
> La reprise ne se tape plus (`--resume-from`), elle se **déduit de l'état sur disque**.
>
> 🔴 **Le défaut de tête n'était pas dans le code — il était dans une FIXTURE.** La racine d'état
> `src/.install-state/` vivait dans le répertoire que `clean_target_directory` efface : sur le chemin
> **nominal** d'un fork-streamer, après les modules 00 et 05, les sentinelles et l'horodatage étaient
> détruits, **code retour 0**, et `make install-dev-full` échouait ensuite à sa dernière étape sur une
> install réussie. **25 mutations ne l'avaient pas vu** : aucune fixture ne posait `.install-state/`
> dans la cible, et la ligne de matrice « cible vraiment vide » décrivait un état qui **n'existe
> jamais en production** après le module 00.
>
> 🔴🔴 **ET IL A ÉTÉ CORRIGÉ FAUX DEUX FOIS.** `-prune` est **inopérant sous `-depth`**, que `-delete`
> implique. Son remplaçant `-not -path` prend un **MOTIF GLOB** : mesuré, un `[` dans le chemin du
> dépôt (`pro[1]jet/src`) faisait repartir la protection à zéro — espaces et `?` passaient, les
> crochets non. C'est le **même mécanisme, en sens inverse**, que le `grep` appliquant une regex à
> `projet[1]_node` corrigé dans le lockfile à la passe précédente. **Un moteur de motif là où un
> littéral était voulu, deux fois dans la même story.** La parade finale n'en emploie **aucun** :
> comparaison littérale de basenames, `rm -rf --` un par un, vérifiée sur six chemins piégés.
>
> ⚖️ **Séparation imposée par la mesure, pas par un goût :** sentinelles côté **conteneur**, lockfile
> côté **hôte**. La racine du dépôt est montée `ro` (`/proc/mounts`, et ⚠️ `test -w` y rend **VRAI** —
> il ment) ; le conteneur php n'a **ni CLI docker ni socket**, donc il ne peut pas lire la version du
> conteneur node — la seule qui ait produit `node_modules/`. Et `npm-install` tourne **après**
> `install-laravel` : un lockfile écrit en fin d'`install.sh` décrirait un `node_modules/` inexistant.
>
> 🔬 **Trois garde-fous NEUFS étaient silencieux**, chacun vu rouge après correction : retirer
> `export INSTALL_FORCE`, retirer le write-once de `started_at`, ou dévier le défaut de racine d'état
> du lockfile laissaient chacun **19/19 vert**. Et le test « racine d'état inécrivable » avait **3 de
> ses 4 assertions satisfaites par un AUTRE chemin de code** — un `log_warn` de métrologie déclaré
> non fatal, pas le refus qu'il nomme.
>
> ⚠️ **Aucune install complète n'a jamais été jouée.** Le module 10 est éprouvé au grain fonction,
> l'orchestrateur sourcé avec `execute_module` remplacé par un compteur. La preuve de bout en bout
> appartient à la **story 2.4** (Bats). Les autres modules non idempotents (seeders rejoués en
> `20-database.sh:319`, configs qualité écrasées en `50-quality-tools.sh:359`) restent **hors
> périmètre**, par arbitrage écrit.
>
> 🩺 **Piège d'environnement relevé ce jour :** `git fetch`/`push` échouaient en `Permission denied
> (publickey)` — aucun agent SSH chargé — et la référence locale `origin/main` était **périmée de
> trois commits**. `gh` (jeton, scopes `repo`+`workflow`) fonctionnait. C'est le piège qui avait
> laissé `origin/main` bloqué à la Story 1.1 pendant sept stories `done`. Remède :
> `eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519`, ou `gh auth setup-git`.
> ✅ **Réglé le 2026-08-22** : `gh auth setup-git` + remote basculé en HTTPS. `git fetch`/`push`
> fonctionnent sans agent ni passphrase.

---

## ✅ Story 2.4 — `/health` sait rougir, et l'installation se joue enfin pour de vrai

> **408 tests Pest (371 + 37) · 31 tests Bats · ratchet 0/0/0 · 60 mutations rejouées sur la story
> — 58 rouges OBSERVÉES, 2 vertes.** ⚠️ Des deux vertes, **une est depuis passée au rouge** grâce à
> `DatabaseHealthCheckTest` ajouté en revue 1 (« `RESET` inconditionnel », verte au premier jet
> faute de test) ; **l'autre est inatteignable par construction** et c'est écrit dans le code.
> `make test-bats` : 31 tests, une seconde. `make test-bats-e2e` : l'installation réelle.

**Ce que la story a changé, dans l'ordre où il fallait le faire.**

1. **`/health` n'était pas une sonde, c'était une constante.** Mesuré avant d'écrire une ligne :
   `curl https://localhost/health` → `200`, **93 octets**, aucune sonde exécutée. Il répondait donc
   `ok` la base à terre. Il exécute désormais les sondes enregistrées : `200` si tout est sain,
   **`503` sinon**, JSON à trois clés `database` / `cache` / `queue`.
2. **Deux sondes neuves** sur le modèle de `DatabaseHealthCheck` : `CacheHealthCheck` (écriture /
   relecture / purge d'une clé éphémère) et `QueueHealthCheck` (**joignabilité du backend**).
3. **Le `QueueCheck` de Spatie est refusé, et le refus est écrit sur place** : il atteste qu'un job
   a tourné récemment, sémantique **fausse au sortir d'une install neuve**. Le nightly aurait rougi
   pour une raison étrangère à l'installeur.
4. **`tests/bats/`** : le E2E d'installation, et surtout `tests/bats/unit/`, qui éprouve en une
   seconde tout ce qui DÉCIDE d'un verdict.
5. **`.github/workflows/nightly.yml`**, planifié 03:17 UTC, déclenchable à la main, bloquant.

---

### 🔴 REVUE 1 — deux défauts que l'implémentation avait ÉCRITS sans les voir

#### (A) La ligne « sonde lente » du bloc GELÉ n'était pas tenue

La matrice exige « réponse **bornée** dans le temps ». Le budget de 5 000 ms n'était évalué
qu'**ENTRE** les sondes : la première tournait sans borne et consommait tout le délai à elle seule.

| Mesure — conteneur postgres RÉELLEMENT arrêté | Avant portillon | Après portillon |
|---|---|---|
| `curl https://localhost/health` | **58,6 s** (et **504 d'Apache à 60 s** sur la 1ʳᵉ passe) | **3,20 – 4,24 s** (10 éch. / 11) |
| sonde `database` (`duration_ms`) | 31,2 s | 3,10 – 3,96 s |
| corps rendu | souvent aucun (504) | `503` complet, à chaque fois |

**Aggravant, et c'est le vrai constat de la revue** : *tous* les tests de dégradation empruntaient
le chemin RAPIDE (`127.0.0.1:1`, `ECONNREFUSED`, ~0 s), et le test Bats « SAIT rougir » réécrivait
`DB_HOST` au lieu d'arrêter le conteneur — **avec, en commentaire, l'aveu que l'arrêt avait été
écarté à cause de la marge**. Le seul test capable d'observer le vrai mode de panne était celui
qu'on avait écrit pour l'éviter.

**Parade : un PORTILLON PAR SONDE** (`App\HealthChecks\Support\BackendEndpoint`) — une connexion
TCP bornée avant l'aller-retour applicatif. Cause mesurée du désastre : `gethostbyname('postgres')`
coûte **3,13 s** quand le conteneur est arrêté, et le framework REJOUE la connexion (~10 tentatives
par sonde). Le portillon supprime le facteur ×10.

⚠️ **Ce qui reste non borné, et c'est écrit partout où le chiffre apparaît** : le coût UNITAIRE
d'une résolution en échec — mesuré à **~3,1 s** par tentative sur cette pile. Aucune API PHP ne
l'expose — `PDO::ATTR_TIMEOUT` a été **essayé, mesuré (3,13 s que le timeout vaille 2, 5 ou rien),
et retiré avec son commentaire**. Report ouvert dans `deferred-work.md`.

Les tests qui ferment l'AC :
- Pest, chemin lent (`.invalid`, RFC 2606) : `503` + résumé du portillon + **borne temporelle** ;
- Bats E2E : **conteneur postgres réellement arrêté**, corps `503` lu par analyse JSON, temps total
  asserté sous **45 s** (passerelle mesurée : 60 s), puis retour à `200`.

#### (B) La sonde cache attestait la MAUVAISE dépendance

```
Redis arrêté, AVANT :  503  ·  database ok · cache ok    · queue error
Redis arrêté, APRÈS :  503  ·  database ok · cache ERROR · queue ERROR
```

Mesuré le 2026-08-23, conteneur redis **réellement arrêté** : `503` en **13,8 s**, dont 3,11 s pour
le portillon cache et 3,13 s pour le portillon queue. ⚠️ **Les ~7,5 s restantes sont HORS des
sondes et ne sont pas expliquées** — elles ne sont pas dans les `duration_ms`. Elles sont écrites
telles quelles plutôt que rationalisées, et rattachées au report « coût unitaire de résolution ».

`config('cache.default')` valait **`database`** : les `.env` déclaraient `CACHE_DRIVER` alors que
Laravel 11+ lit **`CACHE_STORE`** (`config/cache.php:17`). La « sonde cache » était une seconde
sonde base — **et le nightly assertait `"cache":{"status":"ok"` dessus**.

Corrigé dans les six endroits qui écrivaient ou lisaient la clé morte : `.env.example`,
`scripts/setup/generate-configs.sh`, `scripts/lib/laravel.sh`, `ci.yml` (×2), `docker.yml`.
`src/tests/Unit/CacheStoreKeyTest.php` gèle la CONCORDANCE — pas une valeur : ce que les modèles
déclarent doit être ce que la configuration lit.

🎁 **Et cela a annulé une dette qu'on s'apprêtait à consigner.** `/up` mettait **27 s** à rendre son
`200` base coupée, ce qu'on avait attribué à un « surcoût pré-existant hors mandat ». Ce n'était pas
`/up` : cache ET sessions retombaient sur `database`, donc **toute** requête traversait la base
morte. Après correction, mesuré trois fois : **0,073 / 0,073 / 0,075 s**. La dette n'existait pas.

---

### Les autres constats de revue 1, par famille

**Gardes qui ne gardaient rien**
- 🔴 `grep -qF '"status":"ok"'` dans `install.bats` était satisfait par la **sous-chaîne de
  `checks.database.status`** : l'assertion du verdict GLOBAL ne pouvait pas rougir seule. Remplacée
  par `e2e_json_field`, qui **analyse** le document (python3, présent partout ; `jq` ne l'est pas
  ici — mesuré). Un test compare explicitement les deux comportements.
- 🔴 L'en-tête de `lib/e2e.bash` affirmait que tout ce qui décide d'un verdict y vit **et** y est
  couvert. **Faux** : `e2e_resolve_compose` et `e2e_assert_ports_free` — qui décident si le nightly
  démarre et à qui l'échec est imputé — n'avaient aucun test. Ils en ont, par des **coutures**
  (`e2e_has_compose_v1`, `e2e_port_is_busy`) que le test remplace.
- 🔴 `e2e_assert_ports_free` **fermait le descripteur 3**, celui que Bats réserve à `>&3` : la sonde
  ouvrait le fd dans un sous-shell mais `exec 3<&-` s'exécutait dans le PARENT.
- 🔴 `append_healthcheck_route` (`10-laravel-core.sh`) émettait **toujours** la route littérale
  always-200, et le seul test qui l'exécute comptait des occurrences de `'/health'` sans jamais
  asserter ce que la route FAIT. La route émise fait désormais un `SELECT 1` et rend `503` — le
  repli reste minimal (il ne peut pas référencer Spatie, installé au module 35, alors qu'il tourne
  au module 10) mais il **peut rougir**. Le test asserte le corps émis, l'absence de fuite, et que
  le PHP produit est analysable.
- 🔴 Le repli de `35-configure-spatie-packages.sh` **publiait `$e->getMessage()`** — la fuite DSN
  exacte que `DatabaseHealthCheck` scrube et qu'un test de cette story prétend empêcher. Scrubé.
- 🔴 Le repli littéral à 5 000 ms était justifié par une **prémisse fausse** (« 35-configure peut
  republier `config/health.php` » — il ne publie que `if [ ! -f … ]`, et le fichier est versionné).
  Motif corrigé, et un test pose désormais des valeurs hostiles (`null`, `0`, `-1`, `''`,
  `'beaucoup'`) pour éprouver le repli.
- ⚠️ **Le chemin sain est VACU en environnement de test, et un test le DIT maintenant** :
  `phpunit.xml` force `QUEUE_CONNECTION=sync` (`SyncQueue::size()` rend un `0` codé en dur) et
  `CACHE_STORE=array`. « Trois sondes à ok » ne prouve donc rien sur un vrai Redis. La couverture
  des vrais backends appartient au E2E et à la vérification manuelle.

**Robustesse de `/health`**
- Budget `0` ou négatif : `is_numeric()` les acceptait, l'échéance était **déjà dépassée**, et
  `/health` rendait `503` à perpétuité sans nommer de panne. Plancher + test.
- `warning` et `skipped` étaient écrasés en `error`, ce qui rendait `health.treat_skipped_as_failure`
  **inerte**. Chaque statut est publié tel quel ; la clé est lue, et testée dans les deux sens.
- `shouldRun()` (conditions `->if()` / `->unless()`) était ignoré : les sondes conditionnées
  tournaient quand même.
- `Str::snake` peut faire **collisionner** deux noms (`MonCheck` / `mon_check`) : la seconde
  effaçait la première et `/health` rendait `200` en ayant perdu une sonde. Refus bruyant.
- Une sonde qui explose ne laissait **aucune trace** : `catch (Throwable)` jetait l'exception sans
  un mot. Journalisée (classe + nom de sonde, jamais le message), et testée.
- `DatabaseHealthCheck` n'avait **aucun test propre** — la 12ᵉ mutation du premier jet le disait.
  Il en a quatre, dont le rejeu du `RESET` observé par **comptage des tentatives d'ouverture de
  PDO** (1 avec le garde, 2 sans) plutôt que par une durée bruyante.
- ⛔ **Authentification / limitation de débit : REPORTÉES, avec la raison écrite dans le code.**
  `throttle:` passe par le `RateLimiter`, donc par le **magasin de cache** : le poser ferait rendre
  **500** à `/health` quand le cache est à terre — la classe de défaut que cette story supprime,
  réintroduite par sa propre protection. Report ouvert, trigger Epic 3.

**Nightly et outillage**
- `window_limit_seconds` était **interpolé directement dans un `run:`** (injection), et non validé —
  une valeur non numérique produisait un « integer expression expected » étiqueté INSTALLEUR. Passé
  par `env:`, validé, et étiqueté **ENTRÉE**.
- `E2E_MUTATE_MODULE` était **concaténé dans un chemin** sans liste blanche. Confronté à la liste
  RÉELLE lue dans `scripts/install.sh` — même source que le garde `RESUME_FROM` du Makefile.
- Le pinning de Bats était **contourné dès que `bats` était dans le `PATH`** : la version est
  désormais comparée à un plancher (1.5.0 — sous 1.4.0, `BATS_TEST_TMPDIR` est vide et `LOCKFILE`
  devient `/lock.yml`). Et `rm -rf $(BATS_HOME)` refuse un chemin absolu, vide ou avec `..`.
- Le step CI bloquant **clonait `bats-core` depuis github à chaque exécution** : cache + trois
  tentatives + message étiqueté INFRASTRUCTURE.
- L'étiquetage infra ne lisait qu'`install.log` alors que le workflow grepe les deux : une panne DNS
  visible seulement dans `install-container.log` — le cas le plus fréquent, `composer` et `npm`
  tournant dans le conteneur — était imputée à l'INSTALLEUR.
- 🔴 **Rien ne prévenait d'un nightly rouge, et rien ne le maintenait en vie.** GitHub désactive les
  workflows `schedule` après 60 jours sans activité : le garde-fou se serait arrêté **sans un mot**.
  Deux parades : une issue ouverte/commentée à chaque nuit rouge, et un job CI **bloquant**
  `nightly-freshness` qui rougit si le workflow est désactivé, s'il n'a jamais tourné, ou si son
  dernier run date de plus de 3 jours.
- Échecs de `docker exec` **avalés par `|| true`** → journal vide et grep muet, sans dire pourquoi.
- `teardown_file` appelait un **`sudo` interactif** après 20-40 min de run : il bloquait sans sudo
  sans mot de passe. `sudo -n`, et un nettoyage partiel ne rougit pas.
- **Cascade d'échecs** : un `skip` conditionné laisse désormais UN rouge nommant UNE cause.
- **Ports** : 80/443 seulement étaient vérifiés ; `install-dev-full` publie aussi 8080, 8025, 1025,
  8081, 9999. Et « address already in use » n'était pas une signature infra.
- **Un seul `curl`, sans reprise** : Apache ou php-fpm encore en chauffe → rouge instable imputé à
  l'installeur. `e2e_wait_for_http` attend un état et finit par rendre le code réellement observé.
- **Fenêtre nulle acceptée** : `started_at == finished_at` passait « < 15 min ». Une installation
  entièrement court-circuitée par les sentinelles de la 2.2 aurait été félicitée. Plancher **et**
  plafond, par `e2e_window_verdict`.
- `e2e_iso_to_epoch` était **GNU-only silencieusement** (BSD veut `date -j -f`) : le diagnostic
  disait « horodatage inconvertible » — faux, c'est l'outil. Le lecteur de lockfile **perdait la
  dernière ligne** sans saut final, et confondait champ indenté et champ absent.
- 🔴 **La fixture de lockfile était écrite à la main** — la forme exacte du défaut de tête de la
  story 2.2. Elle est désormais **PRODUITE** par le vrai `scripts/install-lockfile.sh` contre des
  sondes stubées, et un test anti-vacuité vérifie qu'elle l'a bien été.
- 🔴 **L'E2E ne rejouait jamais l'idempotence** — le sujet même de la story 2.2. Il relance
  l'installeur et vérifie exit 0, sauts annoncés, et `/health` toujours vert.
- Le nettoyage filtrait `--filter name=e2e-install`, qui matche par **sous-chaîne** : il passe par
  `label=com.docker.compose.project`.

**Phrases fausses à côté de code juste**
- Trois documents donnaient **trois latences pire-cas différentes** (31 s / 58,6 s / « vers 58 s »),
  et le docblock de la route — celui que lira le mainteneur qui touche au budget — sous-estimait de
  28 s. Les trois portent maintenant les mêmes chiffres, tous re-mesurés après le portillon.
- `asAmnesiacCache()` affirmait que `NullStore::put()` rend `true` ; il rend **`false`** (vérifié
  dans `vendor/`). Le commentaire dit désormais pourquoi le cas reste intéressant : la sonde
  n'inspecte pas le retour de `put()`, elle **relit et compare**.
- 🔴 Le compte de tests ne se réconciliait pas, et la revue avait raison. Il est désormais
  vérifiable ligne à ligne : **371 Pest avant la story** (le compte à l'issue de la revue 2 de la
  2.3, mesuré ici — pas les « 349 » d'une passation antérieure) **+ 52 neufs = 423**. Le détail :
  22 `HealthEndpointTest` · 13 `BackendEndpointTest` · 4 `DatabaseHealthCheckTest` ·
  4 `CacheStoreKeyTest` · 5 `WorkflowInputSafetyTest` · 2 `TrackedFilesGuardTest` ·
  1 `InstallSpatieHealthTemplateTest` · 1 assertion neuve dans `InstallDryRunTest`. À quoi
  s'ajoutent **40 tests Bats**, que Pest ne compte pas et qui tournent par `make test-bats`, et
  **6 tests Bats E2E** non joués sur ce poste.

---

### 🔬 Campagne de mutation — 60 mutations sur la story, 38 pour la seule revue 1

**Revue 1, côté PHP — 17 mutations, 16 rouges observées** (boucle locale, **conteneur php**) :
portillon retiré des trois sondes · portillon qui laisse toujours passer · portillon qui refuse
toujours · résolution d'endpoint base neutralisée · résolution d'endpoint cache neutralisée ·
`warning` traité comme fatal · `treat_skipped_as_failure` ignoré · collision de clés silencieuse ·
`shouldRun()` ignoré · plancher de budget retiré · sonde explosive non journalisée · `RESET`
inconditionnel · `CACHE_DRIVER` rétabli dans `.env.example` · socket unix pris pour un hôte TCP.

⚠️ **La 17ᵉ est VERTE, et c'est écrit plutôt que caché** : « poser le drapeau sans lire le retour de
`statement()` » ne fait rougir aucun test. **La branche est inatteignable dans cette pile** — le
framework impose `PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION` (`Connector::$options`), donc un
`execute()` en échec LÈVE au lieu de rendre `false`. C'est dit dans le code ET dans le test, plutôt
que compté comme un garde.

**Revue 1, côté Bats — 21 mutations, 21 rouges observées** (boucle locale, **hôte nu**, `make
test-bats`) : lecture de lockfile par sous-chaîne · validation d'horodatage retirée · fenêtre
négative ramenée à zéro · champ absent rendant une chaîne vide · lockfile absent ignoré · marqueur
d'infrastructure non écrit · tout journal étiqueté infra · aucun journal étiqueté · recherche
mot-à-mot · fenêtre en dur · **un seul journal lu** · signature « address already in use » retirée ·
**dernière ligne sans saut final perdue** · champ indenté indiscernable d'un champ absent ·
diagnostic `date` non-GNU générique · plancher de fenêtre retiré · plafond retiré · **lecture JSON
par sous-chaîne** · ordre de préférence compose inversé · aucun port jamais occupé · liste de ports
réduite à 80/443.

⚖️ **L'ENVIRONNEMENT DE CHAQUE MESURE EST NOMMÉ**, parce que la story 2.3 a livré un garde vert en
conteneur et rouge en CI : les mutations PHP sont rejouées **dans le conteneur php**
(`vendor/bin/pest`), les mutations Bats **sur l'hôte nu** (`make test-bats`, bats 1.14.0). Aucune
des deux boucles ne dépend de la CI pour rougir.

---

### 🔴 REVUE 2 — le correctif du « test qui évitait le vrai mode de panne » l'évitait aussi

C'est le motif du projet appliqué à sa propre correction. Le test « chemin LENT » de la revue 1
assertait une DURÉE (`< 15 s`) et une SOUS-CHAÎNE de résumé (« portillon »). Mesuré en revue 2 :

| fixture | coût `fsockopen(…, 2.0)` | ce que c'est |
|---|---|---|
| `health-probe.nowhere.invalid` | **0,0149 s** | NXDOMAIN immédiat (RFC 2606) — le chemin **RAPIDE** |
| `postgres-arrete-fictif` | **2,5247 s** | nom NON qualifié, liste de recherche du résolveur |
| `postgres` (conteneur arrêté) | **3,13 s** | **le vrai mode de panne** |
| `127.0.0.1:1` | **0,0001 s** | `ECONNREFUSED` |

Avec le portillon **38 ms**, sans **506 ms** : l'assertion temporelle passait dans les deux cas avec
30× de marge. **Seul le libellé faisait rougir** — renommer le résumé emportait la couverture. Et le
docblock affirmait l'inverse (« 3,13 s »), dans la correction du constat qui portait précisément
là-dessus.

⚖️ **L'observable est désormais le NOMBRE DE TENTATIVES D'OUVERTURE DE PDO** (0 avec portillon),
comme `DatabaseHealthCheckTest` le faisait déjà : déterministe, indépendant de l'horloge et du
libellé, et c'est **la grandeur que le portillon borne**. Les trois assertions « le résumé contient
*portillon* » (base, cache, file) ont été converties de la même façon.

---

### 🩺 UN SECOND DÉFAUT DE MÉTHODE, TROUVÉ EN REJOUANT LA VÉRIFICATION FINALE

🔴 **L'opcache de php-fpm servait une version PÉRIMÉE du portillon, et j'ai failli publier ses
chiffres.** À la dernière passe de vérification, conteneur postgres réellement arrêté :

```
via HTTP        503 en 16,1 · 15,5 · 15,2 · 15,2 · 15,3 s   résumé « Failed »
en CLI          isReachable() = false en 3,1 s              résumé du portillon
```

Le même code, deux réponses. `opcache.revalidate_freq=2` n'avait pas repris les éditions de la
revue 2 dans les workers FPM : les requêtes HTTP exécutaient l'ancienne classe, donc **sans
portillon**, donc la tempête de reconnexions. Après `docker restart laravel-app_php` :

```
via HTTP        503 en 4,05 · 3,19 · 3,21 s                 résumé « Backend injoignable — portillon »
```

⚖️ **La règle qui en sort, et elle vaut pour toute mesure HTTP de ce dépôt** : après avoir édité du
PHP, une mesure prise par `curl` ne dit rien tant que php-fpm n'a pas été redémarré. Le CLI, lui,
recharge à chaque appel — c'est pourquoi les deux ne concordaient pas. Cela vaut aussi pour les
chiffres pris **pendant** la revue 2 sur le chemin redis : ils sont re-mesurés ci-dessous, après
redémarrage.

---

### 🩺 La MÉTHODE avait un défaut, et il est consigné

La revue signalait 9 tests rouges indépendamment de toute mutation. **Reproduit — et la cause
n'était pas celle annoncée.** Mesuré ce jour :

```
docker exec -u 1000:1000 … vendor/bin/pest   → 423 verts   ← la commande de mes campagnes
make test                                     → 423 verts
docker exec … vendor/bin/pest  (donc ROOT)   → 6 échecs sur les 2 fichiers sondés
```

`git check-ignore` rend **128 pour les deux utilisateurs** (`/var/www/html` n'est pas un dépôt) : ce
n'est pas le différenciateur. Le différenciateur est l'**UID**. En root, (a) les fixtures qui
éprouvent un REFUS D'ÉCRITURE réussissent — root écrit partout, donc le garde ne peut pas rougir ;
(b) `git` refuse « detected dubious ownership in repository at '/var/www/project' », le dépôt étant
possédé par l'UID 1000.

✅ **Mes trois campagnes PHP ont tourné avec `-u 1000:1000`**, c'est-à-dire dans l'environnement à
423 verts. Elles sont valides. La commande exacte est écrite ci-dessous, et c'est la seule à
employer :

```bash
# mutations PHP — DANS le conteneur, en UID 1000, jamais en root
docker exec -u 1000:1000 laravel-app_php sh -c 'cd /var/www/html && vendor/bin/pest <fichiers>'
# mutations Bats — sur l'HÔTE NU
make test-bats
```

⚠️ **Et deux FAUX VERTS de mes propres campagnes ont été trouvés et corrigés :**
- le test cron employait `->hourly()` (« 0 * * * * ») : la mutation « rétablir `shouldRun()` » est
  passée **VERTE pendant la minute 0** de l'heure où la campagne a tourné. L'expression est
  désormais **calculée** pour ne jamais être due ;
- deux mutations (`10-laravel-core`, `35-configure-spatie`) visaient des fichiers dont les gardes
  vivent dans une suite que le script n'exécutait pas. Rejouées avec la bonne suite : **rouges**.

---

### Les 31 constats de revue 2, par famille

**Gardes qui ne gardaient rien**
- `e2e_wait_for_http` décidait **trois** verdicts du E2E sans aucun test : la forcer à `return 0`
  rendait inconditionnelle la garde anti-vacuité « la pile revient à 200 ». Quatre tests, contre un
  **vrai** `python3 -m http.server` — dont un service démarré en retard, qui prouve la reprise.
  Ils ont trouvé un défaut au passage : `curl … || echo "000"` **recollait** son repli à la sortie
  de curl, qui imprime déjà `000`, donc `$code` valait « 000\n000 ».
- Le corps réel de `e2e_port_is_busy` n'était **jamais exécuté** (les deux tests stubaient la
  fonction) : réintroduire le bug fd-3 de la passe 1 donnait 31/31 ok. Un test lie maintenant un
  port éphémère RÉEL, exerce le corps, et **écrit sur `>&3`** — l'écriture échoue si le défaut
  revient. Le stubbing par couture avait déplacé la surface non testée d'un cran.
- `e2e_published_ports` était faux **dans les deux sens** : il omettait **5432** (publié par
  `docker-compose.dev.yml` sur un service sans profil, donc toujours démarré) et incluait **8082**
  (`redis-commander`, profil `dev-extra`, jamais démarré). Le test recopiait le littéral. La liste
  est maintenant **dérivée de `docker compose config`** — même correctif qu'en 2.3 pour
  `COMPOSITE_INSTALL_TARGETS` — et le test l'exerce sur un fichier compose fabriqué, qu'aucune
  liste écrite à la main ne peut satisfaire.
- Le scrub DSN du module 35 n'était observable par **aucun** test : le module 10 a un harnais, le 35
  n'en avait pas. Il en a un (`InstallSpatieHealthTemplateTest`), et la mutation est rouge.
- Retirer `"tests"` de `GUARDED` (`assert-tracked-files.sh`) était **invisible**. Gardé.

**Défauts introduits par les correctifs de la revue 1**
- `BackendEndpoint` se désactivait **en silence** sur un `host` en TABLEAU (lecture/écriture,
  multi-hôtes), sur `DATABASE_URL`/`REDIS_URL`, et sur `memcached`/`beanstalkd` — exactement les
  déploiements où il compte. Les quatre sont couverts. Et le faux négatif restant (hôte à plusieurs
  enregistrements A, `fsockopen` n'essaie qu'une adresse) a une **porte de sortie nommée** :
  `HEALTH_PROBE_GATE=false`, testée dans les deux sens.
- `shouldRun()` évaluait aussi l'**expression cron** de Spatie : une sonde `->hourly()` aurait fait
  rendre **503** 59 minutes sur 60. Seules les conditions `->if()`/`->unless()` sont honorées.
- La route de repli du module 10 attrape `\Throwable`, pas `PDOException` : entre le module 10 et le
  20 la connexion n'est **pas encore configurée**, et `DB` y lève autre chose qu'une erreur de
  connexion — un **500** au lieu d'un `503`.
- Le job d'alerte du nightly était **mort à son premier appel** : `--jq '.[0].number'` imprime le
  littéral « null » sur un ensemble vide, `[ -n "null" ]` est vrai, `gh issue comment null` échoue
  sous `bash -e`. L'issue n'était **jamais** créée. `// empty`, plus la création du label `nightly`
  (sans lui, le repli créait une issue orpheline : une neuve chaque nuit).
- `window_limit_seconds` atteignait encore un `run:` par **interpolation directe**, dans un step
  `if: always()` — donc rendu même après l'échec de la validation. Corrigé sur deux sites, pas sur
  trois. `WorkflowInputSafetyTest` balaye désormais **tous** les workflows.
- `E2E_PROJECT` était écrit deux fois en littéral : porté au niveau workflow.
- `e2e_json_field` imprimait `True`/`False` (Python) là où bats compare à `true`/`false`.
- `BoundsBackendReachability` justifiait une décision par « `/health` est seulement limité en
  débit » — alors que la limitation de débit a été **reportée** par cette même story.
- Les deux gabarits d'environnement semblaient se contredire : chacun **dit maintenant quel
  environnement il gouverne** (racine = pile Docker ; `src/` = squelette nu). Et **deux fichiers
  suivis prescrivaient encore la clé morte** — `docs/architecture/4-architecture-donnes.md`, qui
  fait autorité, et `prompts/testing/01-add-dusk-e2e-testing.md`. `CacheStoreKeyTest` **balaye le
  dépôt** au lieu d'énumérer six chemins, et distingue « prescrire » de « mentionner ».

**À consigner, et consigné**
- Les assertions sur le gabarit de route du module 10 épinglent une **formulation**, pas un
  comportement : la route émise n'est jamais exécutée. C'est écrit dans le test.
- La liste blanche `E2E_MUTATE_MODULE` ne vit que dans le chemin de 20-40 min ; **ce qui bloque
  réellement une traversée, c'est le contrôle de jeu de caractères du workflow**. Écrit sur place.

---

### 🔬 Campagne de mutation — revue 2 : 27 mutations, 27 rouges OBSERVÉES

**17 côté PHP**, rejouées **dans le conteneur php en UID 1000** (`vendor/bin/pest`, la commande
écrite plus haut) : portillon retiré de la sonde base · portillon toujours passant · porte de sortie
inopérante · hôte en LISTE ignoré · `DATABASE_URL` ignorée · `memcached` non résolu · `beanstalkd`
non résolu · cron de Spatie appliqué à la requête HTTP · conditions `->if()`/`->unless()` ignorées ·
Telescope réenregistrant `/health` · alerte `.[0].number` nu · label `nightly` jamais créé · repli
d'issue **sans** label rétabli · `window_limit` interpolé dans un corps de `run:` · `"tests"` retiré
de `GUARDED` · module 35 refuyant le DSN · repli du module 10 n'attrapant que `PDOException`.

**10 côté Bats**, rejouées **sur l'hôte nu** : `wait_for_http` rendant toujours un succès · ne
rejouant jamais · avalant le code réel · avec le repli qui recolle `000` · `port_is_busy` refermant
le fd 3 du parent · déclarant tout port occupé · liste de ports incluant `dev-extra` · repli
silencieux sur liste vide · scalaires JSON à la mode Python.

🔴 **Trois de ces mutations ont d'abord été vues VERTES, et chacune a corrigé un test :**
- « cron appliqué » : le test employait `->hourly()`, donc vrai **59 minutes sur 60** — la campagne
  est tombée sur la minute 0. Expression désormais **calculée** pour n'être jamais due ;
- « repli du module 10 » et « module 35 » : les gardes vivaient dans une suite que le script
  n'exécutait pas. Suite corrigée, mutations rejouées, rouges ;
- « repli silencieux sur liste vide » : le test voisin passait un répertoire SANS compose, donc la
  fonction sortait **avant** d'atteindre la branche. Un test où compose répond parfaitement mais ne
  publie aucun port a été ajouté.

⚠️ **Et une quatrième a révélé un défaut dans MES PROPRES TESTS** : la mutation « `port_is_busy`
referme le fd 3 » faisait **rester bats suspendu indéfiniment** — mes tests HTTP lançaient
`(cd … && python3 -m http.server) &`, donc `$!` était le pid du SOUS-SHELL et le serveur survivait
au `kill`, tenant le descripteur que Bats lit. Corrigé par `--directory` + `exec` + descripteurs
détachés ; la suite filtrée passe désormais en quelques secondes au lieu de rester bloquée.

---

### 🔁 La bascule à faire JUSTE APRÈS le premier nightly

> ⛔ **Deux gestes, dans cet ordre, et le second est une décision d'Alex prise en revue 2.**

**1. Lancer le nightly une fois, et consigner le run.**
Actions → *Nightly E2E Install* → *Run workflow*, sans mutation. Puis une seconde fois avec
`mutate_module = 20-database`, qui **DOIT** être rouge. Reporter les deux numéros de run ici.

**2. Rebasculer `nightly-freshness` en BLOQUANT.** Il est aujourd'hui **hors** des `needs` de
`CI Summary`, et c'est délibéré : tant qu'il rougit par construction (le nightly n'a jamais tourné),
le laisser dans le verdict global **masquerait une régression réelle** d'`integrity`, `quality`,
`tests` ou `browser` — on apprendrait à lire « CI rouge » comme « ah oui, le nightly ». C'est le
mécanisme du garde-fou qu'on désarme, appliqué au garde-fou anti-désarmement.

Concrètement, dans `.github/workflows/ci.yml`, job `summary` :

```yaml
    needs: [integrity, quality, tests, browser, nightly-freshness]      # ← rajouter
...
        if: needs.integrity.result != 'success' || … || needs.nightly-freshness.result != 'success'
```

…et retirer les quatre lignes d'avertissement du résumé qui annoncent la non-blocance.

⚖️ **Ce que `nightly-freshness` vérifie déjà**, et qui ne changera pas à la bascule : le workflow est
`active` (GitHub désactive les `schedule` après 60 jours d'inactivité), il a tourné il y a moins de
3 jours, **et son dernier run a CONCLU `success`**. Ce dernier point vient de la revue 2 : sans lui,
un nightly qui échoue toutes les nuits laissait le garde **vert** — le garde-fou écrit pour empêcher
qu'un garde-fou s'éteigne en silence était aveugle à son échec.

---

### ⚠️ Ce que la story 2.4 n'a PAS pu observer — et le test qui l'empêche d'être oublié

**Le nightly n'a JAMAIS tourné.** Ni vert, ni rouge. Trois raisons structurelles : `workflow_dispatch`
n'est déclenchable que lorsque le workflow existe sur la branche par défaut ; la CI de ce dépôt ne
se déclenche que sur `main`/`develop` ; et le E2E exige les ports publiés **libres**, donc démonter
la pile de développement d'Alex.

🔴 **CE REPORT EST DEVENU UN TEST QUI ROUGIT.** Le job CI `nightly-freshness` échoue
tant que le workflow n'a jamais tourné, s'il est désactivé, ou si son dernier run date de plus de
3 jours. **La CI sera donc rouge sur ce job jusqu'au premier lancement du nightly** — c'est l'état
réel, et c'est voulu : le projet préfère un rouge qui nomme la dette à une phrase dans un registre.

⚠️ **CORRIGÉ LE 2026-08-24 : ce paragraphe écrivait « le job CI **bloquant** ».** Il ne l'est pas —
il est délibérément HORS des `needs` de `CI Summary` (décision d'Alex, revue 2, expliquée juste
au-dessus). Une phrase fausse à côté d'un code juste, dans le document qui décrit précisément la
bascule qui le rendrait vrai : le motif de tête de ce projet, reproduit dans son propre journal.

**Les deux AC qui restent ouverts, et la manière EXACTE de les fermer :**

- *« mutation de l'installeur exécutée, nightly observé rouge, numéro de run consigné »* →
  Actions → **Nightly E2E Install** → *Run workflow* → `mutate_module = 20-database`. Le module est
  muté **dans le clone** (jamais dans le dépôt), après confrontation à la liste blanche des modules
  réels ; le rapport nomme le module fautif via `Échec du module <nom>`. Un run ainsi lancé **DOIT**
  être rouge.
- *« fenêtre `started_at`→`finished_at` < 15 min sur une install nominale »* → premier run planifié,
  ou *Run workflow* sans mutation. La durée est publiée dans le résumé du job.

✅ **Ce QUI a été observé, sur cette pile, ce jour — php-fpm redémarré, opcache frais :**

| scénario | code | temps | sondes |
|---|---|---|---|
| application saine | `200` | 0,110 s | database ok · cache ok · queue ok |
| **conteneur postgres réellement arrêté** | **`503`** | 4,05 / 3,19 / 3,21 s | **database error** · cache ok · queue ok |
| `/up`, même état | `200` | 0,074 s | *(ne dit rien de la base — c'est son contrat)* |
| **conteneur redis réellement arrêté** | **`503`** | 10,45 / 9,64 / 9,61 s | database ok · **cache error** · **queue error** |
| remontée complète | `200` | 0,112 s | les trois à `ok` |

Plus : **87 mutations sur la story** (60 + 27 en revue 2), **423 tests Pest**, **40 tests Bats**,
ratchet **0/0/0**.

⚠️ Le chemin redis reste à ~9,6 s pour 6,2 s de portillons : les **~3,4 s restantes ne sont pas
localisées**, et l'exclusion Telescope les avait déjà réduites. Report tenu à jour.

---

### 📁 Fichiers

**Neufs** — `src/app/HealthChecks/CacheHealthCheck.php`, `QueueHealthCheck.php`,
`Support/BackendEndpoint.php`, `Support/BoundsBackendReachability.php` ·
`src/tests/Feature/HealthEndpointTest.php`, `DatabaseHealthCheckTest.php`,
`BackendEndpointTest.php` · `src/tests/Unit/CacheStoreKeyTest.php` ·
`src/tests/Support/HealthProbe.php`, `UnreachableBackends.php` ·
`tests/bats/lib/e2e.bash`, `tests/bats/unit/e2e-lib.bats`, `tests/bats/install.bats` ·
`.github/workflows/nightly.yml`.

**Modifiés** — `src/routes/web.php` · `src/app/Providers/AppServiceProvider.php` ·
`src/app/HealthChecks/DatabaseHealthCheck.php` · `src/config/health.php` ·
`src/tests/Unit/InstallDryRunTest.php` · `scripts/install/10-laravel-core.sh` ·
`scripts/install/35-configure-spatie-packages.sh` · `scripts/setup/generate-configs.sh` ·
`scripts/lib/laravel.sh` · `scripts/assert-tracked-files.sh` · `Makefile` · `.env.example` ·
`.gitignore` · `.github/workflows/ci.yml` · `.github/workflows/docker.yml`.

**Non touchés, et c'est délibéré** — `docker/apache/conf/sites-enabled/laravel.conf:111` (Ask
First), `scripts/lib/common.sh` (report W17), `bootstrap/app.php` (`/up` reste ce qu'il est).

---

## ✅ Story 2.3 — `--dry-run` et `--resume-from` tiennent enfin leur promesse

> **349 tests · ratchet 0/0/0 · 19 mutations rejouées, 19 rouges observés.**
> `./scripts/install.sh --dry-run` va au bout et laisse `git status --porcelain` **vide**.

**Ce que la story a réellement changé — les deux drapeaux EXISTAIENT déjà** (`epics.md` demande
de les « implémenter » ; ils sont là depuis toujours). Ce qui manquait était ailleurs, et mesuré :

1. **La simulation s'arrêtait au grain module.** Elle annonçait « je simulerais `10-laravel-core` »
   sans jamais dire **ce qu'elle effacerait**. Elle descend maintenant au grain de la **commande** :
   `[DRY] rm -rf -- <cible>/vendor`, une ligne par entrée condamnée.
2. **Elle n'était PAS sans effet de bord.** `validate_arguments` faisait `mkdir -p` + `chown -R` +
   `chmod -R 755` (et jusqu'à `777`) sur la cible, et `execute_module` un `chmod +x` sur un fichier
   **versionné** — les deux **avant** toute branche `--dry-run`. Un `--dry-run` salissait donc le
   dépôt. Les deux sont neutralisés et diagnostiqués.
3. **`run_cmd` n'existait nulle part**, alors que l'AC de l'epic la nomme. Elle est livrée dans
   `scripts/lib/runtime.sh` (5ᵉ primitive), lit `INSTALL_DRY_RUN`, rend le **code réel**, meurt sans
   argument, et est ajoutée à l'`export -f`.
4. **`make` n'exposait aucun des deux drapeaux.** `make install-laravel DRY_RUN=true
   RESUME_FROM=20-database` relaie désormais `--dry-run --resume-from 20-database`, aux six
   invocations d'`install.sh` (`install-laravel` + les cinq `--only` d'`install-laravel-prod`).

**Le mécanisme : la simulation est OPT-IN PAR MODULE.** `DRY_RUN_AWARE_MODULES` (`install.sh`) ne
contient qu'une entrée, `10-laravel-core`. Un module inscrit est **réellement lancé** sous
`--dry-run` et route ses commandes à effet par `run_cmd` ; tous les autres gardent l'annonce-et-saut,
qui reste la garantie forte de zéro effet.
⛔ **Inscrire un module engage l'audit du module ENTIER**, pas de ses seules lignes destructrices :
ce qui n'est pas routé s'exécute pour de vrai, sous un drapeau qui promet l'inverse. Les 1132 lignes
de `10-laravel-core.sh` ont été relues ; **67 occurrences de `run_cmd`** y couvrent `rm -rf`,
`composer create-project`, `composer install`, `cp -a`, `chown`/`chmod`/`mkdir`, `sed -i`,
`php artisan key:generate|config:clear|cache:clear|view:clear|config:cache` et les deux patchs
`python3` du `composer.json`.

**📋 `20-database` et `99-finalize` sont REPORTÉS** (`_bmad-output/implementation-artifacts/deferred-work.md`,
trigger **Story 2.4**). Tant que le report est ouvert, leur simulation ne dit **rien** des migrations
ni des caches qu'ils joueraient — c'est écrit dans le commentaire de la liste, pas seulement ici.

🔴 **Le commentaire FAUX de `install.sh:41-44` est corrigé.** Il affirmait que « les modules tournent
en sous-processus, donc l'`export -f` de `runtime.sh` ne les atteint pas ». **Sondé : c'est
l'inverse** — bash exporte ses fonctions aux enfants via `BASH_FUNC_x%%`, et un `bash -c 'declare -F
ensure_idempotent'` rend **oui**. Toute la story 2.3 en dépend : c'est parce que l'export traverse
qu'un module lancé en sous-processus peut router ses commandes par `run_cmd`. La vraie raison de
l'enveloppement au niveau orchestrateur est le **grain** — seul l'orchestrateur connaît la liste,
l'ordre, `--only`, `--resume-from` et `--force`.

⚖️ **`pipefail` : Ask First tranché en « pinner, pas armer ».** Le docblock d'`arm_err_trap`
promettait « une commande nue qui échoue meurt » sans dire qu'un **pipeline en était exclu** (report
W20). Neuf pipelines `| tee -a "$LOG_FILE"` dépendent de l'absence de `pipefail`. Le docblock est
corrigé et le comportement **réel** est gelé par un test — armer `pipefail` un jour fera rougir la
suite avant la régression.

⚠️ **Deux constats relevés et NON corrigés, écrits plutôt que tus :**
- `install_laravel_via_composer` teste `if ! cmd 2>&1 | tee -a "$LOG_FILE"` — le statut est celui de
  `tee`, donc la **branche de repli `laravel new` est morte**. La réparer changerait le comportement
  d'installation réelle, hors périmètre gelé de la 2.3. Le commentaire le dit sur place.
- `copy_environment_configuration` appelle `find_root_env` **sans argument** (`common.sh:405` attend
  une racine de projet) ; la détection d'`APP_ENV` depuis le `.env` racine ne peut donc pas aboutir.

**🔬 Campagne de mutation — 19 mutations exécutées, 19 rouges OBSERVÉS** (jamais déduits) :
`run_cmd` sans branche de simulation · code réel avalé · `die` retiré · `-n` au lieu de `= true` ·
absente de l'`export -f` · `pipefail` armé · `export INSTALL_DRY_RUN` retiré · tous les modules
*aware* · aucun module *aware* · garde de `validate_arguments` neutralisée · `chmod +x` rétabli en
simulation · coquille dans `DRY_RUN_AWARE_MODULES` · sentinelle écrite en simulation · `started-at`
écrit en simulation · `rm -rf` non routé · post-condition de vacuité jouée · `run_cmd_quiet`
ignorant la simulation · garde `$(error)` des chaînes composites désarmée · pass-through `make`
retiré.

🔴 **Un test a été trouvé MUET par sa propre mutation, et corrigé.** « le module *aware* ne pose pas
sa sentinelle » restait **VERT** quand on lui faisait écrire la sentinelle : la racine d'état
n'existait pas dans le bac à sable, l'écriture échouait, et le compteur retombait à 0 **pour une
raison étrangère au sujet**. Un compteur qui vaut 0 parce que rien ne POUVAIT s'écrire ne mesure
rien. La sonde crée désormais la racine — et la mutation rougit.

---

## 🔁 Story 2.3 — revue 2 (dernière) : la correction du constat sur les FLUX a menti à son tour

> **371 tests · ratchet 0/0/0 · 17 mutations neuves (16 rouges + 1 témoin neutre voulu vert).**
> Total story : **56 mutations rejouées**.

🔴 **LE MOTIF DE TÊTE DU PROJET S'EST REPRODUIT DANS LA CORRECTION D'UN CONSTAT SUR LE MOTIF.**
La passe 1 demandait de dire sur quel flux part le plan `--dry-run`. La correction a écrit, en
**cinq endroits** — dont `CLAUDE.md` et l'aide de `--help`, les deux que l'opérateur lit — que
« les lignes `[DRY]` partent sur **STDERR**, `> plan.txt` rend un fichier vide ».
**Mesuré : 16 lignes sur STDOUT, 2 sur STDERR.** Un opérateur suivant la doc perdait le plan.
Cause : `execute_module` lance le module *aware* en `2>&1 | tee -a "$LOG_FILE"`, ce qui replie son
stderr dans le stdout de l'orchestrateur. **Aucune sonde ne pouvait le contredire** :
`ShellProbe::run()` construit `bash … 2>&1`, donc toutes les assertions lisaient un flux fusionné.
Parade : `ShellProbe::runSeparated()` (`1> a 2> b`), qui compte sur chaque flux — et la prose dit
désormais la seule chose vraie : **capture complète = `2>&1`**.

⚖️ **QUATRE CONSTATS DE LA PASSE 1 N'ÉTAIENT PAS CONSOMMÉS**, et le relecteur l'a prouvé en
rejouant les mutations :
- **six des sept sites `tee` ressuscités n'avaient aucune sonde** — réécrire `composer install` à
  travers `tee` laissait les 20 tests VERTS, le garde textuel comptant la ligne comme routée parce
  qu'elle contient `run_cmd`. Deux sondes d'**exécution** ajoutées (`composer install`, `cp -a`),
  avec composer/cp/installeur stubés ;
- **neuf des onze `log_applied` n'étaient assertées par rien** — deux chaînes choisies à la main ne
  gardent pas onze sites. Remplacé par un **invariant global** sur la sortie simulée ;
- **la liste composite ne détectait pas une chaîne NEUVE** : ajouter `install-dev-turbo: build
  up-dev install-laravel npm-install` était accepté sous `DRY_RUN=true`. La composite-ness est
  maintenant **dérivée du graphe**, et la dérivation a trouvé une cible que l'énumération avait
  **manquée** : `setup-quick` ;
- **le scan `run_cmd` était contournable par un commentaire** — il porte désormais sur du CODE.

🔴 **ONZE RÉGRESSIONS INTRODUITES PAR LES CORRECTIFS EUX-MÊMES.** La plus large :
`DRY_RUN`/`RESUME_FROM` sont des noms **génériques**, et leur validation évaluée au parse global
faisait sortir en 2 **toutes** les cibles — `DRY_RUN=1 make help`, `RESUME_FROM=x make status`,
`make test`. Portée sur `MAKECMDGOALS` ; et rendue **littérale**, `$(filter)` traitant `%` comme un
joker (`DRY_RUN=%` passait, donc installation réelle en silence). Les dix autres : rapport d'échec
amputé, `.env` absent devenu fatal, succès journalisé après échec, `cp -a` jugé sur son code alors
que `-p` échoue légitimement sur le propriétaire, repli `laravel new` à chemin figé et majeure non
épinglée, `rm -f` de sentinelles absents du plan, `--skip-prereq` hors de tout compteur, ligne
`[DRY]` dupliquée dans le journal, et quatre branches qui **prédisaient** sur un `.env` que la
simulation n'a pas copié.

⚠️ **UN GARDE QUI NE PEUT PAS ROUGIR DANS LA BOUCLE LOCALE, ET C'EST ÉCRIT.** La mutation du garde
« `.env` jamais écrasé sans sauvegarde » reste **verte dans le conteneur** : le `cp` de **BusyBox**
refuse l'écrasement de lui-même, donc `.env` survit pour une raison **étrangère au garde**. Elle
rougit sur GNU coreutils, donc en CI. Le garde tient là où il compte, mais `make test` ne peut pas
le prouver — report ouvert dans `deferred-work.md`, et la phrase qui annonçait « toutes rouges » a
été corrigée plutôt que laissée.

---

## 🔁 Story 2.3 — revue 1 : la conception a tenu, les BORDS ont cédé

> **19 constats, tous traités. 20 mutations neuves, 19 rouges observés dans la boucle locale.**
> ⚠️ La 20ᵉ — le garde « `.env` jamais écrasé sans sauvegarde » — **ne rougit pas dans le
> conteneur** : le `cp` de BusyBox refuse l'écrasement de lui-même, donc `.env` survit pour une
> raison étrangère au garde. Elle rougit sur GNU coreutils (CI). Report ouvert dans
> `deferred-work.md` — rendre la sonde indépendante de l'implémentation de `cp`.
> `run_cmd` + modules *aware* opt-in a traversé les trois couches de revue **intacte** — la
> conception n'a pas été rouverte.

🔴 **UNE SEULE CAUSE RACINE POUR LES DEUX CONSTATS STRUCTURANTS : les AC mesuraient une
PROPAGATION DE DRAPEAU, pas un EFFET.** `make -n` n'exécute rien. Tous les gardes étaient verts
pendant que :

1. **`make install-laravel DRY_RUN=true` n'atteignait que l'étape 1/5.** Les étapes 2 à 5
   s'exécutaient ensuite POUR DE VRAI sur l'application : `chown -R www-data:www-data
   /var/www/html`, deux `find -exec chmod 775/664`, `chmod +x artisan`, `chmod -R 775 storage`,
   puis **`fix-permissions-host` en sudo** côté hôte. La porte d'entrée `make` de la story
   réintroduisait exactement la classe d'effet de bord qu'elle venait de retirer de
   `validate_arguments`. Le raisonnement écrit au-dessus du `$(error)` des chaînes composites
   s'appliquait mot pour mot à cette cible — et personne ne l'avait appliqué.
2. **Le rapport final de la simulation DÉCLARAIT une installation faite** : `🎉 Installation
   Laravel terminée`, `🆕 VERDICT: EXECUTED — 11 module(s) joué(s)`, les onze modules listés sous
   « Modules installés », puis un `cd "$TARGET_DIR"` + `php artisan --version` qui **boote
   l'application** et écrit dans `storage/logs/`. `main()` de `10-laravel-core` avait été rendue
   honnête ; la clôture de l'orchestrateur, non.

⚖️ **La règle nouvelle, non négociable : un AC de cette story se mesure sur un EFFET.** Les sondes
`make` lancent désormais make POUR DE VRAI, avec un `docker` et un `$(MAKE)` remplacés par des
témoins, et mesurent la cible au `stat` — modes ET propriétaire, parce qu'un `chmod` ne touche que
le ctime et qu'aucune empreinte nom+octets+mtime ne le voit.

🔴 **SEPT BRANCHES D'ÉCHEC ÉTAIENT MORTES DANS `10-laravel-core.sh`.** `if ! cmd 2>&1 | tee -a
"$LOG_FILE"` teste le code de **`tee`**, jamais celui de la commande. Le piège était décrit noir sur
blanc dans le docblock que cette story venait d'écrire pour `run_cmd`, et il vivait dans le fichier
d'à côté — repli `laravel new`, échec de `composer install`, échec de la copie `cp -a` vers la
cible, et **`key:generate`, dont l'appelant traite pourtant l'échec comme FATAL** : une application
partait avec un `APP_KEY` vide en croyant l'avoir généré. `run_cmd_logged` rend `${PIPESTATUS[0]}`.

🔴 **DEUX RÉGRESSIONS INTRODUITES PAR LE ROUTAGE LUI-MÊME**, sur le chemin RÉEL : (1) la sauvegarde
du `.env` était devenue facultative (`run_cmd cp … || log_warn` là où un `cp` nu sous `set -e`
arrêtait tout) et la copie suivante écrasait le `.env` de l'opérateur **sans filet** ; (2) l'absence
de `routes/web.php` était devenue un avertissement — donc une application réelle sans route
`/health`, **healthcheck Docker mort**, pour une ligne dans un journal de `/tmp`.

🔴 **ET LE MOTIF DE TÊTE DU PROJET S'EST REPRODUIT DANS LA STORY QUI LE COMBAT** : six
`log_success` / `log_debug` de `10-laravel-core` annonçaient « ✅ fait » sous simulation. `main()`
avait été soigneusement corrigée ; les fonctions qu'elle appelle, pas. Variante inédite relevée au
passage : la simulation **SUR-déclarait** `cache:clear`, qu'en réel une sonde non jouée peut refuser
— sur-déclarer est un mensonge de la même famille que sous-déclarer.

🔴 **TROIS GARDES DE TEST NE GARDAIENT RIEN** (34ᵉ, 35ᵉ et 36ᵉ instances du motif) :
- `substr_count($source, 'run_cmd') > 20` sur un fichier qui en compte **67**, commentaires compris.
  Remplacé par un invariant d'**absence** : aucune ligne non commentée n'invoque une commande à
  effet sans `run_cmd`, liste d'exceptions explicite et justifiée. Retirer **un seul** `run_cmd`
  rougit.
- La fixture de simulation n'était **pas** une application : ni `artisan`, ni `routes/web.php`, ni
  `phpunit.xml`. Les trois `run_cmd sed -i … phpunit.xml` et `run_cmd append_healthcheck_route`
  n'étaient **jamais atteints** — on pouvait leur retirer `run_cmd` sans rien faire rougir.
- Le grep des cinq invocations `--only` n'observait que la **première** ligne : retirer le drapeau
  de la ligne `20-database` — celle des **migrations** — laissait le test vert.

🩺 **DEUX SONDES NEUVES TROUVÉES MUETTES PAR LEUR PROPRE MUTATION, ET CORRIGÉES.**
- `APP_ENV` est **hérité de PHP** (`phpunit.xml` pose `testing`) : le test du `.env` cherchait
  `.env.testing`, sortait par « aucun fichier .env trouvé », et restait vert sur ses deux premières
  assertions sans jamais atteindre la sauvegarde qu'il prétend garder. `ShellProbe` n'épingle que
  les **cinq** variables lues par `logging.sh`/`runtime.sh` — celle-ci est lue par le module.
- La fixture Laravel-shaped portait un `APP_KEY`, ce qui faisait sortir `generate_application_key`
  par sa branche « clé existante conservée ».

⚖️ **Un défaut de TESTABILITÉ corrigé dans le code, sur mesure** : `copy_environment_configuration`
lit désormais `${INSTALL_PROJECT_ROOT:-/var/www/project}`. Écrite en dur, la garde de sauvegarde
n'était atteignable que si `/var/www/project/.env.local` existait — donc jamais sur un runner CI, où
les `.env` ne sont pas versionnés. Même argument que `INSTALL_STATE_DIR` à la story 2.2.

**Makefile, quatre trous fermés** : `DRY_RUN` est `$(strip)`ée et **validée** — `DRY_RUN=1`, `yes`,
`TRUE` retombaient silencieusement dans la branche « pas de simulation » et lançaient une
**installation réelle** ; `RESUME_FROM` est validée contre `INSTALL_MODULES` **extrait de
`scripts/install.sh`** (ce qui ferme aussi le quoting dans le `docker exec`) ; `RESUME_FROM` est
refusé sur `install-laravel-prod` (`--only X --resume-from Y`, précédence non spécifiée) ;
`COMPOSITE_INSTALL_TARGETS` est **lu depuis le Makefile** par le test — c'était la seule des trois
listes du même diff à être réécrite en dur.

📣 **Découvrabilité** : `CLAUDE.md` §Laravel Development et les commentaires `##` d'aide
(`make help`) nomment enfin `DRY_RUN=` et `RESUME_FROM=`. Et le piège à dire tout haut : **le plan
est réparti sur les DEUX flux** — l'orchestrateur journalise sur stderr, mais `execute_module`
lance le module *aware* en `2>&1 | tee`, ce qui replie sa sortie dans le stdout. Capture complète :
`--dry-run > plan.txt 2>&1` ou `2>&1 | tee plan.txt`.

📋 **Deux reports NEUFS** (`deferred-work.md`) : promouvoir `dry_run_active` / `run_cmd_quiet` /
`run_cmd_logged` / `log_applied` vers `runtime.sh` — **trigger : le 2ᵉ module *aware***, pas avant
(promouvoir une primitive à un seul appelant, c'est le piège W23) ; et trancher l'appel
`find_root_env` **sans argument** de `copy_environment_configuration`, dont le voisin
`find_root_env_file()` local et sans appelant est à **une lettre** — trigger : Story 2.4.

---

## ➡️ PROCHAINE ACTION — Story 2.4

**Niveau de cérémonie : R — Renforcé** (`03-boucle-qualite.md` §2 nomme « l'installeur »).
Véhicule de test actuel : `ShellProbe` + suite Unit — **Bats n'arrive qu'en story 2.4**, et c'est
elle qui débloque quatre reports (`W17`, `W22`, et les conversions de `20-database` / `99-finalize`).

**Rappel d'environnement** : la CI ne se déclenche que sur `main`/`develop`. Une branche de story
ne produit **aucun run** ; le verdict n'existe qu'au merge.

---

---

> ✅ **Story 2.1 `done`.** `main` = **`a076a91`**, poussé, **5 jobs CI verts**
> (run 32580142920). **289 tests · 34 navigateur · ratchet 0/0/0.**
>
> 🔴 **La trouvaille tient en une ligne, et elle n'était pas dans la bibliothèque.** `logging.sh`
> affichait sur **stdout**, donc toute capture `x=$(fonction_qui_journalise)` avalait la bannière et
> la rendait comme **valeur** : `detect_working_directory` rendait « [WARN] Structure non reconnue »
> suivi du chemin — un répertoire inexistant, donc non inscriptible, donc pilote à **1**. Dix sites
> capturent cette fonction. Correctif : `>&2`.
>
> 🔴 **Le spec affirmait « les tests tournent dans le conteneur ». Faux.** Le job `tests` s'exécute
> sur `ubuntu-latest` **nu**, et `src/**` était **déjà** en `paths:` : la CI serait partie rouge au
> premier push, sur deux tests assertant `exit 0` sans condition. La CI a **tranché** : les 34 tests
> ont tourné là-bas, dont « rend 0 **HORS conteneur** ». L'inconnue est levée, pas contournée.
>
> ⚖️ **Le `Never: toucher common.sh` n'a PAS eu à être levé** alors qu'Alex l'avait autorisé : le
> recensement a montré la cause **en amont**, dans `logging.sh`, que le `Never` ne nomme pas.
> `common.sh` (892 lignes, 15 consommateurs) reste intouché. *Une autorisation large n'oblige pas à
> s'en servir.*
>
> 🔴 **20ᵉ garde-fou silencieux, dans la story qui en pose un.** Le commentaire de `runtime.sh`
> affirmait que le `readonly` de la sentinelle rendait la garde d'inclusion vérifiable, « mutation
> vue rouge ». Mesuré : le retirer laisse **34 verts**. C'est le bloc `if` qui garde. La mutation
> annoncée rouge ne l'avait jamais été — trouvée par un relecteur qui l'a **rejouée** au lieu de lire
> la phrase.
>
> **Prochaine étape : story 2.2** (`2-2-idempotent-install-with-sentinel-lockfile`) — c'est elle qui
> donne un lecteur à `ensure_idempotent`, livrée sans consommateur de production (W23).
>
> ⚠️ **10 reports ouverts, W14 à W23.** Les plus mordants : **W19** (l'inventaire traverse 1179
> entrées de `_bmad/` et `.claude/` — cause probable de l'instabilité W16, qu'on avait attribuée à
> Laravel), **W22** (le défaut de double-`source` reste vivant dans les 4 autres libs), **W17/W23**
> (3 primitives sur 5 sans appelant, et 4 `retry` maison subsistent dans `scripts/lib/`).
>
> ⚠️ **Fenêtre inchangée : A4**, le scan de couplage aveugle aux FQCN, à refaire **avant Epic 4**.

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
| 🔴 **PR #27 : une décision écrite trois fois, et l'objet qu'elle gouverne ne la porte pas** | Dependabot propose `node 24.19.0-alpine3.23 → 26.7.0-alpine3.23` (`origin/dependabot/docker/docker/node/node-26.7.0-alpine3.23`), **ouverte depuis le 2026-08-10**. Le bump est **refusé jusqu'au 2026-10-28** — v24 est Active LTS jusqu'au 2026-10-20, v26 n'est LTS qu'au 2026-10-28 — et c'est écrit dans `docker/node/Dockerfile:3`, `docs/ETAT.md:287` et le pense-bête plus bas. **Rien ne relie ces trois traces à la PR.** Vue de GitHub : Dependabot, bump d'image, CI verte — quelqu'un la merge de bonne foi et le projet passe sur une version **Current** pendant deux mois. Trouvée seulement le 2026-08-22, au premier `git fetch` réussi après la réparation de l'authentification : tant que `fetch` échouait, la PR était **invisible en local**. ⚖️ Options : commenter la PR avec la date de levée (recommandé, elle devient auto-documentée) ; la fermer (Dependabot la recrée) ; `@dependabot ignore this major version` (trop fort — on *veut* Node 26, après le 2026-10-28). ⚠️ **La règle du projet voudrait mieux qu'une ligne ici** : « un report avec déclencheur doit être un test qui rougit quand le déclencheur survient, pas une phrase dans un registre ». Le test idoine existerait : rougir si `date >= 2026-10-28` **et** que `docker/node/Dockerfile` est encore en v24. Non écrit — c'est un choix, pas un oubli. |
| **Branche mergée qui subsiste sur le distant** | `origin/story/2-1-runtime-shell-primitives` existe encore alors que la story 2.1 est mergée (`a076a91`) et `done`. Sans gravité, mais une branche mergée qui traîne se relit comme du travail en cours. `git push origin --delete story/2-1-runtime-shell-primitives`. Idem pour `story/2-2-idempotent-install-sentinels`, qui n'a **jamais été poussée** (mergée en local) et ne vit que sur ce poste. |
| **Rector plante** | `Container::databasePath()`. Pas une régression de version : `src/rector.php:47` lie `phpstan.neon`, qui inclut l'extension Larastan, laquelle exige une app Laravel bootée. Rector est **informatif** en CI, donc non bloquant. |
| ✅ **Sémantique `/health` — DEUX définitions, chacune avec son domaine énoncé (Story 2.4)** | 🔴 **La ligne précédente contenait une affirmation FAUSSE, et elle a vécu depuis la Story 1.4** : elle disait que `<Location /health>` (Apache `mod_status`) masquait la route Laravel. **Mesuré le 2026-08-23 sur la pile réelle : c'est le JSON de Laravel qui revient** (`curl -skS https://localhost/health` → `200`, `application/json`). Le bloc `laravel.conf:111` est **inopérant sur le vhost HTTPS** ; le retirer dépasse le mandat de la 2.4 (Ask First), mais l'affirmation inverse ne doit plus être répétée. État réel : `/up` = « le framework boote » (mesuré après la revue 1 : **200 en 0,073 s, conteneur postgres réellement arrêté** — la première mesure donnait 27 s, causées par `CACHE_DRIVER`/`CACHE_STORE`, pas par `/up`) ; `/health` = « ses dépendances répondent » (`database`/`cache`/`queue`, **`503` en 3,2 s** dans le même état). La 3ᵉ définition — celle des docs/installeur qui promettaient du JSON sans sonde — n'existe plus. **Ce qui reste pour Epic 3** : décider lequel des deux devient le healthcheck des CONTENEURS (`docker-compose.yml:23` interroge encore `/up`, `:57` exécute `healthcheck.php`). |
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
