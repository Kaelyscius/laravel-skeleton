<?php

declare(strict_types=1);

use Tests\Support\RepoFile;
use Tests\Support\ShellProbe;

/*
|------------------------------------------------------------------------------
| L'entrypoint php — Story 2.4 (clôture)
|------------------------------------------------------------------------------
|
| 🔴 LE DÉFAUT QUI A ROUGI LE NIGHTLY DEUX FOIS. `docker-entrypoint.sh` décidait
| « Laravel est installé » sur `[ -f /var/www/html/artisan ]`. Or `src/artisan`
| est VERSIONNÉ dans ce dépôt et `src/vendor` ne l'est pas (`src/.gitignore:55`) :
| sur un clone neuf, la branche « installé » était donc prise SANS autoloader.
| `artisan:10` fait `require __DIR__.'/vendor/autoload.php'` sans condition, la
| commande sortait en 255, `set -e` tuait l'entrypoint, `restart: unless-stopped`
| bouclait, et `make install-dev-full` — qui a besoin de ce conteneur pour
| peupler `vendor/` — ne pouvait jamais aboutir. Runs 32654512271 et 32688766596.
|
| ⚖️ POURQUOI CE FICHIER PORTE **DEUX** FAMILLES D'ASSERTIONS.
| Les assertions TEXTUELLES (modèle `AdminPanelRateLimitTest.php:842`) disent que
| la formulation n'a pas régressé. Elles ne disent RIEN du comportement : un
| entrypoint réécrit autrement mais toujours cassé les satisferait. Les sondes
| `ShellProbe` LANCENT le script sur un arbre de bac à sable, `vendor/` absent
| puis présent, avec un `php` stubé qui JOURNALISE ses appels — c'est la seule
| famille capable de distinguer « le texte a changé » de « le comportement a
| changé », et c'est celle qui mesure « aucune commande artisan n'est jouée ».
|
| 🔴 ET L'ENVIRONNEMENT DE LA MESURE, C'EST L'INTERPRÉTEUR — PAS LA MACHINE.
| Cette phrase-ci en nommait une version FAUSSE : elle disait où Pest tourne, et
| passait sous silence le seul détail qui décide du verdict. Ces sondes
| lançaient `bash` ; le sujet porte `#!/bin/sh` et l'image est
| `php:8.5-fpm-alpine`, où `/bin/sh` est **BusyBox**. Mesuré : un
| `local -a _probe=(a b)` glissé dans `detect_laravel_state` laissait les onze
| sondes VERTES, alors que le script meurt en « syntax error » sous BusyBox —
| donc boucle de redémarrage, le défaut même que cette story corrige. C'est le
| motif de la story 2.3, reproduit dans le garde censé le clore.
|
| ⚖️ Les sondes emploient donc `ShellProbe::posixShell()`, l'interpréteur RÉEL
| de la machine — BusyBox `ash` dans le conteneur, `dash` sur un runner
| `ubuntu-latest` nu — et un test REFUSE de mesurer si ce `/bin/sh` se révélait
| être `bash`. Le nom de l'interpréteur employé est asserté, pas supposé.
| Le sujet est en outre passé à `sh -n` **et** `bash -n` : la syntaxe de tableau
| que la mutation ci-dessus introduit est rejetée par le premier, pas le second.
|
| Pour le reste : ni Docker, ni PostgreSQL, ni un vrai Laravel — `APP_ROOT` et
| `SUPERVISOR_LOG_DIR` pointent dans `/tmp`, `nc` et `php` sont stubés sur le
| `PATH`, et l'argument `true` fait rendre la main au `exec "$@"` final.
|
*/

/**
 * Fragment bash qui LANCE l'entrypoint sur un arbre de bac à sable.
 *
 * `$arbre` prépare `$bac/app` (artisan ? vendor ? autoload ?), `$env` porte les
 * affectations passées au script. La sortie est rendue en blocs balisés.
 */
function sondeEntrypoint(string $arbre, string $env): string
{
    return <<<BASH
        set -e
        bac="\$(mktemp -d)"
        # ⛔ LE BAC À SABLE DOIT ÊTRE SOUS /tmp, ET C'EST VÉRIFIÉ. Même garde que
        # les sondes d'installation : un test qui échoue est un incident, un test
        # qui salit le dépôt en échouant en est deux.
        case "\$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[\$bac]"; exit 9 ;;
        esac

        mkdir -p "\$bac/bin" "\$bac/app" "\$bac/supervisor"

        JOURNAL_PHP="\$bac/appels-php.txt"
        export JOURNAL_PHP
        : > "\$JOURNAL_PHP"

        # ⚠️ LES STUBS SONT ÉCRITS PAR `printf`, PAS PAR UN HEREDOC IMBRIQUÉ :
        # un heredoc shell à l'intérieur d'un heredoc PHP indenté impose un
        # corps en colonne 0, que PHP refuse (« Invalid body indentation »).
        #
        # `nc` stubé : l'entrypoint attend postgres et redis en TCP. Ici, ils
        # répondent tout de suite — ce n'est pas le sujet de ce fichier.
        printf '%s\\n' \\
            '#!/bin/sh' \\
            'exit 0' \\
            > "\$bac/bin/nc"

        # `php` stubé, et il JOURNALISE. C'est lui qui rend mesurable la phrase
        # « aucune commande artisan n'est jouée » : sans journal, on ne pourrait
        # qu'affirmer.
        printf '%s\\n' \\
            '#!/bin/sh' \\
            'echo "\$*" >> "\$JOURNAL_PHP"' \\
            'if [ "\$*" = "artisan --version" ]; then exit "\${PHP_BOOT_STATUS:-0}"; fi' \\
            'exit "\${PHP_CMD_STATUS:-0}"' \\
            > "\$bac/bin/php"

        chmod +x "\$bac/bin/nc" "\$bac/bin/php"
        PATH="\$bac/bin:\$PATH"
        export PATH

        {$arbre}

        statut=0
        APP_ROOT="\$bac/app" SUPERVISOR_LOG_DIR="\$bac/supervisor" \\
        BOOTABLE_MARKER="\$bac/temoin" {$env} \\
            "\$SH" "\$ENTRYPOINT" true > "\$bac/sortie" 2>&1 || statut=\$?

        echo "STATUT=\$statut"
        echo "=== SORTIE ==="
        cat "\$bac/sortie"
        echo "=== APPELS_PHP ==="
        cat "\$JOURNAL_PHP"
        echo "=== TEMOIN ==="
        cat "\$bac/temoin" 2> /dev/null || echo "(absent)"
        echo "=== FIN ==="

        rm -rf "\$bac"
        BASH;
}

/**
 * Corps d'une fonction shell, extrait par accolades équilibrées.
 *
 * ⚖️ Une regex « du nom jusqu'à la première accolade fermante en colonne 0 »
 * aurait suffi tant que le style ne change pas — c'est-à-dire jusqu'au jour où
 * il change. On compte les accolades.
 */
