<?php

declare(strict_types=1);

use App\Core\Models\Streamer;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Fixtures\RelativeTimeCases;
use Tests\Support\BrowserAssertions;

uses(RefreshDatabase::class);

/*
|--------------------------------------------------------------------------
| Story 1.12 — ce qui n'existe que dans un moteur de rendu
|--------------------------------------------------------------------------
|
| Cinq choses que `tests/Feature/TimeAsTextureTest.php` ne peut PAS prouver,
| parce qu'aucune n'existe dans une chaîne de HTML :
|
|  - un libellé qui SE RÉÉCRIT (rien ne s'exécute hors navigateur) ;
|  - une famille de police RÉSOLUE DEPUIS UN TOKEN (`font-mono` prouve qu'on a
|    tapé ces caractères, pas d'où vient la valeur) ;
|  - une largeur qui NE BOUGE PAS entre deux libellés de longueurs différentes ;
|  - l'ABSENCE d'un setInterval sur un élément trop ancien pour changer ;
|  - la non-dérive entre Carbon et Intl.RelativeTimeFormat, qui ne se mesure
|    qu'en faisant tourner les deux.
|
| ⚠️ Rappels ADR-0013, à ne pas redécouvrir :
|  - `make npm-build` AVANT `make test-browser` dès que app.js ou la CSS bouge.
|    `run-browser-tests.sh` ne construit RIEN : Chromium exécuterait l'ancien
|    bundle, et le rafraîchissement paraîtrait absent — ou pire, paraîtrait
|    marcher alors que le nouveau code n'a jamais été chargé. Piège le plus
|    coûteux de la Story 1.13, y compris ENTRE DEUX MUTATIONS.
|  - Le verdict ne vient PAS du code de sortie de `pest` (le plugin ne rend pas
|    la main ~1 run sur 2) : `make test-browser` lit le rapport JUnit.
|  - Base semée obligatoire : `/_time` passe par SetCurrentStreamer, qui fait un
|    firstOrFail(). Sans Streamer, la page répond 404 et le test rougit pour la
|    mauvaise raison.
|
| ⚠️ Pas de temporisation fixe : cette suite tourne sur DEUX Chromium
| différents. On lit jusqu'à une condition, avec une BORNE.
*/

/**
 * Fige l'horloge de la PAGE, et l'expose en `window.__frozenNow`.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * POURQUOI FIGER PLUTÔT QUE COMPENSER
 *
 * L'AC7 compare des libellés aux BORNES : 59 s, 3599 s, 86399 s. Une borne
 * haute n'a qu'une seconde de marge — le temps d'un aller-retour Playwright et
 * « il y a 23 heures » devient « il y a 1 jour ». Le test rougirait une fois sur
 * dix, donc finirait désarmé : c'est la leçon des 8 `wait(0.6)` retirés en
 * Story 1.11, dans l'autre sens.
 *
 * Figer `Date.now` rend la mesure DÉTERMINISTE sans rien ajouter au code de
 * production : le composant lit toujours son instant dans l'attribut `datetime`,
 * calcule toujours avec `Date.now()`, et le `setInterval` tourne toujours sur
 * l'horloge réelle. C'est le MÊME chemin qu'en production, avec une seule
 * variable immobilisée.
 *
 * @param  callable(string): mixed  $script
 */
$freezeClock = static function (callable $script): void {
    $frozen = $script(
        '(() => { const fixed = Date.now(); window.__frozenNow = fixed; Date.now = () => fixed; return String(fixed); })()',
    );

    expect(is_string($frozen) && $frozen !== '')
        ->toBeTrue('L\'horloge de la page n\'a pas pu être figée : les assertions aux bornes seraient instables.');
};

/*
|--------------------------------------------------------------------------
| AC6 — le libellé se rafraîchit, et seulement là où l'intervalle le permet
|--------------------------------------------------------------------------
*/

