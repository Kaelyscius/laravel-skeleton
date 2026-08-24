<?php

declare(strict_types=1);

namespace Tests\Support;

use FilesystemIterator;
use RecursiveCallbackFilterIterator;
use RecursiveDirectoryIterator;
use RecursiveIteratorIterator;
use RuntimeException;
use SplFileInfo;

/**
 * Exécution de shell depuis Pest, pour éprouver `scripts/lib/*.sh`.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * POURQUOI CETTE CLASSE EXISTE
 *
 * La boucle qualité du projet (Pest, ECS, PHPStan, ratchet) ne voit pas une
 * ligne de shell. Tant que Bats n'est pas installé (Story 2.4), le seul
 * véhicule capable de faire ROUGIR un garde-fou shell est un test Pest qui
 * lance réellement `bash`. Le précédent est
 * `tests/Feature/FilamentPublishedAssetsTest.php` : `exec()` + `escapeshellarg()`.
 *
 * Les helpers vivent dans `tests/Support/` (cf. le commentaire final de
 * `tests/Pest.php`), jamais dans un fichier de test.
 *
 * ⚠️ Chaque exécution passe par `timeout` : une primitive dont le défaut EST la
 * boucle infinie (`retry abc f`, mesuré) ne doit pas suspendre la suite mais la
 * faire échouer avec un code lisible (124).
 *
 * 🔴 LE CWD EST FIXÉ ; L'ENVIRONNEMENT EST HÉRITÉ, SAUF CINQ VARIABLES.
 * `make test` lance pest depuis `/var/www/html` DANS le conteneur ; la CI le
 * lance depuis `src/` sur un `ubuntu-latest` NU (`ci.yml`, job `tests`,
 * `working-directory: src`). Une sonde qui hérite du cwd de PHP mesure donc
 * deux choses différentes selon la machine, et `detect_working_directory`
 * (`common.sh:77`) lit précisément `pwd`. Le cwd est donc FIXÉ (voir
 * `srcDir()`), et les cinq variables que lit `logging.sh` sont ÉPINGLÉES :
 * un `QUIET=true` hérité du shell de l'opérateur éteindrait tout l'affichage
 * et ferait passer chaque `toContain()` sur une sortie vide.
 *
 * ⚠️ Et voici la limite, écrite plutôt que sous-entendue : la commande est
 * `env <épinglages> bash …`, SANS `-i`. Tout le reste de l'environnement de PHP
 * traverse — `PATH` en tête. C'est délibéré (plusieurs sondes reconstruisent
 * `PATH` elles-mêmes pour retirer un binaire) et c'est aussi une dépendance non
 * gardée : une variable que `logging.sh` ou `runtime.sh` se mettrait à lire
 * sans être ajoutée ici redeviendrait silencieusement héritée. Les cinq
 * épinglées sont exactement celles que ces deux libs lisent aujourd'hui.
 */
final class ShellProbe
{
    /**
     * Code de sortie que `timeout(1)` renvoie quand il tue la commande.
     */
    public const TIMEOUT_STATUS = 124;

    /**
     * Racine du dépôt, hôte ou conteneur — résolue par RepoFile, jamais
     * re-dérivée ici.
     */
    public static function repoRoot(): string
    {
        return RepoFile::root();
    }

    /**
     * Répertoire des primitives shell.
     */
    public static function libDir(): string
    {
        return self::repoRoot() . '/scripts/lib';
    }

    /**
     * Répertoire des scripts d'installation, orchestrateur compris.
     *
     * Copié dans un bac à sable par les sondes qui doivent altérer un module
     * (mode non exécutable, module remplacé par un témoin) : `SCRIPT_DIR` est
     * `readonly` dans l'orchestrateur et se dérive de l'emplacement du script,
     * donc la SEULE façon de lui faire voir d'autres modules est de le lancer
     * depuis une copie. Toucher aux modules versionnés serait, littéralement,
     * le défaut que cette story corrige.
     */
    public static function scriptsDir(): string
    {
        return self::repoRoot() . '/scripts';
    }

