<?php

declare(strict_types=1);

use Illuminate\Contracts\Http\Kernel;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Blade;
use Tests\Support\RouteTable;

uses(RefreshDatabase::class);

/**
 * Story 1.13 — <x-layouts.public> et <x-layouts.minimal>.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * CE QUE CE FICHIER NE FAIT PAS
 *
 * Il ne prétend vérifier NI la hauteur du header, NI `position: sticky`, NI la
 * visibilité du lien de saut, NI l'auto-fermeture du toast. Aucune de ces
 * quatre choses n'existe dans une chaîne de HTML : `h-12 lg:h-14` prouve
 * seulement que quelqu'un a tapé ces caractères. Elles vivent dans
 * tests/Browser/LayoutsTest.php, mesurées par valeur calculée.
 *
 * Ce qui se vérifie ici est ce qui se lit dans le rendu : le squelette de
 * document, l'ORDRE des régions, les absences, et les deux piles d'insertion
 * — ces dernières en y POUSSANT du contenu, jamais en cherchant `@stack` dans
 * le fichier source (une directive présente ne prouve pas qu'elle reçoit).
 *
 * `toContain()` est PROSCRIT (variadique sur les needles, donc
 * `->not->toContain('a', 'message')` passe toujours) : on passe par
 * str_contains() + toBeFalse($message).
 */

/**
 * Position d'une aiguille dans le HTML rendu, ou échec nommant l'aiguille.
 *
 * Renvoyer `false` silencieusement ferait passer toute comparaison d'ordre par
 * vacuité : `false < 12` est vrai en PHP. Une région absente doit rougir en
 * disant laquelle, pas décaler l'assertion suivante.
 */
$positionOf = static function (string $html, string $needle, string $what): int {
    $position = mb_strpos($html, $needle);

    expect($position)
        ->not->toBeFalse("{$what} : aucune occurrence de [{$needle}] dans le document rendu.");

    return is_int($position) ? $position : -1;
};

/**
 * Supprime les commentaires Blade et HTML : un fichier a le droit d'écrire ce
 * qu'il s'interdit de faire.
 */
$stripComments = static function (string $source): string {
    return (string) preg_replace(['#\{\{--.*?--\}\}#s', '#<!--.*?-->#s'], '', $source);
};

/**
 * Repère toute EXPRESSION JavaScript dans un template Blade (AC8).
 *
 * Trois familles, et chacune existe pour une raison distincte :
 *
 *  1. `<script>` — du JS inline pur, que `script-src 'self'` bloquerait.
 *  2. Les attributs GESTIONNAIRES (`x-on:`, `@click`, `onclick`) — ils portent
 *     une instruction par nature. Le bouton de fermeture doit être câblé en JS
 *     bundlé, pas ici.
 *  3. Les attributs Alpine restants dont la valeur n'est PAS une référence nue.
 *     `x-show="open"` est un simple accès de propriété et reste autorisé ;
 *     `x-show="open && !dismissed"` est une expression que seule une build
 *     d'Alpine avec `new Function` sait évaluer — donc `'unsafe-eval'`.
 *
 * ⚠️ LES DEUX STYLES DE GUILLEMETS, et ce n'est pas de la coquetterie.
 * Rédaction d'origine : `="[^"]*"`, qui ne voyait que les guillemets DOUBLES.
 * `@click='close()'` passait donc VERT — du HTML parfaitement valide, et le seul
 * garde-fou de l'AC8 ne l'aurait pas vu. Pire : l'auto-contrôle du scanner
 * n'exerçait lui aussi que des guillemets doubles, donc l'angle mort était
 * invisible DE L'INTÉRIEUR. Troisième occurrence du même motif dans cette story,
 * après les deux que la campagne de mutation avait trouvées. Trouvé en revue de
 * code le 2026-08-08. Le quotage est désormais capturé puis référencé (`\2`).
 *
 * @return list<string>
 */
