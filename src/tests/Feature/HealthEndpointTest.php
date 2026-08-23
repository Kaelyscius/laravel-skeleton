<?php

declare(strict_types=1);

use App\HealthChecks\CacheHealthCheck;
use App\HealthChecks\DatabaseHealthCheck;
use App\HealthChecks\QueueHealthCheck;
use Illuminate\Log\LogManager;
use Illuminate\Routing\Route as RoutingRoute;
use Illuminate\Routing\Router;
use Illuminate\Session\Middleware\StartSession;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Route;
use Spatie\Health\Checks\Check;
use Spatie\Health\Checks\Result;
use Spatie\Health\Enums\Status;
use Spatie\Health\Facades\Health;
use Tests\Support\HealthProbe;
use Tests\Support\UnreachableBackends;

/*
|------------------------------------------------------------------------------
| `/health` — Story 2.4
|------------------------------------------------------------------------------
|
| ⚠️ AUCUN TEST DE CE FICHIER NE SE SATISFAIT D'UN CODE HTTP SEUL, et c'est
| l'AC de la story : le sujet est précisément un endpoint qui rendait `200` en
| TOUTE circonstance. Chaque cas dégradé assert donc le PASSAGE À 503 — pas la
| présence d'une clé, pas un corps « non vide ».
|
| Les dégradations sont RÉELLES (`Tests\Support\UnreachableBackends`) : un port
| fermé, un magasin qui n'écrit rien. Pas un mock. Un
| `Cache::shouldReceive()->andThrow()` prouverait que la sonde attrape
| l'exception qu'on lui a soufflée, ce qui n'est pas la question posée.
|
| Les requêtes passent par `Tests\Support\HealthProbe` (donc `HttpProbe`, donc
| le noyau HTTP réel) : `$this->getJson()` dans une closure Pest produit 43
| erreurs PHPStan au niveau 10 — mesuré sur la première rédaction de ce
| fichier — et le ratchet du projet est à 0.
|
*/

/**
 * Récupère une route par son URI, TYPÉE.
 *
 * `RouteCollection::getByName()` rend `Route|null`, ce que
 * `gatherRouteMiddleware()` refuse au niveau 10 — même motif que
 * `HttpProbe::livewireUpdateUri()`, qui passe par `getRoutes()->getRoutes()`
 * pour la même raison.
 */
function healthTestRouteByUri(string $uri): RoutingRoute
{
    foreach (app(Router::class)->getRoutes()->getRoutes() as $route) {
        if ($route->uri() === $uri) {
            return $route;
        }
    }

    throw new RuntimeException("Route « {$uri} » absente de la table de routage.");
}

it('rend 200 et les trois sondes à ok quand l’application est saine', function (): void {
    $probe = HealthProbe::probe();

    expect($probe->status)
        ->toBe(200);
    expect($probe->overallStatus())
        ->toBe('ok');
    expect($probe->checkKeys())
        ->toBe(['database', 'cache', 'queue']);
    expect($probe->checkStatus('database'))
        ->toBe('ok');
    expect($probe->checkStatus('cache'))
        ->toBe('ok');
    expect($probe->checkStatus('queue'))
        ->toBe('ok');
});

it('passe à 503 quand la BASE est injoignable, et rapporte quand même les trois sondes', function (): void {
    UnreachableBackends::asDefaultDatabase();

    $probe = HealthProbe::probe();

    // ⛔ L'ASSERTION EST LE PASSAGE À 503. Le test précédent a établi que la
    // même route rend 200 sur une pile saine : les deux ensemble interdisent
    // un endpoint constant, dans un sens comme dans l'autre.
    expect($probe->status)
        ->toBe(503);
    expect($probe->overallStatus())
        ->toBe('error');
    expect($probe->checkStatus('database'))
        ->toBe('error');

    // Les deux autres restent RAPPORTÉES (matrice de la story) : la route ne
    // s'arrête pas à la première panne.
    expect($probe->checkKeys())
        ->toBe(['database', 'cache', 'queue']);
});

