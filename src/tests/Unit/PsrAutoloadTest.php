<?php

declare(strict_types=1);

/**
 * Smoke test for ADR-0009 modular architecture.
 *
 * Verifies that the 6 PSR-4 namespaces (App\Core, App\Modules\{Public, Live, Reviews, PressKit, Admin})
 * are correctly declared in composer.json and that the corresponding directories exist on disk.
 *
 * MUST pass before any other module-specific code is added (Story 1.1 AC #5).
 *
 * @see docs/adr/ADR-0009-modular-app-modules-psr4.md
 */

// True unit test: resolve project root via filesystem, no Laravel boot dependency.
$projectRoot = dirname(__DIR__, 2);

it('registers the 6 PSR-4 namespaces required by ADR-0009', function () use ($projectRoot): void {
    $composerPath = $projectRoot . '/composer.json';
    $contents = file_get_contents($composerPath);
    expect($contents)->not->toBeFalse("composer.json missing at {$composerPath}");

    $composerJson = json_decode(
        json: $contents,
        associative: true,
        flags: JSON_THROW_ON_ERROR,
    );

    $psr4 = $composerJson['autoload']['psr-4'] ?? [];

    // Laravel native namespace must remain (backward compat).
    expect($psr4)->toHaveKey('App\\');

    // 6 ADR-0009 namespaces.
    expect($psr4)->toHaveKey('App\\Core\\');
    expect($psr4)->toHaveKey('App\\Modules\\Public\\');
    expect($psr4)->toHaveKey('App\\Modules\\Live\\');
    expect($psr4)->toHaveKey('App\\Modules\\Reviews\\');
    expect($psr4)->toHaveKey('App\\Modules\\PressKit\\');
    expect($psr4)->toHaveKey('App\\Modules\\Admin\\');

    // Mappings exact.
    expect($psr4['App\\Core\\'])->toBe('app/Core/');
    expect($psr4['App\\Modules\\Public\\'])->toBe('app/Modules/Public/');
    expect($psr4['App\\Modules\\Live\\'])->toBe('app/Modules/Live/');
    expect($psr4['App\\Modules\\Reviews\\'])->toBe('app/Modules/Reviews/');
    expect($psr4['App\\Modules\\PressKit\\'])->toBe('app/Modules/PressKit/');
    expect($psr4['App\\Modules\\Admin\\'])->toBe('app/Modules/Admin/');
});

it('has all 6 module directories created on disk', function () use ($projectRoot): void {
    expect(is_dir($projectRoot . '/app/Core'))->toBeTrue();
    expect(is_dir($projectRoot . '/app/Modules/Public'))->toBeTrue();
    expect(is_dir($projectRoot . '/app/Modules/Live'))->toBeTrue();
    expect(is_dir($projectRoot . '/app/Modules/Reviews'))->toBeTrue();
    expect(is_dir($projectRoot . '/app/Modules/PressKit'))->toBeTrue();
    expect(is_dir($projectRoot . '/app/Modules/Admin'))->toBeTrue();
});
