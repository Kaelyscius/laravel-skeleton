<?php

declare(strict_types=1);

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;

uses(RefreshDatabase::class);

/*
|------------------------------------------------------------------------------
| Pourquoi ce fichier existe
|------------------------------------------------------------------------------
|
| `App\Models\User` était à 0 % de couverture. Le 2026-08-07, en suivant une
| suggestion de PHP Insights (« Property type hint »), `$fillable` et `$hidden`
| ont reçu un type natif `array`. PHP l'INTERDIT sur une propriété héritée non
| typée : c'est un « Fatal error: Type of User::$fillable must be omitted to
| match the parent definition ».
|
| Les 63 tests sont passés quand même. Aucun ne chargeait la classe.
|
| Un modèle qu'aucun test n'instancie peut donc porter une erreur fatale de
| production sans qu'une seule assertion ne bouge. Ces tests ne visent pas la
| couverture pour la couverture : ils garantissent que la classe se CHARGE et
| que son contrat d'exposition est celui qu'on croit.
*/

it('se charge sans erreur fatale et s\'instancie', function (): void {
    // L'assertion faible en apparence est la plus importante : si la déclaration
    // de la classe est invalide, PHP échoue AVANT toute assertion.
    expect(new User())
        ->toBeInstanceOf(User::class);
});

it('n\'expose ni le mot de passe ni le remember_token en sérialisation', function (): void {
    $user = User::factory()->create([
        'name' => 'Alex',
        'email' => 'alex@example.test',
    ]);

    $serialized = $user->toArray();

    expect($serialized)
        ->toHaveKey('name');
    expect($serialized)
        ->toHaveKey('email');
    // Le vrai enjeu de $hidden : une fuite ici passerait dans toute réponse API
    // sérialisant un utilisateur.
    expect(array_key_exists('password', $serialized))
        ->toBeFalse('Le hash du mot de passe est exposé par toArray().');
    expect(array_key_exists('remember_token', $serialized))
        ->toBeFalse('Le remember_token est exposé par toArray().');
});

it('n\'accepte en assignation de masse que les 3 champs déclarés', function (): void {
    $user = new User();
    $user->fill([
        'name' => 'Alex',
        'email' => 'alex@example.test',
        'password' => 'secret',
        // Champ non déclaré dans $fillable : doit être ignoré silencieusement
        // par Eloquent, et surtout ne jamais atterrir sur le modèle.
        'is_admin' => true,
    ]);

    expect($user->getAttribute('name'))
        ->toBe('Alex');
    expect($user->getAttribute('is_admin'))
        ->toBeNull('Un champ hors $fillable a franchi l\'assignation de masse.');
});

it('hache le mot de passe et le cache-t comme datetime les champs attendus', function (): void {
    $casts = (new User())->getCasts();

    expect($casts)
        ->toHaveKey('email_verified_at');
    expect($casts['email_verified_at'])->toBe('datetime');
    expect($casts)
        ->toHaveKey('password');
    expect($casts['password'])->toBe('hashed');
});
