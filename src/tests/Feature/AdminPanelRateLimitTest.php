<?php

declare(strict_types=1);

use App\Core\Providers\CoreServiceProvider;
use App\Core\Support\TrustedProxies;
use App\Models\User;
use Filament\Auth\Pages\Login;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Middleware\TrustProxies;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\RateLimiter;
use Livewire\Livewire;
use Tests\Support\HttpProbe;
use Tests\Support\RepoFile;

uses(RefreshDatabase::class);

/**
 * Story 1.10a — AC5 : la limitation des tentatives de connexion, MESURÉE, et
 * dont la clé n'est pas falsifiable par le client.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * LA MESURE, FAITE AVANT D'ÉCRIRE LA MOINDRE ASSERTION (2026-08-09)
 *
 * Lue dans `vendor/`, pas dans la documentation :
 *
 *   • `Filament\Auth\Pages\Login::authenticate()` appelle `$this->rateLimit(5)`
 *     en TOUTE PREMIÈRE instruction — donc avant `$this->form->getState()` et
 *     avant toute consultation de la table `users`.
 *   • `DanHarrin\LivewireRateLimiting\WithRateLimiting::rateLimit()` prend
 *     `$decaySeconds = 60` par défaut → fenêtre d'UNE MINUTE.
 *   • la clé de seau vaut
 *     `'livewire-rate-limiter:' . sha1($component . '|' . $method . '|' . request()->ip())`.
 *
 * Soit exactement « 5 tentatives par minute et par IP ». ⚠️ C'est le DÉFAUT de
 * Filament : l'AC d'origine (« le rate limiting est de 5/min/IP ») aurait donc
 * été vert sans qu'une seule ligne soit écrite. Un test qui s'arrête là garde
 * le comportement d'une bibliothèque tierce, pas une décision du projet.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * 🔴 CE QUE LA MESURE A RÉVÉLÉ, ET QUI EST LE VRAI SUJET DE CET AC
 *
 * La clé dérive de `request()->ip()`. Or `bootstrap/app.php` faisait
 * `env('TRUSTED_PROXIES', '*')`, et Laravel traduit `'*'` par
 * `setTrustedProxies(['0.0.0.0/0', '::/0'])` — c'est-à-dire « TOUTE adresse
 * d'Internet est un reverse-proxy de confiance ». Symfony remonte alors la
 * chaîne `X-Forwarded-For` de droite à gauche en sautant tout ce qui est de
 * confiance, donc jusqu'à l'entrée la plus à GAUCHE : celle qu'écrit le client.
 *
 * Mesuré sous la topologie réelle du squelette, AVANT correction :
 *
 *   REMOTE_ADDR       = 172.20.0.5              (le conteneur Apache)
 *   X-Forwarded-For   = 198.51.100.42, 203.0.113.9
 *                       ^^^^^^^^^^^^^  forgé par le client
 *                                      ^^^^^^^^^^^ ajouté par Apache = la vraie IP
 *   request()->ip()   → 198.51.100.42          ❌ la valeur forgée
 *
 * Un attaquant qui incrémente cet en-tête obtient donc UN SEAU NEUF À CHAQUE
 * TENTATIVE : le « 5/min/IP » de FR-Admin-8 ne limite rien, sur la seule
 * surface d'authentification du produit.
 *
 * ⚠️ La justification écrite dans `.env.example` — « '*' = trust any proxy
 * (safe quand l'app est TOUJOURS derrière un reverse-proxy) » — est fausse
 * précisément parce qu'Apache AJOUTE à `X-Forwarded-For` au lieu de le
 * remplacer : être derrière un proxy ne protège pas, ça rallonge la chaîne que
 * le joker fait sauter.
 *
 * ⚠️⚠️ ET LA STORY ELLE-MÊME SE TROMPAIT SUR UN POINT : ses Dev Notes §4
 * affirment que `TRUSTED_PROXIES` est « absente de `.env` ET de
 * `.env.example` ». Elle est absente de `.env`, mais bien PRÉSENTE dans
 * `.env.example:90`, à la valeur `*` et accompagnée d'un commentaire qui la
 * justifie. La conclusion tenait ; le correctif, lui, n'est pas « ajouter une
 * variable oubliée » mais « corriger une valeur écrite et son motif ».
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * POURQUOI DEUX TESTS, ET POURQUOI CELUI DE LA CLÉ NE PASSE PAS PAR LIVEWIRE
 *
 * Mesuré aussi : `Livewire::test()` construit sa propre requête et n'hérite pas
 * de `withServerVariables()` — l'IP y reste 127.0.0.1 quoi qu'on pose. Un test
 * « 6ᵉ tentative avec un autre X-Forwarded-For » écrit via Livewire ne
 * prouverait donc rien : il serait vert parce que RIEN N'A BOUGÉ, pas parce que
 * le système résiste. C'est le piège nommé au §11 de la story.
 *
 * Le partage retenu :
 *
 *   • la LIMITE (5/min, et le refus avant la base) est exercée par Livewire,
 *     seul chemin qui exécute réellement `authenticate()` ;
 *   • la CLÉ DE SEAU est exercée par une vraie requête HTTP, où les en-têtes
 *     s'appliquent normalement, en appelant la MÉTHODE RÉELLE du paquet
 *     (`getRateLimitKey`) plutôt qu'en récrivant son expression — une
 *     réécriture serait une seconde source de vérité, capable de rester verte
 *     pendant que le paquet change.
 */

