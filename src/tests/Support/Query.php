<?php

declare(strict_types=1);

namespace Tests\Support;

use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Lecture typée d'une valeur scalaire renvoyée par une requête à une ligne.
 *
 * `DB::selectOne()` renvoie `object|null` : chaque accès de propriété est donc
 * `mixed`, et chaque sentinelle refaisait son propre `(int) $row->x`. PHPStan
 * comptait 7 erreurs de ce seul motif au niveau 10.
 *
 * L'intérêt dépasse le typage : une requête qui ne renvoie rien, ou une colonne
 * absente, lève ici une exception qui nomme la requête — au lieu de produire un
 * `(int) null === 0` sur lequel une assertion pourrait passer par accident.
 * Les sentinelles de ce projet existent précisément pour ne pas conclure à tort.
 */
final class Query
{
    /**
     * Valeur entière d'une colonne, sur une requête à une seule ligne.
     */
    public static function int(string $sql, string $column): int
    {
        $value = self::scalar($sql, $column);

        if (! is_numeric($value)) {
            throw new RuntimeException("La colonne « {$column} » n'est pas numérique : {$sql}");
        }

        return (int) $value;
    }

    /**
     * Valeur en chaîne d'une colonne, sur une requête à une seule ligne.
     */
    public static function string(string $sql, string $column): string
    {
        $value = self::scalar($sql, $column);

        if (! is_scalar($value)) {
            throw new RuntimeException("La colonne « {$column} » n'est pas scalaire : {$sql}");
        }

        return (string) $value;
    }

    private static function scalar(string $sql, string $column): mixed
    {
        $row = DB::selectOne($sql);

        // `selectOne()` est typé `mixed` : on exige explicitement un objet plutôt
        // que de supposer. Une requête sans résultat renvoie null.
        if (! is_object($row)) {
            throw new RuntimeException("Requête sans résultat : {$sql}");
        }

        if (! property_exists($row, $column)) {
            throw new RuntimeException("Colonne « {$column} » absente du résultat : {$sql}");
        }

        return $row->{$column};
    }
}
