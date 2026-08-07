<?php

declare(strict_types=1);

use Tests\Support\RepoFile;

/**
 * Smoke test for ADR-0009 modular architecture.
 *
 * Verifies that the 6 PSR-4 namespaces (App\Core, App\Modules\{Public, Live, Reviews, PressKit, Admin})
 * are correctly declared in composer.json and that the corresponding directories exist on disk.
 *
 * MUST pass before any other module-specific code is added (Story 1.1 AC #5).
 *
 * La lecture de composer.json passe par Tests\Support\RepoFile : `json_decode`
 * renvoie `mixed`, et chaque accès produisait sa propre erreur PHPStan au
 * niveau 10. Le typage entre une fois, dans le lecteur, et bruyamment — un
 * composer.json absent lève une exception nommée au lieu de laisser un tableau
 * vide passer les assertions.
 *
 * @see docs/adr/ADR-0009-modular-app-modules-psr4.md
 */

/**
 * Les 6 namespaces d'ADR-0009 et leur répertoire, plus le namespace natif
 * Laravel conservé pour compatibilité.
 *
 * @return array<string, string>
 */
function adr0009Namespaces(): array
{
    return [
        'App\\Core\\' => 'app/Core/',
        'App\\Modules\\Public\\' => 'app/Modules/Public/',
        'App\\Modules\\Live\\' => 'app/Modules/Live/',
        'App\\Modules\\Reviews\\' => 'app/Modules/Reviews/',
        'App\\Modules\\PressKit\\' => 'app/Modules/PressKit/',
        'App\\Modules\\Admin\\' => 'app/Modules/Admin/',
    ];
}

it('registers the 6 PSR-4 namespaces required by ADR-0009', function (): void {
    $psr4 = RepoFile::section(RepoFile::json('src/composer.json'), 'autoload.psr-4');

    // Le namespace natif Laravel doit rester (compatibilité ascendante).
    expect($psr4)
        ->toHaveKey('App\\');

    foreach (adr0009Namespaces() as $namespace => $directory) {
        expect($psr4)->toHaveKey($namespace);
        expect($psr4[$namespace])
            ->toBe($directory, "Le namespace {$namespace} ne pointe pas sur {$directory}.");
    }
});

it('has all 6 module directories created on disk', function (): void {
    // dirname(__DIR__, 2) = src/ : ce test reste un vrai test unitaire, sans
    // démarrage de Laravel, donc sans base_path().
    $appRoot = dirname(__DIR__, 2);

    foreach (adr0009Namespaces() as $namespace => $directory) {
        expect(is_dir($appRoot . '/' . rtrim($directory, '/')))
            ->toBeTrue("Répertoire manquant pour {$namespace} : {$directory}");
    }
});
