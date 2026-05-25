<?php

declare(strict_types=1);

namespace App\Core\Models;

use Database\Factories\StreamerFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

/**
 * Tenant-root model — tenancy v1 mono-streamer (ADR-0002, architecture §3.4).
 *
 * Single source of truth for streamer-configurable data (tagline, bilingual bios,
 * CTAs, social handles) consumed by tenant-aware components (Press Kit Epic 8,
 * CTAs Epic 5). A fork-streamer overrides these via Filament SettingsResource
 * (Story 1.10) — never hardcode a streamer's data in views (ADR-0001).
 *
 * Invariants:
 *  - NO `streamer_id` column: this model IS the streamer.
 *  - Does NOT use the BelongsToStreamer trait (that is for business models).
 *
 * @property int $id
 * @property string $name
 * @property string|null $tagline
 * @property string|null $bio_fr
 * @property string|null $bio_en
 * @property string|null $photo_url
 * @property string|null $cta_text
 * @property string|null $cta_url
 * @property string|null $twitter_handle
 * @property string|null $discord_url
 */
class Streamer extends Model
{
    /** @use HasFactory<StreamerFactory> */
    use HasFactory;

    /**
     * @var list<string>
     */
    protected $fillable = [
        'name',
        'tagline',
        'bio_fr',
        'bio_en',
        'photo_url',
        'cta_text',
        'cta_url',
        'twitter_handle',
        'discord_url',
    ];

    /**
     * Explicit factory wiring: the model lives in App\Core\Models\, outside
     * Laravel's default App\Models\ factory-resolution path, so automatic
     * discovery would fail. See StreamerFactory.
     */
    protected static function newFactory(): StreamerFactory
    {
        return StreamerFactory::new();
    }
}
