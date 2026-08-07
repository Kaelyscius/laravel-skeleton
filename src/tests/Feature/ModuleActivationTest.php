<?php

declare(strict_types=1);

use App\Core\Providers\CoreServiceProvider;
use App\Modules\Admin\Providers\AdminServiceProvider;
use App\Modules\Live\Providers\LiveServiceProvider;
use App\Modules\PressKit\Providers\PressKitServiceProvider;
use App\Modules\Public\Providers\PublicServiceProvider;
use App\Modules\Reviews\Providers\ReviewsServiceProvider;
use App\Providers\AppServiceProvider;
use Illuminate\Container\Container;
use Illuminate\Contracts\Console\Kernel as ConsoleKernel;
use Illuminate\Foundation\Application;
use Illuminate\Support\Facades\Facade;

/**
 * Boots a SECOND, independent application with the given module ENV overrides
 * and returns the providers it actually loaded.
 *
 * Why a second application rather than `config()->set()` : the whole point is to
 * exercise `AppServiceProvider::register()`, which reads `config('modules')`
 * during bootstrap. Once the test application is up, its providers are already
 * registered — mutating config afterwards proves nothing.
 *
 * ⚠️ `$_SERVER` is set as well as `putenv()`, and that is not belt-and-braces :
 * Laravel's `Env` helper consults **`$_SERVER` first**. Setting only `putenv()`
 * leaves `env()` returning the old value — the exact mechanism that let the whole
 * suite run on the development database until 2026-07-31.
 *
 * Creating an Application re-binds the global container instance, so the caller's
 * container and facades are restored in `finally`, otherwise every subsequent
 * test in the process would resolve against this throwaway app.
 *
 * @param  array<string, string>  $env
 * @return array<string, bool>  clés = FQCN des providers chargés
 */
function bootAppWithModuleEnv(array $env): array
{
    $previousContainer = Container::getInstance();
    /** @var array<string, string|null> $previousServer */
    $previousServer = [];

    foreach ($env as $key => $value) {
        // Resserré en string|null dès la capture : `$_SERVER` est `mixed`, et la
        // restauration réinjecte cette valeur dans une chaîne interpolée.
        $previousServer[$key] = isset($_SERVER[$key]) && is_scalar($_SERVER[$key])
            ? (string) $_SERVER[$key]
            : null;
        $_SERVER[$key] = $value;
        putenv("{$key}={$value}");
    }

    try {
        /** @var Application $app */
        $app = require base_path('bootstrap/app.php');
        $app->make(ConsoleKernel::class)->bootstrap();

        return $app->getLoadedProviders();
    } finally {
        foreach ($env as $key => $_) {
            if ($previousServer[$key] === null) {
                unset($_SERVER[$key]);
                putenv($key);
            } else {
                $_SERVER[$key] = $previousServer[$key];
                putenv("{$key}={$previousServer[$key]}");
            }
        }

        Container::setInstance($previousContainer);
        Facade::clearResolvedInstances();

        if ($previousContainer instanceof Application) {
            Facade::setFacadeApplication($previousContainer);
        }
    }
}

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

/*
|------------------------------------------------------------------------------
| Le flag ENV agit-il vraiment ? (trouvé par 0b, 2026-08-07)
|------------------------------------------------------------------------------
|
| Tout ce qui précède prouve le helper statique `moduleProviders()`, ou constate
| que la config PAR DÉFAUT démarre les 5 modules. Rien ne prouvait que
| `register()` consulte réellement `config('modules')`.
|
| Mutation qui le démontre : remplacer `$modules = config('modules');` par un
| tableau en dur tout-à-true. Le flag ENV devient totalement inerte — et, avant
| ces trois tests, les 58 tests de la suite passaient quand même.
|
| C'est ADR-0001 (« un fork-streamer désactive un module via ENV sans toucher au
| code ») sans référent exécutable : la promesse centrale du produit pouvait
| cesser de fonctionner sans qu'un seul test rougisse.
|
| Ces tests démarrent une VRAIE application. Ils sont plus lents que les
| assertions sur le helper, et c'est le prix à payer : le helper n'est pas le
| produit, le câblage l'est.
*/

it('refuses to conclude if the configuration is cached', function (): void {
    // Un `config:cache` fige config/modules.php dans bootstrap/cache/config.php :
    // le flag ENV n'est alors plus lu au boot, et les trois tests suivants
    // mesureraient le cache au lieu du mécanisme. Mieux vaut refuser que mentir.
    expect(file_exists(base_path('bootstrap/cache/config.php')))
        ->toBeFalse('Configuration mise en cache : lancez `php artisan config:clear` avant de conclure quoi que ce soit sur MODULE_*_ENABLED.');
});

it('really stops registering a module provider when its ENV flag is false', function (): void {
    $loaded = bootAppWithModuleEnv([
        'MODULE_LIVE_ENABLED' => 'false',
    ]);

    expect(array_key_exists(LiveServiceProvider::class, $loaded))
        ->toBeFalse('MODULE_LIVE_ENABLED=false mais LiveServiceProvider est chargé : le flag ENV est inerte.');

    // Les autres modules doivent rester debout — désactiver Live ne doit pas
    // désactiver le site. Sans cette moitié, un register() qui n'enregistre
    // RIEN passerait l'assertion ci-dessus.
    expect(array_key_exists(PublicServiceProvider::class, $loaded))
        ->toBeTrue('Désactiver Live a aussi emporté Public.');
    expect(array_key_exists(ReviewsServiceProvider::class, $loaded))
        ->toBeTrue('Désactiver Live a aussi emporté Reviews.');
    expect(array_key_exists(CoreServiceProvider::class, $loaded))
        ->toBeTrue('Core doit rester inconditionnel (bootstrap/providers.php).');
});

it('really stops registering several modules at once', function (): void {
    $loaded = bootAppWithModuleEnv([
        'MODULE_REVIEWS_ENABLED' => 'false',
        'MODULE_PRESS_KIT_ENABLED' => 'false',
    ]);

    expect(array_key_exists(ReviewsServiceProvider::class, $loaded))->toBeFalse();
    // press_kit → PressKit : la clé multi-mots est le cas où le Studly peut
    // diverger du nom de dossier, et où `class_exists()` avalerait l'erreur.
    expect(array_key_exists(PressKitServiceProvider::class, $loaded))->toBeFalse();
    expect(array_key_exists(LiveServiceProvider::class, $loaded))->toBeTrue();
    expect(array_key_exists(AdminServiceProvider::class, $loaded))->toBeTrue();
});

it('restores the caller container so the throwaway app leaks nothing', function (): void {
    $before = Container::getInstance();

    bootAppWithModuleEnv([
        'MODULE_LIVE_ENABLED' => 'false',
    ]);

    expect(Container::getInstance())->toBe($before);
    expect(array_key_exists('MODULE_LIVE_ENABLED', $_SERVER))
        ->toBeFalse();
    // L'application appelante doit rester utilisable : si les façades pointaient
    // encore sur l'app jetable, tout test ultérieur casserait de façon opaque.
    expect(config('modules.live'))
        ->not->toBeNull();
});
