<?php

declare(strict_types=1);

use App\Core\Providers\CoreServiceProvider;
use App\Modules\Admin\Providers\AdminServiceProvider;
use App\Modules\Admin\Providers\Filament\AdminPanelProvider;
use App\Modules\Public\Providers\PublicServiceProvider;
use App\Providers\AppServiceProvider;
use Illuminate\Contracts\Http\Kernel;
use Illuminate\Foundation\Application;
use Illuminate\Http\Request;
use Tests\Support\HttpProbe;
use Tests\Support\ModuleBoot;
use Tests\Support\RepoFile;

/**
 * Story 1.10a — AC2 : le panel vit dans le module `Admin`, et s'éteint avec lui.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * CE QUE CE FICHIER GARDE, ET POURQUOI ÇA N'EST PAS DE L'ORGANISATION DE CODE
 *
 * `php artisan filament:install --panels` fait deux choses que ce projet a
 * décidé de ne pas accepter :
 *
 *   1. il pose le provider sous `app/Providers/Filament/` — alors qu'ADR-0009
 *      assigne à `app/Modules/Admin/` la mention littérale « Filament panels
 *      + Sanctum + Spatie Permission » ;
 *   2. il l'enregistre dans `bootstrap/providers.php`, qui est INCONDITIONNEL
 *      par construction (c'est là que vit `CoreServiceProvider`, transversal
 *      *par décision*).
 *
 * ADR-0009 §Conséquences écrit : « un module désactivé via ENV ne charge ni ses
 * routes, ni ses migrations, ni ses **Filament resources** ». Laissé tel quel,
 * `MODULE_ADMIN_ENABLED=false` aurait continué de servir `/admin` — et RIEN ne
 * l'aurait dit : `ModuleActivationTest` observe les providers de MODULE, et le
 * `PanelProvider` aurait été chargé correctement, depuis le mauvais endroit.
 *
 * C'est la forme exacte du défaut trouvé par la story 0b — un mécanisme
 * d'activation auquel le code est sourd, avec 58 tests verts — transposée sur
 * la seule surface d'authentification du produit.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * POURQUOI DEUX NIVEAUX D'OBSERVATION (providers ET routes)
 *
 * Les deux peuvent diverger, et c'est précisément le défaut qu'on garde :
 * un panel enregistré hors du module ne se voit PAS dans la liste des providers
 * de module, mais se voit dans la table de routage. Observer les seuls
 * providers laisserait passer exactement ce qu'on cherche à interdire.
 *
 * @see docs/adr/ADR-0009-modular-app-modules-psr4.md
 */

/**
 * Toutes les URIs de routes vues par une application démarrée avec `$env`.
 *
 * @param  array<string, string>  $env
 * @return array<int, string>
 */
function adminPanelRouteUris(array $env): array
{
    return ModuleBoot::routeUris($env);
}

/**
 * Les URIs ci-dessus qui appartiennent au panel (`admin`, `admin/login`, …).
 *
 * @param  array<int, string>  $uris
 * @return array<int, string>
 */
function adminPanelRoutesAmong(array $uris): array
{
    return array_values(array_filter(
        $uris,
        // ⚠️ PAS SEULEMENT LE PRÉFIXE `admin/` (finding Q15, revue du 2026-08-20).
        // Toutes les routes du panel ne le portent pas : exports, imports et
        // routes de plugins vivent ailleurs dans la table. Filtrer sur le seul
        // préfixe laissait ces routes-là invisibles au garde-fou, donc encore
        // enregistrées module éteint pendant que l'AC2 restait verte.
        static fn (string $uri): bool => $uri === 'admin'
            || str_starts_with($uri, 'admin/')
            || str_contains($uri, 'filament'),
    ));
}

it('keeps the panel provider inside the Admin module namespace', function (): void {
    expect(class_exists(AdminPanelProvider::class))->toBeTrue(
        'Le PanelProvider doit vivre sous App\\Modules\\Admin\\Providers\\Filament (ADR-0009), '
        . 'pas sous app/Providers/Filament/ où filament:install le dépose.',
    );

    $reflection = new ReflectionClass(AdminPanelProvider::class);
    $file = (string) $reflection->getFileName();

    expect(str_contains($file, '/app/Modules/Admin/Providers/Filament/'))
        ->toBeTrue(
            "Le PanelProvider est chargé depuis {$file} — attendu sous app/Modules/Admin/Providers/Filament/.",
        );
});

