<?php

declare(strict_types=1);

namespace Tests\Support;

/**
 * Dégradations RÉELLES de dépendances, pour éprouver `/health`.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * ⛔ AUCUN MOCK, ET C'EST L'INTÉRÊT DE CE FICHIER.
 *
 * L'AC de la story 2.4 dit : « observé en coupant, pas simulé par un mock ». Un
 * `Cache::shouldReceive('put')->andThrow(...)` prouverait que la sonde attrape
 * l'exception qu'on lui a demandé de lever — il ne prouverait rien de ce que
 * fait un vrai pilote face à un vrai backend absent. Ici, la connexion est
 * réellement ouverte vers un port réellement fermé.
 *
 * ⚖️ POURQUOI `127.0.0.1` PORT 1, ET PAS UN NOM D'HÔTE INEXISTANT :
 * un nom qui ne résout pas coûte le délai du résolveur — mesuré à **3,13 s**
 * dans le conteneur php de ce projet, et davantage en CI. Une boucle locale sur
 * un port fermé rend `ECONNREFUSED` en **0,00 s** (mesuré au `fsockopen`). La
 * suite reste donc rapide tout en éprouvant le VRAI chemin d'échec du pilote.
 * Le port 1 (`tcpmux`) n'est écouté par rien sur un runner GitHub ni dans les
 * conteneurs de ce dépôt.
 *
 * ⚠️ Ces méthodes n'écrasent JAMAIS la connexion par défaut du dépôt : elles
 * DÉCLARENT une connexion supplémentaire et déplacent le pointeur `default`.
 * Casser `database.connections.pgsql` en place ferait échouer le démontage des
 * transactions des tests qui l'utilisent, et l'échec ne parlerait plus de
 * `/health`.
 */
final class UnreachableBackends
{
    /**
     * Nom de la connexion/du magasin/de la file dégradés.
     */
    public const NAME = 'health_probe_unreachable';

    /**
     * Mot de passe SENTINELLE de la connexion dégradée.
     *
     * Il n'ouvre rien : le port est fermé. Il existe pour qu'un test puisse
     * affirmer, sans ambiguïté, qu'AUCUN identifiant n'a fuité dans le corps
     * de `/health` — un mot de passe réel de configuration serait, lui,
     * indiscernable d'une chaîne quelconque.
     */
    public const SENTINEL_PASSWORD = 'sentinelle-jamais-affichee-par-health';

    /**
     * Nom de la connexion dont l'HÔTE NE RÉSOUT PAS (chemin lent).
     */
    public const UNRESOLVABLE = 'health_probe_unresolvable';

    /**
     * Déclare une connexion base de données pointant sur un port fermé.
     *
     * Ne change rien d'autre : appelez `asDefaultDatabase()` pour que les
     * sondes la rencontrent.
     */
    public static function declareDatabaseConnection(): void
    {
        /** @var array<string, mixed> $pgsql */
        $pgsql = (array) config('database.connections.pgsql');

        config([
            'database.connections.' . self::NAME => array_merge($pgsql, [
                'host' => '127.0.0.1',
                'port' => 1,
                'password' => self::SENTINEL_PASSWORD,
            ]),
        ]);
    }

    /**
     * Rend injoignable la base que `DatabaseHealthCheck` interroge.
     */
    public static function asDefaultDatabase(): void
    {
        self::declareDatabaseConnection();

        config([
            'database.default' => self::NAME,
        ]);
    }

    /**
     * Rend injoignable le magasin de cache que `CacheHealthCheck` interroge.
     *
     * Pilote `database` sur la connexion morte : aucune extension n'est
     * requise (ni phpredis, ni memcached), donc la sonde vaut aussi bien dans
     * le conteneur que sur le runner nu.
     */
    public static function asDefaultCache(): void
    {
        self::declareDatabaseConnection();

        config([
            'cache.stores.' . self::NAME => [
                'driver' => 'database',
                'connection' => self::NAME,
                'table' => 'cache',
                'lock_connection' => self::NAME,
                'lock_table' => 'cache_locks',
            ],
            'cache.default' => self::NAME,
        ]);
    }