function corpsFonctionShell(string $source, string $nom): string
{
    $debut = strpos($source, $nom . '() {');

    if ($debut === false) {
        throw new RuntimeException("Fonction shell « {$nom} » introuvable.");
    }

    $offset = strpos($source, '{', $debut);

    if ($offset === false) {
        throw new RuntimeException("Corps de « {$nom} » introuvable.");
    }

    $profondeur = 0;
    $longueur = strlen($source);

    for ($i = $offset; $i < $longueur; $i++) {
        if ($source[$i] === '{') {
            $profondeur++;
        } elseif ($source[$i] === '}') {
            $profondeur--;

            if ($profondeur === 0) {
                return substr($source, $offset, $i - $offset + 1);
            }
        }
    }

    throw new RuntimeException("Corps de « {$nom} » non refermé.");
}

/**
 * Arbre d'une application BOOTABLE : `artisan`, `vendor/autoload.php`, `public/`.
 */
function arbreBootable(): string
{
    return <<<'ARBRE'
        touch "$bac/app/artisan"
        mkdir -p "$bac/app/vendor" "$bac/app/public"
        touch "$bac/app/vendor/autoload.php"
        ARBRE;
}

/**
 * Chemin absolu de l'entrypoint, passé à chaque sonde.
 *
 * @return array<string, string>
 */
function entrypointPhp(): array
{
    return [
        'ENTRYPOINT' => RepoFile::root() . '/docker/php/scripts/docker-entrypoint.sh',
        // ⛔ L'interpréteur du SUJET, pas celui du harnais.
        'SH' => ShellProbe::posixShell()['path'],
    ];
}

/**
 * Le témoin de démarrage relevé par la sonde, ou la chaîne vide.
 */
function temoinSonde(string $sortie): string
{
    if (preg_match('/=== TEMOIN ===\n(.*)=== FIN ===/s', $sortie, $bloc) !== 1) {
        throw new RuntimeException("Bloc TEMOIN absent de la sortie de sonde :\n" . $sortie);
    }

    return trim($bloc[1]);
}

/**
 * Code de sortie de l'entrypoint, LU sur une ligne entière.
 *
 * ⛔ PAS UN `toContain('STATUT=1')` : « STATUT=1 » est une sous-chaîne de
 * « STATUT=127 », donc un entrypoint mort sur une commande introuvable aurait
 * satisfait l'assertion écrite pour un refus délibéré.
 */
function statutSonde(string $sortie): int
{
    if (preg_match('/^STATUT=(\d+)$/m', $sortie, $trouve) !== 1) {
        throw new RuntimeException("Aucune ligne STATUT= dans la sortie de sonde :\n" . $sortie);
    }

    return (int) $trouve[1];
}

/**
 * Les appels `php` journalisés par la sonde, un par ligne.
 *
 * @return list<string>
 */
function appelsPhp(string $sortie): array
{
    if (preg_match('/=== APPELS_PHP ===\n(.*)=== TEMOIN ===/s', $sortie, $bloc) !== 1) {
        throw new RuntimeException("Bloc APPELS_PHP absent de la sortie de sonde :\n" . $sortie);
    }

    return array_values(array_filter(
        array_map('trim', explode("\n", $bloc[1])),
        static fn (string $ligne): bool => $ligne !== '',
    ));
}

// =============================================================================
// FAMILLE 1 — assertions TEXTUELLES (modèle AdminPanelRateLimitTest:842)
// =============================================================================

it('ne décide plus « Laravel est installé » sur la seule présence d’`artisan`', function (): void {
    $entrypoint = RepoFile::read('docker/php/scripts/docker-entrypoint.sh');

    // La sonde fautive, mot pour mot. Elle ne doit plus exister.
    expect($entrypoint)
        ->not->toContain('if [ -f "/var/www/html/artisan" ]; then');

    expect($entrypoint)
        ->toContain('detect_laravel_state');
});

it('ne se contente pas non plus de `vendor/autoload.php` : la bootabilité est MESURÉE', function (): void {
    // ⛔ REFUS EXPLICITE DE LA SPEC (rationale D7). Inverser la sonde vers
    // `[ -f vendor/autoload.php ]` ferait disparaître le symptôme et
    // introduirait un défaut plus coûteux : un `vendor/` PARTIEL satisfait ce
    // test, la branche production s'exécute, et `config:cache` / `route:cache`
    // FIGENT des caches construits depuis un état cassé.
    $entrypoint = RepoFile::read('docker/php/scripts/docker-entrypoint.sh');

    expect($entrypoint)
        ->toContain('artisan --version');
    expect($entrypoint)
        ->toContain('non-bootable');
});

it('garde `proxies:check` fatal, et hors du bloc production', function (): void {
    // Reprise du modèle d'`AdminPanelRateLimitTest.php:842` — la restructuration
    // en `case` ne doit pas avoir déplacé ce contrôle dans le `if production`.
    $entrypoint = RepoFile::read('docker/php/scripts/docker-entrypoint.sh');

    expect($entrypoint)
        ->toContain('php artisan proxies:check || exit 1');

    $garde = strpos($entrypoint, 'php artisan proxies:check');
    $production = strpos($entrypoint, 'if [ "$APP_ENV" = "production" ]');
    $cache = strpos($entrypoint, 'php artisan config:cache');

    // ⛔ L'ABSENCE EST DITE AVANT LA COMPARAISON. `strpos` rend `false`, que PHP
    // compare comme 0 : sans ces trois assertions, un `config:cache` SUPPRIMÉ
    // aurait rendu `0` et satisfait « le contrôle vient avant ».
    expect($garde)
        ->not->toBeFalse();
    expect($production)
        ->not->toBeFalse();
    expect($cache)
        ->not->toBeFalse();

    expect((int) $garde)
        ->toBeLessThan((int) $production, '`proxies:check` est tombé DANS le bloc production.');
    expect((int) $garde)
        ->toBeLessThan((int) $cache, '`proxies:check` contrôlerait une configuration déjà figée.');
});

// =============================================================================
// FAMILLE 2 — sondes de COMPORTEMENT (ShellProbe, bac à sable sous /tmp)
// =============================================================================

