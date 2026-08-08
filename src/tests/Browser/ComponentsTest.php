<?php

declare(strict_types=1);

use App\Core\Models\Streamer;
use Illuminate\Foundation\Testing\RefreshDatabase;

uses(RefreshDatabase::class);

/*
|--------------------------------------------------------------------------
| Story 1.11 — les états qui n'existent que dans un moteur de rendu
|--------------------------------------------------------------------------
|
| `hover`, `active` et `focus-visible` sont des PSEUDO-ÉTATS : ils n'existent
| pas dans une chaîne de HTML. Asserter la présence de `hover:bg-lava/80`
| prouverait seulement que quelqu'un a tapé ces caractères — c'est la correction
| n°4 de la requalification des AC (« observés dans un navigateur via une valeur
| calculée, pas la seule présence d'une classe »).
|
| DEUX NIVEAUX DE PREUVE ICI, et le second est le plus important :
|
|  1. La valeur calculée CHANGE quand l'état change. Prouve que la règle CSS
|     s'applique bien à cet élément.
|  2. La valeur calculée CHANGE quand on mute `--accent-lava` à chaud. Prouve
|     que la couleur DESCEND DU TOKEN. Une couleur en dur produirait exactement
|     la même valeur avant et après la mutation — et le test rougirait. C'est
|     la seule assertion qui distingue « c'est orange » de « c'est lava ».
|
| Les tests sont volontairement DÉCOUPÉS FIN. Une seule grosse assertion en
| chaîne s'arrête au premier échec : casser un garde-fou pour le voir rougir
| masquerait alors tous les suivants, et la campagne de mutation coûterait un
| run de navigateur par garde-fou.
|
| ⚠️ Rappels ADR-0013, à ne pas redécouvrir :
|  - Le verdict ne vient PAS du code de sortie de `pest` (le plugin ne rend pas
|    la main ~1 run sur 2). « ⚠️ Le runner n'a pas rendu la main » n'est pas un
|    échec : `make test-browser` lit le rapport JUnit.
|  - `tests/Browser` n'est pas une testsuite phpunit.xml : `php artisan test` ne
|    l'exécute pas, délibérément.
*/

/**
 * Expression JS renvoyant une propriété calculée, sous forme de chaîne.
 */
$computed = static fn (string $selector, string $property): string => sprintf(
    "(() => { const el = document.querySelector('%s'); return el === null ? 'ABSENT' : String(getComputedStyle(el).getPropertyValue('%s')); })()",
    $selector,
    $property,
);

/**
 * Resserre le `mixed` de script() en chaîne, ICI plutôt qu'à chaque usage.
 *
 * Trois refus explicites, parce que chacun rendrait une assertion vide de sens :
 *  - non-chaîne : script() n'a rien renvoyé d'exploitable ;
 *  - 'ABSENT'   : le sélecteur ne désigne aucun élément (le test se croirait
 *                 vert sur un élément renommé) ;
 *  - ''         : une propriété non résolue, qui passerait tranquillement un
 *                 `->not->toBe('none')` — trouvé en revue de code.
 */
$asComputedValue = static function (mixed $value, string $what): string {
    expect(is_string($value))
        ->toBeTrue("Aucune valeur calculée pour {$what} : script() n'a pas renvoyé de chaîne.");

    $string = is_string($value) ? $value : '';

    expect($string)
        ->not->toBe('ABSENT', "L'élément visé par [{$what}] n'existe pas dans la page.");

    expect($string)
        ->not->toBe('', "Valeur calculée vide pour {$what} : la propriété n'a pas été résolue.");

    return $string;
};

/**
 * Lit une valeur calculée jusqu'à ce qu'elle se stabilise.
 *
 * ⚠️ Remplace les `wait(0.6)` en dur de la première version. Les transitions
 * durent 200 ms (--duration-default) et getComputedStyle rendu PENDANT une
 * transition renvoie la valeur intermédiaire : il faut attendre. Mais une
 * temporisation fixe est un pari sur la vitesse de la machine, dans une suite
 * qui tourne sur DEUX Chromium différents (Alpine/musl en local, Chrome for
 * Testing en CI). On lit donc jusqu'à ce que deux lectures consécutives
 * coïncident — plus rapide au repos, et déterministe sous charge.
 *
 * Un test instable finit désarmé : c'est la raison, pas le confort.
 */
$settled = static function (callable $read, string $what) use ($asComputedValue): string {
    $previous = null;

    for ($attempt = 0; $attempt < 15; $attempt++) {
        $current = $asComputedValue($read(), $what);

        if ($current === $previous) {
            return $current;
        }

        $previous = $current;
        usleep(80_000);
    }

    expect(false)
        ->toBeTrue("La valeur calculée de {$what} ne s'est jamais stabilisée (dernière : [{$previous}]).");

    return (string) $previous;
};

/**
 * Remplace `--accent-lava` par une couleur incontestablement différente.
 *
 * Le token est déclaré sur `:root` dans tokens.css ; une déclaration inline sur
 * <html> le surcharge. Tout ce qui descend du token bouge ; tout ce qui est
 * écrit en dur ne bouge pas. C'est la mutation, appliquée au CSS.
 */
