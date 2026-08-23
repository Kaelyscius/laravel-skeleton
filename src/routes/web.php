<?php

declare(strict_types=1);

use App\Core\Support\CurrentStreamer;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Route;
use Illuminate\Support\Str;
use Spatie\Health\Checks\Check;
use Spatie\Health\Enums\Status;
use Spatie\Health\Facades\Health;

Route::get('/', function () {
    return view('welcome');
});

/*
 * Galerie des composants de base (Story 1.11, T9) — support des tests navigateur.
 *
 * Les AC1/AC2/AC6 exigent des états observés PAR VALEUR CALCULÉE (hover, active,
 * focus-visible sont des pseudo-états : la présence d'une classe ne prouve rien
 * du rendu). Il faut donc une page réelle que Chromium peut charger.
 *
 * ⚠️ DEUX gardes, et la seconde n'est pas de la ceinture-bretelles.
 *
 *  1. À l'ENREGISTREMENT : la route n'existe pas hors local/testing. Vérifiée
 *     par BladeComponentsTest, qui rejoue ce fichier contre un routeur neuf en
 *     environnement `production` — test VU ROUGE en retirant le `if`.
 *  2. À la REQUÊTE : `php artisan route:cache` fige la table de routage au
 *     moment où il tourne. Un cache construit en local puis déployé embarquerait
 *     la route malgré la garde n°1, et aucun test ne pourrait le voir — c'est
 *     exactement la forme « l'affirmation précède son référent ». Le abort()
 *     ci-dessous est évalué à chaque requête, donc il survit au cache.
 */
if (app()->environment(['local', 'testing'])) {
    Route::get('/_components', function () {
        abort_unless(app()->environment(['local', 'testing']), 404);

        return view('_components-demo', [
            'streamer' => app(CurrentStreamer::class)->streamer(),
        ]);
    })->name('components.demo');

    /*
     * Démonstration des layouts (Story 1.13, T7) — même double garde, et pour
     * les mêmes raisons. Deux pages distinctes plutôt qu'une : l'AC2 est une
     * assertion d'ABSENCE de header et de footer, qui ne veut rien dire sur un
     * document qui en porterait par ailleurs.
     *
     * ⛔ Ces routes ne réutilisent PAS `_components-demo` : les 8 tests
     * navigateur de la Story 1.11 dépendent de son ordre de tabulation.
     */
    Route::get('/_layouts', function () {
        abort_unless(app()->environment(['local', 'testing']), 404);

        return view('_layouts-demo');
    })->name('layouts.demo');

    Route::get('/_layouts-minimal', function () {
        abort_unless(app()->environment(['local', 'testing']), 404);

        return view('_layouts-demo-minimal');
    })->name('layouts.demo.minimal');

    /*
     * Démonstration des composants time-as-texture (Story 1.12, T10) — même
     * double garde, et pour les mêmes raisons.
     *
     * Les instants sont calculés ICI plutôt que dans la vue : une page qui
     * fabrique ses propres données est une page dont on ne sait plus ce qu'elle
     * observe.
     */
    Route::get('/_time', function () {
        abort_unless(app()->environment(['local', 'testing']), 404);

        return view('_time-demo', [
            // Une seconde : c'est ce qui rend le rafraîchissement observable en
            // une seconde plutôt qu'en une minute. Un élément vieux de 59
            // minutes rendrait le MÊME libellé à chaque tick pendant 60 s, et
            // « le texte a changé » ne serait jamais vrai.
            'ticking' => now()
                ->subSeconds(1),
            /*
             * Un instant RÉCENT et lisible pour les deux sondes de chemin
             * d'erreur (#time-broken-refresh, #time-broken-iso) : il faut qu'un
             * recalcul réussi soit distinguable du marqueur serveur, donc un
             * instant que le JS sait formater.
             *
             * ⚠️ Ce n'est PAS le référent de l'AC8 — le commentaire d'origine le
             * disait et c'était faux (relevé à la revue du 2026-08-08). Le test
             * de largeur pose lui-même 3540 s puis 3600 s sur #time-fast et ne
             * lit jamais cette valeur.
             */
            'recent' => now()
                ->subMinutes(59),
            'ancient' => now()
                ->subMonths(7),
            'published' => now()
                ->subMonths(8),
            'updated' => now()
                ->subMonths(2),
        ]);
    })->name('time.demo');

    /*
     * Démonstration des faces self-hostées (Story 1.9, T8) — même double garde.
     *
     * Elle existe parce qu'une face n'est CHARGÉE qu'à son usage : `font-display:
     * swap` ne déclenche le téléchargement qu'au premier élément qui la demande,
     * et le preload seul laisse le statut à `unloaded`. Sans une page qui exerce
     * les quatre faces, l'AC6 n'a rien à observer.
     */
    Route::get('/_fonts', function () {
        abort_unless(app()->environment(['local', 'testing']), 404);

        return view('_fonts-demo');
    })->name('fonts.demo');
}

