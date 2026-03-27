# Prompt: Implémenter 2FA avec Laravel Fortify

## Contexte
Le skeleton Laravel n'a actuellement pas de système d'authentification à deux facteurs (2FA). Pour une application moderne et sécurisée, le 2FA est essentiel.

## Objectif
Implémenter l'authentification à deux facteurs (2FA) en utilisant Laravel Fortify avec support TOTP (Time-based One-Time Password) compatible avec Google Authenticator, Authy, etc.

## Instructions pour Claude Code

### Étape 1: Installer Laravel Fortify

```bash
cd src
composer require laravel/fortify
```

### Étape 2: Publier la configuration et les migrations

```bash
php artisan vendor:publish --provider="Laravel\Fortify\FortifyServiceProvider"
php artisan migrate
```

### Étape 3: Enregistrer Fortify dans le Service Provider

**app/Providers/FortifyServiceProvider.php** est déjà créé. Le configurer:

```php
<?php

namespace App\Providers;

use App\Actions\Fortify\CreateNewUser;
use App\Actions\Fortify\ResetUserPassword;
use App\Actions\Fortify\UpdateUserPassword;
use App\Actions\Fortify\UpdateUserProfileInformation;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;
use Laravel\Fortify\Fortify;

class FortifyServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        //
    }

    public function boot(): void
    {
        Fortify::createUsersUsing(CreateNewUser::class);
        Fortify::updateUserProfileInformationUsing(UpdateUserProfileInformation::class);
        Fortify::updateUserPasswordsUsing(UpdateUserPassword::class);
        Fortify::resetUserPasswordsUsing(ResetUserPassword::class);

        RateLimiter::for('login', function (Request $request) {
            $email = (string) $request->email;

            return Limit::perMinute(5)->by($email.$request->ip());
        });

        RateLimiter::for('two-factor', function (Request $request) {
            return Limit::perMinute(5)->by($request->session()->get('login.id'));
        });
    }
}
```

### Étape 4: Activer Two Factor dans la configuration

**config/fortify.php**:

```php
'features' => [
    Features::registration(),
    Features::resetPasswords(),
    // Features::emailVerification(),
    Features::updateProfileInformation(),
    Features::updatePasswords(),
    Features::twoFactorAuthentication([
        'confirm' => true,
        'confirmPassword' => true,
        // 'window' => 0,
    ]),
],
```

### Étape 5: Ajouter les colonnes 2FA au modèle User

**app/Models/User.php** - Vérifier que le trait est présent:

```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Fortify\TwoFactorAuthenticatable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable
{
    use HasApiTokens, HasFactory, Notifiable, TwoFactorAuthenticatable;

    protected $fillable = [
        'name',
        'email',
        'password',
    ];

    protected $hidden = [
        'password',
        'remember_token',
        'two_factor_recovery_codes',
        'two_factor_secret',
    ];

    protected $casts = [
        'email_verified_at' => 'datetime',
        'password' => 'hashed',
    ];

    /**
     * Check if user has two factor enabled
     */
    public function hasTwoFactorEnabled(): bool
    {
        return !is_null($this->two_factor_secret);
    }
}
```

### Étape 6: Créer les Actions Fortify

**app/Actions/Fortify/CreateNewUser.php**:

```php
<?php

namespace App\Actions\Fortify;

use App\Models\User;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Validator;
use Laravel\Fortify\Contracts\CreatesNewUsers;

class CreateNewUser implements CreatesNewUsers
{
    use PasswordValidationRules;

    public function create(array $input): User
    {
        Validator::make($input, [
            'name' => ['required', 'string', 'max:255'],
            'email' => ['required', 'string', 'email', 'max:255', 'unique:users'],
            'password' => $this->passwordRules(),
        ])->validate();

        return User::create([
            'name' => $input['name'],
            'email' => $input['email'],
            'password' => Hash::make($input['password']),
        ]);
    }
}
```

**app/Actions/Fortify/PasswordValidationRules.php**:

```php
<?php

namespace App\Actions\Fortify;

use Laravel\Fortify\Rules\Password;

trait PasswordValidationRules
{
    protected function passwordRules(): array
    {
        return ['required', 'string', new Password, 'confirmed'];
    }
}
```

