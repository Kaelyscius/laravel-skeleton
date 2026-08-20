<?php

declare(strict_types=1);

namespace App\Models;

// use Illuminate\Contracts\Auth\MustVerifyEmail;
use Database\Factories\UserFactory;
use Database\Seeders\RoleSeeder;
use Filament\Models\Contracts\FilamentUser;
use Filament\Panel;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Spatie\Permission\Traits\HasRoles;

final class User extends Authenticatable implements FilamentUser
{
    /** @use HasFactory<UserFactory> */
    use HasFactory;
    use HasRoles;
    use Notifiable;

    /**
     * The attributes that are mass assignable.
     *
     * @var list<string>
     *
     * ⚠️ PAS de type natif ici, malgré ce que suggère PHP Insights
     * (« Property type hint »). PHP interdit d'ajouter un type à une propriété
     * héritée non typée : `protected array $fillable` produit un
     * « Fatal error: Type of User::$fillable must be omitted to match the
     * parent definition in class Model ». PHPStan le signale en non-ignorable.
     * Vérifié le 2026-08-07 — et la suite passait malgré le fatal, parce que
     * ce modèle est à 0 % de couverture.
     */
    protected $fillable = [
        'name',
        'email',
        'password',
    ];

    /**
     * The attributes that should be hidden for serialization.
     *
     * @var list<string>
     *
     * ⚠️ Idem : pas de type natif, voir $fillable ci-dessus.
     */
    protected $hidden = [
        'password',
        'remember_token',
    ];

    /**
     * Décide si cet utilisateur peut entrer dans un panel Filament.
     *
     * ─────────────────────────────────────────────────────────────────────────
     * DEUX CONDITIONS, ET LES DEUX SONT NÉCESSAIRES
     *
     * Le panel demandé doit être `admin`, ET l'utilisateur doit porter le rôle
     * `super-admin`. Chacune seule laisserait passer un défaut :
     *
     *   • sans la vérification du RÔLE, `return $panel->getId() === 'admin'`
     *     signifie « tout utilisateur authentifié entre » — exactement ce que
     *     le contrat FilamentUser existe pour empêcher. C'est aussi ce que fait
     *     Filament en environnement `local`, et c'est pourquoi les tests
     *     tournent en `testing` (phpunit.xml), donc sur le chemin strict.
     *
     *   • sans la vérification du PANEL, un second panel ajouté plus tard
     *     (Epic 5+ : panel « streamer », panel « support »…) hériterait
     *     silencieusement de l'autorisation du panel d'administration. La
     *     décision d'ouvrir un panel doit être écrite panel par panel.
     *
     * ⛔ Pas de `Gate::before` accordant tout à `super-admin` : ce rôle
     * contrôle L'ENTRÉE DU PANEL, pas l'ensemble des autorisations. Un
     * interrupteur global rendrait les policies de l'Epic 5 indistinguables de
     * leur absence.
     *
     * ⚠️ L'appartenance à la table `users` n'accorde RIEN. `test@example.com`,
     * semé par DatabaseSeeder sur toute base fraîche, est refusé — un test le
     * nomme par son adresse.
     */
    public function canAccessPanel(Panel $panel): bool
    {
        // ⚠️ LE GUARD EST EXPLICITE, ET CE N'EST PAS DÉCORATIF (finding Q13).
        //
        // `RoleSeeder` épingle `Role::findOrCreate(self::SUPER_ADMIN, 'web')` en
        // argumentant que `auth.defaults.guard` est modifiable. Sans le second
        // argument ici, Spatie résout le guard DEPUIS LE MODÈLE : le jour où le
        // guard par défaut change, le rôle semé devient « présent en base, sans
        // effet » — la formulation exacte du commentaire du seeder, appliquée à
        // la porte que ce rôle est censé ouvrir. Le producteur se défendait, le
        // consommateur pas.
        //
        // La constante vient de `RoleSeeder` plutôt que d'un littéral : c'est le
        // seeder qui décide du nom, et il n'y a qu'une source de vérité pour le
        // lien seeder ↔ porte.
        return $panel->getId() === 'admin'
            && $this->hasRole(RoleSeeder::SUPER_ADMIN, 'web');
    }

    /**
     * Get the attributes that should be cast.
     *
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
        ];
    }
}
