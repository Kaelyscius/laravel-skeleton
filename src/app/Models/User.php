<?php

declare(strict_types=1);

namespace App\Models;

// use Illuminate\Contracts\Auth\MustVerifyEmail;
use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;

final class User extends Authenticatable
{
    /** @use HasFactory<UserFactory> */
    use HasFactory;
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
