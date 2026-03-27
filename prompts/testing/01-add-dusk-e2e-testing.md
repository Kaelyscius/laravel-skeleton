# Prompt: Ajouter Laravel Dusk pour les tests E2E

## Contexte
Le skeleton Laravel dispose de Pest pour les tests unitaires et feature, mais n'a pas de solution pour les tests end-to-end (E2E) avec un vrai navigateur.

## Objectif
Implémenter Laravel Dusk pour effectuer des tests automatisés dans un navigateur Chrome headless, simulant de vraies interactions utilisateur.

## Instructions pour Claude Code

### Étape 1: Installer Laravel Dusk

```bash
cd src
composer require --dev laravel/dusk
php artisan dusk:install
```

### Étape 2: Configurer Dusk pour Docker

**Créer docker/selenium/Dockerfile**:

```dockerfile
FROM selenium/standalone-chrome:latest

USER root

# Install necessary packages
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

USER seluser
```

### Étape 3: Ajouter Selenium au docker-compose

**docker-compose.dev.yml** - Ajouter service:

```yaml
services:
  selenium:
    build:
      context: ./docker/selenium
      dockerfile: Dockerfile
    profiles: ["dev"]
    container_name: ${COMPOSE_PROJECT_NAME}_selenium
    networks:
      - laravel-network
    shm_size: 2gb
    environment:
      - SE_NODE_MAX_SESSIONS=5
      - SE_NODE_SESSION_TIMEOUT=300
    ports:
      - "4444:4444"
      - "7900:7900"  # VNC pour debug
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4444/wd/hub/status"]
      interval: 10s
      timeout: 5s
      retries: 5
```

### Étape 4: Configurer Dusk pour utiliser Selenium

**tests/DuskTestCase.php**:

```php
<?php

namespace Tests;

use Facebook\WebDriver\Chrome\ChromeOptions;
use Facebook\WebDriver\Remote\DesiredCapabilities;
use Facebook\WebDriver\Remote\RemoteWebDriver;
use Laravel\Dusk\TestCase as BaseTestCase;

abstract class DuskTestCase extends BaseTestCase
{
    /**
     * Prepare for Dusk test execution.
     */
    public static function prepare(): void
    {
        if (!static::runningInSail()) {
            // Only start ChromeDriver if not using Selenium
            // static::startChromeDriver();
        }
    }

    /**
     * Create the RemoteWebDriver instance.
     */
    protected function driver(): RemoteWebDriver
    {
        $options = (new ChromeOptions)->addArguments(collect([
            $this->shouldStartMaximized() ? '--start-maximized' : '--window-size=1920,1080',
            '--disable-gpu',
            '--no-sandbox',
            '--disable-dev-shm-usage',
        ])->filter()->all());

        $capabilities = DesiredCapabilities::chrome()->setCapability(
            ChromeOptions::CAPABILITY, $options
        );

        // Use Selenium in Docker
        $seleniumUrl = env('SELENIUM_URL', 'http://selenium:4444/wd/hub');

        return RemoteWebDriver::create(
            $seleniumUrl,
            $capabilities,
            60000,
            60000
        );
    }

    /**
     * Determine if the tests are running within Laravel Sail or Docker
     */
    protected static function runningInSail(): bool
    {
        return env('LARAVEL_SAIL') === '1' ||
               file_exists('/.dockerenv') ||
               env('SELENIUM_URL') !== null;
    }

    /**
     * Determine whether the browser should start maximized.
     */
    protected function shouldStartMaximized(): bool
    {
        return false;
    }
}
```

### Étape 5: Configurer les variables d'environnement

**.env.testing** - Créer ou modifier:

```env
APP_URL=http://apache
APP_ENV=testing
APP_DEBUG=true

# Selenium configuration
SELENIUM_URL=http://selenium:4444/wd/hub
DUSK_DRIVER_URL=http://selenium:4444/wd/hub

# Database
DB_CONNECTION=mysql
DB_HOST=mariadb
DB_PORT=3306
DB_DATABASE=laravel_test
DB_USERNAME=laravel
DB_PASSWORD=secret

# Cache & Queue
CACHE_DRIVER=array
QUEUE_CONNECTION=sync
SESSION_DRIVER=array
```

### Étape 6: Créer des tests Dusk exemples

**tests/Browser/ExampleTest.php**:

```php
<?php

namespace Tests\Browser;

use Laravel\Dusk\Browser;
use Tests\DuskTestCase;

class ExampleTest extends DuskTestCase
{
    /**
     * A basic browser test example.
     */
    public function test_basic_example(): void
    {
        $this->browse(function (Browser $browser) {
            $browser->visit('/')
                    ->assertSee('Laravel');
        });
    }

    /**
     * Test homepage loads correctly
     */
    public function test_homepage_loads(): void
    {
        $this->browse(function (Browser $browser) {
            $browser->visit('/')
                    ->assertTitle('Laravel')
                    ->assertSee('Laravel')
                    ->screenshot('homepage');
        });
    }

    /**
     * Test navigation works
     */
    public function test_navigation(): void
    {
        $this->browse(function (Browser $browser) {
            $browser->visit('/')
                    ->clickLink('Documentation')
                    ->assertUrlIs('https://laravel.com/docs')
                    ->back()
                    ->assertPathIs('/');
        });
    }
}
```

**tests/Browser/Auth/LoginTest.php**:

```php
<?php

namespace Tests\Browser\Auth;

use App\Models\User;
use Laravel\Dusk\Browser;
use Tests\DuskTestCase;

class LoginTest extends DuskTestCase
{
    /**
     * Test user can view login form
     */
    public function test_user_can_view_login_form(): void
    {
        $this->browse(function (Browser $browser) {
            $browser->visit('/login')
                    ->assertSee('Login')
                    ->assertSee('Email')
                    ->assertSee('Password')
                    ->assertPresent('input[name="email"]')
                    ->assertPresent('input[name="password"]')
                    ->assertPresent('button[type="submit"]');
        });
    }

    /**
     * Test user can login with valid credentials
     */
    public function test_user_can_login_with_valid_credentials(): void
    {
        $user = User::factory()->create([
            'email' => 'test@example.com',
            'password' => bcrypt('password'),
        ]);

        $this->browse(function (Browser $browser) use ($user) {
            $browser->visit('/login')
                    ->type('email', $user->email)
                    ->type('password', 'password')
                    ->press('Login')
                    ->assertPathIs('/dashboard')
                    ->assertAuthenticatedAs($user);
        });
    }

    /**
     * Test user cannot login with invalid credentials
     */
    public function test_user_cannot_login_with_invalid_credentials(): void
    {
        $this->browse(function (Browser $browser) {
            $browser->visit('/login')
                    ->type('email', 'wrong@example.com')
                    ->type('password', 'wrongpassword')
                    ->press('Login')
                    ->assertPathIs('/login')
                    ->assertSee('These credentials do not match our records')
                    ->assertGuest();
        });
    }

    /**
     * Test login form validation
     */
    public function test_login_form_validation(): void
    {
        $this->browse(function (Browser $browser) {
            $browser->visit('/login')
                    ->press('Login')
                    ->assertSee('The email field is required')
                    ->assertSee('The password field is required');
        });
    }
}
```

**tests/Browser/Api/UserApiTest.php**:

```php
<?php

namespace Tests\Browser\Api;

use App\Models\User;
use Laravel\Dusk\Browser;
use Tests\DuskTestCase;

class UserApiTest extends DuskTestCase
{
    /**
     * Test API documentation is accessible
     */
    public function test_api_documentation_loads(): void
    {
        $this->browse(function (Browser $browser) {
            $browser->visit('/api/documentation')
                    ->assertSee('API Documentation')
                    ->assertSee('Swagger')
                    ->screenshot('api-docs');
        });
    }

    /**
     * Test can interact with Swagger UI
     */
    public function test_can_use_swagger_try_it_out(): void
    {
        $user = User::factory()->create();

        $this->browse(function (Browser $browser) use ($user) {
            $browser->visit('/api/documentation')
                    // Expand GET /api/users endpoint
                    ->click('[data-path="/api/users"]')
                    ->pause(500)
                    // Click Try it out
                    ->click('button.try-out__btn')
                    ->pause(500)
                    // Execute request
                    ->click('button.execute')
                    ->pause(1000)
                    // Verify response
                    ->assertSee('Response body')
                    ->assertSee('200')
                    ->screenshot('swagger-execute');
        });
    }
}
```

### Étape 7: Configurer Pest pour Dusk

**tests/Pest.php** - Ajouter:

```php
uses(Tests\DuskTestCase::class)->in('Browser');

// Helper pour les tests Dusk
function browser(Closure $callback): void
{
    test()->browse($callback);
}
```

### Étape 8: Créer des commandes Makefile

**Makefile** - Ajouter:

```makefile
# Dusk E2E Testing
.PHONY: dusk
dusk: ## Run Dusk E2E tests
	@echo "$(YELLOW)→ Running Dusk tests...$(NC)"
	@docker exec $(PHP_CONTAINER_NAME) php artisan dusk
	@echo "$(GREEN)✓ Dusk tests completed$(NC)"

.PHONY: dusk-filter
dusk-filter: ## Run specific Dusk test (use: make dusk-filter FILTER=LoginTest)
	@echo "$(YELLOW)→ Running Dusk tests matching: $(FILTER)$(NC)"
	@docker exec $(PHP_CONTAINER_NAME) php artisan dusk --filter=$(FILTER)

.PHONY: dusk-debug
dusk-debug: ## Run Dusk with VNC debugging enabled
	@echo "$(YELLOW)→ Starting Dusk with VNC debug mode$(NC)"
	@echo "$(BLUE)→ VNC available at: http://localhost:7900 (password: secret)$(NC)"
	@docker exec $(PHP_CONTAINER_NAME) php artisan dusk
	@echo "$(GREEN)✓ Check screenshots in tests/Browser/screenshots/$(NC)"

.PHONY: dusk-screenshots
dusk-screenshots: ## View Dusk screenshots
	@echo "$(CYAN)Screenshots:$(NC)"
	@ls -lh src/tests/Browser/screenshots/ 2>/dev/null || echo "No screenshots found"

.PHONY: dusk-clear
dusk-clear: ## Clear Dusk screenshots and console logs
	@echo "$(YELLOW)→ Clearing Dusk artifacts...$(NC)"
	@rm -rf src/tests/Browser/screenshots/*
	@rm -rf src/tests/Browser/console/*
	@echo "$(GREEN)✓ Dusk artifacts cleared$(NC)"
```

### Étape 9: Configuration CI pour Dusk

**.github/workflows/ci.yml** - Ajouter job:

```yaml
dusk-tests:
  runs-on: ubuntu-latest

  services:
    selenium:
      image: selenium/standalone-chrome:latest
      options: --shm-size=2g
      ports:
        - 4444:4444

    mariadb:
      image: mariadb:11.4
      env:
        MYSQL_ROOT_PASSWORD: root
        MYSQL_DATABASE: laravel_test
        MYSQL_USER: laravel
        MYSQL_PASSWORD: secret
      ports:
        - 3306:3306
      options: >-
        --health-cmd="mysqladmin ping"
        --health-interval=10s
        --health-timeout=5s
        --health-retries=3

  steps:
    - uses: actions/checkout@v4

    - name: Setup PHP
      uses: shivammathur/setup-php@v2
      with:
        php-version: '8.5'
        extensions: mbstring, pdo, pdo_mysql, gd, redis

    - name: Install dependencies
      working-directory: src
      run: composer install --prefer-dist --no-progress

    - name: Copy environment file
      working-directory: src
      run: cp .env.testing .env

    - name: Generate application key
      working-directory: src
      run: php artisan key:generate

    - name: Run migrations
      working-directory: src
      env:
        DB_HOST: 127.0.0.1
        DB_PORT: 3306
      run: php artisan migrate --force

    - name: Start Laravel server
      working-directory: src
      run: php artisan serve &
      env:
        APP_URL: http://localhost:8000

    - name: Run Dusk tests
      working-directory: src
      env:
        SELENIUM_URL: http://localhost:4444/wd/hub
        APP_URL: http://localhost:8000
      run: php artisan dusk

    - name: Upload Dusk screenshots
      if: failure()
      uses: actions/upload-artifact@v4
      with:
        name: dusk-screenshots
        path: src/tests/Browser/screenshots

    - name: Upload Dusk console logs
      if: failure()
      uses: actions/upload-artifact@v4
      with:
        name: dusk-console
        path: src/tests/Browser/console
```

### Étape 10: Créer des Page Objects pour réutilisabilité

**tests/Browser/Pages/HomePage.php**:

```php
<?php

namespace Tests\Browser\Pages;

use Laravel\Dusk\Browser;
use Laravel\Dusk\Page;

class HomePage extends Page
{
    /**
     * Get the URL for the page.
     */
    public function url(): string
    {
        return '/';
    }

    /**
     * Assert that the browser is on the page.
     */
    public function assert(Browser $browser): void
    {
        $browser->assertPathIs($this->url());
    }

    /**
     * Get the element shortcuts for the page.
     */
    public function elements(): array
    {
        return [
            '@header' => 'header',
            '@navigation' => 'nav',
            '@footer' => 'footer',
            '@documentation-link' => 'a[href*="docs"]',
        ];
    }

    /**
     * Navigate to documentation
     */
    public function goToDocumentation(Browser $browser): void
    {
        $browser->click('@documentation-link');
    }
}
```