it('leaves no generated provider directory behind', function (): void {
    // `filament:install` crée `app/Providers/Filament/`. Le déplacement n'est
    // complet que si l'original a disparu : deux PanelProvider dont un seul est
    // enregistré, c'est une seconde source de vérité qui attend son lecteur.
    expect(is_dir(base_path('app/Providers/Filament')))
        ->toBeFalse(
            'app/Providers/Filament/ existe encore : le panel généré n\'a pas été déplacé, il a été copié.',
        );
});

it('never registers the panel from the unconditional bootstrap/providers.php', function (): void {
    /**
     * ⚠️ On lit le TABLEAU RETOURNÉ, pas le texte du fichier.
     *
     * La première rédaction de ce test faisait `str_contains(<source>,
     * 'AdminPanelProvider')`. Elle a rougi immédiatement — sur le COMMENTAIRE
     * qui explique justement pourquoi le provider a été retiré. Un garde-fou
     * qui ne distingue pas le code de la prose accuse la documentation et
     * pousse à l'effacer : il se serait « réparé » en supprimant la seule trace
     * du motif.
     *
     * Le référent réel est la liste de providers que ce fichier PRODUIT. C'est
     * elle que Laravel consomme, et c'est donc elle qu'on observe.
     *
     * @var array<int, class-string>
     */
    $unconditional = require RepoFile::root() . '/src/bootstrap/providers.php';

    expect(in_array(AdminPanelProvider::class, $unconditional, true))->toBeFalse(
        'bootstrap/providers.php est INCONDITIONNEL : un PanelProvider enregistré là '
        . 'continuerait de servir /admin avec MODULE_ADMIN_ENABLED=false (ADR-0009 §Conséquences).',
    );

    // ⚠️ La contrepartie — « quelqu'un DOIT tout de même l'enregistrer » — n'est
    // pas ré-assertée ici par une seconde lecture de source. Elle est prouvée
    // dynamiquement par « loads the panel provider when the Admin module is
    // enabled » : ce test-là observe le provider effectivement chargé par une
    // application réelle, ce qu'aucun grep ne peut établir. Sans cette
    // contrepartie, « absent de bootstrap/providers.php » serait aussi satisfait
    // par un panel que personne n'enregistre nulle part.
});

it('loads the panel provider when the Admin module is enabled', function (): void {
    $loaded = ModuleBoot::loadedProviders([
        'MODULE_ADMIN_ENABLED' => 'true',
    ]);

    expect(array_key_exists(AdminServiceProvider::class, $loaded))->toBeTrue(
        'MODULE_ADMIN_ENABLED=true mais AdminServiceProvider n\'est pas chargé.',
    );
    expect(array_key_exists(AdminPanelProvider::class, $loaded))->toBeTrue(
        'AdminServiceProvider est chargé mais il n\'enregistre pas le PanelProvider.',
    );
});

it('serves the panel routes when the Admin module is enabled', function (): void {
    $panelRoutes = adminPanelRoutesAmong(adminPanelRouteUris([
        'MODULE_ADMIN_ENABLED' => 'true',
    ]));

    expect($panelRoutes)
        ->not->toBeEmpty();

    // Sans cette moitié, un test qui compte « au moins une route admin » resterait
    // vert si Filament n'exposait qu'une page d'erreur. C'est la page de connexion
    // qui prouve qu'il y a une porte.
    expect(in_array('admin/login', $panelRoutes, true))
        ->toBeTrue(
            'Le panel est monté mais n\'expose pas admin/login : ->login() a-t-il disparu du provider ?',
        );
});

it('really stops loading the panel provider when the Admin module is disabled', function (): void {
    $loaded = ModuleBoot::loadedProviders([
        'MODULE_ADMIN_ENABLED' => 'false',
    ]);

    expect(array_key_exists(AdminServiceProvider::class, $loaded))->toBeFalse(
        'MODULE_ADMIN_ENABLED=false mais AdminServiceProvider est chargé : le flag est inerte.',
    );
    expect(array_key_exists(AdminPanelProvider::class, $loaded))->toBeFalse(
        'MODULE_ADMIN_ENABLED=false mais le PanelProvider est chargé — il est enregistré '
        . 'hors du module (bootstrap/providers.php ?), donc /admin reste servi.',
    );

    // Éteindre Admin ne doit pas éteindre le site : sans cette moitié, un
    // register() qui n'enregistre RIEN passerait les deux assertions ci-dessus.
    expect(array_key_exists(PublicServiceProvider::class, $loaded))
        ->toBeTrue('Désactiver Admin a aussi emporté Public.');
    expect(array_key_exists(CoreServiceProvider::class, $loaded))
        ->toBeTrue('Core doit rester inconditionnel (bootstrap/providers.php).');
});