$mutateLavaToken = "(() => { document.documentElement.style.setProperty('--accent-lava', 'rgb(0, 128, 255)'); return true; })()";

it('distingue repos, survol et enfoncement de <x-button> par valeur calculée (AC1)', function () use (
    $computed,
    $asComputedValue,
    $settled
): void {
    Streamer::factory()->create();

    $page = visit('/_components');

    $readBackground = static fn (): mixed => $page->script($computed('#btn-primary', 'background-color'));

    $atRest = $settled($readBackground, 'bouton primaire au repos');

    $page->hover('#btn-primary');
    $hovered = $settled($readBackground, 'bouton primaire survolé');

    expect($hovered)
        ->not->toBe($atRest, "Le survol ne change pas la couleur calculée du bouton primaire (toujours [{$atRest}]) : la règle hover: ne s'applique pas.");

    /*
     * :active ne se simule pas en JS — ni un dispatchEvent, ni une classe. On
     * focalise le bouton et on MAINTIENT la barre d'espace : Chromium considère
     * alors le bouton comme activé, exactement comme un vrai appui.
     */
    $page->script("(() => { document.querySelector('#btn-primary').focus(); return true; })()");

    $pressed = null;

    $page->withKeyDown(' ', function () use ($page, $computed, &$pressed): void {
        $page->wait(0.5);
        $pressed = $page->script($computed('#btn-primary', 'background-color'));
    });

    $activeBackground = $asComputedValue($pressed, 'bouton primaire enfoncé');

    expect($activeBackground)
        ->not->toBe($hovered, "L'état actif ne se distingue pas du survol (toujours [{$hovered}]).");

    expect($activeBackground)
        ->not->toBe($atRest, 'L\'état actif ne se distingue pas du repos.');
});

it('fait descendre la couleur du bouton primaire du token --accent-lava (AC1)', function () use (
    $computed,
    $settled,
    $mutateLavaToken
): void {
    Streamer::factory()->create();

    $page = visit('/_components');

    $readBackground = static fn (): mixed => $page->script($computed('#btn-primary', 'background-color'));

    $before = $settled($readBackground, 'bouton primaire avant mutation du token');

    $page->script($mutateLavaToken);

    $after = $settled($readBackground, 'bouton primaire après mutation du token');

    expect($after)
        ->not->toBe($before, "La couleur du bouton primaire n'a pas bougé alors que --accent-lava a changé : elle est écrite en dur, elle ne descend pas du token.");
});

it('rend disabled et loading comme des états réels, observables dans le navigateur (AC1)', function () use (
    $computed,
    $asComputedValue,
    $settled
): void {
    Streamer::factory()->create();

    $page = visit('/_components');

    $disabledOpacity = $settled(
        static fn (): mixed => $page->script($computed('#btn-disabled', 'opacity')),
        'bouton désactivé',
    );

    expect((float) $disabledOpacity)
        ->toBeLessThan(1.0, "Le bouton désactivé est rendu à pleine opacité [{$disabledOpacity}].");

    $reallyDisabled = $page->script("(() => String(document.querySelector('#btn-disabled').disabled))()");

    expect($reallyDisabled)
        ->toBe('true', 'Le bouton désactivé est encore cliquable : l\'état n\'est que du style.');

    $busy = $page->script("(() => String(document.querySelector('#btn-loading').getAttribute('aria-busy')))()");

    expect($busy)
        ->toBe('true', 'Le bouton en chargement n\'annonce pas aria-busy aux technologies d\'assistance.');

    $spinnerAnimation = $asComputedValue(
        $page->script($computed('#btn-loading [data-role="spinner"]', 'animation-name')),
        'indicateur de chargement',
    );

    expect($spinnerAnimation)
        ->not->toBe('none', 'L\'indicateur de chargement ne tourne pas : la classe est là, l\'animation non.');
});

it('observe les 3 états de <x-card> par valeur calculée (AC2)', function () use ($computed, $settled): void {
    /*
     * `border-top-color` et non `border-color` : le raccourci se sérialise
     * différemment selon le moteur quand les 4 côtés coïncident, et cette suite
     * tourne sur deux builds de Chromium distincts. On lit l'axe qui ne peut pas
     * diverger pour une raison étrangère à la carte.
     */
    Streamer::factory()->create();

    $page = visit('/_components');

    $atRest = $settled(
        static fn (): mixed => $page->script($computed('#card-default', 'border-top-color')),
        'carte au repos',
    );

    $selected = $settled(
        static fn (): mixed => $page->script($computed('#card-selected', 'border-top-color')),
        'carte sélectionnée',
    );

    $page->hover('#card-default');

    $hovered = $settled(
        static fn (): mixed => $page->script($computed('#card-default', 'border-top-color')),
        'carte survolée',
    );

    expect(array_unique([$atRest, $hovered, $selected]))
        ->toHaveCount(3, "Les 3 états de la carte ne produisent pas 3 bordures distinctes : [{$atRest}] / [{$hovered}] / [{$selected}].");
});

