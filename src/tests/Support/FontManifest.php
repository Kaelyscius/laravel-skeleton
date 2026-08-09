<?php

declare(strict_types=1);

namespace Tests\Support;

use RuntimeException;

/**
 * Lecture TYPÉE de `resources/fonts.json` — Story 1.9, AC2.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * POURQUOI CETTE CLASSE EXISTE
 *
 * Trois fichiers de tests dérivent leurs attentes de la table : `Feature/FontsTest`
 * (paquets, @font-face, preloads, graisses) et `Browser/FontsTest` (faces
 * chargées, origines, preloads effectifs). Chacun aurait sinon son propre
 * `json_decode` + ses propres casts — et PHPStan au niveau 10 comptabilise
 * chaque accès `mixed`. C'est le raisonnement qui a fait naître RepoFile,
 * BrowserAssertions, RouteTable et BladeTemplates : extraire d'abord.
 *
 * ⚠️ ELLE VALIDE BRUYAMMENT, ET C'EST LA MOITIÉ DE SON UTILITÉ. Une entrée sans
 * `target`, un `weight` écrit en chaîne, un `preload` absent : chacun ferait
 * échouer un test plus loin, sur une assertion qui ne nommerait pas la cause. Ici
 * l'échec nomme l'index et le champ.
 *
 * ⛔ ELLE NE RECOPIE AUCUNE VALEUR. Écrire ici la liste attendue des faces ferait
 * de cette classe une SECONDE table, capable de diverger de la première — le
 * défaut exact que la table unique existe pour éliminer.
 *
 * @phpstan-type Face array{package: string, source: string, target: string, family: string, weight: int, preload: bool}
 * @phpstan-type Asset array{package: string, source: string, target: string}
 */
final class FontManifest
{
    /**
     * Chemin relatif à la racine du DÉPÔT (pas à celle de l'application) : c'est
     * la convention de RepoFile, qui résout les deux dispositions d'exécution.
     */
    public const string PATH = 'src/resources/fonts.json';

    /**
     * Les faces self-hostées, dans l'ordre de la table.
     *
     * @return list<Face>
     */
    public static function faces(): array
    {
        $faces = [];

        foreach (self::entries('faces') as $index => $entry) {
            $fields = self::assoc($entry, 'faces', $index);

            $faces[] = [
                'package' => self::string($fields, 'package', 'faces', $index),
                'source' => self::string($fields, 'source', 'faces', $index),
                'target' => self::string($fields, 'target', 'faces', $index),
                'family' => self::string($fields, 'family', 'faces', $index),
                'weight' => self::int($fields, 'weight', 'faces', $index),
                'preload' => self::bool($fields, 'preload', 'faces', $index),
            ];
        }

        return $faces;
    }

    /**
     * Les seules faces qui portent un `<link rel="preload">`.
     *
     * @return list<Face>
     */
    public static function preloaded(): array
    {
        return array_values(array_filter(
            self::faces(),
            static fn (array $face): bool => $face['preload'],
        ));
    }

    /**
     * Les licences SIL OFL redistribuées à côté des woff2.
     *
     * ⚠️ DEUX fichiers, pas un. Les LICENSE des deux paquets ne sont PAS
     * identiques : leur première ligne porte la notice de copyright de la fonte
     * concernée (2019 / IBM Plex Sans, 2017 / IBM Plex Mono). N'en redistribuer
     * qu'une perdrait celle de l'autre, ce que l'OFL §1 interdit précisément.
     *
     * @return list<Asset>
     */
    public static function licenses(): array
    {
        $licenses = [];

        foreach (self::entries('licenses') as $index => $entry) {
            $fields = self::assoc($entry, 'licenses', $index);

            $licenses[] = [
                'package' => self::string($fields, 'package', 'licenses', $index),
                'source' => self::string($fields, 'source', 'licenses', $index),
                'target' => self::string($fields, 'target', 'licenses', $index),
            ];
        }

        return $licenses;
    }

    /**
     * Décrit un ensemble de faces sous la forme `Famille/graisse`.
     *
     * Elle vit ICI, et pas en closure locale à un test, pour une raison de
     * typage : la forme `Face` n'est connue que de ce fichier. Une closure de
     * test recevant un `array` nu redevient `mixed` à chaque accès, et PHPStan
     * au niveau 10 le compte quatre fois.
     *
     * @param  list<Face>  $faces
     * @return list<string>
     */
    public static function describe(array $faces): array
    {
        $described = [];

        foreach ($faces as $face) {
            $described[] = $face['family'] . '/' . $face['weight'];
        }

        return $described;
    }

