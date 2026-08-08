<?php

declare(strict_types=1);

use App\Core\Models\Streamer;
use Illuminate\Contracts\Events\Dispatcher;
use Illuminate\Contracts\Http\Kernel;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Illuminate\Routing\Router;
use Illuminate\Support\Facades\Blade;
use Illuminate\Support\Facades\Route as RouteFacade;

uses(RefreshDatabase::class);

/**
 * Story 1.11 — composants Blade de base.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * CE QUE CE FICHIER NE FAIT PAS
 *
 * Il ne prétend PAS vérifier les pseudo-états. `hover`, `active` et
 * `focus-visible` n'existent pas dans une chaîne de HTML : asserter la présence
 * de `hover:bg-lava/80` prouverait seulement que quelqu'un a tapé ces
 * caractères. C'est la correction n°4 de la requalification des AC, et elle est
 * prise au sérieux — la vérification par VALEUR CALCULÉE vit dans
 * tests/Browser/ComponentsTest.php.
 *
 * Ce qui se vérifie ici est ce qui se lit dans le rendu : structure, attributs
 * d'accessibilité, discipline des tokens, et les gardes fail-loud.
 *
 * `toContain()` est PROSCRIT (variadique sur les needles, donc
 * `->not->toContain('a', 'message')` passe toujours) : on passe par
 * str_contains() + toBeFalse($message).
 */

/**
 * Extrait le contenu du premier attribut `class` du HTML rendu.
 *
 * Échoue bruyamment plutôt que de renvoyer une chaîne vide : un composant qui
 * ne rend aucune classe ferait passer toutes les assertions « n'émet pas lava »
 * par vacuité — le faux-vert exact que ces tests existent pour attraper.
 */
$firstClassAttribute = static function (string $html): string {
    $matched = preg_match('/class="([^"]*)"/', $html, $matches);

    expect($matched)
        ->toBe(1, "Aucun attribut class dans le HTML rendu : [{$html}]");

    return $matches[1] ?? '';
};

/**
 * Retire les utilities de l'ANNEAU de focus — nommément, pas par préfixe.
 *
 * L'AC6 impose que TOUT focusable de cette story dérive son anneau de focus de
 * `ring-lava/40`. L'AC1 impose que `variant="primary"` soit le SEUL à porter
 * --accent-lava. Les deux ne se contredisent que si on confond une surface avec
 * un état : l'anneau est un état (les 2 % de 90/8/2), pas un aplat — exemption
 * inscrite dans `tokens.css` RÈGLE 2.
 *
 * ⚠️ La première version filtrait TOUT ce qui commence par `focus-visible:`.
 * Trouvé en revue de code : un futur `focus-visible:bg-lava` — un aplat entier,
 * pas un liseré — aurait été écarté par le filtre et le garde-fou serait resté
 * vert. L'exemption est donc une LISTE NOMMÉE, qu'il faut modifier sciemment.
 *
 * @var list<string>
 */
$focusRingUtilities = [
    'focus-visible:outline-hidden',
    'focus-visible:outline-offset-2',
    'focus-visible:ring-2',
    'focus-visible:ring-lava/40',
    'focus-visible:ring-offset-2',
    'focus-visible:ring-offset-bg',
];

$classesOutsideFocusRing = static function (string $classes) use ($focusRingUtilities): string {
    $kept = array_filter(
        preg_split('/\s+/', trim($classes)) ?: [],
        static fn (string $class): bool => ! in_array($class, $focusRingUtilities, true),
    );

    return implode(' ', $kept);
};

/**
 * Vrai/faux sur la PRÉSENCE D'UN ATTRIBUT HTML, et non sur une sous-chaîne.
 *
 * Piège rencontré en écrivant ce fichier : `str_contains($html, 'disabled')` est
 * toujours vrai, parce que la liste de classes contient
 * `disabled:cursor-not-allowed`. Le test passait donc « au repos » aussi bien
 * qu'« désactivé » — une assertion qui ne distingue pas les deux états qu'elle
 * prétend séparer. On retire l'attribut class avant de chercher.
 */
$hasAttribute = static function (string $html, string $attribute): bool {
    $withoutClasses = (string) preg_replace('/\sclass="[^"]*"/', '', $html);

    return preg_match('/\s' . preg_quote($attribute, '/') . '(?=[\s=>])/', $withoutClasses) === 1;
};

/**
 * Déballe la cause racine d'une exception levée pendant un rendu Blade.
 *
 * Blade emballe toute exception de compilation dans une ViewException. Asserter
 * sur ViewException suffirait à faire passer le test pour n'importe quelle
 * erreur — y compris une faute de frappe dans le template. On remonte donc à la
 * cause, et c'est ELLE qui doit être l'InvalidArgumentException attendue.
 */
$rootCauseOf = static function (callable $callback): ?Throwable {
    try {
        $callback();
    } catch (Throwable $thrown) {
        while ($thrown->getPrevious() instanceof Throwable) {
            $thrown = $thrown->getPrevious();
        }

        return $thrown;
    }

    return null;
};

/**
 * Assertion d'absence avec un message qui atteint réellement le rapporteur.
 * Voir le commentaire de DesignTokensTest : `toContain()` ne peut pas le faire.
 */
$expectAbsent = static function (string $haystack, string $needle, string $message): void {
    expect(str_contains($haystack, $needle))
        ->toBeFalse($message);
};

/**
 * Supprime les commentaires Blade et HTML : un fichier a le droit d'écrire ce
 * qu'il s'interdit de faire.
 */
$stripComments = static function (string $source): string {
    return (string) preg_replace(['#\{\{--.*?--\}\}#s', '#<!--.*?-->#s'], '', $source);
};

