<?php

declare(strict_types=1);

use Carbon\Carbon;
use Carbon\CarbonInterface;
use Carbon\Laravel\ServiceProvider as CarbonServiceProvider;
use Illuminate\Contracts\Http\Kernel;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Blade;
use Tests\Fixtures\RelativeTimeCases;
use Tests\Support\RouteTable;

uses(RefreshDatabase::class);

/**
 * Story 1.12 — les 4 composants <x-time-*>, côté serveur.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * CE QUE CE FICHIER NE FAIT PAS
 *
 * Il ne prétend vérifier NI le rafraîchissement Alpine, NI la famille de police
 * réellement appliquée, NI la largeur réservée. Aucune de ces trois choses
 * n'existe dans une chaîne de HTML : `font-mono` prouve seulement que quelqu'un
 * a tapé ces caractères. Elles vivent dans tests/Browser/TimeAsTextureTest.php,
 * mesurées par valeur calculée.
 *
 * Ce qui se vérifie ici est ce qui se lit dans le rendu : le balisage, les
 * libellés produits par Carbon, les seuils, les gardes fail-loud, et les
 * absences.
 *
 * `toContain()` est PROSCRIT (variadique sur les needles, donc
 * `->not->toContain('a', 'message')` passe toujours) : on passe par
 * str_contains() + toBeFalse($message).
 */

/**
 * Le contenu textuel du premier `<time>` du rendu, ou échec qui le nomme.
 */
$timeText = static function (string $html, string $what): string {
    $matched = preg_match('/<time\b[^>]*>(.*?)<\/time>/s', $html, $matches);

    expect($matched)
        ->toBe(1, "{$what} : aucun <time> dans le rendu.");

    return trim($matches[1] ?? '');
};

/**
 * La valeur d'un attribut du rendu, ou échec qui le nomme.
 */
$attributeOf = static function (string $html, string $name, string $what): string {
    $matched = preg_match('/\s' . preg_quote($name, '/') . '="([^"]*)"/', $html, $matches);

    expect($matched)
        ->toBe(1, "{$what} : l'attribut [{$name}] est absent du rendu.");

    return $matches[1] ?? '';
};

/**
 * Assère qu'un rendu Blade échoue, et échoue POUR LA BONNE RAISON.
 *
 * ⚠️ Blade emballe toute exception de rendu dans une `ViewException`. Asserter
 * sur elle suffirait à faire passer le test pour n'importe quelle erreur — y
 * compris une faute de frappe dans le template, c'est-à-dire un test vert sur
 * une garde qui n'existe plus. On parcourt donc TOUTE la chaîne des causes.
 *
 * ⚠️ Et on ne s'arrête pas à la cause RACINE, contrairement au patron de
 * BladeComponentsTest : les gardes de cette story CHAÎNENT la vraie cause (une
 * `DateMalformedStringException` de PHP), donc la racine n'est justement plus la
 * garde. On cherche la garde elle-même, et on exige que son message NOMME le
 * composant — sans quoi une InvalidArgumentException venue d'ailleurs suffirait.
 *
 * @param  callable(): mixed  $render
 */
$expectRejected = static function (callable $render, string $component, string $what): void {
    $guard = null;
    $raised = false;

    try {
        $render();
    } catch (Throwable $caught) {
        $raised = true;

        for ($link = $caught; $link instanceof Throwable; $link = $link->getPrevious()) {
            if ($link instanceof InvalidArgumentException) {
                $guard = $link;

                break;
            }
        }
    }

    expect($raised)
        ->toBeTrue("{$what} : le rendu a réussi — la garde de {$component} n'existe pas ou ne s'applique pas.");

    expect($guard)
        ->not->toBeNull("{$what} : le rendu a échoué, mais aucune InvalidArgumentException dans la chaîne — l'échec vient d'ailleurs.");

    expect(str_contains($guard instanceof Throwable ? $guard->getMessage() : '', $component))
        ->toBeTrue("{$what} : le message d'erreur ne nomme pas {$component}, il désignerait le mauvais coupable.");
};

/**
 * Fige l'horloge, exécute, restaure — même en cas d'échec.
 *
 * ⚠️ `now()` dans un composant rend les tests non déterministes : entre le rendu
 * et l'assertion, une seconde peut passer et « il y a 59 secondes » devient
 * « il y a 1 minute ». Le test rougirait une fois sur mille, donc finirait
 * désarmé.
 *
 * @param  callable(): void  $work
 */
$atFrozenTime = static function (string $instant, callable $work): void {
    Carbon::setTestNow(Carbon::parse($instant));

    try {
        $work();
    } finally {
        Carbon::setTestNow();
    }
};

/*
|--------------------------------------------------------------------------
| AC1 — Carbon parle français, et il l'apprend de la configuration
|--------------------------------------------------------------------------
*/

it('fait descendre la locale de Carbon de config(app.locale), sans la graver (AC1)', function (): void {
    /*
     * ─────────────────────────────────────────────────────────────────────────
     * L'AC1 SE TROMPAIT DE RÉFÉRENT, ET LA CAMPAGNE DE MUTATION L'A MONTRÉ.
     *
     * L'AC exigeait un `Carbon::setLocale(config('app.locale'))` dans
     * AppServiceProvider::boot(), sur la foi d'un `grep LocaleUpdated` restreint
     * à `vendor/laravel/framework/`. Retirer cette ligne n'a fait rougir AUCUN
     * test : la propriété était DÉJÀ vraie.
     *
     * Backtrace du 2026-08-08 — c'est Carbon lui-même qui la garantit, via son
     * propre provider Laravel, auto-découvert par Composer :
     *
     *   vendor/nesbot/carbon/src/Carbon/Laravel/ServiceProvider.php:54-70
     *     boot()  → updateLocale() depuis app('translator')
     *     puis    → listen(LocaleUpdated) → updateLocale()
     *
     * La ligne du provider a donc été RETIRÉE : elle aurait été une seconde
     * source de vérité, et plus faible que la première (posée une fois au boot,
     * elle ne suivrait pas un `app()->setLocale()` à chaud).
     *
     * Ce test-ci, lui, reste — c'est lui qui manquait. Son référent n'est pas
     * une de NOS lignes, c'est une intégration de dépendance : elle peut
     * disparaître à une montée de version, à un `dont-discover`, à un
     * `config:cache` construit ailleurs. Le jour où elle disparaît,
     * `diffForHumans()` rend « 3 hours ago » — en anglais, sans erreur, sans
     * warning, et sans rien d'autre pour le signaler que ce test.
     *
     * Vu rouge : en ajoutant `nesbot/carbon` à `extra.laravel.dont-discover`
     * dans composer.json.
     */
    expect(Carbon::getLocale())
        ->toBe(config()->string('app.locale'), 'La locale de Carbon ne suit pas config(app.locale).');

    /*
     * On NOMME le mécanisme, pour que sa disparition n'apparaisse pas comme un
     * mystérieux « attendu fr, obtenu en » à trois stories d'ici.
     */
    expect(array_key_exists(CarbonServiceProvider::class, app()->getLoadedProviders()))
        ->toBeTrue('Le provider Laravel de Carbon n\'est plus chargé : c\'est LUI qui aligne la locale de Carbon sur celle de l\'application, et rien d\'autre ne le fait.');
});