/**
 * Les deux routes que le PAQUET Filament enregistre lui-même, hors de tout panel.
 *
 * ⚠️ ELLES NE SONT PAS UNE EXCEPTION DE CONFORT — elles ont été MESURÉES le
 * 2026-08-20 en élargissant le filtre de ce fichier (finding Q15). Le filtre
 * ne retenait que le préfixe `admin/` et ne les voyait donc pas ; l'AC2 disait
 * « aucune route Filament n'est enregistrée » et le garde-fou n'en vérifiait
 * qu'une partie.
 *
 * Elles sont enregistrées par le `ServiceProvider` du paquet (découverte
 * Composer), pas par `AdminPanelProvider`, donc `MODULE_ADMIN_ENABLED=false` ne
 * les éteint pas — et ne peut pas les éteindre sans désinstaller le paquet.
 * Elles portent le seul middleware `filament.actions` et servent des
 * téléchargements signés d'export/import : sans panel enregistré et sans URL
 * signée valide, elles ne donnent accès à rien.
 *
 * Cette liste est FERMÉE : toute route Filament supplémentaire apparaissant
 * module éteint fera rougir le test, ce qui est le comportement voulu — c'est le
 * jour où quelqu'un aura enregistré du panel hors du mécanisme d'activation.
 *
 * @var list<string>
 */
const FILAMENT_PACKAGE_ROUTES = [
    'filament/exports/{export}/download',
    'filament/imports/{import}/failed-rows/download',
];

it('registers no panel route at all when the Admin module is disabled', function (): void {
    $panelRoutes = adminPanelRoutesAmong(adminPanelRouteUris([
        'MODULE_ADMIN_ENABLED' => 'false',
    ]));

    $unexpected = array_values(array_diff($panelRoutes, FILAMENT_PACKAGE_ROUTES));

    expect($unexpected)
        ->toBe(
            [],
            'MODULE_ADMIN_ENABLED=false laisse des routes de panel enregistrées : '
                . implode(', ', $unexpected) . ' — donc /admin ne répond pas 404.',
        );
});

it('leaves only the package-level Filament routes behind, and they serve nothing', function (): void {
    /*
     * LE CONTRE-TEST DE LA LISTE CI-DESSUS. Sans lui, `array_diff` serait une
     * autorisation permanente : on pourrait y ajouter n'importe quoi et le
     * garde-fou d'AC2 s'éteindrait sans bruit. Ici on exige que ces deux routes
     * soient EFFECTIVEMENT PRÉSENTES module éteint — donc que la liste décrive un
     * fait, pas une commodité — et qu'elles ne soient pas atteignables.
     */
    $panelRoutes = adminPanelRoutesAmong(adminPanelRouteUris([
        'MODULE_ADMIN_ENABLED' => 'false',
    ]));

    expect(array_values(array_intersect(FILAMENT_PACKAGE_ROUTES, $panelRoutes)))
        ->toBe(
            FILAMENT_PACKAGE_ROUTES,
            'La liste des routes de paquet tolérées ne correspond plus à ce que Filament '
                . 'enregistre : elle autorise donc des routes qui n\'existent pas, et n\'est plus '
                . 'un constat mais une permission.',
        );

    /*
     * ⚠️ CE QU'ON MESURE EST UNE INVARIANCE, PAS UN CODE DE STATUT — et la première
     *    rédaction se trompait deux fois.
     *
     * Elle assertait `>= 400`, borne assez lâche pour avaler n'importe quoi. La
     * lentille adversariale l'a relevé (2026-08-20) en mesurant un **500**, et a
     * diagnostiqué `NoDefaultPanelSetException` — un panel par défaut absent.
     * VÉRIFIÉ : c'est faux. L'exception réellement levée est un `QueryException`,
     * `relation "exports" does not exist` : ces routes lient un modèle `Export`
     * dont ce projet n'a jamais publié la migration, et n'en a pas besoin.
     *
     * Conséquence : le 500 n'a RIEN à voir avec le gate de module. Il se produit
     * à l'identique module allumé. La propriété honnête n'est donc pas « ces
     * routes refusent », c'est « le gate ne les influence pas » — ce qui est le
     * vrai sujet de l'AC2 — et « elles ne servent jamais rien ».
     *
     * ⛔ Un renderer transformant `NoDefaultPanelSetException` en 404 a été écrit
     * puis RETIRÉ : il aurait gardé une exception qui ne survient jamais ici.
     */
    $statusWithModule = static function (string $enabled): int {
        /** @var int $status */
        $status = ModuleBoot::withEnv(
            [
                'MODULE_ADMIN_ENABLED' => $enabled,
            ],
            static fn (): int => HttpProbe::get('/filament/exports/1/download')->getStatusCode(),
        );

        return $status;
    };
    $off = $statusWithModule('false');
    $on = $statusWithModule('true');

    expect($off)
        ->toBe(
            $on,
            "Une route de PAQUET Filament rend {$off} module éteint et {$on} module allumé : "
                . 'le gate de module l\'influence, alors qu\'elle ne lui appartient pas.',
        );

    expect($off)
        ->not->toBe(200, "Une route de paquet Filament rend 200 module éteint : elle sert quelque chose.");
});

