<?php

declare(strict_types=1);

use App\Core\Models\Streamer;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Support\BrowserAssertions;
use Tests\Support\FontManifest;

uses(RefreshDatabase::class);

/*
|--------------------------------------------------------------------------
| Story 1.9 — ce qui n'existe que dans un moteur de rendu
|--------------------------------------------------------------------------
|
| tests/Feature/FontsTest.php prouve le CÂBLAGE : la table, les @font-face, les
| preloads, leurs attributs, leur ordre. Aucune de ces preuves ne dit qu'un seul
| octet de police a été téléchargé. Un @font-face parfaitement écrit vers un
| fichier absent produit une page correcte, en fonte système, sans erreur de
| build, sans erreur console lisible, et sans un seul test rouge.
|
| ⛔ ET SURTOUT — LE PIÈGE QUE CETTE STORY A TROUVÉ DANS SON PROPRE ÉNONCÉ.
|
| `getComputedStyle(document.body).fontFamily` NE PROUVE RIEN ICI. C'est la
| lecture que fait tests/Browser/CascadeSmokeTest.php, qui exige « IBM Plex
| Sans » dans la valeur calculée — et qui est VERT depuis le 2026-08-06, alors
| qu'aucun woff2 n'existait dans ce dépôt. La propriété rend la PILE DÉCLARÉE
| par --font-sans, pas la fonte que le moteur a employée pour dessiner les
| glyphes. Elle la rendrait tout autant si IBM Plex n'existait pas au monde.
|
| ⛔ `document.fonts.check('16px "IBM Plex Sans"')` est un second faux-vert, plus
| vicieux : par spécification, `check()` renvoie `true` quand AUCUNE @font-face
| ne correspond à la famille demandée — les fontes système étant réputées
| toujours disponibles. Il répondait donc `true` avant cette story.
|
| L'observable retenu est l'ÉNUMÉRATION de `document.fonts` : elle ne contient
| que les faces déclarées par nos @font-face, et chacune porte un `status`.
|
| ─────────────────────────────────────────────────────────────────────────────
| ⚠️ RAPPELS ADR-0013, À NE PAS REDÉCOUVRIR
|
|  - `make npm-build` AVANT `make test-browser`, ET ENTRE CHAQUE MUTATION. Le
|    navigateur lit le CSS COMPILÉ et les fichiers de public/fonts/, pas les
|    sources. Sans rebuild, on mesure l'état précédent et on conclut faux.
|  - Le verdict ne vient PAS du code de sortie de pest (le plugin ne rend pas la
|    main ~1 run sur 2) : `make test-browser` lit le rapport JUnit.
|  - Pas de temporisation fixe. `document.fonts` est peuplé de façon ASYNCHRONE ;
|    une attente fixe est un pari sur la vitesse de la machine, et un test
|    instable finit désarmé.
|  - Local ≠ CI : Chromium natif d'Alpine (musl) ici, Chrome for Testing (glibc)
|    en CI.
*/

/**
 * Décode une liste d'objets renvoyée par `script()` sous forme de JSON.
 *
 * `script()` renvoie `mixed`, et un JSON malformé décoderait en `null` — sur
 * lequel un `foreach` vide passerait tranquillement. Le refus est ici, une fois,
 * et il nomme ce qui manquait.
 *
 * @return list<array<string, mixed>>
 */
$decodeList = static function (mixed $value, string $what): array {
    expect(is_string($value))
        ->toBeTrue("{$what} : script() n'a pas renvoyé de chaîne JSON.");

    $decoded = json_decode(is_string($value) ? $value : '', true);

    expect(is_array($decoded))
        ->toBeTrue("{$what} : la réponse n'est pas un tableau JSON — reçu [" . BrowserAssertions::readable($value) . '].');

    $rows = [];

    foreach (is_array($decoded) ? $decoded : [] as $row) {
        expect(is_array($row))
            ->toBeTrue("{$what} : une entrée n'est pas un objet.");

        /** @var array<string, mixed> $row */
        $rows[] = $row;
    }

    return $rows;
};

