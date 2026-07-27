<?php

declare(strict_types=1);

use App\Core\Providers\CoreServiceProvider;
use App\Modules\Admin\Providers\AdminServiceProvider;
use App\Modules\Live\Providers\LiveServiceProvider;
use App\Modules\PressKit\Providers\PressKitServiceProvider;
use App\Modules\Public\Providers\PublicServiceProvider;
use App\Modules\Reviews\Providers\ReviewsServiceProvider;
use App\Providers\AppServiceProvider;

/*
 * Conditional module activation via ENV (ADR-0001/0009, architecture §3.2).
 *
 * The mechanism is proven two ways:
 *   1. The pure static helper AppServiceProvider::moduleProviders() — synthetic,
 *      deterministic, the core of the proof (same "helper + self-check" pattern
 *      as Stories 1.5/1.6).
 *   2. The real container wiring — the default config boots all 5 module
 *      providers + Core.
 *
 * The literal ACs "GET /reviews/... → 404 when disabled" and "reviews migration
 * not applied" are DORMANT: Reviews has no route/migration before Epic 5, so an
 * HTTP test would pass trivially even with the flag ON (green-but-useless). We
 * therefore prove non-registration of the provider, which is what guarantees no
 * route/migration/view/Filament resource of a disabled module ever loads. Those
 * literal ACs become verifiable as-is once Reviews gains routes/migrations.
 */

it('maps every enabled module key to its provider FQCN (helper self-check)', function (): void {
    $all = AppServiceProvider::moduleProviders([
        'public' => true,
        'live' => true,
        'reviews' => true,
        'press_kit' => true,
        'admin' => true,
    ]);

    expect($all)
        ->toBe([
            PublicServiceProvider::class,
            LiveServiceProvider::class,
            ReviewsServiceProvider::class,
            PressKitServiceProvider::class,
            AdminServiceProvider::class,
        ]);
});

it('drops a disabled module so its provider is never registered (mechanism, not HTTP)', function (): void {
    $providers = AppServiceProvider::moduleProviders([
        'public' => true,
        'live' => true,
        'reviews' => false,
        'press_kit' => true,
        'admin' => true,
    ]);

    // 4 enabled providers, Reviews excluded → nothing from Reviews can load.
    expect($providers)
        ->toHaveCount(4);
    expect($providers)
        ->not->toContain(ReviewsServiceProvider::class);
});

it('Studly-cases snake_case keys (press_kit → PressKitServiceProvider)', function (): void {
    expect(AppServiceProvider::moduleProviders([
        'press_kit' => true,
    ]))
        ->toBe([PressKitServiceProvider::class]);
});

it('returns an empty set for an all-disabled or empty config (no fatal)', function (): void {
    expect(AppServiceProvider::moduleProviders([
        'reviews' => false,
    ]))->toBe([])
        ->and(AppServiceProvider::moduleProviders([]))->toBe([]);
});

it('treats every falsy ENV writing as disabled (false / 0 / empty string)', function (): void {
    expect(AppServiceProvider::moduleProviders([
        'public' => false,
        'live' => 0,
        'reviews' => '',
        'press_kit' => true,
        'admin' => '1',
    ]))->toBe([
        PressKitServiceProvider::class,
        AdminServiceProvider::class,
    ]);
});

it('boots all 5 module providers plus Core under the default config', function (): void {
    $loaded = array_keys(app()->getLoadedProviders());

    expect($loaded)
        ->toContain(PublicServiceProvider::class)
        ->toContain(LiveServiceProvider::class)
        ->toContain(ReviewsServiceProvider::class)
        ->toContain(PressKitServiceProvider::class)
        ->toContain(AdminServiceProvider::class)
        // Core is registered unconditionally (bootstrap/providers.php), never
        // gated by config/modules.php.
        ->toContain(CoreServiceProvider::class);
});

it('loads config/modules.php with exactly the 5 deactivatable keys (core excluded)', function (): void {
    expect(array_keys((array) config('modules')))
        ->toBe(['public', 'live', 'reviews', 'press_kit', 'admin']);
});