it('réécrit le libellé d\'un élément à intervalle court, et laisse l\'autre intact au même instant (AC6)', function (): void {
    /*
     * ⚠️ LA SECONDE MOITIÉ EST CE QUI REND L'ASSERTION NON-VIDE. « Le texte a
     * changé » serait vrai d'un rechargement de page, d'un Alpine qui plante, ou
     * d'un sélecteur qui ne trouve rien. On vérifie donc, AU MÊME INSTANT, qu'un
     * élément à intervalle par défaut (60 000 ms) n'a PAS bougé — les deux
     * éléments portent le même instant, seul leur intervalle diffère.
     *
     * C'est le patron `#toast-short` / `#toast-long` de la Story 1.13, transposé.
     *
     * Vu rouge : en remplaçant l'intervalle lu dans le DOM par une constante
     * dans app.js — l'élément « lent » se met alors à bouger lui aussi.
     */
    Streamer::factory()->create();

    $page = visit('/_time');

    $readFast = static fn (): mixed => $page->script(BrowserAssertions::text('#time-fast'));
    $readSlow = static fn (): mixed => $page->script(BrowserAssertions::text('#time-slow'));

    $initialFast = BrowserAssertions::asComputedValue($readFast(), 'libellé initial de #time-fast');
    $initialSlow = BrowserAssertions::asComputedValue($readSlow(), 'libellé initial de #time-slow');

    $changed = BrowserAssertions::waitUntilChanged($readFast, $initialFast, 10_000, 'rafraîchissement de #time-fast');

    expect(str_contains($changed, 'il y a'))
        ->toBeTrue("Le libellé rafraîchi vaut [{$changed}] : ce n'est plus une durée relative française.");

    $slowNow = BrowserAssertions::asComputedValue($readSlow(), 'libellé de #time-slow après rafraîchissement du voisin');

    expect($slowNow)
        ->toBe($initialSlow, "L'élément à intervalle par défaut a bougé ([{$initialSlow}] → [{$slowNow}]) : l'intervalle du DOM n'est pas lu.");

    expect($slowNow)
        ->not->toBe($changed, 'Les deux éléments affichent la même chose : l\'assertion ne distingue plus rien.');
});

it('ne programme AUCUN intervalle au-delà de 7 jours d\'ancienneté (AC6)', function (): void {
    /*
     * Un libellé en semaines, mois ou années ne peut pas changer pendant une
     * session : un setInterval qui réécrit la même chaîne toutes les minutes est
     * un coût sans contrepartie — et, accessoirement, la seule chose qui
     * empêcherait une page d'archive de 30 vignettes de tourner en continu.
     *
     * L'observation passe par un COMPTEUR DE DÉCLENCHEMENTS exposé sur
     * l'élément. Il est posé à '0' AVANT toute garde : un attribut absent
     * voudrait dire « aucun tick » ET « Alpine n'a jamais tourné », deux choses
     * que ce test doit pouvoir distinguer. La fenêtre d'observation n'est pas
     * une temporisation fixe — on attend que le voisin récent se soit déclenché
     * trois fois, ce qui prouve que la fenêtre EN AURAIT produit.
     *
     * ⚠️ DÉCLENCHEMENTS, ET NON RÉÉCRITURES. La première rédaction comptait les
     * réécritures : la mutation « plafond des 7 jours retiré » lui a SURVÉCU, le
     * 2026-08-08. L'intervalle était bien programmé, se déclenchait, sortait
     * sans réécrire — et le compteur restait à 0. Le garde-fou lisait
     * exactement ce qu'il aurait lu si la garde avait tenu. Voir app.js, tick().
     *
     * Vu rouge : en retirant la sortie sur `fresh === null` avant le
     * setInterval — #time-old se met alors à se déclencher comme les autres.
     */
    Streamer::factory()->create();

    $page = visit('/_time');

    /*
     * ⚠️ UN SEUIL, PAS UNE ÉGALITÉ. `data-time-ticks` est MONOTONE et
     * s'incrémente toutes les 250 ms ; chaque lecture est un aller-retour
     * Playwright non compté dans la borne. Sur une machine chargée, le compteur
     * passe de 2 à 4 et la valeur '3' n'est jamais observée — le test échouerait
     * alors que la garde qu'il observe fonctionne. Ce que la fenêtre doit
     * prouver, c'est « elle a bien eu lieu », et c'est ce que `>=` dit.
     * (Corrigé à la revue du 2026-08-08.)
     */
    BrowserAssertions::waitUntilAtLeast(
        static fn (): mixed => $page->script(BrowserAssertions::dataAttribute('#time-fast', 'data-time-ticks')),
        3,
        10_000,
        'compteur de ticks de #time-fast (fenêtre d\'observation)',
    );

    $oldTicks = BrowserAssertions::asComputedValue(
        $page->script(BrowserAssertions::dataAttribute('#time-old', 'data-time-ticks')),
        'compteur de ticks de #time-old',
    );

    expect($oldTicks)
        ->toBe('0', "L'élément vieux de plusieurs mois a tické [{$oldTicks}] fois : un intervalle a été programmé pour réécrire la même chaîne.");
});

