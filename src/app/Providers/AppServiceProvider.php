<?php

declare(strict_types=1);

namespace App\Providers;

use App\HealthChecks\DatabaseHealthCheck;
use Illuminate\Support\ServiceProvider;
use Spatie\Health\Facades\Health;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        // FR3-5: Removed the boot-time HEALTH_SECRET_TOKEN throw — it was
        // redundant with Spatie Health's built-in `secret_token` config which
        // enforces auth at the HTTP route layer. The boot-time variant was also
        // dangerous (broke `artisan migrate` on first deploy, didn't trigger
        // under Octane due to runningInConsole() returning true). Operators
        // setting HEALTH_SECRET_TOKEN= in .env get a documented warning in the
        // Spatie Health route registration; production deployment checklists
        // should verify the env is set.

        Health::checks([
            DatabaseHealthCheck::new(),
        ]);
    }
}