/**
 * Les conditions `->if()` / `->unless()` d'une sonde tiennent-elles ?
 *
 * ⚠️ Volontairement PAS `Check::shouldRun()` : celui-ci évalue en plus
 * l'expression cron de Spatie, qui n'a aucun sens sur une requête HTTP
 * synchrone (voir le commentaire sur le site d'appel).
 *
 * ⚠️ Cette fonction est déclarée dans un fichier de routes que
 * `Tests\Support\RouteTable` RE-REQUIERT pour éprouver la table de routage en
 * environnement `production`. Elle est donc gardée par `function_exists` —
 * sans quoi le second `require` serait une erreur fatale de redéclaration.
 */
if (! function_exists('healthCheckConditionsHold')) {
    function healthCheckConditionsHold(Check $check): bool
    {
        foreach ($check->getRunConditions() as $condition) {
            $holds = is_callable($condition) ? $condition() : $condition;

            if (! $holds) {
                return false;
            }
        }

        return true;
    }
}

/*
 * ─────────────────────────────────────────────────────────────────────────────
 * `/health` — LES DÉPENDANCES DE L'APPLICATION RÉPONDENT-ELLES ? (Story 2.4)
 *
 * 🔴 CE QUE CETTE ROUTE ÉTAIT, ET POURQUOI C'ÉTAIT LE PIRE DES DÉFAUTS.
 * Jusqu'au 2026-08-23 elle rendait un JSON LITTÉRAL — mesuré : `200`, 93 octets,
 * `{"status":"ok",…}` — sans exécuter la moindre sonde. Elle répondait donc `ok`
 * la base à terre. Un nightly bloquant qui aurait asserté `200` dessus n'aurait
 * JAMAIS PU ROUGIR : le garde-fou vert qui ne garde rien, dans le rôle où il
 * coûte le plus cher.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * CE QUE LA ROUTE ATTESTE
 *
 *   Les dépendances déclarées (base, cache, file) RÉPONDENT à un aller-retour
 *   réel, à l'instant de la requête.
 *
 * CE QU'ELLE N'ATTESTE PAS — et la liste est ici parce qu'elle sera relue :
 *
 *   • que le framework boote — c'est le rôle de `/up` (`bootstrap/app.php:13`),
 *     qui reste la sonde de LIVENESS. MESURÉ le 2026-08-23, conteneur postgres
 *     réellement arrêté : `/up` rend **200 en 0,073 s** — il ne dit donc RIEN
 *     de la base, ce qui est exactement son contrat.
 *     ⚠️ UNE PREMIÈRE MESURE DONNAIT **27 s** POUR CE MÊME `200`, et la cause
 *     n'était pas `/up` : `.env` déclarait `CACHE_DRIVER` là où Laravel 11+ lit
 *     `CACHE_STORE`, donc cache ET sessions retombaient sur le pilote
 *     `database` et TOUTE requête traversait la base morte. Corriger la clé
 *     (revue 1) a fait tomber la mesure de 27 s à 0,073 s. Le « surcoût
 *     pré-existant » qu'on s'apprêtait à consigner comme dette n'existait pas :
 *     c'était le même défaut, vu par un autre bout ;
 *   • qu'un worker traite des jobs : `queue: ok` cohabite avec zéro worker
 *     (cf. le docblock de `QueueHealthCheck`, et le refus explicite du
 *     `QueueCheck` de Spatie) ;
 *   • que le domaine est sain : aucune règle métier n'est évaluée ici ;
 *   • que les migrations sont à jour.
 *
 * ⚖️ DEUX DÉFINITIONS COEXISTENT DONC, CHACUNE AVEC SON DOMAINE ÉNONCÉ :
 * `/up` = « le framework boote », `/health` = « ses dépendances répondent ».
 * Epic 3 tranchera laquelle devient le healthcheck des CONTENEURS. Aujourd'hui,
 * mesuré : `docker-compose.yml:23` interroge `/up` (apache) et `:57` exécute
 * `healthcheck.php` (php) — aucun consommateur de `/health`. Le nightly de la
 * story 2.4 en est le PREMIER.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * ⛔ HORS DU GROUPE `web`, ET CE N'EST PAS UN DÉTAIL
 *
 * `withoutMiddleware('web')` retire les middlewares du groupe pour CETTE route
 * (le routeur résout l'alias de groupe en ses membres avant de les exclure).
 * Sans cela, `StartSession` s'exécuterait AVANT le contrôleur : avec
 * `SESSION_DRIVER=redis` — la valeur du `.env` de développement — un Redis à
 * terre ferait lever la session et rendrait **500**, pas `503`. La sonde de
 * dépendances aurait alors échoué à cause de la dépendance qu'elle est censée
 * DIAGNOSTIQUER, en rendant un code qui ne dit pas « dépendance en panne » mais
 * « bug applicatif ». Gardé par `HealthEndpointTest`.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * ⚠️ NI AUTHENTIFIÉE, NI LIMITÉE EN DÉBIT — SU, PESÉ, ET REPORTÉ
 *
 * Chaque requête déclenche un aller-retour vers chacune des trois dépendances,
 * et la réponse publie les latences par sonde. C'est une surface
 * d'amplification et une fuite de topologie modestes, relevées en revue 1.
 *
 * ⛔ LA PARADE ÉVIDENTE EST PIRE QUE LE MAL, ET C'EST LA RAISON DU REPORT :
 * `throttle:` s'appuie sur le `RateLimiter`, donc sur le MAGASIN DE CACHE.
 * Poser un throttle ici ferait rendre **500** à `/health` quand le cache est à
 * terre — soit exactement la classe de défaut que cette story existe pour
 * supprimer, réintroduite par sa propre protection. Et épingler
 * `cache.limiter` sur un magasin indépendant changerait la sémantique de
 * limitation de TOUTES les routes de l'application (limites par conteneur au
 * lieu de partagées), ce qui dépasse ce mandat.
 * → Report ouvert dans `_bmad-output/implementation-artifacts/deferred-work.md`,
 *   déclencheur Epic 3, qui tranche la sémantique de `/health`.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * ⛔ ZÉRO SONDE ENREGISTRÉE ⇒ `503`, JAMAIS `200`
 *
 * Une boucle `foreach` sur une collection vide laisse `$healthy` à `true` : la
 * route rendrait `200` avec `"checks": {}`. C'est la VACUITÉ — exactement la
 * forme de vert-qui-ne-garde-rien que cette story existe pour supprimer, et
 * elle se produirait au pire moment (un `AppServiceProvider` cassé). Le refus
 * est explicite ci-dessous et il est mutation-testé.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * ⏱️ CE QUI BORNE RÉELLEMENT LA RÉPONSE — TOUT EST MESURÉ, RIEN N'EST DÉDUIT
 *
 * 🔴 LA PREMIÈRE VERSION DE CETTE ROUTE NE RENDAIT PAS `503` SUR UNE BASE
 * MORTE : ELLE NE RENDAIT RIEN. Mesuré le 2026-08-23, conteneur postgres
 * réellement arrêté, une requête seule sur une pile au repos :
 *
 *     curl -m 90 https://localhost/health   →  504 d'Apache à 60 s, 0 octet
 *     noyau HTTP instrumenté, en conteneur  →  503 correct, mais à 89 s
 *       database 31,1 s · cache 31,0 s · queue ~27 s · terminate 25,5 s
 *
 * Décomposition, mesurée elle aussi : `gethostbyname('postgres')` coûte
 * **3,13 s** quand le conteneur est arrêté (l'alias ne résout plus, le
 * résolveur laisse expirer), et le framework REJOUE la connexion — ~10
 * tentatives par sonde. `SET statement_timeout = 2000` n'y peut rien : il borne
 * l'exécution d'une requête sur une connexion ÉTABLIE.
 *
 * ⛔ ET `PDO::ATTR_TIMEOUT` NON PLUS — ESSAYÉ, MESURÉ, RETIRÉ. Un `new PDO(…)`
 * nu échoue en 3,13 s que le timeout vaille 2, 5 ou rien : le coût est la
 * RÉSOLUTION DE NOM, que ni libpq ni PDO ne bornent. La ligne de configuration
 * qui l'ajoutait a été retirée plutôt que gardée avec un commentaire faux.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * CE QUI BORNE, AUJOURD'HUI, ET DANS CET ORDRE
 *
 *   1. LE PORTILLON PAR SONDE (`App\HealthChecks\Support\BackendEndpoint`) —
 *      UNE connexion TCP bornée avant l'aller-retour applicatif. C'est lui qui
 *      fait tomber le facteur ×10. ⚠️ Ajouté en revue 1 : le budget ci-dessous
 *      n'est évalué qu'ENTRE les sondes, donc la PREMIÈRE tournait sans borne
 *      et consommait les 58 s à elle seule — une violation directe de la ligne
 *      « sonde lente » de la matrice, pas une omission.
 *   2. LE BUDGET CUMULÉ ci-dessous : une fois dépassé, les sondes restantes ne
 *      sont pas lancées et sont rapportées en échec explicite. La réponse est
 *      ainsi bornée à « une sonde qui déborde », pas à leur somme.
 *   3. `SET statement_timeout = 2000` (`DatabaseHealthCheck`), une fois la
 *      connexion établie.
 *   4. `duration_ms` par sonde : une dépendance qui PEND est LUE dans la
 *      réponse, pas devinée.
 *
 * APRÈS LE PORTILLON, MÊME PANNE, MÊME PILE — mesure finale du 2026-08-23,
 * conteneur postgres réellement arrêté, **php-fpm redémarré** :
 *
 *     503, corps complet : 4,05 s · 3,19 s · 3,21 s      (jamais de 504)
 *     conteneur redis arrêté :  10,45 · 9,64 · 9,61 s    (deux portillons)
 *
 * ⛔ « PHP-FPM REDÉMARRÉ » N'EST PAS UNE PRÉCAUTION DE STYLE. Une mesure HTTP
 * prise juste après avoir édité ce code lit l'ANCIENNE version : l'opcache des
 * workers ne l'avait pas reprise, et les mêmes requêtes rendaient **15 à 16 s**
 * avec le résumé « Failed » — c'est-à-dire sans portillon — pendant que le CLI,
 * qui recharge à chaque appel, rendait 3,1 s. Deux réponses pour un seul code.
 * Toute mesure `curl` de ce fichier exige donc un redémarrage préalable.
 *
 * ⚠️ CE QUI N'EST TOUJOURS PAS BORNÉ, ET QUI DOIT ÊTRE SU : le coût UNITAIRE
 * d'une résolution de nom en échec (~3,1 s ici). PHP ne peut pas l'interrompre
 * (`pcntl` est indisponible sous FPM). Le portillon borne le NOMBRE de
 * tentatives, pas leur durée. Le client du nightly pose de toute façon son
 * propre `--max-time`, et le test E2E asserte 45 s — sous le délai de
 * passerelle d'Apache, mesuré à 60 s.
 *
 */
