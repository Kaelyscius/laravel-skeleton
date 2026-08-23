<?php

declare(strict_types=1);

namespace App\HealthChecks\Support;

use Illuminate\Support\Facades\Log;
use Spatie\Health\Checks\Result;

/**
 * Portillon de joignabilité BORNÉ, commun aux trois sondes.
 *
 * Voir `BackendEndpoint` pour la mesure qui a rendu ce portillon nécessaire, et
 * pour ce qu'il borne réellement (le nombre de tentatives et la connexion — pas
 * la résolution de nom).
 *
 * ⛔ IL NE CONCLUT JAMAIS AU VERT. Il ne sait que dire « inutile d'aller plus
 * loin » ; quand il laisse passer, la sonde fait son aller-retour applicatif
 * complet, qui seul atteste l'authentification et l'écriture.
 */
trait BoundsBackendReachability
{
    /**
     * Rend un `Result` en échec quand le portillon refuse, sinon `null`.
     *
     * `null` couvre DEUX cas volontairement confondus, parce qu'ils appellent
     * la même suite : le backend a répondu au portillon, ou il n'y a pas de
     * portillon applicable (pilote sans point de terminaison TCP — `array`,
     * `sync`, `sqlite`, socket unix).
     */
    private function refuseIfUnreachable(?BackendEndpoint $endpoint, string $subject): ?Result
    {
        if (! $endpoint instanceof BackendEndpoint) {
            return null;
        }

        /*
         * ⚖️ PORTE DE SORTIE, ET ELLE A UNE RAISON PRÉCISE (revue 2) : sur un
         * hôte à plusieurs enregistrements A, `fsockopen()` n'essaie qu'une
         * adresse, donc le portillon peut refuser alors qu'une autre répondrait.
         * `HEALTH_PROBE_GATE=false` le désarme, au prix du retour aux ~10
         * tentatives du framework — c'est un arbitrage d'exploitation, pas un
         * interrupteur à poser par confort.
         */
        $enabled = config('health.probe_gate_enabled');

        if (is_bool($enabled) && ! $enabled) {
            return null;
        }

        if ($endpoint->isReachable(self::connectTimeoutSeconds())) {
            return null;
        }

        // 🔒 L'hôte et le port vont au JOURNAL, jamais dans le corps public.
        // ⚠️ La rédaction précédente justifiait cela par « `/health` n'est pas
        // authentifié (il est SEULEMENT LIMITÉ EN DÉBIT) » — or la limitation
        // de débit a été REPORTÉE par cette même story (revue 1), avec sa
        // raison écrite dans le docblock de la route. Phrase fausse à côté d'un
        // code juste ; relevée en revue 2. Le motif réel, et il suffit :
        // l'endpoint est PUBLIC et NON AUTHENTIFIÉ, donc il ne publie pas la
        // topologie interne.
        Log::error('Health probe gate refused', [
            'subject' => $subject,
            'endpoint' => $endpoint->label(),
        ]);

        return Result::make()
            ->failed(ucfirst($subject) . ' backend unreachable')
            ->shortSummary('Backend injoignable — portillon TCP borné');
    }

    /**
     * Délai maximal accordé à l'ouverture du socket, en secondes.
     *
     * ⚠️ LE DÉFAUT EST DANS LE CODE, PAS SEULEMENT DANS LA CONFIGURATION —
     * même raisonnement que le budget de la route : une valeur absente, nulle
     * ou négative rendrait le portillon inopérant (0 = « pas de limite » pour
     * `fsockopen`), c'est-à-dire exactement la panne qu'il existe pour éviter.
     */
    private static function connectTimeoutSeconds(): float
    {
        $configured = config('health.probe_connect_timeout_seconds');

        if (is_numeric($configured) && (float) $configured > 0.0) {
            return (float) $configured;
        }

        return 2.0;
    }
}