$findJavaScriptExpressions = static function (string $source) use ($stripComments): array {
    $stripped = $stripComments($source);

    $found = [];

    if (preg_match('/<script\b/i', $stripped) === 1) {
        $found[] = '<script>';
    }

    // Gestionnaires d'évènement, quelle que soit leur syntaxe.
    preg_match_all('/(?:^|\s)(x-on:[\w.\-]+|@[a-z]+(?:\.[\w\-]+)*|on[a-z]+)=(["\']).*?\2/is', $stripped, $handlers);
    foreach ($handlers[1] as $handler) {
        $found[] = $handler;
    }

    // Directives Alpine « à instruction », qui ne prennent jamais de référence nue.
    preg_match_all('/(?:^|\s)(x-init|x-effect|x-modelable)=(["\']).*?\2/is', $stripped, $statements);
    foreach ($statements[1] as $statement) {
        $found[] = $statement;
    }

    // Toute autre directive Alpine : la valeur doit être une référence nue.
    preg_match_all('/(?:^|\s)(x-[\w:.\-]+)=(["\'])(.*?)\2/is', $stripped, $directives, PREG_SET_ORDER);
    foreach ($directives as $directive) {
        $value = trim($directive[3]);

        if ($value !== '' && preg_match('/^[A-Za-z_$][\w$]*$/', $value) !== 1) {
            $found[] = "{$directive[1]}=\"{$value}\"";
        }
    }

    return $found;
};

/*
|--------------------------------------------------------------------------
| AC8 — Alpine sans expression inline (préparation CSP, sans allumer la CSP)
|--------------------------------------------------------------------------
*/

it('détecte une expression JS, et seulement elle (auto-contrôle du scanner AC8)', function () use ($findJavaScriptExpressions): void {
    /*
     * Leçon de la Story 1.8 : un scanner qui parcourt des fichiers peut être
     * vert par vacuité. On l'exerce donc d'abord sur des fixtures synthétiques
     * avant de le lâcher sur le vrai fichier.
     */
    expect($findJavaScriptExpressions('<div x-data="{ open: true }"></div>'))
        ->not->toBeEmpty('Un objet littéral en x-data n\'est pas détecté.');
    expect($findJavaScriptExpressions('<button @click="open = false"></button>'))
        ->not->toBeEmpty('Un @click inline n\'est pas détecté.');
    expect($findJavaScriptExpressions('<button x-on:click="close()"></button>'))
        ->not->toBeEmpty('Un x-on: inline n\'est pas détecté.');
    expect($findJavaScriptExpressions('<div x-init="setTimeout(() => 1, 5)"></div>'))
        ->not->toBeEmpty('Un x-init n\'est pas détecté.');
    expect($findJavaScriptExpressions('<div x-show="open && !dismissed"></div>'))
        ->not->toBeEmpty('Une expression composée en x-show n\'est pas détectée.');
    expect($findJavaScriptExpressions('<script>window.foo = 1;</script>'))
        ->not->toBeEmpty('Un <script> inline n\'est pas détecté.');
    expect($findJavaScriptExpressions('<button onclick="close()"></button>'))
        ->not->toBeEmpty('Un onclick natif n\'est pas détecté.');

    /*
     * ⚠️ LES MÊMES, EN GUILLEMETS SIMPLES — ajouté par la revue de code du
     * 2026-08-08. C'est du HTML parfaitement valide, et le motif d'origine
     * (`="[^"]*"`) n'en voyait aucun. L'auto-contrôle ci-dessus n'exerçait lui
     * non plus que des guillemets doubles : le scanner et son propre contrôle
     * partageaient l'angle mort, donc aucun des deux ne pouvait le révéler.
     * C'est la forme la plus coûteuse du garde-fou silencieux — celle où le
     * garde-fou du garde-fou est complice.
     */
    expect($findJavaScriptExpressions("<button @click='open = false'></button>"))
        ->not->toBeEmpty('Un @click en guillemets simples n\'est pas détecté.');
    expect($findJavaScriptExpressions("<button x-on:click='close()'></button>"))
        ->not->toBeEmpty('Un x-on: en guillemets simples n\'est pas détecté.');
    expect($findJavaScriptExpressions("<div x-init='setTimeout(() => 1, 5)'></div>"))
        ->not->toBeEmpty('Un x-init en guillemets simples n\'est pas détecté.');
    expect($findJavaScriptExpressions("<div x-show='open && !dismissed'></div>"))
        ->not->toBeEmpty('Une expression composée en x-show, en guillemets simples, n\'est pas détectée.');
    expect($findJavaScriptExpressions("<button onclick='close()'></button>"))
        ->not->toBeEmpty('Un onclick en guillemets simples n\'est pas détecté.');

    // Faux positifs à ne pas produire : les références nues, et le PHP alentour.
    expect($findJavaScriptExpressions('<div x-data="toast" x-show="open" x-cloak></div>'))
        ->toBeEmpty('Les références nues sont pourtant ce que l\'AC8 autorise.');
    expect($findJavaScriptExpressions("<div x-data='toast' x-show='open'></div>"))
        ->toBeEmpty('Les références nues restent autorisées, y compris en guillemets simples.');
    expect($findJavaScriptExpressions('<div class="flex" data-toast-duration="5000">{{ $slot }}</div>'))
        ->toBeEmpty('Le HTML et le Blade ordinaires ne sont pas du JavaScript.');
});