/*
|--------------------------------------------------------------------------
| AC6 — les deux chemins d'erreur, exercés en HTML brut
|--------------------------------------------------------------------------
*/

it('ne programme aucun intervalle sur un rafraîchissement illisible, SANS emporter le recalcul (AC6 — chemin d\'erreur)', function (): void {
    /*
     * DEUX garde-fous en un, et c'est le même piège que la Story 1.13 a payé.
     *
     * 1. La branche fail-loud d'app.js (intervalle invalide → aucune minuterie)
     *    n'est atteignable par AUCUN rendu de <x-time-relative> : sa garde PHP
     *    refuse une valeur non numérique. C'est précisément pourquoi elle ne
     *    serait exercée par rien — d'où l'élément en HTML brut dans la page.
     *
     *    ⚠️ Ne pas « simplifier » en retirant la garde JS au motif que le PHP
     *    valide déjà : `setInterval(fn, NaN)` ne se contente pas d'échouer, il
     *    tourne à intervalle MINIMAL, en continu. Une boucle chaude.
     *
     * 2. L'intervalle cassé ne doit PAS emporter le recalcul initial du libellé.
     *    La Story 1.13 a livré une première rédaction où la garde sur la durée
     *    désarmait le câblage du bouton : les deux mécanismes n'ont aucune
     *    raison de tomber ensemble. Le texte de départ est donc un MARQUEUR
     *    volontairement absurde — s'il est encore là, le recalcul a été emporté.
     *
     * Vu rouge : en remontant le `return` de la garde d'intervalle avant le
     * recalcul (le marqueur reste), puis en retirant `Number.isFinite` (l'élément
     * se met à ticker).
     */
    Streamer::factory()->create();

    $page = visit('/_time');

    /*
     * ⚠️ UN SEUIL, PAS UNE ÉGALITÉ. `data-time-ticks` est MONOTONE et
     * s'incrémente toutes les 250 ms ; chaque lecture est un aller-retour
     * Playwright non compté dans la borne. Sur une machine chargée, le compteur
     * passe de 2 à 4 et la valeur '3' n'est jamais observée — le test échouerait
     * alors que la garde qu'il observe fonctionne. Ce que la fenêtre doit
     * prouver, c'est « elle a bien eu lieu », et c'est ce que `>=` dit.
     * (Corrigé à la revue du 2026-08-08.)
     */
    BrowserAssertions::waitUntilAtLeast(
        static fn (): mixed => $page->script(BrowserAssertions::dataAttribute('#time-fast', 'data-time-ticks')),
        3,
        10_000,
        'compteur de ticks de #time-fast (fenêtre d\'observation)',
    );

    $ticks = BrowserAssertions::asComputedValue(
        $page->script(BrowserAssertions::dataAttribute('#time-broken-refresh', 'data-time-ticks')),
        'compteur de ticks de #time-broken-refresh',
    );

    expect($ticks)
        ->toBe('0', "L'élément à intervalle illisible a tické [{$ticks}] fois : une minuterie a été programmée sur une valeur que rien ne définit.");

    $label = BrowserAssertions::asComputedValue(
        $page->script(BrowserAssertions::text('#time-broken-refresh')),
        'libellé de #time-broken-refresh',
    );

    expect($label)
        ->not->toBe('LIBELLE-SERVEUR-A-REMPLACER', 'La garde sur l\'intervalle a emporté le recalcul initial du libellé : une garde en a désarmé une autre.');

    expect(str_contains($label, 'il y a'))
        ->toBeTrue("Le libellé recalculé vaut [{$label}] : ce n'est pas une durée relative française.");
});

