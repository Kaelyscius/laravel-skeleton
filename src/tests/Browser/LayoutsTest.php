<?php

declare(strict_types=1);

use App\Core\Models\Streamer;
use Illuminate\Foundation\Testing\RefreshDatabase;

uses(RefreshDatabase::class);

/*
|--------------------------------------------------------------------------
| Story 1.13 — ce qui n'existe que dans un moteur de rendu
|--------------------------------------------------------------------------
|
| Quatre choses que `tests/Feature/LayoutsTest.php` ne peut PAS prouver, parce
| qu'aucune n'existe dans une chaîne de HTML :
|
|  - une HAUTEUR (`h-12 lg:h-14` prouve qu'on a tapé ces caractères) ;
|  - `position: sticky` APRÈS DÉFILEMENT (la propriété n'est pas la position) ;
|  - la visibilité d'un `sr-only` au focus (un pseudo-état) ;
|  - une fermeture différée par Alpine (rien ne s'exécute hors navigateur).
|
| ⚠️ Rappels ADR-0013, à ne pas redécouvrir :
|  - `make npm-build` AVANT `make test-browser` dès que app.js ou la CSS bouge.
|    `run-browser-tests.sh` ne construit RIEN : Chromium exécuterait l'ancien
|    bundle, et le comportement du toast paraîtrait absent — ou pire, paraîtrait
|    marcher alors que le nouveau code n'a jamais été chargé.
|  - Le verdict ne vient PAS du code de sortie de `pest` (le plugin ne rend pas
|    la main ~1 run sur 2). « ⚠️ Le runner n'a pas rendu la main » n'est pas un
|    échec : `make test-browser` lit le rapport JUnit.
|  - `tests/Browser` n'est pas une testsuite phpunit.xml : `php artisan test` ne
|    l'exécute pas, délibérément.
|
| ⚠️ Pas de temporisation fixe (leçon de la Story 1.11, 8 `wait(0.6)` retirés en
| revue) : cette suite tourne sur DEUX Chromium différents. On lit jusqu'à
| stabilisation, ou jusqu'à une condition, avec une BORNE.
*/

/**
 * Le <body>, écrit sous une forme que le plugin reconnaît comme du CSS.
 *
 * ⚠️ Piège coûteux, trouvé en écrivant ce fichier : `keys('body', 'Tab')` échoue
 * sur un « Timeout 5000ms exceeded » qui ne nomme rien. `GuessLocator` ne traite
 * une chaîne comme un sélecteur CSS que si elle COMMENCE par `#`, `.`, `[` ou
 * `internal:`, ou si elle CONTIENT un caractère spécial CSS. `body` n'a rien de
 * tout cela : le plugin cherche donc `[id="body"]`, puis `[name="body"]`, puis
 * un élément dont le TEXTE vaut « body » — et attend cinq secondes qu'il
 * apparaisse. `html > body` contient `>`, donc il est reconnu.
 */
const DOCUMENT_BODY = 'html > body';

/**
 * Rend un `mixed` lisible DANS UN MESSAGE d'échec, sans prétendre le typer.
 *
 * `script()` renvoie `mixed`. L'interpoler tel quel est une erreur PHPStan au
 * niveau 10, et surtout : un message d'échec qui affiche « Array » ou rien du
 * tout ne dit pas ce qui s'est passé. On nomme donc le type quand ce n'est pas
 * une chaîne.
 */
$readable = static fn (mixed $value): string => is_string($value) ? $value : get_debug_type($value);

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
 * non-chaîne (script() n'a rien renvoyé d'exploitable), 'ABSENT' (le sélecteur
 * ne désigne aucun élément) et '' (propriété non résolue, qui passerait
 * tranquillement un `->not->toBe('none')`).
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
 * Lit une valeur calculée jusqu'à ce que deux lectures consécutives coïncident.
 *
 * Une temporisation fixe est un pari sur la vitesse de la machine ; un test
 * instable finit désarmé. C'est la raison, pas le confort.
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
 * Attend qu'une lecture renvoie la valeur attendue, avec une BORNE en millisecondes.
 *
 * Renvoie le temps écoulé : c'est lui qui distingue « fermé par le bouton » de
 * « fermé parce que la durée était courte ».
 */
