<?php

declare(strict_types=1);

use App\Core\Http\Middleware\SetCurrentStreamer;
use App\Core\Models\Streamer;
use App\Models\User;
use Database\Seeders\DatabaseSeeder;
use Database\Seeders\RoleSeeder;
use Filament\Auth\Pages\Login;
use Filament\Facades\Filament;
use Filament\Models\Contracts\FilamentUser;
use Filament\Panel;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Schema;
use Livewire\Livewire;
use Spatie\Permission\Models\Role;
use Spatie\Permission\Traits\HasRoles;
use Tests\Support\HttpProbe;

uses(RefreshDatabase::class);

/**
 * Story 1.10a — AC3, AC6, AC9 : qui entre dans le panel, et à quelles conditions.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * ⚠️ CES TESTS S'EXÉCUTENT SUR LE CHEMIN DE PRODUCTION, ET C'EST UNE CHANCE
 *
 * Filament n'accorde le laissez-passer « tous les `App\Models\User` » qu'en
 * environnement **`local`** (voir le commentaire de sécurité dans
 * `Filament\Models\Contracts\FilamentUser`). Ailleurs — production comme
 * `testing` — le contrat est obligatoire.
 *
 * `phpunit.xml` force `APP_ENV=testing` en `<server>` ET en `<env>` (les deux
 * sont nécessaires : le helper `Env` de Laravel interroge `$_SERVER` en
 * premier). Ces tests exercent donc nativement le chemin le plus strict, celui
 * où « n'importe quel utilisateur entre dans le panel » ne peut pas rester
 * invisible.
 *
 * ⛔ LE CONTRE-MOUVEMENT À REFUSER : un test rouge parce que Filament refuse
 * l'accès n'est PAS un problème d'environnement. Basculer les tests en `local`
 * pour les faire passer détruirait la seule preuve que l'AC3 produit.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * ⛔ AUCUN `Gate::before` N'ACCORDE TOUT À `super-admin`
 *
 * C'est le raccourci habituel de Spatie Permission. Il transforme
 * l'autorisation en interrupteur global et rendrait les policies de l'Epic 5
 * indistinguables de leur absence. Ici le rôle contrôle L'ENTRÉE DU PANEL, et
 * rien d'autre.
 */

/**
 * Un utilisateur porteur du rôle `super-admin` (guard `web`).
 */
function superAdminUser(): User
{
    $user = User::factory()->create();
    $user->assignRole(Role::findOrCreate('super-admin', 'web'));

    return $user;
}

/*
|------------------------------------------------------------------------------
| AC3 — le contrat, sur le modèle
|------------------------------------------------------------------------------
*/

it('makes User implement the FilamentUser contract', function (): void {
    // Sans ce contrat, Filament REFUSE tout le monde hors `local` — la suite
    // serait donc verte sur ses assertions de refus, et muette sur l'accès.
    // C'est pourquoi la preuve discriminante est le test `super-admin` → 200.
    // `class_implements()` plutôt que `is_subclass_of()` : PHPStan sait résoudre
    // le second statiquement et signale « alreadyNarrowedType », c'est-à-dire
    // « cette assertion est toujours vraie ». Elle l'est aujourd'hui, et c'est
    // bien le sujet — ce test garde une ÉDITION FUTURE, pas l'état présent.
    // La réflexion runtime dit la même chose sans prétendre au contraire.
    // `class_implements()` rend `false` sur une classe introuvable : le `?: []`
    // n'est donc pas décoratif, il empêche un `in_array(…, false)` fatal de se
    // présenter comme un échec d'assertion ordinaire.
    $interfaces = class_implements(User::class) ?: [];

    expect(in_array(FilamentUser::class, $interfaces, true))->toBeTrue(
        'App\\Models\\User doit implémenter Filament\\Models\\Contracts\\FilamentUser.',
    );
});

it('gives User the Spatie HasRoles trait', function (): void {
    expect(in_array(HasRoles::class, class_uses_recursive(User::class), true))->toBeTrue(
        'App\\Models\\User doit utiliser Spatie\\Permission\\Traits\\HasRoles : '
        . 'sans lui, canAccessPanel() ne peut pas interroger de rôle.',
    );
});

it('refuses an authenticated user who carries no role', function (): void {
    $user = User::factory()->create();

    expect(HttpProbe::get('/admin', $user)->getStatusCode())
        ->toBe(403, 'Un utilisateur authentifié sans rôle a franchi la porte du panel.');
});

