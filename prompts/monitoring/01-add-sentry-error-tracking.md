# Prompt: Ajouter Sentry pour le suivi des erreurs en production

## Contexte
Le skeleton Laravel utilise Laravel Nightwatch pour le monitoring, mais Sentry est l'outil industry-standard pour le suivi d'erreurs en production avec des fonctionnalités avancées de debugging.

## Objectif
Implémenter Sentry pour capturer et tracker automatiquement toutes les exceptions, erreurs, et problèmes de performance en production.

## Instructions pour Claude Code

### Étape 1: Installer Sentry SDK

```bash
cd src
composer require sentry/sentry-laravel
```

### Étape 2: Publier la configuration

```bash
php artisan sentry:publish --dsn
```

Cela va créer `config/sentry.php` et ajouter SENTRY_LARAVEL_DSN dans .env

### Étape 3: Configurer les variables d'environnement

**. env.example** - Ajouter:

```env
# Sentry Error Tracking
SENTRY_LARAVEL_DSN=
SENTRY_TRACES_SAMPLE_RATE=0.2
SENTRY_PROFILES_SAMPLE_RATE=0.2
SENTRY_ENVIRONMENT="${APP_ENV}"
SENTRY_RELEASE=
```

**.env.local**:
```env
SENTRY_LARAVEL_DSN=  # Laisser vide pour dev local
```

**.env.production**:
```env
SENTRY_LARAVEL_DSN=https://xxx@xxx.ingest.sentry.io/xxx
SENTRY_TRACES_SAMPLE_RATE=0.2  # 20% des transactions
SENTRY_PROFILES_SAMPLE_RATE=0.2
SENTRY_ENVIRONMENT=production
SENTRY_RELEASE="${APP_VERSION}"
```

### Étape 4: Configurer Sentry

**config/sentry.php** - Personnaliser:

```php
<?php

return [
    'dsn' => env('SENTRY_LARAVEL_DSN'),

    // Capture rate for errors (1.0 = 100%)
    'sample_rate' => 1.0,

    // Trace sampling rate for performance monitoring
    'traces_sample_rate' => (float) env('SENTRY_TRACES_SAMPLE_RATE', 0.0),

    // Profiling sample rate
    'profiles_sample_rate' => (float) env('SENTRY_PROFILES_SAMPLE_RATE', 0.0),

    // Breadcrumbs
    'breadcrumbs' => [
        // Capture Laravel logs as breadcrumbs
        'logs' => true,

        // Capture SQL queries as breadcrumbs
        'sql_queries' => env('SENTRY_BREADCRUMBS_SQL', true),

        // Capture SQL bindings
        'sql_bindings' => env('SENTRY_BREADCRUMBS_SQL_BINDINGS', false),

        // Capture queue info
        'queue_info' => true,

        // Capture command info
        'command_info' => true,
    ],

    // Send default PII (Personally Identifiable Information)
    'send_default_pii' => false,

    // Environment
    'environment' => env('SENTRY_ENVIRONMENT', env('APP_ENV')),

    // Release version
    'release' => env('SENTRY_RELEASE'),

    // Server name
    'server_name' => gethostname(),

    // Before send callback
    'before_send' => function (\Sentry\Event $event, ?\Sentry\EventHint $hint): ?\Sentry\Event {
        // Ne pas envoyer certaines exceptions
        if ($hint && $hint->exception) {
            $exception = $hint->exception;

            // Ignorer les 404
            if ($exception instanceof \Symfony\Component\HttpKernel\Exception\NotFoundHttpException) {
                return null;
            }

            // Ignorer les authentification failures
            if ($exception instanceof \Illuminate\Auth\AuthenticationException) {
                return null;
            }
        }

        return $event;
    },

    // Performance monitoring
    'traces_sampler' => function (\Sentry\Tracing\SamplingContext $context): float {
        // Sample all transaction
        return (float) env('SENTRY_TRACES_SAMPLE_RATE', 0.2);
    },
];
```

### Étape 5: Intégration avec le Handler d'exceptions

**app/Exceptions/Handler.php**:

```php
<?php

namespace App\Exceptions;

use Illuminate\Foundation\Exceptions\Handler as ExceptionHandler;
use Sentry\Laravel\Integration;
use Throwable;

class Handler extends ExceptionHandler
{
    /**
     * A list of exception types with their corresponding custom log levels.
     *
     * @var array<class-string<\Throwable>, \Psr\Log\LogLevel::*>
     */
    protected $levels = [
        //
    ];

    /**
     * A list of the exception types that are not reported.
     *
     * @var array<int, class-string<\Throwable>>
     */
    protected $dontReport = [
        //
    ];

    /**
     * A list of the inputs that are never flashed to the session on validation exceptions.
     *
     * @var array<int, string>
     */
    protected $dontFlash = [
        'current_password',
        'password',
        'password_confirmation',
    ];

    /**
     * Register the exception handling callbacks for the application.
     */
    public function register(): void
    {
        $this->reportable(function (Throwable $e) {
            Integration::captureUnhandledException($e);
        });
    }

    /**
     * Report or log an exception.
     */
    public function report(Throwable $exception): void
    {
        if ($this->shouldReport($exception)) {
            // Add user context if authenticated
            if (auth()->check()) {
                \Sentry\configureScope(function (\Sentry\State\Scope $scope): void {
                    $scope->setUser([
                        'id' => auth()->id(),
                        'email' => auth()->user()->email,
                        'username' => auth()->user()->name,
                    ]);
                });
            }

            // Add tags
            \Sentry\configureScope(function (\Sentry\State\Scope $scope): void {
                $scope->setTag('environment', app()->environment());
                $scope->setTag('laravel_version', app()->version());
            });
        }

        parent::report($exception);
    }
}
```

### Étape 6: Ajouter un Middleware Sentry

**app/Http/Middleware/SentryContext.php**:

```php
<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class SentryContext
{
    public function handle(Request $request, Closure $next): Response
    {
        if (app()->bound('sentry')) {
            \Sentry\configureScope(function (\Sentry\State\Scope $scope) use ($request): void {
                // Add request data
                $scope->setContext('request', [
                    'url' => $request->fullUrl(),
                    'method' => $request->method(),
                    'ip' => $request->ip(),
                    'user_agent' => $request->userAgent(),
                ]);

                // Add route info
                if ($route = $request->route()) {
                    $scope->setTag('route', $route->getName() ?? $route->uri());
                }

                // Add authenticated user
                if ($request->user()) {
                    $scope->setUser([
                        'id' => $request->user()->id,
                        'email' => $request->user()->email,
                        'username' => $request->user()->name,
                    ]);
                }
            });
        }

        return $next($request);
    }
}
```

**Enregistrer dans bootstrap/app.php** (Laravel 11+):

```php
->withMiddleware(function (Middleware $middleware) {
    $middleware->append(\App\Http\Middleware\SentryContext::class);
})
```

### Étape 7: Créer un helper pour les rapports manuels

**app/Helpers/SentryHelper.php**:

```php
<?php

namespace App\Helpers;

use Sentry\Severity;
use Sentry\State\Scope;

class SentryHelper
{
    /**
     * Capture a message with context
     */
    public static function captureMessage(string $message, array $context = [], string $level = Severity::INFO): void
    {
        if (!app()->bound('sentry')) {
            return;
        }

        \Sentry\withScope(function (Scope $scope) use ($message, $context, $level): void {
            foreach ($context as $key => $value) {
                $scope->setExtra($key, $value);
            }

            \Sentry\captureMessage($message, $level);
        });
    }

    /**
     * Add breadcrumb
     */
    public static function addBreadcrumb(string $message, array $data = [], string $category = 'default', string $level = 'info'): void
    {
        if (!app()->bound('sentry')) {
            return;
        }

        \Sentry\addBreadcrumb([
            'message' => $message,
            'category' => $category,
            'level' => $level,
            'data' => $data,
        ]);
    }

    /**
     * Capture exception with extra context
     */
    public static function captureException(\Throwable $exception, array $context = []): void
    {
        if (!app()->bound('sentry')) {
            return;
        }

        \Sentry\withScope(function (Scope $scope) use ($exception, $context): void {
            foreach ($context as $key => $value) {
                $scope->setExtra($key, $value);
            }

            \Sentry\captureException($exception);
        });
    }

    /**
     * Start a performance transaction
     */
    public static function startTransaction(string $name, string $op = 'http.request'): ?\Sentry\Tracing\Transaction
    {
        if (!app()->bound('sentry')) {
            return null;
        }

        return \Sentry\startTransaction(
            \Sentry\Tracing\TransactionContext::make()
                ->setName($name)
                ->setOp($op)
        );
    }
}
```

### Étape 8: Intégrer avec les Jobs

**app/Jobs/ExampleJob.php** - Exemple:

```php
<?php

namespace App\Jobs;

use App\Helpers\SentryHelper;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;

class ExampleJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public function __construct(
        public readonly int $userId,
    ) {}

    public function handle(): void
    {
        try {
            SentryHelper::addBreadcrumb('Job started', [
                'user_id' => $this->userId,
                'queue' => $this->queue,
            ], 'job');

            // Job logic here

            SentryHelper::addBreadcrumb('Job completed successfully', [], 'job');
        } catch (\Throwable $e) {
            SentryHelper::captureException($e, [
                'user_id' => $this->userId,
                'queue' => $this->queue,
                'attempts' => $this->attempts(),
            ]);

            throw $e;
        }
    }
}
```

### Étape 9: Monitoring des performances

**app/Http/Middleware/SentryPerformanceMiddleware.php**:

```php
<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class SentryPerformanceMiddleware
{
    public function handle(Request $request, Closure $next): Response
    {
        if (!app()->bound('sentry')) {
            return $next($request);
        }

        $transaction = \Sentry\startTransaction(
            \Sentry\Tracing\TransactionContext::make()
                ->setName($request->route()?->getName() ?? $request->path())
                ->setOp('http.request')
        );

        \Sentry\SentrySdk::getCurrentHub()->setSpan($transaction);

        $response = $next($request);

        $transaction->finish();

        return $response;
    }
}
```

### Étape 10: Créer une commande de test

**app/Console/Commands/TestSentry.php**:

```php
<?php

namespace App\Console\Commands;

use App\Helpers\SentryHelper;
use Illuminate\Console\Command;

class TestSentry extends Command
{
    protected $signature = 'sentry:test {--exception : Test exception capture}';
    protected $description = 'Test Sentry integration';

    public function handle(): int
    {
        if ($this->option('exception')) {
            $this->info('Throwing test exception...');
            throw new \Exception('This is a test exception from Laravel CLI');
        }

        $this->info('Sending test message to Sentry...');

        SentryHelper::captureMessage(
            'Test message from Laravel',
            [
                'environment' => app()->environment(),
                'laravel_version' => app()->version(),
                'user' => 'CLI Test',
            ],
            \Sentry\Severity::INFO
        );

        $this->info('✓ Message sent to Sentry');
        $this->info('Check your Sentry dashboard: https://sentry.io');

        return self::SUCCESS;
    }
}
```

### Étape 11: Ajouter des commandes Make file

**Makefile** - Ajouter:

```makefile
# Sentry Commands
.PHONY: sentry-test
sentry-test: ## Test Sentry integration
	@echo "$(YELLOW)→ Testing Sentry integration...$(NC)"
	@docker exec $(PHP_CONTAINER_NAME) php artisan sentry:test
	@echo "$(GREEN)✓ Check Sentry dashboard$(NC)"

.PHONY: sentry-test-exception
sentry-test-exception: ## Test Sentry exception capture
	@echo "$(YELLOW)→ Testing exception capture...$(NC)"
	@docker exec $(PHP_CONTAINER_NAME) php artisan sentry:test --exception || true
	@echo "$(GREEN)✓ Check Sentry dashboard for exception$(NC)"
```

### Étape 12: Configuration GitHub Actions

**.github/workflows/deploy.yml** - Ajouter:

```yaml
- name: Create Sentry release
  if: startsWith(github.ref, 'refs/tags/')
  env:
    SENTRY_AUTH_TOKEN: ${{ secrets.SENTRY_AUTH_TOKEN }}
    SENTRY_ORG: your-org
    SENTRY_PROJECT: your-project
  run: |
    curl -sL https://sentry.io/get-cli/ | bash
    export SENTRY_RELEASE=$(sentry-cli releases propose-version)
    sentry-cli releases new -p $SENTRY_PROJECT $SENTRY_RELEASE
    sentry-cli releases set-commits --auto $SENTRY_RELEASE
    sentry-cli releases finalize $SENTRY_RELEASE
    sentry-cli releases deploys $SENTRY_RELEASE new -e production
```

### Étape 13: Créer des tests

**tests/Feature/SentryIntegrationTest.php**:

```php
<?php

use App\Helpers\SentryHelper;

test('sentry is bound in container', function () {
    expect(app()->bound('sentry'))->toBeTrue();
});

test('can capture message manually', function () {
    SentryHelper::captureMessage('Test message', ['foo' => 'bar']);

    // No exception thrown = success
    expect(true)->toBeTrue();
});

test('can add breadcrumb', function () {
    SentryHelper::addBreadcrumb('Test breadcrumb', ['test' => true]);

    expect(true)->toBeTrue();
});

test('exception handler captures exceptions', function () {
    $this->withoutExceptionHandling();

    expect(function () {
        throw new \Exception('Test exception');
    })->toThrow(\Exception::class);
});
```