it('ne laisse AUCUNE expression JS dans toast.blade.php (AC8)', function () use ($findJavaScriptExpressions): void {
    /*
     * Ce test REMPLACE le dos-d'âne daté de la Story 1.11
     * (« ne livre AUCUN comportement d'auto-fermeture »), dont le commentaire
     * annonçait lui-même ce rendez-vous.
     *
     * Il n'interdit plus le comportement : il interdit qu'il soit écrit INLINE.
     * La différence est tout l'objet de l'AC8 — la CSP n'est pas allumée
     * aujourd'hui (CSP_ENABLED=false), et le jour où elle le sera, ce fichier
     * n'aura rien à réécrire.
     *
     * Vu rouge : en remplaçant `x-show="open"` par `x-show="open === true"`,
     * puis en câblant le bouton avec `@click="close()"`.
     */
    $expressions = $findJavaScriptExpressions(
        (string) file_get_contents(base_path('resources/views/components/toast.blade.php')),
    );

    expect($expressions)
        ->toBeEmpty('toast.blade.php contient des expressions JS : ' . implode(' / ', $expressions)
            . ' — elles exigeraient \'unsafe-eval\' ou \'unsafe-inline\'. La logique appartient à resources/js/app.js.');
});

it('câble bien le comportement du toast, plutôt que de simplement l\'interdire (AC8)', function () use ($stripComments): void {
    /*
     * ⚠️ Anti-vacuité, et ce n'est pas décoratif : le test précédent serait
     * PARFAITEMENT VERT sur un toast qui n'a aucun comportement du tout — c'est
     * l'état exact de la Story 1.11. Sans ce contrôle, supprimer `x-data` et
     * `Alpine.data('toast')` ne ferait rougir aucun test de rendu.
     *
     * ⚠️ `$stripComments` N'EST PAS COSMÉTIQUE. Première version sans lui : la
     * campagne de mutation a retiré `x-data="toast"` et `x-show="open"` du
     * markup, et ce test est resté VERT — parce que l'en-tête Blade du composant
     * CITE ces deux attributs pour les expliquer. Le garde-fou lisait la
     * documentation du fichier au lieu de son comportement : « l'affirmation
     * précède son référent », en miniature, dans le test censé l'empêcher.
     */
    $template = $stripComments(
        (string) file_get_contents(base_path('resources/views/components/toast.blade.php')),
    );

    expect(preg_match('/\sx-data="toast"/', $template))
        ->toBe(1, 'toast.blade.php ne référence plus la fabrique Alpine : le scan AC8 serait vert sur un composant inerte.');

    expect(preg_match('/\sx-show="open"/', $template))
        ->toBe(1, 'toast.blade.php n\'expose plus son état de visibilité à Alpine.');

    $script = (string) file_get_contents(base_path('resources/js/app.js'));

    expect(str_contains($script, "Alpine.data('toast'"))
        ->toBeTrue('resources/js/app.js n\'enregistre aucune fabrique Alpine nommée `toast` : x-data="toast" ne résoudrait rien.');

    expect(str_contains($script, 'dataset.toastDuration'))
        ->toBeTrue('La durée n\'est pas lue depuis le DOM : elle serait écrite en dur dans le JS, seconde source de vérité.');

    /*
     * ⚠️ L'APPEL, pas la chaîne. `str_contains($script, '[data-toast-dismiss]')`
     * restait vert quand la campagne de mutation remplaçait le sélecteur par
     * `querySelector('button')` — parce que le message d'erreur fail-loud du
     * même fichier cite le sélecteur. Deuxième occurrence du même piège dans ce
     * fichier de tests : chercher une chaîne dans du code, c'est aussi la
     * chercher dans ce que ce code raconte sur lui-même.
     */
    expect(str_contains($script, "querySelector('[data-toast-dismiss]')"))
        ->toBeTrue('Le bouton de fermeture n\'est câblé sur aucun [data-toast-dismiss].');
});

