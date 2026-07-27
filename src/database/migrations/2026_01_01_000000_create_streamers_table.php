<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Story 1.3 — tenant-root table for App\Core\Models\Streamer.
 *
 * Lives in root database/migrations/ (NOT a module folder): Core is always-active,
 * so the "no root migrations" rule (ADR-0009 §3.3) — which targets disableable
 * modules — does not apply. The streamers table carries NO streamer_id: it IS the
 * streamer (tenancy v1 Pattern C, ADR-0002, architecture §3.4).
 */
return new class() extends Migration {
    public function up(): void
    {
        Schema::create('streamers', function (Blueprint $table): void {
            $table->id();
            $table->string('name');
            $table->string('tagline')
                ->nullable();
            $table->text('bio_fr')
                ->nullable();
            $table->text('bio_en')
                ->nullable();
            $table->string('photo_url', 500)
                ->nullable();
            $table->string('cta_text', 100)
                ->nullable();
            $table->string('cta_url', 500)
                ->nullable();
            $table->string('twitter_handle')
                ->nullable();
            $table->string('discord_url', 500)
                ->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('streamers');
    }
};
