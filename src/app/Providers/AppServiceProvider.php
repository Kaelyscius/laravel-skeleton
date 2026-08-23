<?php

declare(strict_types=1);

namespace App\Providers;

use App\HealthChecks\CacheHealthCheck;
use App\HealthChecks\DatabaseHealthCheck;
use App\HealthChecks\QueueHealthCheck;
use Illuminate\Support\ServiceProvider;
use Illuminate\Support\Str;
use Spatie\Health\Facades\Health;

final class AppServiceProvider extends ServiceProvider
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

        /*
         * ─────────────────────────────────────────────────────────────────────
         * PAS DE `Carbon::setLocale()` ICI, ET C'EST UNE DÉCISION (Story 1.12, AC1)
         *
         * L'AC1 exigeait cette ligne, sur la foi d'un `grep LocaleUpdated`
         * restreint à `vendor/laravel/framework/`. Le framework, en effet,
         * n'écoute pas cet évènement. Mais CARBON, LUI, L'ÉCOUTE : il embarque
         * son propre provider Laravel, auto-découvert par Composer —
         *
         *   vendor/nesbot/carbon/src/Carbon/Laravel/ServiceProvider.php
         *     boot()  → updateLocale() depuis app('translator')
         *     puis    → listen(LocaleUpdated) → updateLocale()
         *
         * Constaté par la campagne de mutation du 2026-08-08 : retirer la ligne
         * ne faisait rougir AUCUN test. Elle ne gardait rien — la propriété
         * était déjà vraie, et le référent se trouvait un répertoire plus loin
         * que là où la story avait regardé.
         *
         * La conserver serait donc une SECONDE SOURCE DE VÉRITÉ, et strictement
         * plus faible que celle qui existe : posée une fois au boot, elle ne
         * suivrait pas un `app()->setLocale()` à chaud, là où le listener de
         * Carbon le suit.
         *
         * Ce qui manquait vraiment, et qui existe désormais : les DEUX TESTS qui
         * OBSERVENT la propriété (tests/Feature/TimeAsTextureTest.php, AC1). Ils
         * rougissent si l'auto-découverte du provider de Carbon est désactivée —
         * vu rouge via `extra.laravel.dont-discover`.
         */

        /*
         * ─────────────────────────────────────────────────────────────────────
         * LES TROIS SONDES DE `/health` (Story 2.4)
         *
         * Jusqu'ici UNE seule sonde était enregistrée, et AUCUNE route ne
         * l'exposait : `/health` rendait un JSON littéral de 93 octets qui
         * disait `ok` la base à terre. Un garde-fou incapable de rougir.
         *
         * ⛔ LES NOMS SONT POSÉS EXPLICITEMENT, ET C'EST STRUCTUREL.
         * `Check::getName()` dérive du nom de classe : `DatabaseHealthCheck`
         * donnerait `DatabaseHealth`, donc la clé JSON `database_health`. La
         * route publie `Str::snake($check->getName())` ; ces trois littéraux
         * sont donc le CONTRAT de la réponse, et `HealthEndpointTest` les gèle.
         * Renommer une classe ne doit pas renommer une clé publique.
         */
        Health::checks([
            DatabaseHealthCheck::new()->name('database'),
            CacheHealthCheck::new()->name('cache'),
            QueueHealthCheck::new()->name('queue'),
        ]);
    }
}