it('affiche au clavier un anneau de focus réellement décalé de 2px (AC6)', function () use (
    $computed,
    $asComputedValue,
    $settled
): void {
    /*
     * `:focus-visible` ne se déclenche PAS sur un focus programmatique appliqué
     * à un bouton — c'est tout l'intérêt du pseudo-état. On arrive donc par la
     * touche Tab depuis #focus-start, ce qui est aussi la seule façon honnête de
     * vérifier une affordance clavier.
     *
     * ⚠️ #focus-lab doit rester la dernière section de la page de démo et ses
     * éléments contigus : un focusable inséré entre eux casserait cet ordre.
     *
     * ⚠️ Le « décalage » se vérifie sur la BOX-SHADOW, pas sur outline-offset.
     * Première version de ce test : elle assertait `outline-offset === '2px'`
     * alors que `outline-none` posait `outline-style: none` — la propriété était
     * bien calculée à 2px et ne décalait rien du tout. Le composant utilise
     * désormais `ring-offset-2 ring-offset-bg`, ce qui produit DEUX couches de
     * box-shadow : 2px de la couleur du fond, puis l'anneau jusqu'à 4px. C'est
     * ce 4px qui prouve qu'un décalage existe.
     */
    Streamer::factory()->create();

    $page = visit('/_components');

    foreach ([
        '#fl-button' => '#focus-start',
        '#fl-icon' => '#fl-button',
    ] as $target => $previous) {
        $page->keys($previous, 'Tab');

        $focused = $page->script(
            sprintf("(() => String(document.activeElement === document.querySelector('%s')))()", $target),
        );

        expect($focused)
            ->toBe('true', "La tabulation depuis [{$previous}] n'a pas atteint [{$target}] : l'ordre de tabulation de #focus-lab a changé.");

        $isFocusVisible = $page->script(
            sprintf("(() => String(document.querySelector('%s').matches(':focus-visible')))()", $target),
        );

        expect($isFocusVisible)
            ->toBe('true', "[{$target}] ne correspond pas à :focus-visible après une navigation au clavier.");

        $ring = $settled(
            static fn (): mixed => $page->script($computed($target, 'box-shadow')),
            "anneau de focus de {$target}",
        );

        expect($ring)
            ->not->toBe('none', "[{$target}] n'affiche aucun anneau au focus clavier.");

        expect(str_contains($ring, '4px'))
            ->toBeTrue("L'anneau de [{$target}] ne s'étend pas jusqu'à 4px : il n'y a pas de décalage de 2px avant l'anneau de 2px. box-shadow calculée = [{$ring}].");

        $offset = $asComputedValue($page->script($computed($target, 'outline-offset')), "outline-offset de {$target}");

        expect($offset)
            ->toBe('2px', "[{$target}] n'applique pas outline-offset: 2px, qui gouverne l'outline conservé en contrastes forcés (calculé : [{$offset}]).");
    }
});

it('dérive l\'anneau de focus de --accent-lava, et non d\'un orange en dur (AC6)', function () use (
    $computed,
    $settled,
    $mutateLavaToken
): void {
    /*
     * Le test précédent prouve qu'un anneau existe et qu'il est décalé. Celui-ci
     * prouve d'OÙ IL VIENT : un `ring-[#FF5722]/40` écrit en dur passerait tout
     * le test précédent sans broncher. Muter le token à chaud les sépare.
     */
    Streamer::factory()->create();

    $page = visit('/_components');

    foreach ([
        '#fl-button' => '#focus-start',
        '#fl-icon' => '#fl-button',
    ] as $target => $previous) {
        $page->script("(() => { document.documentElement.style.removeProperty('--accent-lava'); return true; })()");
        $page->keys($previous, 'Tab');

        $readRing = static fn (): mixed => $page->script($computed($target, 'box-shadow'));

        $ring = $settled($readRing, "anneau de focus de {$target}");

        $page->script($mutateLavaToken);

        $mutatedRing = $settled($readRing, "anneau de focus muté de {$target}");

        expect($mutatedRing)
            ->not->toBe($ring, "L'anneau de [{$target}] n'a pas bougé alors que --accent-lava a changé : il n'est pas dérivé du token.");
    }
});

it('distingue les 4 types de <x-toast> par une couleur réellement peinte (AC7)', function () use ($computed, $settled): void {
    /*
     * La première version comparait des chaînes de classes. Or le `text-*` du
     * conteneur ne peignait RIEN — le corps du message a sa propre couleur, le
     * bouton de fermeture la sienne — donc « visuellement distincts » n'était
     * prouvé par personne. La pastille `bg-current` hérite du `text-*` du type :
     * c'est elle qu'on mesure.
     */
    Streamer::factory()->create();

    $page = visit('/_components');

    $colours = [];

    foreach (['success', 'info', 'warning', 'error'] as $type) {
        $colours[] = $settled(
            static fn (): mixed => $page->script($computed("#toast-{$type} [data-role=\"toast-indicator\"]", 'background-color')),
            "pastille du toast {$type}",
        );
    }

    expect(array_unique($colours))
        ->toHaveCount(4, 'Les 4 types de toast ne peignent pas 4 couleurs distinctes : ' . implode(' / ', $colours));
});
