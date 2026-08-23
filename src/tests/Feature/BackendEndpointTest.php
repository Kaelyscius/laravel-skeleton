<?php

declare(strict_types=1);

use App\HealthChecks\Support\BackendEndpoint;

/*
|------------------------------------------------------------------------------
| `BackendEndpoint` — la résolution qui décide si le portillon s'applique
|------------------------------------------------------------------------------
|
| 🔴 UN `null` ET UN REFUS NE SONT PAS LA MÊME CHOSE, ET TOUT CE FICHIER EST LÀ
| POUR ÇA. `null` signifie « pas de point de terminaison TCP, donc pas de
| portillon » ; un endpoint résolu signifie « on peut, et on doit, tenter une
| connexion bornée ». Se tromper de sens fait échouer une sonde parfaitement
| saine (socket unix pris pour un hôte) ou laisse repartir la tempête de
| reconnexions que le portillon existe pour supprimer (hôte non résolu).
|
| Mesuré en revue 1 : la mutation « socket unix traité comme un hôte TCP »
| restait VERTE — cette logique n'avait aucun test.
|
*/

it('résout une connexion pgsql en hôte et port', function (): void {
    config([
        'database.default' => 'sonde',
        'database.connections.sonde' => [
            'driver' => 'pgsql',
            'host' => 'postgres',
            'port' => 5433,
        ],
    ]);

    $endpoint = BackendEndpoint::forDatabaseConnection();

    expect($endpoint?->label())
        ->toBe('postgres:5433');
});

it('applique le port par défaut du pilote quand la configuration n’en déclare pas', function (): void {
    config([
        'database.default' => 'sonde',
        'database.connections.sonde' => [
            'driver' => 'pgsql',
            'host' => 'postgres',
        ],
    ]);

    expect(BackendEndpoint::forDatabaseConnection()?->label())
        ->toBe('postgres:5432');
});

it('ne résout AUCUN point de terminaison pour un socket unix', function (): void {
    // 🔴 MUTATION VUE VERTE EN REVUE 1, D'OÙ CE TEST. Un `host` commençant par
    // « / » est un chemin de socket unix — PostgreSQL le supporte, et c'est
    // même la configuration par défaut de nombreuses distributions. Le traiter
    // comme un hôte TCP ferait échouer le portillon sur une base PARFAITEMENT
    // SAINE : `/health` rendrait 503 en accusant une dépendance qui répond.
    config([
        'database.default' => 'sonde',
        'database.connections.sonde' => [
            'driver' => 'pgsql',
            'host' => '/var/run/postgresql',
            'port' => 5432,
        ],
    ]);

    expect(BackendEndpoint::forDatabaseConnection())
        ->toBeNull();
});

it('ne résout AUCUN point de terminaison pour sqlite ni pour un pilote inconnu', function (): void {
    config([
        'database.default' => 'sonde',
        'database.connections.sonde' => [
            'driver' => 'sqlite',
            'database' => ':memory:',
        ],
    ]);

    expect(BackendEndpoint::forDatabaseConnection())
        ->toBeNull();

    config([
        'database.connections.sonde' => [
            'driver' => 'pilote-inconnu',
            'host' => 'ailleurs',
            'port' => 1234,
        ],
    ]);

    expect(BackendEndpoint::forDatabaseConnection())
        ->toBeNull();
});

it('refuse un port hors bornes plutôt que de sonder n’importe quoi', function (): void {
    config([
        'database.default' => 'sonde',
        'database.connections.sonde' => [
            'driver' => 'pgsql',
            'host' => 'postgres',
            'port' => 70000,
        ],
    ]);

    expect(BackendEndpoint::forDatabaseConnection())
        ->toBeNull();
});

it('résout un magasin de cache redis vers SA connexion redis', function (): void {
    config([
        'cache.default' => 'sonde',
        'cache.stores.sonde' => [
            'driver' => 'redis',
            'connection' => 'cache',
        ],
        'database.redis.cache' => [
            'host' => 'redis',
            'port' => 6380,
        ],
    ]);

    expect(BackendEndpoint::forCacheStore()?->label())
        ->toBe('redis:6380');
});

it('résout un magasin de cache database vers SA connexion base', function (): void {
    config([
        'cache.default' => 'sonde',
        'cache.stores.sonde' => [
            'driver' => 'database',
            'connection' => 'autre',
        ],
        'database.connections.autre' => [
            'driver' => 'pgsql',
            'host' => 'ailleurs',
            'port' => 5432,
        ],
    ]);

    expect(BackendEndpoint::forCacheStore()?->label())
        ->toBe('ailleurs:5432');
});

it('ne résout AUCUN point de terminaison pour les magasins sans réseau', function (): void {
    // `array` et `file` n'ont rien à joindre : le portillon ne s'applique pas,
    // et la sonde fait son aller-retour comme avant. C'est ce que `null` dit.
    foreach (['array', 'file', 'null'] as $driver) {
        config([
            'cache.default' => 'sonde',
            'cache.stores.sonde' => [
                'driver' => $driver,
            ],
        ]);

        expect(BackendEndpoint::forCacheStore())
            ->toBeNull();
    }
});

