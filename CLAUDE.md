# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Guidelines Laravel (générées — Laravel Boost)

@src/CLAUDE.md

> ⚠️ **Cette ligne n'est pas décorative, et elle est verrouillée par un test.**
> `src/CLAUDE.md` est **généré** par `php artisan boost:update` et contient les
> conventions Laravel/PHP/Pest/Livewire tenues à jour par les mainteneurs. Sans
> cet import, il serait versionné, à jour… et **jamais lu** : une session
> ouverte à la racine du dépôt ne charge que *ce* fichier-ci.
>
> `src/tests/Unit/BoostGuidelinesTest.php` verrouille deux invariants, **tous
> deux observés rouges le 2026-08-09 avant correction** : (1) l'import ci-dessus
> existe ; (2) **tout import `@chemin` d'un fichier de consignes résout sur
> disque** — parce que `laravel/boost` 2.5.3 y avait injecté, sans revue, une
> consigne impérative pointant vers un `.ai/rules` inexistant.
>
> 🔁 **`boost:update` ne tourne PLUS automatiquement** (retiré de
> `post-update-cmd` le 2026-08-09) : un outil ne modifie pas un fichier
> versionné en marge d'un `composer update`. Il se lance explicitement, par
> `make boost-update`, et son diff se relit comme n'importe quel autre.

## Development Commands

### Docker Environment - Architecture Modulaire

**🎯 Architecture avec Profiles Docker** : Ce projet utilise une architecture modulaire basée sur les Docker Compose Profiles permettant de démarrer uniquement les services nécessaires selon l'environnement. Voir [DOCKER-ARCHITECTURE.md](./DOCKER-ARCHITECTURE.md) pour la documentation complète.

#### Démarrage par environnement
- `make up-local` - **Développement local complet** (recommandé) - Services essentiels + dev + tools
- `make up-dev` - Développement - Services essentiels + outils dev (node, mailpit, adminer)
- `make up-dev-full` - Développement complet - Tous les services + monitoring (dozzle, it-tools, watchtower)
- `make up-dev-extra` - Développement + outils extra (redis-commander)
- `make up-prod` - Production - Services essentiels uniquement (apache, php, postgres, redis)
- `make up-tools` - Démarrer uniquement les outils de monitoring (dozzle, it-tools, watchtower)

#### Profiles disponibles
- **Aucun profile** (Production) : apache, php, postgres, postgres-pulse, redis
- **dev** (Développement) : node, mailpit, adminer
- **tools** (Utilitaires) : dozzle, it-tools, watchtower
- **dev-extra** (Outils additionnels) : redis-commander

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
- `make install-laravel DRY_RUN=true` - **Simulation** : rien n'est installé, aucune sentinelle
  écrite, aucun `chown`/`chmod` appliqué. Les étapes 2/5 à 5/5 de la recette (permissions
  container, `fix-permissions-host` en sudo, MCP) sont **sautées** — elles mutent l'arbre, elles
  ne le simulent pas. Le module `10-laravel-core` est le seul *dry-run aware* : il tourne
  réellement et annonce chaque commande à effet en `[DRY] …`. Les autres sont annoncés puis
  sautés, et leur contenu n'est **pas** décrit (voir `DRY_RUN_AWARE_MODULES` dans
  `scripts/install.sh`).
  ⚠️ **Le plan est réparti sur STDOUT et STDERR** — mesuré : l'orchestrateur journalise sur
  stderr, mais `execute_module` lance le module *aware* en `2>&1 | tee`, ce qui replie SA sortie
  dans le stdout. La seule capture complète prend donc les **deux** :
  `make install-laravel DRY_RUN=true > plan.txt 2>&1` (ou `2>&1 | tee plan.txt`). Ni
  `> plan.txt` ni `2> plan.txt` seuls ne suffisent. Le plan est aussi dans
  `/tmp/laravel-install-*.log`.
  ⛔ `DRY_RUN=true` est **refusé** sur les chaînes composites (`install`, `install-dev`,
  `install-dev-full`, `install-prod`, les variantes `-fast`, `install-incremental`) : elles
  bâtissent des images et démarrent des conteneurs avant d'atteindre `install.sh`.
  Toute valeur autre que `true`/`false` est refusée bruyamment (`DRY_RUN=1` lancerait sinon une
  installation réelle en silence).