/**
 * Clé de seau que le paquet de limitation calcule pour la page de connexion,
 * dans le contexte de requête courant.
 *
 * ⚠️ On appelle la méthode PROTÉGÉE réellement fournie par
 * `DanHarrin\LivewireRateLimiting\WithRateLimiting`, sur une instance réelle de
 * la page de connexion du panel. Rien n'est réimplémenté : récrire l'expression
 * `sha1($component . '|' . $method . '|' . request()->ip())` en ferait une
 * seconde source de vérité, capable de rester verte pendant que le paquet
 * change de composition de clé — c'est-à-dire pendant que le garde-fou cesse de
 * garder quoi que ce soit.
 *
 * Les deux échecs possibles (liaison impossible, retour non-chaîne) lèvent au
 * lieu de rendre une valeur vague : un test qui compare deux `null` serait vert.
 */
function loginRateLimitKey(): string
{
    $bound = Closure::bind(
        fn (): mixed => $this->getRateLimitKey('authenticate', Login::class),
        new Login(),
        Login::class,
    );

    if (! $bound instanceof Closure) {
        throw new RuntimeException(
            'Impossible de lier une closure à Filament\\Auth\\Pages\\Login : '
            . 'la page de connexion du panel a changé de forme.',
        );
    }

    $key = $bound();

    if (! is_string($key)) {
        throw new RuntimeException(
            'getRateLimitKey() ne rend plus une chaîne : la composition de la clé de seau '
            . 'de danharrin/livewire-rate-limiting a changé, et ce test ne mesure plus rien.',
        );
    }

    return $key;
}

/**
 * Simule une requête telle qu'Apache la présente à PHP-FPM, puis rend la clé de
 * seau calculée dans ce contexte.
 *
 * `$forgedPrefix` est ce que le CLIENT a écrit dans `X-Forwarded-For` ;
 * `203.0.113.9` est ce qu'Apache y a AJOUTÉ, c'est-à-dire la vraie IP source.
 */
function rateLimitKeyUnderForgedChain(string $forgedPrefix): string
{
    HttpProbe::get('/admin/login', null, [
        'REMOTE_ADDR' => '172.20.0.5',
        'HTTP_X_FORWARDED_FOR' => $forgedPrefix . ', 203.0.113.9',
    ]);

    return loginRateLimitKey();
}

/*
|------------------------------------------------------------------------------
| La limite elle-même
|------------------------------------------------------------------------------
*/

it('refuses the 6th failed login within the window, without consulting the users table', function (): void {
    User::factory()->create([
        'email' => 'victim@example.com',
    ]);

    // Les 5 premières tentatives atteignent la vérification d'identifiants :
    // elles produisent une erreur de validation sur l'e-mail.
    for ($attempt = 1; $attempt <= 5; $attempt++) {
        Livewire::test(Login::class)
            ->fillForm([
                'email' => 'victim@example.com',
                'password' => 'wrong-password',
            ])
            ->call('authenticate')
            ->assertHasFormErrors(['email']);
    }

    // La 6ᵉ est arrêtée AVANT `$this->form->getState()` : elle ne peut donc pas
    // produire d'erreur d'identifiants. C'est la forme observable de « sans
    // consulter la base d'utilisateurs ».
    Livewire::test(Login::class)
        ->fillForm([
            'email' => 'victim@example.com',
            'password' => 'wrong-password',
        ])
        ->call('authenticate')
        ->assertHasNoFormErrors();
});

/*
|------------------------------------------------------------------------------
| ⛔ AC5, TROISIÈME GIVEN — NON COMPOSÉ, ET VOICI LA MESURE QUI DIT POURQUOI
|------------------------------------------------------------------------------
|
| L'AC5 demande : « When la 6ᵉ arrive avec un `X-Forwarded-For` DIFFÉRENT fourni
| par le client — Then elle est TOUJOURS refusée », et ajoute que les deux Given
| « sont indissociables : le premier sans le second est une décoration ».
|
| La revue du 2026-08-10 (P5) puis celle du 2026-08-20 (Q8) ont toutes deux
| relevé que la conjonction n'était pas écrite, la seconde en affirmant que le
| §11 de la story donnait la voie. ELLE NE LA DONNE PAS, et c'est mesuré :
|
|   Sous `Livewire::withHeaders(['X-Forwarded-For' => '198.51.100.7, 203.0.113.9'])`
|   ->test(Login::class) — mesuré le 2026-08-20 sur cette pile :
|
|     request()->headers->get('X-Forwarded-For')  →  '198.51.100.7, 203.0.113.9'  ✅ posé
|     request()->server->get('REMOTE_ADDR')       →  '127.0.0.1'                  ⛔ non pilotable
|     request()->ip()                             →  '127.0.0.1'
|     après `Request::setTrustedProxies(['0.0.0.0/0','::/0'], …)` à la main
|     request()->ip()                             →  '198.51.100.7'
|
| Deux obstacles, tous deux dans le harnais et non dans le code testé :
|
|   1. Le middleware `TrustProxies` NE S'EXÉCUTE PAS sous `Livewire::test()` —
|      `RequestBroker` désactive les middlewares. `request()->ip()` rend donc
|      toujours `REMOTE_ADDR`, quelle que soit la configuration de l'application.
|      Un test écrit là serait vert que le correctif soit présent OU ABSENT.
|
|   2. `Livewire::withHeaders()` ne pose que des EN-TÊTES. `REMOTE_ADDR` n'en est
|      pas un, donc le pair immédiat vaut toujours `127.0.0.1` — et « faire
|      confiance au pair immédiat » revient alors à faire confiance au client
|      lui-même. La chaîne de production (Apache AJOUTE la vraie IP à droite du
|      forgé) n'est pas reproductible dans ce harnais.
|
| ⚠️ UN CONTRE-TEST A ÉTÉ ÉCRIT ET A ROUGI, ET C'EST LUI QUI A ÉTABLI TOUT CECI :
| il rendait `*` à la confiance et attendait que la 6ᵉ tentative passe. Elle ne
| passait pas — parce que l'en-tête n'était jamais honoré. Sans ce contre-test, le
| test principal aurait été committé vert en ne mesurant rien : exactement le
| motif dominant de ce dépôt, sur sa seule surface d'authentification.
|
| CE QUI EST RÉELLEMENT GARDÉ, ET PAR QUOI :
|   • la 6ᵉ tentative est refusée                → `refuses the 6th failed login…`
|   • deux préfixes forgés donnent LA MÊME clé   → `keeps the same bucket when the
|                                                   client forges…` (requête noyau
|                                                   RÉELLE, où `TrustProxies` tourne
|                                                   et où `REMOTE_ADDR` est pilotable)
|   • deux pairs distincts donnent DEUX clés     → `still separates two genuinely…`
|
| La conjonction reste donc établie par composition, pas par un test unique. La
| voie qui la composerait vraiment — frapper l'endpoint Livewire en HTTP réel —
| demande de fabriquer un instantané de composant valide (snapshot + checksum) ;
| c'est un travail à part, inscrit dans `deferred-work.md`.
*/