it('refuses the seeded test@example.com user by name', function (): void {
    // Nommé explicitement par l'AC3. Cet utilisateur est créé par
    // DatabaseSeeder avec le mot de passe `password` : il existe sur toute base
    // fraîchement semée, y compris en CI et chez un fork-streamer qui vient de
    // lancer `make fresh`. Qu'il n'ouvre PAS le panel est la propriété qui
    // sépare « appartenir à la table users » de « être administrateur ».
    Artisan::call('db:seed', [
        '--class' => DatabaseSeeder::class,
    ]);

    $seeded = User::query()->where('email', 'test@example.com')->firstOrFail();

    expect($seeded->hasRole('super-admin'))
        ->toBeFalse(
            'DatabaseSeeder ne doit JAMAIS donner super-admin à test@example.com.',
        );

    expect(HttpProbe::get('/admin', $seeded)->getStatusCode())
        ->toBe(403, 'test@example.com, semé par le dépôt, ouvre le panel.');
});

it('lets a super-admin reach the panel dashboard', function (): void {
    // LA preuve discriminante de l'AC3 : tous les refus ci-dessus seraient déjà
    // verts sans une ligne de code (Filament refuse par défaut hors `local`).
    // Seule cette assertion prouve que canAccessPanel() accorde vraiment, et
    // qu'il accorde sur le RÔLE.
    expect(HttpProbe::get('/admin', superAdminUser())->getStatusCode())
        ->toBe(200, 'Le porteur de super-admin n\'atteint pas le tableau de bord.');
});

it('grants the panel on the role, not on panel identity alone', function (): void {
    // canAccessPanel() doit vérifier DEUX choses : le panel demandé ET le rôle.
    // Un test qui n'observe que le panel `admin` laisserait passer une
    // implémentation `return $panel->getId() === 'admin';` — c'est-à-dire
    // « tout utilisateur authentifié entre », le défaut exact que le contrat
    // FilamentUser existe pour empêcher.
    $roleless = User::factory()->create();
    $admin = superAdminUser();

    $panel = Filament::getPanel('admin');

    expect($admin->canAccessPanel($panel))
        ->toBeTrue('Le porteur de super-admin doit entrer.');
    expect($roleless->canAccessPanel($panel))
        ->toBeFalse('Un utilisateur sans rôle ne doit pas entrer.');
});

/*
|------------------------------------------------------------------------------
| AC6 — le panel reste joignable sur une base sans streamer
|------------------------------------------------------------------------------
*/

it('serves the panel login page on a database with no streamer at all', function (): void {
    /*
     * CE TEST FIXE UNE DÉCISION, IL NE DÉCRIT PAS UN ACCIDENT.
     *
     * Les ROUTES PROPRES du panel (`/admin`, `/admin/login`) ne traversent pas
     * le groupe `web` : Filament leur construit sa propre pile. Sur ce
     * chemin-là, `SetCurrentStreamer` ne s'exécute donc pas, et c'est voulu en
     * v1 — aucun modèle tenant ne vit dans le panel avant l'Epic 5.
     *
     * ⚠️ CE N'EST VRAI QUE DES ROUTES PROPRES DU PANEL. Voir le test suivant :
     * toute INTERACTION du panel passe par l'endpoint de mise à jour de
     * Livewire, qui, lui, est bien dans le groupe `web`. La revue du 2026-08-10
     * a mesuré que l'affirmation « Filament ne traverse pas `web` », écrite ici
     * sans qualificatif, était fausse pour le chemin qui compte le plus.
     *
     * Ce test-ci reste le garde-fou de la pile du panel : il rougit si
     * quelqu'un ajoute `SetCurrentStreamer` aux middlewares du panel — vu
     * rouge, pas supposé (campagne de mutation, T10).
     */
    expect(Streamer::query()->count())->toBe(0, 'RefreshDatabase doit laisser la table streamers vide.');

    expect(HttpProbe::get('/admin/login')->getStatusCode())
        ->toBe(200, 'La page de connexion du panel ne répond pas 200 sur une base sans streamer.');
});