/**
 * Les fichiers soumis à la RÈGLE 1 (aucune couleur en dur, aucune arbitrary
 * value) pour cette story : les composants et leur page de démonstration.
 *
 * La marche est RÉCURSIVE, comme celle de DesignTokensTest. Un `glob` plat
 * laissait sortir du périmètre tout composant rangé en sous-dossier
 * (`components/forms/input.blade.php`) — le contrôle de comptage serait resté
 * vert en n'inspectant rien de nouveau.
 *
 * @return list<string>
 */
$storyTemplates = static function (): array {
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

    $files[] = base_path('resources/views/_components-demo.blade.php');

    sort($files);

    return $files;
};

/**
 * Détecte une couleur en dur ou une arbitrary value Tailwind (RÈGLE 1).
 *
 * ⚠️ La première version ne connaissait que `#RRGGBB` et les arbitrary values.
 * Trouvé en revue de code : `class="bg-red-500"`, `style="color: red"` et
 * `oklch(...)` passaient tous — alors que la palette Tailwind est écrite en
 * oklch, donc que c'est la notation la plus susceptible d'être collée. Les
 * motifs de notation et de couleurs nommées sont repris de DesignTokensTest,
 * dont le périmètre s'arrêtait explicitement aux feuilles CSS.
 *
 * Le motif des arbitrary values exige un tiret avant le crochet et interdit
 * guillemets et espaces à l'intérieur : `bg-[#FF5722]` et `w-[32px]` sont
 * attrapés, `$entry['label']` et `in_array($t, ['a'])` ne sont pas des faux
 * positifs. Les `href="#..."` sont retirés avant l'analyse — sans quoi une ancre
 * nommée `#face` ou `#dad` serait signalée comme une couleur. Un détecteur
 * désarmé au premier faux positif est une décoration.
 *
 * `currentColor`, `transparent` et `inherit` restent autorisés : ils ne portent
 * aucune décision de design.
 *
 * @return list<string>
 */
$findHardcodedValues = static function (string $source) use ($stripComments): array {
    $stripped = $stripComments($source);
    $stripped = (string) preg_replace('/href="#[^"]*"/i', '', $stripped);

    $patterns = [
        '/#(?:[0-9A-Fa-f]{8}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{3})\b/',
        '/[a-z0-9]-\[[^\]\s\'"]*\]/i',
        '/\b(?:rgba?|hsla?|hwb|lab|lch|oklab|oklch|color|color-mix)\s*\(/i',
        '/\b(?:white|black|red|green|blue|yellow|orange|purple|pink|gray|grey|silver|maroon|navy|teal|olive|lime|aqua|fuchsia)\b/i',
    ];

    $found = [];

    foreach ($patterns as $pattern) {
        preg_match_all($pattern, $stripped, $matches);
        foreach ($matches[0] as $match) {
            $found[] = $match;
        }
    }

    return $found;
};

/**
 * Rejoue routes/web.php contre un routeur neuf, dans l'environnement demandé.
 *
 * C'est le seul moyen honnête de vérifier une garde `app()->environment()` : les
 * routes sont enregistrées au boot, donc changer l'environnement après coup ne
 * prouve rien. On reconstruit un routeur, on force l'environnement, on ré-exécute
 * le fichier (`require`, pas `require_once` : il DOIT s'exécuter à nouveau), puis
 * on remet tout en place.
 */
$routesRegisteredIn = static function (string $environment): Illuminate\Routing\RouteCollectionInterface {
    $app = app();
    $detected = $app->environment();
    $previousEnvironment = is_string($detected) ? $detected : 'testing';
    $previousRouter = app(Router::class);

    $app->detectEnvironment(static fn (): string => $environment);

    $router = new Router(app(Dispatcher::class), $app);
    $app->instance('router', $router);
    RouteFacade::swap($router);

    try {
        // Portée isolée : `require` s'exécute dans le scope de l'appelant, donc
        // une future variable `$router` ou `$app` déclarée dans routes/web.php
        // écraserait celles d'ici — et le `finally` restaurerait un routeur
        // corrompu pour toute la suite.
        (static function (): void {
            require base_path('routes/web.php');
        })();

        // `Route::get(...)->name(...)` nomme la route APRÈS son ajout à la
        // collection : la table de correspondance nom → route est reconstruite
        // par le framework au `booted()`, jamais atteint ici. Sans ce
        // rafraîchissement, getByName() renvoie null pour TOUTES les routes et
        // le test serait vert en production pour la mauvaise raison.
        $router->getRoutes()
            ->refreshNameLookups();
    } finally {
        $app->detectEnvironment(static fn (): string => $previousEnvironment);
        $app->instance('router', $previousRouter);
        RouteFacade::swap($previousRouter);
    }

    return $router->getRoutes();
};

/*
|--------------------------------------------------------------------------
| AC1 — <x-button>
|--------------------------------------------------------------------------
*/

it('rend 3 variants de bouton aux classes distinctes (AC1)', function () use ($firstClassAttribute): void {
    $classesByVariant = [];

    foreach (['primary', 'secondary', 'ghost'] as $variant) {
        $classesByVariant[$variant] = $firstClassAttribute(
            Blade::render('<x-button :variant="$variant">Go</x-button>', [
                'variant' => $variant,
            ]),
        );
    }

    expect(array_unique(array_values($classesByVariant)))
        ->toHaveCount(3, 'Deux variants de bouton produisent les mêmes classes.');
});