it('passe à 503 quand le CACHE est injoignable, la base restant saine', function (): void {
    UnreachableBackends::asDefaultCache();

    $attempts = 0;
    DB::connection(UnreachableBackends::NAME)
        ->setPdo(function () use (&$attempts): never {
            $attempts++;

            throw new PDOException('SQLSTATE[08006]: connection refused');
        });

    $probe = HealthProbe::probe();

    expect($probe->status)
        ->toBe(503);
    expect($probe->checkStatus('cache'))
        ->toBe('error');

    // ⛔ ET C'EST LE PORTILLON QUI A COUPÉ, pas le pilote après une tempête de
    // reconnexions. Sans cette assertion, retirer le portillon de la sonde
    // cache laisse le test VERT — le pilote lèverait de toute façon, et le
    // garde-fou de bornage disparaîtrait en silence.
    //
    // ⚖️ L'OBSERVABLE EST LE COMPTEUR, PAS LE LIBELLÉ (revue 2) : une
    // assertion sur le résumé disparaît avec un renommage. Le magasin dégradé
    // roule sur le pilote `database`, donc son pilote est un PDO — qu'on
    // remplace par un compteur.
    expect($attempts)
        ->toBe(0);

    // Anti-vacuité : si la base tombait aussi, le 503 ne dirait rien du cache.
    expect($probe->checkStatus('database'))
        ->toBe('ok');
});

it('passe à 503 quand le cache ACCEPTE l’écriture sans jamais rendre la valeur', function (): void {
    // 🔴 LE CAS QUI FAIT DE LA COMPARAISON UN GARDE. Un backend injoignable
    // fait LEVER le pilote : la sonde serait rouge même sans comparer quoi que
    // ce soit. Ici le magasin répond, accepte, et ne conserve rien — un Redis
    // en MISCONF, un répertoire de cache repassé en lecture seule. Sans ce
    // test, retirer la comparaison de `CacheHealthCheck` laisse la suite verte.
    UnreachableBackends::asAmnesiacCache();

    $probe = HealthProbe::probe();

    expect($probe->status)
        ->toBe(503);
    expect($probe->checkStatus('cache'))
        ->toBe('error');
    expect($probe->checkStatus('database'))
        ->toBe('ok');
});

it('passe à 503 quand la FILE est injoignable, la base restant saine', function (): void {
    UnreachableBackends::asDefaultQueue();

    $attempts = 0;
    DB::connection(UnreachableBackends::NAME)
        ->setPdo(function () use (&$attempts): never {
            $attempts++;

            throw new PDOException('SQLSTATE[08006]: connection refused');
        });

    $probe = HealthProbe::probe();

    expect($probe->status)
        ->toBe(503);
    expect($probe->checkStatus('queue'))
        ->toBe('error');

    // Même raison que pour le cache, et même observable : le COMPTEUR.
    expect($attempts)
        ->toBe(0);

    expect($probe->checkStatus('database'))
        ->toBe('ok');
});

it('ne laisse JAMAIS fuiter le point de connexion d’un backend mort', function (): void {
    // 🔒 Le message d'une `PDOException` embarque l'hôte et le port. Les trois
    // sondes ne journalisent que la CLASSE de l'exception et une clé de
    // configuration ; le corps public ne porte que des résumés écrits ici.
    UnreachableBackends::asDefaultDatabase();

    // ⛔ ANTI-VACUITÉ, ET ELLE EST INDISPENSABLE : sans elle, ce test resterait
    // vert si le pilote avait cessé de mettre l'hôte dans son message. On
    // ÉTABLIT d'abord que la fuite est réelle, ensuite seulement qu'elle est
    // scrubée.
    $leaked = '';

    try {
        DB::connection(UnreachableBackends::NAME)
            ->select('SELECT 1');
    } catch (Throwable $e) {
        $leaked = $e->getMessage();
    }

    expect($leaked)
        ->toContain('127.0.0.1');
    expect($leaked)
        ->toContain('SQLSTATE');

    $probe = HealthProbe::probe();

    expect($probe->body)
        ->not->toContain('127.0.0.1');
    expect($probe->body)
        ->not->toContain('SQLSTATE');
    expect($probe->body)
        ->not->toContain(UnreachableBackends::SENTINEL_PASSWORD);
});