it('lets the panel be used on a database with no streamer — neither a 404 nor a 500', function (): void {
    /*
     * 🔴 CE QUE LA PAGE DE CONNEXION EN 200 NE PROUVAIT PAS — trouvé en revue
     *    le 2026-08-10, REPRODUIT avant d'être écrit ; puis rouvert le 2026-08-20.
     *
     * La page de connexion s'AFFICHE hors du groupe `web`. Mais la SOUMISSION du
     * formulaire est une requête Livewire, et Livewire n'a qu'UN endpoint de mise
     * à jour pour toute l'application :
     *
     *   POST /livewire-<hash>/update  →  middleware ['web', RequireLivewireHeaders]
     *   groupe `web`                  →  …, AddCspHeaders, SetCurrentStreamer
     *
     * Filament ne surcharge pas cette route (aucun `setUpdateRoute` dans
     * `vendor/filament`). Sur une base migrée non semée, la page s'affichait donc
     * en 200 et la connexion échouait — d'abord en 404, puis, après le correctif
     * du 2026-08-10, en 500.
     *
     * ⚠️ ET C'EST LÀ QUE LA REVUE DU 2026-08-20 A REPRIS L'AFFAIRE (décision D5).
     * Un 500 nommé est un meilleur message, pas une porte ouverte. L'AC6 n'existe
     * pas pour améliorer un diagnostic : elle existe pour qu'un fork-streamer ne
     * soit pas « sans aucun moyen de créer le streamer manquant, puisque la seule
     * interface pour le faire est ce panel ». Tant que l'interaction rendait 500,
     * cette propriété restait NON TENUE — l'impasse était renommée, pas levée.
     *
     * ⛔ La correction n'a PAS été d'exclure cette route de `SetCurrentStreamer` :
     * elle est partagée par tous les composants Livewire de l'application, y
     * compris les futurs composants publics qui ont besoin du contexte tenant. On
     * échangerait un échec visible contre une fuite de contexte silencieuse.
     *
     * La correction est que le middleware enregistre un RÉSOLVEUR : rien n'est lu
     * en base tant que personne ne demande `CurrentStreamer`. La connexion au
     * panel ne touche aucun modèle tenant, donc elle aboutit. Le « fail-loud »
     * n'est pas perdu pour autant — `TenancyPatternCTest` garde qu'une résolution
     * réelle lève toujours l'exception nommée.
     */
    /*
     * 📌 LA PROPRIÉTÉ MESURÉE EST UNE ÉGALITÉ, PAS UN CODE DE STATUT.
     *
     * Un `not->toBe(404)` serait faux ici : 404 est la réponse NORMALE de
     * Livewire à un corps de requête sans composant, avec ou sans streamer. Ce
     * qu'il faut prouver, c'est que l'absence de streamer NE CHANGE RIEN au
     * parcours — donc que les deux mesures coïncident. Cette formulation garde
     * aussi les deux bornes d'un coup : si la liaison redevenait empressée, la
     * mesure « base vide » partirait en 500 et l'égalité rougirait.
     */
    expect(Streamer::query()->count())->toBe(0, 'RefreshDatabase doit laisser la table streamers vide.');

    $probe = static fn (): int => HttpProbe::post(
        HttpProbe::livewireUpdateUri(),
        '{"components":[]}',
        [
            'HTTP_X_LIVEWIRE' => '1',
            'CONTENT_TYPE' => 'application/json',
        ],
    )->getStatusCode();

    $withoutStreamer = $probe();

    expect($withoutStreamer)
        ->toBeLessThan(
            500,
            "L'endpoint d'interaction du panel rend {$withoutStreamer} sur une base sans streamer : "
                . 'l\'opérateur reste enfermé dehors, et l\'AC6 n\'est pas tenue (décision D5).',
        );

    Streamer::factory()->create();

    expect($probe())
        ->toBe(
            $withoutStreamer,
            'Le parcours d\'interaction du panel ne rend pas le même statut avec et sans streamer : '
                . 'l\'absence de streamer influence donc encore la seule surface capable de le créer.',
        );
});