it('ne laisse que variant="primary" porter --accent-lava (AC1, RÈGLE 2)', function () use (
    $firstClassAttribute,
    $classesOutsideFocusRing,
    $expectAbsent
): void {
    /*
     * L'usage 2/4 de la RÈGLE 2 est « les CTA primaires ». Un jour où
     * `secondary` gagnera un `text-lava` « juste pour attirer l'œil », l'orange
     * cessera d'être un signal et le badge LIVE — seul vrai moment d'urgence de
     * l'app — perdra son pouvoir. Ce test est le prix d'entrée.
     *
     * Vu rouge : en ajoutant `text-lava` aux classes du variant `ghost`.
     */
    $primary = $classesOutsideFocusRing($firstClassAttribute(Blade::render('<x-button variant="primary">Go</x-button>')));

    expect(str_contains($primary, 'lava'))
        ->toBeTrue('variant="primary" est le CTA primaire : il DOIT porter lava (usage 2/4).');

    foreach (['secondary', 'ghost'] as $variant) {
        $classes = $classesOutsideFocusRing(
            $firstClassAttribute(Blade::render('<x-button :variant="$variant">Go</x-button>', [
                'variant' => $variant,
            ])),
        );

        $expectAbsent(
            $classes,
            'lava',
            "<x-button variant=\"{$variant}\"> émet lava hors anneau de focus : RÈGLE 2 (90/8/2) ne l'autorise que sur les CTA primaires.",
        );
    }
});

it('émet de vrais attributs pour disabled et loading, pas seulement du style (AC1)', function () use ($hasAttribute): void {
    /*
     * Un bouton qui a l'air désactivé mais reste cliquable, ou qui a l'air de
     * charger sans le dire aux technologies d'assistance, est un garde-fou
     * silencieux au sens strict : il affirme un état que rien ne porte.
     */
    $plain = Blade::render('<x-button>Go</x-button>');
    $disabled = Blade::render('<x-button :disabled="true">Go</x-button>');
    $loading = Blade::render('<x-button :loading="true">Go</x-button>');

    expect($hasAttribute($plain, 'disabled'))
        ->toBeFalse('Un bouton au repos ne doit pas être désactivé.');
    expect($hasAttribute($plain, 'aria-busy'))
        ->toBeFalse('Un bouton au repos ne doit pas être aria-busy.');

    expect($hasAttribute($disabled, 'disabled'))
        ->toBeTrue('L\'attribut disabled est absent du bouton désactivé.');

    expect(str_contains($loading, 'aria-busy="true"'))
        ->toBeTrue('Le bouton en chargement n\'annonce pas aria-busy.');
    expect($hasAttribute($loading, 'disabled'))
        ->toBeTrue('Un bouton en chargement doit aussi être disabled.');
    expect(str_contains($loading, 'data-role="spinner"'))
        ->toBeTrue('Le bouton en chargement ne rend aucun indicateur.');
});

/*
|--------------------------------------------------------------------------
| AC2 — <x-card>
|--------------------------------------------------------------------------
*/

it('expose un slot principal et distingue selected de default (AC2)', function () use ($firstClassAttribute): void {
    $default = Blade::render('<x-card>Contenu de carte</x-card>');
    $selected = Blade::render('<x-card :selected="true">Contenu de carte</x-card>');

    expect(str_contains($default, 'Contenu de carte'))
        ->toBeTrue('<x-card> ne rend pas son slot principal.');

    expect(str_contains($selected, 'data-selected="true"'))
        ->toBeTrue('<x-card :selected="true"> n\'expose pas son état dans le DOM.');

    expect($firstClassAttribute($default))
        ->not->toBe($firstClassAttribute($selected), 'default et selected produisent les mêmes classes.');
});

/*
|--------------------------------------------------------------------------
| AC3 — <x-badge>
|--------------------------------------------------------------------------
*/

it('rend les 5 variants de badge, tous distincts (AC3)', function () use ($firstClassAttribute): void {
    $classes = [];

    foreach (['neutral', 'lava', 'ok', 'warn', 'err'] as $variant) {
        $html = Blade::render('<x-badge :variant="$variant">X</x-badge>', [
            'variant' => $variant,
        ]);

        expect(str_contains($html, "data-variant=\"{$variant}\""))
            ->toBeTrue("Le variant [{$variant}] n'est pas rendu.");

        $classes[] = $firstClassAttribute($html);
    }

    expect(array_unique($classes))
        ->toHaveCount(5, 'Deux variants de badge produisent les mêmes classes.');
});

it('interdit --accent-lava à tout variant de badge autre que lava (AC3)', function () use (
    $firstClassAttribute,
    $expectAbsent
): void {
    /*
     * Vu rouge : en remplaçant les classes du variant `neutral` par
     * `bg-surface text-lava border-border`. Le test a échoué en nommant le
     * variant fautif, puis la garde a été restaurée.
     */
    $lava = $firstClassAttribute(Blade::render('<x-badge variant="lava">LIVE</x-badge>'));

    expect(str_contains($lava, 'lava'))
        ->toBeTrue('Le variant lava n\'émet pas lava — il porte pourtant 3 des 4 usages de la RÈGLE 2.');

    foreach (['neutral', 'ok', 'warn', 'err'] as $variant) {
        $classes = $firstClassAttribute(
            Blade::render('<x-badge :variant="$variant">X</x-badge>', [
                'variant' => $variant,
            ]),
        );

        $expectAbsent(
            $classes,
            'lava',
            "<x-badge variant=\"{$variant}\"> émet lava : la RÈGLE 2 réserve l'accent à 4 usages nommés.",
        );
    }
});

/*
|--------------------------------------------------------------------------
| AC4 — <x-icon-button>
|--------------------------------------------------------------------------
*/

it('refuse de rendre un icon-button sans aria-label, en se nommant (AC4)', function () use ($rootCauseOf): void {
    /*
     * Une icône seule n'expose AUCUN nom accessible : le bouton est muet pour un
     * lecteur d'écran et rien, à l'écran, ne le signale. C'est une erreur de
     * programmation, pas une valeur par défaut acceptable — d'où le fail-loud.
     *
     * Vu rouge : en remplaçant le `throw` par un `$ariaLabel = '';` silencieux.
     */
    $templates = [
        '<x-icon-button>x</x-icon-button>',
        '<x-icon-button aria-label="">x</x-icon-button>',
        '<x-icon-button aria-label="  ">x</x-icon-button>',
    ];

    foreach ($templates as $template) {
        $cause = $rootCauseOf(static fn (): string => Blade::render($template));

        expect($cause)
            ->toBeInstanceOf(InvalidArgumentException::class, "[{$template}] a été rendu sans nom accessible.");

        expect(str_contains($cause instanceof Throwable ? $cause->getMessage() : '', '<x-icon-button>'))
            ->toBeTrue('Le message d\'erreur ne nomme pas le composant fautif.');
    }
});

