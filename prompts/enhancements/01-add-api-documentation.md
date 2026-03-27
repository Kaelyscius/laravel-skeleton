# Prompt: Ajouter la documentation API avec Swagger/OpenAPI

## Contexte
Le projet Laravel skeleton n'a actuellement pas de documentation API automatique. Pour un skeleton destiné à être forké pour créer des applications, avoir une documentation API interactive est essentiel.

## Objectif
Implémenter L5-Swagger pour générer automatiquement une documentation OpenAPI/Swagger interactive pour l'API Laravel.

## Instructions pour Claude Code

### Étape 1: Installer L5-Swagger

```bash
cd src
composer require darkaonline/l5-swagger
```

### Étape 2: Publier la configuration

```bash
php artisan vendor:publish --provider="L5Swagger\L5SwaggerServiceProvider"
```

### Étape 3: Configurer L5-Swagger

**Éditer config/l5-swagger.php**:

```php
'default' => 'default',
'documentations' => [
    'default' => [
        'api' => [
            'title' => env('APP_NAME', 'Laravel') . ' API Documentation',
        ],
        'routes' => [
            'api' => 'api/documentation',
        ],
        'paths' => [
            'docs' => storage_path('api-docs'),
            'docs_json' => 'api-docs.json',
            'docs_yaml' => 'api-docs.yaml',
            'annotations' => [
                base_path('app/Http/Controllers'),
                base_path('app/Models'),
            ],
        ],
    ],
],
```

### Étape 4: Créer le contrôleur OpenAPI principal

**app/Http/Controllers/Controller.php**:

```php
<?php

namespace App\Http\Controllers;

use OpenApi\Annotations as OA;

/**
 * @OA\Info(
 *     version="1.0.0",
 *     title="Laravel Skeleton API",
 *     description="API Documentation for Laravel Skeleton Project",
 *     @OA\Contact(
 *         email="admin@example.com"
 *     ),
 *     @OA\License(
 *         name="MIT",
 *         url="https://opensource.org/licenses/MIT"
 *     )
 * )
 * @OA\Server(
 *     url=L5_SWAGGER_CONST_HOST,
 *     description="API Server"
 * )
 * @OA\SecurityScheme(
 *     securityScheme="sanctum",
 *     type="http",
 *     scheme="bearer",
 *     bearerFormat="JWT"
 * )
 */
abstract class Controller
{
}
```

### Étape 5: Créer un contrôleur API exemple documenté

**app/Http/Controllers/Api/UserController.php**:

```php
<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use OpenApi\Annotations as OA;

class UserController extends Controller
{
    /**
     * @OA\Get(
     *     path="/api/users",
     *     operationId="getUsersList",
     *     tags={"Users"},
     *     summary="Get list of users",
     *     description="Returns list of users",
     *     security={{"sanctum":{}}},
     *     @OA\Parameter(
     *         name="page",
     *         in="query",
     *         description="Page number",
     *         required=false,
     *         @OA\Schema(type="integer")
     *     ),
     *     @OA\Parameter(
     *         name="per_page",
     *         in="query",
     *         description="Items per page",
     *         required=false,
     *         @OA\Schema(type="integer", default=15)
     *     ),
     *     @OA\Response(
     *         response=200,
     *         description="Successful operation",
     *         @OA\JsonContent(
     *             type="object",
     *             @OA\Property(property="data", type="array", @OA\Items(ref="#/components/schemas/User")),
     *             @OA\Property(property="links", type="object"),
     *             @OA\Property(property="meta", type="object")
     *         )
     *     ),
     *     @OA\Response(
     *         response=401,
     *         description="Unauthenticated"
     *     )
     * )
     */
    public function index(Request $request): JsonResponse
    {
        $perPage = $request->input('per_page', 15);
        $users = User::paginate($perPage);

        return response()->json($users);
    }

    /**
     * @OA\Get(
     *     path="/api/users/{id}",
     *     operationId="getUserById",
     *     tags={"Users"},
     *     summary="Get user information",
     *     description="Returns user data",
     *     security={{"sanctum":{}}},
     *     @OA\Parameter(
     *         name="id",
     *         description="User ID",
     *         required=true,
     *         in="path",
     *         @OA\Schema(type="integer")
     *     ),
     *     @OA\Response(
     *         response=200,
     *         description="Successful operation",
     *         @OA\JsonContent(ref="#/components/schemas/User")
     *     ),
     *     @OA\Response(
     *         response=404,
     *         description="User not found"
     *     )
     * )
     */
    public function show(User $user): JsonResponse
    {
        return response()->json(['data' => $user]);
    }

    /**
     * @OA\Post(
     *     path="/api/users",
     *     operationId="createUser",
     *     tags={"Users"},
     *     summary="Create new user",
     *     description="Creates a new user and returns user data",
     *     security={{"sanctum":{}}},
     *     @OA\RequestBody(
     *         required=true,
     *         @OA\JsonContent(
     *             required={"name","email","password"},
     *             @OA\Property(property="name", type="string", example="John Doe"),
     *             @OA\Property(property="email", type="string", format="email", example="john@example.com"),
     *             @OA\Property(property="password", type="string", format="password", example="password123")
     *         )
     *     ),
     *     @OA\Response(
     *         response=201,
     *         description="User created successfully",
     *         @OA\JsonContent(ref="#/components/schemas/User")
     *     ),
     *     @OA\Response(
     *         response=422,
     *         description="Validation error"
     *     )
     * )
     */
    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'name' => 'required|string|max:255',
            'email' => 'required|string|email|unique:users',
            'password' => 'required|string|min:8',
        ]);

        $validated['password'] = bcrypt($validated['password']);
        $user = User::create($validated);

        return response()->json(['data' => $user], 201);
    }
}
```

