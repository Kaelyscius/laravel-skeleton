<?php

declare(strict_types=1);

namespace App\Providers;

use App\HealthChecks\DatabaseHealthCheck;
use Illuminate\Support\ServiceProvider;
use Illuminate\Support\Str;
use Spatie\Health\Facades\Health;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     *
     * Conditionally registers each deactivatable module's service provider
     * based on config/modules.php (ADR-0001/0009). Core stays unconditional in
     * bootstrap/providers.php. The class_exists() guard keeps a fork that
     * removed a module directory from fataling.
     */
    public function register(): void
    {
        /** @var array<string, mixed> $modules */
        $modules = is_array(config('modules')) ? config('modules') : [];

        foreach (self::moduleProviders($modules) as $provider) {
            if (class_exists($provider)) {
                $this->app->register($provider);
            }
        }
    }

    /**
     * Map enabled module config keys to their service-provider FQCNs.
     *
     * Falsy values (false / 0 / '' / null) are dropped, so a disabled module is
     * never registered. Snake_case keys are Studly-cased (press_kit → PressKit).
     *
     * @param  array<string, mixed>  $modules
     * @return array<int, string>
     */
    public static function moduleProviders(array $modules): array
    {
        return collect($modules)
            ->filter()
            ->keys()
            ->map(fn ($key): string => 'App\\Modules\\' . Str::studly((string) $key)
                . '\\Providers\\' . Str::studly((string) $key) . 'ServiceProvider')
            ->all();
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