it('suit un changement de locale à chaud, et pas seulement celui du boot (AC1)', function (): void {
    /*
     * La moitié que notre ligne retirée n'aurait PAS su tenir : un
     * `app()->setLocale()` en cours de requête. C'est le listener sur
     * `LocaleUpdated` qui l'assure — donc c'est aussi ce qui distingue le vrai
     * mécanisme de celui que l'AC proposait.
     *
     * ⚠️ La locale de Carbon est un ÉTAT STATIQUE GLOBAL, pas un service
     * conteneurisé : un test qui la change contamine tous les suivants. On
     * restaure dans un `finally`, patron déjà employé par LayoutsTest.
     */
    $originalLocale = app()
        ->getLocale();

    try {
        app()->setLocale('en');

        expect(Carbon::getLocale())
            ->toBe('en', 'Carbon n\'a pas suivi le changement de locale à chaud.');
    } finally {
        app()->setLocale($originalLocale);
    }

    expect(Carbon::getLocale())
        ->toBe($originalLocale, 'La locale de Carbon n\'a pas été restaurée : les tests suivants seraient contaminés.');
});

it('rend réellement du français, et pas seulement une locale déclarée (AC1)', function (): void {
    /*
     * `getLocale()` seul ne prouve rien : il renvoie ce qu'on lui a posé, même
     * si le fichier de langue n'a jamais été chargé. Il faut donc regarder une
     * chaîne PRODUITE.
     */
    $rendered = Carbon::now()
        ->subHours(3)
        ->diffForHumans();

    expect(str_contains($rendered, 'il y a'))
        ->toBeTrue("Carbon rend [{$rendered}] : la locale est déclarée, mais le fichier de langue français n'est pas chargé.");
});

/*
|--------------------------------------------------------------------------
| AC2 — <x-time-relative>
|--------------------------------------------------------------------------
*/

it('porte l\'instant en ISO-8601 dans l\'attribut datetime (AC2)', function () use ($attributeOf): void {
    /*
     * L'assertion compare l'attribut à `$instant->toIso8601String()`, JAMAIS à
     * une date écrite dans le test : un littéral daté serait hérité du jour de
     * rédaction et ne matcherait jamais `now()->subHours(3)`. L'AC porte sur la
     * FORME, pas sur une valeur.
     */
    $instant = Carbon::now()->subHours(3);

    $html = Blade::render('<x-time-relative :datetime="$instant" />', [
        'instant' => $instant,
    ]);

    expect($attributeOf($html, 'datetime', '<x-time-relative>'))
        ->toBe($instant->toIso8601String(), 'L\'attribut datetime ne porte pas l\'instant passé en prop, en ISO-8601.');
});

it('rend la durée relative en français, en forme longue par défaut (AC2)', function () use ($timeText): void {
    $html = Blade::render('<x-time-relative :datetime="$instant" />', [
        'instant' => Carbon::now()->subHours(3),
    ]);

    expect($timeText($html, '<x-time-relative>'))
        ->toBe('il y a 3 heures', 'La forme longue française n\'est pas le défaut.');
});

it('bascule sur la forme courte de Carbon avec la prop short (AC2)', function () use ($timeText): void {
    /*
     * La forme courte n'est pas un supplément d'âme : c'est celle des écrans de
     * référence (`02-home-offline.html:85` — « Dernier stream il y a 14 h »).
     * Sans cette prop, ces écrans seraient irréalisables — ou seraient réalisés
     * À CÔTÉ du composant.
     */
    $html = Blade::render('<x-time-relative :datetime="$instant" short />', [
        'instant' => Carbon::now()->subHours(3),
    ]);

    expect($timeText($html, '<x-time-relative short>'))
        ->toBe('il y a 3 h', 'La prop short ne bascule pas sur la forme courte de Carbon.');
});

it('ne préfixe RIEN : la phrase appartient à l\'écran (AC2)', function () use ($timeText): void {
    /*
     * Assertion d'ABSENCE. « Dernier stream », « En direct depuis » sont du
     * contexte d'écran — vérifié sur les écrans de référence, où le même
     * composant est précédé de deux libellés DIFFÉRENTS.
     */
    $html = Blade::render('<x-time-relative :datetime="$instant" />', [
        'instant' => Carbon::now()->subHours(3),
    ]);

    $text = $timeText($html, '<x-time-relative>');

    expect($text)
        ->toBe('il y a 3 heures', "Le composant rend [{$text}] : il ajoute un préfixe que l'écran devrait porter.");

    foreach (['Dernier', 'stream', 'Publié', 'depuis'] as $prefix) {
        expect(str_contains($text, $prefix))
            ->toBeFalse("Le composant grave le mot [{$prefix}] : il appartient à l'appelant.");
    }
});

it('refuse un datetime qui n\'est ni DateTimeInterface ni parsable (AC2)', function () use ($expectRejected): void {
    /*
     * Un repli silencieux sur `now()` afficherait « il y a 0 seconde » sur une
     * prop cassée : une valeur PLAUSIBLE, donc invisible à la relecture.
     */
    $expectRejected(
        static fn (): string => Blade::render('<x-time-relative :datetime="$instant" />', [
            'instant' => 'pas-une-date-du-tout',
        ]),
        '<x-time-relative>',
        'chaîne non parsable',
    );

    $expectRejected(
        static fn (): string => Blade::render('<x-time-relative :datetime="$instant" />', [
            'instant' => 42,
        ]),
        '<x-time-relative>',
        'entier au lieu d\'un instant',
    );

    /*
     * ⚠️ LA CHAÎNE VIDE, ET C'EST LE CAS QUI MANQUAIT (revue du 2026-08-08).
     *
     * `Carbon::parse('')` ne lève pas : il renvoie **now()**. Mesuré, pas
     * supposé. Sans la condition `trim($datetime) !== ''` du composant, une prop
     * vide — la forme que prend une variable non initialisée, un champ nul en
     * base, un accesseur qui rend '' — s'afficherait « il y a 0 seconde ». Une
     * valeur PLAUSIBLE, donc invisible à la relecture : exactement ce que
     * l'en-tête du composant dit exister pour empêcher, et que rien n'observait.
     */
    $expectRejected(
        static fn (): string => Blade::render('<x-time-relative :datetime="$instant" />', [
            'instant' => '',
        ]),
        '<x-time-relative>',
        'chaîne vide (Carbon::parse(\'\') renvoie now(), donc un repli silencieux)',
    );

    $expectRejected(
        static fn (): string => Blade::render('<x-time-relative :datetime="$instant" />', [
            'instant' => '   ',
        ]),
        '<x-time-relative>',
        'chaîne d\'espaces',
    );
});

