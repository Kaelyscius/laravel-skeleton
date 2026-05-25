<?php

declare(strict_types=1);

// tests/Feature/StreamerModelTest.php
// Story 1.3 — Streamer Core model (tenancy root, ADR-0002).
// Verifies schema, tenant-root invariants, model fillable, factory wiring, and idempotent seeding.

use App\Core\Models\Streamer;
use Database\Seeders\StreamerSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Schema;

uses(RefreshDatabase::class);

it('creates the streamers table with all 12 expected columns', function (): void {
    expect(Schema::hasTable('streamers'))->toBeTrue();

    expect(Schema::hasColumns('streamers', [
        'id',
        'name',
        'tagline',
        'bio_fr',
        'bio_en',
        'photo_url',
        'cta_text',
        'cta_url',
        'twitter_handle',
        'discord_url',
        'created_at',
        'updated_at',
    ]))->toBeTrue();

    // Assert the count too: presence-only checks would not catch an unexpected
    // extra column (e.g. a stray streamer_id or deleted_at) sneaking in.
    expect(Schema::getColumnListing('streamers'))->toHaveCount(12);
});

it('does not give the tenant-root table a streamer_id column', function (): void {
    // Streamer IS the tenant — it must never carry streamer_id (architecture §3.4).
    expect(Schema::hasColumn('streamers', 'streamer_id'))->toBeFalse();
});

it('enforces the PRD-pinned column types', function (): void {
    $columns = collect(Schema::getColumns('streamers'))->keyBy('name');

    // Anchor the length in parentheses so the assertion can't false-match an
    // adjacent length — '500' is a substring of '1500', but '(500)' is not a
    // substring of '(1500)'. Robust to 'character varying(N)' vs 'varchar(N)'.
    expect($columns['tagline']['type'])->toContain('(255)')
        ->and($columns['cta_text']['type'])->toContain('(100)')
        ->and($columns['cta_url']['type'])->toContain('(500)')
        ->and($columns['bio_fr']['type'])->toBe('text')
        ->and($columns['bio_en']['type'])->toBe('text');
});

it('exposes the editable fields as fillable and is not the tenant trait', function (): void {
    $streamer = new Streamer();

    expect($streamer->getFillable())->toContain(
        'name',
        'tagline',
        'bio_fr',
        'bio_en',
        'photo_url',
        'cta_text',
        'cta_url',
        'twitter_handle',
        'discord_url',
    );

    // The tenant root must not pull in BelongsToStreamer (that trait is for business models).
    // Recursive: also catches the trait being applied via a parent class or a composed trait.
    expect(class_uses_recursive(Streamer::class))->not->toContain('App\Core\Concerns\BelongsToStreamer');
});

it('persists a streamer through its explicitly-wired factory', function (): void {
    // Streamer lives in App\Core\Models\, outside Laravel's default factory path —
    // this proves the newFactory() override resolves StreamerFactory correctly.
    $streamer = Streamer::factory()->create([
        'name' => 'Test Streamer',
    ]);

    expect($streamer->exists)->toBeTrue()
        ->and(Streamer::query()->where('name', 'Test Streamer')->exists())->toBeTrue();
});

it('seeds exactly one streamer and stays idempotent on re-run', function (): void {
    (new StreamerSeeder())->run();
    expect(Streamer::query()->count())->toBe(1);

    // Re-running must not create a duplicate — tenancy v1 requires exactly 1 (Story 1.5 tenancy:assert).
    (new StreamerSeeder())->run();
    expect(Streamer::query()->count())->toBe(1);

    // Real failure mode: a fork-streamer renames the row via Filament (Story 1.10),
    // then a re-seed runs. Keying on row existence (not on name) must still keep exactly 1.
    Streamer::query()->firstOrFail()->update([
        'name' => 'Renamed Streamer',
    ]);
    (new StreamerSeeder())->run();
    expect(Streamer::query()->count())->toBe(1);
});
