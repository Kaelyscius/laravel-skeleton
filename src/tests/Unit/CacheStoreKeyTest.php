<?php

declare(strict_types=1);

use Tests\Support\RepoFile;

/*
|------------------------------------------------------------------------------
| La clé d'environnement du cache — Story 2.4, revue 1
|------------------------------------------------------------------------------
|
| 🔴 CE QUE CE FICHIER EMPÊCHE DE RECOMMENCER, ET IL A DÉJÀ EU LIEU.
|
| Laravel 11+ lit `CACHE_STORE` (`config/cache.php:17`). Les modèles et les
| scripts de ce dépôt écrivaient `CACHE_DRIVER`, l'ancienne clé. Conséquence
| MESURÉE le 2026-08-23 sur la pile réelle : `config('cache.default')` valait
| `database` alors que trois fichiers annonçaient Redis — et la sonde cache de
| `/health` restait **`ok` avec Redis arrêté**, parce qu'elle éprouvait la BASE.
| Une seconde sonde base déguisée en sonde cache, et le nightly l'assertait.
|
| ⚖️ Le garde porte sur la CONCORDANCE, pas sur une valeur : ce que les modèles
| déclarent doit être ce que la configuration lit. Une clé morte dans un `.env`
| est silencieuse par construction — rien ne prévient jamais.
|
*/

it('lit bien CACHE_STORE dans config/cache.php', function (): void {
    // Anti-vacuité : si la clé lue changeait, tout le reste de ce fichier
    // garderait la mauvaise chose.
    expect(RepoFile::read('src/config/cache.php'))
        ->toContain("env('CACHE_STORE'");
});

/**
 * Fichiers texte du dépôt susceptibles de PRESCRIRE une clé d'environnement.
 *
 * 🔴 BALAYAGE, PAS ÉNUMÉRATION (revue 2). La rédaction précédente listait SIX
 * chemins en dur — et a laissé passer deux prescriptions de la clé morte :
 * `docs/architecture/4-architecture-donnes.md` (document qui fait AUTORITÉ) et
 * `prompts/testing/01-add-dusk-e2e-testing.md`. C'est exactement le correctif
 * appliqué en story 2.3 à `COMPOSITE_INSTALL_TARGETS` : une énumération ne peut
 * pas garder ce qu'elle ne connaît pas.
 *
 * @return array<int, string>  chemins relatifs à la racine du dépôt
 */
function cacheStoreScannedFiles(): array
{
    $root = Tests\Support\RepoFile::root();

    // Répertoires sans intérêt (dépendances, artefacts, historique git) ou
    // trop volumineux pour un balayage synchrone.
    // ⛔ Exclusions, chacune pour une raison :
    //   • dépendances et artefacts : rien n'y est écrit par ce dépôt ;
    //   • `_bmad-output/` : gitignoré (décision PO du 2026-07-30, dépôt public) ;
    //   • fichiers générés (`_ide_helper*`, `.phpstorm.meta.php`) : ils
    //     ÉNUMÈRENT les clés connues de tous les paquets, ils n'en prescrivent
    //     aucune.
    $skipped = [
        'vendor', 'node_modules', '.git', 'storage', 'public/build', 'coverage',
        '.tools', 'backups', 'logs', '_bmad-output', '.idea', '.claude',
    ];
    $extensions = ['md', 'sh', 'yml', 'yaml', 'php', 'example', 'env', 'conf', 'ini', 'json'];

    $found = [];

    $iterator = new RecursiveIteratorIterator(
        new RecursiveCallbackFilterIterator(
            new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS),
            static function (SplFileInfo $file) use ($root, $skipped): bool {
                $relative = ltrim(str_replace($root, '', $file->getPathname()), '/');

                foreach ($skipped as $prefix) {
                    if ($relative === $prefix || str_starts_with($relative, $prefix . '/')) {
                        return false;
                    }
                }

                return true;
            },
        ),
    );

    foreach ($iterator as $file) {
        if (! $file instanceof SplFileInfo || ! $file->isFile()) {
            continue;
        }

        $name = $file->getFilename();
        $extension = $file->getExtension();

        // `.env.example`, `Makefile`, `Dockerfile` n'ont pas d'extension utile.
        if (! in_array($extension, $extensions, true)
            && ! str_starts_with($name, '.env')
            && ! in_array($name, ['Makefile', 'Dockerfile'], true)) {
            continue;
        }

        // ⚠️ Seul `.env.example` est SUIVI : `.gitignore` exclut `.env.*` et ne
        // ré-inclut que celui-là. Les `.env.local` / `.env.development` d'un
        // poste ne sont pas des prescriptions du dépôt.
        if (str_starts_with($name, '.env') && $name !== '.env.example') {
            continue;
        }

        if (str_starts_with($name, '_ide_helper') || $name === '.phpstorm.meta.php') {
            continue;
        }

        if ($file->getSize() > 512_000) {
            continue;
        }

        $found[] = ltrim(str_replace($root, '', $file->getPathname()), '/');
    }

    sort($found);

    return $found;
}