it('decays the bucket over a one-minute window, not a longer one', function (): void {
    /*
     * ⚠️ CE TEST A ÉTÉ RÉÉCRIT PENDANT LA CAMPAGNE DE MUTATION, ET LE MOTIF
     *    MÉRITE D'ÊTRE LU.
     *
     * Sa première rédaction s'appelait « applies the limit at 5 attempts, not
     * at some larger number » et assertait `RateLimiter::tooManyAttempts($key, 5)`
     * après cinq échecs. La mutation « porter la limite de Filament de 5 à 500 »
     * l'a laissé VERT — parce qu'il ne mesurait pas la limite de Filament : il
     * comptait les coups portés au seau, avec SON PROPRE seuil de 5 en argument.
     * Le seau se remplit à l'identique quelle que soit la limite ; seule la
     * décision de refuser change.
     *
     * C'était donc un garde-fou dont le nom promettait plus que ce qu'il
     * vérifiait — le motif dominant de ce projet, produit par la story qui le
     * traque. La limite de 5 EST déjà bornée des deux côtés par le test
     * précédent (les 5 premières atteignent la validation, la 6ᵉ non) : y
     * ajouter une assertion non discriminante n'apportait rien.
     *
     * Ce qui n'était couvert par RIEN, en revanche, c'est la FENÊTRE — le
     * troisième terme que l'AC5 demande de mesurer et de figer. La voici.
     */
    User::factory()->create([
        'email' => 'victim@example.com',
    ]);

    for ($attempt = 1; $attempt <= 5; $attempt++) {
        Livewire::test(Login::class)
            ->fillForm([
                'email' => 'victim@example.com',
                'password' => 'wrong-password',
            ])
            ->call('authenticate');
    }

    $availableIn = RateLimiter::availableIn(loginRateLimitKey());

    // Fenêtre lue dans le paquet : `WithRateLimiting::rateLimit()` prend
    // `$decaySeconds = 60` par défaut, et Filament ne le surcharge pas. On
    // borne des DEUX côtés : `> 0` prouve qu'un seau existe réellement,
    // `<= 60` prouve qu'il expire dans la minute et pas dans une heure.
    expect($availableIn)
        ->toBeGreaterThan(
            0,
            'Aucun seau ne subsiste après 5 échecs : la limitation n\'est pas armée.',
        );
    expect($availableIn)
        ->toBeLessThanOrEqual(
            60,
            "La fenêtre de limitation dure {$availableIn}s au lieu de 60s au plus : "
                . 'un `decaySeconds` allongé enferme l\'administrateur légitime hors de son panel.',
        );
});

/*
|------------------------------------------------------------------------------
| 🔴 La clé de seau — le vrai sujet
|------------------------------------------------------------------------------
*/

it('derives the rate limit bucket from the real client IP, not from a client-supplied header', function (): void {
    /*
     * ⚠️ L'ATTENDU A CHANGÉ LE 2026-08-20, ET C'EST LE CŒUR DE LA REVUE DE SÉCURITÉ.
     *
     * Ce test attendait `203.0.113.9` — la SECONDE entrée de la chaîne — parce
     * qu'il supposait `REMOTE_ADDR = 172.20.0.5 = le conteneur Apache`, donc un
     * proxy de confiance dont la contribution serait dépouillée. Sous FastCGI,
     * cette topologie n'existe pas : Apache transmet à PHP-FPM en posant
     * `REMOTE_ADDR` = l'adresse du CLIENT. Aucun proxy n'est visible de PHP.
     *
     * Avec le défaut corrigé (aucun proxy de confiance), la réponse juste est le
     * PAIR — `172.20.0.5` ici — et l'intégralité de `X-Forwarded-For` est ignorée.
     * C'est plus fort que l'ancien attendu : le client ne contrôle plus aucune
     * partie de la valeur.
     */
    HttpProbe::get('/admin/login', null, [
        'REMOTE_ADDR' => '172.20.0.5',
        'HTTP_X_FORWARDED_FOR' => '198.51.100.42, 203.0.113.9',
    ]);

    // Sonde : on vérifie d'abord que l'en-tête est bien DÉLIVRÉ, sinon ce test
    // prouverait seulement que rien n'a bougé (§11 de la story).
    expect(request()->header('X-Forwarded-For'))
        ->toBe(
            '198.51.100.42, 203.0.113.9',
            'L\'en-tête X-Forwarded-For n\'atteint pas l\'application : le test n\'exerce pas le mécanisme.',
        );

    expect(request()->ip())
        ->toBe(
            '172.20.0.5',
            'request()->ip() ne rend pas le pair de la connexion : une partie au moins de la valeur '
                . 'vient de l\'en-tête écrit par le client, donc la clé de seau est falsifiable.',
        );
});