$waitUntilValue = static function (callable $read, string $expected, int $boundMs, string $what): int {
    $waited = 0;
    $last = null;

    while ($waited <= $boundMs) {
        $last = $read();

        if ($last === $expected) {
            return $waited;
        }

        usleep(50_000);
        $waited += 50;
    }

    expect(false)
        ->toBeTrue("{$what} : la valeur attendue [{$expected}] n'est jamais arrivée en {$boundMs} ms (dernière : ["
            . (is_string($last) ? $last : gettype($last)) . ']).');

    return $waited;
};

/*
|--------------------------------------------------------------------------
| AC3 — skip-to-content
|--------------------------------------------------------------------------
*/

it('fait du lien de saut le PREMIER élément focusable du document (AC3)', function () use ($readable): void {
    /*
     * Un skip-link qui n'est pas le premier focusable ne sert à rien : il faut
     * traverser le chrome pour l'atteindre, c'est-à-dire faire exactement ce
     * qu'il existe pour éviter. On arrive donc par Tab depuis <body>, seule
     * façon honnête de vérifier une affordance clavier.
     *
     * Vu rouge : en déplaçant le lien après le <header> dans le gabarit.
     */
    Streamer::factory()->create();

    $page = visit('/_layouts');

    $page->keys(DOCUMENT_BODY, 'Tab');

    $isSkipLink = $page->script(
        "(() => { const a = document.activeElement; return String(a !== null && a.tagName === 'A' && a.getAttribute('href') === '#main'); })()",
    );

    expect($isSkipLink)
        ->toBe('true', 'La première tabulation n\'atteint pas <a href="#main"> : le lien de saut n\'est pas le premier focusable.');

    $label = $page->script("(() => String(document.activeElement.textContent).trim())()");

    expect($label)
        ->toBe('Aller au contenu', 'Le premier focusable ne porte pas le libellé attendu (lu : [' . $readable($label) . ']).');
});

it('garde le lien de saut invisible au repos et le rend visible au focus (AC3)', function () use (
    $computed,
    $asComputedValue,
    $settled
): void {
    /*
     * Deux valeurs CALCULÉES, et jamais la présence des classes `sr-only` /
     * `focus:not-sr-only` : `focus:` est un pseudo-état, une chaîne de classes
     * n'en prouve rien. Tailwind 4 rend `sr-only` par `clip-path: inset(50%)`
     * sur une boîte de 1×1 px ; `not-sr-only` remet `clip-path: none` et rend
     * les dimensions au contenu.
     *
     * ⚠️ `focus:absolute` et `focus:not-sr-only` se disputent la propriété
     * `position` (static contre absolute) : on OBSERVE laquelle gagne, plutôt
     * que de faire confiance à l'ordre de génération de Tailwind. Si un jour il
     * s'inverse, le skip-link décalerait la page entière à chaque focus.
     */
    Streamer::factory()->create();

    $page = visit('/_layouts');

    $clipAtRest = $settled(
        static fn (): mixed => $page->script($computed('a[href="#main"]', 'clip-path')),
        'lien de saut au repos',
    );

    expect($clipAtRest)
        ->not->toBe('none', 'Le lien de saut est visible au repos : il occuperait le haut de chaque page.');

    $widthAtRest = $asComputedValue($page->script($computed('a[href="#main"]', 'width')), 'largeur du lien de saut au repos');

    expect((float) $widthAtRest)
        ->toBeLessThan(2.0, "Le lien de saut mesure [{$widthAtRest}] au repos : il n'est pas retiré du flux visuel.");

    $page->keys(DOCUMENT_BODY, 'Tab');

    $clipFocused = $settled(
        static fn (): mixed => $page->script($computed('a[href="#main"]', 'clip-path')),
        'lien de saut au focus',
    );

    expect($clipFocused)
        ->toBe('none', "Le lien de saut reste rogné au focus (clip-path calculée : [{$clipFocused}]) : il est focalisé et invisible.");

    $widthFocused = $asComputedValue($page->script($computed('a[href="#main"]', 'width')), 'largeur du lien de saut au focus');

    expect((float) $widthFocused)
        ->toBeGreaterThan((float) $widthAtRest, "Le lien de saut n'a pas repris de place au focus ([{$widthAtRest}] → [{$widthFocused}]).");

    $position = $asComputedValue($page->script($computed('a[href="#main"]', 'position')), 'position du lien de saut au focus');

    expect($position)
        ->toBe('absolute', "Au focus, le lien de saut est en [{$position}] : il pousse le document au lieu de flotter au-dessus.");
});

