<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Core\Models\Streamer;
use Illuminate\Database\Seeder;

/**
 * Seeds the single tenant-root Streamer row with placeholder values for Alex.
 *
 * IDEMPOTENT BY DESIGN: tenancy v1 requires exactly one Streamer (Story 1.5
 * `tenancy:assert`). Idempotency is keyed on the EXISTENCE of any streamer row,
 * NOT on `name` — a fork-streamer renames the row via Filament (Story 1.10), and
 * keying on a mutable attribute would let a re-seed miss the match and insert a
 * SECOND row, breaking the exactly-one invariant. A fork-streamer replaces these
 * placeholders via Filament (Story 1.10).
 */
class StreamerSeeder extends Seeder
{
    public function run(): void
    {
        Streamer::query()->firstOr(function (): Streamer {
            return Streamer::create([
                'name' => 'Alex',
                'tagline' => 'Streamer & créateur de contenu',
                'bio_fr' => 'Bio à compléter…',
                'bio_en' => 'Bio to be completed…',
                'photo_url' => null,
                'cta_text' => 'Suivre sur Twitch',
                'cta_url' => 'https://twitch.tv/',
                'twitter_handle' => null,
                'discord_url' => null,
            ]);
        });
    }
}