    /**
     * Les modules déclarés *dry-run aware*, lus SUR DISQUE.
     *
     * Écrite en dur dans le test, la liste resterait juste après un module
     * ajouté, retiré ou mal orthographié — donc verte sur une déclaration qui
     * aurait cessé de désigner un module réel.
     *
     * @return list<string>
     */
    public static function dryRunAwareModules(): array
    {
        $source = file_get_contents(self::installScript());

        if ($source === false) {
            throw new RuntimeException('Orchestrateur illisible : ' . self::installScript());
        }

        if (preg_match('/readonly DRY_RUN_AWARE_MODULES=\((.*?)\n\)/s', $source, $block) !== 1) {
            throw new RuntimeException('Tableau DRY_RUN_AWARE_MODULES introuvable dans l’orchestrateur.');
        }

        preg_match_all('/"([^"]+)"/', $block[1], $matches);

        return $matches[1];
    }

    /**
     * Valeurs d'une variable-liste du `Makefile`, lues SUR DISQUE.
     *
     * Ré-écrite en dur dans un test, la liste resterait juste après une cible
     * ajoutée au Makefile — donc VERTE sur une cible que le garde n'atteint
     * plus. Exactement le motif déjà refusé pour `INSTALL_MODULES` et
     * `DRY_RUN_AWARE_MODULES` ; il n'y a pas de raison de traiter deux listes
     * du même diff de façon opposée.
     *
     * Gère les continuations `\` de make.
     *
     * @return list<string>
     */
    public static function makefileListVariable(string $name): array
    {
        $lines = explode("\n", RepoFile::read('Makefile'));
        $collected = null;

        foreach ($lines as $line) {
            if ($collected === null) {
                // Ancré en début de ligne, et l'affectation doit suivre le nom :
                // sans cet ancrage, une MENTION en commentaire ferait office de
                // déclaration et le garde lirait une liste vide.
                if (preg_match('/^' . preg_quote($name, '/') . '\s*[:?+]?=\s*(.*)$/', $line, $match) !== 1) {
                    continue;
                }

                $collected = $match[1];
            } else {
                $collected .= ' ' . $line;
            }

            if (! str_ends_with(rtrim($collected), '\\')) {
                break;
            }

            $collected = rtrim(rtrim($collected), '\\');
        }

        if ($collected === null) {
            throw new RuntimeException("Variable {$name} introuvable dans le Makefile.");
        }

        $values = preg_split('/\s+/', trim(str_replace("\t", ' ', $collected))) ?: [];

        return array_values(array_filter(
            $values,
            static fn (string $value): bool => $value !== '' && $value !== '\\',
        ));
    }

    /**
     * L'interpréteur POSIX RÉEL de cette machine, avec son IDENTITÉ.
     *
     * 🔴 POURQUOI CETTE MÉTHODE EXISTE. Toutes les sondes de ce dépôt lançaient
     * `bash`. Or `docker/php/scripts/docker-entrypoint.sh` porte `#!/bin/sh` et
     * l'image est `php:8.5-fpm-alpine`, où `/bin/sh` est **BusyBox**. Mesuré :
     * un `local -a _probe=(a b)` glissé dans `detect_laravel_state` laisse les
     * 11 sondes VERTES sous bash, et fait mourir le script en « syntax error »
     * sous BusyBox — donc boucle de redémarrage, le défaut même que la story
     * vient de corriger. C'est le motif de la story 2.3 (un garde mesuré sous
     * GNU coreutils, faux sous BusyBox) reproduit dans le garde censé le clore.
     *
     * ⚖️ L'IDENTITÉ EST RENDUE, PAS DEVINÉE. L'appelant peut la NOMMER dans son
     * rapport — « nommer l'environnement de la mesure » ne veut pas dire nommer
     * la machine, mais l'interpréteur qui décide du verdict. Et un `/bin/sh` qui
     * serait en fait `bash` doit pouvoir être REFUSÉ par le test plutôt que
     * mesuré en croyant mesurer autre chose.
     *
     * @return array{path: string, name: string}
     */
    public static function posixShell(): array
    {
        $path = '/bin/sh';
        $reel = realpath($path);

        return [
            'path' => $path,
            'name' => $reel === false ? 'introuvable' : basename($reel),
        ];
    }