/**
 * Lit une clé de chaîne d'une entrée décodée, ou échoue en la nommant.
 *
 * @param  array<string, mixed>  $row
 */
$field = static function (array $row, string $key, string $what): string {
    $value = $row[$key] ?? null;

    expect(is_scalar($value))
        ->toBeTrue("{$what} : la clé [{$key}] est absente ou non scalaire.");

    return is_scalar($value) ? (string) $value : '';
};

/*
|--------------------------------------------------------------------------
| AC3 — ce que le build a réellement déposé
|--------------------------------------------------------------------------
*/

it('sert dans public/fonts EXACTEMENT les fichiers décrits par la table, et rien d\'autre (AC3)', function (): void {
    /*
     * Cette assertion vit dans la suite NAVIGATEUR et pas dans la suite Feature,
     * pour une raison précise : `public/fonts/` est dérivé du build. Un test
     * Feature qui le lirait rougirait chez un développeur qui n'a pas encore
     * buildé, pour une raison étrangère à ce qu'il teste. La suite navigateur,
     * elle, exige déjà un build — elle a le droit d'en constater le résultat.
     *
     * « et rien d'autre » n'est pas de la coquetterie : un fichier orphelin —
     * laissé par un `target` renommé — signifie que public/fonts contient plus
     * que ce que décrit une source de vérité, donc que le compte de l'AC7
     * mesurerait un état que plus personne ne décrit.
     *
     * Vu rouge : en désactivant le plugin de copie de vite.config.js.
     */
    $expected = FontManifest::servedFiles();

    expect($expected)
        ->not->toBeEmpty('La table ne décrit aucun fichier à servir : le test ne prouve rien.');

    /*
     * ⚠️ L'ABSENCE DU DOSSIER EST TESTÉE AVANT SON CONTENU. Sans cette ligne,
     * `scandir()` d'un dossier inexistant émet un warning PHP et renvoie `false` :
     * le test se soldait par une ERREUR anonyme au lieu d'un échec qui nomme la
     * cause. Constaté en rejouant la mutation « plugin de copie désactivé »
     * (T10, MF-E) — un garde-fou dont le rouge n'est pas lisible se fait
     * désarmer au premier run pressé.
     */
    expect(is_dir(public_path('fonts')))
        ->toBeTrue('public/fonts/ n\'existe pas : le plugin `self-hosted-fonts` de vite.config.js n\'a pas tourné (npm run build oublié, ou plugin retiré).');

    $found = array_values(array_diff(
        scandir(public_path('fonts')) ?: [],
        ['.', '..'],
    ));

    sort($expected);
    sort($found);

    expect($found)
        ->toBe($expected, 'public/fonts/ ne correspond pas à la table — le plugin de copie de vite.config.js n\'a pas tourné, ou un fichier orphelin est resté.');

    /*
     * ⚠️ LA LICENCE EST VÉRIFIÉE PAR SON CONTENU, PAS PAR SON NOM DE FICHIER.
     *
     * Toute la chaîne se contentait jusqu'ici de noms : le manifeste nomme deux
     * paquets et deux `target` distincts, et l'assertion ci-dessus vérifie que
     * deux fichiers atterrissent. DEUX FICHIERS DE ZÉRO OCTET satisfaisaient donc
     * l'intégralité de la story — et le risque énoncé par l'AC1, « un problème
     * juridique offert à chaque forkeur » (ADR-0001), restait entier. Relevé à la
     * revue du 2026-08-09.
     *
     * Le contrôle vit ICI et pas en test Feature parce qu'il porte sur ce que le
     * build a réellement déposé : un test Feature devrait lire node_modules ou
     * public/fonts, que les Dev Notes §3 lui interdisent l'un comme l'autre.
     */
    foreach (FontManifest::licenses() as $license) {
        $contents = (string) file_get_contents(public_path('fonts/' . $license['target']));

        expect(mb_strlen($contents))
            ->toBeGreaterThan(1000, "La licence [{$license['target']}] est vide ou tronquée : une police servie sans sa licence est un problème juridique offert à chaque forkeur.");

        expect(str_contains($contents, 'SIL OPEN FONT LICENSE'))
            ->toBeTrue("Le fichier [{$license['target']}] ne contient pas le texte de la SIL Open Font License.");

        expect(str_contains($contents, 'Copyright'))
            ->toBeTrue("Le fichier [{$license['target']}] ne porte pas de notice de copyright — c'est elle qui diffère entre les deux paquets, et l'OFL §1 exige sa conservation.");
    }

    // Les deux notices sont DISTINCTES : c'est tout le motif d'en redistribuer
    // deux plutôt qu'une (2019/IBM Plex Sans, 2017/IBM Plex Mono).
    $notices = array_map(
        static fn (array $license): string => (string) file_get_contents(public_path('fonts/' . $license['target'])),
        FontManifest::licenses(),
    );

    expect(array_unique($notices))
        ->toHaveCount(count($notices), 'Les deux licences servies sont identiques : l\'une des deux notices de copyright a été perdue, ce que l\'OFL §1 interdit.');
});