it('`LARAVEL_ENTRYPOINT_SOURCE_ONLY` n’est posée NULLE PART en configuration', function (): void {
    /*
     * ⛔ C'EST UN COUPE-CIRCUIT, ET IL ÉTAIT NON GARDÉ. Posée dans un
     * `docker-compose*.yml`, un `.env` ou le Dockerfile, cette variable fait
     * sortir l'entrypoint en 0 AVANT `exec "$@"` : php-fpm ne démarre jamais, le
     * conteneur s'arrête « proprement », et rien ne dit pourquoi.
     *
     * 🔴 Le commentaire de l'entrypoint affirme « en exécution réelle elle est
     * absente ». C'était une phrase sans test derrière — exactement le motif de
     * tête de ce projet, dans la porte ouverte pour le tester.
     */
    $surfaces = array_merge(
        glob(RepoFile::root() . '/docker-compose*.yml') ?: [],
        [
            RepoFile::root() . '/docker/php/Dockerfile',
            RepoFile::root() . '/.env.example',
            RepoFile::root() . '/src/.env.example',
            // ⛔ ET LES GÉNÉRATEURS, PAS SEULEMENT LES FICHIERS (2ᵉ revue).
            // `interactive-setup.sh` ÉCRIT `.env` et
            // `docker-compose.override.yml` : garder les fichiers produits sans
            // garder ce qui les produit laisse la variable rentrer par la porte
            // de service, et l'override n'est même pas versionné.
            RepoFile::root() . '/scripts/setup/interactive-setup.sh',
        ],
    );

    $examinees = 0;
    $coupables = [];

    foreach ($surfaces as $chemin) {
        if (! is_file($chemin)) {
            continue;
        }

        $examinees++;
        $contenu = (string) file_get_contents($chemin);

        if (str_contains($contenu, 'LARAVEL_ENTRYPOINT_SOURCE_ONLY')) {
            $coupables[] = basename($chemin);
        }
    }

    // Anti-vacuité : les surfaces existent bel et bien. Sans ce compte, un
    // renommage de fichier rendrait ce garde vert en n'examinant rien.
    expect($examinees)
        ->toBeGreaterThanOrEqual(4);

    expect($coupables)
        ->toBe([], 'Coupe-circuit de sonde posé en configuration : php-fpm ne démarrera pas.');
});

it('mesure sous l’interpréteur RÉEL du sujet, et REFUSE de mesurer sous bash', function (): void {
    /*
     * 🔴 LE GARDE MESURAIT LE MAUVAIS INTERPRÉTEUR, ET C'EST DÉMONTRÉ.
     * `local -a _probe=(a b)` glissé dans `detect_laravel_state` laissait les
     * onze sondes VERTES sous `bash`. Sous le `sh` de l'image
     * (`php:8.5-fpm-alpine` → `/bin/sh -> /bin/busybox`), le script meurt en
     * « syntax error » avant d'imprimer quoi que ce soit : conteneur en boucle
     * de redémarrage, c'est-à-dire le défaut EXACT que cette story corrige.
     *
     * ⛔ CE TEST-CI EST LE PRÉALABLE DE TOUS LES AUTRES. S'il passait sous un
     * `/bin/sh` qui est en réalité `bash`, chaque sonde de ce fichier mesurerait
     * autre chose que ce qu'elle croit — sans que rien ne le dise.
     */
    $shell = ShellProbe::posixShell();

    expect($shell['name'])
        ->not->toBe('bash', 'Ce /bin/sh est bash : les sondes mesureraient une syntaxe que le sujet n’a pas le droit d’employer.');
    expect($shell['name'])
        ->not->toBe('introuvable', 'Aucun /bin/sh sur cette machine : les sondes ne peuvent pas mesurer le sujet.');

    // Le nom est ASSERTÉ, pas supposé : BusyBox dans le conteneur, dash sur un
    // runner nu. Toute autre valeur est un environnement qu'on n'a pas prévu et
    // dont on ne sait donc rien.
    expect(['busybox', 'dash', 'ash'])
        ->toContain($shell['name']);
});

it('le sujet parse sous `sh` autant que sous `bash`', function (): void {
    // ⚖️ LES DEUX, ET DANS CET ORDRE D'IMPORTANCE. `bash -n` accepte les
    // tableaux, `x=(a b)` compris ; `sh -n` les REJETTE. C'est cette asymétrie
    // qui a laissé passer la mutation, et c'est elle qu'on retourne en garde.
    $entrypoint = escapeshellarg(RepoFile::root() . '/docker/php/scripts/docker-entrypoint.sh');
    $sh = escapeshellarg(ShellProbe::posixShell()['path']);

    foreach ([
        $sh => 'sh',
        'bash' => 'bash',
    ] as $binaire => $nom) {
        $sortie = [];
        $statut = 0;
        exec(sprintf('%s -n %s 2>&1', $binaire === 'bash' ? 'bash' : $binaire, $entrypoint), $sortie, $statut);

        expect($statut)
            ->toBe(0, "L’entrypoint ne parse pas sous « {$nom} » : " . implode(' ', $sortie));
    }
});

it('distingue les CINQ états sur un arbre RÉEL, pas sur une lecture', function (): void {
    $result = ShellProbe::run(<<<'BASH'
        set -e
        bac="$(mktemp -d)"
        case "$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;;
        esac

        # ⛔ `.` ET NON `source` : `source` est un bashisme, et ce fragment
        # tourne sous l'interpréteur du SUJET.
        LARAVEL_ENTRYPOINT_SOURCE_ONLY=true
        export LARAVEL_ENTRYPOINT_SOURCE_ONLY
        . "$ENTRYPOINT"

        mkdir -p "$bac/app" "$bac/bin"

        echo "SANS_ARTISAN=$(detect_laravel_state "$bac/app")"

        touch "$bac/app/artisan"
        echo "SANS_VENDOR=$(detect_laravel_state "$bac/app")"

        mkdir -p "$bac/app/vendor"
        touch "$bac/app/vendor/autoload.php"

        printf '#!/bin/sh\nexit 255\n' > "$bac/bin/php-casse"
        printf '#!/bin/sh\necho "Laravel Framework 13.0.0"\n' > "$bac/bin/php-sain"
        printf '#!/bin/sh\nsleep 30\n' > "$bac/bin/php-muet"
        chmod +x "$bac/bin/php-casse" "$bac/bin/php-sain" "$bac/bin/php-muet"

        PHP_BIN="$bac/bin/php-casse"; export PHP_BIN
        echo "VENDOR_PARTIEL=$(detect_laravel_state "$bac/app")"

        # ⛔ LA SONDE EST BORNÉE : un php qui ne rend JAMAIS la main doit
        # produire un état, pas un entrypoint figé. Borne ramenée à 1 s.
        PHP_BIN="$bac/bin/php-muet"; export PHP_BIN
        BOOT_PROBE_TIMEOUT=1; export BOOT_PROBE_TIMEOUT
        echo "MUET=$(detect_laravel_state "$bac/app")"

        BOOT_PROBE_TIMEOUT=15; export BOOT_PROBE_TIMEOUT
        PHP_BIN="$bac/bin/php-sain"; export PHP_BIN
        echo "BOOTABLE=$(detect_laravel_state "$bac/app")"

        rm -rf "$bac"
        BASH
        , entrypointPhp(), 60, ShellProbe::posixShell()['path']);

    expect($result['output'])->toContain('SANS_ARTISAN=absent');
    expect($result['output'])->toContain('SANS_VENDOR=sans-vendor');
    expect($result['output'])->toContain('VENDOR_PARTIEL=non-bootable');
    expect($result['output'])->toContain('MUET=non-bootable-timeout');
    expect($result['output'])->toContain('BOOTABLE=bootable');

    // ⛔ ANTI-VACUITÉ DU SOURCING : la garde `SOURCE_ONLY` ne doit charger QUE
    // les définitions. Si le corps impératif s'exécutait, la bannière de
    // démarrage apparaîtrait — et la sonde attendrait postgres.
    expect($result['output'])->not->toContain('Démarrage du container PHP');
    expect($result['status'])->toBe(0);
});

