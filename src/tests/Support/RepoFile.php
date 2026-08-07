<?php

declare(strict_types=1);

namespace Tests\Support;

use JsonException;
use RuntimeException;
use Symfony\Component\Yaml\Yaml;

/**
 * Lecture typée des fichiers du dépôt, pour les tests d'infrastructure.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * POURQUOI CETTE CLASSE EXISTE
 *
 * Les tests qui inspectent `docker-compose.yml`, `composer.json` ou un
 * `phpunit.xml` travaillent nécessairement sur des données non typées :
 * `Yaml::parseFile()` et `json_decode()` renvoient `mixed`, `file_get_contents()`
 * renvoie `string|false`. Chaque accès produisait donc son propre cast, et
 * PHPStan comptait 39 erreurs de ce seul motif au niveau 10 — pour trois
 * fichiers de tests.
 *
 * Le remède n'est pas de saupoudrer des `@var` : c'est de faire entrer les
 * données dans le typage UNE fois, ici, et bruyamment. Chaque méthode échoue
 * avec un message qui nomme le fichier plutôt que de renvoyer une valeur vague.
 *
 * ⚠️ Conséquence voulue : un fichier absent ou malformé fait échouer le test
 * avec une raison lisible, au lieu de produire un tableau vide sur lequel une
 * assertion `toBe([])` passerait tranquillement. Un test d'infrastructure qui
 * lit un fichier inexistant doit rougir, pas conclure.
 */
final class RepoFile
{
    /**
     * Racine du dépôt, résolue pour les deux dispositions d'exécution.
     *
     * Sur l'hôte, `src/tests/Support/` remonte de 3 niveaux jusqu'à la racine.
     * Dans le conteneur, `src/` est monté sur `/var/www/html` et la racine du
     * dépôt (où vivent les fichiers compose) est montée en lecture seule sur
     * `/var/www/project`.
     */
    public static function root(): string
    {
        foreach ([dirname(__DIR__, 3), '/var/www/project'] as $candidate) {
            if (file_exists($candidate . '/docker-compose.yml')) {
                return $candidate;
            }
        }

        return dirname(__DIR__, 3);
    }

    /**
     * Contenu brut d'un fichier, relatif à la racine du dépôt.
     */
    public static function read(string $relative): string
    {
        $path = self::root() . '/' . ltrim($relative, '/');
        $contents = file_get_contents($path);

        if ($contents === false) {
            throw new RuntimeException("Fichier illisible ou absent : {$path}");
        }

        return $contents;
    }

    /**
     * Décode un JSON du dépôt en tableau associatif.
     *
     * @return array<string, mixed>
     *
     * @throws JsonException
     */
    public static function json(string $relative): array
    {
        $decoded = json_decode(self::read($relative), true, 512, JSON_THROW_ON_ERROR);

        if (! is_array($decoded)) {
            throw new RuntimeException("{$relative} ne contient pas un objet JSON.");
        }

        /** @var array<string, mixed> $decoded */
        return $decoded;
    }

    /**
     * Parse un YAML du dépôt en tableau associatif.
     *
     * @return array<string, mixed>
     */
    public static function yaml(string $relative): array
    {
        $path = self::root() . '/' . ltrim($relative, '/');

        if (! file_exists($path)) {
            throw new RuntimeException("Fichier YAML absent : {$path}");
        }

        $parsed = Yaml::parseFile($path);

        if (! is_array($parsed)) {
            throw new RuntimeException("{$relative} ne contient pas une racine de type mapping.");
        }

        /** @var array<string, mixed> $parsed */
        return $parsed;
    }

    /**
     * Sous-tableau d'une structure décodée, à un chemin en notation pointée.
     *
     * Renvoie un tableau VIDE si le chemin n'existe pas — c'est volontaire :
     * l'absence d'une section (« aucun service ne porte ce profil ») est une
     * réponse légitime, contrairement à l'absence du fichier lui-même.
     *
     * @param  array<string, mixed>  $data
     * @return array<string, mixed>
     */
    public static function section(array $data, string $path): array
    {
        $cursor = $data;

        foreach (explode('.', $path) as $segment) {
            if (! is_array($cursor) || ! array_key_exists($segment, $cursor)) {
                return [];
            }

            $cursor = $cursor[$segment];
        }

        if (! is_array($cursor)) {
            return [];
        }

        /** @var array<string, mixed> $cursor */
        return $cursor;
    }

    /**
     * Valeur scalaire attendue en chaîne, à un chemin en notation pointée.
     *
     * Renvoie `null` si absente ou non scalaire, pour que l'appelant décide si
     * c'est un échec — toutes les clés ne sont pas obligatoires.
     *
     * @param  array<string, mixed>  $data
     */
    public static function stringAt(array $data, string $path): ?string
    {
        $cursor = $data;

        foreach (explode('.', $path) as $segment) {
            if (! is_array($cursor) || ! array_key_exists($segment, $cursor)) {
                return null;
            }

            $cursor = $cursor[$segment];
        }

        return is_scalar($cursor) ? (string) $cursor : null;
    }

    /**
     * Liste de chaînes à un chemin donné (profils Compose, labels…).
     *
     * @param  array<string, mixed>  $data
     * @return array<int, string>
     */
    public static function stringList(array $data, string $path): array
    {
        return array_values(array_map(
            static fn (mixed $value): string => is_scalar($value) ? (string) $value : '',
            array_filter(self::section($data, $path), static fn (mixed $v): bool => is_scalar($v)),
        ));
    }
}