it('fait refuser un datetime cassé par les TROIS AUTRES composants, pas seulement par le premier (AC2/AC3/AC4/AC5)', function () use ($expectRejected): void {
    /*
     * ⚠️ CINQ GARDES SUR HUIT N'ÉTAIENT EXERCÉES PAR RIEN (revue du 2026-08-08).
     *
     * `$expectRejected` n'était appelé que sur `<x-time-relative>` et
     * `<x-time-since>`. Les gardes de `<x-time-absolute>` (datetime, format),
     * `<x-time-dual>` (published, updated, format) et celle de `<x-time-since>`
     * sur son datetime pouvaient être supprimées intégralement sans qu'un seul
     * test bouge — du code défensif que rien ne défend.
     *
     * Chaque cas passe la chaîne vide OU une valeur non parsable, et exige que
     * le message NOMME le composant : sans cela, une InvalidArgumentException
     * venue d'ailleurs suffirait à faire passer le test.
     */
    $cases = [
        ['<x-time-absolute>', '<x-time-absolute :datetime="$v" />', 'pas-une-date', 'datetime non parsable'],
        ['<x-time-absolute>', '<x-time-absolute :datetime="$v" />', '', 'datetime vide'],
        ['<x-time-since>', '<x-time-since :datetime="$v" />', 'pas-une-date', 'datetime non parsable'],
        ['<x-time-since>', '<x-time-since :datetime="$v" />', '', 'datetime vide'],
        ['<x-time-dual>', '<x-time-dual :published="$v" />', 'pas-une-date', 'published non parsable'],
        ['<x-time-dual>', '<x-time-dual :published="$v" />', '', 'published vide'],
    ];

    foreach ($cases as [$component, $blade, $value, $what]) {
        $expectRejected(
            static fn (): string => Blade::render($blade, [
                'v' => $value,
            ]),
            $component,
            $what,
        );
    }

    // `updated` a sa propre branche dans $toCarbon, avec son propre nom de prop
    // dans le message : la tester séparément est ce qui distingue les deux.
    $expectRejected(
        static fn (): string => Blade::render('<x-time-dual :published="$p" :updated="$u" />', [
            'p' => Carbon::parse('2026-01-14'),
            'u' => 'pas-une-date',
        ]),
        '<x-time-dual>',
        'updated non parsable',
    );

    // Les gardes sur le gabarit de format, dans les deux composants qui en ont un.
    foreach ([
        ['<x-time-absolute>', '<x-time-absolute :datetime="$d" :format="$f" />'],
        ['<x-time-dual>', '<x-time-dual :published="$d" :format="$f" />'],
    ] as [$component, $blade]) {
        foreach (['', '   ', 42] as $badFormat) {
            $expectRejected(
                static fn (): string => Blade::render($blade, [
                    'd' => Carbon::parse('2026-01-14'),
                    'f' => $badFormat,
                ]),
                $component,
                'format vide ou non textuel',
            );
        }
    }
});

/*
|--------------------------------------------------------------------------
| AC3 — <x-time-absolute>
|--------------------------------------------------------------------------
*/

it('rend le mois en toutes lettres et EN FRANÇAIS (AC3)', function () use ($timeText): void {
    /*
     * ⚠️ JANVIER, PAS MARS. Avec mars, `d M Y` et `d F Y` rendent la même
     * chaîne et l'assertion ne distinguerait plus la forme courte de la longue.
     *
     * Vu rouge : en remplaçant `translatedFormat()` par `format()` dans le
     * composant — qui rend « 14 January 2026 », en anglais, sans erreur ni
     * warning, quelle que soit la locale.
     */
    $html = Blade::render('<x-time-absolute :datetime="$date" />', [
        'date' => Carbon::parse('2026-01-14'),
    ]);

    expect($timeText($html, '<x-time-absolute>'))
        ->toBe('14 janvier 2026', 'Le mois n\'est pas rendu en toutes lettres et en français.');
});

it('laisse surcharger le gabarit par la prop format (AC3)', function () use ($timeText): void {
    $html = Blade::render('<x-time-absolute :datetime="$date" format="d M Y" />', [
        'date' => Carbon::parse('2026-01-14'),
    ]);

    // `janv.` et non `janvier` : c'est ce qui prouve que le gabarit a bien été
    // pris en compte, et c'est aussi ce qu'un mois comme mars ne montrerait pas.
    expect($timeText($html, '<x-time-absolute format>'))
        ->toBe('14 janv. 2026', 'La prop format ne surcharge pas le gabarit par défaut.');
});

it('porte l\'instant en ISO-8601 dans l\'attribut datetime (AC3)', function () use ($attributeOf): void {
    $date = Carbon::parse('2026-01-14 09:30:00');

    $html = Blade::render('<x-time-absolute :datetime="$date" />', [
        'date' => $date,
    ]);

    expect($attributeOf($html, 'datetime', '<x-time-absolute>'))
        ->toBe($date->toIso8601String(), 'L\'attribut datetime ne porte pas l\'instant passé en prop.');
});

/*
|--------------------------------------------------------------------------
| AC4 — <x-time-dual>, le seuil des 30 jours
|--------------------------------------------------------------------------
*/

it('rend « Publié » ET « Mis à jour » au-delà de 30 jours, séparés par un point médian (AC4)', function (): void {
    $published = Carbon::parse('2026-01-14');

    $html = Blade::render('<x-time-dual :published="$published" :updated="$updated" />', [
        'published' => $published,
        'updated' => $published->copy()
            ->addDays(31),
    ]);

    expect(str_contains($html, 'Publié <time'))
        ->toBeTrue('La date de publication n\'est pas rendue.');

    expect(str_contains($html, ' · Mis à jour <time'))
        ->toBeTrue('La mise à jour n\'est pas rendue, ou pas séparée par « · ».');

    /*
     * ⚠️ ON LIT LE CONTENU DE LA SECONDE DATE, PAS SEULEMENT SA BALISE OUVRANTE.
     *
     * La rédaction d'origine s'arrêtait à `' · Mis à jour <time'`. Le TEXTE de
     * la seconde date n'était donc lu par rien : remplacer `translatedFormat()`
     * par `format()` sur cette ligne-là rendait « Mis à jour 14 February 2026 »,
     * en anglais, sans erreur et sans test rouge. MT-B ne mutait que
     * `<x-time-absolute>`. (Revue du 2026-08-08.)
     *
     * Le 14 janvier + 31 jours tombe le 14 février : « février », pas
     * « February ». Et le mois est choisi pour que les formes courte et longue
     * DIFFÈRENT (« févr. » ≠ « février »), comme l'exige l'AC3.
     */
    expect(str_contains($html, '14 février 2026'))
        ->toBeTrue('La date de mise à jour n\'est pas rendue en français : translatedFormat() a été remplacé par format() sur la seconde date, que rien ne lisait.');

    expect(str_contains($html, 'February'))
        ->toBeFalse('La seconde date est rendue en anglais.');

    // Et son attribut datetime, que $attributeOf (preg_match, PREMIÈRE
    // occurrence) ne pouvait pas voir : il ne lit jamais le second <time>.
    expect(substr_count($html, '<time datetime="'))
        ->toBe(2, 'Les DEUX dates doivent porter leur instant en ISO-8601 : le second <time> n\'était lu par aucune assertion.');
});