it('keeps the same bucket when the client forges a different X-Forwarded-For prefix', function (): void {
    // La conséquence directe : deux tentatives venant du MÊME client réel, avec
    // deux en-têtes forgés différents, doivent tomber dans LE MÊME seau.
    // Sinon l'attaquant obtient un seau neuf à chaque requête et la limite de 5
    // ne limite rien.
    $first = rateLimitKeyUnderForgedChain('198.51.100.42');
    $second = rateLimitKeyUnderForgedChain('192.0.2.7');

    expect($first)
        ->toBe(
            $second,
            'Deux en-têtes X-Forwarded-For forgés différents produisent DEUX seaux : '
                . 'un attaquant réinitialise sa limite à chaque tentative.',
        );
});

it('still separates two genuinely different clients into different buckets', function (): void {
    /*
     * ⚠️ CE TEST A CHANGÉ DE FIXTURE LE 2026-08-20, ET LE MOTIF EST LE DÉFAUT
     *    QU'IL N'AVAIT PAS PU VOIR.
     *
     * Il distinguait deux clients par leur `X-Forwarded-For`, à `REMOTE_ADDR`
     * constant — une topologie où Apache serait le pair de PHP. Sous FastCGI ce
     * n'est pas le cas : `REMOTE_ADDR` EST l'adresse du client. La fixture codait
     * donc un monde qui n'existe pas, et c'est précisément ce qui a permis au
     * défaut `TRUSTED_PROXIES=REMOTE_ADDR` de rester vert pendant deux passes de
     * revue. Deux clients réellement distincts se distinguent par leur
     * `REMOTE_ADDR`.
     */
    HttpProbe::get('/admin/login', null, [
        'REMOTE_ADDR' => '203.0.113.9',
    ]);
    $clientA = loginRateLimitKey();

    HttpProbe::get('/admin/login', null, [
        'REMOTE_ADDR' => '203.0.113.250',
    ]);
    $clientB = loginRateLimitKey();

    expect($clientA)
        ->not->toBe(
            $clientB,
            'Deux clients réellement distincts partagent le même seau : la limitation devient '
                . 'un déni de service — cinq échecs d\'un attaquant ferment la porte à l\'administrateur.',
        );
});

it('cannot be pivoted onto the wildcard by a forged Host header', function (): void {
    /*
     * 🔴 LA MÊME FAILLE, TROISIÈME ITÉRATION — trouvée par la lentille adversariale
     *    le 2026-08-20, REPRODUITE en HTTP réel avant d'être écrite.
     *
     * Le défaut « aucun proxy de confiance » avait été exprimé par un TABLEAU VIDE.
     * Or `TrustProxies::proxies()` est `static::$alwaysTrustProxies ?: $this->proxies` :
     * un tableau vide est FALSY, la valeur s'effondre sur `null`, et `null` signifie
     * pour Laravel « jamais configuré ». Dans cette branche :
     *
     *   if (is_null($trustedIps) && (laravel_cloud()
     *       || str_ends_with($request->host(), '.on-forge.com')
     *       || str_ends_with($request->host(), '.on-vapor.com'))) { $trustedIps = '*'; }
     *
     * `$request->host()` est l'en-tête `Host`, écrit par le client. UN SEUL EN-TÊTE
     * FORGÉ rendait donc tout le joker. Mesuré avant correction :
     *
     *   Host: localhost      → ip = 172.18.0.3      trusted = []
     *   Host: x.on-vapor.com → ip = 198.51.100.42   trusted = ['0.0.0.0/0','::/0']
     *
     * Aucun test ne pouvait le voir : toutes les sondes passent par
     * `Request::create()`, dont l'hôte par défaut est `localhost`.
     */
    $peer = '203.0.113.9';

    foreach (['localhost', 'x.on-vapor.com', 'y.on-forge.com', 'anything.on-forge.com'] as $host) {
        HttpProbe::get('/admin/login', null, [
            'HTTP_HOST' => $host,
            'REMOTE_ADDR' => $peer,
            'HTTP_X_FORWARDED_FOR' => '198.51.100.42',
        ]);

        expect(request()->ip())
            ->toBe(
                $peer,
                "Sous `Host: {$host}`, request()->ip() rend une valeur écrite par le client : "
                    . 'la confiance aux proxys a basculé sur le joker à cause d\'un en-tête forgé.',
            );
    }
});

it('expresses "no trusted proxy" with something, never with an empty array', function (): void {
    /*
     * LE GARDE-FOU DE L'EXPRESSION ELLE-MÊME.
     *
     * Le test précédent observe l'effet ; celui-ci observe la cause, parce que le
     * pivot ne se déclenche que sur des hôtes précis et qu'une future version de
     * Laravel peut en ajouter d'autres. La propriété robuste est : la valeur
     * remise à `TrustProxies` n'est JAMAIS vide, donc `proxies()` ne peut jamais
     * rendre `null`, donc la branche « jamais configuré » est hors d'atteinte.
     */
    expect(TrustedProxies::parse('')['at'])->not->toBe([]);
    expect(TrustedProxies::parse('   ')['at'])->not->toBe([]);
    expect(TrustedProxies::parse(true)['at'])->not->toBe([]);
    expect(TrustedProxies::parse('*,*')['at'])->not->toBe([]);

    // Et ce « quelque chose » ne doit faire confiance à personne.
    expect(TrustedProxies::TRUST_NOBODY)->toBe(['0.0.0.0/32']);
});