it('balaye le dépôt ENTIER, pas une liste de chemins écrite à la main', function (): void {
    $scanned = cacheStoreScannedFiles();

    // Anti-vacuité : les deux fichiers que l'énumération précédente avait
    // MANQUÉS doivent être dans le périmètre, sinon le garde ne garde rien.
    expect($scanned)
        ->toContain('docs/architecture/4-architecture-donnes.md')
        ->toContain('prompts/testing/01-add-dusk-e2e-testing.md')
        ->toContain('.env.example')
        ->toContain('src/.env.example');

    expect(count($scanned))
        ->toBeGreaterThan(100);
});

it('ne laisse AUCUN fichier suivi PRESCRIRE la clé morte CACHE_DRIVER', function (): void {
    $offenders = [];

    foreach (cacheStoreScannedFiles() as $path) {
        // ⛔ UN GARDE NE PEUT PAS ÊTRE SON PROPRE SUJET : ce fichier contient
        // l'expression qu'il cherche, et l'exclure est la seule issue honnête.
        if ($path === 'src/tests/Unit/CacheStoreKeyTest.php') {
            continue;
        }

        foreach (explode("\n", Tests\Support\RepoFile::read($path)) as $line) {
            // Les COMMENTAIRES sont écartés : plusieurs fichiers expliquent la
            // bascule et citent donc la clé morte. Un garde qui crie sur
            // l'explication de sa propre raison d'être est un garde qu'on
            // désarme le lendemain.
            $trimmed = ltrim($line);

            if ($trimmed === ''
                || str_starts_with($trimmed, '#')
                || str_starts_with($trimmed, '//')
                || str_starts_with($trimmed, '*')
                || str_starts_with($trimmed, '>')) {
                continue;
            }

            /*
             * ⚖️ LE CRITÈRE EST « PRESCRIRE », PAS « MENTIONNER », ET LA
             * DISTINCTION EST MÉCANIQUE PLUTÔT QUE PAR LISTE DE CHEMINS :
             *
             *   • la ligne AFFECTE quelque chose (`=`) — une prose qui cite la
             *     clé n'en affecte aucune ;
             *   • et elle ne nomme PAS `CACHE_STORE` — car toute ligne qui
             *     explique la bascule cite forcément les deux.
             *
             * Vérifié contre les deux offenseurs réels que l'énumération
             * précédente avait manqués : « - `CACHE_DRIVER=redis` » (doc
             * d'architecture) et « CACHE_DRIVER=array » (prompt Dusk) sont tous
             * deux attrapés, y compris entourés de guillemets obliques.
             *
             * ⚠️ Ancré sur la clé NUE : `PULSE_CACHE_DRIVER` est légitime.
             */
            if (preg_match('/(?<![A-Z_])CACHE_DRIVER/', $line) !== 1) {
                continue;
            }

            if (! str_contains($line, '=') || str_contains($line, 'CACHE_STORE')) {
                continue;
            }

            $offenders[] = $path . ' :: ' . trim($line);
        }
    }

    expect($offenders)
        ->toBe([]);
});

it('déclare CACHE_STORE dans les deux modèles d’environnement suivis', function (): void {
    expect(RepoFile::read('.env.example'))
        ->toContain('CACHE_STORE=');
    expect(RepoFile::read('src/.env.example'))
        ->toContain('CACHE_STORE=');
});