it('n’ARRACHE PAS l’arbre à l’hôte : seuls `storage/` et `bootstrap/cache/` changent de main', function (): void {
    /*
     * 🔴 CE GARDE EXISTE PARCE QUE LE PREMIER NIGHTLY RÉELLEMENT ABOUTI EST MORT
     * ICI (run 32742873104, runner GitHub nu). L'entrypoint faisait
     * `find "$APP_ROOT" -not -user www-data … -exec chown www-data:www-data {} +`
     * — il confisquait TOUT l'arbre vers l'uid de `www-data`, soit **1000** dans
     * cette image. Or `scripts/install-lockfile.sh` tourne SUR L'HÔTE, et l'hôte
     * d'un runner GitHub est **1001** : son `mktemp` dans
     * `src/.install-state/`, devenu propriété de 1000, était refusé. Onze
     * modules réussis, Laravel installé, et l'installation mourait à sa
     * dernière étape.
     *
     * ⛔ ET RIEN NE POUVAIT L'ATTRAPER, POUR LA RAISON HABITUELLE : sur la
     * machine de développement (WSL2) l'hôte EST uid 1000, exactement
     * `www-data`. Le conflit n'y existe pas. Sixième fois dans cet epic que
     * l'environnement de mesure décide du verdict — après BusyBox/GNU,
     * bash/ash, `timeout` 124/143, `jq` absent et un relecteur en root. Cette
     * fois : **1000 contre 1001**.
     *
     * ⚖️ CE QUE CETTE SONDE MESURE, EXACTEMENT — et ce qu'elle ne mesure pas.
     * Elle stube `chown` sur le `PATH` et ENREGISTRE chaque appel, puis applique
     * ces appels à un modèle de propriété dont l'uid de départ est **1001**,
     * délibérément DIFFÉRENT de celui de `www-data`. C'est l'uid qui est
     * ÉPINGLÉ, au lieu d'être hérité de la machine qui lance le test.
     * ⚠️ Elle ne relit pas la propriété réelle des inodes, et c'est dit plutôt
     * que sous-entendu : les tests tournent en uid 1000 — donc `chown`
     * vers `www-data` y serait un no-op indiscernable — et un second uid
     * exigerait des privilèges (mesuré le 2026-08-24 : `unshare -Ur` rend
     * « Operation not permitted » dans ce conteneur). Le modèle est donc la
     * mesure la plus fidèle disponible, et il porte sur ce qui décide vraiment :
     * QUELS CHEMINS l'entrypoint demande à changer de main.
     */
    $result = ShellProbe::run(<<<'BASH'
        set -e
        bac="$(mktemp -d)"
        case "$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;;
        esac

        mkdir -p "$bac/bin" "$bac/supervisor"
        mkdir -p "$bac/app/storage/logs" "$bac/app/bootstrap/cache" \
                 "$bac/app/.install-state" "$bac/app/config" "$bac/app/public"
        touch "$bac/app/artisan" "$bac/app/composer.json" "$bac/app/.env" \
              "$bac/app/.install-state/lock.yml" "$bac/app/config/app.php"

        JOURNAL_CHOWN="$bac/chown.txt"; export JOURNAL_CHOWN
        JOURNAL_FIND="$bac/find.txt"; export JOURNAL_FIND
        : > "$JOURNAL_CHOWN"
        : > "$JOURNAL_FIND"

        # `chown` ET `find` sont stubés, et TOUS DEUX enregistrent.
        # 🔴 STUBER `chown` SEUL NE SUFFISAIT PAS, et la mutation l'a prouvé :
        # le défaut passait par `find … -not -user www-data -exec chown …`, dont
        # le PRÉDICAT est évalué contre les inodes réels. Les tests tournant en
        # uid 1000 — c'est-à-dire `www-data` — le filtre ne matchait RIEN, `find`
        # n'appelait jamais `chown`, et la sonde restait verte sur le défaut
        # exact qu'elle existe pour attraper. C'était l'uid de la machine qui
        # décidait, dans le garde écrit contre ce travers.
        printf '%s\n' \
            '#!/bin/sh' \
            'echo "$*" >> "$JOURNAL_CHOWN"' \
            'exit 0' \
            > "$bac/bin/chown"
        printf '%s\n' \
            '#!/bin/sh' \
            'echo "$*" >> "$JOURNAL_FIND"' \
            'exit 0' \
            > "$bac/bin/find"
        printf '%s\n' '#!/bin/sh' 'exit 0' > "$bac/bin/nc"
        printf '%s\n' '#!/bin/sh' 'exit 0' > "$bac/bin/php"
        chmod +x "$bac/bin/chown" "$bac/bin/find" "$bac/bin/nc" "$bac/bin/php"

        PATH="$bac/bin:$PATH"; export PATH

        statut=0
        APP_ROOT="$bac/app" SUPERVISOR_LOG_DIR="$bac/supervisor" \
        BOOTABLE_MARKER="$bac/temoin" APP_ENV=local \
            "$SH" "$ENTRYPOINT" true > "$bac/sortie" 2>&1 || statut=$?

        echo "STATUT=$statut"
        echo "RACINE=$bac/app"
        echo "=== CHOWNS ==="
        sed "s|$bac/app|<APP>|g" "$JOURNAL_CHOWN"
        echo "=== FINDS ==="
        sed "s|$bac/app|<APP>|g" "$JOURNAL_FIND"
        echo "=== FIN ==="

        rm -rf "$bac"
        BASH
        , entrypointPhp(), 60, ShellProbe::posixShell()['path']);

    expect($result['output'])
        ->toContain('STATUT=0');

    if (preg_match('/=== CHOWNS ===\n(.*)=== FINDS ===\n(.*)=== FIN ===/s', $result['output'], $bloc) !== 1) {
        throw new RuntimeException("Blocs CHOWNS/FINDS absents :\n" . $result['output']);
    }

    $lignes = static fn (string $brut): array => array_values(array_filter(
        array_map('trim', explode("\n", $brut)),
        static fn (string $l): bool => $l !== '',
    ));

    $appels = $lignes($bloc[1]);

    /*
     * ⛔ UN `find … -exec chown …` EST UNE SAISIE RÉCURSIVE, et c'est ainsi
     * qu'il est modélisé — sous la PRÉMISSE ÉPINGLÉE que l'hôte n'est pas
     * `www-data`. C'est précisément la prémisse du runner (1001 contre 1000),
     * et sous elle le filtre `-not -user www-data` matche TOUT l'arbre.
     */
    foreach ($lignes($bloc[2]) as $find) {
        if (! str_contains($find, 'chown')) {
            continue;
        }

        $mots = preg_split('/\s+/', $find) ?: [];

        foreach ($mots as $mot) {
            if (str_starts_with($mot, '<APP>')) {
                $appels[] = '-R www-data:www-data ' . $mot;

                break;
            }
        }
    }

    // Anti-vacuité : l'entrypoint ajuste bien QUELQUE CHOSE. Un stub jamais
    // appelé rendrait tout le reste vrai pour la pire des raisons.
    expect($appels)
        ->not->toBe([], 'Aucun `chown` : la sonde ne mesure rien.');

    /*
     * ⛔ LE MODÈLE DE PROPRIÉTÉ, AVEC UN UID DE DÉPART ÉPINGLÉ À 1001.
     * On applique les appels enregistrés, puis on regarde qui possède quoi.
     */
    $possesseur = [
        '<APP>' => '1001',
        '<APP>/artisan' => '1001',
        '<APP>/composer.json' => '1001',
        '<APP>/.env' => '1001',
        '<APP>/config/app.php' => '1001',
        '<APP>/.install-state' => '1001',
        '<APP>/.install-state/lock.yml' => '1001',
        '<APP>/storage' => '1001',
        '<APP>/storage/logs' => '1001',
        '<APP>/bootstrap/cache' => '1001',
    ];

    foreach ($appels as $appel) {
        $mots = preg_split('/\s+/', $appel) ?: [];
        $cibles = array_values(array_filter(
            $mots,
            static fn (string $m): bool => str_starts_with($m, '<APP>'),
        ));

        foreach ($cibles as $cible) {
            foreach (array_keys($possesseur) as $chemin) {
                if ($chemin === $cible || str_starts_with($chemin, $cible . '/')) {
                    $possesseur[$chemin] = 'www-data(1000)';
                }
            }
        }
    }

    // ⛔ CE QUI DOIT RESTER À L'HÔTE. `.install-state/` est le chemin exact qui
    // a tué le nightly : `install-lockfile.sh` y écrit DEPUIS L'HÔTE.
    foreach ([
        '<APP>',
        '<APP>/artisan',
        '<APP>/composer.json',
        '<APP>/.env',
        '<APP>/config/app.php',
        '<APP>/.install-state',
        '<APP>/.install-state/lock.yml',
    ] as $chemin) {
        expect($possesseur[$chemin])
            ->toBe('1001', "L’entrypoint arrache « {$chemin} » à l’hôte : `install-lockfile.sh` y écrira depuis l’hôte et sera REFUSÉ.");
    }

    // …et ce qui doit bien changer de main, sinon le conteneur ne peut plus
    // écrire ses journaux ni ses caches : anti-vacuité de l'assertion inverse.
    foreach (['<APP>/storage', '<APP>/storage/logs', '<APP>/bootstrap/cache'] as $chemin) {
        expect($possesseur[$chemin])
            ->toBe('www-data(1000)', "« {$chemin} » n’est plus ajusté : le conteneur ne pourra pas y écrire.");
    }
});