it('rend « Publié » SEUL en deçà de 30 jours (AC4)', function (): void {
    /*
     * Assertion d'ABSENCE, vue rouge en inversant la comparaison du composant :
     * une coquille corrigée le lendemain n'est pas une information pour le
     * lecteur.
     */
    $published = Carbon::parse('2026-01-14');

    $html = Blade::render('<x-time-dual :published="$published" :updated="$updated" />', [
        'published' => $published,
        'updated' => $published->copy()
            ->addDays(29),
    ]);

    expect(str_contains($html, 'Mis à jour'))
        ->toBeFalse('« Mis à jour » apparaît pour une mise à jour de moins de 30 jours.');

    // Anti-vacuité : l'absence ci-dessus serait verte sur un rendu vide.
    expect(str_contains($html, 'Publié'))
        ->toBeTrue('Le composant n\'a rien rendu du tout : l\'absence ci-dessus ne prouve rien.');
});

it('rend « Publié » seul EXACTEMENT sur la borne des 30 jours (AC4)', function (): void {
    /*
     * ⚠️ C'EST CE CAS-LÀ QUI DISTINGUE `>` DE `>=`, ET LUI SEUL. Les deux tests
     * précédents passent avec l'une comme avec l'autre.
     *
     * Vu rouge : en passant `greaterThan()` à `greaterThanOrEqualTo()`.
     */
    $published = Carbon::parse('2026-01-14');

    $html = Blade::render('<x-time-dual :published="$published" :updated="$updated" />', [
        'published' => $published,
        'updated' => $published->copy()
            ->addDays(30),
    ]);

    expect(str_contains($html, 'Mis à jour'))
        ->toBeFalse('À exactement +30 jours, « Mis à jour » apparaît : la comparaison n\'est pas strictement supérieure.');
});

it('n\'altère pas la date publiée en calculant le seuil (AC4, piège de mutation Carbon)', function () use ($attributeOf): void {
    /*
     * ⚠️ `addDays()` MUTE l'instance en place en Carbon 3. Sans `copy()`, le
     * calcul du seuil décalerait la date PUBLIÉE de 30 jours — et les trois
     * tests ci-dessus resteraient VERTS, puisqu'ils n'observent que la branche.
     * La page afficherait une date fausse et rien ne rougirait.
     *
     * Vu rouge : en retirant le `copy()` du composant.
     */
    $published = Carbon::parse('2026-01-14');

    $html = Blade::render('<x-time-dual :published="$published" :updated="$updated" />', [
        'published' => $published,
        'updated' => $published->copy()
            ->addDays(31),
    ]);

    expect($attributeOf($html, 'datetime', '<x-time-dual>'))
        ->toBe(Carbon::parse('2026-01-14')->toIso8601String(), 'La date publiée rendue n\'est pas celle passée en prop : le calcul du seuil l\'a mutée.');

    expect(str_contains($html, '14 janvier 2026'))
        ->toBeTrue('La date publiée affichée n\'est pas le 14 janvier 2026 : addDays() a muté l\'instance.');
});

it('rend « Publié » seul quand aucune mise à jour n\'est fournie (AC4)', function (): void {
    $html = Blade::render('<x-time-dual :published="$published" />', [
        'published' => Carbon::parse('2026-01-14'),
    ]);

    expect(str_contains($html, 'Mis à jour'))
        ->toBeFalse('« Mis à jour » apparaît alors qu\'aucune date de mise à jour n\'a été fournie.');
});

/*
|--------------------------------------------------------------------------
| AC5 — <x-time-since>, la durée et pas la phrase
|--------------------------------------------------------------------------
*/

it('rend la durée ABSOLUE, sans « il y a » et sans « depuis » (AC5)', function () use ($timeText, $atFrozenTime): void {
    /*
     * L'AC d'origine disait « rend `Streaming depuis 4 ans` ». L'écran de
     * référence press kit (story 0c, `done`) rend `<dt>En stream depuis</dt>` +
     * `<dd class="temporal">4 ans</dd>` : le préfixe est HORS du composant, et
     * ce n'est même pas le même mot. Les écrans de référence font foi.
     */
    $text = '';

    /*
     * ⚠️ LA FIXTURE N'EST PAS UN COMPTE ROND, ET C'EST LE POINT (revue du
     * 2026-08-08).
     *
     * Elle valait auparavant 2022-06-15 → 2026-06-15, soit EXACTEMENT 4 ans à la
     * seconde près : la seconde part était nulle, donc `parts: 1` et `parts: 2`
     * rendaient tous deux « 4 ans » et la valeur par défaut de la prop n'était
     * distinguée par aucun cas. Décalée à mars, elle rend « 4 ans » avec le
     * défaut et « 4 ans 3 mois » sans lui.
     */
    $atFrozenTime('2026-06-15 12:00:00', static function () use (&$text, $timeText): void {
        $text = $timeText(
            Blade::render('<x-time-since :datetime="$start" />', [
                'start' => Carbon::parse('2022-03-15 12:00:00'),
            ]),
            '<x-time-since>',
        );
    });

    expect($text)
        ->toBe('4 ans', "Le composant rend [{$text}] au lieu de la durée nue : le défaut `parts` ne vaut plus 1.");

    foreach (['il y a', 'depuis', 'Streaming'] as $forbidden) {
        expect(str_contains($text, $forbidden))
            ->toBeFalse("Le composant grave [{$forbidden}] : le préfixe appartient à l'appelant.");
    }
});

it('rend deux unités avec la prop parts, pour le futur badge LIVE (AC5)', function () use ($timeText, $atFrozenTime): void {
    /*
     * ⚠️ Carbon rend « 2 h 17 min », et non « 2 h 17 » comme l'écrivait l'AC :
     * l'unité de la seconde part est conservée. Mesuré le 2026-08-08, pas
     * supposé — c'est la sortie réelle qui fait foi.
     */
    $text = '';

    $atFrozenTime('2026-06-15 12:00:00', static function () use (&$text, $timeText): void {
        $text = $timeText(
            Blade::render('<x-time-since :datetime="$start" :parts="2" short />', [
                'start' => Carbon::parse('2026-06-15 09:43:00'),
            ]),
            '<x-time-since parts>',
        );
    });

    expect($text)
        ->toBe('2 h 17 min', 'La prop parts ne produit pas une durée en deux unités.');
});