/*
|--------------------------------------------------------------------------
| AC1 — <x-layouts.public>, squelette de document
|--------------------------------------------------------------------------
*/

it('fait descendre <html lang> de config(app.locale), sans le graver dans le gabarit (AC1)', function (): void {
    /*
     * Le référent a été vérifié le 2026-08-09 : `config('app.locale')` valait
     * `en`, donc un `lang="fr"` gravé dans le gabarit aurait créé une SECONDE
     * source de vérité — verte ici, et fausse partout où le locale gouverne
     * réellement quelque chose (Carbon::setLocale en Story 1.12).
     *
     * La première assertion seule ne distinguerait pas les deux cas : un `fr`
     * en dur la passerait. C'est la MUTATION du locale qui les sépare.
     */
    $default = Blade::render('<x-layouts.public>Contenu</x-layouts.public>');

    expect(str_contains($default, '<html lang="fr">'))
        ->toBeTrue('Le document ne rend pas lang="fr" : APP_LOCALE n\'est pas positionné à `fr` (.env et .env.example).');

    // On restaure le locale RÉELLEMENT actif, et non `config('app.locale')` :
    // la configuration n'est pas nécessairement ce que l'application porte à
    // l'instant du test, et le fuir laisserait la suite en `de_DE`.
    $originalLocale = app()
        ->getLocale();

    app()
        ->setLocale('de_DE');

    try {
        $mutated = Blade::render('<x-layouts.public>Contenu</x-layouts.public>');
    } finally {
        app()->setLocale($originalLocale);
    }

    expect(str_contains($mutated, '<html lang="de-DE">'))
        ->toBeTrue('lang n\'a pas bougé alors que le locale a changé : il est gravé dans le gabarit, il ne descend pas de la configuration.');
});

it('rend un <head> complet, et un <title> alimenté par une prop (AC1)', function (): void {
    $html = Blade::render('<x-layouts.public title="Ma page">Contenu</x-layouts.public>');

    expect(str_contains($html, '<!DOCTYPE html>'))
        ->toBeTrue('Le document ne déclare pas de doctype : le navigateur bascule en quirks mode.');

    expect(str_contains($html, '<meta charset="utf-8">'))
        ->toBeTrue('charset absent du <head>.');

    expect(str_contains($html, 'name="viewport"'))
        ->toBeTrue('viewport absent du <head> : le rendu mobile serait mis à l\'échelle de force.');

    expect(str_contains($html, '<title>Ma page</title>'))
        ->toBeTrue('La prop title n\'alimente pas le <title>.');

    // Sans nom de page, le titre retombe sur celui de l'application plutôt que
    // sur un <title> vide — qu'aucun lecteur d'écran ne sait annoncer.
    $withoutTitle = Blade::render('<x-layouts.public>Contenu</x-layouts.public>');

    expect(str_contains($withoutTitle, '<title>' . config()->string('app.name') . '</title>'))
        ->toBeTrue('Sans prop title, le <title> devrait retomber sur le nom de l\'application.');
});