/*
|--------------------------------------------------------------------------
| AC6 — les faces sont CHARGÉES, pas seulement déclarées
|--------------------------------------------------------------------------
*/

it('charge chaque face de la table, avec sa famille, sa graisse et le statut loaded (AC6)', function () use (
    $decodeList,
    $field
): void {
    /**
     * L'observable central de cette story.
     * 📌 Une face n'est chargée que si un élément de la page L'EMPLOIE :
     * `font-display: swap` ne déclenche le téléchargement qu'à l'usage, et le
     * preload seul laisse le statut à `unloaded`. D'où /_fonts, qui exerce les
     * quatre faces — un test Feature garde d'ailleurs cette propriété de la page.
     * Vu rouge : en renommant un `target` dans resources/fonts.json. Le plugin
     * copie alors le fichier sous le NOUVEAU nom, tandis que `public/fonts/` ne
     * contient plus l'ancien : le navigateur reçoit un 404 sur l'URL que le
     * @font-face demandait, et la face reste `unloaded`. Aucune erreur de build,
     * aucune page cassée.
     */
    Streamer::factory()->create();

    $faces = FontManifest::faces();
    $page = visit('/_fonts');

    $readLoadedCount = static fn (): mixed => $page->script(
        '(() => String(Array.from(document.fonts).filter(f => f.status === "loaded").length))()',
    );

    /*
     * `waitUntilAtLeast` et PAS `waitUntilValue` : le compte de faces chargées
     * est MONOTONE. L'égalité stricte peut être sautée si un aller-retour
     * Playwright dure plus longtemps qu'un chargement — leçon de la Story 1.12.
     * Le compte EXACT est vérifié ci-dessous, sur une énumération figée.
     */
    BrowserAssertions::waitUntilAtLeast(
        $readLoadedCount,
        count($faces),
        10_000,
        'le nombre de faces au statut `loaded`',
    );

    /*
     * ⚠️ ET `settled()` SUR LA TAILLE DE L'ÉNUMÉRATION, PARCE QUE LE COMPTE
     * EXACT CI-DESSOUS PRÉTEND DÉTECTER UN SURPLUS. Relevé à la seconde passe de
     * revue du 2026-08-09 : le raisonnement de compteur monotone justifie une
     * borne BASSE, jamais une borne haute. `waitUntilAtLeast` rend la main dès
     * que 4 faces sont chargées — une cinquième @font-face surnuméraire, arrivée
     * par une feuille chargée plus tard, n'a alors pas eu le temps d'exister, et
     * l'assertion « une @font-face surnuméraire » passe. C'est exactement le
     * défaut corrigé sur l'AC7 et l'AC8 à la première passe ; le raisonnement
     * avait été appliqué à deux des trois sites.
     */
    $readEnumeratedCount = static fn (): mixed => $page->script(
        '(() => String(document.fonts.size))()',
    );

    BrowserAssertions::settled($readEnumeratedCount, 'la taille de document.fonts');

    $enumerated = $decodeList(
        $page->script('(() => JSON.stringify(Array.from(document.fonts).map(f => ({family: f.family, weight: f.weight, style: f.style, status: f.status}))))()'),
        'l\'énumération de document.fonts',
    );

    expect($enumerated)
        ->toHaveCount(count($faces), 'document.fonts n\'énumère pas exactement les faces de la table : une @font-face surnuméraire ou manquante.');

    foreach ($faces as $face) {
        $matching = array_values(array_filter(
            $enumerated,
            static fn (array $row): bool => ($row['family'] ?? null) === $face['family']
                && (is_scalar($row['weight'] ?? null) ? (string) $row['weight'] : '') === (string) $face['weight'],
        ));

        expect($matching)
            ->toHaveCount(1, "document.fonts ne contient pas exactement une face [{$face['family']} {$face['weight']}].");

        expect($field($matching[0], 'status', 'la face ' . $face['family'] . ' ' . $face['weight']))
            ->toBe('loaded', "La face [{$face['family']} {$face['weight']}] n'est pas chargée : le fichier demandé par son @font-face n'a pas été servi.");

        expect($field($matching[0], 'style', 'la face ' . $face['family'] . ' ' . $face['weight']))
            ->toBe('normal', "La face [{$face['family']} {$face['weight']}] n'est pas déclarée en style normal.");
    }
});