### Étape 6: Documenter le modèle User

**app/Models/User.php** - Ajouter les annotations:

```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;
use OpenApi\Annotations as OA;

/**
 * @OA\Schema(
 *     schema="User",
 *     title="User",
 *     description="User model",
 *     @OA\Property(property="id", type="integer", readOnly=true, example=1),
 *     @OA\Property(property="name", type="string", maxLength=255, example="John Doe"),
 *     @OA\Property(property="email", type="string", format="email", maxLength=255, example="john@example.com"),
 *     @OA\Property(property="email_verified_at", type="string", format="date-time", nullable=true),
 *     @OA\Property(property="created_at", type="string", format="date-time", readOnly=true),
 *     @OA\Property(property="updated_at", type="string", format="date-time", readOnly=true)
 * )
 */
class User extends Authenticatable
{
    use HasApiTokens, HasFactory, Notifiable;

    // ... reste du modèle
}
```

### Étape 7: Ajouter les routes API

**routes/api.php**:

```php
<?php

use App\Http\Controllers\Api\UserController;
use Illuminate\Support\Facades\Route;

Route::middleware('auth:sanctum')->group(function () {
    Route::apiResource('users', UserController::class);
});
```

### Étape 8: Générer la documentation

```bash
php artisan l5-swagger:generate
```

### Étape 9: Configurer l'accès à la documentation

**Mise à jour .env**:

```env
L5_SWAGGER_GENERATE_ALWAYS=true
L5_SWAGGER_CONST_HOST=https://laravel.local/api
```

**Pour production (.env.production)**:
```env
L5_SWAGGER_GENERATE_ALWAYS=false
```

### Étape 10: Protéger l'accès en production (optionnel)

**app/Providers/AppServiceProvider.php**:

```php
use Illuminate\Support\Facades\Gate;

public function boot(): void
{
    // Protéger Swagger en production
    Gate::define('viewApiDocs', function ($user = null) {
        return app()->environment('local') || $user?->is_admin;
    });
}
```

**routes/api.php** - Ajouter protection:

```php
Route::get('/documentation', function () {
    abort_unless(Gate::allows('viewApiDocs'), 403);
    return redirect('/api/documentation');
});
```

### Étape 11: Ajouter au Makefile

**Ajout dans le Makefile**:

```makefile
# API Documentation
.PHONY: api-docs
api-docs: ## Générer la documentation API
	@echo "$(YELLOW)→ Generating API documentation...$(NC)"
	@docker exec $(PHP_CONTAINER_NAME) php artisan l5-swagger:generate
	@echo "$(GREEN)✓ API documentation generated$(NC)"
	@echo "$(BLUE)→ Access at: https://laravel.local/api/documentation$(NC)"

.PHONY: api-docs-watch
api-docs-watch: ## Regénérer la doc API à chaque changement
	@echo "$(YELLOW)→ Watching for API changes...$(NC)"
	@while true; do \
		inotifywait -r -e modify app/Http/Controllers/Api app/Models; \
		$(MAKE) api-docs; \
	done
```