it('refuses a super-admin on a panel that is not the admin panel', function (): void {
    /*
     * 🔴 LA MOITIÉ DU CONTRAT QUI N'ÉTAIT GARDÉE PAR RIEN — finding Q2, revue du
     *    2026-08-20, MUTATION VUE VERTE avant correction.
     *
     * Le docblock de `canAccessPanel()` consacre un paragraphe à justifier la
     * vérification du panel : « un second panel ajouté plus tard hériterait
     * silencieusement de l'autorisation du panel d'administration ». Or tous les
     * tests d'accès résolvaient LE MÊME panel (`Filament::getPanel('admin')`), y
     * compris celui nommé « grants the panel on the role, not on panel identity
     * alone », qui n'observait que la dimension rôle.
     *
     * La revue a APPLIQUÉ la mutation `return $this->hasRole('super-admin');` et
     * relancé la suite entière : 226 tests, 0 échec. Le paragraphe défendait une
     * ligne que rien ne gardait, sur la seule surface d'authentification du
     * produit — le motif dominant de ce dépôt, à sa place la plus coûteuse.
     *
     * Ce test est le rouge de cette mutation. Il fabrique un second panel — celui
     * de l'Epic 5, en avance — et exige que le rôle d'administration n'y ouvre
     * rien.
     */
    Role::findOrCreate(RoleSeeder::SUPER_ADMIN, 'web');

    $admin = User::factory()->create();
    $admin->assignRole(RoleSeeder::SUPER_ADMIN);

    $adminPanel = Filament::getPanel('admin');
    $otherPanel = Panel::make()->id('streamer')->path('streamer');

    expect($admin->canAccessPanel($adminPanel))
        ->toBeTrue('Le porteur de super-admin doit entrer dans le panel d\'administration.');

    expect($admin->canAccessPanel($otherPanel))
        ->toBeFalse(
            'Le rôle `super-admin` ouvre un panel qui n\'est PAS le panel d\'administration : '
                . 'tout panel ajouté plus tard héritera silencieusement de cette autorisation, '
                . 'et la décision d\'ouvrir un panel cessera d\'être écrite panel par panel.',
        );
});

it('binds the panel gate to the role name the seeder decides, not to a re-typed literal', function (): void {
    /*
     * ⚠️ finding Q13. `RoleSeeder::SUPER_ADMIN` était défini puis employé nulle
     * part : `canAccessPanel()` retapait `'super-admin'` en dur, et le littéral
     * était recopié dans les tests et deux docblocks — six copies et plus du lien
     * seeder ↔ porte, dans un diff qui combat la « seconde source de vérité »
     * partout ailleurs.
     *
     * Second point, celui qui mord : le seeder épingle le guard `web` en
     * expliquant que `auth.defaults.guard` est modifiable, mais `hasRole()` sans
     * guard le résout depuis le modèle. Le producteur se défendait, le
     * consommateur pas.
     */
    Role::findOrCreate(RoleSeeder::SUPER_ADMIN, 'web');

    $admin = User::factory()->create();
    $admin->assignRole(RoleSeeder::SUPER_ADMIN);

    expect($admin->canAccessPanel(Filament::getPanel('admin')))->toBeTrue();

    /*
     * ⚠️ CE QUI N'EST **PAS** GARDÉ ICI, ET POURQUOI C'EST ÉCRIT PLUTÔT QUE SIMULÉ.
     *
     * `canAccessPanel()` passe `'web'` explicitement à `hasRole()`. C'est plus sûr
     * que de laisser Spatie résoudre le guard depuis le modèle, et le docblock de
     * `RoleSeeder` décrit précisément ce risque. Mais AUCUNE mutation atteignable
     * ne le démontre aujourd'hui, et c'est mesuré, pas supposé :
     *
     *   • retirer le second argument (`hasRole(RoleSeeder::SUPER_ADMIN)`) laisse
     *     TOUTE la suite verte — mutation appliquée le 2026-08-20 ;
     *   • un rôle homonyme sur un autre guard n'est pas constructible : Spatie
     *     lève `GuardDoesNotMatch` à l'attribution — constaté le même jour ;
     *   • basculer `auth.defaults.guard` ne suffit pas : Spatie ne lit pas ce
     *     réglage, il apparie le PROVIDER du modèle aux guards déclarés.
     *
     * Un test écrit là-dessus serait donc vert quoi qu'il arrive. Il est
     * délibérément absent, et cette note tient sa place : l'argument explicite
     * reste une précaution justifiée, pas un invariant gardé — et le lecteur qui
     * le retirera saura qu'il ne le retire pas contre un test, mais contre un
     * raisonnement.
     */
});