it('refuse de rendre 200 quand AUCUNE sonde n’est enregistrée', function (): void {
    // 🔴 LA VACUITÉ EST LE DÉFAUT QUE CETTE STORY EXISTE POUR SUPPRIMER.
    // Une boucle `foreach` sur une collection vide laisse le verdict à « sain » :
    // la route rendrait `200` avec `"checks": {}` — un garde-fou vert qui ne
    // garde rien, et précisément au moment où il faut hurler (un
    // `AppServiceProvider` cassé, un module désactivé par erreur).
    Health::clearChecks();

    $probe = HealthProbe::probe();

    expect($probe->status)
        ->toBe(503);
    expect($probe->overallStatus())
        ->toBe('error');
});

it('traite une sonde qui LÈVE comme une sonde en échec, pas comme une sonde absente', function (): void {
    Health::clearChecks();
    Health::checks([
        new class() extends Check {
            public function run(): Result
            {
                throw new RuntimeException('sonde explosive');
            }
        },
    ]);

    $probe = HealthProbe::probe();

    expect($probe->status)
        ->toBe(503);
    expect($probe->overallStatus())
        ->toBe('error');
});

it('rapporte en ÉCHEC EXPLICITE les sondes que le budget n’a pas laissé jouer', function (): void {
    // ⛔ « NON EXÉCUTÉE » N'EST PAS « SAINE ». Sans cette assertion, la branche
    // de dépassement pourrait laisser le verdict à `ok` et rendre 200 sur une
    // application dont deux dépendances sur trois n'ont jamais été interrogées.
    //
    // Le budget est poussé à 1 ms plutôt que de faire dormir la suite cinq
    // secondes : c'est la MÊME branche, franchie au même endroit.
    config([
        'health.probe_budget_ms' => 1,
    ]);

    Health::clearChecks();
    Health::checks([
        (new class() extends Check {
            public function run(): Result
            {
                usleep(20_000);

                return Result::make()
                    ->ok();
            }
        })->name('lente'),
        (new class() extends Check {
            public function run(): Result
            {
                return Result::make()
                    ->ok();
            }
        })->name('jamais_jouee'),
    ]);

    $probe = HealthProbe::probe();

    expect($probe->status)
        ->toBe(503);

    // La première a bien tourné — sinon le test ne dirait rien du dépassement.
    expect($probe->checkStatus('lente'))
        ->toBe('ok');

    // La seconde est rapportée, en échec, et se NOMME comme non exécutée.
    expect($probe->hasCheck('jamais_jouee'))
        ->toBeTrue();
    expect($probe->checkStatus('jamais_jouee'))
        ->toBe('error');
    expect($probe->checkDurationMs('jamais_jouee'))
        ->toBeNull();
    expect($probe->checkSummary('jamais_jouee'))
        ->toContain('Non exécutée');
});

it('publie les trois clés sous leur nom PUBLIC, indépendamment du nom de classe', function (): void {
    // Les noms sont posés explicitement dans `AppServiceProvider` : sans eux,
    // `Check::getName()` dériverait `DatabaseHealthCheck` en `DatabaseHealth`
    // et la clé publique deviendrait `database_health`. Ce test gèle le
    // CONTRAT de la réponse contre un simple renommage de classe.
    expect(Health::registeredChecks()->map(fn (Check $check): string => $check->getName())->all())
        ->toBe(['database', 'cache', 'queue']);

    expect(Health::registeredChecks()->map(fn (Check $check): string => $check::class)->all())
        ->toBe([DatabaseHealthCheck::class, CacheHealthCheck::class, QueueHealthCheck::class]);
});

