# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Docker Environment - Architecture Modulaire

**🎯 Architecture avec Profiles Docker** : Ce projet utilise une architecture modulaire basée sur les Docker Compose Profiles permettant de démarrer uniquement les services nécessaires selon l'environnement. Voir [DOCKER-ARCHITECTURE.md](./DOCKER-ARCHITECTURE.md) pour la documentation complète.

#### Démarrage par environnement
- `make up-local` - **Développement local complet** (recommandé) - Services essentiels + dev + tools
- `make up-dev` - Développement - Services essentiels + outils dev (node, mailpit, adminer)
- `make up-dev-full` - Développement complet - Tous les services + monitoring (dozzle, it-tools, watchtower)
- `make up-dev-extra` - Développement + outils extra (phpmyadmin, redis-commander)
- `make up-prod` - Production - Services essentiels uniquement (apache, php, postgres, redis)
- `make up-tools` - Démarrer uniquement les outils de monitoring (dozzle, it-tools, watchtower)

#### Profiles disponibles
- **Aucun profile** (Production) : apache, php, postgres, redis
- **dev** (Développement) : node, mailpit, adminer
- **tools** (Utilitaires) : dozzle, it-tools, watchtower
- **dev-extra** (Outils additionnels) : phpmyadmin, redis-commander

#### Gestion des containers
- `make up` - Start containers (ancien comportement, démarrage basique)
- `make down` - Stop all containers
- `make restart` - Restart containers
- `make status` - Check container status
- `make ps-profiles` - Show active services by profile
- `make stop-profile PROFILE=dev` - Stop specific profile

#### Build et maintenance
- `make build` - Build Docker images
- `make build-fast` - Build with cache (faster)
- `make rebuild` - Rebuild and restart
- `make shell` - Access PHP container shell
- `make logs` - View container logs
- `make logs service=php` - View specific service logs
- `make fix-permissions` - Fix file permissions for PhpStorm/IDE

### Laravel Development
- `make install-dev-full` - **Installation complète recommandée** (build + up + Laravel + npm + SSL)
- `make install-laravel` - Install Laravel with dependencies (containers déjà démarrés)
- `make artisan cmd="migrate"` - Run artisan commands
- `make composer cmd="install"` - Run composer commands
- `make migrate` - Run database migrations
- `make fresh` - Fresh database with seeders

### Frontend Development
- `make npm-install` - Install Node.js dependencies
- `make npm-build` - Build production assets
- `make npm-dev` - Start development server
- `make npm-watch` - Watch for file changes

### Testing
- `make test` - Run all tests (using Pest framework)
- `make test-unit` - Run unit tests only
- `make test-feature` - Run feature tests only
- `make test-coverage` - Run tests with coverage report
- `make test-drift` - Run tests with Drift (detect uncovered code)

### Diagnostics & Troubleshooting
- `make diagnostic` - Run complete diagnostic suite (PHP 8.5.1 + Laravel 12)
- `make quick-check` - Quick test of Laravel + PHP 8.5.1 compatibility
- `make check-extensions` - Verify PHP 8.5.1 extensions installation
- `make test-packages` - Test package compatibility with Laravel 12
- `make fix-composer` - Fix Composer configuration and cache issues
- `make check-compatibility` - Check if incompatible packages became Laravel 12 compatible
- `make update-packages` - Auto-install packages that became Laravel 12 compatible
- `make enable-xdebug` - Enable Xdebug for development (rebuilds containers)

### Code Quality
- `make ecs` - Check code style (Easy Coding Standard)
- `make ecs-fix` - Fix code style issues
- `make phpstan` - Run static analysis (PHPStan/Larastan level 8)
- `make rector` - Show refactoring suggestions (dry-run)
- `make rector-fix` - Apply refactoring suggestions
- `make insights` - Run PHP Insights analysis
- `make quality-all` - Run complete quality audit (ECS + PHPStan + Rector + Insights)
- `make quality-fix` - Fix all auto-fixable quality issues (ECS + Rector)
- `make quality-quick` - Quick quality check (ECS + PHPStan only)
- `make archeology` - Full architecture metrics + git churn report (HTML + JSON)
- `make archeology-quick` - Quick architecture analysis
- `make ide-helper` - Regenerate IDE helpers (_ide_helper.php, _ide_helper_models.php, .phpstorm.meta.php)

### Security & Monitoring
- `make security-setup` - Setup Snyk security scanning
- `make security-scan` - Run security vulnerability scan (PHP + Node)
- `make security-scan-php` - Scan PHP dependencies only
- `make security-scan-node` - Scan Node.js dependencies only
- `make nightwatch-start` - Start Laravel Nightwatch agent
- `make nightwatch-status` - Check Nightwatch status
- `make health` - Run Laravel health checks (DB, Cache, Queue, etc.)
- `make schedule-monitor-sync` - Sync schedule monitor
- `make schedule-monitor-list` - List monitored scheduled tasks