### Étape 7: Créer le Controller 2FA API

**app/Http/Controllers/Api/TwoFactorAuthenticationController.php**:

```php
<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Laravel\Fortify\Actions\EnableTwoFactorAuthentication;
use Laravel\Fortify\Actions\DisableTwoFactorAuthentication;

class TwoFactorAuthenticationController extends Controller
{
    public function __construct()
    {
        $this->middleware('auth:sanctum');
    }

    /**
     * Enable two factor authentication for the user.
     */
    public function store(Request $request, EnableTwoFactorAuthentication $enable): JsonResponse
    {
        $enable($request->user());

        return response()->json([
            'message' => 'Two factor authentication enabled.',
            'two_factor_qr_code_svg' => $request->user()->twoFactorQrCodeSvg(),
            'two_factor_recovery_codes' => json_decode(decrypt($request->user()->two_factor_recovery_codes)),
        ]);
    }

    /**
     * Disable two factor authentication for the user.
     */
    public function destroy(Request $request, DisableTwoFactorAuthentication $disable): JsonResponse
    {
        $disable($request->user());

        return response()->json([
            'message' => 'Two factor authentication disabled.',
        ]);
    }

    /**
     * Get the two factor authentication QR code.
     */
    public function show(Request $request): JsonResponse
    {
        if (!$request->user()->hasTwoFactorEnabled()) {
            return response()->json([
                'message' => 'Two factor authentication is not enabled.',
            ], 400);
        }

        return response()->json([
            'two_factor_qr_code_svg' => $request->user()->twoFactorQrCodeSvg(),
        ]);
    }

    /**
     * Get the two factor authentication recovery codes.
     */
    public function recoveryCodes(Request $request): JsonResponse
    {
        if (!$request->user()->hasTwoFactorEnabled()) {
            return response()->json([
                'message' => 'Two factor authentication is not enabled.',
            ], 400);
        }

        return response()->json([
            'two_factor_recovery_codes' => json_decode(decrypt($request->user()->two_factor_recovery_codes)),
        ]);
    }

    /**
     * Regenerate the two factor authentication recovery codes.
     */
    public function regenerateRecoveryCodes(Request $request): JsonResponse
    {
        $request->user()->generateRecoveryCodes();
        $request->user()->save();

        return response()->json([
            'message' => 'Recovery codes regenerated.',
            'two_factor_recovery_codes' => json_decode(decrypt($request->user()->two_factor_recovery_codes)),
        ]);
    }
}
```

### Étape 8: Ajouter les routes API pour 2FA

**routes/api.php**:

```php
use App\Http\Controllers\Api\TwoFactorAuthenticationController;

Route::middleware('auth:sanctum')->group(function () {
    // Two Factor Authentication
    Route::prefix('user/two-factor-authentication')->group(function () {
        Route::post('/', [TwoFactorAuthenticationController::class, 'store'])
            ->name('two-factor.enable');
        Route::delete('/', [TwoFactorAuthenticationController::class, 'destroy'])
            ->name('two-factor.disable');
        Route::get('/', [TwoFactorAuthenticationController::class, 'show'])
            ->name('two-factor.show');
        Route::get('/recovery-codes', [TwoFactorAuthenticationController::class, 'recoveryCodes'])
            ->name('two-factor.recovery-codes');
        Route::post('/recovery-codes', [TwoFactorAuthenticationController::class, 'regenerateRecoveryCodes'])
            ->name('two-factor.recovery-codes.regenerate');
    });
});
```

### Étape 9: Créer une migration pour ajouter un champ 2FA activé

