<?php

declare(strict_types=1);

namespace App\HealthChecks\Support;

/**
 * Point de terminaison TCP d'une dépendance, et sonde de joignabilité BORNÉE.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * 🔴 POURQUOI CETTE CLASSE EXISTE : LA LIGNE « SONDE LENTE » DE LA MATRICE
 *
 * La matrice gelée de la story exige « réponse BORNÉE dans le temps ». La
 * première implémentation ne bornait qu'ENTRE les sondes (budget cumulé) : la
 * PREMIÈRE tournait sans borne et consommait tout le délai à elle seule.
 *
 * Mesuré sur cette pile, conteneur postgres RÉELLEMENT arrêté :
 *
 *   gethostbyname('postgres')            →  3,13 s   (l'alias ne résout plus)
 *   DB::connection()->select('SELECT 1') → 12,5 s    (le framework REJOUE)
 *   sonde `database` via /health         → 31,2 s    (~10 tentatives)
 *   réponse HTTP complète                → 58,6 s    contre 60 s de passerelle
 *
 * Le coût unitaire est la RÉSOLUTION DE NOM ; le facteur ×10 est la reprise
 * automatique du framework. `PDO::ATTR_TIMEOUT` ne borne ni l'un ni l'autre —
 * essayé, mesuré (3,13 s que le timeout vaille 2, 5 ou rien), retiré.
 *
 * APRÈS ce portillon, MÊME PANNE, MÊME PILE — mesure finale du 2026-08-23,
 * php-fpm redémarré : `/health` rend `503` avec son corps complet en
 * **4,05 · 3,19 · 3,21 s**. Le facteur ×10 a disparu ; le coût unitaire de la
 * résolution (~3,1 s), non.
 *
 * ⚠️ Une mesure HTTP prise sans redémarrer php-fpm après édition lit l'ANCIENNE
 * classe — mesuré : 15 à 16 s, résumé « Failed », donc sans portillon.
 *
 * ⚖️ CE QUI EST BORNÉ ICI, ET CE QUI NE PEUT PAS L'ÊTRE :
 *
 *   • le nombre de tentatives passe de ~10 à UNE. C'est le facteur qui compte ;
 *   • la CONNEXION est bornée par le timeout passé à `fsockopen()` ;
 *   • ⛔ la RÉSOLUTION DE NOM ne l'est pas — ni `fsockopen`, ni libpq, ni PDO
 *     n'exposent de borne dessus, et PHP ne peut pas interrompre un appel
 *     bloquant sans `pcntl`, indisponible sous FPM. Le plancher pratique reste
 *     donc le délai du résolveur (3,13 s ici), UNE fois par sonde.
 *
 * ⚠️ TROIS LIMITES CONNUES, ÉCRITES PLUTÔT QUE DÉCOUVERTES (revue 2) :
 *
 *   • un hôte à PLUSIEURS enregistrements A : `fsockopen()` n'essaie qu'une
 *     adresse. Le portillon peut donc refuser alors qu'une autre adresse
 *     répondrait — un `503` nommant un backend en réalité joignable. C'est le
 *     seul faux négatif possible de ce mécanisme, et il a une porte de sortie :
 *     `HEALTH_PROBE_GATE=false` (`health.probe_gate_enabled`) le désarme
 *     entièrement, au prix du retour aux ~10 tentatives ;
 *   • les pilotes SANS couple hôte/port (`sqs`, `dynamodb`, `sqlite`, socket
 *     unix, `array`, `sync`…) rendent `null` : le portillon ne s'applique pas,
 *     et la sonde travaille comme avant. `null` ne veut JAMAIS dire
 *     « injoignable » ;
 *   • un socket ouvert ne prouve ni l'authentification, ni le droit d'écrire.
 *
 * ⛔ CE N'EST PAS UN REMPLACEMENT DE LA SONDE. Un socket qui s'ouvre ne prouve
 * ni l'authentification, ni le droit d'écrire, ni qu'un Redis n'est pas en
 * `MISCONF`. La sonde fait toujours son aller-retour applicatif ensuite ; ce
 * portillon ne sert qu'à ÉCHOUER VITE, jamais à conclure au vert.
 */
