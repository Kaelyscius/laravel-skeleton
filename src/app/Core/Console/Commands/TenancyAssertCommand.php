<?php

declare(strict_types=1);

namespace App\Core\Console\Commands;

use App\Core\Models\Streamer;
use Illuminate\Console\Command;

/**
 * CI / deploy gate for the v1 mono-streamer invariant (Pattern C — ADR-0002).
 *
 * Exits 0 when exactly one Streamer row exists, 1 otherwise (0 or >=2 both
 * count as violations). Queries the tenant-root Streamer model, which does NOT
 * use BelongsToStreamer, so no tenant scope / CurrentStreamer resolution is
 * triggered — the command runs safely outside an HTTP request.
 */
class TenancyAssertCommand extends Command
{
    protected $signature = 'tenancy:assert';

    protected $description = 'Assert the v1 mono-streamer invariant: exactly one Streamer row (ADR-0002).';

    public function handle(): int
    {
        $count = Streamer::query()->count();

        if ($count === 1) {
            $this->info('Tenancy OK: exactly one streamer (v1 mono-streamer invariant holds).');

            return self::SUCCESS;
        }

        $this->error(
            "Tenancy violation: expected exactly 1 streamer, found {$count}. "
            . 'v1 is mono-streamer (ADR-0002 — enable Pattern D / RLS before going multi-streamer).',
        );

        return self::FAILURE;
    }
}
