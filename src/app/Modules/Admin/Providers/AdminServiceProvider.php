<?php

declare(strict_types=1);

namespace App\Modules\Admin\Providers;

use Illuminate\Support\ServiceProvider;

/**
 * Admin module provider (ADR-0009). Registered conditionally by
 * AppServiceProvider when MODULE_ADMIN_ENABLED is truthy (config/modules.php).
 */
final class AdminServiceProvider extends ServiceProvider
{
    public function register(): void
    {
    }

    public function boot(): void
    {
        // Epic 9+/10 wires module-scoped routes/migrations/views + Filament
        // resources here (explicit registration, no auto-discovery — ADR-0009).
        //   $this->loadRoutesFrom(__DIR__ . '/../Routes/web.php');
        //   $this->loadMigrationsFrom(__DIR__ . '/../Database/migrations');
        // (paths/casing locked when the first module gains them — see story Open Questions)
    }
}
