<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Models\User;
use Illuminate\Database\Console\Seeds\WithoutModelEvents;
use Illuminate\Database\Seeder;

final class DatabaseSeeder extends Seeder
{
    use WithoutModelEvents;

    /**
     * Seed the application's database.
     */
    public function run(): void
    {
        // Tenant-root Streamer (Story 1.3) — idempotent, exactly one row (tenancy v1).
        $this->call(StreamerSeeder::class);

        // Rôles reconnus par l'application (Story 1.10a) — idempotent.
        // ⚠️ Pose le RÔLE `super-admin`, jamais un utilisateur qui le porte :
        // un administrateur semé aurait un mot de passe connu du dépôt, et
        // cette commande tourne dans `make fresh`, en CI et au déploiement.
        // L'opérateur crée son compte avec `php artisan make:filament-user`.
        $this->call(RoleSeeder::class);

        // User::factory(10)->create();

        // Idempotent guard keeps `db:seed` re-runnable: the fixed email would
        // otherwise hit the unique constraint on a second run.
        if (! User::query()->where('email', 'test@example.com')->exists()) {
            User::factory()->create([
                'name' => 'Test User',
                'email' => 'test@example.com',
            ]);
        }
    }
}