### Étape 14: Documentation

**Créer docs/SENTRY-SETUP.md**:

```markdown
# Sentry Error Tracking Setup

## Configuration

### 1. Créer un projet Sentry

1. Aller sur https://sentry.io
2. Créer un compte/organisation
3. Créer un nouveau projet Laravel
4. Copier le DSN

### 2. Configurer les variables d'environnement

\`\`\`env
SENTRY_LARAVEL_DSN=https://xxx@xxx.ingest.sentry.io/xxx
SENTRY_TRACES_SAMPLE_RATE=0.2
SENTRY_PROFILES_SAMPLE_RATE=0.2
SENTRY_ENVIRONMENT=production
\`\`\`

### 3. Tester l'intégration

\`\`\`bash
make sentry-test                # Test message
make sentry-test-exception      # Test exception
\`\`\`

## Usage

### Capturer des messages

\`\`\`php
use App\Helpers\SentryHelper;

SentryHelper::captureMessage('Something happened', [
    'user_id' => $userId,
    'action' => 'payment',
], 'warning');
\`\`\`

### Capturer des exceptions

\`\`\`php
try {
    // risky code
} catch (\\Throwable $e) {
    SentryHelper::captureException($e, [
        'context' => 'payment_processing',
        'amount' => $amount,
    ]);
}
\`\`\`

### Ajouter des breadcrumbs

\`\`\`php
SentryHelper::addBreadcrumb('User clicked button', [
    'button_id' => 'checkout',
], 'user_action');
\`\`\`

### Performance monitoring

\`\`\`php
$transaction = SentryHelper::startTransaction('process-order');

// Your code here

$transaction?->finish();
\`\`\`

## Best Practices

1. **Ne pas envoyer de PII** (données personnelles) sans consentement
2. **Filtrer les exceptions non pertinentes** (404, auth failures)
3. **Utiliser les tags** pour catégoriser les erreurs
4. **Ajouter du contexte** avec breadcrumbs
5. **Monitor les performances** avec traces sampling

## Alertes

Configurer des alertes dans Sentry pour:
- Nouvelles erreurs
- Spike d'erreurs (>X% augmentation)
- Erreurs sur les endpoints critiques
- Dégradation des performances

## Dashboard recommandé

Créer un dashboard avec:
- Total d'erreurs par jour
- Erreurs par endpoint
- Erreurs par utilisateur
- Performance des transactions
- Taux d'erreur par release
\`\`\`

### Étape 15: Mettre à jour le README

**README.md** - Ajouter:

```markdown
## 🔍 Error Tracking avec Sentry

### Configuration

\`\`\`bash
# Configurer Sentry DSN dans .env
SENTRY_LARAVEL_DSN=your-dsn

# Tester l'intégration
make sentry-test
\`\`\`

### Documentation

Voir [docs/SENTRY-SETUP.md](docs/SENTRY-SETUP.md)
```

## Checklist de vérification

- [ ] Sentry SDK installé
- [ ] Configuration publiée
- [ ] Variables d'environnement configurées
- [ ] Handler d'exceptions intégré
- [ ] Middleware SentryContext créé
- [ ] Helper SentryHelper créé
- [ ] Performance monitoring configuré
- [ ] Commande de test créée
- [ ] Commandes Makefile ajoutées
- [ ] GitHub Actions configuré (releases)
- [ ] Tests créés et passent
- [ ] Documentation créée (SENTRY-SETUP.md)
- [ ] README mis à jour
- [ ] Test en production validé
- [ ] Commit créé

## Fonctionnalités avancées à considérer

Après l'implémentation de base:

1. **Source Maps** pour JavaScript (si utilisation frontend)
2. **Replays** pour voir les sessions utilisateur
3. **Profiling** pour identifier les bottlenecks
4. **Cron Monitoring** pour surveiller les scheduled tasks
5. **Custom Metrics** pour business KPIs
6. **Alerts personnalisées** par Slack/Email
7. **Releases tracking** automatique via CI/CD

## Coût et limites

- **Free tier**: 5,000 événements/mois
- **Team tier**: $26/mois (50K événements)
- **Business**: $80/mois (500K événements)

Configurer `traces_sample_rate` selon le volume pour contrôler les coûts.

## Références

- Sentry Laravel SDK: https://docs.sentry.io/platforms/php/guides/laravel/
- Performance Monitoring: https://docs.sentry.io/product/performance/
- Error Tracking: https://docs.sentry.io/product/issues/
