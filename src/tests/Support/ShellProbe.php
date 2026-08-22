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
     * Le sujet VERSIONNÉ du trap ERR, relisible et lançable à la main.
     */
    public static function trapSubject(): string
    {
        return dirname(__DIR__) . '/Fixtures/shell/trap-subject.sh';
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
    public static function run(string $bash, array $env = [], int $timeout = 30): array
    {
        $script = self::writeTempFile('probe-', '.sh', $bash);

        try {
            return self::runFile($script, $env, $timeout);
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
     * Exécute un script existant du dépôt (pilote d'install, fixture de trap…).
     *
     * @param  array<string, string>  $env
     * @return array{status: int, output: string, seconds: float}
     */
    public static function runFile(string $absolutePath, array $env = [], int $timeout = 30): array
    {
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
        $command = sprintf(
            'cd %s && timeout %d env %s bash %s 2>&1',
            escapeshellarg(self::srcDir()),
            $timeout,
            $assignments,
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
