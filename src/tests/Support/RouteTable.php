<?php

declare(strict_types=1);

namespace Tests\Support;

use Illuminate\Contracts\Events\Dispatcher;
use Illuminate\Routing\RouteCollectionInterface;
use Illuminate\Routing\Router;
use Illuminate\Support\Facades\Route as RouteFacade;

/**
 * Rejoue `routes/web.php` contre un routeur neuf, dans l'environnement demandé.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * POURQUOI CETTE CLASSE EXISTE
 *
 * C'est le seul moyen honnête de vérifier une garde `app()->environment()` : les
 * routes sont enregistrées au boot, donc changer l'environnement après coup ne
 * prouve rien. On reconstruit un routeur, on force l'environnement, on ré-exécute
 * le fichier (`require`, pas `require_once` : il DOIT s'exécuter à nouveau), puis
 * on remet tout en place.
 *
 * Le mécanisme est né en Story 1.11 sous forme de closure locale à
 * BladeComponentsTest. La Story 1.13 ajoute deux routes de démonstration gardées
 * de la même façon : dupliquer 35 lignes délicates dans un second fichier de
 * tests aurait garanti qu'une des deux copies dérive en silence.
 */
final class RouteTable
{
    /**
     * Table de routage telle qu'elle serait construite dans `$environment`.
     */
    public static function registeredIn(string $environment): RouteCollectionInterface
    {
        $app = app();
        $detected = $app->environment();
        $previousEnvironment = is_string($detected) ? $detected : 'testing';
        $previousRouter = app(Router::class);

        $app->detectEnvironment(static fn (): string => $environment);

        $router = new Router(app(Dispatcher::class), $app);
        $app->instance('router', $router);
        RouteFacade::swap($router);

        try {
            // Portée isolée : `require` s'exécute dans le scope de l'appelant, donc
            // une future variable `$router` ou `$app` déclarée dans routes/web.php
            // écraserait celles d'ici — et le `finally` restaurerait un routeur
            // corrompu pour toute la suite.
            (static function (): void {
                require base_path('routes/web.php');
            })();

            // `Route::get(...)->name(...)` nomme la route APRÈS son ajout à la
            // collection : la table de correspondance nom → route est reconstruite
            // par le framework au `booted()`, jamais atteint ici. Sans ce
            // rafraîchissement, getByName() renvoie null pour TOUTES les routes et
            // le test serait vert en production pour la mauvaise raison.
            $router->getRoutes()
                ->refreshNameLookups();
        } finally {
            $app->detectEnvironment(static fn (): string => $previousEnvironment);
            $app->instance('router', $previousRouter);
            RouteFacade::swap($previousRouter);
        }

        return $router->getRoutes();
    }
}