final class BackendEndpoint
{
    private function __construct(
        public readonly string $host,
        public readonly int $port,
    ) {
    }

    /**
     * Ports par défaut, quand la configuration n'en déclare pas.
     *
     * @var array<string, int>
     */
    private const DEFAULT_PORTS = [
        'pgsql' => 5432,
        'mysql' => 3306,
        'mariadb' => 3306,
        'sqlsrv' => 1433,
    ];

    /**
     * Point de terminaison d'une connexion base de données.
     *
     * Rend `null` quand il n'y a rien à joindre par TCP — `sqlite`, ou un hôte
     * qui est en réalité un socket unix (`/var/run/...`). Un `null` signifie
     * « pas de portillon applicable », JAMAIS « injoignable ».
     */
    public static function forDatabaseConnection(?string $name = null): ?self
    {
        $name ??= self::stringConfig('database.default');

        if ($name === null) {
            return null;
        }

        $driver = self::stringConfig("database.connections.{$name}.driver");

        if ($driver === null || ! array_key_exists($driver, self::DEFAULT_PORTS)) {
            return null;
        }

        /*
         * ⚠️ `url` D'ABORD — c'est `DATABASE_URL`, et il PRIME sur `host`/`port`
         * dans le framework (`ConfigurationUrlParser`). Le lire après aurait
         * laissé le portillon muet sur toute installation « cloud », qui est
         * précisément celle où une base injoignable coûte le plus cher.
         * Relevé en revue 2.
         */
        $fromUrl = self::fromUrl(self::stringConfig("database.connections.{$name}.url"), self::DEFAULT_PORTS[$driver]);

        if ($fromUrl instanceof self) {
            return $fromUrl;
        }

        return self::make(
            self::hostConfig("database.connections.{$name}.host"),
            self::intConfig("database.connections.{$name}.port") ?? self::DEFAULT_PORTS[$driver],
        );
    }

    /**
     * Point de terminaison du magasin de cache.
     */
    public static function forCacheStore(?string $name = null): ?self
    {
        $name ??= self::stringConfig('cache.default');

        if ($name === null) {
            return null;
        }

        return match (self::stringConfig("cache.stores.{$name}.driver")) {
            'redis' => self::forRedisConnection(
                self::stringConfig("cache.stores.{$name}.connection") ?? 'cache',
            ),
            'database' => self::forDatabaseConnection(
                self::stringConfig("cache.stores.{$name}.connection"),
            ),
            // `memcached` déclare ses serveurs en liste ; on sonde le premier.
            'memcached' => self::make(
                self::hostConfig("cache.stores.{$name}.servers.0.host"),
                self::intConfig("cache.stores.{$name}.servers.0.port") ?? 11211,
            ),
            // ⛔ `dynamodb`, `octane`, `array`, `file`, `null`, `failover` :
            // pas de couple hôte/port à sonder (API HTTP, mémoire, disque, ou
            // composition d'autres magasins). `null` dit « portillon non
            // applicable », jamais « injoignable ».
            default => null,
        };
    }

    /**
     * Point de terminaison du backend de file.
     *
     * ⚠️ `sqs` et `beanstalkd` rendent `null` VOLONTAIREMENT : le premier est
     * une API HTTP (pas un couple hôte/port), le second n'a pas de port par
     * défaut dans la configuration de ce dépôt. Le portillon ne s'applique pas ;
     * la sonde fait son aller-retour comme avant.
     */
    public static function forQueueConnection(?string $name = null): ?self
    {
        $name ??= self::stringConfig('queue.default');

        if ($name === null) {
            return null;
        }

        return match (self::stringConfig("queue.connections.{$name}.driver")) {
            'redis' => self::forRedisConnection(
                self::stringConfig("queue.connections.{$name}.connection") ?? 'default',
            ),
            'database' => self::forDatabaseConnection(
                self::stringConfig("queue.connections.{$name}.connection"),
            ),
            'beanstalkd' => self::make(
                self::hostConfig("queue.connections.{$name}.host"),
                self::intConfig("queue.connections.{$name}.port") ?? 11300,
            ),
            // ⛔ `sqs` est une API HTTP (pas de couple hôte/port) ; `sync`,
            // `null`, `deferred`, `background` n'ont aucun backend.
            default => null,
        };
    }