/*
|--------------------------------------------------------------------------
| AC7 — aucune requête tierce, et les woff2 viennent du domaine local
|--------------------------------------------------------------------------
*/

it('ne demande AUCUNE ressource à un hôte de police tiers (AC7)', function () use ($decodeList, $field): void {
    /*
     * Le garde-fou STATIQUE existe déjà et reste en place : DesignTokensTest
     * interdit fonts.googleapis.com, fonts.gstatic.com et fonts.bunny.net dans
     * toutes les CSS et tous les Blade. Il a été écrit après avoir constaté que
     * welcome.blade.php tirait Instrument Sans de fonts.bunny.net pendant que la
     * feuille de style, elle, était propre.
     *
     * Celui-ci en est la contrepartie OBSERVÉE : ce que le navigateur demande
     * réellement, pas ce qui est écrit dans les sources. Une police tirée par un
     * paquet npm, une iframe ou une CSS de vendor échapperait au premier.
     *
     * ⚠️ `settled()` AVANT DE LIRE, COMME SES DEUX VOISINS. Relevé à la seconde
     * passe de revue du 2026-08-09 : ce test échantillonnait le Resource Timing
     * SANS aucune attente, alors que les deux assertions suivantes appellent
     * `settled()` pour exactement cette raison. Or la faute qu'il cherche est
     * une requête TARDIVE — une feuille de vendor, une iframe, un chargement
     * différé — c'est-à-dire précisément celle qui atterrit après un instantané
     * pris trop tôt. Un scan de tiers qui lit trop tôt est vert par construction.
     */
    Streamer::factory()->create();

    $page = visit('/_fonts');

    $readResourceCount = static fn (): mixed => $page->script(
        '(() => String(performance.getEntriesByType("resource").length))()',
    );

    BrowserAssertions::settled($readResourceCount, 'le nombre d\'entrées du Resource Timing');

    $resources = $decodeList(
        $page->script('(() => JSON.stringify(performance.getEntriesByType("resource").map(e => ({name: e.name}))))()'),
        'les entrées de performance.getEntriesByType("resource")',
    );

    expect($resources)
        ->not->toBeEmpty('Aucune ressource relevée : le test ne prouve rien.');

    $banned = ['fonts.googleapis.com', 'fonts.gstatic.com', 'fonts.bunny.net'];

    foreach ($resources as $resource) {
        $name = $field($resource, 'name', 'une entrée de ressource');

        foreach ($banned as $host) {
            expect(str_contains($name, $host))
                ->toBeFalse("La page demande [{$name}] : aucun octet de police ne doit transiter par un tiers (RGPD, ADR-0001).");
        }
    }
});