it('laisse INTACT le libellé du serveur quand l\'instant est illisible (AC6 — chemin d\'erreur)', function (): void {
    /*
     * Un composant qui viderait son texte sur une date cassée remplacerait une
     * information périmée par rien du tout — et `x-text="label"` fait exactement
     * cela si `label` n'a pas été initialisé depuis le DOM.
     *
     * Vu rouge : en retirant la reprise du texte serveur en tête d'`init()`
     * (l'élément se vide), puis en retirant la garde `Number.isFinite` sur
     * l'instant (il affiche « Invalid Date » ou une durée absurde).
     */
    Streamer::factory()->create();

    $page = visit('/_time');

    /*
     * ⚠️ UN SEUIL, PAS UNE ÉGALITÉ. `data-time-ticks` est MONOTONE et
     * s'incrémente toutes les 250 ms ; chaque lecture est un aller-retour
     * Playwright non compté dans la borne. Sur une machine chargée, le compteur
     * passe de 2 à 4 et la valeur '3' n'est jamais observée — le test échouerait
     * alors que la garde qu'il observe fonctionne. Ce que la fenêtre doit
     * prouver, c'est « elle a bien eu lieu », et c'est ce que `>=` dit.
     * (Corrigé à la revue du 2026-08-08.)
     */
    BrowserAssertions::waitUntilAtLeast(
        static fn (): mixed => $page->script(BrowserAssertions::dataAttribute('#time-fast', 'data-time-ticks')),
        3,
        10_000,
        'compteur de ticks de #time-fast (fenêtre d\'observation)',
    );

    $label = BrowserAssertions::asComputedValue(
        $page->script(BrowserAssertions::text('#time-broken-iso')),
        'libellé de #time-broken-iso',
    );

    expect($label)
        ->toBe('texte du serveur intact', "Le libellé rendu par le serveur n'a pas été laissé intact (lu : [{$label}]).");

    $ticks = BrowserAssertions::asComputedValue(
        $page->script(BrowserAssertions::dataAttribute('#time-broken-iso', 'data-time-ticks')),
        'compteur de ticks de #time-broken-iso',
    );

    // '0' — et pas 'null' : Alpine a bien initialisé l'élément, et n'a rien
    // programmé. Sans cette lecture, « le texte n'a pas changé » serait vrai
    // d'un composant qu'Alpine n'aurait jamais vu.
    expect($ticks)
        ->toBe('0', "Le compteur de #time-broken-iso vaut [{$ticks}] : Alpine ne l'a pas initialisé, l'assertion ci-dessus ne prouve rien.");
});

