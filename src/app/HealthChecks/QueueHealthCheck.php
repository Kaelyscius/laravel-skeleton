<?php

declare(strict_types=1);

namespace App\HealthChecks;

use App\HealthChecks\Support\BackendEndpoint;
use App\HealthChecks\Support\BoundsBackendReachability;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Queue;
use Spatie\Health\Checks\Check;
use Spatie\Health\Checks\Result;
use Throwable;

/**
 * Atteste que le BACKEND de file d'attente est JOIGNABLE. Rien d'autre.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * ⛔ POURQUOI CE N'EST PAS `Spatie\Health\Checks\Checks\QueueCheck`
 *
 * Le `QueueCheck` de Spatie atteste qu'un JOB A TOURNÉ RÉCEMMENT : il pousse un
 * `HealthQueueJob` depuis le planificateur, lequel écrit un battement de cœur
 * en cache, et la sonde compare l'âge de ce battement à un seuil. Sémantique
 * juste en EXPLOITATION — et FAUSSE au sortir d'une installation neuve, où
 * aucun worker n'a encore rien traité et où le planificateur n'a jamais tourné.
 *
 * Employé tel quel, il ferait rougir le nightly bloquant de la story 2.4 pour
 * une raison ÉTRANGÈRE à l'installeur. Le premier réflexe, la troisième nuit,
 * serait de désarmer le nightly — c'est-à-dire de perdre le garde-fou entier
 * pour un défaut de sémantique de sonde.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * CE QUE LA SONDE FAIT, ET CE QU'ELLE NE DIT PAS
 *
 * Elle demande sa PROFONDEUR à la connexion de file par défaut. C'est un
 * aller-retour RÉEL vers le backend pour tous les pilotes qui en ont un :
 * `redis` (LLEN), `database` (SELECT COUNT), `sqs`, `beanstalkd`. Pour `sync`
 * et `null`, `size()` rend 0 sans toucher quoi que ce soit — et c'est la
 * réponse HONNÊTE : ces pilotes n'ONT pas de backend, donc il ne peut pas être
 * injoignable.
 *
 * ⛔ ELLE N'ATTESTE PAS qu'un worker tourne, ni qu'un job serait traité, ni que
 * la file se vide. Le JSON de `/health` le dit dans ces termes plutôt que de
 * laisser un lecteur en déduire une garantie de traitement : un `queue: ok`
 * cohabite parfaitement avec zéro worker.
 *
 * 🔒 SCRUB — même règle que `DatabaseHealthCheck` : jamais le message
 * d'exception (les pilotes y mettent l'hôte, le port, et pour SQS l'URL de
 * file). Classe de l'exception + NOM de la connexion, qui est une clé de
 * configuration.
 *
 * ⏱️ BORNE TEMPORELLE : voir le docblock de la route `/health`.
 */
final class QueueHealthCheck extends Check
{
    use BoundsBackendReachability;

    public function run(): Result
    {
        $connectionName = self::defaultConnectionName();

        // ⛔ Portillon borné d'abord (voir `BackendEndpoint`).
        $gate = $this->refuseIfUnreachable(BackendEndpoint::forQueueConnection(), 'queue');

        if ($gate instanceof Result) {
            return $gate;
        }

        try {
            Queue::connection()->size();

            return Result::make()
                ->ok()
                ->shortSummary('Backend joignable — n\'atteste AUCUN traitement de job');
        } catch (Throwable $e) {
            Log::error('QueueHealthCheck failed', [
                'type' => $e::class,
                'connection' => $connectionName,
            ]);

            return Result::make()
                ->failed('Queue backend unreachable')
                ->shortSummary('Backend injoignable');
        }
    }

    /**
     * Nom de la connexion de file par défaut, pour le journal — jamais son DSN.
     */
    private static function defaultConnectionName(): string
    {
        $configured = config('queue.default');

        return is_string($configured) ? $configured : '(non résolu)';
    }
}