it('ignores a forged X-Forwarded-For end to end, through the real HTTP kernel', function (): void {
    /*
     * 🔴 LE GARDE-FOU QUI MANQUAIT, ET QUI AURAIT ATTRAPÉ LE DÉFAUT.
     *
     * Tous les tests de ce fichier passaient par `loginRateLimitKey()`, c'est-à-dire
     * comparaient des CLÉS entre elles. Aucun n'observait la propriété élémentaire
     * dont tout le reste dépend : **l'adresse que l'application attribue au client
     * n'est pas celle que le client a écrite**. Deux passes de revue plus tard,
     * `TRUSTED_PROXIES=REMOTE_ADDR` faisait rendre à `request()->ip()` la valeur
     * forgée, et rien ne rougissait.
     *
     * Ici on émet une requête à travers le noyau HTTP — donc `TrustProxies`
     * s'exécute avec la configuration réellement livrée — et on compare l'IP vue
     * par l'application au pair, pas à une autre clé.
     */
    $forged = '198.51.100.42';
    $peer = '203.0.113.9';

    HttpProbe::get('/admin/login', null, [
        'REMOTE_ADDR' => $peer,
        'HTTP_X_FORWARDED_FOR' => $forged,
        'HTTP_X_FORWARDED_HOST' => 'evil.example',
    ]);

    expect(request()->ip())
        ->toBe(
            $peer,
            'request()->ip() rend une valeur écrite par le client : la configuration de confiance '
                . 'aux proxys fait confiance au client lui-même, et TOUTE limitation par IP est '
                . 'inopérante.',
        );

    expect(request()->getHost())
        ->not->toBe(
            'evil.example',
            'X-Forwarded-Host est honoré : toute URL absolue générée par l\'application '
                . '(redirections, liens signés, e-mails) peut viser un domaine choisi par l\'attaquant.',
        );
});

/*
|------------------------------------------------------------------------------
| 🔴 La valeur de confiance doit survivre à `config:cache` (revue 2026-08-10, D3)
|------------------------------------------------------------------------------
*/

it('hands the configured proxy list to the middleware that actually reads it', function (): void {
    /*
     * 🔴 CE QUE LA VERSION PRÉCÉDENTE DE CE TEST N'OBSERVAIT PAS — finding Q1,
     *    revue du 2026-08-20.
     *
     * Elle assertait `expect(config('proxies.at'))->not->toBeNull()`. C'est vrai
     * dès qu'un fichier existe dans `config/`, que quiconque le LISE ou non. Le
     * garde-fou était donc satisfait par la simple présence du fichier, pendant
     * que `bootstrap/app.php` faisait `require config/proxies.php` — ré-évaluant
     * `env()` dans un callback qui s'exécute après le bootstrap, donc retombant
     * sur le défaut sous `config:cache`, en production. L'`env()` avait changé de
     * fichier, pas de moment.
     *
     * MESURÉ le 2026-08-20 : dans le callback `withMiddleware()`,
     * `app()->bound('config')` vaut `false` — `withMiddleware()` s'accroche à
     * `afterResolving(HttpKernel::class)`, et `Application::handleRequest()`
     * résout le noyau AVANT `$kernel->handle()`, qui est ce qui bootstrape. Ni
     * `env()` ni `config()` n'y sont lisibles. La valeur est donc posée par
     * `CoreServiceProvider::boot()`, après `LoadConfiguration`.
     *
     * Ce test observe la VALEUR QUE LE MIDDLEWARE PORTE, pas l'existence d'une
     * clé de configuration. Il rougit si quelqu'un rapatrie l'appel dans
     * `bootstrap/app.php` : la valeur y devient `null`, et plus aucun proxy n'est
     * de confiance — en silence.
     */
    $heldAt = static fn (): mixed => (new \ReflectionClass(TrustProxies::class))
        ->getStaticPropertyValue('alwaysTrustProxies');

    expect($heldAt())
        ->not->toBeNull(
            'Le middleware TrustProxies ne porte AUCUNE valeur : personne n\'a appelé '
                . '`TrustProxies::at()`, donc aucun proxy n\'est de confiance et la détection '
                . 'HTTPS est cassée — silencieusement.',
        );
    expect($heldAt())
        ->toBe(
            config('proxies.at'),
            'La valeur portée par TrustProxies ne vient pas de `config/proxies.php` : elle ne '
                . 'survivra donc pas à `config:cache`, qui est le chemin de production.',
        );

    /*
     * ⚠️ ET VOICI LA MOITIÉ SANS LAQUELLE CE TEST SERAIT SILENCIEUX — et je l'ai
     * découverte en tentant la mutation, pas en relisant.
     *
     * Les deux assertions ci-dessus restent VERTES si quelqu'un rapatrie la
     * lecture dans `bootstrap/app.php` : en environnement de test, `.env` est
     * chargé, donc la valeur `require`d et la valeur de configuration coïncident.
     * Le garde-fou n'aurait alors gardé que la ressemblance de deux chemins, pas
     * l'identité de leur source — exactement le défaut Q1 qu'il est censé fermer.
     *
     * On change donc la CONFIGURATION seule, et on exige que la valeur portée
     * suive. Une valeur venue d'un `require` de `config/proxies.php` — ou d'un
     * `env()` — ne bougerait pas.
     */
    config()
        ->set('proxies.at', ['10.0.0.0/8']);

    // `boot()` est idempotent ici : `pushMiddlewareToGroup` ignore un doublon et
    // `commands()` ré-enregistre à l'identique.
    (new CoreServiceProvider(app()))->boot();

    expect($heldAt())
        ->toBe(
            ['10.0.0.0/8'],
            'La valeur portée par TrustProxies ne SUIT PAS la configuration : elle est donc figée '
                . 'ailleurs (un `env()` ou un `require` dans bootstrap/app.php), et le cache de '
                . 'configuration construit au déploiement n\'est lu par personne.',
        );
});