it('answers 404 on GET /admin when the Admin module is disabled', function (): void {
    // La preuve littérale de l'AC : pas « aucune route ne correspond », mais le
    // code de statut qu'un visiteur reçoit vraiment. La requête traverse le
    // noyau HTTP de l'application jetable, middlewares compris.
    $observed = ModuleBoot::withEnv(
        [
            'MODULE_ADMIN_ENABLED' => 'false',
        ],
        static function (Application $app): int {
            /** @var Kernel $kernel */
            $kernel = $app->make(Kernel::class);

            return $kernel->handle(Request::create('/admin', 'GET'))
                ->getStatusCode();
        },
    );

    $status = is_int($observed) ? $observed : -1;

    expect($status)
        ->toBe(404, "GET /admin répond {$status} avec MODULE_ADMIN_ENABLED=false.");
});

it('redirects GET /admin to the panel login page when the module is enabled', function (): void {
    // Ici on interroge l'application de test ORDINAIRE : c'est le chemin réel,
    // et il doit mener à une porte, pas à un mur.
    $response = HttpProbe::get('/admin');

    expect($response->getStatusCode())
        ->toBe(302);
    expect($response->headers->get('Location'))
        ->toContain('/admin/login');
});

it('registers Core before the module providers, and pins that order', function (): void {
    /*
     * 🔴 UN INVARIANT DE COMPORTEMENT QUI N'ÉTAIT GARDÉ QUE PAR UN COMMENTAIRE.
     *
     * `bootstrap/providers.php` a vu son ordre s'inverser en silence le
     * 2026-08-09 — `AppServiceProvider, CoreServiceProvider` → l'inverse. C'était
     * une CORRECTION (ADR-0009:102 : le cœur d'abord, puisque
     * `AppServiceProvider::register()` enregistre les providers de module et que
     * ceux-ci dépendent des liaisons du cœur), mais elle est passée sans une
     * ligne : ni dans le commentaire de 18 lignes du fichier, ni dans la File
     * List, ni dans le Change Log.
     *
     * Le remède retenu à la revue du 2026-08-20 avait été… un commentaire de
     * plus, qui écrivait lui-même « ⛔ Aucun test n'observe l'ORDRE … cette note
     * est la seule chose qui empêche quelqu'un de le réinverser en croyant
     * ranger ». La lentille adversariale a relevé qu'un garde-fou déclarant son
     * propre vide reste un vide. Le voici.
     */
    $providers = require RepoFile::root() . '/src/bootstrap/providers.php';

    expect($providers)
        ->toBe(
            [
                CoreServiceProvider::class,
                AppServiceProvider::class,
            ],
            'L\'ordre d\'enregistrement des providers inconditionnels a changé. ADR-0009:102 exige '
                . 'le cœur AVANT les modules : AppServiceProvider::register() enregistre les providers '
                . 'de module, qui dépendent des liaisons de Core (CurrentStreamer notamment).',
        );
});