it('rend aria-label et s\'en sert comme infobulle native (AC4)', function (): void {
    $html = Blade::render('<x-icon-button aria-label="Fermer">x</x-icon-button>');

    expect(str_contains($html, 'aria-label="Fermer"'))
        ->toBeTrue('aria-label a disparu du HTML rendu — il a probablement été absorbé par @props.');

    expect(str_contains($html, 'title="Fermer"'))
        ->toBeTrue('aria-label ne sert pas d\'infobulle native.');
});

it('laisse un title explicite l\'emporter sur le repli aria-label (AC4)', function (): void {
    $html = Blade::render('<x-icon-button aria-label="Fermer" title="Fermer la notification">x</x-icon-button>');

    expect(str_contains($html, 'title="Fermer la notification"'))
        ->toBeTrue('Le title fourni par l\'appelant doit primer : merge() fournit un défaut, pas une contrainte.');
});

/*
|--------------------------------------------------------------------------
| AC5 — <x-divider>
|--------------------------------------------------------------------------
*/

it('porte role="separator" et ne rend son libellé que s\'il est fourni (AC5)', function () use ($expectAbsent): void {
    $plain = Blade::render('<x-divider />');
    $labelled = Blade::render('<x-divider>Suite</x-divider>');

    expect(str_contains($plain, 'role="separator"'))
        ->toBeTrue('<x-divider> ne porte pas role="separator" (le rôle implicite de <hr> ne se lit pas dans le markup).');

    $expectAbsent(
        $plain,
        'data-role="divider-label"',
        '<x-divider /> rend un conteneur de libellé vide alors qu\'aucun slot n\'est fourni.',
    );

    expect(str_contains($labelled, 'Suite'))
        ->toBeTrue('<x-divider> ne rend pas le libellé fourni.');
});

/*
|--------------------------------------------------------------------------
| AC6 — anneau de focus (structure ; la valeur calculée est en Browser)
|--------------------------------------------------------------------------
*/

it('dérive l\'anneau de focus du token sur tous les focusables de la story (AC6)', function (): void {
    $focusables = [
        '<x-button>Go</x-button>',
        '<x-icon-button aria-label="Fermer">x</x-icon-button>',
    ];

    foreach ($focusables as $template) {
        $html = Blade::render($template);

        expect(str_contains($html, 'focus-visible:ring-lava/40'))
            ->toBeTrue("Anneau de focus non dérivé du token dans [{$template}] : ring-lava/40 compile en color-mix(in oklab, var(--accent-lava) 40%, transparent).");

        expect(str_contains($html, 'focus-visible:outline-offset-2'))
            ->toBeTrue("outline-offset: 2px manquant dans [{$template}].");
    }
});

/*
|--------------------------------------------------------------------------
| AC7 — <x-toast>, structure seulement
|--------------------------------------------------------------------------
*/

it('rend les 4 types de toast, visuellement distincts, avec le bon rôle ARIA (AC7)', function () use ($firstClassAttribute): void {
    /*
     * `alert` interrompt le lecteur d'écran ; `status` est annoncé poliment.
     * Interrompre pour un « Enregistré. » est une agression, ne pas interrompre
     * pour une erreur est une perte d'information.
     */
    $expectedRoles = [
        'success' => 'status',
        'info' => 'status',
        'warning' => 'alert',
        'error' => 'alert',
    ];

    $classes = [];

    foreach ($expectedRoles as $type => $role) {
        $html = Blade::render('<x-toast :type="$type">Message</x-toast>', [
            'type' => $type,
        ]);

        expect(str_contains($html, "role=\"{$role}\""))
            ->toBeTrue("<x-toast type=\"{$type}\"> devrait porter role=\"{$role}\".");

        $classes[] = $firstClassAttribute($html);
    }

    expect(array_unique($classes))
        ->toHaveCount(4, 'Deux types de toast sont visuellement identiques.');
});

it('expose un bouton de fermeture nommé et une durée par défaut de 5000 ms (AC7)', function (): void {
    $html = Blade::render('<x-toast type="info">Message</x-toast>');

    expect(str_contains($html, 'data-toast-duration="5000"'))
        ->toBeTrue('La durée d\'auto-fermeture n\'est pas exposée en attribut de données avec le défaut 5000.');

    expect(str_contains($html, 'data-toast-dismiss'))
        ->toBeTrue('Aucun bouton de fermeture dans le toast.');

    expect(str_contains($html, 'aria-label="Fermer la notification"'))
        ->toBeTrue('Le bouton de fermeture n\'a pas de nom accessible.');

    $custom = Blade::render('<x-toast type="info" :duration="1200">Message</x-toast>');

    expect(str_contains($custom, 'data-toast-duration="1200"'))
        ->toBeTrue('La durée n\'est pas surchargeable par prop.');
});