it('signale BRUYAMMENT les deux chemins d\'erreur, plutôt que d\'échouer en silence (AC6)', function (): void {
    /*
     * Les deux tests précédents observent les CONSÉQUENCES des gardes. Celui-ci
     * observe leur autre moitié : elles doivent parler. Une garde muette laisse
     * un attribut cassé vivre indéfiniment en production — c'est ce que
     * `console.error` empêche, et rien d'autre ne le prouve.
     *
     * L'espion ne peut pas être posé avant le chargement de la page. On rejoue
     * donc les deux chemins en CLONANT les éléments d'erreur : Alpine initialise
     * les nœuds ajoutés au DOM (MutationObserver), donc les mêmes gardes
     * repassent, sous observation cette fois. Les identifiants sont retirés des
     * clones — deux `id` identiques dans un document, et les sélecteurs des
     * autres tests deviendraient ambigus.
     */
    Streamer::factory()->create();

    $page = visit('/_time');

    $installed = $page->script(<<<'JS'
        (() => {
            window.__consoleErrors = [];
            const original = console.error;
            console.error = (...args) => { window.__consoleErrors.push(args.join(' ')); original(...args); };
            return 'ok';
        })()
        JS);

    expect($installed)
        ->toBe('ok', 'L\'espion sur console.error n\'a pas été posé : l\'assertion suivante serait vide.');

    $replayed = $page->script(<<<'JS'
        (() => {
            const host = document.createElement('div');
            host.id = 'error-replay';
            document.body.appendChild(host);
            for (const id of ['#time-broken-refresh', '#time-broken-iso']) {
                const clone = document.querySelector(id).cloneNode(true);
                clone.removeAttribute('id');
                host.appendChild(clone);
            }
            return String(host.children.length);
        })()
        JS);

    expect($replayed)
        ->toBe('2', 'Les deux chemins d\'erreur n\'ont pas été rejoués.');

    /*
     * ⚠️ ON N'ATTEND QUE LES ERREURS QUI NOUS APPARTIENNENT.
     *
     * La première rédaction attendait `__consoleErrors.length === '2'`, TOUTES
     * erreurs confondues. Une seule `console.error` étrangère — un asset en 404,
     * un avertissement Livewire, une violation CSP — faisait dépasser 2, et le
     * compte n'y revenait jamais : cinq secondes d'attente puis un échec dont le
     * message accusait les gardes. Le filtre existait déjà dix lignes plus bas ;
     * il s'applique désormais AUSSI à l'attente. (Revue du 2026-08-08.)
     *
     * ⚠️ Et il n'y a PAS d'assertion derrière : `waitUntilValue()` lève elle-même
     * si le compte n'arrive pas. La ligne qui suivait comparait son temps de
     * retour à sa propre borne — toujours vraie, avec un message qui parlait
     * d'autre chose.
     */
    $countNamedErrors = "(() => String(window.__consoleErrors.filter((m) => m.includes('<x-time-relative>')).length))()";

    BrowserAssertions::waitUntilValue(
        static fn (): mixed => $page->script($countNamedErrors),
        '2',
        5_000,
        'nombre d\'erreurs console NOMMANT <x-time-relative> (une par garde)',
    );

    /*
     * ⚠️ DEUX ERREURS NE SONT PAS DEUX GARDES.
     *
     * Le compte ci-dessus vaudrait aussi 2 si UNE SEULE garde avait parlé deux
     * fois — c'est-à-dire exactement le scénario « une garde en a désarmé une
     * autre » que toute cette story traque. On vérifie donc que les deux CAUSES
     * distinctes sont nommées, pas seulement qu'il y a deux lignes.
     */
    foreach ([
        'data-time-refresh' => 'la garde sur l\'intervalle n\'a pas parlé',
        'datetime illisible' => 'la garde sur l\'instant n\'a pas parlé',
    ] as $needle => $reproach) {
        $found = $page->script(sprintf(
            "(() => String(window.__consoleErrors.some((m) => m.includes('%s'))))()",
            $needle,
        ));

        expect($found)
            ->toBe('true', "{$reproach} : les deux erreurs comptées viennent peut-être de la même garde.");
    }
});

/*
|--------------------------------------------------------------------------
| AC7 — le côté CLIENT de la table de cas partagée
|--------------------------------------------------------------------------
*/