- `make install-laravel RESUME_FROM=<module>` - Reprendre à partir d'un module. La valeur est
  validée contre `INSTALL_MODULES` lu dans `scripts/install.sh`. ⚠️ **`--resume-from` ne FORCE
  rien** : il saute ce qui précède, l'état sur disque décide toujours en aval — seul `--force`
  rejoue un module déjà franchi. Refusé sur `install-laravel-prod` (qui enchaîne cinq `--only`).
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
- `make test-drift` - ⛔ **DESTRUCTIF, et mal nommé** : `pest --drift` est le *migrateur PHPUnit → Pest*, pas un outil d'analyse. Il **réécrit `tests/` sur place**. Ce dépôt est déjà entièrement en Pest, donc la commande n'a plus d'objet ; elle affiche désormais un avertissement et n'exécute rien (`make test-drift-force` pour forcer). Pour éprouver un garde-fou, la méthode du projet est la **campagne de mutation manuelle** (`docs/process/03-boucle-qualite.md` §Étape 5)

### Diagnostics & Troubleshooting
- `make diagnostic` - Run complete diagnostic suite (PHP 8.5 + Laravel 13)
- `make quick-check` - Quick test of Laravel + PHP 8.5 compatibility
- `make check-extensions` - Verify PHP 8.5 extensions installation
- `make test-packages` - Test package compatibility with Laravel 13
- `make fix-composer` - Fix Composer configuration and cache issues
- `make check-compatibility` - Check if incompatible packages became Laravel 13 compatible
- `make update-packages` - Auto-install packages that became Laravel 13 compatible
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

### Application Modular Architecture (ADR-0009)

**Architecture modulaire `app/Modules/*` PSR-4 hand-rolled** — décision LOCKED party-mode (ADR-0009). Pas de `nwidart/laravel-modules`, pas de DDD/hexagonal, pas de repositories systématiques.

#### Arborescence cible

```
src/app/
├── Core/                          # Cœur transversal, toujours actif
│   ├── Models/Streamer.php
│   ├── Concerns/BelongsToStreamer.php
│   ├── Scopes/BelongsToStreamerScope.php
│   ├── Http/Middleware/SetCurrentStreamer.php
│   ├── Providers/CoreServiceProvider.php
│   └── Support/CurrentStreamer.php
│
└── Modules/                       # Modules métier activables via ENV
    ├── Public/                    # Homepage, About, SEO, sitemap
    ├── Live/                      # Twitch embed + chat + status
    ├── Reviews/                   # CRUD articles + comments dormant
    ├── PressKit/                  # Page presse + bio FR+EN
    └── Admin/                     # Filament panels + Sanctum + Permissions
```

#### Namespaces PSR-4 (déclarés dans `src/composer.json`)

| Namespace | Path |
|---|---|
| `App\Core\` | `app/Core/` |
| `App\Modules\Public\` | `app/Modules/Public/` |
| `App\Modules\Live\` | `app/Modules/Live/` |
| `App\Modules\Reviews\` | `app/Modules/Reviews/` |
| `App\Modules\PressKit\` | `app/Modules/PressKit/` |
| `App\Modules\Admin\` | `app/Modules/Admin/` |

Le namespace Laravel natif `App\\` → `app/` reste pour les controllers/models génériques (compatibilité Laravel standard).

#### Conventions interdites (refus explicites)

- ❌ `nwidart/laravel-modules` — magic inutile, PSR-4 natif suffit
- ❌ Repositories systématiques — Eloquent EST le repository
- ❌ Façades custom par module
- ❌ Event bus inter-modules J1 (YAGNI v1)
- ❌ CQRS / Command Bus
- ❌ Hexagonal / Ports & Adapters / DDD vocabulaire
- ❌ DTOs systématiques (Form Requests + Resources Eloquent suffisent)
- ❌ `app/Domain/`, `app/UseCases/`, `app/Application/`
- ❌ Mix migrations modules dans `database/migrations/` racine — chaque module aura son propre dossier `Database/migrations/`
- ❌ Discovery automatique Filament resources — registration explicite par module

#### Couplage cross-modules

Un module **ne peut pas** importer un autre module directement (sauf via `App\Core\`). Cette règle sera enforcée en CI par un test Pest scan `use` statements (Story 1.6 à venir). En attendant : convention humaine + review PR.

#### Activation conditionnelle des modules

Modules activables au déploiement via variables d'environnement `MODULE_<NAME>_ENABLED=true|false` + `config/modules.php` + bootstrap conditionnel dans `AppServiceProvider::register()` (Story 1.7 à venir).

→ Un fork-streamer peut désactiver `MODULE_REVIEWS_ENABLED=false` sans toucher au code (philosophie Plausible-style — ADR-0001).

#### Smoke test (Story 1.1)

`src/tests/Unit/PsrAutoloadTest.php` vérifie que les 6 namespaces sont correctement déclarés dans `composer.json` ET que les 6 dossiers existent sur disque. **DOIT passer** avant toute story module-spécifique.

#### Références

- ADR-0009 : `docs/adr/ADR-0009-modular-app-modules-psr4.md`
- ADR-0001 (Plausible-style, refus WordPress runtime) : `docs/adr/ADR-0001-modularity-plausible-style.md`
- Architecture applicative §3.1 : `docs/architecture/3-architecture-applicative.md#31-arborescence-cible`

