<?php

declare(strict_types=1);

/*
|--------------------------------------------------------------------------
| Faces self-hostées — la table de resources/fonts.json, côté PHP
|--------------------------------------------------------------------------
|
| Story 1.9, AC2/AC4/AC5. Ce fichier ne DÉCLARE rien : il expose la table unique
| au rendu, qui en dérive ses <link rel="preload"> ET ses @font-face.
|
| POURQUOI PASSER PAR LA CONFIG PLUTÔT QUE LIRE LE JSON DANS LE BLADE
|
| ⚠️ La première rédaction disait « un file_get_contents dans un template
| s'exécuterait à chaque rendu de chaque page ». C'est faux, et corrigé à la
| revue du 2026-08-09 : le composant est rendu une fois par requête, exactement
| comme la config est chargée une fois par requête. Le gain réel est ailleurs, et
| il est entier : `php artisan config:cache` fige cette table dans un tableau PHP
| compilé, et la lecture disque disparaît alors complètement en production — ce
| qu'un `file_get_contents` dans un template ne pourrait jamais offrir.
|
| ⚠️ L'ÉCHEC EST BRUYANT, ET C'EST VOULU. L'alternative — un `?? []` défensif —
| rendrait zéro preload, zéro @font-face, une page en fonte système et aucun test
| rouge : la forme exacte du garde-fou silencieux que cette story existe pour ne
| pas produire.
|
| ⚠️ ET IL EST BRUYANT SUR LES QUATRE FORMES, PAS SEULEMENT SUR LE JSON CASSÉ.
| La première rédaction ne contrôlait que `is_array($manifest['faces'] ?? null)`,
| qui est VRAI pour `[]` : une table tronquée démarrait proprement, ne rendait
| rien, et ne levait pas. Un fichier absent donnait un `JsonException: Syntax
| error` qui ne nommait pas le fichier manquant. Une ligne sans `target` levait
| « Undefined array key » à chaque rendu de chaque page. Et un `preload` écrit
| `"false"` (chaîne) est truthy : les quatre faces auraient été préchargées. Les
| quatre sont refusées ici, au boot, en nommant l'index. Relevé à la revue du
| 2026-08-09.
|
| ⛔ NE PAS ajouter de face ici. La table vit dans resources/fonts.json, que
| lisent aussi vite.config.js et tests/Support/FontManifest.php. Une seconde
| liste, même exacte le jour où elle est écrite, est une liste qui dérivera.
*/

$path = resource_path('fonts.json');

if (! is_file($path)) {
    throw new RuntimeException("resources/fonts.json est introuvable [{$path}] : aucune face ne peut être servie.");
}

$raw = file_get_contents($path);

/*
 * La CINQUIÈME forme d'échec, relevée à la seconde passe de revue du
 * 2026-08-09 : un fichier PRÉSENT mais illisible (permissions, ou tronqué en
 * cours de déploiement). `is_file()` passe, `file_get_contents()` rend `false`,
 * `(string) false` vaut `''` — et le JsonException qui suit dit « Syntax error »
 * SANS NOMMER LE CHEMIN. L'en-tête ci-dessus revendique de les nommer toutes.
 */
if ($raw === false) {
    throw new RuntimeException("resources/fonts.json est présent mais illisible [{$path}] : vérifier les permissions.");
}

$manifest = json_decode($raw, true, 512, JSON_THROW_ON_ERROR);
$rawFaces = is_array($manifest) ? ($manifest['faces'] ?? null) : null;

if (! is_array($rawFaces) || $rawFaces === []) {
    throw new RuntimeException('resources/fonts.json ne décrit aucune face self-hostée sous [faces].');
}

$faces = [];

foreach (array_values($rawFaces) as $index => $face) {
    if (! is_array($face)) {
        throw new RuntimeException("resources/fonts.json : l'entrée faces[{$index}] n'est pas un objet.");
    }

    $target = $face['target'] ?? null;
    $family = $face['family'] ?? null;
    $weight = $face['weight'] ?? null;
    $preload = $face['preload'] ?? null;

    if (! is_string($target) || $target === '') {
        throw new RuntimeException("resources/fonts.json : faces[{$index}].target doit être une chaîne non vide.");
    }

    /*
     * Le `target` est un NOM DE FICHIER NU — même règle que vite.config.js, et
     * elle est répétée ici PARCE QUE les deux lecteurs ne tournent jamais au
     * même moment : le plugin au build, cette config au boot HTTP. Un `target`
     * porteur d'un chemin passerait le boot, s'échapperait dans l'`href` du
     * preload et dans l'`url()` du @font-face, et seul le build l'aurait vu.
     */
    if ($target !== basename($target) || str_starts_with($target, '.')) {
        throw new RuntimeException("resources/fonts.json : faces[{$index}].target [{$target}] n'est pas un nom de fichier nu.");
    }

    if (! is_string($family) || $family === '') {
        throw new RuntimeException("resources/fonts.json : faces[{$index}].family doit être une chaîne non vide.");
    }

    /*
     * ⚠️ LE JEU DE CARACTÈRES DE `family` EST CONTRAINT, ET CE N'EST PAS DU ZÈLE.
     * Relevé à la seconde passe de revue du 2026-08-09.
     *
     * Cette valeur est interpolée par `{{ }}` DANS un <style>, entre apostrophes.
     * Blade y applique `e()`, qui échappe pour le HTML — or le parseur CSS ne
     * décode pas les entités : une apostrophe dans `family` devient `&#039;`,
     * la déclaration est invalide, la règle tombe, et `font-display: swap` rend
     * la page en fonte système sans une erreur. Symétriquement, `e()` n'échappe
     * NI `{`, NI `}`, NI `;` : une valeur de `family` pourrait terminer la règle
     * et injecter du CSS arbitraire.
     *
     * Contraindre la valeur ici est la seule garde qui tienne aux deux bouts :
     * un nom de famille de police est fait de lettres, de chiffres, d'espaces et
     * de tirets. Tout le reste est soit une faute de frappe, soit une injection.
     */
    if (in_array(preg_match('/^[A-Za-z0-9][A-Za-z0-9 \-]*$/', $family), [0, false], true)) {
        throw new RuntimeException("resources/fonts.json : faces[{$index}].family [{$family}] contient autre chose que des lettres, chiffres, espaces et tirets — cette valeur est interpolée dans un <style>.");
    }

    if (! is_int($weight)) {
        throw new RuntimeException("resources/fonts.json : faces[{$index}].weight doit être un entier (pas une chaîne).");
    }

    if (! is_bool($preload)) {
        throw new RuntimeException("resources/fonts.json : faces[{$index}].preload doit être un booléen (la chaîne \"false\" est truthy).");
    }

    /*
     * Seuls les champs consommés au RENDU sont réexportés. `package` et `source`
     * sont des chemins de node_modules : ils n'ont aucun lecteur à l'exécution, et
     * les laisser passer les sérialiserait dans bootstrap/cache/config.php en
     * production. Relevé à la revue du 2026-08-09.
     */
    $faces[] = [
        'target' => $target,
        'family' => $family,
        'weight' => $weight,
        'preload' => $preload,
    ];
}

return [
    'faces' => $faces,
];