it('produit en JavaScript exactement les libellés que Carbon produit côté serveur (AC7)', function () use ($freezeClock): void {
    /*
     * LA MOITIÉ CLIENT de l'AC7. L'autre moitié — Carbon produit-il ces
     * libellés ? — vit dans tests/Feature/TimeAsTextureTest.php et lit LA MÊME
     * table. C'est la seule construction où une dérive d'un SEUL côté rougit.
     *
     * Le défaut visé se nomme en une phrase : *le serveur affiche « il y a
     * 1 jour », soixante secondes plus tard le client affiche « hier »*. C'est
     * exactement ce que produit `numeric: 'auto'`, le défaut d'Intl.
     *
     * Les deux formes sont lues AU MÊME INSTANT, sur deux sondes portant le même
     * instant : une seule lecture par cas, donc une seule fenêtre de dérive.
     *
     * Vu rouge côté client SEUL : en passant Intl en `numeric: 'auto'` dans
     * app.js — ce test rougit sur « il y a 1 jour », le test Feature reste vert.
     * Vu rouge côté serveur SEUL : en désactivant l'auto-découverte du provider
     * Laravel de Carbon (`nesbot/carbon` dans `extra.laravel.dont-discover`)
     * — le test Feature rougit, celui-ci reste vert.
     */
    Streamer::factory()->create();

    $page = visit('/_time');

    $freezeClock(static fn (string $js): mixed => $page->script($js));

    $long = RelativeTimeCases::long();
    $short = RelativeTimeCases::short();

    expect($long)
        ->not->toBeEmpty('La table de cas partagée est vide : ce test ne prouverait rien.');

    $probes = ['#time-fast', '#time-fast-short'];

    $readTicks = static fn (string $selector): int => (int) BrowserAssertions::asComputedValue(
        $page->script(BrowserAssertions::dataAttribute($selector, 'data-time-ticks')),
        "compteur de ticks de {$selector}",
    );

    foreach ($long as $seconds => $expectedLong) {
        $expectedShort = $short[$seconds] ?? null;

        expect($expectedShort)
            ->not->toBeNull("La table courte ne couvre pas le cas à {$seconds} s.");

        /*
         * ⚠️ ON RELÈVE LES COMPTEURS AVANT DE POSER L'INSTANT, ET C'EST TOUT
         * L'INTÉRÊT DE CE TEST.
         *
         * La première rédaction attendait simplement que le libellé VAILLE
         * l'attendu. Or DEUX PAIRES de cas consécutifs de la table portent le
         * MÊME libellé (60 s / 90 s → « il y a 1 minute » ; 518400 s / 604740 s
         * → « il y a 6 jours ») : au second des deux, le libellé encore affiché
         * était déjà égal à l'attendu, et l'attente rendait à la PREMIÈRE
         * lecture — sans qu'aucun recalcul client soit garanti. Le cas 90 s,
         * ajouté exprès pour distinguer `Math.floor` de `Math.round`, était
         * précisément celui qui ne pouvait rien garantir.
         *
         * Une sentinelle posée dans le texte ne marcherait pas : quand le
         * libellé recalculé est identique au précédent, Alpine ne réécrit pas le
         * DOM et la sentinelle resterait. Ce qu'il faut observer, c'est le
         * DÉCLENCHEMENT — d'où le compteur, +2 pour être certain qu'un tick a
         * commencé APRÈS la pose et non à cheval sur elle.
         * (Revue du 2026-08-08.)
         */
        $ticksBefore = [];

        foreach ($probes as $probe) {
            $ticksBefore[$probe] = $readTicks($probe);
        }

        $posed = $page->script(sprintf(
            "(() => { const iso = new Date(window.__frozenNow - %d * 1000).toISOString(); "
            . "document.querySelector('#time-fast').setAttribute('datetime', iso); "
            . "document.querySelector('#time-fast-short').setAttribute('datetime', iso); return iso; })()",
            $seconds,
        ));

        expect(is_string($posed) && $posed !== '')
            ->toBeTrue("L'instant à {$seconds} s n'a pas pu être posé sur les sondes.");

        foreach ($probes as $probe) {
            BrowserAssertions::waitUntilAtLeast(
                static fn (): mixed => $page->script(BrowserAssertions::dataAttribute($probe, 'data-time-ticks')),
                $ticksBefore[$probe] + 2,
                5_000,
                "recalcul de {$probe} après avoir posé l'instant à {$seconds} s",
            );
        }

        /*
         * ⚠️ UNE ASSERTION, PAS UNE ATTENTE. Le recalcul est désormais garanti
         * par les compteurs ci-dessus : la comparaison peut donc être FERME.
         * L'ancienne rédaction laissait toute la propriété de l'AC7 reposer sur
         * la branche d'échec d'une aide de test — si celle-ci cessait de lever,
         * ce test devenait une boucle vide et six mutations navigateur
         * survivaient d'un coup.
         */
        $rendered = BrowserAssertions::asComputedValue(
            $page->script(
                "(() => JSON.stringify([document.querySelector('#time-fast').textContent.trim(), "
                . "document.querySelector('#time-fast-short').textContent.trim()]))()",
            ),
            "libellés JS à {$seconds} s",
        );

        expect($rendered)
            ->toBe(
                (string) json_encode([$expectedLong, $expectedShort], JSON_UNESCAPED_UNICODE),
                "Libellés JS à {$seconds} s (longue puis courte) — comparaison OCTET À OCTET : "
                . 'si attendu et lu paraissent identiques, cherche une espace INSÉCABLE (U+00A0), '
                . "c'est la dérive qu'Intl introduit en forme courte.",
            );
    }
});