    /**
     * Les prérequis d'une cible, LUS DANS LA BASE DE `make`, pas dans le fichier.
     *
     * ⛔ POURQUOI PAS UN `preg_match` SUR LE MAKEFILE. Une regex lit du TEXTE ;
     * `make -pRrq :` rend le graphe que `make` va réellement parcourir, après
     * expansion des variables, des `include` et des conditionnelles. Un
     * prérequis posé par variable, ou une règle rendue inatteignable, se voient
     * ici et pas là-bas.
     *
     * ⚠️ ET C'EST UNE LECTURE, PAS UNE EXÉCUTION. `-p` imprime la base et `q :`
     * demande une cible inexistante : aucune recette n'est jouée. Un `make -n`
     * aurait été bien pire — `make` EXÉCUTE les lignes contenant `$(MAKE)`
     * même en simulation, et `check_container` en contient une qui démarre les
     * conteneurs.
     *
     * @return list<string>
     */
    public static function makefilePrerequisites(string $target): array
    {
        $command = sprintf(
            'cd %s && make -pRrq : 2>/dev/null',
            escapeshellarg(self::repoRoot()),
        );

        $output = [];
        $status = 0;
        exec($command, $output, $status);

        foreach ($output as $line) {
            if (! str_starts_with($line, $target . ':')) {
                continue;
            }

            $reste = substr($line, strlen($target) + 1);
            $valeurs = preg_split('/\s+/', trim($reste)) ?: [];

            return array_values(array_filter(
                $valeurs,
                static fn (string $value): bool => $value !== '',
            ));
        }

        throw new RuntimeException("Cible « {$target} » absente de la base de make.");
    }

    /**
     * La RECETTE d'une cible, telle que `make` la stocke.
     *
     * Sert aux cibles qui pilotent depuis leur recette (`$(MAKE) …`) plutôt que
     * par leurs prérequis : le graphe ne les voit pas, et c'est précisément
     * pourquoi le Makefile les énumère à la main dans
     * `COMPOSITE_RECIPE_TARGETS`.
     */
    public static function makefileRecipe(string $target): string
    {
        $command = sprintf(
            'cd %s && make -pRrq : 2>/dev/null',
            escapeshellarg(self::repoRoot()),
        );

        $output = [];
        $status = 0;
        exec($command, $output, $status);

        $dans = false;
        $commencee = false;
        $lignes = [];

        foreach ($output as $line) {
            if (! $dans) {
                if (str_starts_with($line, $target . ':')) {
                    $dans = true;
                }

                continue;
            }

            // ⚠️ `make -p` INTERCALE SES PROPRES COMMENTAIRES entre la règle et
            // sa recette (« # Phony target », « # recipe to execute … »).
            // S'arrêter à la première ligne non tabulée coupait donc AVANT
            // d'avoir lu la moindre ligne de recette.
            if (str_starts_with($line, '#')) {
                continue;
            }

            // La recette est indentée par une TABULATION.
            if (str_starts_with($line, "\t")) {
                $commencee = true;
                $lignes[] = substr($line, 1);

                continue;
            }

            if ($commencee || trim($line) === '') {
                break;
            }
        }

        if ($lignes === []) {
            throw new RuntimeException("Recette de « {$target} » introuvable dans la base de make.");
        }

        return implode("\n", $lignes);
    }

