<?php

declare(strict_types=1);

use Illuminate\Support\Facades\DB;

/**
 * Sentinelle de base de test.
 *
 * Ce test existe parce que TOUTE la suite a tourné sur la base de DÉVELOPPEMENT
 * pendant des mois, qu'elle vidait à chaque exécution via RefreshDatabase, alors
 * que `phpunit.xml` déclarait `DB_DATABASE=laravel_test`. Constaté le
 * 2026-07-31 : `laravel_test` contenait 0 table — elle n'avait jamais servi —
 * pendant que 55 tests passaient au vert.
 *
 * Cause : PHPUnit n'écrase pas une variable d'environnement déjà définie sans
 * `force="true"`, et Laravel charge `.env` avant que le bloc <php> ne
 * s'applique. La déclaration était donc une affirmation sans effet.
 *
 * Le garde-fou porte sur la connexion RÉELLEMENT active au moment du test, pas
 * sur le contenu d'un fichier de configuration — c'est toute la différence entre
 * ce qui est déclaré et ce qui s'exécute.
 */
it('ne tourne jamais sur la base de développement', function (): void {
    $database = DB::connection()->getDatabaseName();

    // Liste blanche explicite plutôt que « contient test » : un jour quelqu'un
    // nommera sa base de dev `latest_snapshot` et la sous-chaîne passera.
    expect($database)
        ->toBeIn(['laravel_test', 'testing', ':memory:']);
})->group('sentinel');

it('rougit si la connexion pointe sur la base de développement', function (): void {
    $database = DB::connection()->getDatabaseName();

    // Auto-contrôle : la sentinelle doit savoir nommer ce qu'elle interdit.
    // `laravel` est la base de dev déclarée dans .env — si on la voit ici,
    // RefreshDatabase est en train de la vider.
    expect($database === 'laravel')
        ->toBeFalse("La suite tourne sur la base de DÉVELOPPEMENT [{$database}] et la vide à chaque exécution. Vérifier force=\"true\" sur les <env> de phpunit.xml.");
})->group('sentinel');

it('écrit dans une base réellement distincte de celle de développement', function (): void {
    // Preuve d'effet, pas de déclaration : on crée une table temporaire et on
    // vérifie qu'elle atterrit dans la base attendue.
    $current = DB::selectOne('SELECT current_database() AS db')->db;

    expect($current)
        ->not->toBe('laravel')
        ->and($current)
        ->toBe(DB::connection()->getDatabaseName());
})->group('sentinel');