it('est exclue de l’enregistrement Telescope', function (): void {
    /*
     * 🔴 MESURÉ, PAS SUPPOSÉ (revue 2). Telescope enregistre chaque requête,
     * chaque requête SQL et chaque interaction de cache — donc, sur `/health`,
     * il rejoue vers les dépendances que la route vient de déclarer
     * INJOIGNABLES, hors du portillon et hors du budget de sonde.
     *
     * Conteneur redis réellement arrêté, bascule des drapeaux, noyau HTTP dans
     * le conteneur php :
     *
     *   TELESCOPE=on  PULSE=on   13,77 s        TELESCOPE=off PULSE=on   6,39 s
     *   TELESCOPE=on  PULSE=off  12,91 s        TELESCOPE=off PULSE=off  6,39 s
     *
     * Telescope pesait ~6,5 s. Effet de l'exclusion sur de vraies requêtes
     * HTTP : 13,74 / 12,86 s → 9,59 / 9,61 s.
     *
     * ⚠️ CE TEST GARDE LA CONFIGURATION, PAS LA LATENCE. Une assertion
     * temporelle serait bruyante et dépendante de la machine ; celle-ci rougit
     * si quelqu'un retire l'entrée en « rangeant » la liste.
     */
    expect(config('telescope.ignore_paths'))
        ->toBeArray()
        ->toContain('health');

    // Anti-vacuité : la liste existe et porte déjà d'autres entrées, donc
    // l'assertion ci-dessus ne passe pas par accident sur un tableau vide.
    expect(config('telescope.ignore_paths'))
        ->toContain('pulse*');
});

it('est servie HORS du groupe web — StartSession ne s’exécute pas', function (): void {
    // ⛔ SANS CETTE EXCLUSION, `/health` RENDRAIT 500 AU LIEU DE 503 SUR UNE
    // PANNE DE SESSION. Avec `SESSION_DRIVER=redis` — la valeur du .env de
    // développement — un Redis à terre ferait lever `StartSession` AVANT le
    // contrôleur : la sonde de dépendances échouerait à cause de la dépendance
    // qu'elle est censée diagnostiquer, en rendant un code qui dit « bug
    // applicatif » et non « dépendance en panne ».
    Route::middleware('web')
        ->get('/_health_web_canary', fn (): string => 'canary');

    $router = app(Router::class);

    // Anti-vacuité : le canari PROUVE que `StartSession` est bien dans le
    // groupe `web` de cette application. Sans lui, l'assertion du dessous
    // serait vraie même si le groupe était vide.
    expect($router->gatherRouteMiddleware(healthTestRouteByUri('_health_web_canary')))
        ->toContain(StartSession::class);
    expect($router->gatherRouteMiddleware(healthTestRouteByUri('health')))
        ->not->toContain(StartSession::class);
});

it('répond encore quand le magasin de SESSION est mort', function (): void {
    UnreachableBackends::asDefaultSession();

    // Les dépendances de `/health` sont saines : le verdict doit rester 200.
    // S'il retombait à 500, c'est que la session s'exécute sur cette route.
    expect(HealthProbe::probe()->status)
        ->toBe(200);
});