/*
|--------------------------------------------------------------------------
| AC8 — discipline typographique, observée par valeur calculée
|--------------------------------------------------------------------------
*/

it('rend les 4 composants en mono, à 13 px au moins, en chiffres tabulaires et resserrés (AC8)', function (): void {
    /*
     * ADR-0012 §7 : mono, >= 13 px (« en dessous, les chiffres se ferment à
     * 375 px »), `tabular-nums`, `tracking-tight`, couleur secondaire. Chacune
     * est une VALEUR CALCULÉE : une chaîne de classes ne prouve rien d'un rendu.
     *
     * `text-sm` vaut 14 px et passe ; `text-xs` vaut 12 px et échoue. C'est la
     * mutation qui donne son sens au seuil.
     */
    Streamer::factory()->create();

    $page = visit('/_time');

    $selectors = ['#time-fast', '#time-absolute', '#time-dual', '#time-since'];

    /*
     * ⚠️ LA COULEUR ATTENDUE EST RÉSOLUE DEPUIS LE TOKEN, PAS RECOPIÉE.
     *
     * La première rédaction comparait à `'rgba(255, 255, 255, 0.6)'`, littéral
     * recopié de tokens.css — une seconde source de vérité sur un token, dans la
     * story qui érige la source unique en principe, et à trois lignes d'un test
     * voisin qui prouve la police PAR MUTATION DU TOKEN. Une couleur écrite en
     * dur qui vaudrait la même chose passait. On plante donc une sonde qui, elle,
     * DESCEND du token, et on compare les quatre composants à elle.
     * (Revue du 2026-08-08.)
     */
    $expectedColor = BrowserAssertions::asComputedValue(
        $page->script(
            "(() => { const probe = document.createElement('span'); probe.id = 'token-color-probe'; "
            . "probe.style.color = 'var(--text-secondary)'; document.body.appendChild(probe); "
            . "return String(getComputedStyle(probe).getPropertyValue('color')); })()",
        ),
        'couleur résolue de --text-secondary',
    );

    // Anti-vacuité : une sonde qui ne résout rien retomberait sur le noir hérité
    // et rendrait les quatre comparaisons ci-dessous triviales.
    expect($expectedColor)
        ->not->toBe('rgb(0, 0, 0)', 'La sonde n\'a pas résolu --text-secondary : la comparaison de couleur ne prouverait rien.');

    foreach ($selectors as $selector) {
        $size = BrowserAssertions::asComputedValue(
            $page->script(BrowserAssertions::computed($selector, 'font-size')),
            "taille de police de {$selector}",
        );

        expect((float) $size)
            ->toBeGreaterThanOrEqual(13.0, "{$selector} est rendu à [{$size}] : sous 13 px, les chiffres se ferment à 375 px (ADR-0012 §7).");

        $variant = BrowserAssertions::asComputedValue(
            $page->script(BrowserAssertions::computed($selector, 'font-variant-numeric')),
            "variante numérique de {$selector}",
        );

        expect(str_contains($variant, 'tabular-nums'))
            ->toBeTrue("{$selector} n'est pas en chiffres tabulaires (lu : [{$variant}]) : les chiffres danseraient d'un rafraîchissement à l'autre.");

        $tracking = BrowserAssertions::asComputedValue(
            $page->script(BrowserAssertions::computed($selector, 'letter-spacing')),
            "interlettrage de {$selector}",
        );

        expect((float) $tracking)
            ->toBeLessThan(0.0, "{$selector} a un interlettrage de [{$tracking}] : la mono n'est pas resserrée (tracking-tight).");

        $color = BrowserAssertions::asComputedValue(
            $page->script(BrowserAssertions::computed($selector, 'color')),
            "couleur de {$selector}",
        );

        expect($color)
            ->toBe($expectedColor, "{$selector} est rendu en [{$color}] au lieu de [{$expectedColor}], la couleur que --text-secondary résout dans cette page.");
    }
});

