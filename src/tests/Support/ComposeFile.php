<?php

declare(strict_types=1);

namespace Tests\Support;

/**
 * Interrogation typée des fichiers docker-compose.
 *
 * Les tests de profils posaient tous la même question — « quels services
 * portent tel profil ? » — en réécrivant à chaque fois le même
 * `array_filter` sur des `mixed`. D'où 17 erreurs PHPStan au niveau 10 dans un
 * seul fichier, et une intention noyée dans la plomberie.
 *
 * Les méthodes renvoient des listes de NOMS de services, triées : c'est ce que
 * les assertions comparent, et le tri rend l'échec lisible (un diff de deux
 * listes ordonnées) au lieu d'un ordre de déclaration arbitraire.
 */
final class ComposeFile
{
    /**
     * Services déclarés, fusionnés dans l'ordre des fichiers donnés.
     *
     * La fusion est volontairement plate : un service redéfini dans un fichier
     * d'override remplace entièrement l'entrée précédente, ce qui correspond au
     * seul usage qu'en font ces tests (chercher un profil ou un label).
     *
     * @return array<string, array<string, mixed>>
     */
    public static function services(string ...$files): array
    {
        $services = [];

        foreach ($files as $file) {
            foreach (RepoFile::section(RepoFile::yaml($file), 'services') as $name => $definition) {
                if (is_array($definition)) {
                    /** @var array<string, mixed> $definition */
                    $services[(string) $name] = $definition;
                }
            }
        }

        return $services;
    }

    /**
     * Noms des services portant le profil donné.
     *
     * @param  array<string, array<string, mixed>>  $services
     * @return array<int, string>
     */
    public static function withProfile(array $services, string $profile): array
    {
        return self::sortedNames($services, static function (array $definition) use ($profile): bool {
            $profiles = $definition['profiles'] ?? [];

            return is_array($profiles) && in_array($profile, $profiles, true);
        });
    }

    /**
     * Noms des services SANS aucun profil — c'est-à-dire ceux que
     * `docker compose up` démarre par défaut : le socle de production.
     *
     * @param  array<string, array<string, mixed>>  $services
     * @return array<int, string>
     */
    public static function withoutProfile(array $services): array
    {
        return self::sortedNames($services, static function (array $definition): bool {
            $profiles = $definition['profiles'] ?? [];

            return ! is_array($profiles) || $profiles === [];
        });
    }

    /**
     * Noms des services portant le label donné (forme `clé=valeur`).
     *
     * @param  array<string, array<string, mixed>>  $services
     * @return array<int, string>
     */
    public static function withLabel(array $services, string $label): array
    {
        return self::sortedNames($services, static function (array $definition) use ($label): bool {
            $labels = $definition['labels'] ?? [];

            return is_array($labels) && in_array($label, $labels, true);
        });
    }

    /**
     * @param  array<string, array<string, mixed>>  $services
     * @param  callable(array<string, mixed>): bool  $matches
     * @return array<int, string>
     */
    private static function sortedNames(array $services, callable $matches): array
    {
        $names = array_keys(array_filter($services, $matches));
        sort($names);

        return $names;
    }
}