**database/migrations/xxxx_add_two_factor_columns_to_users_table.php**:

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->text('two_factor_secret')->nullable()->after('password');
            $table->text('two_factor_recovery_codes')->nullable()->after('two_factor_secret');
            $table->timestamp('two_factor_confirmed_at')->nullable()->after('two_factor_recovery_codes');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn([
                'two_factor_secret',
                'two_factor_recovery_codes',
                'two_factor_confirmed_at',
            ]);
        });
    }
};
```

### Étape 10: Créer un Middleware pour forcer 2FA

**app/Http/Middleware/RequireTwoFactor.php**:

```php
<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class RequireTwoFactor
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        // Si l'utilisateur est admin et n'a pas 2FA activé
        if ($user && $user->is_admin && !$user->hasTwoFactorEnabled()) {
            return response()->json([
                'message' => 'Two factor authentication is required for administrators.',
                'redirect' => '/user/two-factor-authentication',
            ], 403);
        }

        return $next($request);
    }
}
```

**Enregistrer dans app/Http/Kernel.php** (bootstrap/app.php pour Laravel 12):

```php
protected $middlewareAliases = [
    // ...
    'require-2fa' => \App\Http\Middleware\RequireTwoFactor::class,
];
```

### Étape 11: Créer des tests

**tests/Feature/TwoFactorAuthenticationTest.php**:

```php
<?php

use App\Models\User;
use Laravel\Fortify\Features;

test('two factor authentication can be enabled', function () {
    if (!Features::enabled(Features::twoFactorAuthentication())) {
        $this->markTestSkipped('Two factor authentication is not enabled.');
    }

    $user = User::factory()->create();

    $response = $this->actingAs($user)
        ->postJson('/api/user/two-factor-authentication');

    $response->assertOk();
    $response->assertJsonStructure([
        'message',
        'two_factor_qr_code_svg',
        'two_factor_recovery_codes',
    ]);

    $user->refresh();
    expect($user->hasTwoFactorEnabled())->toBeTrue();
});

test('two factor authentication can be disabled', function () {
    if (!Features::enabled(Features::twoFactorAuthentication())) {
        $this->markTestSkipped('Two factor authentication is not enabled.');
    }

    $user = User::factory()->create();

    // Enable 2FA first
    $this->actingAs($user)->postJson('/api/user/two-factor-authentication');

    // Now disable it
    $response = $this->actingAs($user)
        ->deleteJson('/api/user/two-factor-authentication');

    $response->assertOk();

    $user->refresh();
    expect($user->hasTwoFactorEnabled())->toBeFalse();
});

test('recovery codes can be regenerated', function () {
    if (!Features::enabled(Features::twoFactorAuthentication())) {
        $this->markTestSkipped('Two factor authentication is not enabled.');
    }

    $user = User::factory()->create();

    // Enable 2FA
    $this->actingAs($user)->postJson('/api/user/two-factor-authentication');

    $user->refresh();
    $originalCodes = $user->two_factor_recovery_codes;

    // Regenerate codes
    $response = $this->actingAs($user)
        ->postJson('/api/user/two-factor-authentication/recovery-codes');

    $response->assertOk();

    $user->refresh();
    expect($user->two_factor_recovery_codes)->not->toBe($originalCodes);
});
```

### Étape 12: Documenter 2FA dans OpenAPI

**app/Http/Controllers/Api/TwoFactorAuthenticationController.php** - Ajouter annotations:

```php
/**
 * @OA\Post(
 *     path="/api/user/two-factor-authentication",
 *     tags={"Authentication"},
 *     summary="Enable two factor authentication",
 *     security={{"sanctum":{}}},
 *     @OA\Response(
 *         response=200,
 *         description="2FA enabled successfully",
 *         @OA\JsonContent(
 *             @OA\Property(property="message", type="string"),
 *             @OA\Property(property="two_factor_qr_code_svg", type="string"),
 *             @OA\Property(property="two_factor_recovery_codes", type="array", @OA\Items(type="string"))
 *         )
 *     )
 * )
 */
public function store(Request $request, EnableTwoFactorAuthentication $enable): JsonResponse
```

### Étape 13: Ajouter dans la documentation

**Créer docs/2FA-SETUP.md**:

```markdown
# Two Factor Authentication Setup

## Pour les utilisateurs

### Activer 2FA

1. Endpoint: `POST /api/user/two-factor-authentication`
2. Headers: `Authorization: Bearer {token}`
3. Response contient:
   - QR Code SVG à scanner avec Google Authenticator
   - Codes de récupération (à sauvegarder!)

### Scanner le QR Code

1. Ouvrir Google Authenticator, Authy, ou 1Password
2. Scanner le QR code fourni
3. Entrer le code à 6 chiffres pour confirmer

### Codes de récupération

