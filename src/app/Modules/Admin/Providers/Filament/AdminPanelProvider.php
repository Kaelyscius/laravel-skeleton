<?php

declare(strict_types=1);

namespace App\Modules\Admin\Providers\Filament;

use Filament\Http\Middleware\Authenticate;
use Filament\Http\Middleware\AuthenticateSession;
use Filament\Http\Middleware\DisableBladeIconComponents;
use Filament\Http\Middleware\DispatchServingFilamentEvent;
use Filament\Pages\Dashboard;
use Filament\Panel;
use Filament\PanelProvider;
use Filament\Support\Colors\Color;
use Filament\Widgets\AccountWidget;
use Filament\Widgets\FilamentInfoWidget;
use Illuminate\Cookie\Middleware\AddQueuedCookiesToResponse;
use Illuminate\Cookie\Middleware\EncryptCookies;
use Illuminate\Foundation\Http\Middleware\PreventRequestForgery;
use Illuminate\Routing\Middleware\SubstituteBindings;
use Illuminate\Session\Middleware\StartSession;
use Illuminate\View\Middleware\ShareErrorsFromSession;

/**
 * Panel Filament `/admin` — la seule surface authentifiée du produit.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * POURQUOI CE FICHIER N'EST PAS LÀ OÙ FILAMENT L'A ÉCRIT
 *
 * `php artisan filament:install --panels` génère
 * `app/Providers/Filament/AdminPanelProvider.php` et l'enregistre dans
 * `bootstrap/providers.php`. Les deux sont contraires à ADR-0009 :
 *
 *   • l'arborescence cible assigne à `app/Modules/Admin/` la mention littérale
 *     « Filament panels + Sanctum + Spatie Permission » ;
 *   • `bootstrap/providers.php` est INCONDITIONNEL par construction, alors
 *     qu'ADR-0009 §Conséquences promet qu'« un module désactivé via ENV ne
 *     charge ni ses routes, ni ses migrations, ni ses Filament resources ».
 *
 * Mesuré le 2026-08-09, avant déplacement : avec `MODULE_ADMIN_ENABLED=false`,
 * `GET /admin` répondait **302** (redirection vers la page de connexion) au
 * lieu de 404. La promesse d'ADR-0001 — « un fork-streamer désactive un module
 * via ENV sans toucher au code » — était donc fausse pour le module le plus
 * sensible, et aucun test ne pouvait le dire.
 *
 * L'enregistrement se fait désormais depuis `AdminServiceProvider::register()`,
 * lui-même conditionné par `AppServiceProvider::register()` d'après
 * `config/modules.php`. Gardé par `tests/Feature/AdminPanelModuleGateTest.php`.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * ⛔ PAS DE `discoverResources()` / `discoverPages()` / `discoverWidgets()`
 *
 * Le squelette généré par Filament les appelle sur `app_path('Filament/…')`.
 * Trois raisons de les avoir retirés, dans cet ordre :
 *
 *   1. ADR-0009 §Conventions interdites nomme explicitement « Discovery
 *      automatique Filament resources — registration explicite par module ».
 *   2. Ces chemins pointent hors de tout module (`app/Filament/`), donc vers un
 *      emplacement qu'aucun `MODULE_*_ENABLED` ne gouverne : une resource y
 *      serait chargée quel que soit l'état du module qui la revendique.
 *   3. Ils désignent aujourd'hui des répertoires INEXISTANTS. Une découverte qui
 *      scanne le vide est un mécanisme vert sans référent — le motif dominant de
 *      ce projet. Epic 5 enregistrera ses resources nommément, ici.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * ⛔ PAS DE `SetCurrentStreamer` DANS LA PILE DE MIDDLEWARE — C'EST UNE DÉCISION
 *
 * Filament construit sa propre pile pour SES PROPRES ROUTES (`/admin`,
 * `/admin/login`) : celles-là ne traversent pas le groupe `web`, donc
 * `SetCurrentStreamer` ne s'y exécute pas. C'est VOULU en v1 — aucun modèle
 * tenant ne vit dans le panel avant l'Epic 5 — et l'ajouter ici couvrirait
 * l'affichage des pages sans rien régler du reste.
 *
 * ⚠️ CE QUE CETTE PHRASE NE DIT PAS, ET QUI A COÛTÉ UNE CONCLUSION FAUSSE.
 * « Le panel ne traverse pas `web` » n'est vrai que des routes ci-dessus. Toute
 * INTERACTION du panel — à commencer par la soumission du formulaire de
 * connexion — est une requête Livewire, et Livewire n'a qu'UN endpoint de mise
 * à jour pour toute l'application, qui est dans le groupe `web` :
 *
 *   POST /livewire-<hash>/update  →  ['web', RequireLivewireHeaders]
 *
 * Mesuré en revue le 2026-08-10 (Filament ne surcharge pas cette route). Sur
 * une base migrée non semée, la page de connexion s'affichait donc en 200 et la
 * connexion échouait en **404** — l'impasse que l'AC6 existe pour empêcher,
 * atteinte par une autre porte.
 *
 * ⛔ La correction n'était PAS d'exclure cette route du middleware tenant : elle
 * est partagée par tous les composants Livewire, y compris les futurs
 * composants publics qui ont besoin du contexte. Elle était en amont — le
 * `firstOrFail()` a été remplacé par `NoStreamerConfiguredException`, rendue en
 * 500 nommé, ce qui a fermé l'entrée ouverte de `deferred-work.md`.
 *
 * Gardé par trois tests d'`AdminPanelAccessTest` : la page en 200, l'endpoint
 * d'interaction qui ne rend pas 404, et le contre-test « avec un streamer, plus
 * de 500 ».
 *
 * @see docs/adr/ADR-0009-modular-app-modules-psr4.md
 * @see docs/adr/ADR-0010-laravel-13-supersedes-filament-v3-lock.md
 */
final class AdminPanelProvider extends PanelProvider
{
    public function panel(Panel $panel): Panel
    {
        return $panel
            ->default()
            ->id('admin')
            ->path('admin')
            ->login()
            ->colors([
                // Palette laissée telle que générée : le thème du panel n'a
                // aucun AC dans la Story 1.10a, et l'habiller avant qu'une
                // seule resource n'existe fabriquerait de la dette visuelle
                // (§10 « hors périmètre »). Le panel est interne et
                // desktop-first (NFR-Mobile-2).
                'primary' => Color::Amber,
            ])
            ->pages([
                Dashboard::class,
            ])
            ->widgets([
                AccountWidget::class,
                FilamentInfoWidget::class,
            ])
            ->middleware([
                EncryptCookies::class,
                AddQueuedCookiesToResponse::class,
                StartSession::class,
                AuthenticateSession::class,
                ShareErrorsFromSession::class,
                PreventRequestForgery::class,
                SubstituteBindings::class,
                DisableBladeIconComponents::class,
                DispatchServingFilamentEvent::class,
            ])
            ->authMiddleware([
                Authenticate::class,
            ]);
    }
}