it('fait pointer le lien de saut sur une cible réellement présente dans le DOM (AC3)', function (): void {
    Streamer::factory()->create();

    $page = visit('/_layouts');

    $targetIsMain = $page->script(
        "(() => { const t = document.querySelector('#main'); return String(t !== null && t.tagName === 'MAIN'); })()",
    );

    expect($targetIsMain)
        ->toBe('true', 'La cible #main n\'existe pas, ou n\'est pas le <main> : le lien de saut ne saute nulle part.');
});

it('déplace le FOCUS sur le <main> quand le lien de saut est ACTIVÉ (AC3)', function () use ($readable): void {
    /*
     * Ajouté par la revue de code du 2026-08-08. Les trois tests d'AC3 ci-dessus
     * vérifient que le lien est premier focusable, qu'il devient visible, et que
     * sa cible existe. AUCUN ne vérifie ce qu'il fait quand on l'active — et
     * c'est là que l'affordance se joue.
     *
     * Sans `tabindex="-1"` sur la cible, plusieurs moteurs (Safari/VoiceOver en
     * tête) déplacent le DÉFILEMENT sans déplacer le FOCUS : la tabulation
     * suivante repart du header, c'est-à-dire de ce que le lien existe pour
     * éviter. Un lien de saut qui a l'air de marcher et ne marche pas est pire
     * qu'aucun lien de saut : l'utilisateur le prend et se retrouve nulle part.
     *
     * Vu rouge : en retirant `tabindex="-1"` du <main>.
     */
    Streamer::factory()->create();

    $page = visit('/_layouts');

    // Le chemin réel de l'utilisateur : on arrive au lien par Tab, on l'active.
    $page->keys(DOCUMENT_BODY, 'Tab');
    $page->keys('a[href="#main"]', 'Enter');

    $focused = $page->script(
        "(() => { const a = document.activeElement; return String(a === null ? 'AUCUN' : a.tagName + '#' + a.id); })()",
    );

    expect($focused)
        ->toBe('MAIN#main', 'Après activation du lien de saut, le focus est sur ['
            . $readable($focused) . '] : le saut déplace le défilement sans déplacer le focus.');
});

/*
|--------------------------------------------------------------------------
| AC4 — header sticky, hauteur observée
|--------------------------------------------------------------------------
*/

it('mesure 48 px en mobile et 56 px en desktop, et bascule bien à lg: (AC4)', function () use (
    $computed,
    $settled
): void {
    /*
     * Les deux largeurs du MILIEU ne sont pas décoratives : ce sont elles qui
     * distinguent `lg:` de `md:`. Avec un `md:h-14`, la mesure à 1023 px
     * renverrait 56 px et le garde-fou serait resté vert. La tablette est
     * délibérément traitée comme « mobile XL » (UX spec §Layout grid responsive).
     *
     * Vu rouge : en remplaçant `lg:h-14` par `md:h-14`.
     */
    Streamer::factory()->create();

    $page = visit('/_layouts');

    $expectations = [
        [375, 812, '48px', 'mobile'],
        [1023, 800, '48px', 'juste sous le breakpoint lg'],
        [1024, 800, '56px', 'exactement au breakpoint lg'],
        [1280, 800, '56px', 'desktop'],
    ];

    foreach ($expectations as [$width, $height, $expected, $label]) {
        $page->resize($width, $height);

        $measured = $settled(
            static fn (): mixed => $page->script($computed('header[data-role="site-header"]', 'height')),
            "hauteur du header à {$width} px",
        );

        expect($measured)
            ->toBe($expected, "Header à {$width} px ({$label}) : hauteur calculée [{$measured}], attendue [{$expected}].");
    }
});

