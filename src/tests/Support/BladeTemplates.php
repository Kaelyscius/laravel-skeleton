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
     * 13 composants (dont les 2 layouts, les 4 `<x-time-*>` et
     * `<x-font-preloads>`) + 5 pages de démonstration. Ce nombre RAIDIT
     * volontairement : un fichier ajouté ou retiré sans mise à jour consciente
     * fait rougir les deux scans, au lieu de sortir du périmètre en silence.
     *
     * 16 → 18 en Story 1.9 : `<x-font-preloads>` est un COMPOSANT plutôt qu'un
     * partial de `resources/views/partials/` précisément pour rester dans ce
     * périmètre. Un fragment de <head> hors des scans serait le seul fichier
     * Blade du dépôt que ni la RÈGLE 1 ni le scan « zéro expression JS » ne
     * regarde.
     */
    public const int EXPECTED_COUNT = 18;

    /**
     * Le nombre de templates attendus sous le périmètre TOTAL — `all()`.
     *
     * Les 18 de `scanned()`, plus `welcome.blade.php` : la page servie par `/`,
     * qui n'est pas un composant et qui est pourtant, aujourd'hui, la SEULE
     * route atteignable hors `local`/`testing`.
     *
     * ⚠️ CE COMPTE EXISTE PARCE QUE LES DEUX PÉRIMÈTRES SONT LÉGITIMES, ET
     * DIFFÉRENTS. `scanned()` sert les scans qui parlent de nos CONVENTIONS
     * D'ÉCRITURE (RÈGLE 1, zéro expression JS) ; `all()` sert ceux qui parlent
     * d'un FAIT DE RENDU (les graisses de l'AC9). Une page qui n'est pas un
     * composant relève du second et pas du premier.
     *
     * 20 → 19 à la SECONDE passe de revue du 2026-08-09 : `vendor/pulse/`
     * en est sorti, voir le docblock d'`all()`.
     */
    public const int ALL_COUNT = 19;

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
     * TOUS les templates Blade de l'application, récursivement, triés.
     *
     * Le périmètre des scans qui parlent du RENDU plutôt que de nos conventions
     * d'écriture — aujourd'hui le scan des graisses de l'AC9 (Story 1.9). Une
     * graisse sans face self-hostée est un défaut partout où elle est écrite, y
     * compris dans une page qui n'est pas un composant : le repli CSS y est tout
     * aussi silencieux.
     *
     * ⛔ `resources/views/vendor/` EST HORS PÉRIMÈTRE, ET C'EST UNE DÉCISION —
     * arbitrage Alex du 2026-08-09, seconde passe de revue de la Story 1.9.
     *
     * La première rédaction disait l'inverse (« AUCUNE EXEMPTION, ET C'EST
     * VOULU »), au motif qu'une graisse non servie rend aussi mal dans une vue
     * de vendor que dans la nôtre. C'est vrai, et ce n'est pas suffisant :
     *
     *   1. On ne peut pas la corriger. `scanned()` porte déjà cette doctrine,
     *      mot pour mot, ligne 59 — c'était l'exception d'`all()` qui n'était
     *      pas argumentée, pas la règle de `scanned()`.
     *   2. Le déclencheur est `php artisan vendor:publish`, pas une écriture de
     *      code. Une publication de routine (mail, pagination, notifications)
     *      ferait rougir un garde-fou de GRAISSE pour une raison qui ne le
     *      regarde pas, sans correctif disponible. Un rouge légitime ET
     *      irréparable désarme par usure — c'est le motif déjà retenu contre le
     *      faux positif `italic` du même scan.
     *   3. Les vues publiées de Laravel Pulse embarquent leur propre style. Un
     *      faux-gras sur `/pulse` est un détail de surface d'administration, pas
     *      une régression du design system.
     *
     * ⚠️ `welcome.blade.php` N'EST PAS CONCERNÉ par cette exemption : ce n'est
     * pas du vendor, c'est notre page, et c'est la seule route atteignable en
     * production. Elle reste dans le périmètre.
     *
     * 📌 Ce que cette exemption NE couvre PAS, et qui est tracé : les vues de
     * modules (`app/Modules/<Nom>/Resources/views/`, ADR-0009) échappent à cette
     * marche, qui ne parcourt que `resources/views`. Reporté délibérément — ces
     * répertoires n'existent pas encore, et écrire la garde avant son objet est
     * le motif d'ADR-0011. Voir `deferred-work.md`, trigger « première vue de
     * module ».
     *
     * @return list<string>
     */
    public static function all(): array
    {
        $root = base_path('resources/views');

        if (! is_dir($root)) {
            return [];
        }

        $vendorRoot = $root . '/vendor/';

        $iterator = new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS),
        );

        $files = [];

        foreach ($iterator as $file) {
            if (! $file instanceof SplFileInfo || ! str_ends_with($file->getFilename(), '.blade.php')) {
                continue;
            }

            if (str_starts_with($file->getPathname(), $vendorRoot)) {
                continue;
            }

            $files[] = $file->getPathname();
        }

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