### AI Assistance (Laravel Boost)
- `make boost-mcp` - Configure MCP server for Claude Code (côté hôte)
- `make boost-setup` - Install and configure Laravel Boost
- `make boost-update` - Update Laravel Boost guidelines

### Deployment & Setup
- `make setup-interactive` - Interactive environment setup
- `make setup-dev` - Development environment setup
- `make setup-prod` - Production environment setup
- `make install-dev-full` - Full dev install (build + up + Laravel + npm + SSL)
- `make update-deps` - Update Composer + NPM dependencies

## Project Architecture

### Docker-based Modular Architecture

**Architecture modulaire avec Docker Compose Profiles** permettant de démarrer uniquement les services nécessaires selon l'environnement.

#### Services essentiels (toujours actifs, aucun profile)
- **PHP 8.5.1** container with FPM, Supervisor, and OPcache
- **Apache 2.4** with HTTPS/HTTP2 support
- **PostgreSQL** for database
- **Redis** for caching and sessions

#### Profile "dev" (Outils de développement)
- **Node.js 24** for frontend builds (LTS "Krypton")
- **Mailpit** for email testing (port 8025)
- **Adminer** for database management (port 8080)

#### Profile "tools" (Monitoring et utilitaires)
- **Dozzle** for real-time log monitoring (port 9999)
- **IT-Tools** for development utilities (port 8081)
- **Watchtower** for automatic container updates

#### Profile "dev-extra" (Outils additionnels)
- **PHPMyAdmin** as an alternative to Adminer (port 8083)
- **Redis Commander** for Redis management (port 8082)

#### Commandes recommandées
- **Développement local** : `make up-local` (tous les outils)
- **Production** : `make up-prod` (services essentiels uniquement)
- **Documentation complète** : Voir [DOCKER-ARCHITECTURE.md](./DOCKER-ARCHITECTURE.md)

### Laravel 12 Application Structure
- Main application code in `/src` directory
- Standard Laravel folder structure within `/src`
- Uses Pest for testing framework
- Configured with Laravel Horizon for queue management
- Laravel Telescope for debugging
- Laravel Sanctum for API authentication
- Laravel Nightwatch for monitoring

### Quality Tools Configuration
- **PHPStan/Larastan** (v3.x) at level 8 for strict type checking
- **ECS** (Easy Coding Standard v13.x) for PSR-12 compliance
- **Rector** (v2.x) for automated refactoring — rules PHP 8.5 + Laravel 12
- **driftingly/rector-laravel** (v2.x) for Laravel-specific Rector rules
- **PHP Insights** (v2.14+) for code quality metrics
- **PhpCodeArcheology** (v2.x) for architecture metrics + git churn analysis
- **Snyk** for security vulnerability scanning

### Key Configuration Files
- `src/composer.json` - PHP dependencies and scripts
- `src/package.json` - Node.js dependencies
- `src/phpstan.neon` - PHPStan configuration (level 8)
- `src/ecs.php` - Code style configuration
- `src/rector.php` - Refactoring rules
- `src/vite.config.js` - Frontend build configuration
- `docker-compose.yml` - Docker services configuration with profiles
- `docker-compose.dev.yml` - Development environment overrides
- `docker-compose.prod.yml` - Production environment overrides
- `docker-compose.override.yml` - Local overrides (auto-generated)
- `Makefile` - Development commands
- `DOCKER-ARCHITECTURE.md` - Documentation de l'architecture modulaire

### Environment Management
- Multiple environment configurations via interactive setup
- **Docker Compose Profiles** for modular service management
- Docker compose overrides for dev/prod environments with profiles
- Automated SSL certificate generation
- Flexible profile activation (`dev`, `tools`, `dev-extra`)

### Testing Setup
- **Pest framework** for modern PHP testing
- **Pest Plugin Drift** for detecting uncovered code and mutation testing
- Separate test suites for Unit and Feature tests
- PostgreSQL test database (`laravel_test`) for testing
- Coverage reporting available
- Test configuration in `src/phpunit.xml` and `src/tests/Pest.php`

### Development Workflow
1. Use `make setup-interactive` for initial setup
2. Run `make dev` for development environment
3. Use `make quality-all` before commits
4. Run `make test` to ensure tests pass
5. Use `make security-scan` for security checks

### Monitoring & Observability

#### Laravel (toujours actif)
- **Laravel Horizon** (v5.x) — queue monitoring dashboard (`/horizon`)
- **Laravel Telescope** (v5.x) — application debugging, désactivé en production
- **Laravel Pulse** (v1.x) — dashboard temps réel : exceptions, slow queries, jobs, cache (`/pulse`)
- **Laravel Nightwatch** (v1.x) — error monitoring externe (service payant, optionnel)
- **Spatie Laravel Health** (v1.x) — health checks: DB, Cache, Queue, Disk (`/health`)
- **Spatie Laravel Schedule Monitor** (v4.x) — monitoring des tâches cron

#### Via Docker Profiles
- Profil `dev` : Adminer (8080), Mailpit (8025)
- Profil `tools` : Dozzle (9999), IT-Tools (8081), Watchtower
- Profil `dev-extra` : PHPMyAdmin (8083), Redis Commander (8082)

