<?php

declare(strict_types=1);

namespace Tests\Support;

use Illuminate\Contracts\Auth\Authenticatable;
use Illuminate\Contracts\Http\Kernel;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Route as Router;
use RuntimeException;
use Symfony\Component\HttpFoundation\Response;

/**
 * Émet une VRAIE requête HTTP à travers le noyau de l'application, avec un
 * typage complet.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * POURQUOI CETTE CLASSE PLUTÔT QUE `$this->get()` / `$this->actingAs()`
 *
 * Dans une closure Pest, PHPStan résout `$this` en `Pest\PendingCalls\TestCall`
 * et non en `Tests\TestCase`. Au niveau 10, chaque `$this->get()` produit donc
 * deux à trois erreurs (« Call to an undefined method », puis « Cannot call
 * method … on mixed »). La Story 1.10a en a fabriqué 49 d'un coup, et le
 * ratchet du projet est à 0.
 *
 * La parade était déjà employée par `BladeComponentsTest` (Story 1.11), qui
 * appelait le noyau HTTP à la main avec ce motif écrit en toutes lettres. Cette
 * classe ne fait qu'extraire cette parade, pour la même raison que `RouteTable`
 * et `ModuleBoot` avant elle : elle est désormais employée par cinq fichiers de
 * tests, et cinq copies dérivent.
 *
 * ⚠️ Ce n'est PAS un contournement du typage : le noyau exécute le parcours
 * réel — pile de middleware complète, sessions, authentification, en-têtes de
 * réponse. C'est même plus fidèle que le client de test sur un point qui
 * compte pour cette story : les variables serveur passées ici arrivent
 * réellement dans la requête, ce qui permet d'observer `X-Forwarded-For` et
 * `REMOTE_ADDR` tels qu'un reverse-proxy les présente.
 */
final class HttpProbe
{
    /**
     * Exécute `GET $uri` et rend la réponse.
     *
     * @param  Authenticatable|null  $actingAs  utilisateur connecté sur le guard `web`,
     *                                          ou `null` pour une requête anonyme
     * @param  array<string, string>  $server  variables serveur (`REMOTE_ADDR`,
     *                                         `HTTP_X_FORWARDED_FOR`, …)
     */
    public static function get(string $uri, ?Authenticatable $actingAs = null, array $server = []): Response
    {
        self::authenticate($actingAs);

        return app(Kernel::class)->handle(
            Request::create($uri, 'GET', [], [], [], $server),
        );
    }

    /**
     * Exécute `POST $uri` avec un corps brut et rend la réponse.
     *
     * Sert à exercer les endpoints qui n'ont pas de page : celui de mise à jour
     * de Livewire, notamment, par lequel passe TOUTE interaction du panel — y
     * compris la soumission du formulaire de connexion.
     *
     * @param  array<string, string>  $server
     */
    public static function post(
        string $uri,
        string $body = '',
        array $server = [],
        ?Authenticatable $actingAs = null,
    ): Response {
        // ⚠️ MÊME SYMÉTRIE QUE `get()`, ET ELLE MANQUAIT (finding de revue, 2026-08-20).
        //
        // Le correctif Q12 avait posé le `logout()` sur `get()` seulement. Un
        // `post()` suivant un `get($uri, $user)` dans le même test tournait donc
        // ENCORE AUTHENTIFIÉ — sur l'endpoint qui porte TOUT le trafic du panel.
        // Le défaut réparé d'un côté restait ouvert de l'autre.
        self::authenticate($actingAs);

        return app(Kernel::class)->handle(
            Request::create($uri, 'POST', [], [], [], $server, $body),
        );
    }

    /**
     * Aligne la session sur ce que la sonde demande — connectée, ou franchement anonyme.
     */
    private static function authenticate(?Authenticatable $actingAs): void
    {
        if ($actingAs instanceof Authenticatable) {
            // On connecte sur le guard `web` explicitement plutôt que sur le
            // guard par défaut : c'est celui par lequel Filament authentifie
            // (AC9), et `auth.defaults.guard` est modifiable.
            Auth::guard('web')->login($actingAs);

            return;
        }

        Auth::guard('web')->logout();
    }

    /**
     * URI de l'endpoint de mise à jour de Livewire, lue dans la table de
     * routage plutôt que devinée : son segment est haché par version
     * (`livewire-6e95faa6/update`) et change avec le paquet.
     */
    public static function livewireUpdateUri(): string
    {
        // ⚠️ `->getRoutes()` DEUX FOIS, et ce n'est pas une maladresse :
        // `Route::getRoutes()` rend une `RouteCollectionInterface`, dont
        // l'itération directe n'est pas typée. Sa méthode `getRoutes()`, elle,
        // est déclarée `@return \Illuminate\Routing\Route[]` — c'est la seule
        // forme qui donne un `$route` typé, et donc l'unique façon de garder le
        // ratchet PHPStan à 0 sans annotation de complaisance.
        foreach (Router::getRoutes()->getRoutes() as $route) {
            if (str_starts_with($route->uri(), 'livewire') && str_ends_with($route->uri(), '/update')) {
                return '/' . $route->uri();
            }
        }

        throw new RuntimeException(
            'Aucune route de mise à jour Livewire dans la table de routage : les tests qui '
            . 'exercent le chemin de soumission du panel ne mesurent plus rien.',
        );
    }
}
