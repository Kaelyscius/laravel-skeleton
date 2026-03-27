# Prompt: Restaurer l'application Laravel 12

## Contexte
Le répertoire `/src` de ce skeleton Laravel est actuellement vide. Tous les fichiers Laravel ont été supprimés (voir git status avec marqueur 'D'). Ce prompt guide la restauration complète de l'application Laravel 12.

## Objectif
Restaurer une application Laravel 12 complète dans `/src` avec tous les packages et configurations décrits dans la documentation du projet.

## Instructions pour Claude Code

### Étape 1: Installation Laravel de base
```bash
# Créer une nouvelle installation Laravel 12 dans /src
composer create-project laravel/laravel:^12.0 src-temp
# Copier le contenu dans /src
cp -r src-temp/* src/
cp -r src-temp/.* src/ 2>/dev/null || true
rm -rf src-temp
cd src
```

### Étape 2: Installer les packages de production mentionnés

**Packages Horizon & Telescope**:
```bash
composer require laravel/horizon
composer require laravel/telescope --dev
```

**Packages Sanctum**:
```bash
composer require laravel/sanctum
```

**Packages Spatie**:
```bash
composer require spatie/laravel-permission
composer require spatie/laravel-activitylog
composer require spatie/laravel-health
composer require spatie/laravel-schedule-monitor
composer require spatie/laravel-csp
```

**Monitoring**:
```bash
composer require laravel/nightwatch
```

### Étape 3: Installer les packages de développement

**Outils de qualité**:
```bash
composer require --dev larastan/larastan
composer require --dev symplify/easy-coding-standard
composer require --dev rector/rector
composer require --dev nunomaduro/phpinsights
composer require --dev enlightn/enlightn
```

**Testing**:
```bash
composer require --dev pestphp/pest
composer require --dev pestphp/pest-plugin-laravel
composer require --dev pestphp/pest-plugin-drift
```

**IDE & Debug**:
```bash
composer require --dev barryvdh/laravel-ide-helper
composer require --dev barryvdh/laravel-debugbar
composer require --dev beyondcode/laravel-query-detector
```

### Étape 4: Publier les configurations

```bash
# Horizon
php artisan vendor:publish --provider="Laravel\Horizon\HorizonServiceProvider"

# Telescope
php artisan vendor:publish --provider="Laravel\Telescope\TelescopeServiceProvider"

# Sanctum
php artisan vendor:publish --provider="Laravel\Sanctum\SanctumServiceProvider"

# Spatie Packages
php artisan vendor:publish --provider="Spatie\Permission\PermissionServiceProvider"
php artisan vendor:publish --provider="Spatie\Activitylog\ActivitylogServiceProvider"
php artisan vendor:publish --provider="Spatie\Health\HealthServiceProvider"
php artisan vendor:publish --provider="Spatie\ScheduleMonitor\ScheduleMonitorServiceProvider"
php artisan vendor:publish --provider="Spatie\Csp\CspServiceProvider"

# PHPInsights
php artisan vendor:publish --provider="NunoMaduro\PhpInsights\Application\Adapters\Laravel\InsightsServiceProvider"
```

### Étape 5: Configurer les fichiers de configuration

**config/horizon.php**:
- Ajuster les queues selon les besoins
- Configurer Redis connection
- Définir les supervisors

**config/telescope.php**:
- Activer seulement en environnement local
- Configurer les watchers nécessaires
- Limiter le storage

**config/health.php**:
- Activer checks: database, cache, queue, disk, redis
- Configurer les seuils

**config/schedule-monitor.php**:
- Configurer la surveillance des cron jobs

**config/csp.php**:
- Définir une politique CSP stricte mais fonctionnelle

### Étape 6: Créer les fichiers de configuration des outils

**phpstan.neon**:
```neon
includes:
    - ./vendor/larastan/larastan/extension.neon

parameters:
    level: 8
    paths:
        - app
        - config
        - database
        - routes
    excludePaths:
        - vendor
    checkMissingIterableValueType: false
```

**ecs.php**:
```php
<?php

use PhpCsFixer\Fixer\ArrayNotation\ArraySyntaxFixer;
use Symplify\EasyCodingStandard\Config\ECSConfig;

return ECSConfig::configure()
    ->withPaths([
        __DIR__ . '/app',
        __DIR__ . '/config',
        __DIR__ . '/database',
        __DIR__ . '/routes',
        __DIR__ . '/tests',
    ])
    ->withRules([
        ArraySyntaxFixer::class,
    ])
    ->withPreparedSets(
        psr12: true,
        common: true,
        symplify: true,
        strict: true,
    );
```