it('fait descendre la police des mentions temporelles du token --font-mono (AC8)', function (): void {
    /*
     * Le test précédent prouve que quelque chose est rendu en mono. Celui-ci
     * prouve D'OÙ ÇA VIENT : un `font-family` écrit en dur passerait le test
     * précédent sans broncher. Muter le token À CHAUD les sépare — c'est la
     * technique de la Story 1.11 sur `--accent-lava`, transposée à la police.
     *
     * ⚠️ Ce test ne prétend PAS qu'IBM Plex Mono est réellement rendu : les
     * woff2 arrivent en Story 1.9, et d'ici là `--font-mono` retombe sur le mono
     * système (tokens.css le dit lui-même). Un AC qui prétendrait mesurer la
     * fonte se validerait aujourd'hui contre du mono système.
     */
    Streamer::factory()->create();

    $page = visit('/_time');

    $selectors = ['#time-fast', '#time-absolute', '#time-dual', '#time-since'];
    $before = [];

    foreach ($selectors as $selector) {
        $before[$selector] = BrowserAssertions::asComputedValue(
            $page->script(BrowserAssertions::computed($selector, 'font-family')),
            "police de {$selector} avant mutation",
        );
    }

    $page->script("(() => { document.documentElement.style.setProperty('--font-mono', 'Times New Roman'); return true; })()");

    foreach ($selectors as $selector) {
        $after = BrowserAssertions::asComputedValue(
            $page->script(BrowserAssertions::computed($selector, 'font-family')),
            "police de {$selector} après mutation",
        );

        expect($after)
            ->not->toBe($before[$selector], "La police de {$selector} n'a pas bougé alors que --font-mono a changé : elle est écrite en dur, elle ne descend pas du token.");
    }
});

it('ne laisse PAS la largeur bouger quand le libellé raccourcit au rafraîchissement (AC8)', function (): void {
    /*
     * ADR-0012 §7, transcrit littéralement : « largeur réservée pour que le
     * refresh Alpine 60 s de <x-time-relative> ne fasse pas tressauter la page ».
     *
     * « il y a 59 minutes » fait 17 caractères, « il y a 1 heure » en fait 14.
     * Sans largeur réservée, la boîte rétrécit d'un coup et décale tout ce qui
     * suit sur la ligne — une fois par minute, sur une page que personne ne
     * touche. C'est la MESURE qui le prouve, pas la classe.
     *
     * Vu rouge : en retirant `min-w-temporal` du composant.
     */
    Streamer::factory()->create();

    $page = visit('/_time');

    $poseAndRead = static function (int $seconds, string $expectedLabel) use ($page): string {
        $page->script(sprintf(
            "(() => { const iso = new Date(Date.now() - %d * 1000).toISOString(); "
            . "document.querySelector('#time-fast').setAttribute('datetime', iso); return iso; })()",
            $seconds,
        ));

        BrowserAssertions::waitUntilValue(
            static fn (): mixed => $page->script(BrowserAssertions::text('#time-fast')),
            $expectedLabel,
            5_000,
            "libellé [{$expectedLabel}] avant mesure de largeur",
        );

        return BrowserAssertions::asComputedValue(
            $page->script(BrowserAssertions::computed('#time-fast', 'width')),
            "largeur de #time-fast à [{$expectedLabel}]",
        );
    };

    $wide = $poseAndRead(3540, 'il y a 59 minutes');
    $narrow = $poseAndRead(3600, 'il y a 1 heure');

    // Anti-vacuité : une largeur nulle rendrait l'égalité ci-dessous triviale.
    expect((float) $wide)
        ->toBeGreaterThan(0.0, 'La largeur mesurée est nulle : la comparaison ne prouverait rien.');

    expect($narrow)
        ->toBe($wide, "La largeur est passée de [{$wide}] à [{$narrow}] au rafraîchissement : la page tressaute.");
});