it('garde le header à l\'écran après un défilement, pas seulement en propriété CSS (AC4)', function () use (
    $computed,
    $asComputedValue,
    $readable
): void {
    /*
     * `position: sticky` calculée ne prouve RIEN à elle seule : un ancêtre en
     * `overflow: hidden`, un conteneur trop court, et l'élément défile comme
     * n'importe quel autre — la propriété reste pourtant « sticky ». On mesure
     * donc la position À L'ÉCRAN APRÈS défilement.
     *
     * Vu rouge : en retirant `sticky top-0` du header.
     */
    Streamer::factory()->create();

    $page = visit('/_layouts');
    $page->resize(1280, 800);

    $position = $asComputedValue($page->script($computed('header[data-role="site-header"]', 'position')), 'position du header');

    expect($position)
        ->toBe('sticky', "Le header est en [{$position}] : le seul élément sticky du site ne l'est pas.");

    $scrolled = $page->script('(() => { window.scrollTo(0, 1500); return String(Math.round(window.scrollY)); })()');

    // Anti-vacuité : sur une page trop courte pour défiler, le header serait
    // resté en haut sans que « sticky » y soit pour quoi que ce soit.
    expect((float) (is_string($scrolled) ? $scrolled : '0'))
        ->toBeGreaterThan(500.0, 'La page n\'a défilé que de [' . $readable($scrolled) . '] px : sticky n\'a pas été mis à l\'épreuve.');

    $top = $page->script(
        "(() => String(Math.round(document.querySelector('header[data-role=\"site-header\"]').getBoundingClientRect().top)))()",
    );

    expect($top)
        ->toBe('0', 'Après défilement, le header est à [' . $readable($top) . '] px du haut de la fenêtre : il a défilé avec la page.');
});

/*
|--------------------------------------------------------------------------
| AC5 — prefers-reduced-motion: reduce
|--------------------------------------------------------------------------
*/

it('réduit la durée de transition sous prefers-reduced-motion, et la restitue sans (AC5)', function () use (
    $computed,
    $asComputedValue
): void {
    /*
     * LES DEUX MESURES SONT DANS LE MÊME TEST, et c'est l'AC qui l'exige : une
     * durée quasi nulle sous `reduce` ne prouve rien si on ne montre pas que la
     * même mesure vaut 200 ms sans la préférence. Une transition simplement
     * absente donnerait « 0s » dans les deux cas.
     *
     * `visit(..., ['reducedMotion' => 'reduce'])` a été sondé avant d'écrire cet
     * AC (T0) : le plugin étale les options dans `newContext()`, où Playwright
     * accepte `reducedMotion`. La sonde a vérifié les DEUX sens —
     * `matchMedia('(prefers-reduced-motion: reduce)').matches` vaut `true` avec
     * l'option, `false` sans.
     *
     * Vu rouge : en retirant l'import de motion.css dans app.css.
     */
    Streamer::factory()->create();

    $reduced = visit('/_layouts', [
        'reducedMotion' => 'reduce',
    ]);

    $mediaMatches = $reduced->script("(() => String(window.matchMedia('(prefers-reduced-motion: reduce)').matches))()");

    expect($mediaMatches)
        ->toBe('true', 'Le contexte navigateur n\'a pas activé la préférence : la mesure suivante ne prouverait rien.');

    $reducedDuration = $asComputedValue(
        $reduced->script($computed('#motion-probe', 'transition-duration')),
        'durée de transition sous reduce',
    );

    expect((float) $reducedDuration)
        ->toBeLessThan(0.01, "Sous prefers-reduced-motion, la durée calculée vaut [{$reducedDuration}] : le mouvement n'est pas réduit.");

    $nominal = visit('/_layouts');

    $nominalDuration = $asComputedValue(
        $nominal->script($computed('#motion-probe', 'transition-duration')),
        'durée de transition nominale',
    );

    expect($nominalDuration)
        ->toBe('0.2s', "Sans la préférence, la durée calculée vaut [{$nominalDuration}] au lieu des 200 ms du token --duration-default.");
});

