<?php

declare(strict_types=1);

use App\Core\Concerns\BelongsToStreamer;
use App\Core\Http\Middleware\SetCurrentStreamer;
use App\Core\Models\Streamer;
use App\Core\Scopes\BelongsToStreamerScope;
use App\Core\Support\CurrentStreamer;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Schema;
use Tests\Fixtures\TenantFixtureModel;

uses(RefreshDatabase::class);

beforeEach(function (): void {
    // Built on the fly (not a migration). Postgres DDL is transactional, so
    // RefreshDatabase rolls this table back at the end of each test.
    Schema::create('tenant_fixtures', function (Blueprint $table): void {
        $table->id();
        $table->foreignId('streamer_id');
        $table->string('label')
            ->nullable();
    });
});

/**
 * Bind the request-scoped tenant context to a given streamer, as the middleware would.
 */
function actingAsStreamer(Streamer $streamer): void
{
    app()->instance(CurrentStreamer::class, new CurrentStreamer($streamer));
}

it('auto-applies the global scope and isolates rows across streamers', function (): void {
    $a = Streamer::factory()->create();
    $b = Streamer::factory()->create();

    actingAsStreamer($a);
    TenantFixtureModel::create([
        'label' => 'a1',
    ]);
    TenantFixtureModel::create([
        'label' => 'a2',
    ]);

    actingAsStreamer($b);
    TenantFixtureModel::create([
        'label' => 'b1',
    ]);

    // Bound to B: only B's row is visible.
    expect(TenantFixtureModel::count())->toBe(1);

    // Bound to A: only A's two rows are visible.
    actingAsStreamer($a);
    expect(TenantFixtureModel::count())->toBe(2);

    // Escape hatch sees every row regardless of tenant.
    expect(TenantFixtureModel::withoutGlobalScope(BelongsToStreamerScope::class)->count())->toBe(3);
});

it('injects a table-qualified streamer_id WHERE clause into queries', function (): void {
    actingAsStreamer(Streamer::factory()->create());

    expect(TenantFixtureModel::query()->toSql())
        ->toContain('"tenant_fixtures"."streamer_id"');
});

it('auto-fills streamer_id on creation from the current streamer', function (): void {
    $a = Streamer::factory()->create();
    actingAsStreamer($a);

    $model = TenantFixtureModel::create([
        'label' => 'x',
    ]);

    expect($model->streamer_id)
        ->toBe($a->id);
});

it('fails loud when CurrentStreamer is resolved without the middleware', function (): void {
    expect(fn () => app(CurrentStreamer::class)->id())
        ->toThrow(RuntimeException::class);
});

it('registers the tenant middleware on the web group via CoreServiceProvider', function (): void {
    expect(app('router')->getMiddlewareGroups()['web'])
        ->toContain(SetCurrentStreamer::class);
});

it('binds the current streamer through the SetCurrentStreamer middleware', function (): void {
    $streamer = Streamer::factory()->create();

    $response = (new SetCurrentStreamer())->handle(
        Request::create('/'),
        fn (Request $request) => response('ok'),
    );

    expect(app(CurrentStreamer::class)->id())->toBe($streamer->id)
        ->and($response->getContent())
        ->toBe('ok');
});

it('exposes the streamer relation from a tenant model', function (): void {
    $a = Streamer::factory()->create();
    actingAsStreamer($a);

    $model = TenantFixtureModel::create([
        'label' => 'x',
    ]);

    expect($model->streamer)
        ->toBeInstanceOf(Streamer::class)
        ->and($model->streamer?->id)
        ->toBe($a->id);
});

it('applies the trait to business models but never to the streamer root', function (): void {
    // Positive control resolving Story 1.3's deferred (anti-trait test was tautological).
    expect(class_uses_recursive(TenantFixtureModel::class))->toContain(BelongsToStreamer::class)
        ->and(class_uses_recursive(Streamer::class))->not->toContain(BelongsToStreamer::class);
});