it('actually opens the door: a super-admin signs in with real credentials and lands authenticated', function (): void {
    /*
     * 🔴 CE QUE TOUS LES AUTRES TESTS D'ACCÈS NE PROUVAIENT PAS — finding Q5,
     *    revue du 2026-08-20.
     *
     * Chaque assertion d'accès de ce fichier injecte l'utilisateur EN PROCESSUS
     * (`HttpProbe::get($uri, $user)` → `Auth::guard('web')->login()`) : pas
     * d'identifiants, pas de formulaire, pas d'aller-retour de session. Et les
     * tests de limitation n'appellent `authenticate()` qu'avec un mauvais mot de
     * passe. Résultat : aucun test de la suite n'établissait qu'une CONNEXION
     * RÉUSSIE est possible.
     *
     * Conséquence mesurée en revue : une régression de cookie de session, de
     * `SESSION_DOMAIN`, de `LoginResponse` ou d'`AuthenticateSession` produisait
     * 419/403/302 dans un navigateur pendant que toute la suite restait verte —
     * et l'opérateur qui suit la procédure documentée (`make:filament-user` puis
     * `assignRole`) ne pouvait pas entrer. La seule porte du produit pouvait être
     * livrée fermée, avec un rapport de test impeccable.
     *
     * ⚠️ Ce test exerce le chemin RÉEL de Filament : le composant Livewire de la
     * page de connexion, avec le bon mot de passe. Le `POST /admin/login` n'existe
     * pas (§11 de la story) — c'est `authenticate()` qui authentifie.
     */
    Role::findOrCreate('super-admin', 'web');

    $admin = User::factory()->create([
        'email' => 'operator@example.com',
        'password' => Hash::make('correct-horse-battery-staple'),
    ]);
    $admin->assignRole('super-admin');

    expect(Filament::auth()->check())->toBeFalse('La session doit partir non authentifiée.');

    Livewire::test(Login::class)
        ->fillForm([
            'email' => 'operator@example.com',
            'password' => 'correct-horse-battery-staple',
        ])
        ->call('authenticate')
        ->assertHasNoFormErrors();

    expect(Filament::auth()->check())
        ->toBeTrue(
            'Les identifiants sont bons et le rôle est porté, mais la session n\'est pas '
                . 'authentifiée après `authenticate()` : la porte du panel ne s\'ouvre pas.',
        );
    expect(Filament::auth()->id())
        ->toBe($admin->getKey(), 'La session authentifiée ne porte pas l\'utilisateur attendu.');
});

it('refuses the same real credentials when the role is missing', function (): void {
    /*
     * LE CONTRE-TEST DE Q5, sans lequel le précédent serait satisfait par un
     * panel qui ouvre à tout le monde. Mêmes identifiants valides, pas de rôle :
     * l'authentification peut réussir, mais l'accès au panel doit être refusé.
     */
    $user = User::factory()->create([
        'email' => 'roleless@example.com',
        'password' => Hash::make('correct-horse-battery-staple'),
    ]);

    expect($user->canAccessPanel(Filament::getPanel('admin')))
        ->toBeFalse('Un utilisateur sans rôle passe la porte du panel.');

    expect(HttpProbe::get('/admin', $user)->getStatusCode())
        ->toBe(403, 'Un utilisateur authentifié sans rôle n\'est pas refusé par le panel.');
});

it('keeps SetCurrentStreamer out of the panel\'s own middleware stack', function (): void {
    /*
     * ⚠️ LE GARDE-FOU EST DEVENU STRUCTUREL, ET C'EST DÉLIBÉRÉ.
     *
     * La mutation M7 de la campagne — « ajouter `SetCurrentStreamer` à la pile du
     * panel » — rougissait par le SYMPTÔME : la pile du panel résolvait le
     * contexte, la base était vide, la requête partait en erreur. Depuis que la
     * liaison est paresseuse (décision D5), ce symptôme n'existe plus : la
     * mutation ne rougirait plus rien, et le garde-fou serait devenu silencieux
     * sans que personne le remarque.
     *
     * On garde donc la propriété elle-même, pas sa conséquence : le panel construit
     * sa propre pile, et ce middleware n'y a pas sa place — il appartient au groupe
     * `web`, que le panel ne traverse que par l'endpoint partagé de Livewire.
     */
    $middleware = Filament::getPanel('admin')->getMiddleware();

    expect($middleware)
        ->not->toContain(
            SetCurrentStreamer::class,
            'SetCurrentStreamer a été ajouté à la pile propre du panel : le contexte tenant '
                . 'serait résolu sur des pages qui n\'en ont pas besoin, et l\'AC6 retomberait.',
        );
});