Route::get('/health', function () {
    /*
     * Budget CUMULÉ des sondes, en millisecondes.
     *
     * Une fois le budget dépassé, les sondes restantes ne sont PAS lancées et
     * sont rapportées `error` / « non exécutée » — jamais omises, jamais `ok`.
     * La réponse reste donc à trois clés (exigence de la matrice) tout en étant
     * bornée (autre exigence de la matrice) : le lecteur voit ce qui a été
     * mesuré ET ce qui ne l'a pas été, ce qu'un timeout HTTP ne lui dit pas.
     *
     * ⚠️ LE DÉFAUT VIT DANS LE CODE, PAS SEULEMENT DANS LA CONFIGURATION —
     * et la justification de la première rédaction était FAUSSE (relevé en
     * revue 1) : elle invoquait une republication de `config/health.php` par
     * `scripts/install/35-configure-spatie-packages.sh`, qui ne publie en
     * réalité QUE si le fichier est absent (`if [ ! -f config/health.php ]`),
     * et il est versionné. Le vrai motif est plus simple et se mesure : une
     * clé absente, vide, non numérique, nulle ou NÉGATIVE donnerait une
     * échéance déjà dépassée, donc un `/health` qui ne sonde plus rien et
     * rend `503` à perpétuité sans nommer la moindre panne. Le littéral est
     * le plancher de sûreté, et `HealthEndpointTest` retire la clé pour le
     * vérifier.
     */
    $configuredBudget = config('health.probe_budget_ms');
    $probeBudgetMs = is_numeric($configuredBudget) && (float) $configuredBudget > 0
        ? (int) $configuredBudget
        : 5_000;
    $deadline = hrtime(true) + ($probeBudgetMs * 1_000_000);

    /*
     * ⚖️ CORRESPONDANCE DES STATUTS DE SPATIE, ÉCRITE PLUTÔT QU'IMPLICITE.
     *
     * La première rédaction écrasait TOUT ce qui n'était pas `ok` en `error` :
     * `warning` (dégradé mais servable) et `skipped` (non applicable ici et
     * maintenant) devenaient indiscernables d'une panne, et
     * `health.treat_skipped_as_failure` — que Spatie livre — était inerte.
     * Chaque statut est désormais publié tel quel, et seul le caractère FATAL
     * est décidé ici.
     */
    $fatal = static function (Status $status): bool {
        if ($status->equals(Status::skipped())) {
            $configured = config('health.treat_skipped_as_failure');

            return ! is_bool($configured) || $configured;
        }

        return ! $status->equals(Status::ok()) && ! $status->equals(Status::warning());
    };

    $checks = [];
    $healthy = true;

    foreach (Health::registeredChecks() as $check) {
        $key = Str::snake($check->getName());

        /*
         * ⛔ COLLISION DE CLÉ ⇒ ÉCHEC BRUYANT, JAMAIS ÉCRASEMENT SILENCIEUX.
         * `Str::snake()` n'est pas injective : « MonCheck » et « mon_check »
         * donnent la même clé. Spatie interdit les noms EXACTEMENT dupliqués,
         * pas les noms qui se rejoignent après normalisation — le second
         * effaçait donc le premier, et `/health` rendait `200` en ayant perdu
         * une sonde en route.
         */
        if (array_key_exists($key, $checks)) {
            $healthy = false;
            $checks[$key] = [
                'status' => 'error',
                'summary' => "Collision de clé : deux sondes se normalisent en « {$key} »",
                'duration_ms' => null,
            ];

            continue;
        }

        /*
         * ⛔ LES CONDITIONS `->if()` / `->unless()` SONT ÉVALUÉES ICI, MAIS PAS
         * LA PLANIFICATION CRON — ET C'EST LA DIFFÉRENCE QUI COMPTE.
         *
         * 🔴 La rédaction précédente appelait `$check->shouldRun()`, qui
         * évalue AUSSI l'expression cron de Spatie (`Check::$expression`,
         * `* * * * *` par défaut). Conséquence : une sonde déclarée `->hourly()`
         * — parfaitement légitime pour le planificateur — aurait fait rendre
         * **503** à cet endpoint 59 minutes sur 60. Relevé en revue 2.
         *
         * La planification appartient au `schedule:run` de Spatie, pas à une
         * requête HTTP synchrone : ici, « maintenant » est toujours le bon
         * moment. Seules les conditions explicites de l'auteur sont honorées,
         * et `getRunConditions()` les expose sans la partie cron.
         */
        if (! healthCheckConditionsHold($check)) {
            $status = Status::skipped();
            $healthy = $healthy && ! $fatal($status);
            $checks[$key] = [
                'status' => (string) $status,
                'summary' => 'Non applicable : une condition ->if()/->unless() de la sonde est fausse',
                'duration_ms' => null,
            ];

            continue;
        }

        if (hrtime(true) >= $deadline) {
            // ⛔ NON EXÉCUTÉE ⇒ EN ÉCHEC. Une sonde qu'on n'a pas jouée ne
            // témoigne de rien ; la compter comme saine serait la vacuité que
            // toute cette route existe pour supprimer.
            $healthy = false;
            $checks[$key] = [
                'status' => 'error',
                'summary' => "Non exécutée : budget cumulé de {$probeBudgetMs} ms dépassé par les sondes précédentes",
                'duration_ms' => null,
            ];

            continue;
        }

        $startedAt = hrtime(true);

        try {
            $result = $check->run();
        } catch (Throwable $e) {
            /*
             * Une sonde qui LÈVE est une sonde en échec, pas une sonde absente.
             * 🔒 Et elle laisse une trace : la première rédaction avalait
             * l'exception sans un mot, donc une sonde cassée était
             * indiscernable d'une dépendance en panne dans les journaux.
             * Classe + nom de sonde seulement — jamais le message, qui porte
             * les points de connexion.
             */
            Log::error('Health check crashed', [
                'check' => $check->getName(),
                'type' => $e::class,
            ]);

            $result = $check->markAsCrashed();
        }

        $status = $result->status;
        $isFatal = $fatal($status);
        $healthy = $healthy && ! $isFatal;

        $checks[$key] = [
            'status' => $status->equals(Status::ok()) ? 'ok' : ($isFatal ? 'error' : (string) $status),
            'summary' => $result->getShortSummary(),
            'duration_ms' => (int) round((hrtime(true) - $startedAt) / 1_000_000),
        ];
    }

    if ($checks === []) {
        $healthy = false;
        $checks['_no_checks_registered'] = [
            'status' => 'error',
            'summary' => 'Aucune sonde enregistrée — Health::checks() n\'a jamais été appelé',
            'duration_ms' => 0,
        ];
    }

    return response()->json([
        'status' => $healthy ? 'ok' : 'error',
        'timestamp' => now()
            ->toISOString(),
        'service' => 'laravel',
        'app' => config('app.name', 'Laravel'),
        'attests' => 'dependency reachability at request time — NOT framework boot (see /up), NOT job processing, NOT domain health',
        'checks' => $checks,
    ], $healthy ? 200 : 503);
})->name('health')
    ->withoutMiddleware('web');