it('sert chaque woff2 depuis son propre domaine, une seule fois, et depuis la table (AC7)', function () use (
    $decodeList,
    $field
): void {
    /*
     * TROIS fautes attrapées d'un coup, et aucune ne produit d'erreur visible :
     *
     *  1. Une police servie par un tiers → origine étrangère à celle du document.
     *  2. Un `href` de preload orphelin → une entrée SURNUMÉRAIRE (le 404 est
     *     compté par le Resource Timing), donc plus d'entrées que de faces.
     *  3. Un `crossorigin` manquant sur un preload → le fichier est téléchargé
     *     DEUX FOIS (une fois en mode non-CORS par le <link>, une fois en mode
     *     CORS par le @font-face). Deux entrées portent alors le MÊME nom.
     *
     * D'où le double compte : total d'entrées ET noms distincts. Ne compter que
     * les noms distincts laisserait passer le cas 3 ; ne compter que le total
     * laisserait passer un remplacement.
     *
     * Vu rouge : en retirant `crossorigin` du composant de preload.
     */
    Streamer::factory()->create();

    $faces = FontManifest::faces();
    $page = visit('/_fonts');

    $readWoffCount = static fn (): mixed => $page->script(
        '(() => String(performance.getEntriesByType("resource").filter(e => e.name.endsWith(".woff2")).length))()',
    );

    BrowserAssertions::waitUntilAtLeast(
        $readWoffCount,
        count($faces),
        10_000,
        'le nombre d\'entrées .woff2 du Resource Timing',
    );

    /*
     * ⚠️ PUIS ON ATTEND QUE LE COMPTE SE STABILISE, ET C'EST LA MOITIÉ DU TEST.
     *
     * `waitUntilAtLeast` rend la main à l'INSTANT où le compteur atteint 4. Or
     * les trois fautes visées se manifestent par un compte SUPÉRIEUR — un href
     * orphelin, un crossorigin manquant. Asserter `toHaveCount(4)` juste après un
     * seuil « au moins 4 » revient à échantillonner avant que la 5ᵉ entrée n'ait
     * eu le temps d'arriver : vert par chance dans un sens, instable dans l'autre.
     * MF-B a bien été vu rouge (7 entrées), ce qui prouve que ça marchait souvent
     * — pas que c'était déterministe. Relevé à la revue du 2026-08-09.
     *
     * `settled()` lit jusqu'à ce que deux lectures consécutives coïncident : le
     * surplus a alors eu le temps d'exister, et le compte exact ci-dessous mesure
     * un état stable plutôt qu'un instant.
     */
    BrowserAssertions::settled($readWoffCount, 'le nombre d\'entrées .woff2 du Resource Timing');

    $origin = BrowserAssertions::asComputedValue(
        $page->script('(() => window.location.origin)()'),
        'l\'origine du document',
    );

    $entries = $decodeList(
        $page->script('(() => JSON.stringify(performance.getEntriesByType("resource").filter(e => e.name.endsWith(".woff2")).map(e => ({name: e.name}))))()'),
        'les entrées .woff2',
    );

    $names = [];

    foreach ($entries as $entry) {
        $name = $field($entry, 'name', 'une entrée .woff2');
        $names[] = $name;

        expect(str_starts_with($name, $origin . '/fonts/'))
            ->toBeTrue("Le woff2 [{$name}] n'est pas servi depuis l'origine du document [{$origin}].");

        $target = mb_substr($name, mb_strlen($origin . '/fonts/'));

        expect(in_array($target, array_map(static fn (array $face): string => $face['target'], $faces), true))
            ->toBeTrue("Le woff2 [{$target}] n'appartient à aucune entrée de resources/fonts.json.");
    }

    expect($entries)
        ->toHaveCount(count($faces), 'Le nombre d\'entrées .woff2 ne correspond pas au nombre de faces employées par la page : soit un href de preload est orphelin, soit un preload sans crossorigin a provoqué un second téléchargement.');

    expect(array_unique($names))
        ->toHaveCount(count($names), 'Un même woff2 a été téléchargé deux fois : un <link rel="preload"> sans `crossorigin` ne se rapproche jamais de la requête du @font-face.');
});

