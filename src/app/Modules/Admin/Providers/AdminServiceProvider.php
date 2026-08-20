<?php

declare(strict_types=1);

namespace App\Modules\Admin\Providers;

use App\Modules\Admin\Providers\Filament\AdminPanelProvider;
use Illuminate\Support\ServiceProvider;

/**
 * Admin module provider (ADR-0009). Registered conditionally by
 * AppServiceProvider when MODULE_ADMIN_ENABLED is truthy (config/modules.php).
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * ARBORESCENCE ET CASSE — FIGÉES ICI (Story 1.10a)
 *
 * Ce commentaire annonçait « paths/casing locked when the first module gains
 * them ». C'est fait : `Admin` est le premier module à recevoir du code réel,
 * et les conventions arrêtées sont celles employées ci-dessous.
 *
 *   app/Modules/<Module>/Providers/<Module>ServiceProvider.php   (existant)
 *   app/Modules/<Module>/Providers/Filament/<Module>PanelProvider.php
 *
 * Sous-répertoire `Providers/Filament/` plutôt qu'un `Filament/` de premier
 * niveau : le PanelProvider EST un service provider, et le ranger ailleurs
 * dissocierait le fichier de sa nature. Les resources Filament de l'Epic 5
 * iront, elles, sous `app/Modules/<Module>/Filament/Resources/` — ce sont des
 * écrans, pas des providers.
 *
 * Les chemins encore commentés dans `boot()` (Routes, Database/migrations)
 * restent des propositions : ils seront figés par la première story qui les
 * emploie, exactement comme celle-ci vient de figer les deux ci-dessus. Un
 * chemin écrit avant son premier usage est une affirmation sans référent.
 */
final class AdminServiceProvider extends ServiceProvider
{
    /**
     * Enregistre le panel Filament `/admin` DANS le module.
     *
     * C'est ce qui rend `MODULE_ADMIN_ENABLED=false` opérant sur le panel :
     * ce provider n'est lui-même enregistré que si le module est actif, donc le
     * PanelProvider ne l'est pas non plus, donc aucune route de panel n'existe.
     *
     * `AppServiceProvider::register()` appelle `$this->app->register()` pendant
     * la phase d'enregistrement ; enregistrer à son tour ici est le même
     * mécanisme une couche plus bas, pas une invention.
     */
    public function register(): void
    {
        $this->app->register(AdminPanelProvider::class);
    }

    public function boot(): void
    {
        // Epic 5+ wires module-scoped routes/migrations/views + Filament
        // resources here (explicit registration, no auto-discovery — ADR-0009).
        //   $this->loadRoutesFrom(__DIR__ . '/../Routes/web.php');
        //   $this->loadMigrationsFrom(__DIR__ . '/../Database/migrations');
    }
}