it('lets the panel interact normally once a streamer exists', function (): void {
    /*
     * LE CONTRE-TEST, sans lequel le précédent serait satisfait par un 500
     * permanent. Il borne l'autre côté : avec un streamer, l'endpoint
     * d'interaction ne rend PLUS 500 — le 500 vient bien de l'absence de
     * streamer, pas de la pile de middleware ni du corps de requête.
     *
     * (Le 404 attendu ici est celui de Livewire lui-même, qui ne trouve aucun
     * composant dans un corps de requête volontairement vide. C'est la preuve
     * que la requête est allée jusqu'à lui.)
     */
    Streamer::factory()->create();

    $status = HttpProbe::post(
        HttpProbe::livewireUpdateUri(),
        '{"components":[]}',
        [
            'HTTP_X_LIVEWIRE' => '1',
            'CONTENT_TYPE' => 'application/json',
        ],
    )->getStatusCode();

    expect($status)
        ->not->toBe(
            500,
            'L\'endpoint d\'interaction du panel rend 500 ALORS QU\'UN STREAMER EXISTE : '
                . 'le test précédent ne mesure donc pas l\'absence de streamer.',
        );
});

/*
|------------------------------------------------------------------------------
| AC9 — Sanctum n'authentifie rien ici ; c'est le guard de session `web`
|------------------------------------------------------------------------------
*/

it('authenticates the panel through the web session guard, never Sanctum', function (): void {
    /*
     * POURQUOI CE TEST EXISTE ALORS QUE PERSONNE N'A ÉCRIT DE CODE SANCTUM.
     *
     * La rédaction d'origine de la story (epics.md) annonçait « login sur
     * /admin via Sanctum cookie SPA ». C'est faux, et vérifié le 2026-08-09 :
     * Sanctum est installé mais totalement INERTE dans ce dépôt — sa migration
     * est distribuée par publishesMigrations(), n'a jamais été publiée, et la
     * table personal_access_tokens n'existe pas.
     *
     * Ce test fixe le mécanisme réel pour que l'affirmation ne revienne pas.
     */
    $panel = Filament::getPanel('admin');

    expect($panel->getAuthGuard())
        ->toBe('web', 'Le panel doit s\'authentifier par le guard de session `web`.');
    expect(config('auth.guards.web.driver'))
        ->toBe('session');

    // Et la table Sanctum n'existe toujours pas : la story n'a rien publié.
    expect(Schema::hasTable('personal_access_tokens'))->toBeFalse(
        'Une table personal_access_tokens est apparue : un vendor:publish Sanctum a eu lieu, '
        . 'contrairement à l\'AC9.',
    );
});

it('does not leak an authenticated session into the next anonymous probe', function (): void {
    /*
     * 🔴 finding Q12 — ET SON GARDE, ÉCRIT PARCE QUE LA MUTATION EST RESTÉE VERTE.
     *
     * `HttpProbe::get($uri, $user)` connecte sur le guard `web` ; rien ne
     * déconnectait. Deux sondes dans le même test partageaient donc la session :
     * après une sonde authentifiée, une sonde « anonyme » tournait ENCORE
     * AUTHENTIFIÉE. Une assertion de refus pouvait passer sans avoir jamais
     * exercé le chemin anonyme — sur les tests d'accès au panel, c'est-à-dire là
     * où le refus EST la propriété.
     *
     * ⚠️ La correction (un `logout()` explicite dans la branche anonyme) a d'abord
     * été livrée SANS ce test : la mutation « retirer le logout » a été appliquée
     * et la suite est restée verte. Ce test est le rouge de cette mutation.
     */
    Role::findOrCreate(RoleSeeder::SUPER_ADMIN, 'web');

    $admin = User::factory()->create();
    $admin->assignRole(RoleSeeder::SUPER_ADMIN);

    expect(HttpProbe::get('/admin', $admin)->getStatusCode())
        ->toBe(200, 'La sonde authentifiée n\'entre pas dans le panel : le préalable est faux.');

    // La MÊME sonde, sans utilisateur. Elle doit être anonyme, donc redirigée
    // vers la page de connexion — jamais servie comme si elle était connectée.
    expect(HttpProbe::get('/admin')->getStatusCode())
        ->not->toBe(
            200,
            'Une sonde anonyme obtient le tableau de bord : la session de la sonde précédente '
                . 'a fuité, et toute assertion de refus de ce fichier peut être verte sans avoir '
                . 'exercé le chemin anonyme.',
        );
});