    /**
     * Les chaînes d'installation COMPOSITES, dérivées comme le Makefile les
     * dérive : par le graphe de dépendances, jamais par une énumération.
     *
     * ⛔ POURQUOI PAS `makefileListVariable('COMPOSITE_INSTALL_TARGETS')` :
     * la variable est désormais RÉCURSIVE et son corps est un programme `awk`.
     * La lire textuellement ne rendrait rien d'utile — et surtout, un test qui
     * relit l'énumération ne peut pas prouver qu'une cible NEUVE est attrapée.
     * On demande donc à `make` lui-même, qui applique la règle réelle.
     *
     * @return list<string>
     */
    public static function makefileComposites(): array
    {
        $command = sprintf(
            // Sans `-n` : avec, make IMPRIME la recette (« echo … ») au lieu
            // de l'exécuter, et le mot « echo » se retrouvait dans la liste.
            'cd %s && make --eval=%s __composites__ 2>/dev/null',
            escapeshellarg(self::repoRoot()),
            escapeshellarg('__composites__: ; @echo $(COMPOSITE_INSTALL_TARGETS)'),
        );

        $output = [];
        $status = 0;
        exec($command . ' DRY_RUN=false', $output, $status);

        if ($status !== 0) {
            throw new RuntimeException('Impossible de dériver COMPOSITE_INSTALL_TARGETS du Makefile.');
        }

        $valeurs = preg_split('/\s+/', trim(implode(' ', $output))) ?: [];

        return array_values(array_filter(
            $valeurs,
            static fn (string $valeur): bool => $valeur !== '',
        ));
    }

    /**
     * Racine de l'application Laravel — le cwd de TOUTE sonde.
     *
     * C'est le répertoire d'où la CI lance pest (`working-directory: src`) et,
     * dans le conteneur, le point de montage de `src/` (`/var/www/html`). Le
     * fixer supprime la seule différence qui faisait diverger le pilote entre
     * les deux environnements.
     */
    public static function srcDir(): string
    {
        foreach (['/var/www/html', self::repoRoot() . '/src'] as $candidate) {
            if (is_dir($candidate . '/bootstrap')) {
                return $candidate;
            }
        }

        return self::repoRoot() . '/src';
    }

    /**
     * Le pilote — seul script d'install converti par la story 2.1.
     */
    public static function pilotScript(): string
    {
        return self::repoRoot() . '/scripts/install/00-prerequisites.sh';
    }

    /**
     * L'orchestrateur d'installation — sujet de la story 2.2.
     *
     * Sourçable : sa garde `BASH_SOURCE[0] = $0` l'empêche de s'auto-exécuter,
     * ce qui permet de remplacer `execute_module` par un compteur sans toucher
     * à la boucle, au fail-fast ni au calcul de sentinelle.
     */
    public static function installScript(): string
    {
        return self::repoRoot() . '/scripts/install.sh';
    }

    /**
     * Un module d'installation, par son identifiant (`10-laravel-core`).
     */
    public static function installModuleScript(string $module): string
    {
        return self::repoRoot() . '/scripts/install/' . $module . '.sh';
    }

    /**
     * Le script HÔTE du lockfile d'installation.
     */
    public static function lockfileScript(): string
    {
        return self::repoRoot() . '/scripts/install-lockfile.sh';
    }

    /**
     * Le sujet VERSIONNÉ du trap ERR, relisible et lançable à la main.
     */
    public static function trapSubject(): string
    {
        return dirname(__DIR__) . '/Fixtures/shell/trap-subject.sh';
    }

    /**
     * Le sujet VERSIONNÉ de l'idempotence, relisible et lançable à la main.
     */
    public static function idempotenceSubject(): string
    {
        return dirname(__DIR__) . '/Fixtures/shell/idempotence-subject.sh';
    }

    /**
     * Les modules énumérés par l'orchestrateur, lus SUR DISQUE.
     *
     * Écrite en dur dans le test, la liste resterait juste après un module
     * ajouté ou renommé — donc verte sur une boucle qui aurait cessé de le
     * couvrir. Les identifiants viennent du tableau `INSTALL_MODULES`, qui est
     * aussi le grain des sentinelles.
     *
     * @return list<string>
     */
    public static function installModules(): array
    {
        $source = file_get_contents(self::installScript());

        if ($source === false) {
            throw new RuntimeException('Orchestrateur illisible : ' . self::installScript());
        }

        if (preg_match('/readonly INSTALL_MODULES=\((.*?)\n\)/s', $source, $block) !== 1) {
            throw new RuntimeException('Tableau INSTALL_MODULES introuvable dans l’orchestrateur.');
        }

        preg_match_all('/"([^":]+):/', $block[1], $matches);

        return $matches[1];
    }