it('fait descendre la durée de transition du token --duration-default (AC5)', function () use (
    $computed,
    $asComputedValue
): void {
    /*
     * Le test précédent prouve qu'une durée de 200 ms existe. Celui-ci prouve
     * d'OÙ ELLE VIENT : un `duration-200` écrit à la main passerait le test
     * précédent sans broncher. Muter le token à chaud les sépare — c'est la
     * technique de la Story 1.11 (`--accent-lava`), transposée au temps.
     */
    Streamer::factory()->create();

    $page = visit('/_layouts');

    $before = $asComputedValue($page->script($computed('#motion-probe', 'transition-duration')), 'durée avant mutation');

    $page->script("(() => { document.documentElement.style.setProperty('--duration-default', '700ms'); return true; })()");

    $after = $asComputedValue($page->script($computed('#motion-probe', 'transition-duration')), 'durée après mutation');

    expect($after)
        ->not->toBe($before, "La durée n'a pas bougé alors que --duration-default a changé : elle est écrite en dur, elle ne descend pas du token.");
});

/*
|--------------------------------------------------------------------------
| AC6 — comportement de <x-toast> (dette héritée de la Story 1.11)
|--------------------------------------------------------------------------
*/

it('ferme seul un toast à durée courte, et laisse le toast long ouvert au même instant (AC6)', function () use (
    $computed,
    $waitUntilValue
): void {
    /*
     * ⚠️ La seconde moitié est ce qui rend l'assertion NON-VIDE. « Le toast a
     * disparu » serait vrai d'un toast masqué dès le chargement, d'un Alpine qui
     * plante, d'un sélecteur qui ne trouve rien. On vérifie donc, AU MÊME
     * INSTANT, qu'un toast à durée longue est ENCORE LÀ.
     *
     * Vu rouge : en remplaçant la durée lue dans le DOM par une constante dans
     * app.js — le toast long se fermait alors en même temps que le court.
     */
    Streamer::factory()->create();

    $page = visit('/_layouts');

    $readShort = static fn (): mixed => $page->script($computed('#toast-short', 'display'));

    // Le toast court dure 900 ms. La borne est large pour absorber le démarrage
    // d'Alpine sur une machine lente, mais elle reste TRÈS inférieure aux
    // 60 000 ms du toast long : la distinction ne peut pas venir de l'attente.
    $waitUntilValue($readShort, 'none', 8_000, 'auto-fermeture du toast à durée courte');

    $longDisplay = $page->script($computed('#toast-long', 'display'));

    expect($longDisplay)
        ->not->toBe('none', 'Le toast à durée longue s\'est fermé en même temps que le court : la durée du DOM n\'est pas lue.');

    expect($longDisplay)
        ->not->toBe('ABSENT', 'Le toast à durée longue n\'existe pas dans la page : l\'assertion serait vide.');
});

it('ferme un toast immédiatement au bouton, sans attendre sa durée (AC6)', function () use (
    $computed,
    $waitUntilValue
): void {
    /*
     * Le toast visé dure 60 000 ms. S'il se ferme en moins de 5 secondes, c'est
     * le bouton qui l'a fermé — aucune autre explication ne tient.
     *
     * Vu rouge : en retirant l'addEventListener('click') de app.js.
     */
    Streamer::factory()->create();

    $page = visit('/_layouts');

    $readDismissable = static fn (): mixed => $page->script($computed('#toast-dismiss', 'display'));

    // Anti-vacuité : il doit être OUVERT avant qu'on le ferme.
    expect($readDismissable())
        ->not->toBe('none', 'Le toast fermable est déjà fermé avant le clic : le clic ne prouverait rien.');

    $page->click('#toast-dismiss [data-toast-dismiss]');

    $elapsed = $waitUntilValue($readDismissable, 'none', 5_000, 'fermeture au bouton');

    expect($elapsed)
        ->toBeLessThan(5_000, "Le toast ne s'est pas fermé au clic en moins de 5 s alors que sa durée est de 60 s.");
});

