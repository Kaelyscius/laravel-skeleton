<?php

declare(strict_types=1);

namespace App\HealthChecks;

use App\HealthChecks\Support\BackendEndpoint;
use App\HealthChecks\Support\BoundsBackendReachability;
use Illuminate\Database\Connection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use PDOException;
use Spatie\Health\Checks\Check;
use Spatie\Health\Checks\Result;
use Throwable;

final class DatabaseHealthCheck extends Check
{
    use BoundsBackendReachability;

    public function run(): Result
    {
        // ⛔ PORTILLON D'ABORD — voir `BackendEndpoint`. Sans lui, une base
        // dont l'hôte ne résout plus coûtait ~10 tentatives × 3,13 s, et
        // `/health` rendait un 504 de passerelle au lieu de son corps 503 :
        // l'endpoint muet dans la panne même pour laquelle il existe.
        $gate = $this->refuseIfUnreachable(BackendEndpoint::forDatabaseConnection(), 'database');

        if ($gate instanceof Result) {
            return $gate;
        }

        $connection = DB::connection();
        $isPgsql = $connection->getDriverName() === 'pgsql';

        /*
         * ⏱️ VRAI SI ET SEULEMENT SI LE `SET` A ABOUTI — donc si une session
         * existe et porte réellement le réglage.
         *
         * 🔴 MESURÉ le 2026-08-23, story 2.4 : sans ce drapeau, une base
         * INJOIGNABLE payait le `RESET` du `finally` — c'est-à-dire une
         * tempête de reconnexions complète pour remettre à sa valeur par
         * défaut une session qui n'a jamais existé. Sur une base joignable
         * cela ne coûte rien ; sur une base morte, c'est un TIERS du coût de
         * la sonde, au moment précis où `/health` doit répondre vite.
         *
         * ⚠️ DEPUIS LA REVUE 1, LE PORTILLON COUPE AVANT — donc ce drapeau ne
         * change plus rien dans le cas « backend injoignable » : la sonde rend
         * son échec sans jamais atteindre `statement()`. Il reste utile pour le
         * cas où le portillon PASSE et où la requête échoue ensuite (droits,
         * authentification, base absente), et c'est ce que
         * `DatabaseHealthCheckTest` fige. La mesure ci-dessous est donc
         * HISTORIQUE : elle documente pourquoi le drapeau existe.
         *
         * Mesuré sur `/health`, hôte de base rendu irrésoluble (`DB_HOST=
         * nosuchhost.invalid`), noyau HTTP instrumenté en conteneur :
         *
         *   `checks.database.duration_ms`  avant : 6043
         *                                  après : 3148, puis 3916 / 2938 / 2348
         *
         * La mesure est BRUYANTE (elle est dominée par la résolution de nom) :
         * c'est l'ordre de grandeur — un aller-retour de connexion en moins —
         * qui est le résultat, pas un chiffre au millième.
         *
         * ⚖️ C'est le seul écart au « réutiliser tel quel » de la story, et il
         * est ici parce qu'une mesure l'a exigé, pas parce qu'il était élégant.
         */
        $timeoutApplied = false;

        try {
            if ($isPgsql) {
                // ⚠️ LE DRAPEAU VIENT DU RETOUR, PAS DE L'ABSENCE D'EXCEPTION.
                // `Connection::statement()` rend le booléen de
                // `PDOStatement::execute()`, qui peut valoir `false` SANS lever.
                // ⛔ ET LA PHRASE HONNÊTE EST CELLE-CI : dans CETTE pile, cette
                // branche est INATTEIGNABLE — le framework impose
                // `PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION`
                // (`Connector::$options`), donc un échec LÈVE. La lecture du
                // retour est une défense pour un pilote configuré autrement ;
                // elle n'est gardée par aucun test, et `DatabaseHealthCheckTest`
                // le dit plutôt que de la compter comme protégée.
                $timeoutApplied = $connection->statement('SET statement_timeout = 2000');
            }

            $connection->select('SELECT 1');

            return Result::make()->ok();
        } catch (Throwable $e) {
            // FR3-4: Scrub. PDOException messages routinely embed the DSN, host,
            // port, database name, and username (e.g. "FATAL: password
            // authentication failed for user 'laravel' at host 'postgres'").
            // We log ONLY the exception class and SQLSTATE — enough to triage
            // ('connection refused' vs 'auth failed' vs 'permission denied')
            // without leaking connection string info to the log aggregator.
            Log::error('DatabaseHealthCheck failed', [
                'type' => $e::class,
                'sqlstate' => $e instanceof PDOException ? ($e->errorInfo[0] ?? null) : null,
            ]);

            return Result::make()->failed('Database unreachable');
        } finally {
            if ($timeoutApplied) {
                self::resetStatementTimeout($connection);
            }
        }
    }

    /**
     * Remet `statement_timeout` à sa valeur de session par défaut.
     *
     * Extrait de `run()` pour deux raisons : la méthode dépassait la longueur
     * tolérée par PHP Insights, et surtout le `try/catch` silencieux méritait
     * d'être nommé plutôt que noyé dans un `finally`.
     *
     * Le silence est VOLONTAIRE et ne doit pas être « corrigé » : la connexion
     * peut être morte, et journaliser ici produirait un avertissement par sonde
     * pendant toute la durée d'une panne — soit exactement le moment où les logs
     * doivent rester lisibles.
     */
    private static function resetStatementTimeout(Connection $connection): void
    {
        try {
            $connection->statement('RESET statement_timeout');
        } catch (Throwable) {
            // Voir le docblock : silence assumé, pas un oubli.
        }
    }
}
