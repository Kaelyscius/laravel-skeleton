<?php

declare(strict_types=1);

namespace App\HealthChecks;

use App\HealthChecks\Support\BackendEndpoint;
use App\HealthChecks\Support\BoundsBackendReachability;
use Illuminate\Contracts\Cache\Repository;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;
use Random\RandomException;
use Spatie\Health\Checks\Check;
use Spatie\Health\Checks\Result;
use Throwable;

/**
 * Atteste que le magasin de cache par défaut ACCEPTE puis REND une valeur.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * POURQUOI UN ALLER-RETOUR, ET PAS UN `ping`
 *
 * Un `ping` prouve qu'un socket répond. Il ne prouve pas que le magasin écrit :
 * un Redis en `MISCONF` (persistance en échec) répond `PONG` et REFUSE toute
 * écriture ; un magasin `file` dont le répertoire est passé en lecture seule
 * accepte l'appel `put()` — qui rend `false` sans lever — et rend `null` à la
 * lecture. Les deux cas produisent une application cassée derrière un socket
 * sain. La sonde écrit donc une clé éphémère, la relit, et COMPARE.
 *
 * ⚠️ LA COMPARAISON EST LE GARDE, PAS L'ABSENCE D'EXCEPTION. C'est la seule
 * assertion qui distingue « le backend a pris ma valeur » de « le backend n'a
 * pas protesté ». Retirer la comparaison rend la sonde verte sur un magasin qui
 * n'écrit rien — le mode de défaillance exact que cette story existe pour ne
 * plus produire.
 *
 * ⛔ CE QUE LA SONDE N'ATTESTE PAS : ni le taux de succès du cache applicatif,
 * ni la mémoire disponible, ni l'éviction. Elle dit « le backend répond et
 * conserve », rien de plus (cf. le docblock de la route `/health`).
 *
 * 🔒 SCRUB — même règle que `DatabaseHealthCheck` : le message d'exception n'est
 * JAMAIS journalisé. Les exceptions des pilotes de cache embarquent l'hôte, le
 * port et parfois le mot de passe (`predis` compose « tcp://redis:6379 » dans
 * son message ; `PDOException` y met le DSN complet). On journalise la CLASSE et
 * le NOM DE MAGASIN — une clé de configuration, pas un identifiant.
 *
 * ⏱️ BORNE TEMPORELLE : voir le docblock de la route `/health`, qui énonce ce
 * qui borne réellement chaque sonde et ce qui ne la borne pas.
 */
final class CacheHealthCheck extends Check
{
    use BoundsBackendReachability;

    /**
     * Durée de vie de la clé de sonde, en secondes.
     *
     * Volontairement courte mais non nulle : le `forget()` du `finally`
     * peut échouer (backend qui vient de tomber entre l'écriture et le
     * nettoyage), et cette TTL est alors le seul ramasse-miettes.
     */
    private const PROBE_TTL_SECONDS = 10;

    public function run(): Result
    {
        $storeName = self::defaultStoreName();

        // ⛔ Portillon borné d'abord (voir `BackendEndpoint`) : sans lui, un
        // magasin `database` ou `redis` dont l'hôte ne résout plus coûte la
        // même tempête de reconnexions que la sonde base.
        $gate = $this->refuseIfUnreachable(BackendEndpoint::forCacheStore(), 'cache');

        if ($gate instanceof Result) {
            return $gate;
        }

        try {
            $key = 'health-check:cache:' . bin2hex(random_bytes(8));
            $value = bin2hex(random_bytes(8));
        } catch (RandomException $e) {
            // Un CSPRNG indisponible n'est pas une panne de cache : le dire.
            Log::error('CacheHealthCheck could not build a probe key', [
                'type' => $e::class,
            ]);

            return Result::make()
                ->failed('Cache probe could not be generated')
                ->shortSummary('Sonde non générable');
        }

        $store = null;

        try {
            $store = Cache::store();
            $store->put($key, $value, self::PROBE_TTL_SECONDS);

            if ($store->get($key) !== $value) {
                return Result::make()
                    ->failed('Cache store did not return the value it was given')
                    ->shortSummary('Écriture acceptée, relecture incohérente');
            }

            return Result::make()
                ->ok()
                ->shortSummary('Backend joignable (aller-retour écriture/lecture)');
        } catch (Throwable $e) {
            Log::error('CacheHealthCheck failed', [
                'type' => $e::class,
                'store' => $storeName,
            ]);

            return Result::make()
                ->failed('Cache backend unreachable')
                ->shortSummary('Backend injoignable');
        } finally {
            if ($store instanceof Repository) {
                self::forgetQuietly($store, $key);
            }
        }
    }

    /**
     * Nom du magasin par défaut, pour le journal — jamais ses identifiants.
     */
    private static function defaultStoreName(): string
    {
        $configured = config('cache.default');

        return is_string($configured) ? $configured : '(non résolu)';
    }

    /**
     * Retire la clé de sonde sans jamais faire échouer la sonde.
     *
     * Le silence est VOLONTAIRE et ne doit pas être « corrigé », pour la même
     * raison que `DatabaseHealthCheck::resetStatementTimeout()` : ce nettoyage
     * tourne précisément quand le backend vient d'échouer, et journaliser ici
     * produirait une ligne par sonde pendant toute la durée d'une panne — soit
     * exactement le moment où les journaux doivent rester lisibles. La TTL de
     * la clé garantit de toute façon sa disparition.
     */
    private static function forgetQuietly(Repository $store, string $key): void
    {
        try {
            $store->forget($key);
        } catch (Throwable) {
            // Voir le docblock : silence assumé, pas un oubli.
        }
    }
}