it('charge la CSS et le JS applicatifs par @vite (AC1)', function (): void {
    $html = Blade::render('<x-layouts.public>Contenu</x-layouts.public>');

    /*
     * On ne cherche PAS la chaîne `@vite` : elle prouverait qu'une directive est
     * écrite, pas qu'elle produit quelque chose. On cherche les balises émises,
     * qui portent le hash du manifeste — donc un build réel.
     */
    expect(preg_match('/<link[^>]+rel="stylesheet"[^>]+href="[^"]*\/build\/assets\/app-[^"]+\.css"/', $html))
        ->toBe(1, 'Aucune feuille de style issue du manifeste Vite dans le <head>.');

    expect(preg_match('/<script[^>]+src="[^"]*\/build\/assets\/app-[^"]+\.js"/', $html))
        ->toBe(1, 'Aucun script applicatif issu du manifeste Vite : Alpine.data(\'toast\') ne serait jamais enregistré.');
});

it('rend les régions du <body> dans l\'ordre annoncé (AC1)', function () use ($positionOf): void {
    $html = Blade::render('<x-layouts.public>Corps de la page</x-layouts.public>');

    /*
     * Aiguille => nom lisible. La comparaison se fait DEUX À DEUX plutôt qu'en
     * une seule assertion : un ordre faux doit nommer les deux régions qui se
     * sont croisées, pas se contenter d'un « faux ».
     */
    $regions = [
        'href="#main"' => 'le lien skip-to-content',
        '<header' => 'le <header>',
        '<main id="main"' => 'le <main id="main">',
        'Corps de la page' => 'le slot par défaut',
        '</main>' => 'la fermeture du <main>',
        '<footer' => 'le <footer>',
        'livewire.js' => 'les scripts Livewire',
    ];

    $previousPosition = -1;
    $previousLabel = 'le début du document';

    foreach ($regions as $needle => $label) {
        $position = $positionOf($html, $needle, $label);

        expect($position)
            ->toBeGreaterThan($previousPosition, "L'ordre du <body> est faux : {$label} devrait suivre {$previousLabel}.");

        $previousPosition = $position;
        $previousLabel = $label;
    }
});

it('fait pointer le lien de saut vers une cible qui existe réellement (AC1)', function (): void {
    /*
     * Un href="#main" sans élément #main est un lien de saut qui ne saute nulle
     * part : l'attribut est là, l'affordance n'existe pas. On vérifie donc la
     * CIBLE, et on la vérifie unique — deux id identiques et le navigateur
     * choisit le premier, qui n'est pas forcément le contenu.
     */
    $html = Blade::render('<x-layouts.public>Contenu</x-layouts.public>');

    expect(preg_match_all('/\sid="main"/', $html))
        ->toBe(1, 'La cible #main du lien de saut est absente, ou présente plusieurs fois.');

    expect(preg_match('/<main[^>]+id="main"/', $html))
        ->toBe(1, 'L\'id="main" n\'est pas porté par le <main> : le saut n\'atteindrait pas le contenu.');
});

/*
|--------------------------------------------------------------------------
| AC2 — <x-layouts.minimal>
|--------------------------------------------------------------------------
*/

it('rend un document minimal : slot dans <main>, et rien autour (AC2)', function (): void {
    $html = Blade::render('<x-layouts.minimal title="Erreur">Corps minimal</x-layouts.minimal>');

    expect(str_contains($html, '<html lang="fr">'))
        ->toBeTrue('Le layout minimal ne rend pas lang="fr".');

    expect(str_contains($html, '<title>Erreur</title>'))
        ->toBeTrue('Le layout minimal n\'expose pas de <title>.');

    expect(preg_match('/<main[^>]*>\s*Corps minimal/', $html))
        ->toBe(1, 'Le layout minimal ne rend pas son slot dans un <main>.');
});