it('ne livre AUCUN comportement d\'auto-fermeture — il appartient à la Story 1.13 (AC7)', function () use (
    $stripComments,
    $expectAbsent
): void {
    /*
     * ⚠️ Ce test est un dos-d'âne délibéré, et il est daté.
     *
     * L'auto-fermeture exige Alpine, chargé par @livewireScripts en Story 1.13.
     * Écrite ici, elle serait du comportement livré dans une page qui n'exécute
     * rien : un AC qui se valide sans que quoi que ce soit ne tourne — le motif
     * exact qui a fait réordonner l'Epic 1 (arbitrage PO du 2026-08-08).
     *
     * EN STORY 1.13 : supprimer ce test et le remplacer par la vérification du
     * comportement dans un navigateur (fermeture après data-toast-duration ms).
     * Le voir rougir alors n'est pas une régression, c'est le rendez-vous.
     */
    $source = $stripComments((string) file_get_contents(base_path('resources/views/components/toast.blade.php')));

    foreach (['x-data', 'x-init', 'setTimeout', 'addEventListener', 'wire:', 'Alpine'] as $needle) {
        $expectAbsent(
            $source,
            $needle,
            "toast.blade.php contient [{$needle}] : le comportement d'auto-fermeture appartient à la Story 1.13, où Alpine est chargé et où il peut être observé.",
        );
    }
});

/*
|--------------------------------------------------------------------------
| RÈGLE 1 — aucune couleur en dur, aucune arbitrary value
|--------------------------------------------------------------------------
*/

it('détecte hex et arbitrary values, et seulement elles (auto-contrôle du scanner)', function () use ($findHardcodedValues): void {
    /*
     * Leçon de la Story 1.8 : un scanner qui parcourt des fichiers peut être vert
     * par vacuité. On l'exerce donc d'abord sur des fixtures synthétiques — une
     * qui DOIT être signalée, une qui ne DOIT PAS l'être — avant de le lâcher sur
     * le vrai code.
     */
    expect($findHardcodedValues('<div class="bg-[#FF5722]"></div>'))
        ->not->toBeEmpty();
    expect($findHardcodedValues('<div style="color: #AABBCC"></div>'))
        ->not->toBeEmpty();
    expect($findHardcodedValues('<div class="w-[32px]"></div>'))
        ->not->toBeEmpty();

    /*
     * Une notation par cas. Un détecteur qui ne connaîtrait que #RRGGBB
     * laisserait passer les trois suivantes — et oklch est celle dans laquelle
     * la palette Tailwind elle-même est écrite, donc la plus susceptible d'être
     * collée. Ajouté après la revue de code de cette story.
     */
    expect($findHardcodedValues('<div class="bg-red-500"></div>'))
        ->not->toBeEmpty();
    expect($findHardcodedValues('<div style="background: oklch(0.7 0.21 41)"></div>'))
        ->not->toBeEmpty();
    expect($findHardcodedValues('<div style="color: rgb(255 87 34)"></div>'))
        ->not->toBeEmpty();

    // Faux positifs à ne pas produire : ancres (y compris celles dont le nom
    // ressemble à un hex), accès tableau PHP, entités HTML, mots-clés neutres.
    expect($findHardcodedValues('<a href="#focus-lab">x</a>'))
        ->toBeEmpty();
    expect($findHardcodedValues('<a href="#face">x</a><a href="#dad">y</a>'))
        ->toBeEmpty();
    expect($findHardcodedValues('{{ $entry[\'label\'] }} @if (in_array($t, [\'a\']))'))
        ->toBeEmpty();
    expect($findHardcodedValues('<span>&times;</span>'))
        ->toBeEmpty();
    expect($findHardcodedValues('<div class="border-transparent text-current"></div>'))
        ->toBeEmpty();
});

it('ne hardcode ni couleur ni arbitrary value dans les composants de la story (RÈGLE 1)', function () use (
    $storyTemplates,
    $findHardcodedValues
): void {
    $templates = $storyTemplates();

    expect($templates)
        ->not->toBeEmpty('Le scan RÈGLE 1 n\'a trouvé aucun template à inspecter.');

    expect($templates)
        ->toHaveCount(7, 'Les 6 composants + la page de démonstration sont attendus : un fichier a été ajouté ou retiré sans mettre ce garde-fou à jour.');

    foreach ($templates as $template) {
        expect($findHardcodedValues((string) file_get_contents($template)))
            ->toBeEmpty(basename($template) . ' hardcode une couleur ou une arbitrary value — tout doit passer par les utilities issues des tokens.');
    }
});

/*
|--------------------------------------------------------------------------
| T9 — la page de démonstration ne doit pas exister en production
|--------------------------------------------------------------------------
*/

it('n\'enregistre la route de démonstration qu\'en local et testing (T9)', function () use ($routesRegisteredIn): void {
    /*
     * Vu rouge : en retirant le `if (app()->environment([...]))` de
     * routes/web.php. Le test a échoué sur l'environnement `production`, puis la
     * garde a été restaurée.
     */
    foreach (['local', 'testing'] as $environment) {
        expect($routesRegisteredIn($environment)->getByName('components.demo'))
            ->not->toBeNull("La galerie de composants devrait être disponible en [{$environment}].");
    }

    $production = $routesRegisteredIn('production');

    // Anti-vacuité : si le fichier de routes n'avait pas été rejoué du tout, la
    // route de démo serait absente pour une mauvaise raison et ce test serait
    // vert sans rien prouver.
    expect(count($production->getRoutes()))
        ->toBeGreaterThan(0, 'routes/web.php n\'a pas été rejoué : le test ne prouve rien.');

    expect($production->getByName('components.demo'))
        ->toBeNull('La galerie de composants est exposée en production : surface inutile, non gardée.');
});

/*
|--------------------------------------------------------------------------
| AC8 — champs streamer consommés par l'écran offline
|--------------------------------------------------------------------------
*/

it('ordonne les liens sociaux et les garde entièrement configurables (AC8)', function (): void {
    $streamer = Streamer::factory()->create([
        'discord_url' => 'https://discord.example/serveur',
        'social_links' => [
            [
                'label' => 'Second',
                'url' => 'https://exemple.test/2',
                'order' => 2,
            ],
            [
                'label' => 'Premier',
                'url' => 'https://exemple.test/1',
                'order' => 1,
            ],
        ],
    ]);

    expect($streamer->orderedSocialLinks())
        ->toBe([
            [
                'label' => 'Premier',
                'url' => 'https://exemple.test/1',
            ],
            [
                'label' => 'Second',
                'url' => 'https://exemple.test/2',
            ],
        ]);
});

