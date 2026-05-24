<?php

declare(strict_types=1);

namespace App\HealthChecks;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use PDOException;
use Spatie\Health\Checks\Check;
use Spatie\Health\Checks\Result;
use Throwable;

class DatabaseHealthCheck extends Check
{
    public function run(): Result
    {
        $connection = DB::connection();
        $isPgsql = $connection->getDriverName() === 'pgsql';

        try {
            if ($isPgsql) {
                $connection->statement('SET statement_timeout = 2000');
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
            if ($isPgsql) {
                try {
                    $connection->statement('RESET statement_timeout');
                } catch (Throwable) {
                    // Silent: connection may be dead. Logging here would amplify
                    // noise (one warning per probe during outages).
                }
            }
        }
    }
}