it('coupe AVANT le pilote quand l’hôte de la base ne résout pas — UNE tentative devient ZÉRO', function (): void {
    /*
     * 🔴 CE TEST A ÉTÉ RÉÉCRIT EN REVUE 2, ET LA RAISON EST LA MÊME QUE CELLE
     * QUI L'AVAIT FAIT NAÎTRE EN REVUE 1 : il n'observait pas ce qu'il
     * prétendait observer.
     *
     * Sa première rédaction assertait une DURÉE (`< 15 s`) et une SOUS-CHAÎNE
     * de résumé (« portillon »). Mesuré : avec le portillon **38 ms**, sans
     * **506 ms** — l'assertion temporelle passait dans les deux cas avec 30×
     * de marge. Seul le LIBELLÉ faisait rougir : renommer le résumé emportait
     * la couverture avec lui.
     *
     * ⛔ ET LE DOCBLOCK AFFIRMAIT UNE MESURE FAUSSE. Il disait que cet hôte
     * coûte « le délai du résolveur, 3,13 s ». Remesuré le 2026-08-23 dans le
     * conteneur php, `fsockopen(…, 2.0)` :
     *
     *     health-probe.nowhere.invalid   0,0149 s   ← NXDOMAIN immédiat (RFC 2606)
     *     postgres-arrete-fictif         2,5247 s   ← nom NON qualifié, liste de recherche
     *     postgres (conteneur arrêté)    3,13   s   ← le vrai mode de panne
     *     127.0.0.1:1                    0,0001 s   ← ECONNREFUSED
     *
     * Un TLD réservé répond NXDOMAIN tout de suite : c'est le chemin RAPIDE,
     * pas le lent. L'horloge n'est donc un observable fiable dans AUCUN
     * environnement — et surtout pas sur un runner GitHub.
     *
     * ⚖️ L'OBSERVABLE EST LE NOMBRE DE TENTATIVES D'OUVERTURE DE PDO, comme
     * dans `DatabaseHealthCheckTest` : déterministe, indépendant de l'horloge
     * et du libellé, et déjà éprouvé dans ce dépôt. C'est aussi la GRANDEUR
     * QUE LE PORTILLON BORNE — il ne raccourcit pas une résolution, il
     * supprime les ~10 tentatives que le framework enchaînait.
     *
     * Anti-vacuité du compteur : `DatabaseHealthCheckTest` l'exerce dans
     * l'autre sens (hôte joignable, portillon franchi ⇒ le compteur monte
     * à 1). Un compteur qui vaudrait 0 parce que rien ne PEUT s'ouvrir ne
     * mesurerait rien.
     */
    UnreachableBackends::asUnresolvableDatabase();

    $attempts = 0;
    DB::connection(UnreachableBackends::UNRESOLVABLE)
        ->setPdo(function () use (&$attempts): never {
            $attempts++;

            throw new PDOException('SQLSTATE[08006]: connection refused');
        });

    $probe = HealthProbe::probe();

    expect($probe->status)
        ->toBe(503);
    expect($probe->checkStatus('database'))
        ->toBe('error');

    // ⛔ LE GARDE : le pilote n'a JAMAIS été sollicité. Retirer
    // `refuseIfUnreachable` de `DatabaseHealthCheck` fait monter ce compteur.
    expect($attempts)
        ->toBe(0);

    // Les deux autres tournent quand même : le budget n'a pas été consommé.
    expect($probe->checkStatus('cache'))
        ->toBe('ok');
    expect($probe->checkStatus('queue'))
        ->toBe('ok');
});

it('désarme le portillon quand la configuration le demande — et RIEN d’autre ne le désarme', function (): void {
    // ⚖️ La porte de sortie existe pour UN cas nommé : un hôte à plusieurs
    // enregistrements A, où `fsockopen()` n'essaie qu'une adresse. Ce test
    // vérifie qu'elle fonctionne ET qu'elle est bien fermée par défaut.
    UnreachableBackends::asDefaultDatabase();

    $attempts = 0;
    DB::connection(UnreachableBackends::NAME)
        ->setPdo(function () use (&$attempts): never {
            $attempts++;

            throw new PDOException('SQLSTATE[08006]: connection refused');
        });

    config([
        'health.probe_gate_enabled' => false,
    ]);

    expect(HealthProbe::probe()->status)
        ->toBe(503);

    // Portillon désarmé ⇒ le pilote EST sollicité. Sans cette assertion, le
    // drapeau pourrait ne rien faire et le test resterait vert.
    expect($attempts)
        ->toBeGreaterThan(0);
});

it('retombe sur son budget codé en dur quand la configuration est absente ou hostile', function (): void {
    // ⛔ `0`, `-1` et `null` donnent une échéance DÉJÀ dépassée : sans plancher,
    // `/health` cesserait de sonder quoi que ce soit et rendrait `503` à
    // perpétuité en ne nommant aucune panne réelle. La clé est aussi RETIRÉE —
    // la revue 1 a relevé qu'aucun test ne l'éprouvait.
    foreach ([null, 0, -1, '', 'beaucoup'] as $hostile) {
        config([
            'health.probe_budget_ms' => $hostile,
        ]);

        $probe = HealthProbe::probe();

        expect($probe->status)
            ->toBe(200);
        expect($probe->checkStatus('database'))
            ->toBe('ok');
    }
});