**rector.php**:
```php
<?php

use Rector\Config\RectorConfig;
use Rector\Set\ValueObject\LevelSetList;
use Rector\Set\ValueObject\SetList;

return RectorConfig::configure()
    ->withPaths([
        __DIR__ . '/app',
        __DIR__ . '/config',
        __DIR__ . '/database',
        __DIR__ . '/routes',
        __DIR__ . '/tests',
    ])
    ->withSets([
        LevelSetList::UP_TO_PHP_84,
        SetList::CODE_QUALITY,
        SetList::DEAD_CODE,
        SetList::EARLY_RETURN,
        SetList::TYPE_DECLARATION,
    ]);
```

### Étape 7: Configurer Pest

**tests/Pest.php**:
```php
<?php

use Illuminate\Foundation\Testing\RefreshDatabase;

uses(
    Tests\TestCase::class,
    RefreshDatabase::class,
)->in('Feature');

uses(Tests\TestCase::class)->in('Unit');

expect()->extend('toBeOne', function () {
    return $this->toBe(1);
});
```

**Créer des tests exemples**:
- `tests/Unit/ExampleTest.php`
- `tests/Feature/ExampleTest.php`

### Étape 8: Créer des exemples d'implémentation

**app/Http/Controllers/Api/ExampleController.php**:
- Controller API avec Sanctum
- Responses structurées
- Validation

**app/Models/Example.php**:
- Model avec traits Spatie
- Activity logging
- Permissions

**database/migrations/xxxx_create_examples_table.php**:
- Migration exemple
- Indexes appropriés

**database/seeders/DatabaseSeeder.php**:
- Seeder exemple avec Faker
- Création users de test

**app/Jobs/ExampleJob.php**:
- Job exemple pour Horizon
- Retry logic
- Timeout configuration

### Étape 9: Configurer le .env.example

Copier depuis la racine du projet si existant, sinon créer avec:
```env
APP_NAME=Laravel
APP_ENV=local
APP_KEY=
APP_DEBUG=true
APP_URL=http://localhost

# Database
DB_CONNECTION=mysql
DB_HOST=mariadb
DB_PORT=3306
DB_DATABASE=laravel
DB_USERNAME=laravel
DB_PASSWORD=secret

# Redis
REDIS_HOST=redis
REDIS_PASSWORD=null
REDIS_PORT=6379

# Queue
QUEUE_CONNECTION=redis

# Horizon
HORIZON_PATH=horizon

# Telescope
TELESCOPE_ENABLED=true
TELESCOPE_PATH=telescope

# Nightwatch (optionnel)
NIGHTWATCH_API_KEY=
NIGHTWATCH_PROJECT_ID=
```

### Étape 10: Générer les helpers IDE

```bash
php artisan ide-helper:generate
php artisan ide-helper:models --nowrite
php artisan ide-helper:meta
```

### Étape 11: Vérifier l'installation

```bash
# Vérifier Composer
composer validate

# Vérifier Laravel
php artisan about

# Vérifier les packages
php artisan package:discover

# Tester PHPStan
vendor/bin/phpstan analyse --memory-limit=2G

# Tester ECS
vendor/bin/ecs check

# Tester les tests
vendor/bin/pest
```

### Étape 12: Créer un commit de restauration

```bash
git add .
git commit -m "feat: Restore Laravel 12 application with all packages

- Install Laravel 12 base
- Add Horizon, Telescope, Sanctum
- Install all Spatie packages
- Configure quality tools (PHPStan level 8, ECS, Rector)
- Set up Pest testing framework
- Add IDE helpers
- Create example implementations
- Configure all services

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

## Checklist de vérification

- [ ] Laravel 12 installé dans `/src`
- [ ] Tous les packages mentionnés installés
- [ ] Configurations publiées
- [ ] Fichiers de config outils créés (phpstan.neon, ecs.php, rector.php)
- [ ] Pest configuré avec tests exemples
- [ ] Exemples créés (controller, model, migration, seeder, job)
- [ ] .env.example à jour
- [ ] IDE helpers générés
- [ ] Tests passent
- [ ] PHPStan level 8 passe
- [ ] ECS check passe
- [ ] Commit créé

## Notes importantes

1. **Version PHP**: S'assurer que PHP 8.5.1 est utilisé (vérifier Dockerfile)
2. **Compatibilité**: Tous les packages doivent être compatibles Laravel 12
3. **Tests**: Créer des tests pour chaque exemple d'implémentation
4. **Documentation**: Mettre à jour le README si nécessaire

## Après la restauration

Une fois cette restauration terminée, vous pourrez:
1. Exécuter `make install-laravel` pour finaliser
2. Lancer `make migrate` pour les migrations
3. Utiliser `make quality-all` pour vérifier la qualité
4. Commencer à développer sur une base solide

## Références

- Documentation Laravel 12: https://laravel.com/docs/12.x
- Larastan: https://github.com/larastan/larastan
- Pest: https://pestphp.com
- Spatie Packages: https://spatie.be/open-source
