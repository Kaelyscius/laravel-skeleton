<?php

declare(strict_types=1);

namespace Tests\Fixtures;

/**
 * La table de cas UNIQUE de l'AC7 — Story 1.12.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * POURQUOI CE FICHIER EXISTE
 *
 * Le rafraîchissement client impose une SECONDE implémentation du formatage
 * français : Carbon côté serveur, `Intl.RelativeTimeFormat` côté navigateur.
 * Deux implémentations d'une même règle finissent toujours par diverger, et
 * celle-ci divergerait en silence — à l'écran, chez l'utilisateur, sans erreur.
 *
 * Le défaut se nomme en une phrase : *le serveur affiche « il y a 1 jour »,
 * soixante secondes plus tard le client affiche « hier »*. C'est exactement ce
 * que produit `numeric: 'auto'`, le défaut d'Intl.
 *
 * Cette table est donc consommée par DEUX tests, et c'est le point :
 *
 *   - tests/Feature/TimeAsTextureTest.php  → assère que CARBON produit chaque libellé ;
 *   - tests/Browser/TimeAsTextureTest.php  → assère que le JS produit le MÊME.
 *
 * Une dérive d'un seul côté rougit. C'est la seule propriété qui rend cette
 * table utile — une table que les deux côtés liraient pour se calculer
 * l'un l'autre ne prouverait rien.
 *
 * ⚠️ LES LIBELLÉS SONT ÉCRITS EN DUR, PAS CALCULÉS. Les dériver de Carbon
 * ferait du test Feature une tautologie (« Carbon rend ce que Carbon rend ») et
 * laisserait le test navigateur se valider contre une valeur que Carbon aurait
 * pu changer sous lui. Ils ont été relevés le 2026-08-08 sur Carbon 3.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * CE QUE LES CAS COUVRENT
 *
 * Les 4 unités que le client a le droit de calculer — secondes, minutes,
 * heures, jours — et LES DEUX CÔTÉS de chaque transition, qui sont précisément
 * ce que le rafraîchissement existe pour rendre :
 *
 *      59 s / 60 s   ·   3599 s / 3600 s   ·   86399 s / 86400 s
 *
 * L'AC écrivait « 59 s → 1 minute ». C'est faux au pied de la lettre, et la
 * mesure l'a montré : Carbon TRONQUE, donc 59 s rend « il y a 59 secondes ».
 * Tester les deux côtés est strictement plus fort que la formulation d'origine.
 *
 * ⚠️ `90 => il y a 1 minute` distingue `Math.floor` de `Math.round` — mais
 * PAS « lui seul », contrairement à ce que disait la rédaction d'origine :
 * `3599` le distingue aussi (`round(3599/60)` vaut 60, donc « il y a 60
 * minutes »), et c'est en réalité LUI qui a fait rougir la mutation MB-C.
 * Corrigé à la revue du 2026-08-08, qui a montré au passage que le cas 90 s
 * était le seul à ne rien pouvoir garantir tout seul : il partage son libellé
 * avec le cas 60 s qui le précède, donc le test navigateur pouvait le
 * satisfaire sur une lecture PÉRIMÉE. C'est pour cela que ce test attend
 * désormais un DÉCLENCHEMENT du compteur avant de comparer.
 *
 * ⚠️ LES DEUX SENS. Le composant accepte un instant FUTUR — un stream annoncé
 * en est le cas d'usage évident — et le JS gère explicitement le signe
 * (`elapsedSeconds < 0 ? value : -value`). Sans cas négatif, toute cette
 * branche n'était observée par rien : l'inverser rendait « il y a 3 heures »
 * pour dans 3 heures, sans qu'aucun test ne bouge. Ajouté à la revue du
 * 2026-08-08.
 *
 * Aucun cas au-delà de 604 800 s (7 jours) en valeur absolue : au-delà, le
 * client ne calcule rien du tout et le libellé du serveur fait foi (voir
 * resources/js/app.js). `604740` (6 j 23 h 59 min) est le dernier cas côté
 * passé — une marge d'une minute sous le plafond, qui rend le cas lisible
 * plutôt que collé à la borne.
 */
final class RelativeTimeCases
{
    /**
     * Forme LONGUE — le défaut de <x-time-relative>.
     *
     * @return array<int, string> secondes écoulées => libellé français attendu
     */
    public static function long(): array
    {
        return [
            1 => 'il y a 1 seconde',
            5 => 'il y a 5 secondes',
            59 => 'il y a 59 secondes',
            60 => 'il y a 1 minute',
            90 => 'il y a 1 minute',
            3599 => 'il y a 59 minutes',
            3600 => 'il y a 1 heure',
            10800 => 'il y a 3 heures',
            50400 => 'il y a 14 heures',
            86399 => 'il y a 23 heures',
            86400 => 'il y a 1 jour',
            172800 => 'il y a 2 jours',
            518400 => 'il y a 6 jours',
            604740 => 'il y a 6 jours',
            // Instants FUTURS — clés négatives, les 4 unités. Carbon rend
            // « dans … », Intl aussi ; c'est la branche de signe du JS, que rien
            // n'observait avant la revue du 2026-08-08.
            -1 => 'dans 1 seconde',
            -60 => 'dans 1 minute',
            -3600 => 'dans 1 heure',
            -86400 => 'dans 1 jour',
        ];
    }

    /**
     * Forme COURTE — celle qu'emploient les écrans de référence.
     *
     * Elle n'est pas un supplément d'âme : `02-home-offline.html` rend
     * « Dernier stream il y a 14 h » et « il y a 2 jours ». Le rafraîchissement
     * client la recalcule donc AUSSI, et une table qui ne couvrirait que la
     * forme longue laisserait la moitié réellement employée dériver librement.
     *
     * @return array<int, string> secondes écoulées => libellé français attendu
     */
    public static function short(): array
    {
        return [
            1 => 'il y a 1 s',
            5 => 'il y a 5 s',
            59 => 'il y a 59 s',
            60 => 'il y a 1 min',
            90 => 'il y a 1 min',
            3599 => 'il y a 59 min',
            3600 => 'il y a 1 h',
            10800 => 'il y a 3 h',
            50400 => 'il y a 14 h',
            86399 => 'il y a 23 h',
            86400 => 'il y a 1 j',
            172800 => 'il y a 2 j',
            518400 => 'il y a 6 j',
            604740 => 'il y a 6 j',
            -1 => 'dans 1 s',
            -60 => 'dans 1 min',
            -3600 => 'dans 1 h',
            -86400 => 'dans 1 j',
        ];
    }
}
