# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Docker Environment
- `make up` - Start all containers
- `make down` - Stop containers
- `make restart` - Restart containers
- `make build` - Build Docker images
- `make shell` - Access PHP container shell
- `make logs` - View container logs
- `make status` - Check container status

### Laravel Development
- `make install-laravel` - Install Laravel with dependencies
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
- `make test-coverage` - Run tests with coverage report

### Diagnostics & Troubleshooting
- `make diagnostic` - Run complete diagnostic suite (PHP 8.4 + Laravel 12)
- `make quick-check` - Quick test of Laravel + PHP 8.4 compatibility
- `make check-extensions` - Verify PHP 8.4 extensions installation
- `make test-packages` - Test package compatibility with Laravel 12
- `make fix-composer` - Fix Composer configuration and cache issues

### Code Quality
- `make ecs` - Check code style (Easy Coding Standard)
- `make ecs-fix` - Fix code style issues
- `make phpstan` - Run static analysis (PHPStan/Larastan level 8)
- `make rector` - Show refactoring suggestions
- `make rector-fix` - Apply refactoring suggestions
- `make insights` - Run PHP Insights analysis
- `make quality-all` - Run complete quality audit

### Security
- `make security-setup` - Setup Snyk security scanning
- `make security-scan` - Run security vulnerability scan
- `make nightwatch-start` - Start Laravel Nightwatch agent
- `make nightwatch-status` - Check Nightwatch status

### Deployment
- `make setup-interactive` - Interactive environment setup
- `make setup-dev` - Development environment setup
- `make setup-prod` - Production environment setup

## Project Architecture

### Docker-based Development Environment
- **PHP 8.4** container with FPM, Supervisor, and OPcache
- **Apache 2.4** with HTTPS/HTTP2 support
- **MariaDB** for database
- **Redis** for caching and sessions
- **Node.js 20** for frontend builds
- **Watchtower** for automatic container updates

### Laravel 12 Application Structure
- Main application code in `/src` directory
- Standard Laravel folder structure within `/src`
- Uses Pest for testing framework
- Configured with Laravel Horizon for queue management
- Laravel Telescope for debugging
- Laravel Sanctum for API authentication
- Laravel Nightwatch for monitoring

### Quality Tools Configuration
- **PHPStan/Larastan** at level 8 for strict type checking
- **ECS** (Easy Coding Standard) for PSR-12 compliance
- **Rector** for automated refactoring and PHP modernization
- **PHP Insights** for code quality analysis
- **Snyk** for security vulnerability scanning

### Key Configuration Files
- `src/composer.json` - PHP dependencies and scripts
- `src/package.json` - Node.js dependencies
- `src/phpstan.neon` - PHPStan configuration (level 8)
- `src/ecs.php` - Code style configuration
- `src/rector.php` - Refactoring rules
- `src/vite.config.js` - Frontend build configuration
- `docker-compose.yml` - Docker services configuration
- `Makefile` - Development commands

### Environment Management
- Multiple environment configurations via interactive setup
- Ansible playbooks for production deployment
- Docker compose overrides for dev/prod environments
- Automated SSL certificate generation

### Testing Setup
- Pest framework for modern PHP testing
- Separate test suites for Unit and Feature tests
- SQLite in-memory database for testing
- Coverage reporting available

### Development Workflow
1. Use `make setup-interactive` for initial setup
2. Run `make dev` for development environment
3. Use `make quality-all` before commits
4. Run `make test` to ensure tests pass
5. Use `make security-scan` for security checks

### Monitoring & Observability
- Dozzle for real-time log monitoring (port 9999)
- Adminer for database management (port 8080)
- MailHog for email testing (port 8025)
- IT-Tools for development utilities (port 8081)
- Laravel Horizon for queue monitoring
- Laravel Telescope for application debugging

### Deployment
- Ansible playbooks for infrastructure management
- Docker-based deployment with health checks
- Automated updates via Watchtower
- Support for development, staging, and production environments

## Important Notes

- All Laravel code is in the `/src` directory
- Use `make` commands instead of direct Docker commands
- PHPStan is configured at level 8 for strict type checking
- Code must pass ECS, PHPStan, and tests before deployment
- Security scanning is integrated with Snyk
- Watchtower handles automatic updates for standard Docker images
- Custom images (PHP, Apache, Node) are excluded from auto-updates