it('refuse un nombre de parts qui ferait disparaître la mention (AC5)', function () use ($expectRejected): void {
    /*
     * `(int) $parts` transformerait 'deux' et 0 en 0, et Carbon rendrait une
     * chaîne VIDE : une mention temporelle qui disparaît sans que rien ne la
     * réclame.
     */
    foreach ([0, -1, 'deux'] as $parts) {
        $expectRejected(
            static fn (): string => Blade::render('<x-time-since :datetime="$start" :parts="$parts" />', [
                'start' => Carbon::now()->subYears(4),
                'parts' => $parts,
            ]),
            '<x-time-since>',
            'parts = [' . $parts . ']',
        );
    }
});

/*
|--------------------------------------------------------------------------
| AC6 — l'intervalle est exposé, par défaut à 60 000 ms
|--------------------------------------------------------------------------
*/

it('expose un intervalle de 60 000 ms par défaut, surchargeable (AC6)', function () use ($attributeOf): void {
    /*
     * La valeur par défaut se vérifie STRUCTURELLEMENT — attendre une minute
     * dans un test navigateur serait absurde, et une borne d'attente qui
     * dépasse la minute rendrait la suite inutilisable. Ce que le navigateur
     * vérifie, lui, c'est que l'intervalle LU est bien celui du DOM.
     */
    $instant = Carbon::now()->subHours(3);

    $default = Blade::render('<x-time-relative :datetime="$instant" />', [
        'instant' => $instant,
    ]);

    expect($attributeOf($default, 'data-time-refresh', '<x-time-relative>'))
        ->toBe('60000', 'L\'intervalle par défaut n\'est pas 60 000 ms.');

    $overridden = Blade::render('<x-time-relative :datetime="$instant" :refresh="250" />', [
        'instant' => $instant,
    ]);

    expect($attributeOf($overridden, 'data-time-refresh', '<x-time-relative :refresh>'))
        ->toBe('250', 'L\'intervalle n\'est pas surchargeable par une prop.');
});

it('refuse un intervalle non numérique, nul, minuscule ou débordant (AC6)', function () use ($expectRejected): void {
    /*
     * ⚠️ `setInterval(fn, NaN)` ne se contente PAS d'échouer : il tourne à
     * intervalle minimal, EN CONTINU. Cette garde empêche une boucle chaude sur
     * une page publique — elle n'est pas défensive par principe.
     *
     * ⚠️ ET ELLE EST BORNÉE DES DEUX CÔTÉS (revue du 2026-08-08). `> 0` seul
     * laissait passer `:refresh="1"`, qui produit EXACTEMENT la boucle chaude
     * annoncée : les navigateurs clampent à 4 ms, soit 250 réveils par seconde
     * et par mention temporelle. Une page d'archive à 12 vignettes en ferait
     * 3000. Et à l'autre bout, une valeur au-delà de 2^31-1 déborde l'entier
     * signé de `setInterval` et se déclenche immédiatement, en continu : le même
     * défaut, atteint par le côté qui avait l'air inoffensif.
     */
    $instant = Carbon::now()->subHours(3);

    foreach (['pas-un-nombre', 0, -1, 1, 249, 86400001, 2147483648] as $refresh) {
        $expectRejected(
            static fn (): string => Blade::render('<x-time-relative :datetime="$instant" :refresh="$refresh" />', [
                'instant' => $instant,
                'refresh' => $refresh,
            ]),
            '<x-time-relative>',
            'refresh = [' . $refresh . ']',
        );
    }

    // Anti-vacuité : les bornes elles-mêmes doivent être ACCEPTÉES, sans quoi la
    // garde pourrait tout refuser et les assertions ci-dessus resteraient vertes.
    foreach ([250, 60000, 86400000] as $refresh) {
        $html = Blade::render('<x-time-relative :datetime="$instant" :refresh="$refresh" />', [
            'instant' => $instant,
            'refresh' => $refresh,
        ]);

        expect(str_contains($html, 'data-time-refresh="' . $refresh . '"'))
            ->toBeTrue("La garde refuse [{$refresh}] ms, qui est pourtant dans le domaine autorisé : elle refuserait tout.");
    }
});

it('câble bien le comportement Alpine, plutôt que de simplement l\'interdire (AC6)', function (): void {
    /*
     * ⚠️ ANTI-VACUITÉ, ET CE N'EST PAS DÉCORATIF : le scan « zéro expression JS »
     * de l'AC9 serait PARFAITEMENT VERT sur un composant qui n'a aucun
     * comportement du tout. Sans ce contrôle, supprimer `x-data` du template et
     * `Alpine.data('timeRelative')` d'app.js ne ferait rougir aucun test de
     * rendu.
     *
     * ⚠️ On cherche L'APPEL, pas la chaîne : `str_contains($script, 'datetime')`
     * resterait vert sur un JS qui ne lit plus l'attribut, parce que ses propres
     * messages d'erreur en parlent. Deux garde-fous de la Story 1.13 sont morts
     * exactement ainsi.
     */
    $template = (string) preg_replace(
        '#\{\{--.*?--\}\}#s',
        '',
        (string) file_get_contents(base_path('resources/views/components/time-relative.blade.php')),
    );

    expect(preg_match('/\sx-data="timeRelative"/', $template))
        ->toBe(1, 'time-relative.blade.php ne référence plus la fabrique Alpine : le scan AC9 serait vert sur un composant inerte.');

    expect(preg_match('/\sx-text="label"/', $template))
        ->toBe(1, 'time-relative.blade.php n\'expose plus son libellé à Alpine.');

    $script = (string) file_get_contents(base_path('resources/js/app.js'));

    expect(str_contains($script, "Alpine.data('timeRelative'"))
        ->toBeTrue('app.js n\'enregistre aucune fabrique Alpine nommée `timeRelative` : x-data="timeRelative" ne résoudrait rien.');

    expect(str_contains($script, "Alpine.data('toast'"))
        ->toBeTrue('La fabrique `toast` de la Story 1.13 a été REMPLACÉE au lieu d\'être rejointe dans le même écouteur alpine:init.');

    expect(str_contains($script, 'dataset.timeRefresh'))
        ->toBeTrue('L\'intervalle n\'est pas lu depuis le DOM : il serait écrit en dur dans le JS, seconde source de vérité.');

    expect(str_contains($script, "getAttribute('datetime')"))
        ->toBeTrue('L\'instant n\'est pas lu depuis l\'attribut datetime : le libellé se calculerait sur autre chose que ce que le document annonce.');

    expect(str_contains($script, "numeric: 'always'"))
        ->toBeTrue('Intl tourne en `numeric: auto` : il rendrait « hier » là où Carbon rend « il y a 1 jour ».');
});