it('laisse un toast à durée invalide ouvert, ET fermable à la main (AC6 — chemin d\'erreur)', function () use (
    $computed,
    $waitUntilValue
): void {
    /*
     * Ajouté par la revue de code du 2026-08-08 — DEUX garde-fous en un.
     *
     * 1. La branche fail-loud d'`app.js` (durée invalide → aucune minuterie)
     *    n'était exercée par RIEN. Elle est inatteignable depuis `<x-toast>`,
     *    dont la garde PHP refuse une durée non numérique : c'est précisément
     *    pourquoi elle n'avait jamais été vue rouge. `#toast-broken` est donc
     *    écrit en HTML brut dans la page de démonstration.
     *
     *    ⚠️ Ne pas « simplifier » en retirant la garde JS au motif que le PHP
     *    valide déjà : `setTimeout(fn, NaN)` se déclenche IMMÉDIATEMENT. Le
     *    toast disparaîtrait en silence — la mutation à ne surtout pas laisser
     *    passer, et ce test est ce qui l'attrape.
     *
     * 2. La durée invalide ne doit PAS emporter le bouton de fermeture. La
     *    première rédaction sortait par `return` avant de le câbler : un toast
     *    à durée cassée devenait totalement infermable.
     *
     * L'HORLOGE N'EST PAS UNE TEMPORISATION FIXE : on attend la fermeture de
     * `#toast-short` (900 ms), un évènement observable, et on lit `#toast-broken`
     * à cet instant-là. S'il avait programmé quoi que ce soit, il serait parti
     * avec — ou avant, si la durée avait été lue comme NaN.
     *
     * Vu rouge : en remettant la lecture de la durée avant le câblage du bouton
     * (le clic ne ferme plus rien), puis en retirant la garde `Number.isFinite`
     * (le toast se ferme instantanément, avant même l'ancre).
     */
    Streamer::factory()->create();

    $page = visit('/_layouts');

    $readBroken = static fn (): mixed => $page->script($computed('#toast-broken', 'display'));

    // Anti-vacuité : il doit exister et être ouvert AVANT que l'ancre ne tombe.
    expect($readBroken())
        ->not->toBe('ABSENT', 'Le toast à durée invalide n\'existe pas dans la page : le chemin d\'erreur n\'est exercé par rien.');

    $waitUntilValue(
        static fn (): mixed => $page->script($computed('#toast-short', 'display')),
        'none',
        8_000,
        'auto-fermeture du toast court (ancre du chemin d\'erreur)',
    );

    expect($readBroken())
        ->not->toBe('none', 'Le toast à durée invalide s\'est fermé seul : une minuterie a été programmée sur une durée que rien ne définit.');

    $page->click('#toast-broken [data-toast-dismiss]');

    $elapsed = $waitUntilValue($readBroken, 'none', 5_000, 'fermeture au bouton d\'un toast à durée invalide');

    expect($elapsed)
        ->toBeLessThan(5_000, 'Le bouton ne ferme pas un toast dont la durée est invalide : la garde sur la durée a emporté le câblage du bouton.');
});

/*
|--------------------------------------------------------------------------
| AC2 — l'absence, observée dans un vrai document
|--------------------------------------------------------------------------
*/

it('ne rend NI header NI footer dans un document servi par le layout minimal (AC2)', function () use ($readable): void {
    /*
     * L'absence est déjà vérifiée sur le HTML rendu (Feature). Ici on la vérifie
     * sur le DOM CONSTRUIT : un `<header>` produit par un script, ou injecté par
     * un middleware, n'apparaîtrait dans aucune des deux autres vérifications.
     */
    Streamer::factory()->create();

    $page = visit('/_layouts-minimal');

    $counts = $page->script(
        "(() => JSON.stringify({ header: document.querySelectorAll('header').length, footer: document.querySelectorAll('footer').length, title: document.querySelectorAll('#page-title').length }))()",
    );

    expect($counts)
        ->toBe('{"header":0,"footer":0,"title":1}', 'Le document minimal n\'est pas celui attendu (lu : ' . $readable($counts) . ').');
});
