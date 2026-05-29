<?php

declare(strict_types=1);

use App\Core\Models\Streamer;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Artisan;

uses(RefreshDatabase::class);

it('exits 0 when exactly one streamer exists', function (): void {
    Streamer::factory()->create();

    expect(Artisan::call('tenancy:assert'))->toBe(0);
});

it('exits 1 and reports the count when more than one streamer exists', function (): void {
    Streamer::factory()->count(2)->create();

    expect(Artisan::call('tenancy:assert'))->toBe(1)
        ->and(Artisan::output())->toContain('found 2');
});

it('exits 1 and reports a zero count when no streamer is seeded (unseeded database is a violation)', function (): void {
    expect(Artisan::call('tenancy:assert'))->toBe(1)
        ->and(Artisan::output())->toContain('found 0');
});