/*
|--------------------------------------------------------------------------
| AC7 — une seule vérité pour le libellé : le côté serveur de la table
|--------------------------------------------------------------------------
*/

it('produit avec Carbon chaque libellé de la table de cas partagée, forme longue (AC7)', function () use ($atFrozenTime): void {
    /*
     * La MOITIÉ SERVEUR de l'AC7. L'autre moitié — le JS produit-il la même
     * chose ? — vit dans tests/Browser/TimeAsTextureTest.php et lit LA MÊME
     * table. C'est la seule construction où une dérive d'un seul côté rougit.
     *
     * Vu rouge : en mutant un libellé de RelativeTimeCases::long().
     */
    $atFrozenTime('2026-06-15 12:00:00', static function (): void {
        $cases = RelativeTimeCases::long();

        // Anti-vacuité : une table vide passerait la boucle sans rien prouver.
        expect($cases)
            ->not->toBeEmpty('La table de cas partagée est vide.');

        foreach ($cases as $seconds => $expected) {
            $rendered = Carbon::now()
                ->subSeconds($seconds)
                ->diffForHumans();

            expect($rendered)
                ->toBe($expected, "Carbon rend [{$rendered}] à {$seconds} s, la table attend [{$expected}].");
        }
    });
});

it('produit avec Carbon chaque libellé de la table de cas partagée, forme courte (AC7)', function () use ($atFrozenTime): void {
    $atFrozenTime('2026-06-15 12:00:00', static function (): void {
        $cases = RelativeTimeCases::short();

        expect($cases)
            ->not->toBeEmpty('La table de cas courte est vide.');

        foreach ($cases as $seconds => $expected) {
            $rendered = Carbon::now()
                ->subSeconds($seconds)
                ->diffForHumans(short: true);

            expect($rendered)
                ->toBe($expected, "Carbon rend [{$rendered}] à {$seconds} s en forme courte, la table attend [{$expected}].");
        }
    });
});

it('couvre les 4 unités que le client a le droit de calculer, et les deux côtés de leurs bornes (AC7)', function (): void {
    /*
     * La table n'est utile que si elle couvre ce que le rafraîchissement fait
     * réellement changer. Ce test-ci garde LA COUVERTURE de la table, pas son
     * exactitude : sans lui, quelqu'un pourrait la réduire à trois cas de
     * secondes et les deux tests ci-dessus resteraient verts.
     *
     * ⚠️ L'AC écrivait « 59 s → 1 minute ». C'est faux au pied de la lettre :
     * Carbon TRONQUE, donc 59 s rend « il y a 59 secondes ». Ce sont les DEUX
     * CÔTÉS de chaque transition qu'il faut, et c'est strictement plus fort.
     */
    $cases = RelativeTimeCases::long();

    foreach ([59, 60, 3599, 3600, 86399, 86400] as $boundary) {
        expect(array_key_exists($boundary, $cases))
            ->toBeTrue("La table ne couvre pas la borne des {$boundary} s : c'est pourtant une transition que le rafraîchissement existe pour rendre.");
    }

    // Les 4 unités, et rien au-delà du plafond des 7 jours : au-delà, le client
    // ne calcule rien et le libellé du serveur fait foi.
    foreach (['seconde', 'minute', 'heure', 'jour'] as $unit) {
        $found = array_filter($cases, static fn (string $label): bool => str_contains($label, $unit));

        expect($found)
            ->not->toBeEmpty("Aucun cas de la table ne couvre l'unité [{$unit}].");
    }

    foreach (array_keys($cases) as $seconds) {
        expect(abs($seconds))
            ->toBeLessThan(604800, "Le cas à {$seconds} s dépasse le plafond des 7 jours EN VALEUR ABSOLUE : le client ne calcule rien au-delà, ce cas ne serait vérifiable d'aucun côté.");
    }

    /*
     * ⚠️ LES DEUX SENS. Le composant accepte un instant futur (un stream
     * annoncé), et le JS gère explicitement le signe. Sans cas négatif, toute
     * cette branche est non observée : l'inverser rendrait « il y a 3 heures »
     * pour dans 3 heures, sans qu'aucun test ne bouge. Ajouté à la revue du
     * 2026-08-08.
     */
    $future = array_filter(array_keys($cases), static fn (int $seconds): bool => $seconds < 0);

    expect($future)
        ->not->toBeEmpty('La table ne couvre aucun instant FUTUR : la branche de signe du JS n\'est observée par rien.');

    foreach ($future as $seconds) {
        expect(str_starts_with($cases[$seconds], 'dans '))
            ->toBeTrue("Le cas futur à {$seconds} s attend [{$cases[$seconds]}] : un instant futur se dit « dans … », pas « il y a … ».");
    }

    /*
     * ⚠️ LES MÊMES CLÉS, PAS LE MÊME NOMBRE DE CLÉS. La rédaction d'origine
     * comparait les CARDINAUX avec un message qui promettait « les mêmes cas » :
     * deux tables de 18 entrées aux clés différentes passaient, et seul le test
     * navigateur — le plus lent et le plus fragile — l'aurait rattrapé.
     */
    expect(array_keys(RelativeTimeCases::short()))
        ->toBe(array_keys($cases), 'Les deux formes de la table ne couvrent pas les mêmes cas : un décalage de clés laisserait une forme vérifiée d\'un seul côté.');

    // Les 4 unités doivent aussi être couvertes en forme COURTE : c'est elle que
    // les écrans de référence emploient, et c'est elle qui portait l'insécable.
    foreach (['s', 'min', 'h', 'j'] as $shortUnit) {
        $found = array_filter(
            RelativeTimeCases::short(),
            static fn (string $label): bool => preg_match('/\d ' . preg_quote($shortUnit, '/') . '$/', $label) === 1,
        );

        expect($found)
            ->not->toBeEmpty("Aucun cas de la table courte ne couvre l'unité [{$shortUnit}].");
    }
});