    /**
     * Tout ce que `public/fonts/` doit contenir — et rien d'autre (AC3).
     *
     * @return list<string>
     */
    public static function servedFiles(): array
    {
        return array_merge(
            array_map(static fn (array $face): string => $face['target'], self::faces()),
            array_map(static fn (array $license): string => $license['target'], self::licenses()),
        );
    }

    /**
     * Les graisses servies dans les familles MONOSPACE — le référent du scan de
     * l'AC9 qui rapproche `font-mono` d'une graisse.
     *
     * ⚠️ Cette méthode s'appelait `weightsByFamily()` et n'avait AUCUN appelant :
     * un seul hit dans tout `src/`, sa propre déclaration, sous un docblock qui
     * la désignait « le référent de l'AC9 » pendant que le scanner construisait
     * sa carte à la main. C'est le motif dominant du projet — l'affirmation avant
     * son référent — à l'intérieur de la story écrite pour le traquer. Relevé à
     * la revue du 2026-08-09 : elle a désormais un consommateur, ou elle n'existe
     * pas.
     *
     * @return array<int, true> les graisses servies en mono, en CLÉS (le scan teste `isset`)
     */
    public static function monospaceWeights(): array
    {
        $weights = [];

        foreach (self::faces() as $face) {
            if (str_contains(mb_strtolower($face['family']), 'mono')) {
                $weights[$face['weight']] = true;
            }
        }

        return $weights;
    }

    /**
     * Toutes les graisses servies, familles confondues — le référent du scan de
     * l'AC9 qui interdit une utility sans face.
     *
     * ⚠️ L'UNION est délibérée, et sa limite est écrite plutôt que tue : sans
     * navigateur, on ne peut pas savoir quelle famille s'applique à un élément
     * quelconque. Le cas déterminable — `font-mono` et une graisse dans le même
     * attribut — est traité séparément par `monospaceWeights()`.
     *
     * @return array<int, true>
     */
    public static function servedWeights(): array
    {
        $weights = [];

        foreach (self::faces() as $face) {
            $weights[$face['weight']] = true;
        }

        return $weights;
    }

    /**
     * Les entrées brutes d'une section, ou un échec qui nomme la section.
     *
     * Une section vide est un ÉCHEC, pas une réponse : un test qui itère sur
     * zéro face passerait par vacuité, ce qui est le défaut que toute cette
     * story existe pour ne pas produire.
     *
     * @return list<mixed>
     */
    private static function entries(string $section): array
    {
        $raw = RepoFile::json(self::PATH)[$section] ?? null;

        if (! is_array($raw) || $raw === []) {
            throw new RuntimeException(self::PATH . " ne décrit aucune entrée sous [{$section}].");
        }

        return array_values($raw);
    }

    /**
     * @return array<string, mixed>
     */
    private static function assoc(mixed $entry, string $section, int $index): array
    {
        if (! is_array($entry)) {
            throw new RuntimeException(self::PATH . " : l'entrée {$section}[{$index}] n'est pas un objet.");
        }

        /** @var array<string, mixed> $entry */
        return $entry;
    }

    /**
     * @param  array<string, mixed>  $fields
     */
    private static function string(array $fields, string $key, string $section, int $index): string
    {
        $value = $fields[$key] ?? null;

        if (! is_string($value) || $value === '') {
            throw new RuntimeException(self::PATH . " : {$section}[{$index}].{$key} doit être une chaîne non vide.");
        }

        return $value;
    }

    /**
     * @param  array<string, mixed>  $fields
     */
    private static function int(array $fields, string $key, string $section, int $index): int
    {
        $value = $fields[$key] ?? null;

        if (! is_int($value)) {
            throw new RuntimeException(self::PATH . " : {$section}[{$index}].{$key} doit être un entier (pas une chaîne).");
        }

        return $value;
    }

    /**
     * @param  array<string, mixed>  $fields
     */
    private static function bool(array $fields, string $key, string $section, int $index): bool
    {
        $value = $fields[$key] ?? null;

        if (! is_bool($value)) {
            throw new RuntimeException(self::PATH . " : {$section}[{$index}].{$key} doit être un booléen.");
        }

        return $value;
    }
}
