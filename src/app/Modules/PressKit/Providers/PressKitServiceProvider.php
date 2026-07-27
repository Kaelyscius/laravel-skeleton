<?php

declare(strict_types=1);

namespace App\Modules\PressKit\Providers;

use Illuminate\Support\ServiceProvider;

/**
 * PressKit module provider (ADR-0009). Registered conditionally by
 * AppServiceProvider when MODULE_PRESS_KIT_ENABLED is truthy (config/modules.php).
 */
final class PressKitServiceProvider extends ServiceProvider
{
    public function register(): void
    {
    }

    public function boot(): void
    {
        // Epic 8+ wires module-scoped routes/migrations/views here, e.g.:
        //   $this->loadRoutesFrom(__DIR__ . '/../Routes/web.php');
        //   $this->loadMigrationsFrom(__DIR__ . '/../Database/migrations');
        // (paths/casing locked when the first module gains them — see story Open Questions)
    }
}