it('honours a real comma-separated CIDR list — the branch that production actually uses', function (): void {
    /*
     * ⚠️ LA SEULE BRANCHE QUI COMPTE EN PRODUCTION, ET ELLE N'ÉTAIT GARDÉE PAR
     *    RIEN — finding Q14.
     *
     * Les tests couvraient le vide, le `*` seul et le `*` noyé dans une liste.
     * Aucun n'assertait qu'une vraie liste — celle que `.env.example` demande à
     * l'opérateur d'énumérer pour un déploiement à proxys en cascade — est
     * effectivement parsée. Une implémentation qui aurait retourné
     * inconditionnellement `['REMOTE_ADDR']` depuis la branche `else` passait
     * tous les tests du fichier, en réintroduisant en silence le seau unique que
     * le commentaire du fichier décrit comme un déni de service.
     */
    $parsed = TrustedProxies::parse('10.0.0.0/8, 172.16.0.0/12 ,192.168.1.1');

    expect($parsed['at'])
        ->toBe(
            ['10.0.0.0/8', '172.16.0.0/12', '192.168.1.1'],
            'Une liste CIDR légitime n\'est pas parsée telle quelle : les proxys de l\'opérateur '
                . 'ne correspondront à rien, et tous ses clients partageront un seul seau.',
        );
    expect($parsed['problems'])
        ->toBe([], 'Une liste CIDR parfaitement valide est signalée comme problématique.');
});

it('refuses a wildcard buried in a list without making the application unbootable', function (): void {
    /*
     * DÉCISION D8 (revue du 2026-08-20). Le refus était juste, l'endroit ne
     * l'était pas : `config/proxies.php` levait une RuntimeException PENDANT le
     * chargement de `config/`, donc une faute de frappe faisait échouer
     * `config:cache` au démarrage du conteneur, puis TOUTE commande artisan —
     * y compris celles qu'un opérateur emploierait pour réparer sa faute de
     * frappe. Le refus vit désormais dans `proxies:check`, exécuté par
     * l'entrypoint AVANT `config:cache`.
     *
     * Ce test borne les deux moitiés : le problème est SIGNALÉ (donc le contrôle
     * de déploiement le refusera), et la valeur reste utilisable (donc
     * l'application démarre et reste réparable) — avec la liste étroite, jamais
     * une liste élargie par accident.
     */
    $parsed = TrustedProxies::parse('10.0.0.0/8,*');

    expect($parsed['problems'])->toHaveCount(1, 'Le `*` noyé dans une liste n\'est plus signalé.');
    expect($parsed['at'])
        ->toBe(
            ['10.0.0.0/8'],
            'L\'astérisque a été conservé comme adresse littérale, ou la liste a été élargie : '
                . 'dans les deux cas l\'opérateur croit avoir décidé autre chose que ce qui s\'applique.',
        );
});

it('refuses an entry that can never match a client', function (): void {
    // Un nom d'hôte n'est jamais résolu par la comparaison CIDR : l'entrée ne
    // correspondra à aucun client, `request()->ip()` rendra l'adresse du proxy,
    // et tous les clients derrière lui partageront un seau. Rien ne le disait.
    $parsed = TrustedProxies::parse('proxy.interne.example');

    expect($parsed['problems'])->toHaveCount(1);
    expect($parsed['problems'][0])->toContain('proxy.interne.example');
});

it('does not let a non-string value silently trust nothing', function (): void {
    // `Env` convertit `true`/`false`/`null` en types PHP AVANT tout cast en
    // chaîne : `TRUSTED_PROXIES=true` deviendrait le proxy littéral `'1'`, qui ne
    // correspond à rien — donc plus rien n'est de confiance, la détection HTTPS
    // casse, et personne n'est prévenu. Finding Q22.
    $parsed = TrustedProxies::parse(true);

    expect($parsed['at'])->toBe(TrustedProxies::TRUST_NOBODY, 'Une valeur non-chaîne ne retombe pas sur le défaut sûr (aucun proxy de confiance).');
    expect($parsed['problems'])->toHaveCount(1, 'Une valeur non-chaîne passe sans être signalée.');
});

