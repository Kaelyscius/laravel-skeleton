<?php

declare(strict_types=1);

use App\Core\Support\CurrentStreamer;
use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('welcome');
});

/*
 * Galerie des composants de base (Story 1.11, T9) — support des tests navigateur.
 *
 * Les AC1/AC2/AC6 exigent des états observés PAR VALEUR CALCULÉE (hover, active,
 * focus-visible sont des pseudo-états : la présence d'une classe ne prouve rien
 * du rendu). Il faut donc une page réelle que Chromium peut charger.
 *
 * ⚠️ DEUX gardes, et la seconde n'est pas de la ceinture-bretelles.
 *
 *  1. À l'ENREGISTREMENT : la route n'existe pas hors local/testing. Vérifiée
 *     par BladeComponentsTest, qui rejoue ce fichier contre un routeur neuf en
 *     environnement `production` — test VU ROUGE en retirant le `if`.
 *  2. À la REQUÊTE : `php artisan route:cache` fige la table de routage au
 *     moment où il tourne. Un cache construit en local puis déployé embarquerait
 *     la route malgré la garde n°1, et aucun test ne pourrait le voir — c'est
 *     exactement la forme « l'affirmation précède son référent ». Le abort()
 *     ci-dessous est évalué à chaque requête, donc il survit au cache.
 */
if (app()->environment(['local', 'testing'])) {
    Route::get('/_components', function () {
        abort_unless(app()->environment(['local', 'testing']), 404);

        return view('_components-demo', [
            'streamer' => app(CurrentStreamer::class)->streamer(),
        ]);
    })->name('components.demo');
}

// Route de healthcheck pour Docker
Route::get('/health', function () {
    return response()->json([
        'status' => 'ok',
        'timestamp' => now()
            ->toISOString(),
        'service' => 'laravel',
        'app' => config('app.name', 'Laravel'),
    ]);
});