it('publie `warning` tel quel et le laisse SERVABLE', function (): void {
    // La première rédaction écrasait tout non-`ok` en `error` : un « dégradé
    // mais servable » devenait indiscernable d'une panne, et un orchestrateur
    // aurait retiré le conteneur du pool pour un avertissement.
    Health::clearChecks();
    Health::checks([
        (new class() extends Check {
            public function run(): Result
            {
                return Result::make()
                    ->warning('dégradé');
            }
        })->name('tiede'),
    ]);

    $probe = HealthProbe::probe();

    expect($probe->status)
        ->toBe(200);
    expect($probe->checkStatus('tiede'))
        ->toBe('warning');
});

it('honore `treat_skipped_as_failure` dans LES DEUX SENS', function (): void {
    // ⛔ Cette clé de Spatie était INERTE (revue 1). Une clé de configuration
    // qui ne change rien est un garde-fou qui ne garde rien.
    Health::clearChecks();
    Health::checks([
        (new class() extends Check {
            public function run(): Result
            {
                return Result::make()
                    ->ok();
            }
        })->name('conditionnelle')
            ->if(false),
    ]);

    config([
        'health.treat_skipped_as_failure' => true,
    ]);
    $strict = HealthProbe::probe();

    config([
        'health.treat_skipped_as_failure' => false,
    ]);
    $lax = HealthProbe::probe();

    expect($strict->status)
        ->toBe(503);
    expect($lax->status)
        ->toBe(200);

    // Dans les deux cas la sonde est RAPPORTÉE, et comme `skipped` — jamais `ok`.
    expect($strict->checkStatus('conditionnelle'))
        ->toBe((string) Status::skipped());
    expect($lax->checkStatus('conditionnelle'))
        ->toBe((string) Status::skipped());
});

it('n’applique PAS la planification cron d’une sonde à une requête HTTP', function (): void {
    // 🔴 `Check::shouldRun()` évalue AUSSI l'expression cron de Spatie
    // (`* * * * *` par défaut). Une sonde déclarée `->hourly()` — usage
    // légitime pour le planificateur — aurait fait rendre **503** à cet
    // endpoint 59 minutes sur 60. Relevé en revue 2 : la planification
    // appartient à `schedule:run`, pas à une requête synchrone.
    //
    // ⛔ L'EXPRESSION EST CALCULÉE, PAS `->hourly()`, ET LA CAMPAGNE DE
    // MUTATION L'A EXIGÉ : avec « 0 * * * * », la mutation « rétablir
    // shouldRun() » est VERTE pendant la minute 0 de chaque heure — et elle
    // l'a été, mesuré. Un test vrai 59 minutes sur 60 est un test qu'on croit
    // vert. Ici l'expression vise une minute qui n'est JAMAIS l'actuelle.
    $jamaisMaintenant = ((int) date('i') + 30) % 60 . ' * * * *';
    Health::clearChecks();
    Health::checks([
        (new class() extends Check {
            public function run(): Result
            {
                return Result::make()
                    ->ok();
            }
        })->name('horaire')
            ->cron($jamaisMaintenant),
    ]);

    $probe = HealthProbe::probe();

    // Anti-vacuité : la sonde a bien été JOUÉE, pas seulement « pas sautée ».
    expect($probe->checkStatus('horaire'))
        ->toBe('ok');
    expect($probe->checkDurationMs('horaire'))
        ->not->toBeNull();
    expect($probe->status)
        ->toBe(200);
});

it('refuse BRUYAMMENT deux sondes dont les clés se normalisent pareil', function (): void {
    // 🔴 `Str::snake()` n'est pas injective : « MonCheck » et « mon_check »
    // donnent `mon_check`. Spatie n'interdit que les noms EXACTEMENT dupliqués.
    // La seconde effaçait donc la première, et `/health` rendait `200` en ayant
    // perdu une sonde en route — un garde-fou disparu sans un mot.
    Health::clearChecks();
    Health::checks([
        (new class() extends Check {
            public function run(): Result
            {
                return Result::make()
                    ->ok();
            }
        })->name('MonCheck'),
        (new class() extends Check {
            public function run(): Result
            {
                return Result::make()
                    ->ok();
            }
        })->name('mon_check'),
    ]);

    $probe = HealthProbe::probe();

    expect($probe->status)
        ->toBe(503);
    expect($probe->checkSummary('mon_check'))
        ->toContain('Collision de clé');
});

