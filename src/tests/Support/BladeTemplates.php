<?php

declare(strict_types=1);

namespace Tests\Support;

use FilesystemIterator;
use RecursiveDirectoryIterator;
use RecursiveIteratorIterator;
use SplFileInfo;

/**
 * L'inventaire des templates Blade soumis aux scans de garde-fou.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * POURQUOI CETTE CLASSE EXISTE
 *
 * La même marche récursive vivait en DEUX exemplaires : `$storyTemplates` dans
 * `tests/Feature/BladeComponentsTest.php` (scan RÈGLE 1, valeurs en dur) et
 * `$scannedTemplates` dans `tests/Feature/LayoutsTest.php` (scan AC8/AC9, zéro
 * expression JS). Même `RecursiveIteratorIterator`, même `glob('_*demo*')`,
 * même `sort()`, et **le même nombre 16 écrit deux fois avec le même message**.
 *
 * Les deux copies avaient déjà commencé à diverger — seule celle de LayoutsTest
 * portait un mécanisme d'exemptions. C'est exactement le raisonnement qui a fait
 * extraire `BrowserAssertions` et `RouteTable` : dupliquer, c'est garantir
 * qu'une des copies dérivera en silence. Relevé à la revue de code du
 * 2026-08-08 — dans le commit même qui écrivait ce raisonnement.
 *
 * ⚠️ LE COMPTE VIT ICI, ET NULLE PART AILLEURS. Deux comptages indépendants
 * peuvent diverger ; un seul ne le peut pas.
 */
final class BladeTemplates
{
    /**
     * Le nombre de templates attendus sous le périmètre des scans.
     *
     * 12 composants (dont les 2 layouts et les 4 `<x-time-*>`) + 4 pages de
     * démonstration. Ce nombre RAIDIT volontairement : un fichier ajouté ou
     * retiré sans mise à jour consciente fait rougir les deux scans, au lieu de
     * sortir du périmètre en silence.
     */
    public const int EXPECTED_COUNT = 16;

    /**
     * Tous les templates soumis aux scans, chemins absolus, triés.
     *
     * La marche est RÉCURSIVE (un `glob` plat raterait `components/layouts/`) et
     * les pages de démonstration sont ramassées PAR MOTIF, jamais nommées une à
     * une : une démo ajoutée sortirait sinon du périmètre sans rien faire
     * rougir.
     *
     * ⚠️ LES EXEMPTIONS SE NOMMENT PAR CHEMIN RELATIF, PAS PAR NOM DE FICHIER.
     * Un filtre sur `basename()` exempterait d'un coup tous les homonymes de
     * tous les sous-dossiers — c'est le filtre par préfixe de la Story 1.11 sous
     * une autre forme, celui qui avait désarmé un garde-fou d'un seul caractère.
     * Corrigé à la revue du 2026-08-08.
     *
     * @param  list<string>  $exemptions chemins relatifs à `resources/`, un par fichier, avec son motif en commentaire au point d'appel
     * @return list<string>
     */
    public static function scanned(array $exemptions = []): array
    {
        $root = base_path('resources/views/components');

        $files = [];

        if (is_dir($root)) {
            $iterator = new RecursiveIteratorIterator(
                new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS),
            );

            foreach ($iterator as $file) {
                if ($file instanceof SplFileInfo && str_ends_with($file->getFilename(), '.blade.php')) {
                    $files[] = $file->getPathname();
                }
            }
        }

        foreach (glob(base_path('resources/views/_*demo*.blade.php')) ?: [] as $demo) {
            $files[] = $demo;
        }

        $files = array_values(array_filter(
            $files,
            static fn (string $path): bool => ! in_array(self::relative($path), $exemptions, true),
        ));

        sort($files);

        return $files;
    }

    /**
     * Le chemin relatif à la racine applicative — la forme sous laquelle une
     * exemption se nomme, et sous laquelle un message d'échec se lit.
     */
    public static function relative(string $path): string
    {
        return str_replace(base_path() . '/', '', $path);
    }
}