it('verrouille le fuseau applicatif sur UTC, dont la table de non-dérive dépend sans le dire (AC7)', function (): void {
    /*
     * ⚠️ LE CAS QUE LA TABLE NE PEUT PAS COUVRIR, ET QU'ELLE SUPPOSE POURTANT.
     *
     * Carbon compte en CALENDAIRE (`DateTime::diff`), le JS compte en SECONDES
     * FIXES (`RELATIVE_UNITS`, `86400 s = 1 jour`). Les deux ne coïncident que
     * dans un fuseau SANS changement d'heure.
     *
     * Mesuré au passage à l'heure d'été à Paris (2026-03-29), pas supposé :
     *
     *     82800 s réelles  →  Carbon : « il y a 1 jour »
     *                      →  JS     : floor(82800/86400) = 0 → « il y a 23 heures »
     *
     * 23 heures murales font 1 jour calendaire. C'est une dérive unilatérale,
     * deux fois par an, exactement ce que l'AC7 existe pour rendre impossible —
     * dans la seule dimension que la table ne paramètre pas.
     *
     * Elle est neutralisée aujourd'hui par `APP_TIMEZONE=UTC`, et RIEN NE
     * GARDAIT cette dépendance : un fork-streamer qui met `Europe/Paris` — un
     * réglage raisonnable, interdit nulle part — l'activerait sans le savoir,
     * avec 145 tests verts. Décision PO à la revue du 2026-08-08 : verrouiller
     * la dépendance plutôt que réimplémenter le calendaire côté client, ce qui
     * rouvrirait la surface de duplication que le plafond des 7 jours existe
     * pour borner.
     *
     * ⚠️ Ce test n'est PAS une préférence de configuration. Le jour où le fuseau
     * doit changer, il faut d'abord traiter la dérive — et c'est ce message qui
     * le dira, au lieu de laisser découvrir le défaut un dimanche de mars.
     */
    expect(config('app.timezone'))
        ->toBe('UTC', 'Le fuseau applicatif n\'est plus UTC : la table de non-dérive de l\'AC7 suppose que 86400 s valent 1 jour, ce qui est FAUX aux changements d\'heure. Traiter la dérive calendaire Carbon ↔ Intl AVANT de changer ce réglage.');
});

it('fait porter aux sondes HTML brut de la démo exactement les classes du composant (AC6 — chemins d\'erreur)', function (): void {
    /*
     * ⚠️ LES DEUX SONDES SONT DES CLONES, ET UN CLONE DÉRIVE.
     *
     * `#time-broken-refresh` et `#time-broken-iso` sont écrits en HTML brut —
     * il le faut, le composant REFUSE de produire leurs attributs cassés. Mais
     * ils recopient la liste de classes de `<x-time-relative>`, et c'est sur eux
     * que tourne le test « signale bruyamment ». Le jour où le composant change
     * sa liste, les clones divergent en silence et les chemins d'erreur ne sont
     * plus exercés dans les conditions du code livré — ce que l'AC6 exige
     * pourtant en toutes lettres (« exercent des chemins d'erreur RÉELS du code
     * livré »). Relevé à la revue du 2026-08-08.
     */
    $classesOf = static function (string $html): array {
        preg_match('/class="([^"]*)"/', $html, $matches);

        $classes = preg_split('/\s+/', trim($matches[1] ?? ''), -1, PREG_SPLIT_NO_EMPTY) ?: [];
        sort($classes);

        return $classes;
    };

    $expected = $classesOf(Blade::render('<x-time-relative :datetime="$d" />', [
        'd' => Carbon::now()->subHours(3),
    ]));

    expect($expected)
        ->not->toBeEmpty('Le composant ne rend aucune classe : la comparaison ci-dessous serait vide.');

    $demo = (string) file_get_contents(base_path('resources/views/_time-demo.blade.php'));

    /*
     * ⚠️ ON NE DÉCOUPE PAS LA BALISE AVEC `[^>]*`.
     *
     * Les sondes portent `datetime="{{ $recent->toIso8601String() }}"` — et
     * `->` contient un `>`. Un `[^>]*` s'arrête donc AVANT l'attribut `class`,
     * et la comparaison porte sur le vide en ayant l'air de porter sur quelque
     * chose. (Attrapé par ce test lui-même, en le voyant rouge.)
     *
     * Les balises de la démo sont écrites un attribut par ligne et fermées par
     * un `>` seul en début de ligne : c'est ce qui les délimite ici.
     */
    preg_match_all('/<time\b.*?\R\s*>/s', $demo, $elements);

    foreach (['time-broken-refresh', 'time-broken-iso'] as $id) {
        $element = '';

        foreach ($elements[0] as $candidate) {
            if (str_contains($candidate, 'id="' . $id . '"')) {
                $element = $candidate;

                break;
            }
        }

        expect($element)
            ->not->toBe('', "La sonde #{$id} a disparu de la page de démonstration : un chemin d'erreur n'est plus exercé.");

        expect($classesOf($element))
            ->toBe($expected, "Les classes de la sonde #{$id} ont dérivé de celles de <x-time-relative> : le chemin d'erreur n'est plus exercé dans les conditions du code livré.");
    }
});

/*
|--------------------------------------------------------------------------
| AC10 — les mentions temporelles restent inventoriables
|--------------------------------------------------------------------------
*/

it('fait porter data-temporal aux 4 composants, une fois chacun (AC10)', function (): void {
    /*
     * ⚠️ CECI N'EST PAS UN TEST AUTOMATISÉ DE L'AUDIT. Personne n'a su nommer
     * la mutation qui ferait rougir utilement « la liste des mentions est
     * intentionnelle ». C'est un INSTRUMENT DE RELECTURE, exactement comme le
     * `grep -c 'class="temporal"'` du §4 de l'audit — à ceci près que celui-ci
     * n'avait jamais eu de référent côté production. Le voici.
     *
     * Ce qui est réellement gardé ici : qu'aucune mention temporelle rendue par
     * ces composants n'échappe au comptage, et qu'un <x-time-dual> compte pour
     * UNE mention et non deux.
     */
    $instant = Carbon::parse('2026-01-14');

    $renders = [
        '<x-time-relative>' => Blade::render('<x-time-relative :datetime="$d" />', [
            'd' => $instant,
        ]),
        '<x-time-absolute>' => Blade::render('<x-time-absolute :datetime="$d" />', [
            'd' => $instant,
        ]),
        '<x-time-since>' => Blade::render('<x-time-since :datetime="$d" />', [
            'd' => $instant,
        ]),
        '<x-time-dual>' => Blade::render('<x-time-dual :published="$d" :updated="$u" />', [
            'd' => $instant,
            'u' => $instant->copy()
                ->addDays(90),
        ]),
    ];

    foreach ($renders as $component => $html) {
        expect(preg_match_all('/\sdata-temporal(?=[\s>=])/', $html))
            ->toBe(1, "{$component} ne porte pas exactement un marqueur data-temporal : l'inventaire de la Story 10.5 se croirait exhaustif sans l'être.");
    }
});

/*
|--------------------------------------------------------------------------
| T10 — la page de démonstration ne doit pas exister en production
|--------------------------------------------------------------------------
*/

it('répond 200 sur la page de démonstration du temps (T10)', function (): void {
    /*
     * Cette page passe par le groupe `web`, donc par SetCurrentStreamer, qui
     * fait un firstOrFail(). Sans streamer semé, elle répond 404 — et les tests
     * navigateur rougiraient pour une raison étrangère aux composants.
     */
    App\Core\Models\Streamer::factory()->create();

    $response = app(Kernel::class)->handle(Request::create(route('time.demo')));

    expect($response->getStatusCode())
        ->toBe(200, 'La page de démonstration du temps ne répond pas 200.');
});

