<?php

declare(strict_types=1);

namespace App\Core\Http\Middleware;

use App\Core\Exceptions\NoStreamerConfiguredException;
use App\Core\Models\Streamer;
use App\Core\Support\CurrentStreamer;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Schema;
use Symfony\Component\HttpFoundation\Response;

/**
 * Resolves the current streamer and binds it for the request (Pattern C —
 * ADR-0002, architecture §3.4). Pushed onto the `web` middleware group by
 * CoreServiceProvider.
 *
 * v1 mono-streamer: there is exactly one row (enforced by Story 1.5
 * `tenancy:assert`).
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * ⚠️ CE MIDDLEWARE COUVRE PLUS DE CHOSES QUE « LES PAGES DU SITE »
 *
 * Le groupe `web` porte aussi l'endpoint de mise à jour de Livewire
 * (`POST /livewire-<hash>/update`), unique pour toute l'application. Toute
 * interaction d'un composant Livewire y passe — Y COMPRIS LA SOUMISSION DU
 * FORMULAIRE DE CONNEXION DU PANEL `/admin`, dont les *pages*, elles, sont
 * servies hors du groupe `web` par la pile propre de Filament.
 *
 * C'est ce qui a fermé l'entrée ouverte de `deferred-work.md` : tant que l'échec
 * se présentait en 404, une base migrée non semée servait la page de connexion
 * en 200 et refusait la connexion en 404. Voir NoStreamerConfiguredException,
 * qui porte la démonstration complète.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * 🔴 ET POURQUOI LA LIAISON EST PARESSEUSE (décision D5, revue du 2026-08-20)
 *
 * Rendre l'échec diagnosticable ne l'avait pas SUPPRIMÉ. Sur une base migrée non
 * semée, la soumission du formulaire de connexion passait de 404 à 500 : mieux
 * nommé, tout aussi fermé. Or l'AC6 n'existe pas pour améliorer un message — elle
 * existe pour qu'un fork-streamer ne se retrouve pas enfermé dehors, « sans aucun
 * moyen de créer le streamer manquant, puisque la seule interface pour le faire
 * est ce panel ».
 *
 * ⛔ LA CORRECTION N'EST PAS D'EXCLURE L'ENDPOINT LIVEWIRE de ce middleware :
 * il est partagé par TOUS les composants de l'application, y compris les futurs
 * composants publics qui ont besoin du contexte tenant. On échangerait un échec
 * visible contre une fuite de contexte silencieuse.
 *
 * La correction est de ne plus RÉSOUDRE ce dont on n'a pas besoin. Le middleware
 * enregistre désormais un résolveur : la requête à la base n'a lieu que si
 * quelque chose demande réellement `CurrentStreamer`. Conséquences :
 *
 *   • la connexion au panel — qui ne touche aucun modèle tenant — aboutit sur
 *     une base vide, et l'opérateur peut enfin créer son streamer ;
 *   • une page publique qui résout le contexte lève toujours
 *     NoStreamerConfiguredException, nommée, en 500 ;
 *   • l'endpoint partagé n'est exclu de rien, donc aucun composant ne perd son
 *     contexte tenant.
 *
 * ⚠️ CONSÉQUENCE SUR LA CAMPAGNE DE MUTATION : la mutation M7 (« ajouter ce
 * middleware à la pile du panel ») ne rougit plus par le symptôme, puisque le
 * symptôme n'existe plus. Le garde-fou est devenu STRUCTUREL — `AdminPanelAccessTest`
 * assert que la pile du panel ne contient pas ce middleware. Rejoué le 2026-08-20.
 *
 * v2+ multi-streamer (Pattern D, ADR-0002) will enrich this with RLS /
 * `SET LOCAL` inside a transaction. NOT implemented here.
 */
final class SetCurrentStreamer
{
    /**
     * @param  Closure(Request): Response  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        // `scoped()` plutôt que `instance()` : la requête à la base est différée
        // jusqu'au premier `app(CurrentStreamer::class)`, et ré-enregistrer la
        // liaison à chaque requête écarte l'instance résolue de la précédente
        // (`dropStaleInstances`), donc aucun contexte ne fuit d'une requête à
        // l'autre — y compris sous une application persistante (tests, Octane).
        app()
            ->scoped(CurrentStreamer::class, static function (): CurrentStreamer {
                // « Pas migré » et « table vide » se ressemblent depuis un navigateur
                // et demandent deux commandes différentes. Sans ce test, le premier
                // cas rend une QueryException nue — un 500 sans remède dedans, soit
                // exactement le coût de diagnostic que ce chemin existe pour retirer.
                if (! Schema::hasTable('streamers')) {
                    throw NoStreamerConfiguredException::migrationsMissing();
                }

                // ⛔ PAS de `firstOrFail()` : sa ModelNotFoundException est rendue en
                // 404 par le handler, c'est-à-dire en « page inexistante ». L'échec doit
                // être une erreur serveur nommée, que la supervision voit.
                $streamer = Streamer::query()->orderBy('id')->first();

                if (! $streamer instanceof Streamer) {
                    throw NoStreamerConfiguredException::make();
                }

                return new CurrentStreamer($streamer);
            });

        return $next($request);
    }
}
