<?php

declare(strict_types=1);

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Spatie\Permission\Models\Role;

/**
 * Seeds the roles the application recognises. Today: `super-admin` only.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * POURQUOI CE FICHIER EST ICI ET NON DANS `app/Modules/Admin/Database/seeders/`
 *
 * La Story 1.10a devait trancher entre les deux, et écrire le motif. Le voici.
 *
 * Trois raisons, dans cet ordre de poids :
 *
 *   1. **La table qu'il remplit est une table racine.** `roles` est créée par
 *      `database/migrations/2026_05_24_142957_create_permission_tables.php`,
 *      qui n'appartient à aucun module. Poser la graine ailleurs que le schéma
 *      qu'elle remplit sépare deux choses qui se relisent ensemble.
 *
 *   2. **L'AC4 exige que `php artisan db:seed` produise le rôle.** `db:seed`
 *      exécute `DatabaseSeeder`, et lui seul. Un seeder rangé sous
 *      `app/Modules/Admin/` devrait donc être appelé depuis la racine de toute
 *      façon — c'est-à-dire inconditionnellement, quel que soit
 *      `MODULE_ADMIN_ENABLED`. Un « seeder de module » qui s'exécute même
 *      module éteint n'est pas un seeder de module : c'est un seeder racine mal
 *      rangé, avec en prime une promesse d'isolation qu'il ne tient pas.
 *
 *   3. **ADR-0009 range dans les modules ce qu'un module POSSÈDE** : ses
 *      routes, ses migrations, ses Filament resources. Le rôle `super-admin`
 *      n'est pas possédé par le module `Admin` — la Story 3.2 s'en servira pour
 *      protéger `/pulse`, `/horizon` et `/telescope`, qui n'en font pas partie.
 *
 * Le chemin `app/Modules/<Module>/Database/seeders/` reste donc NON figé, et
 * c'est délibéré : `AdminServiceProvider` l'annonce en commentaire sans le
 * câbler, et il sera figé par la première story qui possède vraiment une graine
 * de module. Un chemin arrêté avant son premier usage est une affirmation sans
 * référent — le motif dominant de ce projet.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * ⛔ CE SEEDER NE CRÉE AUCUN UTILISATEUR
 *
 * Semer un `super-admin` reviendrait à publier un mot de passe dans le dépôt :
 * `DatabaseSeeder` tourne dans `make fresh`, en CI, et sur tout déploiement mal
 * découpé. Le seeder pose le RÔLE ; l'opérateur pose l'UTILISATEUR, avec
 * `php artisan make:filament-user` puis en lui assignant le rôle. Gardé par
 * `tests/Feature/SuperAdminRoleSeederTest.php`.
 */
final class RoleSeeder extends Seeder
{
    /**
     * Nom du rôle qui ouvre le panel `/admin` (App\Models\User::canAccessPanel).
     */
    public const string SUPER_ADMIN = 'super-admin';

    public function run(): void
    {
        // `findOrCreate` cherche sur le couple (name, guard). Le guard est
        // nommé explicitement plutôt que laissé au défaut : `auth.defaults.guard`
        // est modifiable, et un rôle créé sur un autre guard serait invisible
        // pour le `hasRole()` du panel — présent en base, sans effet.
        Role::findOrCreate(self::SUPER_ADMIN, 'web');
    }
}