    /**
     * Numéro de ligne de la commande nue en échec, DÉRIVÉ du marqueur.
     *
     * Écrit en dur, il resterait juste après un déplacement de la commande —
     * donc vert sur un trap qui aurait cessé de rapporter la bonne ligne.
     */
    public static function trapFailingLine(): int
    {
        $lines = file(self::trapSubject(), FILE_IGNORE_NEW_LINES);

        if ($lines === false) {
            throw new RuntimeException('Fixture du trap illisible : ' . self::trapSubject());
        }

        foreach ($lines as $index => $line) {
            if (str_contains($line, 'TRAP-SUBJECT-FAILING-LINE')) {
                return $index + 1;
            }
        }

        throw new RuntimeException('Marqueur TRAP-SUBJECT-FAILING-LINE absent de la fixture.');
    }

    /**
     * Les délais d'attente annoncés par `retry`, dans l'ordre.
     *
     * @return list<string>
     */
    public static function retryDelays(string $output): array
    {
        preg_match_all('/nouvelle tentative dans (\d+)s/', $output, $matches);

        return $matches[1];
    }

    /**
     * Prélude de sourcing, dans l'ordre imposé par le dépôt : `logging.sh`
     * AVANT `runtime.sh`.
     */
    public static function prelude(): string
    {
        $lib = self::libDir();

        return <<<BASH
            set -e
            source '{$lib}/logging.sh'
            source '{$lib}/runtime.sh'

            BASH;
    }

    /**
     * Exécute un fragment bash tel quel — aucun prélude implicite, pour que le
     * test qui éprouve la GARDE D'INCLUSION contrôle lui-même ses `source`.
     *
     * @param  array<string, string>  $env
     * @return array{status: int, output: string, seconds: float}
     */
    public static function run(string $bash, array $env = [], int $timeout = 30, ?string $interpreter = null): array
    {
        $script = self::writeTempFile('probe-', '.sh', $bash);

        try {
            return self::runFile($script, $env, $timeout, $interpreter);
        } finally {
            @unlink($script);
        }
    }

    /**
     * Même chose, avec `logging.sh` + `runtime.sh` déjà sourcés et `set -e`.
     *
     * @param  array<string, string>  $env
     * @return array{status: int, output: string, seconds: float}
     */
    public static function runWithRuntime(string $bash, array $env = [], int $timeout = 30): array
    {
        return self::run(self::prelude() . $bash, $env, $timeout);
    }

    /**
     * Exécute un fragment bash en CAPTURANT LES DEUX FLUX SÉPARÉMENT.
     *
     * 🔴 EXISTE PARCE QU'AUCUNE AUTRE SONDE NE PEUT LES DISTINGUER. `run()` et
     * `runFile()` construisent `bash … 2>&1` : toutes leurs assertions lisent un
     * flux FUSIONNÉ. Une prose affirmant « le plan part sur STDERR » a donc pu
     * vivre dans CINQ fichiers, dont les deux que l'opérateur lit, alors que la
     * mesure dit l'inverse — aucun test ne pouvait la contredire.
     *
     * @param  array<string, string>  $env
     * @return array{status: int, stdout: string, stderr: string}
     */
    public static function runSeparated(
        string $bash,
        array $env = [],
        int $timeout = 30,
        ?string $interpreter = null,
    ): array {
        $script = self::writeTempFile('probe-split-', '.sh', $bash);
        $out = self::writeTempFile('probe-out-', '.txt', '');
        $err = self::writeTempFile('probe-err-', '.txt', '');

        try {
            $assignments = '';

            foreach (array_merge(self::pinnedEnvironment(), $env) as $name => $value) {
                $assignments .= escapeshellarg($name . '=' . $value) . ' ';
            }

            $command = sprintf(
                'cd %s && timeout %d env %s %s %s > %s 2> %s',
                escapeshellarg(self::srcDir()),
                $timeout,
                $assignments,
                escapeshellarg($interpreter ?? 'bash'),
                escapeshellarg($script),
                escapeshellarg($out),
                escapeshellarg($err),
            );

            $ignored = [];
            $status = 0;
            exec($command, $ignored, $status);

            return [
                'status' => $status,
                'stdout' => (string) file_get_contents($out),
                'stderr' => (string) file_get_contents($err),
            ];
        } finally {
            @unlink($script);
            @unlink($out);
            @unlink($err);
        }
    }