---

### Docker-based Modular Architecture

**Architecture modulaire avec Docker Compose Profiles** permettant de démarrer uniquement les services nécessaires selon l'environnement.

#### Services essentiels (toujours actifs, aucun profile)
- **PHP 8.5** container with FPM, Supervisor, and OPcache
- **Apache 2.4** with HTTPS/HTTP2 support
- **PostgreSQL** for database
- **PostgreSQL 18 (postgres-pulse)** dedicated container for Pulse monitoring (ADR-0004)
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
- **Redis Commander** for Redis management (port 8082)

#### Commandes recommandées
- **Développement local** : `make up-local` (tous les outils)
- **Production** : `make up-prod` (services essentiels uniquement)
- **Documentation complète** : Voir [DOCKER-ARCHITECTURE.md](./DOCKER-ARCHITECTURE.md)

### Laravel 13 Application Structure

**Stack effective (source de vérité — vérifiée le 2026-07-27)** : PHP 8.5 · Laravel 13 ·
PostgreSQL 18 · Livewire 4 · Tailwind 4 (CSS-first) · Pest 4 · Vite 8 · Filament v5 *(à
installer en Story 1.10)*. Le verrou historique « Laravel 12 + Filament v3 » du PRD est levé —
voir [ADR-0010](docs/adr/ADR-0010-laravel-13-supersedes-filament-v3-lock.md).

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
- **Rector** (v2.x) for automated refactoring — rules PHP 8.5 + Laravel 13
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
- **Pest Plugin Drift** — migrateur PHPUnit → Pest (⛔ *pas* de la couverture ni de la mutation : la description précédente était fausse, corrigée le 2026-08-09 après qu'un appel a réécrit 7 fichiers de tests)
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
- Profil `dev-extra` : Redis Commander (8082)

### Deployment
- Docker-based deployment with health checks
- Automated updates via Watchtower
- Support for development, staging, and production environments

## Installed Packages & Features

### Admin Panel
- **filament/filament** (^5) - Panel d'administration `/admin`. Le `PanelProvider` vit sous `App\Modules\Admin\Providers\Filament\` et **non** dans `bootstrap/providers.php`, pour que `MODULE_ADMIN_ENABLED=false` l'éteigne réellement (ADR-0009). Accès refusé par défaut : `User::canAccessPanel()` exige le rôle `super-admin`. Le rôle est semé par `RoleSeeder` ; l'administrateur, lui, se crée avec **`make filament-user`** — aucun compte n'est semé. ⚠️ Pas `make artisan cmd="make:filament-user"` : la recette `artisan` n'alloue ni stdin ni TTY, donc une commande interactive y meurt (relevé en revue le 2026-08-20). La version en prose ne fige plus de numéro de patch : `composer.json` déclare `^5` et `AdminPanelDependenciesTest` gèle ce littéral — trois granularités dont deux n'étaient gardées par rien.

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
- **spatie/laravel-permission** (^8) - Role and permission management. ⚠️ La contrainte réelle est `^8` (8.3.0 installée) ; `epics.md` prescrivait `^7.0`, ce qui aurait **rétrogradé** le paquet — gardé par `src/tests/Unit/AdminPanelDependenciesTest.php`
- **spatie/laravel-activitylog** (^5.0) - Activity logging (PHP ^8.4 + Laravel ^12)

### Testing Packages
- **pestphp/pest** (^4.0) - Modern testing framework
- **pestphp/pest-plugin-laravel** (^4.0) - Laravel integration for Pest
- **pestphp/pest-plugin-drift** (^4.0) - Migration PHPUnit → Pest, **destructive et à usage unique**. Ne fait ni mutation testing ni détection de couverture — la mention précédente était erronée (constaté Story 1.10a)

### Development Packages
- **fruitcake/laravel-debugbar** (^4.0) - Debug bar (ownership transférée de barryvdh/ en v4.0, namespace `Fruitcake\LaravelDebugbar`)
- **barryvdh/laravel-ide-helper** (^3.0) - IDE autocompletion (_ide_helper.php, models, meta)
- **laravel/boost** (^2.0) - AI-assisted development: MCP server + Laravel guidelines pour Claude Code / Cursor
- **nunomaduro/collision** (^8.0) - Better error output in console

### Quality Tools Packages
- **larastan/larastan** (^3.0) - PHPStan extension for Laravel (level 8)
- **symplify/easy-coding-standard** (^13.0) - PSR-12 code style enforcement
- **rector/rector** (^2.3) - Automated refactoring, PHP 8.5 + Laravel 13 rules
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
- Database: PostgreSQL 18 for both development and testing (no SQLite) — voir ADR-0007 (amendé 2026-07-27)
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