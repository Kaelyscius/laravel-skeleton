<?php

declare(strict_types=1);

use App\Models\User;
use Database\Seeders\DatabaseSeeder;
use Database\Seeders\RoleSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Artisan;
use Spatie\Permission\Models\Role;
use Tests\Support\HttpProbe;

uses(RefreshDatabase::class);

/**
 * Story 1.10a — AC4 : le rôle `super-admin` est semé, l'administrateur ne l'est pas.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * POURQUOI LE SEEDER POSE UN RÔLE ET JAMAIS UN UTILISATEUR
 *
 * Un `super-admin` semé porte forcément un mot de passe connu du dépôt. Or
 * `DatabaseSeeder` tourne dans `make fresh`, en CI, et sur n'importe quel
 * déploiement mal découpé : ce compte existerait donc, avec ce mot de passe,
 * partout où la commande passe.
 *
 * Le partage retenu est celui-ci : le seeder pose le RÔLE — qui n'est un secret
 * pour personne — et l'opérateur pose l'UTILISATEUR, par
 * `php artisan make:filament-user` (fourni par Filament). Le fork-streamer
 * d'ADR-0001 est exactement dans ce cas : il clone, il seed, il crée son compte.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * POURQUOI CES TESTS VÉRIFIENT L'IDEMPOTENCE PAR UN VRAI SECOND PASSAGE
 *
 * `Role::findOrCreate()` est idempotent par construction — l'affirmer ne coûte
 * rien et ne prouve rien. Ce qui peut casser, c'est la CHAÎNE : un seeder ajouté
 * plus tard qui crée le rôle par un autre chemin, un guard différent qui produit
 * un second enregistrement de même nom, un `DatabaseSeeder` qui appelle deux
 * fois. Ces tests exécutent donc réellement `db:seed` deux fois et comptent.
 */
it('creates exactly one super-admin role on the web guard', function (): void {
    Artisan::call('db:seed', [
        '--class' => RoleSeeder::class,
    ]);

    $roles = Role::query()->where('name', 'super-admin')->get();

    expect($roles)
        ->toHaveCount(1);
    expect($roles->first()?->guard_name)
        ->toBe(
            'web',
            'Le rôle doit porter le guard `web` : c\'est celui par lequel Filament authentifie (AC9). '
                . 'Un rôle sur un autre guard serait invisible pour hasRole() dans le panel.',
        );
});

it('stays at exactly one super-admin role when db:seed runs twice', function (): void {
    // La formulation littérale de l'AC4 : deux passages consécutifs de la
    // chaîne COMPLÈTE, pas du seul RoleSeeder.
    Artisan::call('db:seed', [
        '--class' => DatabaseSeeder::class,
    ]);
    Artisan::call('db:seed', [
        '--class' => DatabaseSeeder::class,
    ]);

    expect(Role::query()->where('name', 'super-admin')->count())->toBe(
        1,
        'Un second `db:seed` a produit un rôle super-admin en double.',
    );
});

it('is reached by the default db:seed chain', function (): void {
    // Sans ce test, RoleSeeder pourrait être parfaitement idempotent et n'être
    // JAMAIS appelé : `db:seed` exécute DatabaseSeeder, et lui seul. Un rôle
    // qu'aucune commande ne crée est un garde-fou sans référent — un opérateur
    // qui suit la documentation obtiendrait un panel qu'il ne peut pas ouvrir.
    Artisan::call('db:seed', [
        '--class' => DatabaseSeeder::class,
    ]);

    expect(Role::query()->where('name', 'super-admin')->exists())->toBeTrue(
        '`db:seed` ne crée pas le rôle super-admin : DatabaseSeeder n\'appelle pas RoleSeeder.',
    );
});

it('seeds no user carrying super-admin, and no admin account at all', function (): void {
    Artisan::call('db:seed', [
        '--class' => DatabaseSeeder::class,
    ]);

    $superAdmins = User::query()->get()->filter(
        static fn (User $user): bool => $user->hasRole('super-admin'),
    );

    expect($superAdmins)
        ->toHaveCount(
            0,
            'DatabaseSeeder a semé un administrateur : son mot de passe serait connu du dépôt, '
                . 'et il existerait sur tout déploiement ayant lancé `db:seed`. '
                . 'L\'opérateur crée son compte par `php artisan make:filament-user`.',
        );
});

it('leaves the seeded test user unable to open the panel', function (): void {
    // Le pendant du test précédent, côté conséquence observable : le seul
    // utilisateur que le dépôt crée n'ouvre pas la porte.
    Artisan::call('db:seed', [
        '--class' => DatabaseSeeder::class,
    ]);

    $seeded = User::query()->where('email', 'test@example.com')->firstOrFail();

    expect(HttpProbe::get('/admin', $seeded)->getStatusCode())
        ->toBe(403, 'Le seul utilisateur que le dépôt crée ouvre le panel.');
});
