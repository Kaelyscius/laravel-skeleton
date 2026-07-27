<?php

declare(strict_types=1);

use Illuminate\Support\Facades\DB;

/**
 * Sentinelle de moteur de base de données.
 *
 * Ce test existe parce que la CI a tourné sur MariaDB alors que la stack LOCKED
 * est PostgreSQL 17 (ADR-0007, architecture §9.2) : un garde-fou vert qui ne
 * gardait rien. Il vit dans la suite principale — il ne dort pas — et rougit
 * immédiatement si quelqu'un rebascule un environnement sur un moteur
 * MySQL-compatible.
 *
 * Chaque assertion utilise de la syntaxe que MySQL ET MariaDB refusent, pour que
 * l'échec soit franc (erreur SQL) plutôt qu'un faux vert silencieux.
 */
it('tourne sur PostgreSQL et pas sur un moteur MySQL-compatible', function (): void {
    expect(DB::connection()->getDriverName())->toBe('pgsql');
})->group('sentinel');

it('exécute de la syntaxe exclusivement PostgreSQL', function (): void {
    // `::` (cast) et `ILIKE` sont tous deux absents de MySQL et de MariaDB.
    // Sur un de ces moteurs, la requête lève une erreur de syntaxe.
    $row = DB::selectOne("SELECT ('streamer'::text ILIKE 'STREAMER')::int AS ok");

    expect((int) $row->ok)->toBe(1);
})->group('sentinel');

it('manipule du jsonb natif', function (): void {
    // jsonb est un type propre à PostgreSQL — l'une des raisons du choix ADR-0007.
    $row = DB::selectOne("SELECT ('{\"note\":9}'::jsonb -> 'note')::int AS note");

    expect((int) $row->note)->toBe(9);
})->group('sentinel');

it('tourne sur PostgreSQL 17 ou plus récent', function (): void {
    $row = DB::selectOne("SELECT current_setting('server_version_num')::int AS version");

    // 170000 = 17.0. Le seuil est un plancher : une montée de version majeure
    // reste verte, un retour en arrière sous la version LOCKED rougit.
    expect((int) $row->version)->toBeGreaterThanOrEqual(170000);
})->group('sentinel');