it('reads no environment variable at middleware-configuration time', function (): void {
    /*
     * ⚠️ ASSUMÉ : C'EST UNE LECTURE DE SOURCE, PAS UNE OBSERVATION D'EFFET.
     *
     * La propriété visée — « cette valeur survit à `config:cache` » — ne
     * s'observe qu'en CONSTRUISANT un cache de configuration, ce qu'un test ne
     * peut pas faire sans réécrire `bootstrap/cache/` de la suite en cours.
     * Le meilleur substitut disponible est de vérifier qu'aucun APPEL à `env()`
     * ne subsiste dans le fichier : c'est la cause exacte du défaut, et son
     * sujet — le fichier — existe bel et bien, contrairement au garde-fou de
     * fontes que cette même revue a trouvé vert sur un chemin inexistant.
     *
     * ─────────────────────────────────────────────────────────────────────────
     * ⛔ POURQUOI ON ANALYSE LES JETONS ET NON LE TEXTE (constaté le 2026-08-20)
     *
     * L'assertion était `str_contains($source, 'env(')`. Elle a rougi sur les
     * DEUX SEULES occurrences du fichier — lignes 20 et 22, à l'intérieur du
     * commentaire ⛔ qui interdit précisément d'y remettre un `env()`. Zéro
     * appel réel. Le garde-fou accusait la documentation de son propre motif :
     * une occurrence de plus du défaut dominant de ce projet, et la seule
     * parade est de demander à PHP ce qu'est un appel plutôt que de le deviner
     * à la sous-chaîne. Commentaires et chaînes littérales sont des jetons
     * distincts de `T_STRING`, donc naturellement hors du champ.
     *
     * ⚠️ CE QUE CE TEST NE COUVRE TOUJOURS PAS, et qui reste à trancher en revue :
     * `bootstrap/app.php` fait `require config/proxies.php` au lieu de lire
     * `config('proxies.at')`. Le fichier est donc évalué DANS le callback, au
     * même instant qu'avant, et le tableau que `config:cache` a mis en cache
     * n'est lu par personne. L'`env()` a changé de fichier, pas de moment.
     * L'assertion ci-dessous serait verte même dans ce cas — elle l'est
     * aujourd'hui.
     */
    $source = RepoFile::read('src/bootstrap/app.php');

    /** @var list<int> $callLines lignes portant un appel à la fonction globale env() */
    $callLines = [];
    $tokens = token_get_all($source);

    foreach ($tokens as $index => $token) {
        if (! is_array($token) || $token[0] !== T_STRING || $token[1] !== 'env') {
            continue;
        }

        // `$objet->env(` et `Classe::env(` ne sont pas l'aide globale visée.
        $previous = $tokens[$index - 1] ?? null;
        if (is_array($previous) && in_array($previous[0], [T_OBJECT_OPERATOR, T_NULLSAFE_OBJECT_OPERATOR, T_DOUBLE_COLON], true)) {
            continue;
        }

        // Un appel, c'est `env` suivi d'une parenthèse ouvrante — le nom seul
        // (`'env'` dans un tableau, par exemple) n'en est pas un.
        for ($next = $index + 1; isset($tokens[$next]); $next++) {
            $candidate = $tokens[$next];

            if (is_array($candidate) && in_array($candidate[0], [T_WHITESPACE, T_COMMENT, T_DOC_COMMENT], true)) {
                continue;
            }

            if ($candidate === '(') {
                $callLines[] = $token[2];
            }

            break;
        }
    }

    expect($callLines)
        ->toBe(
            [],
            'bootstrap/app.php appelle env() (ligne(s) ' . implode(', ', $callLines) . ') : ce callback '
                . 's\'exécute après le bootstrap, donc sous `config:cache` la valeur de `.env` est '
                . 'ignorée et le défaut s\'applique silencieusement en production. Passer par un '
                . 'fichier de config/.',
        );
});

it('falls back to the immediate peer when the variable is written but left empty', function (): void {
    /*
     * ⚠️ CES TROIS TESTS ONT CHANGÉ DE SUJET LE 2026-08-20 (décision D8).
     *
     * Ils `require`aient `config/proxies.php` en manipulant `$_SERVER` à la main,
     * parce que le parsing ET le refus vivaient dans le fichier de configuration.
     * Le refus en est sorti — il levait pendant le chargement de `config/`, donc
     * une faute de frappe rendait l'application non bootable, commandes de
     * réparation comprises. Le parsing vit maintenant dans une fonction pure,
     * `App\Core\Support\TrustedProxies::parse()`, qu'on interroge directement :
     * plus de `$_SERVER` à restaurer dans un `finally`, et le sujet du test est
     * enfin le code qui décide.
     *
     * Une ligne `TRUSTED_PROXIES=` mal renseignée ne doit pas rouvrir la faille en
     * silence : c'est le seul cas où l'on décide à la place de l'opérateur, et
     * c'est parce qu'il n'a précisément rien décidé.
     */
    // ⚠️ `TRUST_NOBODY`, jamais `[]` : un tableau vide est falsy, donc
    // `TrustProxies::proxies()` le rendrait indiscernable de « jamais configuré »
    // et Laravel basculerait sur le joker pour un `Host` forgé. Voir le test
    // `cannot be pivoted onto the wildcard by a forged Host header`.
    expect(TrustedProxies::parse('')['at'])->toBe(TrustedProxies::TRUST_NOBODY);
    expect(TrustedProxies::parse('   ')['at'])->toBe(TrustedProxies::TRUST_NOBODY);
});

it('still honours a wildcard written on its own, because that is a decision', function (): void {
    // Le joker ÉCRIT EXPLICITEMENT reste honoré. Le neutraliser en douce ferait
    // mentir la configuration sur ce qui est en vigueur — le motif exact que ce
    // projet traque. Il a un usage légitime (Laravel Cloud, Vapor), il est
    // documenté comme dangereux dans `.env.example`, et il n'est plus le défaut.
    $parsed = TrustedProxies::parse('*');

    expect($parsed['at'])->toBe('*');
    expect($parsed['problems'])->toBe([], 'Un joker explicite est une décision, pas une erreur.');
});

it('flags REMOTE_ADDR, because under FastCGI it names the client and not the proxy', function (): void {
    /*
     * 🔴 REVUE DE SÉCURITÉ DU 2026-08-20 — LE CORRECTIF DE L'AC5 ÉTAIT ENCORE FAUX.
     *
     * `REMOTE_ADDR` a été le défaut du 2026-08-09 au 2026-08-20, en remplacement
     * de `*`, au motif qu'il ne ferait confiance qu'à « Apache, le pair immédiat ».
     * Apache ne parle pas HTTP à PHP : il transmet par FastCGI en posant
     * `REMOTE_ADDR` = l'adresse du CLIENT. Symfony remplace le jeton par cette
     * adresse, donc le client devient son propre proxy de confiance.
     *
     * MESURÉ en HTTP réel, depuis un conteneur voisin, avant correction :
     *   client 172.18.0.3 · apache 172.18.0.11
     *   X-Forwarded-For: 198.51.100.42  → request()->ip() = 198.51.100.42
     *   X-Forwarded-Host: evil.example  → getHost()       = evil.example
     *
     * C'était STRICTEMENT ÉQUIVALENT au `*` que ce jeton remplaçait. Le jeton
     * reste accepté — une topologie où PHP voit vraiment le proxy existe — mais il
     * est SIGNALÉ, donc `proxies:check` refuse le déploiement.
     */
    $parsed = TrustedProxies::parse(TrustedProxies::REMOTE_ADDR);

    expect($parsed['problems'])
        ->toHaveCount(1, 'REMOTE_ADDR passe sans être signalé : le déploiement certifierait la faille.');
    expect($parsed['problems'][0])->toContain('FastCGI');
});

