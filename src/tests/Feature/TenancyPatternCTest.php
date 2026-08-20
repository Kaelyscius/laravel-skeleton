<?php

declare(strict_types=1);

use App\Core\Concerns\BelongsToStreamer;
use App\Core\Exceptions\NoStreamerConfiguredException;
use App\Core\Http\Middleware\SetCurrentStreamer;
use App\Core\Models\Streamer;
use App\Core\Scopes\BelongsToStreamerScope;
use App\Core\Support\CurrentStreamer;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Schema;
use Tests\Fixtures\TenantFixtureModel;
use Tests\Support\HttpProbe;

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

/*
|------------------------------------------------------------------------------
| Base non semée : le « fail-loud » doit être LISIBLE, pas un 404
|------------------------------------------------------------------------------
*/

it('never renders an unseeded database as a 404, and no longer blocks routes that do not need the tenant', function (): void {
    /*
     * ENTRÉE OUVERTE DE `deferred-work.md` DEPUIS LE 2026-07-30, FERMÉE EN DEUX TEMPS.
     *
     * Temps 1 (2026-08-10). `firstOrFail()` levait ModelNotFoundException, que le
     * handler Laravel rend en **404**, indiscernable de « cette page n'existe
     * pas ». Symptôme constaté le 2026-07-30 : base de dev non semée → `/` en
     * 404, `/up` en 200 (hors groupe `web`). Remplacé par une exception de
     * domaine nommée, rendue en 500. Rouge observé avant correction.
     *
     * Temps 2 (2026-08-20, décision D5 de la revue). Le 500 était mieux nommé et
     * tout aussi fermé : le panel `/admin` — la SEULE interface capable de créer
     * le streamer manquant — restait injoignable, puisque toute interaction
     * Livewire traverse le groupe `web`. L'AC6 n'existe pas pour améliorer un
     * message, elle existe pour que l'opérateur ne soit pas enfermé dehors.
     * `SetCurrentStreamer` enregistre désormais un RÉSOLVEUR : la requête à la
     * base n'a lieu que si quelque chose demande vraiment `CurrentStreamer`.
     *
     * Ce test borne les deux côtés à la fois : jamais un 404 (temps 1), et plus
     * un échec du tout tant que rien ne réclame le contexte (temps 2).
     */
    expect(Streamer::query()->count())
        ->toBe(0, 'RefreshDatabase doit laisser la table streamers vide.');

    $status = HttpProbe::get('/')->getStatusCode();

    expect($status)
        ->not->toBe(
            404,
            'Une base sans streamer rend un 404 : indiscernable d\'une page inexistante. '
                . 'C\'est le défaut ouvert de deferred-work.md — l\'intention « fail-loud » est '
                . 'documentée, le comportement la contredit.',
        );
    expect($status)
        ->toBeLessThan(
            500,
            "Une route qui ne demande AUCUN modèle tenant rend {$status} sur une base sans "
                . 'streamer : la liaison n\'est donc plus paresseuse, et l\'opérateur est de '
                . 'nouveau enfermé dehors (décision D5).',
        );
});

it('still fails loudly, and names the remedy, the moment the tenant context is actually resolved', function (): void {
    /*
     * ⚠️ LA MOITIÉ QU'IL NE FAUT PAS PERDRE EN RENDANT LA LIAISON PARESSEUSE.
     *
     * Différer la résolution ne doit pas transformer l'échec en silence : dès que
     * quelque chose demande réellement `CurrentStreamer` sur une base vide,
     * l'exception nommée doit sortir. Et un 500 anonyme ne vaudrait guère mieux
     * qu'un 404 : ce qui rend l'échec exploitable, c'est que le message dise QUOI
     * FAIRE. Rien d'autre que ce test ne garde cette moitié-là.
     *
     * 📌 Pourquoi la vérification est au niveau du conteneur et non d'une URL :
     * aucune route publique du squelette ne résout encore le contexte tenant —
     * le premier modèle tenant arrive en Epic 5. Écrire ce garde-fou sur une URL
     * aujourd'hui reviendrait à l'écrire sur une route qui ne l'exerce pas,
     * c'est-à-dire à produire un vert qui ne garde rien.
     */
    expect(Streamer::query()->count())->toBe(0);

    (new SetCurrentStreamer())->handle(
        Request::create('/'),
        fn (Request $request) => response('la requête traverse : rien n\'a encore demandé le contexte'),
    );

    expect(fn (): mixed => app(CurrentStreamer::class))
        ->toThrow(NoStreamerConfiguredException::class);

    $message = '';

    try {
        app(CurrentStreamer::class);
    } catch (NoStreamerConfiguredException $e) {
        $message = $e->getMessage();
    }

    expect(str_contains($message, 'db:seed'))
        ->toBeTrue("Le message d'installation ne nomme pas la commande qui répare : [{$message}]");
});

it('names a different remedy when the table itself is missing', function (): void {
    /*
     * « Pas migré » et « table vide » se ressemblent depuis un navigateur et
     * demandent DEUX commandes différentes. Sans cette branche, le premier cas
     * rendait une QueryException nue : un 500 sans remède dedans, soit exactement
     * le coût de diagnostic que cette exception existe pour retirer. Finding Q23.
     */
    Schema::drop('streamers');

    (new SetCurrentStreamer())->handle(
        Request::create('/'),
        fn (Request $request) => response('unreachable'),
    );

    $message = '';

    try {
        app(CurrentStreamer::class);
    } catch (NoStreamerConfiguredException $e) {
        $message = $e->getMessage();
    }

    expect(str_contains($message, 'migrate'))
        ->toBeTrue("Le message ne nomme pas `migrate` alors que la table est absente : [{$message}]");
    expect(str_contains($message, 'db:seed'))
        ->toBeFalse('Le message renvoie vers `db:seed` alors que la table n\'existe pas : semer ne répare rien.');
});