it('ne rend NI header NI footer dans le layout minimal (AC2)', function (): void {
    /*
     * Assertion d'ABSENCE, vue rouge en ajoutant un <header> puis un <footer>
     * au gabarit minimal. Sans elle, `minimal` pourrait dériver vers une copie
     * de `public` sans que rien ne le signale — et « minimal » ne voudrait plus
     * rien dire.
     */
    $html = Blade::render('<x-layouts.minimal>Corps minimal</x-layouts.minimal>');

    expect(str_contains($html, '<header'))
        ->toBeFalse('<x-layouts.minimal> rend un <header> : ce n\'est plus un layout minimal.');

    expect(str_contains($html, '<footer'))
        ->toBeFalse('<x-layouts.minimal> rend un <footer> : ce n\'est plus un layout minimal.');

    // Anti-vacuité : les deux assertions ci-dessus seraient vertes sur une
    // chaîne vide. Le document doit bien avoir été rendu.
    expect(str_contains($html, 'Corps minimal'))
        ->toBeTrue('Le layout minimal n\'a rien rendu du tout : les absences ci-dessus ne prouvent rien.');
});

/*
|--------------------------------------------------------------------------
| AC7 — points d'insertion, et rien de plus
|--------------------------------------------------------------------------
*/

it('reçoit dans le <head>, AVANT @vite, ce qu\'une vue pousse sur la pile head (AC7)', function () use ($positionOf): void {
    /*
     * C'est le point d'insertion que la Story 1.9 renseignera avec les
     * <link rel="preload"> de police. On le vérifie en POUSSANT du contenu et en
     * le retrouvant à la bonne place — chercher `@stack('head')` dans le fichier
     * source prouverait qu'une directive est écrite, pas qu'elle reçoit.
     *
     * « Avant @vite » n'est pas cosmétique : un preload déclaré après le script
     * qui déclenche le chargement arrive trop tard pour servir à quoi que ce soit.
     */
    $html = Blade::render(<<<'BLADE'
        @push('head')
            <meta name="marqueur-pile-head" content="1">
        @endpush
        <x-layouts.public>Contenu</x-layouts.public>
        BLADE);

    $marker = $positionOf($html, 'marqueur-pile-head', 'la pile head');
    $headEnd = $positionOf($html, '</head>', 'la fermeture du <head>');
    $vite = $positionOf($html, '/build/assets/app-', 'les assets Vite');

    expect($marker)
        ->toBeLessThan($headEnd, 'Le contenu poussé sur la pile head sort du <head>.');

    expect($marker)
        ->toBeLessThan($vite, 'La pile head est rendue APRÈS @vite : un <link rel="preload"> y arriverait trop tard.');
});

it('reçoit en fin de <body> ce qu\'une vue pousse sur la pile body-end (AC7)', function () use ($positionOf): void {
    /*
     * Emplacement du bandeau de consentement, rempli en Epic 4. Il est vide
     * aujourd'hui, et c'est le point : un bandeau factice serait un échafaudage
     * plus permissif que la production (ADR-0011).
     */
    $html = Blade::render(<<<'BLADE'
        @push('body-end')
            <div data-role="marqueur-pile-body"></div>
        @endpush
        <x-layouts.public>Contenu</x-layouts.public>
        BLADE);

    $marker = $positionOf($html, 'marqueur-pile-body', 'la pile body-end');
    $footer = $positionOf($html, '<footer', 'le <footer>');
    $bodyEnd = $positionOf($html, '</body>', 'la fermeture du <body>');

    expect($marker)
        ->toBeGreaterThan($footer, 'La pile body-end est rendue avant le <footer>.');

    expect($marker)
        ->toBeLessThan($bodyEnd, 'Le contenu poussé sur la pile body-end sort du <body>.');
});

it('n\'écrit ni preload de police ni bandeau de consentement (AC7)', function (): void {
    /*
     * Les deux noms que la definition-of-ready a requalifiés en points
     * d'insertion. Les rendre ici — même en factice — livrerait un échafaudage
     * PLUS PERMISSIF que la production : la Story 1.9 et l'Epic 4 se
     * valideraient alors contre du décor.
     */
    $html = Blade::render('<x-layouts.public>Contenu</x-layouts.public>');

    /*
     * ⚠️ Première rédaction : `str_contains($html, 'rel="preload"')`. Elle
     * rougissait — mais pas pour la raison visée : Laravel Vite émet SES PROPRES
     * `<link rel="preload" as="style">` pour les chunks du manifeste. Une
     * assertion qui ne distingue pas le preload de Vite du preload de police
     * n'aurait laissé que deux issues le jour de la Story 1.9 : la désarmer, ou
     * la croire. On vise donc ce qui appartient réellement à la 1.9 — la police.
     */
    expect(str_contains($html, 'as="font"'))
        ->toBeFalse('Le layout précharge une police : les <link rel="preload"> de police appartiennent à la Story 1.9.');

    expect(str_contains($html, '.woff'))
        ->toBeFalse('Le layout référence un fichier de police : le self-hosting IBM Plex appartient à la Story 1.9.');

    expect(mb_stripos($html, 'consent') !== false || mb_stripos($html, 'cookie') !== false)
        ->toBeFalse('Le layout rend un bandeau de consentement factice : il appartient à l\'Epic 4.');
});