it('reconnaît le dépassement SOUS LES DEUX `timeout`, GNU comme BusyBox', function (): void {
    /*
     * 🔴 LE BRAS `143` N'ÉTAIT ÉPROUVÉ NULLE PART OÙ LA CI MESURE.
     * Le test voisin déclenche un VRAI dépassement, donc le code rendu est
     * celui du `timeout` DE LA MACHINE : 124 sur un runner GNU, 143 sous le
     * BusyBox de l'image. La CI lance Pest sur le runner nu — supprimer
     * `|| [ "$statut" -eq 143 ]` y restait donc VERT, alors que 143 est le code
     * de la PRODUCTION. L'interpréteur était épinglé ; le BINAIRE ne l'était
     * pas.
     *
     * ⚖️ ON ÉPINGLE DONC LE BINAIRE, comme `pinnedEnvironment()` épingle les
     * variables : un `timeout` stubé sur le PATH rend le code voulu, et les
     * DEUX bras sont exercés quelle que soit la machine.
     */
    foreach ([
        '124' => 'GNU coreutils',
        '143' => 'BusyBox (128 + SIGTERM)',
    ] as $code => $origine) {
        $result = ShellProbe::run(<<<BASH
            set -e
            bac="\$(mktemp -d)"
            case "\$bac" in
                /tmp/*) ;;
                *) echo "BAC_HORS_TMP=[\$bac]"; exit 9 ;;
            esac

            mkdir -p "\$bac/app/vendor" "\$bac/bin"
            touch "\$bac/app/artisan" "\$bac/app/vendor/autoload.php"

            # ⛔ LE BINAIRE `timeout` EST ÉPINGLÉ, PAS SUBI.
            printf '%s\\n' \\
                '#!/bin/sh' \\
                'exit {$code}' \\
                > "\$bac/bin/timeout"
            printf '%s\\n' '#!/bin/sh' 'exit 0' > "\$bac/bin/php"
            chmod +x "\$bac/bin/timeout" "\$bac/bin/php"

            PATH="\$bac/bin:\$PATH"; export PATH
            LARAVEL_ENTRYPOINT_SOURCE_ONLY=true; export LARAVEL_ENTRYPOINT_SOURCE_ONLY
            . "\$ENTRYPOINT"

            echo "ETAT={$code}=\$(detect_laravel_state "\$bac/app")"

            rm -rf "\$bac"
            BASH
            , entrypointPhp(), 60, ShellProbe::posixShell()['path']);

        // ⚠️ `toContain` prend des AIGUILLES, pas un message (cinquième
        // rencontre de ce piège) : le message passe par `toBeTrue`.
        expect(str_contains($result['output'], "ETAT={$code}=non-bootable-timeout"))
            ->toBeTrue("Le code de dépassement {$code} ({$origine}) n’est pas reconnu comme un dépassement.");
    }
});

it('un `timeout` STUBÉ n’est pas un test vide : un code ordinaire reste `non-bootable`', function (): void {
    // ⛔ ANTI-VACUITÉ DU TEST PRÉCÉDENT : si la sonde rendait
    // `non-bootable-timeout` pour TOUT code non nul, les deux bras seraient
    // « verts » sans rien distinguer — et le rapport dirait « ça n’a jamais
    // répondu » sur une application qui a répondu, en erreur.
    $result = ShellProbe::run(<<<'BASH'
        set -e
        bac="$(mktemp -d)"
        case "$bac" in
            /tmp/*) ;;
            *) echo "BAC_HORS_TMP=[$bac]"; exit 9 ;;
        esac

        mkdir -p "$bac/app/vendor" "$bac/bin"
        touch "$bac/app/artisan" "$bac/app/vendor/autoload.php"

        printf '%s\n' '#!/bin/sh' 'exit 255' > "$bac/bin/timeout"
        printf '%s\n' '#!/bin/sh' 'exit 0' > "$bac/bin/php"
        chmod +x "$bac/bin/timeout" "$bac/bin/php"

        PATH="$bac/bin:$PATH"; export PATH
        LARAVEL_ENTRYPOINT_SOURCE_ONLY=true; export LARAVEL_ENTRYPOINT_SOURCE_ONLY
        . "$ENTRYPOINT"

        echo "ETAT=$(detect_laravel_state "$bac/app")"

        rm -rf "$bac"
        BASH
        , entrypointPhp(), 60, ShellProbe::posixShell()['path']);

    expect($result['output'])->toContain('ETAT=non-bootable');
    expect($result['output'])->not->toContain('ETAT=non-bootable-timeout');
});

it('le compte d’états ne peut plus DÉRIVER entre la sonde, le `case` et la prose', function (): void {
    /*
     * 🔴 QUATRE ÉCRITS DU MÊME COMMIT DISAIENT QUATRE CHOSES : « trois états
     * plus un refus », « TROIS ÉTATS et un quatrième », un test nommé « les
     * QUATRE états », et un `case` à cinq branches. Aucun n'était gardé.
     * Le compte est désormais DÉRIVÉ du code : la liste des états que la sonde
     * peut émettre, celle que le `case` traite, et celle que l'en-tête énumère
     * doivent coïncider — sinon ce test rougit, quel que soit le nombre.
     */
    $entrypoint = RepoFile::read('docker/php/scripts/docker-entrypoint.sh');

    $corpsSonde = corpsFonctionShell($entrypoint, 'detect_laravel_state');

    preg_match_all('/^\s*echo "([a-z-]+)"$/m', $corpsSonde, $emis);
    $etatsEmis = array_values(array_unique($emis[1]));
    sort($etatsEmis);

    // Anti-vacuité : la sonde émet bien des états.
    expect(count($etatsEmis))
        ->toBeGreaterThanOrEqual(3);

    // Ceux que le `case` traite, `*)` exclu (c'est le refus d'un état INCONNU).
    preg_match('/case "\$ETAT_LARAVEL" in\n(.*?)\nesac/s', $entrypoint, $bloc);
    expect($bloc)
        ->not->toBe([], 'Le `case` sur l’état a disparu de l’entrypoint.');

    preg_match_all('/^\s([a-z|-]+)\)$/m', $bloc[1] ?? '', $branches);
    $etatsTraites = [];

    foreach ($branches[1] as $branche) {
        foreach (explode('|', $branche) as $etat) {
            $etatsTraites[] = $etat;
        }
    }

    $etatsTraites = array_values(array_unique($etatsTraites));
    sort($etatsTraites);

    expect($etatsTraites)
        ->toBe($etatsEmis, 'Le `case` ne traite pas exactement les états que la sonde peut émettre.');

    /*
     * …et l'en-tête les ÉNUMÈRE tous, sans en inventer.
     *
     * ⚠️ `toContain` prend des AIGUILLES, pas un message : un second argument y
     * devient une seconde aiguille recherchée. Le message passe donc par
     * `toBeTrue`. Ce piège a coûté trois allers-retours dans cette story ; il
     * est écrit ici pour qu'il n'en coûte pas un quatrième.
     */
    /*
     * 🔴 CETTE BOUCLE ÉTAIT SATISFIABLE PAR PRÉFIXE (2ᵉ revue). Un
     * `str_contains('#   non-bootable')` matche encore la ligne de
     * `non-bootable-timeout` : supprimer la documentation de `non-bootable`
     * restait VERT. Tout état dont le nom préfixe un autre pouvait disparaître
     * de l'en-tête en silence. La correspondance est désormais ANCRÉE sur la
     * ligne, avec le tiret cadratin qui suit le nom.
     */
    foreach ($etatsEmis as $etat) {
        $motif = '/^#\s+' . preg_quote($etat, '/') . '\s+—/m';

        expect(preg_match($motif, $entrypoint))
            ->toBe(1, "L’état « {$etat} » n’est pas documenté SUR SA PROPRE LIGNE dans l’en-tête.");
    }

    // Le compte est écrit UNE fois, en toutes lettres, et il est vérifié.
    $compte = [
        '3' => 'TROIS',
        '4' => 'QUATRE',
        '5' => 'CINQ',
        '6' => 'SIX',
    ][(string) count($etatsEmis)] ?? null;

    expect($compte)
        ->not->toBeNull();
    expect(str_contains($entrypoint, $compte . ' ÉTATS'))
        ->toBeTrue("L’en-tête n’annonce pas « {$compte} ÉTATS ».");

    /*
     * ⛔ ET LA PROSE DU JOURNAL COMPTE AUSSI. `docs/ETAT.md` annonçait « sonde à
     * CINQ états » sans que rien ne le garde : un sixième état aurait fait
     * rougir l'entrypoint pendant que le document aurait continué de dire
     * cinq. Le document qui raconte la correction d'un compte qui dérive ne
     * peut pas faire dériver le sien.
     */
    expect(str_contains(RepoFile::read('docs/ETAT.md'), $compte . ' états'))
        ->toBeTrue("docs/ETAT.md n’annonce pas « {$compte} états » pour la sonde de l’entrypoint.");
});

it('CLONE NEUF en dev : démarre, journalise l’état, et ne joue AUCUNE commande artisan', function (): void {
    // C'est l'AC de tête : sur un clone neuf, `vendor/` est absent et le
    // conteneur doit VIVRE, sans quoi `make install-laravel` — qui s'exécute
    // DANS ce conteneur — n'a pas d'hôte où tourner.
    $result = ShellProbe::run(sondeEntrypoint(
        'touch "$bac/app/artisan"',
        'APP_ENV=local',
    ), entrypointPhp(), 60, ShellProbe::posixShell()['path']);

    expect(statutSonde($result['output']))->toBe(0);
    expect($result['output'])->toContain('État de l\'application détecté : sans-vendor');
    expect($result['output'])->toContain('Dépendances non installées');

    // ⛔ MESURÉ, PAS AFFIRMÉ : le stub `php` journalise chacun de ses appels.
    expect(appelsPhp($result['output']))
        ->toBe([]);
});

it('CLONE NEUF avec APP_ENV vide : REFUS explicite, et la variable est NOMMÉE', function (): void {
    // Repli `make up` sans `-f` : `docker-compose.override.yml` n'est pas
    // versionné, donc `APP_ENV` n'est pas posé. `proxies:check` ne peut pas
    // s'exécuter sans `vendor/`, et démarrer sans lui rouvrirait le trou fermé
    // le 2026-08-20.
    $result = ShellProbe::run(sondeEntrypoint(
        'touch "$bac/app/artisan"',
        'APP_ENV=',
    ), entrypointPhp(), 60, ShellProbe::posixShell()['path']);

    expect(statutSonde($result['output']))->toBe(1);
    expect($result['output'])->toContain('APP_ENV');
    expect($result['output'])->toContain('proxies:check');
    expect(appelsPhp($result['output']))
        ->toBe([]);
});

it('CLONE NEUF en production : REFUS, jamais un démarrage silencieux', function (): void {
    $result = ShellProbe::run(sondeEntrypoint(
        'touch "$bac/app/artisan"',
        'APP_ENV=production',
    ), entrypointPhp(), 60, ShellProbe::posixShell()['path']);

    expect(statutSonde($result['output']))->toBe(1);
    expect(appelsPhp($result['output']))
        ->toBe([]);
});

it('`vendor/` PARTIEL en production : aucun cache n’est construit depuis un état cassé', function (): void {
    // 🔴 C'EST LE DÉFAUT QU'UNE SONDE `[ -f vendor/autoload.php ]` AURAIT
    // INTRODUIT. L'autoloader est là, l'application ne boote pas : la branche
    // production aurait figé `config:cache` et `route:cache` — la décision D7
    // existe exactement pour l'empêcher.
    $arbre = <<<'ARBRE'
        touch "$bac/app/artisan"
        mkdir -p "$bac/app/vendor"
        touch "$bac/app/vendor/autoload.php"
        ARBRE;

    $result = ShellProbe::run(
        sondeEntrypoint($arbre, 'APP_ENV=production PHP_BOOT_STATUS=255'),
        entrypointPhp(),
        60,
        ShellProbe::posixShell()['path'],
    );

    expect(statutSonde($result['output']))->toBe(1);
    expect($result['output'])->toContain('non-bootable');

    $appels = appelsPhp($result['output']);

    // La SEULE commande jouée est la sonde de bootabilité elle-même.
    expect($appels)
        ->toBe(['artisan --version']);
});

it('`vendor/` PARTIEL en DEV : le conteneur reste RÉPARABLE, sans jouer d’artisan', function (): void {
    /*
     * 🔴 CE CAS N'AVAIT AUCUNE SONDE, ET IL ÉTAIT TRAITÉ COMME LA PRODUCTION.
     * `sans-vendor` avait reçu le traitement « en dev, on démarre quand même »
     * pour une raison précise : `make install-laravel` s'exécute DANS ce
     * conteneur. `non-bootable` — un `composer install` interrompu, autoloader
     * présent, dépendances incomplètes — est le même problème avec un pas de
     * plus, et il tuait le conteneur : `restart: unless-stopped` le bouclait, et
     * la seule réparation documentée n'avait plus d'hôte. La poule et l'œuf,
     * reconduits un cran plus bas.
     *
     * ⚖️ ET LA FATALITÉ HORS DEV NE BOUGE PAS : le test suivant l'exige encore.
     */
    $arbre = <<<'ARBRE'
        touch "$bac/app/artisan"
        mkdir -p "$bac/app/vendor"
        touch "$bac/app/vendor/autoload.php"
        ARBRE;

    foreach (['local', 'testing'] as $environnement) {
        $result = ShellProbe::run(
            sondeEntrypoint($arbre, "APP_ENV={$environnement} PHP_BOOT_STATUS=255"),
            entrypointPhp(),
            60,
            ShellProbe::posixShell()['path'],
        );

        expect(statutSonde($result['output']))
            ->toBe(0, "APP_ENV={$environnement} : un vendor/ partiel tue le conteneur, donc la réparation n’a plus d’hôte.");

        expect($result['output'])
            ->toContain('non-bootable');

        // ⛔ AUCUNE COMMANDE ARTISAN AU-DELÀ DE LA SONDE ELLE-MÊME : sur une
        // application qui ne boote pas, toute commande sort en erreur et
        // `set -e` tuerait le conteneur qu'on vient de décider de garder.
        expect(appelsPhp($result['output']))
            ->toBe(['artisan --version']);

        // Le témoin de la branche `bootable` ne doit PAS avoir été écrit.
        expect($result['output'])
            ->toContain('(absent)');
    }
});

it('`vendor/` PARTIEL hors dev reste FATAL — la tolérance s’arrête au développement', function (): void {
    $arbre = <<<'ARBRE'
        touch "$bac/app/artisan"
        mkdir -p "$bac/app/vendor"
        touch "$bac/app/vendor/autoload.php"
        ARBRE;

    foreach (['production', 'staging', ''] as $environnement) {
        $result = ShellProbe::run(
            sondeEntrypoint($arbre, "APP_ENV={$environnement} PHP_BOOT_STATUS=255"),
            entrypointPhp(),
            60,
            ShellProbe::posixShell()['path'],
        );

        expect(statutSonde($result['output']))
            ->toBe(1, "APP_ENV=« {$environnement} » : une application non bootable démarre quand même.");
    }
});

it('APPLICATION BOOTABLE en dev : les purges de cache sont jouées, et le conteneur vit', function (): void {
    $result = ShellProbe::run(
        sondeEntrypoint(arbreBootable(), 'APP_ENV=local'),
        entrypointPhp(),
        60,
        ShellProbe::posixShell()['path'],
    );

    expect(statutSonde($result['output']))->toBe(0);

    $appels = appelsPhp($result['output']);

    expect($appels)
        ->toContain('artisan config:clear');
    expect($appels)
        ->toContain('artisan route:clear');
    expect($appels)
        ->toContain('artisan view:clear');
    expect($appels)
        ->toContain('artisan event:clear');

    /*
     * ⛔ LE TÉMOIN EST ÉCRIT, ET C'EST CE QUE `make post-install-restart-php`
     * ATTEND. Personne ne l'assertait (relevé en rejouant la mutation « le
     * témoin repart en fin de branche » : elle restait VERTE). Un témoin jamais
     * écrit ferait expirer la cible sur une installation pourtant saine.
     */
    expect($result['output'])
        ->not->toContain('(absent)');
    expect(temoinSonde($result['output']))
        ->toMatch('/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z \S+$/');

    /*
     * 🔴 ET `storage:link` — LA MOITIÉ QUI MANQUAIT (audit de clôture).
     * `php artisan storage:link` n'existe qu'à UN SEUL endroit du dépôt : cette
     * branche. Aucun module d'installation ne le joue. Tant que l'entrypoint ne
     * repassait pas ici après `install-laravel`, une install de clone neuf ne
     * créait JAMAIS `public/storage` — et comme `/health` ne le regarde pas, le
     * nightly pouvait conclure VERT sur une application incomplète.
     * C'est CE geste que `make post-install-restart-php` va chercher en
     * redémarrant le conteneur ; le redémarrage lui-même est mesuré dans
     * `InstallSentinelsTest`, et le lien y est la POST-CONDITION attendue.
     */
    expect($appels)
        ->toContain('artisan storage:link');

    // ⚖️ En `local`, le contrôle de déploiement ne s'exécute PAS — c'est la
    // décision du 2026-08-20 : « un opérateur bricole et n'a pas à être arrêté ».
    expect($appels)
        ->not->toContain('artisan proxies:check');
});

it('le témoin n’est PAS écrit quand l’entrypoint meurt AVANT de passer la main', function (): void {
    /*
     * 🔴 LE TÉMOIN VIVAIT EN FIN DE BRANCHE `bootable`, PAS EN FIN DE SCRIPT
     * (2ᵉ revue). Entre les deux : `mkdir -p "$SUPERVISOR_LOG_DIR"`, FATAL sous
     * `set -e`, puis le `exec` lui-même. Un échec là laissait
     * `make post-install-restart-php` VERT sur un conteneur qui meurt aussitôt :
     * la cible attestait d'un démarrage qui n'a jamais servi.
     *
     * ⚖️ On rend `mkdir` impossible pour atteindre ce chemin. Ce que le témoin
     * dit désormais, exactement : « bootable ET l'entrypoint est allé jusqu'à
     * passer la main ».
     */
    $result = ShellProbe::run(
        sondeEntrypoint(arbreBootable(), 'APP_ENV=local SUPERVISOR_LOG_DIR=/proc/impossible/supervisor'),
        entrypointPhp(),
        60,
        ShellProbe::posixShell()['path'],
    );

    expect(statutSonde($result['output']))
        ->not->toBe(0, 'L’entrypoint survit à un `mkdir` fatal : le test ne mesure pas ce qu’il croit.');

    // ⛔ ET LE TÉMOIN N'EST PAS LÀ. C'est toute la question.
    expect(temoinSonde($result['output']))
        ->toBe('(absent)', 'Le témoin atteste d’un démarrage qui n’est jamais allé jusqu’à `exec`.');
});

it('`public/storage` en répertoire RÉEL ne tue PAS le conteneur', function (): void {
    /*
     * 🔴 `[ ! -L … ]` EST VRAI POUR UN VRAI RÉPERTOIRE. `storage:link` échouait
     * alors (« The "public/storage" directory already exists »), `set -e` tuait
     * l'entrypoint, et `restart: unless-stopped` bouclait — sur un dossier que
     * quelqu'un a peut-être rempli. On teste l'EXISTENCE, on ne joue pas la
     * commande, et on ne supprime rien : on le DIT.
     */
    $arbre = <<<'ARBRE'
        touch "$bac/app/artisan"
        mkdir -p "$bac/app/vendor" "$bac/app/public/storage"
        touch "$bac/app/vendor/autoload.php"
        ARBRE;

    $result = ShellProbe::run(
        sondeEntrypoint($arbre, 'APP_ENV=local'),
        entrypointPhp(),
        60,
        ShellProbe::posixShell()['path'],
    );

    expect(statutSonde($result['output']))
        ->toBe(0, 'Un `public/storage` en vrai répertoire tue le conteneur.');

    // ⛔ LA COMMANDE N'EST PAS JOUÉE — c'est ça, l'invariant, pas le message.
    expect(appelsPhp($result['output']))
        ->not->toContain('artisan storage:link');

    // …et l'opérateur est prévenu, avec le geste à faire.
    expect($result['output'])
        ->toContain('n\'est PAS un lien symbolique');

    // Le reste de la branche `bootable` s'est déroulé : le conteneur vit.
    expect(appelsPhp($result['output']))
        ->toContain('artisan config:clear');
});

it('`public/storage` en lien CASSÉ ne tue PAS le conteneur non plus', function (): void {
    /*
     * 🔴 LE CAS FRÈRE, NON TRAITÉ AU PREMIER CORRECTIF (2ᵉ revue). `-e` SUIT le
     * lien : sur un symlink pointant dans le vide il est FAUX pendant que `-L`
     * est VRAI. Un test `! -e` seul reprenait donc la branche de création,
     * `storage:link` échouait sur un chemin déjà occupé, `set -e` tuait
     * l'entrypoint, `restart: unless-stopped` bouclait — exactement le mode de
     * panne que le correctif du répertoire réel venait de fermer, par l'autre
     * porte.
     */
    $arbre = <<<'ARBRE'
        touch "$bac/app/artisan"
        mkdir -p "$bac/app/vendor" "$bac/app/public"
        touch "$bac/app/vendor/autoload.php"
        ln -s "$bac/app/cible-absente" "$bac/app/public/storage"
        ARBRE;

    $result = ShellProbe::run(
        sondeEntrypoint($arbre, 'APP_ENV=local'),
        entrypointPhp(),
        60,
        ShellProbe::posixShell()['path'],
    );

    expect(statutSonde($result['output']))
        ->toBe(0, 'Un `public/storage` en lien CASSÉ tue le conteneur.');

    expect(appelsPhp($result['output']))
        ->not->toContain('artisan storage:link');
    expect($result['output'])
        ->toContain('lien symbolique CASSÉ');

    // Le reste de la branche s'est déroulé : le conteneur vit et atteste.
    expect(appelsPhp($result['output']))
        ->toContain('artisan config:clear');
});

it('APPLICATION BOOTABLE en production : `proxies:check` s’exécute AVANT `config:cache`', function (): void {
    // ⚖️ L'ORDRE EST MESURÉ DANS UN JOURNAL D'EXÉCUTION, pas lu dans le fichier.
    // Le garde textuel d'`AdminPanelRateLimitTest` compare deux `strpos` : il
    // resterait vert si la restructuration en `case` plaçait `config:cache` dans
    // une branche atteinte AVANT celle de `proxies:check`.
    $result = ShellProbe::run(
        sondeEntrypoint(arbreBootable(), 'APP_ENV=production'),
        entrypointPhp(),
        60,
        ShellProbe::posixShell()['path'],
    );

    expect(statutSonde($result['output']))->toBe(0);

    $appels = appelsPhp($result['output']);

    $rang = static function (array $appels, string $commande): int {
        $index = array_search($commande, $appels, true);

        expect($index)
            ->not->toBeFalse("« {$commande} » n'a pas été joué.");

        return (int) $index;
    };

    $garde = $rang($appels, 'artisan proxies:check');
    $cache = $rang($appels, 'artisan config:cache');
    // `optimize:clear` purge AVANT de reconstruire (décision D7).
    $purge = $rang($appels, 'artisan optimize:clear');

    expect($garde)
        ->toBeLessThan($cache);
    expect($purge)
        ->toBeLessThan($cache);
});

it('un `proxies:check` en échec TUE le conteneur, en production comme en staging', function (): void {
    // ⛔ ANTI-VACUITÉ DU TEST PRÉCÉDENT : sans celui-ci, un `proxies:check` joué
    // mais dont l'échec serait avalé laisserait tout vert.
    foreach (['production', 'staging'] as $environnement) {
        $result = ShellProbe::run(
            sondeEntrypoint(arbreBootable(), 'APP_ENV=' . $environnement . ' PHP_CMD_STATUS=1'),
            entrypointPhp(),
            60,
            ShellProbe::posixShell()['path'],
        );

        expect(statutSonde($result['output']))
            ->toBe(1, "APP_ENV={$environnement} : l'échec du contrôle de déploiement n'a pas tué le conteneur.");

        $appels = appelsPhp($result['output']);

        expect($appels)
            ->toContain('artisan proxies:check');
        // Rien après le refus.
        expect($appels)
            ->not->toContain('artisan config:cache');
        expect($appels)
            ->not->toContain('artisan config:clear');
    }
});