it('exclut discord_url des liens sociaux — c\'est du retour, pas de la sortie (AC8)', function (): void {
    /*
     * ADR-0012 : `social_links[]` est de la SORTIE (des profils vers lesquels on
     * envoie), `discord_url` est du RETOUR, au rang du CTA. Un streamer qui colle
     * son Discord dans la liste diluerait le seul canal par lequel l'audience
     * revient — la garde est donc active, pas seulement une convention.
     *
     * Vu rouge : en retirant le filtre `if (is_string($discordUrl) && ...)` de
     * Streamer::orderedSocialLinks().
     */
    $streamer = Streamer::factory()->create([
        'discord_url' => 'https://discord.example/serveur',
        'social_links' => [
            [
                'label' => 'Discord',
                'url' => 'https://discord.example/serveur',
                'order' => 1,
            ],
            [
                'label' => 'Ailleurs',
                'url' => 'https://exemple.test/ailleurs',
                'order' => 2,
            ],
        ],
    ]);

    expect($streamer->orderedSocialLinks())
        ->toBe([[
            'label' => 'Ailleurs',
            'url' => 'https://exemple.test/ailleurs',
        ]]);
});

it('laisse tomber les entrées inexploitables plutôt que d\'afficher un lien mort (AC8)', function (): void {
    $streamer = Streamer::factory()->create([
        'discord_url' => null,
        'social_links' => [
            [
                'label' => 'Sans url',
            ],
            [
                'url' => 'https://exemple.test/sans-label',
            ],
            [
                'label' => '   ',
                'url' => 'https://exemple.test/vide',
            ],
            'chaine-brute',
            [
                'label' => 'Valide',
                'url' => 'https://exemple.test/ok',
            ],
        ],
    ]);

    expect($streamer->orderedSocialLinks())
        ->toBe([[
            'label' => 'Valide',
            'url' => 'https://exemple.test/ok',
        ]]);
});

it('tolère un streamer sans aucun lien social configuré (AC8)', function (): void {
    $streamer = Streamer::factory()->create([
        'social_links' => null,
    ]);

    expect($streamer->orderedSocialLinks())
        ->toBe([]);
});

it('ne code en dur aucun réseau social dans les composants ni la page de démo (AC8)', function () use (
    $storyTemplates,
    $stripComments,
    $expectAbsent
): void {
    /*
     * « Zéro réseau en dur » : un fork-streamer sans TikTok ne doit pas avoir à
     * toucher au code (ADR-0001). Le jour où un nom de réseau apparaît dans un
     * template, la configurabilité est morte sans que rien ne le signale.
     */
    $networks = ['twitch', 'youtube', 'instagram', 'tiktok', 'twitter', 'discord', 'facebook', 'bluesky', 'mastodon'];

    $templates = $storyTemplates();

    /*
     * Anti-vacuité, absente de la première version et relevée en revue : si le
     * chemin des templates se déplaçait, la boucle ne s'exécuterait jamais et ce
     * test serait vert après n'avoir rien inspecté. C'est précisément le défaut
     * que l'en-tête de ce fichier passe son temps à dénoncer.
     */
    expect($templates)
        ->not->toBeEmpty('Le scan « zéro réseau en dur » n\'a trouvé aucun template à inspecter.');

    foreach ($templates as $template) {
        $source = mb_strtolower($stripComments((string) file_get_contents($template)));

        foreach ($networks as $network) {
            $expectAbsent(
                $source,
                $network,
                basename($template) . " nomme [{$network}] en dur : les réseaux se configurent, ils ne se codent pas.",
            );
        }
    }
});

/*
|--------------------------------------------------------------------------
| Gardes fail-loud des composants — relevés non testés en revue de code
|--------------------------------------------------------------------------
*/

it('refuse bruyamment un variant, un type ou une durée hors domaine', function () use ($rootCauseOf): void {
    /*
     * Seul <x-icon-button> était couvert. Trois autres `default => throw`
     * pouvaient donc être remplacés par un repli silencieux sans qu'une seule
     * assertion bouge — et un repli silencieux sur le variant de <x-badge> fait
     * s'éroder la RÈGLE 2 sans le moindre signal, ce que le commentaire du
     * composant prétend justement empêcher.
     *
     * `type` et `duration` s'y ajoutent : `type="sumbit"` retombe sur `submit`
     * d'après la spec HTML — dans un formulaire, c'est une soumission non voulue
     * — et `(int) '5s'` valait 0, soit une durée qui n'en est pas une.
     */
    $cases = [
        '<x-button variant="nope">x</x-button>' => '<x-button>',
        '<x-button type="sumbit">x</x-button>' => '<x-button>',
        '<x-badge variant="nope">x</x-badge>' => '<x-badge>',
        '<x-toast type="nope">x</x-toast>' => '<x-toast>',
        '<x-toast type="info" :duration="0">x</x-toast>' => '<x-toast>',
        '<x-toast type="info" duration="5s">x</x-toast>' => '<x-toast>',
        '<x-toast type="info" :dismiss-label="\'\'">x</x-toast>' => '<x-toast>',
        '<x-icon-button type="sumbit" aria-label="x">x</x-icon-button>' => '<x-icon-button>',
    ];

    foreach ($cases as $template => $expectedComponent) {
        $cause = $rootCauseOf(static fn (): string => Blade::render($template));

        expect($cause)
            ->toBeInstanceOf(InvalidArgumentException::class, "[{$template}] a été rendu sans broncher.");

        expect(str_contains($cause instanceof Throwable ? $cause->getMessage() : '', $expectedComponent))
            ->toBeTrue("Le message d'erreur de [{$template}] ne nomme pas {$expectedComponent}.");
    }
});