    /**
     * Exécute un script existant du dépôt (pilote d'install, fixture de trap…).
     *
     * @param  array<string, string>  $env
     * @return array{status: int, output: string, seconds: float}
     */
    public static function runFile(
        string $absolutePath,
        array $env = [],
        int $timeout = 30,
        ?string $interpreter = null,
    ): array {
        if (! is_file($absolutePath)) {
            throw new RuntimeException("Script shell introuvable : {$absolutePath}");
        }

        $assignments = '';

        foreach (array_merge(self::pinnedEnvironment(), $env) as $name => $value) {
            $assignments .= escapeshellarg($name . '=' . $value) . ' ';
        }

        // `cd` explicite : le cwd est une ENTRÉE du sujet sous test
        // (`detect_working_directory` lit `pwd`), pas un décor. `2>&1` est
        // obligatoire depuis que `log()` écrit sur stderr — sans lui, chaque
        // `toContain()` lirait une sortie vide.
        // ⚖️ L'INTERPRÉTEUR EST UN PARAMÈTRE, PAS UN LITTÉRAL — et son défaut
        // reste `bash`, parce que la quasi-totalité des sujets de ce dépôt
        // (`scripts/install.sh`, `scripts/lib/*.sh`) en exigent les tableaux.
        // Ce qui porte `#!/bin/sh` se sonde sous `sh`, explicitement.
        $command = sprintf(
            'cd %s && timeout %d env %s %s %s 2>&1',
            escapeshellarg(self::srcDir()),
            $timeout,
            $assignments,
            escapeshellarg($interpreter ?? 'bash'),
            escapeshellarg($absolutePath),
        );

        $output = [];
        $status = 0;

        $startedAt = microtime(true);
        exec($command, $output, $status);
        $seconds = microtime(true) - $startedAt;

        return [
            'status' => $status,
            'output' => implode("\n", $output),
            'seconds' => $seconds,
        ];
    }

    /**
     * Environnement ÉPINGLÉ de toute sonde.
     *
     * `logging.sh` lit `QUIET`, `LOG_LEVEL` et `DEBUG` ; `runtime.sh` lit
     * `RETRY_BASE_DELAY`. Hérités du shell de l'opérateur ou du runner, ils
     * changent silencieusement ce que la sonde observe — `QUIET=true` suffit à
     * vider la sortie et à rendre VERT tout `toContain()`. `LOG_FILE` est
     * unique par sonde ET sous `/tmp`, ce qui est aussi l'invariant que mesure
     * « le pilote ne modifie ni le dépôt ni l'arbre applicatif ».
     *
     * @return array<string, string>
     */
    private static function pinnedEnvironment(): array
    {
        return [
            'QUIET' => 'false',
            'LOG_LEVEL' => 'DEBUG',
            'DEBUG' => 'true',
            'RETRY_BASE_DELAY' => '1',
            'LOG_FILE' => sys_get_temp_dir() . '/' . uniqid('shellprobe-', true) . '.log',
        ];
    }

