<?php

declare(strict_types=1);

use Tests\Support\RepoFile;

/**
 * Garde-fou sur les fichiers de consignes chargés par l'agent.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * POURQUOI CE TEST EXISTE
 *
 * `src/CLAUDE.md` n'est pas écrit à la main : il est GÉNÉRÉ par
 * `php artisan boost:update` (Laravel Boost). Le 2026-08-09, la montée de
 * `laravel/boost` 2.4.13 → 2.5.3 y a injecté, sans revue, une consigne
 * impérative — « you MUST first: open @.ai/rules/index.md … Do not write code
 * until you have read every matching rule » — pointant vers un répertoire
 * **qui n'existe pas dans ce dépôt**.
 *
 * C'est le motif dominant du projet (« l'affirmation précède son référent »),
 * cette fois importé depuis l'amont, hors de tout commit relu. Un outil qui
 * écrit dans un fichier versionné à chaque `composer update` peut réintroduire
 * n'importe quelle consigne à n'importe quel moment.
 *
 * Deux invariants sont donc verrouillés ici :
 *
 *   1. Tout import `@chemin` d'un fichier de consignes RÉSOUT sur disque.
 *      Une consigne qui renvoie vers un fichier absent n'est pas une consigne,
 *      c'est une affirmation sans référent.
 *
 *   2. Les guidelines de `src/` sont effectivement IMPORTÉES par le
 *      `CLAUDE.md` de la racine. Sans ça, elles sont versionnées, à jour, et
 *      jamais lues : une session ouverte à la racine du dépôt ne charge que le
 *      `CLAUDE.md` racine.
 *
 * ⚠️ Les deux ont été OBSERVÉS ROUGES avant d'être corrigés (2026-08-09) :
 * l'invariant 1 sur `@.ai/rules/index.md`, l'invariant 2 sur l'absence
 * d'import. Ce ne sont pas des tests écrits après coup sur du vert.
 *
 * @see docs/ETAT.md § « Supply chain — plan exécuté »
 */

/**
 * Les fichiers de consignes du dépôt, relatifs à sa racine.
 *
 * @return list<string>
 */
function guidelineFiles(): array
{
    return ['CLAUDE.md', 'src/CLAUDE.md'];
}

/**
 * Extrait les imports `@chemin` d'un fichier de consignes.
 *
 * Syntaxe Claude Code : `@` suivi d'un chemin, résolu relativement au
 * répertoire du fichier qui porte l'import. On ne capture que les extensions
 * de documents pour ne pas confondre avec une annotation PHPDoc ou un
 * `@php artisan` d'exemple.
 *
 * @return list<string>
 */
function guidelineImports(string $contents): array
{
    preg_match_all(
        '/(?<=^|[\s(])@([A-Za-z0-9_.\/-]+\.(?:md|txt|json|ya?ml))/m',
        $contents,
        $matches,
    );

    /** @var list<string> $imports */
    $imports = array_values(array_unique($matches[1]));

    return $imports;
}

it('ne laisse AUCUN import de consigne pointer vers un fichier absent', function (): void {
    $root = RepoFile::root();
    $unresolved = [];
    $checked = 0;

    foreach (guidelineFiles() as $file) {
        $directory = dirname($root . '/' . $file);

        foreach (guidelineImports(RepoFile::read($file)) as $import) {
            $checked++;
            $target = $directory . '/' . $import;

            if (! file_exists($target)) {
                $unresolved[] = "{$file} → @{$import} (cherché : {$target})";
            }
        }
    }

    // Anti-vacuité : si la regex cesse de matcher, le test passerait au vert
    // sans rien avoir vérifié. L'import de `src/CLAUDE.md` par la racine, posé
    // par l'invariant 2, garantit qu'il y a toujours au moins un import.
    expect($checked)
        ->toBeGreaterThan(
            0,
            'Aucun import @chemin trouvé dans les fichiers de consignes : la '
                . 'détection est cassée, ou l\'import de src/CLAUDE.md a disparu.',
        );

    expect($unresolved)
        ->toBe([], sprintf(
            "Consigne(s) sans référent :\n  - %s\n\n"
                . "`src/CLAUDE.md` est GÉNÉRÉ par `php artisan boost:update`. Si ce test "
                . "rougit après une montée de `laravel/boost`, l'amont a réinjecté une "
                . "consigne pointant vers un chemin absent : la retirer, ou créer le "
                . 'référent — mais ne pas laisser une consigne impérative sans cible.',
            implode("\n  - ", $unresolved),
        ));
});

it('fait effectivement CHARGER les guidelines de src/ par le CLAUDE.md racine', function (): void {
    $imports = guidelineImports(RepoFile::read('CLAUDE.md'));

    // ⚠️ PAS `toContain()` : il est VARIADIQUE en Pest. Un second argument y est
    // une deuxième valeur à chercher, pas un message — l'assertion devient alors
    // impossible à satisfaire. Piège déjà rencontré en Story 1.8, dans l'autre
    // sens (des `toContain()` qui ne pouvaient pas échouer).
    expect(in_array('src/CLAUDE.md', $imports, true))
        ->toBeTrue(
            "Le `CLAUDE.md` racine n'importe pas `src/CLAUDE.md`. Les guidelines "
                . "Laravel Boost sont donc versionnées, tenues à jour à chaque "
                . '`composer update`… et jamais lues : une session ouverte à la racine '
                . "du dépôt ne charge que le `CLAUDE.md` racine. Ajouter la ligne "
                . '`@src/CLAUDE.md`.',
        );
});