it('JOURNALISE une sonde qui explose au lieu de l’avaler', function (): void {
    // Sans trace, une sonde CASSÉE est indiscernable d'une dépendance EN PANNE
    // dans les journaux — au moment précis où l'on cherche laquelle des deux.
    /*
     * ⚖️ ON CAPTURE LES APPELS PLUTÔT QUE DE LES MOQUER. Un `Log::spy()` rend
     * un `LegacyMockInterface`, dont l'API fluide n'est pas typée : elle coûte
     * trois erreurs PHPStan au niveau 10, et le ratchet du projet est à 0.
     * `Log::listen()` n'existe pas ; on remplace donc le canal par un
     * enregistreur monolog auquel on ajoute un `handler` de test — ce qui
     * observe la VRAIE écriture, pas une attente déclarée.
     */
    $logger = new class(app()) extends LogManager {
        /**
         * @var array<int, array{message: string, context: array<string, mixed>}>
         */
        public array $captured = [];

        /**
         * @param  \Stringable|string  $message
         * @param  array<string, mixed>  $context
         */
        public function error($message, array $context = []): void
        {
            $this->captured[] = [
                'message' => (string) $message,
                'context' => $context,
            ];
        }
    };

    Log::swap($logger);

    Health::clearChecks();
    Health::checks([
        (new class() extends Check {
            public function run(): Result
            {
                throw new RuntimeException('sonde explosive');
            }
        })->name('explosive'),
    ]);

    expect(HealthProbe::probe()->status)
        ->toBe(503);

    $matching = array_values(array_filter(
        $logger->captured,
        static fn (array $entry): bool => $entry['message'] === 'Health check crashed'
            && ($entry['context']['check'] ?? null) === 'explosive',
    ));

    expect($matching)
        ->toHaveCount(1);

    // 🔒 Et le message de l'exception n'est PAS journalisé — seulement sa classe.
    expect($matching[0]['context'])
        ->toHaveKey('type');
    expect($matching[0]['context'])
        ->not->toHaveKey('message');
});

it('ne divulgue pas le point de connexion interne dans le corps public', function (): void {
    // 🔒 Le portillon journalise `hôte:port` ; le corps public, lui, n'en dit
    // rien. `/health` n'est pas authentifié (arbitrage écrit dans le docblock
    // de la route et reporté), donc il ne publie pas la topologie interne.
    UnreachableBackends::asDefaultDatabase();

    $body = HealthProbe::probe()->body;

    expect($body)
        ->not->toContain('127.0.0.1');
    expect($body)
        ->not->toContain(':1"');
});

it('n’éprouve PAS de vrais backends réseau sur le chemin sain, et le dit', function (): void {
    /*
     * ⚠️ ANTI-VACUITÉ DE L'ANTI-VACUITÉ (revue 1). `phpunit.xml` force
     * `QUEUE_CONNECTION=sync` et `CACHE_STORE=array` : `SyncQueue::size()` rend
     * un `0` CODÉ EN DUR sans toucher aucun backend, et le magasin `array` vit
     * en mémoire. Le test « rend 200 et les trois sondes à ok » ne prouve donc
     * RIEN sur un vrai Redis ou un vrai Postgres — sauf pour la base, qui est
     * bien PostgreSQL en test.
     *
     * Ce test ne corrige pas cette limite : il l'ÉNONCE et la fige, pour que
     * personne ne lise « trois sondes à ok » comme une preuve d'intégration.
     * La couverture des vrais backends appartient au E2E Bats, qui installe et
     * interroge une pile complète — et à la vérification manuelle, où Redis et
     * Postgres ont été RÉELLEMENT arrêtés.
     */
    expect(config('queue.default'))
        ->toBe('sync');
    expect(config('cache.default'))
        ->toBe('array');
    expect(config('database.default'))
        ->toBe('pgsql');
});