/*
|--------------------------------------------------------------------------
| AC8 — le preload sert vraiment, et pas seulement décorativement
|--------------------------------------------------------------------------
*/

it('fait DÉCLENCHER les faces préchargées par le <link>, et les autres par le CSS (AC8)', function () use (
    $decodeList,
    $field
): void {
    /**
     * ⚠️ MESURÉ AVANT D'ÊTRE ASSERTÉ (2026-08-09, Chromium 150 d'Alpine). L'AC
     * prévoyait un repli au cas où le moteur ne distinguerait pas les deux
     * origines de déclenchement. Il les distingue, et proprement :
     *     link :: ibm-plex-sans-latin-400-normal-5.3.0.woff2   (preload: true)
     *     link :: ibm-plex-sans-latin-600-normal-5.3.0.woff2   (preload: true)
     *     link :: ibm-plex-mono-latin-400-normal-5.3.0.woff2   (preload: true)
     *     css  :: ibm-plex-sans-latin-500-normal-5.3.0.woff2   (preload: false)
     * Le repli n'est donc pas employé. La Story 1.11 a payé l'inverse — asserter
     * un comportement de moteur qu'on n'avait pas observé.
     *
     * ⛔ CE RELEVÉ A ÉTÉ REMESURÉ À LA SECONDE PASSE DE REVUE DU 2026-08-09, ET
     * IL FALLAIT. Il avait été recopié tel quel de la mesure d'origine, donc
     * SANS le suffixe de version — les quatre noms qu'il affichait n'existaient
     * plus depuis que la première passe avait fait porter la version au `target`.
     * Dans un docbloc dont la raison d'être est « mesurer avant d'asserter », une
     * mesure dont le référent n'existe pas est exactement le défaut qu'il
     * dénonce. Les valeurs ci-dessus sont celles de `public/fonts/`.
     * LA FAUTE QUE CET AC EXISTE POUR ATTRAPER : un `href` de preload erroné ne
     * casse rien d'observable. Le navigateur télécharge un 404, l'avertit dans
     * une console que personne ne lit, puis charge la police normalement via le
     * @font-face — un peu plus tard. La page est correcte, le preload est mort,
     * et aucune assertion classique ne le voit. Ici, la face passerait en `css`.
     * ⚠️ L'assertion est BILATÉRALE, et la seconde moitié fait le vrai travail :
     * « les faces NON préchargées valent `css` » est ce qui rougit si quelqu'un
     * bascule un `preload` à `true` sans le décider — un preload de plus n'est
     * pas gratuit, il dispute la bande passante au-dessus de la ligne de
     * flottaison.
     *
     * ⛔ CE DOCBLOC A PORTÉ UN « VU ROUGE » MÉCANIQUEMENT IMPOSSIBLE, RETIRÉ À LA
     * REVUE DU 2026-08-09. Il annonçait : « Vu rouge : en basculant `preload` de
     * la face 600 à `false` ». Cette rougeur ne peut pas exister. Les deux côtés
     * dérivent de la table : basculer le booléen fait disparaître le <link> ET
     * fait passer l'attente de `link` à `css` ; la face est alors découverte par
     * le moteur CSS, `initiatorType` vaut `css`, l'assertion est VERTE. C'est mot
     * pour mot ce que la campagne de mutation a consigné pour MF-D — même
     * mutation, face 400 — en la déclarant SURVIVANTE, 5/5 navigateur verts. Les
     * deux relevés ne pouvaient pas être vrais tous les deux.
     *
     * ✅ CE QUI A RÉELLEMENT ÉTÉ VU ROUGE ICI : MF-B, `crossorigin` retiré du
     * composant de preload. Le fichier est alors téléchargé deux fois, et
     * l'initiator de la seconde requête n'est plus celui qu'on attend.
     *
     * ⚠️ Et ce que ce test NE PEUT PAS attraper reste écrit plutôt que tu : un
     * `preload` basculé sans décision. C'est le rôle du test Feature « sert 4
     * faces et n'en précharge que 3 », dont les deux jeux sont écrits en dur.
     */
    Streamer::factory()->create();

    $faces = FontManifest::faces();
    $page = visit('/_fonts');

    $readWoffCount = static fn (): mixed => $page->script(
        '(() => String(performance.getEntriesByType("resource").filter(e => e.name.endsWith(".woff2")).length))()',
    );

    BrowserAssertions::waitUntilAtLeast(
        $readWoffCount,
        count($faces),
        10_000,
        'le nombre d\'entrées .woff2 du Resource Timing',
    );

    // Même raison qu'à l'AC7 : un second téléchargement (crossorigin manquant)
    // n'existe pas encore à l'instant où le seuil est franchi.
    BrowserAssertions::settled($readWoffCount, 'le nombre d\'entrées .woff2 du Resource Timing');

    $entries = $decodeList(
        $page->script('(() => JSON.stringify(performance.getEntriesByType("resource").filter(e => e.name.endsWith(".woff2")).map(e => ({name: e.name, initiatorType: e.initiatorType}))))()'),
        'les entrées .woff2 avec leur initiatorType',
    );

    /** @var array<string, string> $initiatorByTarget */
    $initiatorByTarget = [];

    foreach ($entries as $entry) {
        $name = $field($entry, 'name', 'une entrée .woff2');
        $initiatorByTarget[basename($name)] = $field($entry, 'initiatorType', "l'entrée [{$name}]");
    }

    foreach ($faces as $face) {
        expect(array_key_exists($face['target'], $initiatorByTarget))
            ->toBeTrue("Aucune requête pour [{$face['target']}] : la face n'a jamais été demandée.");

        $initiator = $initiatorByTarget[$face['target']];

        if ($face['preload']) {
            expect($initiator)
                ->toBe('link', "La face [{$face['target']}] est marquée preload, mais son téléchargement a été déclenché par [{$initiator}] : le <link rel=\"preload\"> n'a servi à rien (href erroné, ou rendu après @vite).");

            continue;
        }

        expect($initiator)
            ->toBe('css', "La face [{$face['target']}] n'est PAS marquée preload, mais son téléchargement a été déclenché par [{$initiator}] : un preload que personne n'a décidé dispute la bande passante au premier rendu.");
    }

    /*
     * ⚠️ ANTI-VACUITÉ SUR LES DEUX MOITIÉS, ET PAS SUR UNE SEULE.
     *
     * Seule la première existait : `preloaded()` non vide, qui protège la branche
     * `link`. Rien ne protégeait la branche `css` — celle que le docblock
     * ci-dessus désigne pourtant comme « le vrai travail ». Une table qui
     * passerait toutes ses faces à `preload: true` l'aurait rendue morte en
     * silence : la boucle n'y entrerait jamais, et le test serait vert en ne
     * prouvant plus que la moitié de ce qu'il annonce. C'est exactement la classe
     * de défaut qu'a exposée MF-D, recréée une branche plus loin. Relevé à la
     * revue du 2026-08-09.
     */
    expect(FontManifest::preloaded())
        ->not->toBeEmpty('Aucune face n\'est marquée preload : la branche `link` de l\'assertion n\'est jamais exercée.');

    expect(count(FontManifest::faces()) - count(FontManifest::preloaded()))
        ->toBeGreaterThan(0, 'Toutes les faces sont marquées preload : la branche `css` de l\'assertion n\'est jamais exercée, et ce test ne prouve plus que la moitié de ce qu\'il annonce.');
});