    /**
     * Magasin de cache AMNÉSIQUE : il accepte l'écriture et ne rend rien.
     *
     * 🔴 C'EST LE SEUL ÉTAT QUI ÉPROUVE LA COMPARAISON DE `CacheHealthCheck`.
     * Un backend injoignable fait LEVER le pilote — la sonde serait rouge même
     * sans comparer quoi que ce soit. Sans ce cas, retirer la comparaison
     * laisserait toute la suite VERTE : un garde-fou qui ne garde rien, dans la
     * classe même que cette story écrit pour supprimer ce défaut.
     *
     * Le pilote `null` de Laravel (`NullStore`) est exactement ce comportement :
     * ⚠️ vérifié dans `vendor/` (revue 1 — la rédaction précédente affirmait le
     * contraire), `NullStore::put()` rend **`false`** et `get()` rend `null`.
     * C'est ce qui rend le cas intéressant : la sonde n'inspecte PAS la valeur
     * de retour de `put()` — elle relit et COMPARE. Un magasin qui rendrait
     * `true` en n'écrivant rien serait attrapé exactement de la même façon.
     * C'est aussi le mode de défaillance RÉEL d'un Redis en `MISCONF` ou d'un
     * répertoire de cache repassé en lecture seule.
     */
    public static function asAmnesiacCache(): void
    {
        config([
            'cache.stores.' . self::NAME . '_amnesiac' => [
                'driver' => 'null',
            ],
            'cache.default' => self::NAME . '_amnesiac',
        ]);
    }

    /**
     * Rend injoignable le backend de file que `QueueHealthCheck` interroge.
     */
    public static function asDefaultQueue(): void
    {
        self::declareDatabaseConnection();

        config([
            'queue.connections.' . self::NAME => [
                'driver' => 'database',
                'connection' => self::NAME,
                'table' => 'jobs',
                'queue' => 'default',
                'retry_after' => 90,
            ],
            'queue.default' => self::NAME,
        ]);
    }

    /**
     * Rend la base INTROUVABLE PAR LE RÉSOLVEUR — le chemin LENT.
     *
     * 🔴 CE CAS EST DIFFÉRENT DE TOUS LES AUTRES, ET LA REVUE 1 A RELEVÉ QUE
     * SON ABSENCE VIDAIT LA LIGNE « SONDE LENTE » DE LA MATRICE.
     * `127.0.0.1:1` rend `ECONNREFUSED` : le pilote n'essaie même pas de
     * résoudre. Ici il RÉSOUT, et échoue — deux chemins de code différents
     * dans libpq comme dans phpredis.
     *
     * ⛔ CE N'EST PAS « LE CHEMIN LENT », ET LE PRÉTENDRE SERAIT FAUX (corrigé
     * en revue 2). Remesuré le 2026-08-23, `fsockopen(…, 2.0)` dans le
     * conteneur php :
     *
     *     health-probe.nowhere.invalid   0,0149 s   ← NXDOMAIN immédiat
     *     postgres-arrete-fictif         2,5247 s   ← nom non qualifié
     *     postgres (conteneur arrêté)    3,13   s   ← le vrai mode de panne
     *
     * `.invalid` est réservé par la RFC 2606 : aucun résolveur ne le cherche,
     * donc la réponse est immédiate ET reproductible sur un runner nu comme en
     * conteneur. C'est précisément ce qu'on veut d'un test unitaire : le
     * CHEMIN de code (résolution en échec), pas sa durée. La durée, elle, n'est
     * un observable fiable dans aucun environnement — les tests qui en
     * dépendent assertent le NOMBRE DE TENTATIVES.
     */
    public static function asUnresolvableDatabase(): void
    {
        /** @var array<string, mixed> $pgsql */
        $pgsql = (array) config('database.connections.pgsql');

        config([
            'database.connections.' . self::UNRESOLVABLE => array_merge($pgsql, [
                'host' => 'health-probe.nowhere.invalid',
                'password' => self::SENTINEL_PASSWORD,
            ]),
            'database.default' => self::UNRESOLVABLE,
        ]);
    }

    /**
     * Rend injoignable le magasin de SESSION — pas une dépendance de `/health`,
     * mais la preuve que la route est bien hors du groupe `web`.
     */
    public static function asDefaultSession(): void
    {
        self::declareDatabaseConnection();

        config([
            'session.driver' => 'database',
            'session.connection' => self::NAME,
            'session.table' => 'sessions',
        ]);
    }
}