### Deployment
- Docker-based deployment with health checks
- Automated updates via Watchtower
- Support for development, staging, and production environments

## Installed Packages & Features

### Laravel Core Packages
- **laravel/horizon** (^5.0) - Queue monitoring and management
- **laravel/telescope** (^5.0) - Application debugging and insights (désactivé en production)
- **laravel/sanctum** (^4.0) - API authentication
- **laravel/pulse** (^1.0) - Dashboard monitoring temps réel : exceptions, slow queries, jobs, cache
- **laravel/nightwatch** (^1.0) - Error monitoring externe (service payant, optionnel)

### Security & Monitoring Packages
- **spatie/laravel-csp** (^3.0) - Content Security Policy headers for XSS protection
- **spatie/laravel-health** (^1.0) - Application health checks (DB, Cache, Queue, Disk, etc.)
- **spatie/laravel-schedule-monitor** (^4.0) - Monitor scheduled tasks and cron jobs
- **spatie/laravel-permission** (^7.0) - Role and permission management (PHP ^8.4 + Laravel ^12)
- **spatie/laravel-activitylog** (^5.0) - Activity logging (PHP ^8.4 + Laravel ^12)

### Testing Packages
- **pestphp/pest** (^4.0) - Modern testing framework
- **pestphp/pest-plugin-laravel** (^4.0) - Laravel integration for Pest
- **pestphp/pest-plugin-drift** (^4.0) - Mutation testing, detect uncovered code

### Development Packages
- **fruitcake/laravel-debugbar** (^4.0) - Debug bar (ownership transférée de barryvdh/ en v4.0, namespace `Fruitcake\LaravelDebugbar`)
- **barryvdh/laravel-ide-helper** (^3.0) - IDE autocompletion (_ide_helper.php, models, meta)
- **laravel/boost** (^2.0) - AI-assisted development: MCP server + Laravel guidelines pour Claude Code / Cursor
- **nunomaduro/collision** (^8.0) - Better error output in console

### Quality Tools Packages
- **larastan/larastan** (^3.0) - PHPStan extension for Laravel (level 8)
- **symplify/easy-coding-standard** (^13.0) - PSR-12 code style enforcement
- **rector/rector** (^2.3) - Automated refactoring, PHP 8.5 + Laravel 12 rules
- **driftingly/rector-laravel** (^2.0) - Laravel-specific Rector rule sets
- **nunomaduro/phpinsights** (^2.14) - Code quality metrics (complexity, architecture, style)
- **php-code-archeology/php-code-archeology** (^2.0) - Architecture metrics + git churn analysis

## Security Patterns

### Jobs avec données sensibles — `ShouldBeEncrypted`
Tout job qui transporte des données sensibles (tokens, mots de passe, données personnelles) doit implémenter l'interface `ShouldBeEncrypted`. Cela chiffre le payload en queue (Redis/DB) et réduit le rayon d'impact si la queue est compromise.

```php
use Illuminate\Contracts\Queue\ShouldBeEncrypted;
use Illuminate\Contracts\Queue\ShouldQueue;

class SendPasswordResetEmail implements ShouldQueue, ShouldBeEncrypted
{
    public function __construct(private string $token) {}
}
```

### Fichier de divulgation de sécurité
Un fichier `public/.well-known/security.txt` est généré lors de l'installation. Personnalisez-le avec vos coordonnées réelles.

### TrustProxies en production
Si l'application est derrière un load balancer ou un proxy (Nginx, CloudFlare, AWS ALB), configurez `TrustProxies` dans `bootstrap/app.php` pour garantir que les URLs, redirects et cookies HTTPS fonctionnent correctement.

## Important Notes

- All Laravel code is in the `/src` directory
- Use `make` commands instead of direct Docker commands
- PHPStan is configured at level 8 for strict type checking
- Code must pass ECS, PHPStan, and tests before deployment
- Security scanning is integrated with Snyk
- Watchtower handles automatic updates for standard Docker images
- Custom images (PHP, Apache, Node) are excluded from auto-updates
- Database: PostgreSQL 17 for both development and testing (no SQLite)
- Queue: Redis for job processing, PostgreSQL for job batching and failed jobs

## PhpStorm + WSL2 Configuration

**⚠️ IMPORTANT**: If using PhpStorm on Windows with WSL2:

- Files may appear as "read-only" in PhpStorm even with correct Linux permissions
- **Quick Fix**: Run `./FIX-PHPSTORM-WSL.sh` and follow instructions
- **Full Guide**: See `WSL-PHPSTORM.md` for detailed solutions
- **Best Solution**: Use JetBrains Gateway / Remote Development for optimal experience

Required PhpStorm Settings:
1. Disable "Use safe write" in Settings > System Settings > Synchronization
2. Disable "Protect changes with read-only status" in Version Control > Confirmation
3. Right-click `src/` folder → Mark Directory as → Unmark as Read-Only