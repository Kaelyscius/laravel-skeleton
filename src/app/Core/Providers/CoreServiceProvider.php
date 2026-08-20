<?php

declare(strict_types=1);

namespace App\Core\Providers;

use App\Core\Console\Commands\ProxiesCheckCommand;
use App\Core\Console\Commands\TenancyAssertCommand;
use App\Core\Http\Middleware\SetCurrentStreamer;
use App\Core\Support\CurrentStreamer;
use App\Core\Support\TrustedProxies;
use Illuminate\Http\Middleware\TrustProxies;
use Illuminate\Routing\Router;
use Illuminate\Support\ServiceProvider;
use RuntimeException;

/**
 * Wires the always-active Core layer (ADR-0009): tenancy Pattern C plumbing.
 *
 * Registered unconditionally in bootstrap/providers.php — Core is transversal,
 * never gated by config/modules.php (which is only for deactivatable modules,
 * Story 1.7).
 */
final class CoreServiceProvider extends ServiceProvider
{
    /**
     * Fail-loud default for the tenant context: resolving CurrentStreamer before
     * SetCurrentStreamer has bound an instance (console, or a route outside the
     * web group) throws explicitly instead of leaking a default tenant.
     */
    public function register(): void
    {
        $this->app->bind(CurrentStreamer::class, function (): never {
            throw new RuntimeException(
                'CurrentStreamer is not bound for this request. The SetCurrentStreamer '
                . 'middleware must run before any tenant-scoped query (web group only).',
            );
        });
    }

    public function boot(): void
    {
        $this->app->make(Router::class)->pushMiddlewareToGroup('web', SetCurrentStreamer::class);

        $this->trustConfiguredProxies();

        // app/Core/Console/Commands is outside Laravel's auto-discovery path
        // (app/Console/Commands), so Core commands are registered explicitly.
        $this->commands([
            ProxiesCheckCommand::class,
            TenancyAssertCommand::class,
        ]);
    }

    /**
     * Hands `config('proxies.at')` to the TrustProxies middleware.
     *
     * ⛔ THIS IS WHY IT IS NOT IN `bootstrap/app.php`, and the reason was MEASURED,
     * not deduced. `withMiddleware()` registers its callback on
     * `afterResolving(HttpKernel::class)`, and `Application::handleRequest()`
     * resolves the kernel BEFORE calling `$kernel->handle()` — which is what
     * bootstraps the framework. Probed on this stack on 2026-08-20:
     * `app()->bound('config')` is `false` inside that callback. So neither `env()`
     * nor `config()` can be read there; the previous fix `require`d
     * `config/proxies.php` from inside it, which re-evaluated `env()` after
     * bootstrap and therefore fell back to the default under `config:cache` — the
     * production path, and the only one that matters here. Finding Q1, 2026-08-20.
     *
     * A provider boots after `LoadConfiguration`, so this reads the real value,
     * including when it comes from the configuration cache. `TrustProxies` keeps
     * it in a static that `handle()` consults per request, so setting it here is
     * in time for every request.
     *
     * Guarded by `tests/Feature/AdminPanelRateLimitTest.php` — the guard asserts
     * the value the middleware actually holds, not merely that a config key exists.
     */
    private function trustConfiguredProxies(): void
    {
        /** @var string|array<int, string> $at */
        $at = config('proxies.at', TrustedProxies::TRUST_NOBODY);

        TrustProxies::at($at);
    }
}