/*
|--------------------------------------------------------------------------
| T7 — les pages de démonstration ne doivent pas exister en production
|--------------------------------------------------------------------------
*/

it('répond 200 sur les deux pages de démonstration des layouts (T7)', function (): void {
    /*
     * Ces pages passent par le groupe `web`, donc par SetCurrentStreamer, qui
     * fait un firstOrFail(). Sans streamer semé, elles répondent 404 — et les
     * tests navigateur rougiraient pour une raison étrangère aux layouts.
     */
    App\Core\Models\Streamer::factory()->create();

    foreach (['layouts.demo', 'layouts.demo.minimal'] as $name) {
        $response = app(Kernel::class)->handle(Request::create(route($name)));

        expect($response->getStatusCode())
            ->toBe(200, "La page de démonstration [{$name}] ne répond pas 200.");
    }
});

it('n\'enregistre les pages de démonstration des layouts qu\'en local et testing (T7)', function (): void {
    /*
     * Même double garde que `/_components` (Story 1.11), et pour les mêmes
     * raisons : la garde à l'enregistrement est vérifiée ici, celle à la requête
     * (`abort_unless`) est ce qui survit à `php artisan route:cache` — un cache
     * construit en local puis déployé embarquerait sinon la route sans qu'aucun
     * test ne puisse le voir.
     *
     * Vu rouge : en retirant le `if (app()->environment([...]))` de
     * routes/web.php.
     */
    $names = ['layouts.demo', 'layouts.demo.minimal'];

    foreach (['local', 'testing'] as $environment) {
        foreach ($names as $name) {
            expect(RouteTable::registeredIn($environment)->getByName($name))
                ->not->toBeNull("La page [{$name}] devrait être disponible en [{$environment}].");
        }
    }

    $production = RouteTable::registeredIn('production');

    // Anti-vacuité : si le fichier de routes n'avait pas été rejoué du tout, les
    // routes de démo seraient absentes pour une mauvaise raison et ce test
    // serait vert sans rien prouver.
    expect(count($production->getRoutes()))
        ->toBeGreaterThan(0, 'routes/web.php n\'a pas été rejoué : le test ne prouve rien.');

    foreach ($names as $name) {
        expect($production->getByName($name))
            ->toBeNull("La page [{$name}] est exposée en production : surface inutile, non gardée.");
    }
});

it('refuse la page de démonstration à la requête, même si la route existe (T7)', function (): void {
    /*
     * Le second verrou, celui qui survit à `route:cache`. Le test précédent
     * prouve que la route n'est pas ENREGISTRÉE hors local/testing ; celui-ci
     * prouve que même enregistrée, elle REFUSE de servir. Sans lui, retirer
     * l'`abort_unless` ne ferait rougir personne — c'est exactement la forme
     * « l'affirmation précède son référent ».
     *
     * Vu rouge : en retirant l'abort_unless() des deux routes de layouts.
     */
    App\Core\Models\Streamer::factory()->create();

    $previous = app()
        ->environment();
    $previousEnvironment = is_string($previous) ? $previous : 'testing';

    app()
        ->detectEnvironment(static fn (): string => 'production');

    try {
        foreach (['/_layouts', '/_layouts-minimal'] as $path) {
            $response = app(Kernel::class)->handle(Request::create($path));

            expect($response->getStatusCode())
                ->toBe(404, "[{$path}] a servi une page de démonstration en production.");
        }
    } finally {
        app()->detectEnvironment(static fn (): string => $previousEnvironment);
    }
});