    /**
     * Empreinte (chemin → mtime:taille) des arborescences surveillées.
     *
     * Sert à prouver qu'un script n'écrit RIEN hors /tmp. `find -printf`
     * n'existe pas dans ce conteneur (BusyBox), et une empreinte construite en
     * shell y rendait deux inventaires VIDES — donc identiques, donc verts.
     * L'inventaire est construit ici, et l'appelant doit vérifier qu'il n'est
     * pas vide AVANT de comparer.
     *
     * 🔴 LES EXCLUSIONS SONT DES CHEMINS, PAS DES NOMS DE BASE. Filtrer sur
     * `$file->getFilename()` excluait n'importe quel répertoire nommé `logs`,
     * `vendor` ou `debugbar` À N'IMPORTE QUELLE PROFONDEUR : un script écrivant
     * dans `app/logs/` échappait à la garde sans que rien ne le signale. Les
     * chemins ci-dessous sont ancrés sur chaque racine et coupent à la
     * frontière de répertoire.
     *
     * Ce qui est exclu, et sur quelle preuve :
     *   `.git`, `vendor`, `node_modules` — bougent pour des raisons étrangères
     *   au sujet (commit en cours, installeur de dépendances) ;
     *   `storage/logs`, `storage/debugbar`, `docker/apache/logs` — écrits par le
     *   LANCEUR DE TESTS lui-même pendant la fenêtre de mesure. Mesuré le
     *   2026-08-22 sur 75 itérations instrumentées : 3 diffs, tous de ces trois
     *   chemins, aucun du pilote. `storage/framework` n'est PAS exclu — il n'a
     *   jamais bougé, et on n'exclut que ce qu'on a vu bouger.
     *
     * @param  list<string>  $roots
     * @return array<string, string>
     */
    public static function inventory(array $roots): array
    {
        $entries = [];

        foreach ($roots as $root) {
            if (! is_dir($root)) {
                continue;
            }

            $excluded = self::excludedPaths($root);

            $walker = new RecursiveIteratorIterator(
                new RecursiveCallbackFilterIterator(
                    new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS),
                    static function (SplFileInfo $file) use ($excluded): bool {
                        $path = $file->getPathname();

                        foreach ($excluded as $prefix) {
                            if ($path === $prefix || str_starts_with($path, $prefix . '/')) {
                                return false;
                            }
                        }

                        return true;
                    },
                ),
                RecursiveIteratorIterator::SELF_FIRST,
                RecursiveIteratorIterator::CATCH_GET_CHILD,
            );

            foreach ($walker as $file) {
                if (! $file instanceof SplFileInfo) {
                    continue;
                }

                $entries[$file->getPathname()] = self::fingerprint($file->getPathname());
            }
        }

        ksort($entries);

        return $entries;
    }

    /**
     * Empreinte d'UNE entrée, sans jamais lever.
     *
     * `SplFileInfo::getMTime()` lève une `RuntimeException` sur un lien
     * symbolique pendant ou sur un fichier disparu entre la traversée et la
     * lecture — le test mourrait alors sur une exception au lieu d'une
     * assertion, en masquant ce qu'il mesurait. `src/public/storage` est
     * précisément pendant sur l'hôte. Une entrée illisible est donc ENREGISTRÉE
     * comme telle : elle reste comparable d'un relevé à l'autre, et devenir
     * lisible (ou cesser de l'être) se voit toujours comme un changement.
     */
    private static function fingerprint(string $path): string
    {
        // `file_exists()` SUIT le lien : faux pour un lien pendant. Le tester
        // AVANT `filemtime()` évite le diagnostic plutôt que de le supprimer —
        // `@` ne suffit pas, le gestionnaire d'erreurs de PHPUnit le rattrape
        // quand même et transforme le test en `warning`.
        if (! file_exists($path)) {
            return 'INACCESSIBLE:0';
        }

        $mtime = @filemtime($path);
        $size = is_file($path) ? @filesize($path) : 0;

        return ($mtime === false ? 'INACCESSIBLE' : (string) $mtime)
            . ':' . ($size === false ? '?' : (string) $size);
    }

    /**
     * Chemins absolus exclus de l'inventaire, pour une racine donnée.
     *
     * @return list<string>
     */
    private static function excludedPaths(string $root): array
    {
        $relatives = [
            '.git',
            'vendor',
            'node_modules',
            'storage/logs',
            'storage/debugbar',
            // Racine du dépôt : l'application y vit sous `src/`.
            'src/vendor',
            'src/node_modules',
            'src/storage/logs',
            'src/storage/debugbar',
            'docker/apache/logs',
        ];

        return array_map(static fn (string $relative): string => $root . '/' . $relative, $relatives);
    }

    /**
     * Écrit un fragment de sonde dans un fichier exécutable, sous `/tmp`.
     */
    private static function writeTempFile(string $prefix, string $suffix, string $contents): string
    {
        $path = sys_get_temp_dir() . '/' . uniqid($prefix, true) . $suffix;

        if (file_put_contents($path, $contents) === false) {
            throw new RuntimeException("Écriture impossible : {$path}");
        }

        chmod($path, 0o755);

        return $path;
    }
}