### Étape 12: Documenter dans le README

**Ajouter dans README.md**:

```markdown
### API Documentation

La documentation API interactive est disponible via Swagger/OpenAPI:

- **Local**: https://laravel.local/api/documentation
- **Génération**: `make api-docs`
- **Watch mode**: `make api-docs-watch`

#### Annoter vos controllers

Utilisez les annotations OpenAPI dans vos controllers:

\`\`\`php
/**
 * @OA\Get(
 *     path="/api/resource",
 *     tags={"Resource"},
 *     summary="Get resources",
 *     @OA\Response(response=200, description="Success")
 * )
 */
public function index() { }
\`\`\`

#### Authentification API

La documentation supporte l'authentification Sanctum. Cliquez sur "Authorize" et entrez votre Bearer token.
```

### Étape 13: Créer des tests pour l'API

**tests/Feature/Api/UserControllerTest.php**:

```php
<?php

use App\Models\User;

test('can list users', function () {
    User::factory()->count(3)->create();

    $response = $this->actingAs(User::factory()->create())
        ->getJson('/api/users');

    $response->assertOk()
        ->assertJsonStructure([
            'data' => [
                '*' => ['id', 'name', 'email', 'created_at', 'updated_at']
            ],
            'links',
            'meta'
        ]);
});

test('can show single user', function () {
    $user = User::factory()->create();

    $response = $this->actingAs(User::factory()->create())
        ->getJson("/api/users/{$user->id}");

    $response->assertOk()
        ->assertJson([
            'data' => [
                'id' => $user->id,
                'name' => $user->name,
                'email' => $user->email,
            ]
        ]);
});

test('can create user', function () {
    $userData = [
        'name' => 'Test User',
        'email' => 'test@example.com',
        'password' => 'password123',
    ];

    $response = $this->actingAs(User::factory()->create())
        ->postJson('/api/users', $userData);

    $response->assertCreated()
        ->assertJsonStructure([
            'data' => ['id', 'name', 'email']
        ]);

    $this->assertDatabaseHas('users', [
        'email' => 'test@example.com'
    ]);
});
```

### Étape 14: Créer un schéma de réponse d'erreur standardisé

**app/Http/Controllers/Controller.php** - Ajouter:

```php
/**
 * @OA\Schema(
 *     schema="Error",
 *     title="Error",
 *     description="Error response",
 *     @OA\Property(property="message", type="string", example="Error message"),
 *     @OA\Property(property="errors", type="object", nullable=true)
 * )
 */
```

## Checklist de vérification

- [ ] L5-Swagger installé
- [ ] Configuration publiée et configurée
- [ ] Controller principal avec annotations OA\Info
- [ ] Exemple de controller API documenté
- [ ] Modèle User avec schema OA
- [ ] Routes API configurées
- [ ] Documentation générée (api-docs.json créé)
- [ ] Accessible via browser à /api/documentation
- [ ] Commandes Makefile ajoutées
- [ ] README mis à jour
- [ ] Tests API créés et passent
- [ ] Protection production configurée
- [ ] Commit créé

## Avantages de cette implémentation

1. ✅ **Documentation automatique** à partir du code
2. ✅ **Interface interactive** pour tester l'API
3. ✅ **Synchronisation code/docs** garantie
4. ✅ **Standard OpenAPI** (interopérabilité)
5. ✅ **Support Sanctum** pour authentification
6. ✅ **Exemples prêts** à copier pour nouveaux endpoints

## Prochaines étapes possibles

Après cette implémentation, vous pourriez ajouter:
1. **Scribe** comme alternative plus élégante à Swagger
2. **Postman Collection** générée automatiquement
3. **API Versioning** (v1, v2)
4. **Rate limiting** sur les endpoints
5. **Response caching** pour optimisation

## Références

- L5-Swagger: https://github.com/DarkaOnLine/L5-Swagger
- OpenAPI Spec: https://swagger.io/specification/
- Swagger UI: https://swagger.io/tools/swagger-ui/