**tests/Browser/Pages/LoginPage.php**:

```php
<?php

namespace Tests\Browser\Pages;

use Laravel\Dusk\Browser;
use Laravel\Dusk\Page;

class LoginPage extends Page
{
    public function url(): string
    {
        return '/login';
    }

    public function assert(Browser $browser): void
    {
        $browser->assertPathIs($this->url())
                ->assertSee('Login');
    }

    public function elements(): array
    {
        return [
            '@email' => 'input[name="email"]',
            '@password' => 'input[name="password"]',
            '@remember' => 'input[name="remember"]',
            '@submit' => 'button[type="submit"]',
            '@forgot-password' => 'a[href*="forgot-password"]',
        ];
    }

    /**
     * Login with credentials
     */
    public function loginAs(Browser $browser, string $email, string $password): void
    {
        $browser->type('@email', $email)
                ->type('@password', $password)
                ->press('@submit');
    }
}
```

**Utilisation des Page Objects**:

```php
public function test_login_with_page_object(): void
{
    $user = User::factory()->create();

    $this->browse(function (Browser $browser) use ($user) {
        $browser->visit(new LoginPage)
                ->loginAs($browser, $user->email, 'password')
                ->assertPathIs('/dashboard');
    });
}
```

### Étape 11: Créer des helpers personnalisés

**tests/Browser/Concerns/InteractsWithApi.php**:

```php
<?php

namespace Tests\Browser\Concerns;

use Laravel\Dusk\Browser;

trait InteractsWithApi
{
    /**
     * Authenticate via API and set bearer token
     */
    protected function authenticateApi(Browser $browser, string $email, string $password): string
    {
        // Login and get token
        $response = $browser->visit('/api/login')
                            ->type('email', $email)
                            ->type('password', $password)
                            ->press('Login')
                            ->script('return document.body.textContent');

        $data = json_decode($response[0], true);
        $token = $data['token'] ?? null;

        if ($token) {
            // Store token in browser local storage
            $browser->script("localStorage.setItem('auth_token', '{$token}')");
        }

        return $token;
    }

    /**
     * Set authorization header
     */
    protected function withBearerToken(Browser $browser, string $token): void
    {
        $browser->script("
            window.authToken = '{$token}';
            fetch = (function(fetch) {
                return function(...args) {
                    if (args[1] && !args[1].headers) {
                        args[1].headers = {};
                    }
                    args[1].headers['Authorization'] = 'Bearer ' + window.authToken;
                    return fetch.apply(this, args);
                };
            })(fetch);
        ");
    }
}
```

### Étape 12: Documentation

**Créer docs/DUSK-TESTING.md**:

```markdown
# Laravel Dusk E2E Testing Guide

## Installation

Dusk est déjà configuré dans ce projet avec Selenium Chrome.

## Lancer les tests

\`\`\`bash
# Tous les tests Dusk
make dusk

# Tests spécifiques
make dusk-filter FILTER=LoginTest

# Avec debug VNC
make dusk-debug
# Puis ouvrir http://localhost:7900 (password: secret)
\`\`\`

## Créer un nouveau test

\`\`\`bash
php artisan dusk:make UserRegistrationTest
\`\`\`

## Structure recommandée

\`\`\`
tests/Browser/
├── Auth/
│   ├── LoginTest.php
│   ├── RegisterTest.php
│   └── PasswordResetTest.php
├── Pages/
│   ├── HomePage.php
│   ├── LoginPage.php
│   └── DashboardPage.php
├── Concerns/
│   └── InteractsWithApi.php
└── ExampleTest.php
\`\`\`

## Page Objects

Utiliser des Page Objects pour la réutilisabilité:

\`\`\`php
$this->browse(function (Browser $browser) {
    $browser->visit(new LoginPage)
            ->loginAs($browser, 'user@example.com', 'password')
            ->on(new DashboardPage)
            ->assertSee('Welcome');
});
\`\`\`

## Assertions courantes

\`\`\`php
$browser->assertSee('Text')
        ->assertDontSee('Hidden')
        ->assertPathIs('/dashboard')
        ->assertQueryStringHas('page', '1')
        ->assertVisible('#element')
        ->assertPresent('button')
        ->assertValue('input', 'expected')
        ->assertAttribute('img', 'src', 'image.jpg')
        ->assertAriaAttribute('button', 'pressed', 'true')
        ->assertDataAttribute('div', 'id', '1')
        ->assertTitle('Page Title');
\`\`\`

## Actions courantes

\`\`\`php
$browser->visit('/url')
        ->click('button')
        ->clickLink('Link Text')
        ->type('input', 'value')
        ->select('select', 'option')
        ->check('checkbox')
        ->uncheck('checkbox')
        ->radio('radio', 'value')
        ->attach('file', '/path/to/file')
        ->press('Submit')
        ->keys('selector', '{shift}', 'a')
        ->waitFor('selector')
        ->waitUntilMissing('selector')
        ->pause(1000);
\`\`\`

## JavaScript Execution

\`\`\`php
// Execute JavaScript
$browser->script('return window.location.href');

// Store value
$result = $browser->script(['return 1 + 1'])[0];

// Console logs
$browser->assertConsoleLog('Expected log message');
\`\`\`

## Screenshots & Debugging

\`\`\`php
// Take screenshot
$browser->screenshot('test-name');

// Take screenshot on failure (automatic)
// Screenshots stored in: tests/Browser/screenshots/

// View screenshots
make dusk-screenshots

// Clear screenshots
make dusk-clear
\`\`\`

## VNC Debugging

1. Start test with `make dusk-debug`
2. Open http://localhost:7900 in browser
3. Password: `secret`
4. Watch test execution in real-time

## Best Practices

1. **Use Page Objects** pour réutilisabilité
2. **Explicit Waits** plutôt que pause()
3. **Screenshot on failure** pour debugging
4. **Clean database** entre tests
5. **Descriptive test names** pour lisibilité
6. **Test critical paths** d'abord
7. **Mock external APIs** dans tests E2E

## CI/CD

Tests Dusk s'exécutent automatiquement dans GitHub Actions.
Voir `.github/workflows/ci.yml` pour la configuration.

## Troubleshooting

### Timeout errors

Augmenter le timeout:
\`\`\`php
$browser->waitFor('selector', 30); // 30 seconds
\`\`\`

### Element not found

Vérifier avec `waitFor`:
\`\`\`php
$browser->waitFor('selector')->click('selector');
\`\`\`

### Screenshots vides

Vérifier que Selenium est bien démarré:
\`\`\`bash
docker ps | grep selenium
\`\`\`

### VNC ne fonctionne pas

Vérifier le port 7900:
\`\`\`bash
docker logs laravel-app_selenium
\`\`\`
\`\`\`

### Étape 13: Mettre à jour README

**README.md** - Ajouter:

```markdown
## 🧪 Tests E2E avec Dusk

### Lancer les tests

\`\`\`bash
make dusk                           # Tous les tests
make dusk-filter FILTER=LoginTest   # Tests spécifiques
make dusk-debug                     # Avec VNC debugging
\`\`\`

### Debug visuel

VNC disponible sur http://localhost:7900 (password: secret)

### Documentation

Voir [docs/DUSK-TESTING.md](docs/DUSK-TESTING.md)
```

## Checklist de vérification

- [ ] Laravel Dusk installé
- [ ] Service Selenium ajouté à Docker Compose
- [ ] DuskTestCase configuré pour Selenium
- [ ] Variables d'environnement configurées
- [ ] Tests exemples créés
- [ ] Page Objects créés
- [ ] Helpers personnalisés créés
- [ ] Commandes Makefile ajoutées
- [ ] CI/CD configuré (GitHub Actions)
- [ ] Documentation créée
- [ ] README mis à jour
- [ ] Tests passent localement
- [ ] VNC debugging fonctionne
- [ ] Commit créé

## Avantages de Dusk

1. ✅ **Tests dans un vrai navigateur** (Chrome)
2. ✅ **JavaScript support** complet
3. ✅ **Screenshots automatiques** sur échec
4. ✅ **VNC debugging** en temps réel
5. ✅ **Page Objects** pour réutilisabilité
6. ✅ **CI/CD ready** avec Selenium
7. ✅ **Syntaxe expressive** similaire à Pest

## Références

- Laravel Dusk: https://laravel.com/docs/dusk
- Selenium: https://www.selenium.dev/
- ChromeDriver: https://chromedriver.chromium.org/