it('lit les props booléennes comme du HTML, pas comme du PHP', function () use ($hasAttribute): void {
    /*
     * `<x-button disabled="false">` : l'attribut arrive en CHAÎNE, et
     * `(bool) 'false'` vaut true — le bouton sortait désactivé en demandant le
     * contraire. Aucun test ne pouvait le voir parce que tous passaient des
     * booléens PHP via `:disabled="true"`.
     */
    expect($hasAttribute(Blade::render('<x-button disabled="false">x</x-button>'), 'disabled'))
        ->toBeFalse('disabled="false" désactive le bouton : la chaîne est lue comme un booléen PHP.');

    expect($hasAttribute(Blade::render('<x-button disabled="true">x</x-button>'), 'disabled'))
        ->toBeTrue('disabled="true" ne désactive pas le bouton.');

    expect(str_contains(Blade::render('<x-card selected="false">x</x-card>'), 'data-selected'))
        ->toBeFalse('selected="false" marque la carte comme sélectionnée.');
});

it('n\'émet jamais deux fois le même attribut quand l\'appelant en fournit un (HTML valide)', function (): void {
    /*
     * `role`, `data-variant`, `data-selected` et les `data-toast-*` étaient
     * écrits AVANT le merge du sac d'attributs : un appelant qui en passait un
     * obtenait l'attribut deux fois. Le parseur garde silencieusement le premier
     * et jette l'intention de l'appelant — HTML invalide, aucune erreur.
     */
    $duplicated = [
        '<x-toast type="info" role="alert">x</x-toast>' => 'role',
        '<x-toast type="info" data-toast-duration="9">x</x-toast>' => 'data-toast-duration',
        '<x-divider role="presentation" />' => 'role',
        '<x-badge variant="ok" data-variant="lava">x</x-badge>' => 'data-variant',
        '<x-card :selected="true" data-selected="false">x</x-card>' => 'data-selected',
    ];

    foreach ($duplicated as $template => $attribute) {
        /*
         * Le nom d'attribut est ancré sur une espace précédente : sans elle,
         * chercher `role=` compte aussi `data-role=` — l'assertion échouait pour
         * une raison qui n'avait rien à voir avec le défaut visé. Un test qui
         * rougit pour la mauvaise raison n'est pas un meilleur test.
         */
        $occurrences = preg_match_all(
            '/\s' . preg_quote($attribute, '/') . '="/',
            Blade::render($template),
        );

        expect($occurrences)
            ->toBe(1, "[{$template}] émet [{$attribute}] {$occurrences} fois : HTML invalide, intention de l'appelant perdue en silence.");
    }
});

it('expose le libellé du séparateur aux technologies d\'assistance (AC5)', function () use ($expectAbsent): void {
    /*
     * `role="separator"` n'autorise PAS le « name from content » (ARIA) : le
     * libellé « Suite » était visible à l'écran et muet au lecteur d'écran.
     * Relevé en revue de code — l'AC ne demandait que le rendu, donc le test
     * initial était satisfait par un composant à moitié accessible.
     */
    $labelled = Blade::render('<x-divider>Suite</x-divider>');

    expect(str_contains($labelled, 'aria-label="Suite"'))
        ->toBeTrue('Le libellé du séparateur n\'est exposé à aucune technologie d\'assistance.');

    $expectAbsent(
        Blade::render('<x-divider />'),
        'aria-label',
        'Un séparateur sans libellé ne doit pas porter d\'aria-label vide.',
    );

    // Un slot qui ne contient que des blancs compte pour vide : sinon on rend le
    // trou dans la ligne que ce composant existe pour éviter.
    $expectAbsent(
        Blade::render('<x-divider>   </x-divider>'),
        'data-role="divider-label"',
        'Un slot fait uniquement d\'espaces rend un conteneur de libellé creux.',
    );
});

/*
|--------------------------------------------------------------------------
| AC8 — la moitié « consommée par un composant », relevée non testée en revue
|--------------------------------------------------------------------------
*/

it('rend réellement les champs streamer dans la page qui les consomme (AC8)', function (): void {
    /*
     * Avant ce test, AC8 ne prouvait qu'une chose : une méthode de modèle trie un
     * tableau. On pouvait supprimer les deux blocs @if de la page de démo et
     * toute la suite — Feature ET navigateur — restait verte. « When un composant
     * les consomme » n'avait aucun référent.
     *
     * Le second lien est un PIÈGE délibéré : c'est une AUTRE invitation vers le
     * même serveur Discord. La comparaison octet à octet de la première version
     * l'aurait laissé passer ; la comparaison par HÔTE l'écarte. Le garde-fou se
     * vérifie donc de bout en bout, pas seulement sur l'entrée qui l'arrange.
     */
    $streamer = Streamer::factory()->create([
        'cta_text' => 'Rejoindre le live',
        'cta_url' => 'https://exemple.test/live',
        'discord_url' => 'https://discord.example/serveur',
        'social_links' => [
            [
                'label' => 'Profil principal',
                'url' => 'https://exemple.test/principal',
                'order' => 1,
            ],
            [
                'label' => 'Autre invitation Discord',
                'url' => 'https://discord.example/une-autre-invitation',
                'order' => 2,
            ],
        ],
    ]);

    /*
     * On passe par le Kernel HTTP plutôt que par `$this->get()` : dans une
     * closure Pest, PHPStan résout `$this` en TestCall et non en TestCase, ce
     * qui produit 4 erreurs au niveau 10. Le noyau donne le même parcours réel —
     * groupe `web`, SetCurrentStreamer, CSP — avec un typage complet.
     */
    $response = app(Kernel::class)->handle(Request::create(route('components.demo')));

    expect($response->getStatusCode())
        ->toBe(200, 'La galerie de composants ne répond pas 200 : le streamer courant n\'a pas été résolu ?');

    $html = (string) $response->getContent();

    expect(str_contains($html, 'Rejoindre le live'))
        ->toBeTrue('Le CTA du streamer n\'est pas rendu : cta_text n\'est consommé par rien.');

    expect(str_contains($html, 'https://exemple.test/live'))
        ->toBeTrue('cta_url n\'atteint pas le DOM.');

    expect(str_contains($html, 'Profil principal'))
        ->toBeTrue('Les liens sociaux configurés ne sont pas rendus.');

    expect(str_contains($html, 'Autre invitation Discord'))
        ->toBeFalse('Un second lien vers le serveur Discord a atteint la liste de sortie : ADR-0012 le classe en RETOUR, au rang du CTA.');

    expect(str_contains($html, 'rel="noopener noreferrer"'))
        ->toBeTrue('Les liens sortants ne portent pas rel="noopener noreferrer".');

    expect($streamer->orderedSocialLinks())
        ->toHaveCount(1);
});