    public static function forRedisConnection(string $name): ?self
    {
        // `REDIS_URL` prime lui aussi sur hôte/port (`redis.{conn}.url`).
        $fromUrl = self::fromUrl(self::stringConfig("database.redis.{$name}.url"), 6379);

        if ($fromUrl instanceof self) {
            return $fromUrl;
        }

        return self::make(
            self::hostConfig("database.redis.{$name}.host"),
            self::intConfig("database.redis.{$name}.port") ?? 6379,
        );
    }

    /**
     * Point de terminaison extrait d'une URL de connexion, ou `null`.
     */
    private static function fromUrl(?string $url, int $defaultPort): ?self
    {
        if ($url === null) {
            return null;
        }

        $parts = parse_url($url);

        if (! is_array($parts) || ! isset($parts['host']) || ! is_string($parts['host'])) {
            return null;
        }

        $port = $parts['port'] ?? null;

        return self::make($parts['host'], is_int($port) ? $port : $defaultPort);
    }

    /**
     * Hôte d'une clé de configuration, y compris quand elle porte une LISTE.
     *
     * 🔴 RELEVÉ EN REVUE 2 : `host` accepte un TABLEAU (répartition
     * lecture/écriture, ou plusieurs hôtes pour une même connexion). La
     * rédaction précédente n'acceptait qu'une chaîne, donc rendait `null`, donc
     * DÉSACTIVAIT LE PORTILLON EN SILENCE sur exactement les déploiements où il
     * compte le plus.
     *
     * ⚖️ On sonde le PREMIER hôte déclaré. C'est une réponse partielle, et
     * c'est assumé : le portillon est un raccourci d'échec, pas un verdict —
     * s'il laisse passer, la sonde fait quand même son aller-retour complet.
     */
    private static function hostConfig(string $key): ?string
    {
        $value = config($key);

        if (is_array($value)) {
            foreach ($value as $candidate) {
                if (is_string($candidate) && $candidate !== '') {
                    return $candidate;
                }
            }

            return null;
        }

        return is_string($value) && $value !== '' ? $value : null;
    }

    /**
     * Ouvre puis referme un socket, dans la limite du délai imparti.
     *
     * ⛔ UNE SEULE TENTATIVE, ET C'EST TOUT L'INTÉRÊT : c'est la reprise
     * automatique du framework (~10 tentatives) qui transformait 3 s en 31 s.
     */
    public function isReachable(float $timeoutSeconds): bool
    {
        $errno = 0;
        $error = '';

        $socket = @fsockopen($this->host, $this->port, $errno, $error, $timeoutSeconds);

        if ($socket === false) {
            return false;
        }

        fclose($socket);

        return true;
    }

    /**
     * Désignation SANS IDENTIFIANT, sûre à publier et à journaliser.
     *
     * 🔒 Ni utilisateur, ni mot de passe, ni nom de base — seulement le couple
     * hôte/port, qui est déjà connu de quiconque peut atteindre l'application.
     */
    public function label(): string
    {
        return $this->host . ':' . $this->port;
    }

    private static function make(?string $host, int $port): ?self
    {
        // Un hôte vide, ou un chemin de socket unix : rien à joindre par TCP.
        if ($host === null || $host === '' || str_starts_with($host, '/')) {
            return null;
        }

        if ($port <= 0 || $port > 65535) {
            return null;
        }

        return new self($host, $port);
    }

    private static function stringConfig(string $key): ?string
    {
        $value = config($key);

        return is_string($value) && $value !== '' ? $value : null;
    }

    private static function intConfig(string $key): ?int
    {
        $value = config($key);

        return is_numeric($value) ? (int) $value : null;
    }
}