**IMPORTANT**: Sauvegarder les codes de récupération dans un endroit sûr.
Ces codes permettent de récupérer l'accès si vous perdez votre téléphone.

### Désactiver 2FA

Endpoint: `DELETE /api/user/two-factor-authentication`

## Pour les développeurs

### Forcer 2FA pour les admins

Appliquer le middleware `require-2fa` aux routes sensibles:

\`\`\`php
Route::middleware(['auth:sanctum', 'require-2fa'])->group(function () {
    // Routes requiring 2FA
});
\`\`\`

### Personnaliser la configuration

**config/fortify.php**:

\`\`\`php
'features' => [
    Features::twoFactorAuthentication([
        'confirm' => true,           // Require password confirmation
        'confirmPassword' => true,   // Confirm when disabling
        'window' => 0,               // Time window for codes (default: 0)
    ]),
],
\`\`\`

### Tester en local

\`\`\`bash
# Activer 2FA pour un user
php artisan tinker
>>> $user = User::find(1);
>>> app(Laravel\Fortify\Actions\EnableTwoFactorAuthentication::class)($user);
>>> $user->twoFactorQrCodeUrl()
\`\`\`
```

### Étape 14: Ajouter des commandes Artisan utiles

**app/Console/Commands/DisableTwoFactorForUser.php**:

```php
<?php

namespace App\Console\Commands;

use App\Models\User;
use Illuminate\Console\Command;
use Laravel\Fortify\Actions\DisableTwoFactorAuthentication;

class DisableTwoFactorForUser extends Command
{
    protected $signature = 'user:disable-2fa {email}';
    protected $description = 'Disable two factor authentication for a user';

    public function handle(DisableTwoFactorAuthentication $disable): int
    {
        $user = User::where('email', $this->argument('email'))->first();

        if (!$user) {
            $this->error('User not found.');
            return self::FAILURE;
        }

        if (!$user->hasTwoFactorEnabled()) {
            $this->info('User does not have 2FA enabled.');
            return self::SUCCESS;
        }

        $disable($user);

        $this->info('Two factor authentication disabled for user: ' . $user->email);
        return self::SUCCESS;
    }
}
```

### Étape 15: Mettre à jour le README

**README.md** - Ajouter section:

```markdown
## 🔐 Two Factor Authentication (2FA)

Ce skeleton inclut l'authentification à deux facteurs via Laravel Fortify.

### Activer 2FA

\`\`\`bash
curl -X POST https://laravel.local/api/user/two-factor-authentication \
  -H "Authorization: Bearer {token}"
\`\`\`

### Commandes utiles

\`\`\`bash
# Désactiver 2FA pour un utilisateur (admin recovery)
php artisan user:disable-2fa user@example.com
\`\`\`

### Documentation complète

Voir [docs/2FA-SETUP.md](docs/2FA-SETUP.md)
```

## Checklist de vérification

- [ ] Laravel Fortify installé
- [ ] Configuration publiée
- [ ] Migrations exécutées
- [ ] FortifyServiceProvider configuré
- [ ] Trait TwoFactorAuthenticatable ajouté au modèle User
- [ ] Actions Fortify créées
- [ ] Controller 2FA API créé
- [ ] Routes API ajoutées
- [ ] Middleware RequireTwoFactor créé
- [ ] Tests créés et passent
- [ ] Documentation OpenAPI ajoutée
- [ ] Documentation utilisateur créée (2FA-SETUP.md)
- [ ] Commande Artisan de recovery créée
- [ ] README mis à jour
- [ ] Commit créé

## Sécurité supplémentaire recommandée

Après cette implémentation, considérer:

1. **Backup codes management**: Interface pour voir/régénérer
2. **Email notifications**: Alerter l'user quand 2FA activé/désactivé
3. **Trusted devices**: Remember device for X days
4. **Activity log**: Logger les tentatives 2FA avec Spatie Activity Log
5. **Rate limiting**: Limiter les tentatives de code 2FA

## Références

- Laravel Fortify: https://laravel.com/docs/fortify
- Google Authenticator Protocol: https://github.com/google/google-authenticator
- TOTP RFC 6238: https://tools.ietf.org/html/rfc6238