it('n\'admet que des URL http(s) parmi les liens sociaux (AC8)', function (): void {
    /*
     * `javascript:` et `data:` dans un href s'exécutent au clic. L'échappement
     * Blade empêche la sortie d'attribut, pas l'abus de schéma — et c'est le
     * streamer qui écrit cette colonne, aujourd'hui à la main, demain via un
     * formulaire Filament (Story 1.10a).
     *
     * ⚠️ Le cas `ftp://` n'est pas décoratif, et c'est la campagne de mutation
     * qui l'a exigé : sans lui, retirer le contrôle de schéma de hostOf() ne
     * faisait RIEN rougir. `javascript:` et `data:` n'ont pas d'hôte, donc
     * l'exigence d'hôte les écartait déjà — le contrôle de schéma n'était mis à
     * l'épreuve par aucune entrée. Un garde-fou dont aucun test ne dépend est
     * exactement ce que ce projet passe son temps à trouver.
     *
     * Vu rouge : en retirant le contrôle de schéma de Streamer::hostOf().
     */
    $streamer = Streamer::factory()->create([
        'discord_url' => null,
        'social_links' => [
            [
                'label' => 'Piège',
                'url' => 'javascript:alert(1)',
            ],
            [
                'label' => 'Schéma non web',
                'url' => 'ftp://exemple.test/fichier',
            ],
            [
                'label' => 'Piège 2',
                'url' => 'data:text/html,<script>alert(1)</script>',
            ],
            [
                'label' => 'Relatif',
                'url' => '/interne',
            ],
            [
                'label' => 'Légitime',
                'url' => 'https://exemple.test/ok',
            ],
        ],
    ]);

    expect($streamer->orderedSocialLinks())
        ->toBe([[
            'label' => 'Légitime',
            'url' => 'https://exemple.test/ok',
        ]]);
});

it('écarte le Discord du streamer quelle que soit la forme de l\'URL (AC8)', function (): void {
    /*
     * Comparer les octets faisait passer un slash final, un `http://` au lieu de
     * `https://`, une casse d'hôte différente ou une seconde invitation. Le
     * garde-fou ne rougissait que sur l'unique entrée qu'on lui donnait.
     */
    $streamer = Streamer::factory()->create([
        'discord_url' => 'https://discord.example/serveur',
        'social_links' => [
            [
                'label' => 'Slash final',
                'url' => 'https://discord.example/serveur/',
            ],
            [
                'label' => 'Schéma différent',
                'url' => 'http://discord.example/serveur',
            ],
            [
                'label' => 'Casse différente',
                'url' => 'https://DISCORD.example/serveur',
            ],
            [
                'label' => 'Espaces autour',
                'url' => '  https://discord.example/serveur  ',
            ],
            [
                'label' => 'Ailleurs',
                'url' => 'https://exemple.test/ailleurs',
            ],
        ],
    ]);

    expect($streamer->orderedSocialLinks())
        ->toBe([[
            'label' => 'Ailleurs',
            'url' => 'https://exemple.test/ailleurs',
        ]]);
});

it('honore un ordre écrit en chaîne ou en flottant, comme le JSON le rend (AC8)', function (): void {
    /*
     * Un `order` fait l'aller-retour JSON en "1", en 2.0 ou en 3 selon qui l'a
     * écrit — un formulaire Filament renverra des chaînes. `is_int()` les
     * renvoyait toutes en fin de liste, donc l'ordre configuré était ignoré
     * sans que rien ne le dise.
     */
    $streamer = Streamer::factory()->create([
        'discord_url' => null,
        'social_links' => [
            [
                'label' => 'Troisième',
                'url' => 'https://exemple.test/3',
                'order' => 3,
            ],
            [
                'label' => 'Premier',
                'url' => 'https://exemple.test/1',
                'order' => '1',
            ],
            [
                'label' => 'Deuxième',
                'url' => 'https://exemple.test/2',
                'order' => 2.0,
            ],
            [
                'label' => 'Sans ordre',
                'url' => 'https://exemple.test/4',
            ],
        ],
    ]);

    expect(array_column($streamer->orderedSocialLinks(), 'label'))
        ->toBe(['Premier', 'Deuxième', 'Troisième', 'Sans ordre']);
});

it('renvoie des valeurs déjà nettoyées, pas seulement validées nettoyées (AC8)', function (): void {
    /*
     * La première version validait sur `trim($url)` et renvoyait `$url` brut :
     * l'URL comparée à discord_url n'était donc pas celle qui atteignait le
     * href. Deux notions de « l'URL » dans la même méthode.
     */
    $streamer = Streamer::factory()->create([
        'discord_url' => null,
        'social_links' => [
            [
                'label' => '  Profil  ',
                'url' => '  https://exemple.test/ok  ',
            ],
        ],
    ]);

    expect($streamer->orderedSocialLinks())
        ->toBe([[
            'label' => 'Profil',
            'url' => 'https://exemple.test/ok',
        ]]);
});