/*
|------------------------------------------------------------------------------
| Les garde-fous du garde-fou — findings de la lentille adversariale, 2026-08-20
|------------------------------------------------------------------------------
*/

it('ships an empty TRUSTED_PROXIES default in .env.example', function (): void {
    /*
     * 🔴 CETTE LIGNE A PORTÉ UNE VALEUR DANGEREUSE DEUX FOIS — `*` jusqu'au
     *    2026-08-09, `REMOTE_ADDR` jusqu'au 2026-08-20 — chaque fois avec une
     *    justification confiante et fausse écrite juste à côté, chaque fois
     *    découverte par une revue ultérieure et non par un test.
     *
     * Rien ne gardait cette ligne : tous les tests de `TrustedProxies::parse()`
     * passent un argument LITTÉRAL, donc ils restent verts quoi que dise le
     * fichier que l'opérateur va réellement copier. Une troisième régression
     * serait aussi invisible que les deux premières.
     */
    $line = null;

    foreach (explode("\n", RepoFile::read('src/.env.example')) as $candidate) {
        if (str_starts_with(trim($candidate), 'TRUSTED_PROXIES=')) {
            $line = trim($candidate);

            break;
        }
    }

    expect($line)
        ->not->toBeNull('`.env.example` ne déclare plus TRUSTED_PROXIES du tout.');
    expect($line)
        ->toBe(
            'TRUSTED_PROXIES=',
            "`.env.example` livre [{$line}]. Le défaut doit être VIDE : `*` fait confiance à "
                . 'toute adresse d\'Internet, et `REMOTE_ADDR` désigne le CLIENT sous FastCGI — '
                . 'les deux rendent la clé de seau de limitation falsifiable.',
        );
});

it('registers proxies:check, and it refuses a bad value', function (): void {
    /*
     * ⚠️ LA DÉCISION D8 A DÉPLACÉ LE REFUS DANS UNE COMMANDE QUE RIEN N'EXÉCUTAIT.
     *
     * `TrustedProxies::parse()` était testé, mais la commande qui en fait une
     * porte de déploiement ne l'était pas : ni son enregistrement dans
     * `CoreServiceProvider::boot()`, ni son code de sortie. Une signature changée,
     * un `return self::SUCCESS` glissé dans la branche d'erreur, ou la commande
     * retirée de `$this->commands([...])` laissaient tout vert et la porte inerte.
     */
    expect(array_key_exists('proxies:check', Artisan::all()))
        ->toBeTrue('La commande `proxies:check` n\'est pas enregistrée : l\'entrypoint appelle une commande qui n\'existe pas.');

    config()
        ->set('proxies.problems', []);
    expect(Artisan::call('proxies:check'))
        ->toBe(0, 'Une configuration saine fait échouer le contrôle de déploiement.');

    config()
        ->set('proxies.problems', ['une entrée qui ne correspondra jamais']);
    expect(Artisan::call('proxies:check'))
        ->toBe(1, 'Une configuration signalée comme dangereuse laisse le déploiement passer.');
});

it('keeps the deploy gate outside the production-only block', function (): void {
    // Le contrôle vivait dans `if [ "$APP_ENV" = "production" ]` : un hôte
    // `staging` ou `preprod` démarrait sans lui, avec le `*` hérité d'un vieux
    // `.env` — l'état exact que ce contrôle refuse.
    $entrypoint = RepoFile::read('docker/php/scripts/docker-entrypoint.sh');

    expect(str_contains($entrypoint, 'php artisan proxies:check || exit 1'))
        ->toBeTrue('L\'entrypoint n\'exécute plus `proxies:check`, ou n\'abandonne plus sur son échec.');

    $gate = strpos($entrypoint, 'php artisan proxies:check');
    $cache = (int) strpos($entrypoint, 'php artisan config:cache');

    expect($gate)
        ->toBeLessThan(
            $cache,
            '`proxies:check` s\'exécute APRÈS `config:cache` : il contrôlerait une configuration déjà figée.',
        );
});

it('rejects a CIDR prefix impossible for its address family', function (): void {
    // `/64` sur une IPv4 passait le contrôle de forme, puis ne correspondait à
    // aucun client — `request()->ip()` rendait alors l'adresse du proxy, et tous
    // les clients derrière lui partageaient un seul seau. La borne était celle
    // de l'autre famille d'adresses.
    foreach (['10.0.0.0/64', '192.168.1.1/99', '10.0.0.0/033'] as $bogus) {
        expect(TrustedProxies::parse($bogus)['problems'])
            ->not->toBeEmpty("`{$bogus}` passe sans être signalé alors qu'il ne peut correspondre à aucun client.");
    }

    // Et les bornes légitimes restent acceptées, sans quoi le test précédent
    // serait satisfait par un contrôle qui refuse tout.
    foreach (['10.0.0.0/8', '192.168.1.1/32', '2001:db8::/32', '::1/128'] as $valid) {
        expect(TrustedProxies::parse($valid)['problems'])
            ->toBe([], "`{$valid}` est refusé alors qu'il est parfaitement valide.");
    }
});
