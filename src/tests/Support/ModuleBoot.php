<?php

declare(strict_types=1);

namespace Tests\Support;

use Illuminate\Container\Container;
use Illuminate\Contracts\Console\Kernel as ConsoleKernel;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Bootstrap\LoadEnvironmentVariables;
use Illuminate\Routing\Router;
use Illuminate\Support\Facades\Facade;

/**
 * Démarre une SECONDE application indépendante avec des surcharges ENV, et
 * laisse l'appelant l'observer pendant qu'elle est vivante.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * POURQUOI CETTE CLASSE EXISTE (extraction, Story 1.10a)
 *
 * Le mécanisme est né dans `tests/Feature/ModuleActivationTest.php` (Story 1.7,
 * durci par la 0b). La Story 1.10a a besoin d'exactement la même chose pour
 * prouver que `MODULE_ADMIN_ENABLED=false` éteint le panel Filament — mais elle
 * a besoin d'observer autre chose que la liste des providers : la table de
 * routage, et le code de statut d'une vraie requête.
 *
 * Deux options se présentaient. Recopier les 60 lignes dans un second fichier
 * de tests, ou les extraire ici. C'est la deuxième, pour le motif déjà écrit en
 * toutes lettres par `RouteTable` — le précédent de la Story 1.13 :
 * « dupliquer 35 lignes délicates dans un second fichier de tests aurait
 * garanti qu'une des deux copies dérive en silence ». Ces lignes-ci sont plus
 * délicates encore : elles portent trois pièges déjà payés (ci-dessous).
 *
 * Effet de bord voulu et nécessaire : un fichier de tests peut désormais
 * s'exécuter SEUL (`php artisan test tests/Feature/AdminPanelTest.php`). Une
 * fonction déclarée au sommet d'un autre fichier de tests n'existe que si ce
 * fichier-là est chargé dans la même exécution — la dépendance aurait été
 * invisible jusqu'au jour où quelqu'un lance un seul fichier.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * LES TROIS PIÈGES QUE CE CODE PORTE, ET QUI ONT TOUS ÉTÉ PAYÉS
 *
 * 1. `$_SERVER` est écrit EN PLUS de `putenv()`. Le helper `Env` de Laravel
 *    consulte `$_SERVER` **en premier** : n'écrire que `putenv()` laisse `env()`
 *    rendre l'ancienne valeur. C'est le mécanisme qui a laissé toute la suite
 *    tourner sur la base de développement jusqu'au 2026-07-31.
 *
 * 2. Poser les variables AVANT le bootstrap ne suffit pas : le bootstrapper
 *    `LoadEnvironmentVariables` lit `.env` ensuite, et gagne. Or `.env.example`
 *    déclare `MODULE_LIVE_ENABLED=true` et la CI reconstruit `.env` depuis lui —
 *    les tests passaient en local et échouaient en CI. Les surcharges sont donc
 *    REJOUÉES juste après le chargement du `.env`.
 *
 * 3. `$_ENV` est capturé et restauré aussi. Le rappel `afterBootstrapping` y
 *    écrit ; ne pas le restaurer faisait fuiter le module éteint sur le test
 *    SUIVANT, qui échouait alors sur une assertion sans rapport (2026-08-07).
 *
 * Créer une Application re-lie l'instance globale du conteneur : le conteneur
 * et les façades de l'appelant sont restaurés dans `finally`, sinon tout test
 * ultérieur résoudrait contre cette application jetable.
 */
final class ModuleBoot
{
    /**
     * Démarre l'application jetable et rend ce que `$observe` en a extrait.
     *
     * `$observe` est appelé pendant que l'application jetable est le conteneur
     * courant — c'est le seul instant où l'observer a un sens. Par défaut, on
     * rend la liste des providers chargés, qui était le seul besoin de la
     * Story 1.7.
     *
     * @param  array<string, string>  $env
     * @param  (callable(Application): mixed)|null  $observe
     */
    public static function withEnv(array $env, ?callable $observe = null): mixed
    {
        $previousContainer = Container::getInstance();
        /** @var array<string, string|null> $previousServer */
        $previousServer = [];
        /** @var array<string, string|null> $previousEnv */
        $previousEnv = [];

        foreach ($env as $key => $value) {
            // Resserré en string|null dès la capture : `$_SERVER` est `mixed`, et la
            // restauration réinjecte cette valeur dans une chaîne interpolée.
            $previousServer[$key] = isset($_SERVER[$key]) && is_scalar($_SERVER[$key])
                ? (string) $_SERVER[$key]
                : null;
            $previousEnv[$key] = isset($_ENV[$key]) && is_scalar($_ENV[$key])
                ? (string) $_ENV[$key]
                : null;
            $_SERVER[$key] = $value;
            putenv("{$key}={$value}");
        }

        try {
            /** @var Application $app */
            $app = require base_path('bootstrap/app.php');

            // Rejoue les surcharges APRÈS que `.env` a été lu, sinon `.env` gagne.
            $app->afterBootstrapping(LoadEnvironmentVariables::class, function () use ($env): void {
                foreach ($env as $key => $value) {
                    $_SERVER[$key] = $value;
                    $_ENV[$key] = $value;
                    putenv("{$key}={$value}");
                }
            });

            $app->make(ConsoleKernel::class)->bootstrap();

            if ($observe === null) {
                return $app->getLoadedProviders();
            }

            return $observe($app);
        } finally {
            foreach ($env as $key => $_) {
                if ($previousServer[$key] === null) {
                    unset($_SERVER[$key]);
                    putenv($key);
                } else {
                    $_SERVER[$key] = $previousServer[$key];
                    putenv("{$key}={$previousServer[$key]}");
                }

                if ($previousEnv[$key] === null) {
                    unset($_ENV[$key]);
                } else {
                    $_ENV[$key] = $previousEnv[$key];
                }
            }

            Container::setInstance($previousContainer);
            Facade::clearResolvedInstances();

            if ($previousContainer instanceof Application) {
                Facade::setFacadeApplication($previousContainer);
            }
        }
    }

    /**
     * Providers réellement chargés par une application démarrée avec `$env`.
     *
     * @param  array<string, string>  $env
     * @return array<string, bool>  clés = FQCN des providers chargés
     */
    public static function loadedProviders(array $env): array
    {
        /** @var array<string, bool> $loaded */
        $loaded = self::withEnv($env);

        return $loaded;
    }

    /**
     * URIs de toutes les routes enregistrées par une application démarrée avec `$env`.
     *
     * Observer la table de routage plutôt que les seuls providers est ce qui
     * distingue « le provider n'est pas chargé » de « la surface HTTP n'existe
     * pas ». Les deux sont dans l'AC2 de la Story 1.10a parce qu'ils peuvent
     * diverger : un panel enregistré depuis `bootstrap/providers.php` ne se
     * voit pas dans les providers de module, mais se voit ici.
     *
     * @param  array<string, string>  $env
     * @return array<int, string>
     */
    public static function routeUris(array $env): array
    {
        /** @var array<int, string> $uris */
        $uris = self::withEnv($env, static function (Application $app): array {
            $uris = [];

            $router = $app->make(Router::class);

            foreach ($router->getRoutes()->getRoutes() as $route) {
                $uris[] = $route->uri();
            }

            return $uris;
        });

        return $uris;
    }
}