it('n\'enregistre la page de démonstration du temps qu\'en local et testing (T10)', function (): void {
    /*
     * Vu rouge : en retirant le `if (app()->environment([...]))` de
     * routes/web.php.
     */
    foreach (['local', 'testing'] as $environment) {
        expect(RouteTable::registeredIn($environment)->getByName('time.demo'))
            ->not->toBeNull("La page de démonstration devrait être disponible en [{$environment}].");
    }

    $production = RouteTable::registeredIn('production');

    // Anti-vacuité : si le fichier de routes n'avait pas été rejoué du tout, la
    // route serait absente pour une mauvaise raison et ce test serait vert sans
    // rien prouver.
    expect(count($production->getRoutes()))
        ->toBeGreaterThan(0, 'routes/web.php n\'a pas été rejoué : le test ne prouve rien.');

    expect($production->getByName('time.demo'))
        ->toBeNull('La page de démonstration du temps est exposée en production : surface inutile, non gardée.');
});

it('refuse la page de démonstration du temps à la requête, même si la route existe (T10)', function (): void {
    /*
     * Le second verrou, celui qui survit à `php artisan route:cache` — un cache
     * construit en local puis déployé embarquerait la route malgré la garde à
     * l'enregistrement, et aucun test ne pourrait le voir.
     *
     * La Story 1.11 ne testait qu'UNE des deux gardes ; la 1.13 a corrigé. Ne
     * pas régresser.
     *
     * Vu rouge : en retirant l'abort_unless() de la route.
     */
    App\Core\Models\Streamer::factory()->create();

    $previous = app()
        ->environment();
    $previousEnvironment = is_string($previous) ? $previous : 'testing';

    app()
        ->detectEnvironment(static fn (): string => 'production');

    try {
        $response = app(Kernel::class)->handle(Request::create('/_time'));

        expect($response->getStatusCode())
            ->toBe(404, '[/_time] a servi une page de démonstration en production.');
    } finally {
        app()->detectEnvironment(static fn (): string => $previousEnvironment);
    }
});

/*
|--------------------------------------------------------------------------
| Discipline typographique — la part qui se lit dans le rendu
|--------------------------------------------------------------------------
*/

it('réserve une largeur au SEUL composant dont le libellé change (AC8)', function (): void {
    /*
     * La largeur elle-même est MESURÉE dans le navigateur : `min-w-temporal`
     * prouve seulement qu'on a tapé ces caractères. Ce qui se vérifie ici est
     * l'INTENTION — que la réservation soit portée par le composant qui se
     * rafraîchit, et par lui seul. Réserver 18 caractères sous une date fixe
     * creuserait un trou dans la mise en page sans rien empêcher de tressauter.
     */
    $instant = Carbon::parse('2026-01-14');

    $relative = Blade::render('<x-time-relative :datetime="$d" />', [
        'd' => $instant,
    ]);

    expect(str_contains($relative, 'min-w-temporal'))
        ->toBeTrue('<x-time-relative> ne réserve aucune largeur : la page tressautera à chaque rafraîchissement.');

    /*
     * ⚠️ LES TROIS AUTRES, PAS DEUX. La rédaction d'origine s'intitulait « le
     * SEUL composant » et n'en énumérait que deux : `<x-time-dual>` manquait,
     * donc lui ajouter `min-w-temporal` n'aurait rien fait rougir — alors que
     * réserver 18 caractères sous une date fixe creuse un trou dans la mise en
     * page sans rien empêcher de tressauter, ce que le commentaire ci-dessus dit
     * précisément vouloir empêcher. (Revue du 2026-08-08.)
     */
    foreach ([
        '<x-time-absolute>' => '<x-time-absolute :datetime="$d" />',
        '<x-time-since>' => '<x-time-since :datetime="$d" />',
        '<x-time-dual>' => '<x-time-dual :published="$d" />',
    ] as $component => $blade) {
        expect(str_contains(Blade::render($blade, [
            'd' => $instant,
        ]), 'min-w-temporal'))
            ->toBeFalse("{$component} réserve une largeur alors que son libellé ne change jamais.");
    }
});

it('réserve à la forme COURTE sa propre largeur, pas celle de la forme longue (AC8)', function (): void {
    /*
     * `--width-temporal` vaut 18ch, dimensionné sur « il y a 59 secondes ». En
     * forme courte, le plus long libellé que le rafraîchissement peut produire
     * est « il y a 59 min » : réserver 18ch sous « il y a 14 h » creuse cinq
     * caractères de vide au milieu de « Dernier stream il y a 14 h », qui est
     * LA phrase de l'écran de référence (02-home-offline.html:85).
     *
     * Une largeur réservée existe pour empêcher un tressautement, pas pour
     * creuser un trou. Décision PO à la revue du 2026-08-08.
     */
    $instant = Carbon::parse('2026-01-14');

    $long = Blade::render('<x-time-relative :datetime="$d" />', [
        'd' => $instant,
    ]);
    $short = Blade::render('<x-time-relative :datetime="$d" short />', [
        'd' => $instant,
    ]);

    expect(str_contains($short, 'min-w-temporal-short'))
        ->toBeTrue('La forme courte réserve la largeur de la forme longue : cinq caractères de vide au milieu de la phrase.');

    // ⚠️ `min-w-temporal-short` CONTIENT `min-w-temporal` : une assertion naïve
    // d'absence passerait pour les deux. On compare donc les utilities exactes.
    $utilityOf = static function (string $html): string {
        preg_match('/\bmin-w-temporal(?:-short)?\b/', $html, $matches);

        return $matches[0] ?? 'AUCUNE';
    };

    expect($utilityOf($long))
        ->toBe('min-w-temporal', 'La forme longue n\'emploie plus la largeur dimensionnée sur « il y a 59 secondes ».');

    expect($utilityOf($short))
        ->toBe('min-w-temporal-short', 'La forme courte n\'a pas sa propre largeur.');
});

it('n\'emploie que la forme absolue de CarbonInterface pour la durée nue (AC5)', function () use ($timeText, $atFrozenTime): void {
    /*
     * Le pendant du test « sans préfixe » : celui-ci prouve que la SYNTAXE
     * employée est bien `DIFF_ABSOLUTE` et non un `str_replace('il y a ', '')`
     * qui produirait le même résultat en français et se casserait ailleurs.
     */
    $text = '';

    $atFrozenTime('2026-06-15 12:00:00', static function () use (&$text, $timeText): void {
        $text = $timeText(
            Blade::render('<x-time-since :datetime="$start" />', [
                'start' => Carbon::parse('2026-06-15 09:00:00'),
            ]),
            '<x-time-since>',
        );
    });

    expect($text)
        ->toBe(
            Carbon::parse('2026-06-15 09:00:00')->diffForHumans(
                Carbon::parse('2026-06-15 12:00:00'),
                CarbonInterface::DIFF_ABSOLUTE,
            ),
            'La durée nue ne correspond pas à ce que produit DIFF_ABSOLUTE.',
        );
});
