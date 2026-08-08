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

    /*
     * Démonstration des layouts (Story 1.13, T7) — même double garde, et pour
     * les mêmes raisons. Deux pages distinctes plutôt qu'une : l'AC2 est une
     * assertion d'ABSENCE de header et de footer, qui ne veut rien dire sur un
     * document qui en porterait par ailleurs.
     *
     * ⛔ Ces routes ne réutilisent PAS `_components-demo` : les 8 tests
     * navigateur de la Story 1.11 dépendent de son ordre de tabulation.
     */
    Route::get('/_layouts', function () {
        abort_unless(app()->environment(['local', 'testing']), 404);

        return view('_layouts-demo');
    })->name('layouts.demo');

    Route::get('/_layouts-minimal', function () {
        abort_unless(app()->environment(['local', 'testing']), 404);

        return view('_layouts-demo-minimal');
    })->name('layouts.demo.minimal');

    /*
     * Démonstration des composants time-as-texture (Story 1.12, T10) — même
     * double garde, et pour les mêmes raisons.
     *
     * Les instants sont calculés ICI plutôt que dans la vue : une page qui
     * fabrique ses propres données est une page dont on ne sait plus ce qu'elle
     * observe.
     */
    Route::get('/_time', function () {
        abort_unless(app()->environment(['local', 'testing']), 404);

        return view('_time-demo', [
            // Une seconde : c'est ce qui rend le rafraîchissement observable en
            // une seconde plutôt qu'en une minute. Un élément vieux de 59
            // minutes rendrait le MÊME libellé à chaque tick pendant 60 s, et
            // « le texte a changé » ne serait jamais vrai.
            'ticking' => now()
                ->subSeconds(1),
            /*
             * Un instant RÉCENT et lisible pour les deux sondes de chemin
             * d'erreur (#time-broken-refresh, #time-broken-iso) : il faut qu'un
             * recalcul réussi soit distinguable du marqueur serveur, donc un
             * instant que le JS sait formater.
             *
             * ⚠️ Ce n'est PAS le référent de l'AC8 — le commentaire d'origine le
             * disait et c'était faux (relevé à la revue du 2026-08-08). Le test
             * de largeur pose lui-même 3540 s puis 3600 s sur #time-fast et ne
             * lit jamais cette valeur.
             */
            'recent' => now()
                ->subMinutes(59),
            'ancient' => now()
                ->subMonths(7),
            'published' => now()
                ->subMonths(8),
            'updated' => now()
                ->subMonths(2),
        ]);
    })->name('time.demo');
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
