<?php

declare(strict_types=1);

namespace App\Core\Providers;

use App\Core\Console\Commands\TenancyAssertCommand;
use App\Core\Http\Middleware\SetCurrentStreamer;
use App\Core\Support\CurrentStreamer;
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
class CoreServiceProvider extends ServiceProvider
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

        // app/Core/Console/Commands is outside Laravel's auto-discovery path
        // (app/Console/Commands), so Core commands are registered explicitly.
        $this->commands([
            TenancyAssertCommand::class,
        ]);
    }
}
