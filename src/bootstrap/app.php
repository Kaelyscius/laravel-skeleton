<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;
use Spatie\Csp\AddCspHeaders;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        /*
         * ─────────────────────────────────────────────────────────────────────
         * 🔴 LA VALEUR DE CONFIANCE AUX PROXYS N'EST PAS POSÉE ICI
         *
         * ⛔ NE PAS RAPATRIER `at:` DANS CE CALLBACK, NI PAR `env()`, NI PAR
         * `config()`, NI PAR UN `require` DE `config/proxies.php`.
         *
         * MESURÉ sur cette pile le 2026-08-20, pas déduit :
         *
         *   app()->bound('config')  →  false     ← à l'intérieur de ce callback
         *
         * `withMiddleware()` enregistre ce callback sur
         * `afterResolving(HttpKernel::class)`, et `Application::handleRequest()`
         * résout le noyau AVANT d'appeler `$kernel->handle()` — c'est-à-dire
         * avant le bootstrap. Rien de la configuration n'y est lisible.
         *
         * La correction précédente (revue du 2026-08-10, décision D3) avait
         * déplacé l'appel dans `config/proxies.php` puis l'avait `require` ICI :
         * l'`env()` avait changé de fichier, PAS DE MOMENT. Sous
         * `php artisan config:cache` — que l'entrypoint de production exécute —
         * `.env` n'est jamais chargé, `env()` rendait `null`, et la liste de
         * proxys de l'opérateur était remplacée en silence par `REMOTE_ADDR`.
         * Conséquence : `request()->ip()` rendait l'IP du load-balancer amont,
         * donc UN SEUL SEAU DE LIMITATION POUR TOUS LES CLIENTS. Finding Q1,
         * revue du 2026-08-20.
         *
         * → `CoreServiceProvider::boot()` pose `TrustProxies::at()`. Un provider
         *   boote après `LoadConfiguration`, donc il lit la valeur RÉELLE, y
         *   compris quand elle vient du cache de configuration. `TrustProxies`
         *   garde cette valeur dans un statique que `handle()` consulte à chaque
         *   requête : la poser au boot arrive à temps pour toutes.
         *
         * Le motif du choix de `REMOTE_ADDR` plutôt que `*` est écrit dans
         * `config/proxies.php`, à côté du code qui le décide.
         *
         * Les EN-TÊTES, eux, restent ici : ce sont des constantes de classe, sans
         * lecture de configuration, donc rien n'empêche de les poser à ce moment.
         * ─────────────────────────────────────────────────────────────────────
         */
        $middleware->trustProxies(
            headers: Request::HEADER_X_FORWARDED_FOR
                | Request::HEADER_X_FORWARDED_HOST
                | Request::HEADER_X_FORWARDED_PROTO
                | Request::HEADER_X_FORWARDED_PORT,
        );

        /*
         * FR3-3: Scope CSP to web group only (not global). The default Spatie Basic
         * preset injects strict nonces; applying it globally would break Filament/
         * Horizon/Pulse/Telescope dashboards whose inline <script> blocks don't
         * use @cspNonce.
         *
         * ─────────────────────────────────────────────────────────────────────
         * ⚠️ LA MISE EN GARDE N'EST PAS LEVÉE — ET LA PREMIÈRE MESURE ÉTAIT
         *    PRISE SUR LA MAUVAISE ROUTE
         *
         * Ce commentaire disait : « Future story wiring Filament admin
         * (Story 1.10) must either customize the policy or exclude admin routes
         * from CSP ». La Story 1.10a a mesuré `GET /admin/login`, n'y a vu aucun
         * en-tête, et a déclaré la mise en garde levée.
         *
         * La mesure était juste ; la conclusion ne l'était pas. Les PAGES du
         * panel sont servies hors du groupe `web`, mais toute INTERACTION passe
         * par l'endpoint de mise à jour de Livewire, unique pour l'application,
         * qui est dans `web` — donc derrière `AddCspHeaders`.
         *
         * MESURÉ à nouveau le 2026-08-20, CSP forcée à `true`, sur cette pile :
         *
         *   GET  /_layouts               (groupe `web`)  → CSP PRÉSENTE
         *   GET  /admin/login            (pages panel)   → CSP ABSENTE
         *   POST /livewire-<hash>/update (interactions)  → CSP PRÉSENTE  ← ICI
         *
         * Le trafic qui compte porte donc bien l'en-tête, et la question d'origine
         * — personnaliser la politique, ou exclure — reste ENTIÈRE. Finding Q3,
         * revue du 2026-08-20.
         *
         * ⛔ Ce n'est pas un défaut à corriger ici : `CSP_ENABLED=false` est la
         * valeur du dépôt (arbitrage PO du 2026-08-09), donc rien n'est cassé
         * aujourd'hui. C'est une DÉCISION à prendre avant d'allumer la CSP, et
         * elle doit être prise en sachant que le panel est concerné — ce que la
         * rédaction précédente faisait précisément oublier.
         *
         * Gardé par `tests/Feature/AdminPanelCspTest.php`, qui force le drapeau
         * pour ne pas être vert par extinction, et qui mesure les TROIS routes
         * ci-dessus — pas seulement celle qui arrangeait la conclusion.
         */
        $middleware->web(append: [AddCspHeaders::class]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        //
    })->create();