it('résout une file redis et une file database, mais pas sync ni sqs', function (): void {
    config([
        'queue.default' => 'sonde',
        'queue.connections.sonde' => [
            'driver' => 'redis',
            'connection' => 'default',
        ],
        'database.redis.default' => [
            'host' => 'redis',
            'port' => 6379,
        ],
    ]);

    expect(BackendEndpoint::forQueueConnection()?->label())
        ->toBe('redis:6379');

    config([
        'queue.connections.sonde' => [
            'driver' => 'database',
            'connection' => 'autre',
        ],
        'database.connections.autre' => [
            'driver' => 'pgsql',
            'host' => 'ailleurs',
            'port' => 5432,
        ],
    ]);

    expect(BackendEndpoint::forQueueConnection()?->label())
        ->toBe('ailleurs:5432');

    // ⚠️ `sync` n'a pas de backend, `sqs` est une API HTTP sans couple
    // hôte/port : dans les deux cas le portillon ne s'applique pas, et le dire
    // par `null` vaut mieux que d'inventer un point de terminaison.
    foreach (['sync', 'null', 'sqs', 'beanstalkd'] as $driver) {
        config([
            'queue.connections.sonde' => [
                'driver' => $driver,
            ],
        ]);

        expect(BackendEndpoint::forQueueConnection())
            ->toBeNull();
    }
});

it('résout un hôte déclaré en LISTE plutôt que de se taire', function (): void {
    // 🔴 RELEVÉ EN REVUE 2 : `host` accepte un tableau (répartition
    // lecture/écriture, plusieurs hôtes). La rédaction précédente n'acceptait
    // qu'une chaîne, rendait `null`, et DÉSACTIVAIT LE PORTILLON EN SILENCE sur
    // exactement les déploiements où il compte le plus.
    config([
        'database.default' => 'sonde',
        'database.connections.sonde' => [
            'driver' => 'pgsql',
            'host' => ['pg-1', 'pg-2'],
            'port' => 5432,
        ],
    ]);

    expect(BackendEndpoint::forDatabaseConnection()?->label())
        ->toBe('pg-1:5432');
});

it('lit DATABASE_URL, qui prime sur hôte et port', function (): void {
    // `ConfigurationUrlParser` du framework fait primer `url`. Le lire après
    // `host` aurait laissé le portillon muet sur toute installation « cloud ».
    config([
        'database.default' => 'sonde',
        'database.connections.sonde' => [
            'driver' => 'pgsql',
            'url' => 'pgsql://user:secret@db.interne:6543/appli',
            'host' => 'ignore-moi',
            'port' => 1111,
        ],
    ]);

    expect(BackendEndpoint::forDatabaseConnection()?->label())
        ->toBe('db.interne:6543');
});

it('résout memcached et beanstalkd, qui n’étaient pas couverts', function (): void {
    config([
        'cache.default' => 'sonde',
        'cache.stores.sonde' => [
            'driver' => 'memcached',
            'servers' => [[
                'host' => 'memcache-1',
                'port' => 11212,
            ]],
        ],
    ]);

    expect(BackendEndpoint::forCacheStore()?->label())
        ->toBe('memcache-1:11212');

    config([
        'queue.default' => 'sonde',
        'queue.connections.sonde' => [
            'driver' => 'beanstalkd',
            'host' => 'beanstalk-1',
        ],
    ]);

    expect(BackendEndpoint::forQueueConnection()?->label())
        ->toBe('beanstalk-1:11300');
});

it('déclare joignable un port ouvert et injoignable un port fermé', function (): void {
    // Anti-vacuité de tout le portillon : sans ce test, `isReachable()`
    // pourrait rendre `true` en toute circonstance et rien ne le dirait.
    $host = config('database.connections.pgsql.host');
    $port = config('database.connections.pgsql.port');

    // Anti-vacuité : sans hôte ni port lisibles, le test ne mesurerait rien.
    expect(is_string($host) && $host !== '')
        ->toBeTrue();
    expect(is_numeric($port))
        ->toBeTrue();

    /** @var numeric-string|int $port */
    config([
        'database.default' => 'sonde',
        'database.connections.sonde' => [
            'driver' => 'pgsql',
            'host' => $host,
            'port' => (int) $port,
        ],
    ]);

    expect(BackendEndpoint::forDatabaseConnection()?->isReachable(2.0))
        ->toBeTrue();

    config([
        'database.connections.sonde' => [
            'driver' => 'pgsql',
            'host' => '127.0.0.1',
            'port' => 1,
        ],
    ]);

    expect(BackendEndpoint::forDatabaseConnection()?->isReachable(2.0))
        ->toBeFalse();
});
