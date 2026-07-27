<?php

declare(strict_types=1);

use App\Core\Concerns\BelongsToStreamer;
use Illuminate\Support\Str;

/*
 * Static tenancy guard (Pattern C — ADR-0002, architecture §3.4): every table
 * backed by a BelongsToStreamer model MUST declare a non-nullable streamer_id.
 * The scan is driven by the models that use the trait (never an allowlist of
 * framework/package tables), so streamers/users/cache/jobs/package tables are
 * automatically out of scope. Dormant today (no module models yet) — it
 * activates in Epic 5. A Feature test (app booted) is used so base_path()/
 * app_path()/database_path() and Str resolve reliably (no container path math,
 * cf. Story 1.2 learning); no DB is queried, so RefreshDatabase is unnecessary.
 */

/**
 * True when the migration source declares a `streamer_id` column that is not nullable.
 * False when the column is missing or declared nullable.
 */
function migrationDeclaresNonNullableStreamerId(string $source): bool
{
    foreach (explode(';', $source) as $statement) {
        // A column declaration whose first argument is the streamer_id column name,
        // e.g. ->foreignId('streamer_id') / ->unsignedBigInteger('streamer_id').
        if (preg_match('/->\s*\w+\(\s*[\'"]streamer_id[\'"]/', $statement) !== 1) {
            continue;
        }

        return preg_match('/->\s*nullable\s*\(/', $statement) !== 1;
    }

    return false;
}

/**
 * Map a model file path under app/ to its PSR-4 FQCN (App\ => app/).
 */
function fqcnFromAppPath(string $path): string
{
    $relative = Str::after($path, app_path() . DIRECTORY_SEPARATOR);

    return 'App\\' . str_replace([DIRECTORY_SEPARATOR, '.php'], ['\\', ''], $relative);
}

/**
 * @return list<class-string>  Models (Core + Modules) that use BelongsToStreamer.
 */
function tenantScopedModels(): array
{
    $files = array_merge(
        glob(app_path('Core/Models/*.php')) ?: [],
        glob(app_path('Modules/*/Models/*.php')) ?: [],
    );

    $models = [];

    foreach ($files as $file) {
        $class = fqcnFromAppPath($file);

        if (class_exists($class) && in_array(BelongsToStreamer::class, class_uses_recursive($class), true)) {
            $models[] = $class;
        }
    }

    return $models;
}

it('detects a non-nullable streamer_id column (guard self-check)', function (): void {
    // Conformant declarations.
    expect(migrationDeclaresNonNullableStreamerId("\$table->foreignId('streamer_id');"))
        ->toBeTrue()
        ->and(migrationDeclaresNonNullableStreamerId("\$table->foreignId('streamer_id')->constrained();"))
        ->toBeTrue()
        ->and(migrationDeclaresNonNullableStreamerId("\$table->unsignedBigInteger('streamer_id')->index();"))
        ->toBeTrue();

    // Violations: nullable column, or no streamer_id column at all.
    expect(migrationDeclaresNonNullableStreamerId("\$table->foreignId('streamer_id')->nullable();"))
        ->toBeFalse()
        ->and(migrationDeclaresNonNullableStreamerId("\$table->string('title');\n\$table->timestamps();"))
        ->toBeFalse();
});

it('requires every tenant-scoped table to declare a non-nullable streamer_id', function (): void {
    $migrations = glob(database_path('migrations/*.php')) ?: [];

    $missing = [];

    foreach (tenantScopedModels() as $class) {
        /** @var \Illuminate\Database\Eloquent\Model $model */
        $model = new $class();
        $table = $model->getTable();

        $createMigration = collect($migrations)
            ->first(
                fn (string $path): bool => str_contains(basename($path), "create_{$table}_table"),
            );

        $declared = is_string($createMigration)
            && migrationDeclaresNonNullableStreamerId((string) file_get_contents($createMigration));

        if (! $declared) {
            $missing[] = $table;
        }
    }

    expect($missing)
        ->toBeEmpty();
});

it('requires every module model to use the BelongsToStreamer trait', function (): void {
    $files = glob(app_path('Modules/*/Models/*.php')) ?: [];

    $violations = [];

    foreach ($files as $file) {
        $class = fqcnFromAppPath($file);

        if (class_exists($class) && ! in_array(BelongsToStreamer::class, class_uses_recursive($class), true)) {
            $violations[] = $class;
        }
    }

    expect($violations)
        ->toBeEmpty();
});
