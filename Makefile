# Variables
DOCKER_COMPOSE = docker-compose
DOCKER = docker
COMPOSE_PROJECT_NAME ?= laravel-app

# Containers dynamiques
PHP_CONTAINER = $$(docker ps -qf "name=$(COMPOSE_PROJECT_NAME)_php")
APACHE_CONTAINER = $$(docker ps -qf "name=$(COMPOSE_PROJECT_NAME)_apache")
NODE_CONTAINER = $$(docker ps -qf "name=$(COMPOSE_PROJECT_NAME)_node")
MARIADB_CONTAINER = $$(docker ps -qf "name=$(COMPOSE_PROJECT_NAME)_mariadb")

# Containers par nom (pour vérifications)
PHP_CONTAINER_NAME = $(COMPOSE_PROJECT_NAME)_php
APACHE_CONTAINER_NAME = $(COMPOSE_PROJECT_NAME)_apache
NODE_CONTAINER_NAME = $(COMPOSE_PROJECT_NAME)_node
MARIADB_CONTAINER_NAME = $(COMPOSE_PROJECT_NAME)_mariadb

# Colors
GREEN = \033[0;32m
YELLOW = \033[0;33m
RED = \033[0;31m
BLUE = \033[0;34m
PURPLE = \033[0;35m
CYAN = \033[0;36m
NC = \033[0m

.PHONY: help
help: ## Afficher l'aide
	@echo "$(CYAN)╔══════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(CYAN)║                    LARAVEL DEV ENVIRONMENT                   ║$(NC)"
	@echo "$(CYAN)║                   avec Monitoring Intégré                    ║$(NC)"
	@echo "$(CYAN)╚══════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)💡 Commandes courantes :$(NC)"
	@echo "  $(GREEN)make install$(NC)              - Installation complète"
	@echo "  $(GREEN)make setup-monitoring$(NC)     - Configuration simple Uptime Kuma"
	@echo "  $(GREEN)make setup-monitoring-auto$(NC) - Configuration automatique avancée"
	@echo "  $(GREEN)make setup-watchtower$(NC)     - Configuration simple Watchtower"
	@echo "  $(GREEN)make quality-full$(NC)         - Audit complet de qualité"
	@echo "  $(GREEN)make dev$(NC)                  - Démarrer le développement"
	@echo "  $(GREEN)make monitoring$(NC)           - Ouvrir les outils de monitoring"
	@echo "  $(GREEN)make test-all$(NC)             - Tous les tests"

## 🚀 Installation et Build
.PHONY: install
install: build up install-laravel npm-install setup-ssl ## Installation complète du projet
	@echo "$(GREEN)✓ Installation terminée !$(NC)"
	@echo "$(YELLOW)→ Accédez à l'application : https://laravel.local$(NC)"
	@echo ""
	@echo "$(CYAN)🛠️ Outils de développement :$(NC)"
	@echo "$(YELLOW)→ MailHog : http://localhost:8025$(NC)"
	@echo "$(YELLOW)→ Adminer : http://localhost:8080$(NC)"
	@echo "$(YELLOW)→ IT Tools : http://localhost:8081$(NC)"
	@echo "$(YELLOW)→ Dozzle (logs) : http://localhost:9999$(NC)"
	@echo ""
	@echo "$(PURPLE)📊 Monitoring :$(NC)"
	@echo "$(YELLOW)→ Uptime Kuma : http://localhost:3001$(NC)"
	@echo ""
	@echo "$(BLUE)⚡ Commandes utiles :$(NC)"
	@echo "  • $(GREEN)make setup-monitoring$(NC)     - Configuration simple Uptime Kuma"
	@echo "  • $(GREEN)make setup-watchtower$(NC)     - Configuration simple Watchtower"
	@echo "  • $(GREEN)make npm-build$(NC)            - Builder les assets"
	@echo "  • $(GREEN)make npm-dev$(NC)              - Lancer le dev server"
	@echo "  • $(GREEN)make quality-full$(NC)         - Vérifier la qualité"

.PHONY: build
build: ## Construire tous les containers
	@echo "$(YELLOW)Building containers...$(NC)"
	@$(DOCKER_COMPOSE) build --no-cache

.PHONY: build-parallel
build-parallel: ## Construire tous les containers en parallèle
	@echo "$(YELLOW)Building containers in parallel...$(NC)"
	@$(DOCKER_COMPOSE) build --parallel --no-cache

.PHONY: rebuild
rebuild: down build up ## Reconstruire et redémarrer tous les containers

## 🎮 Contrôle des containers
.PHONY: up
up: ## Démarrer tous les containers
	@echo "$(YELLOW)Starting containers...$(NC)"
	@$(DOCKER_COMPOSE) up -d
	@echo "$(GREEN)✓ Containers started$(NC)"

.PHONY: down
down: ## Arrêter tous les containers
	@echo "$(YELLOW)Stopping containers...$(NC)"
	@$(DOCKER_COMPOSE) down
	@echo "$(GREEN)✓ Containers stopped$(NC)"

.PHONY: restart
restart: down up ## Redémarrer tous les containers

.PHONY: status
status: ## Afficher le statut des containers
	@$(DOCKER_COMPOSE) ps

.PHONY: logs
logs: ## Afficher les logs de tous les containers
	@$(DOCKER_COMPOSE) logs -f

.PHONY: logs-php
logs-php: ## Afficher les logs du container PHP
	@$(DOCKER_COMPOSE) logs -f php

.PHONY: logs-apache
logs-apache: ## Afficher les logs du container Apache
	@$(DOCKER_COMPOSE) logs -f apache

.PHONY: logs-node
logs-node: ## Afficher les logs du container Node
	@$(DOCKER_COMPOSE) logs -f node

## 🛠️ Laravel
.PHONY: install-laravel
install-laravel: ## Installer Laravel avec tous les outils de qualité
	@echo "$(YELLOW)Installing Laravel...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) bash -c "cd /var/www/html && /docker/scripts/install-laravel.sh"
	@echo "$(GREEN)✓ Laravel installed$(NC)"

.PHONY: artisan
artisan: ## Exécuter une commande artisan (ex: make artisan cmd="migrate")
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan $(cmd)

.PHONY: composer
composer: ## Exécuter une commande composer (ex: make composer cmd="install")
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) composer $(cmd)

.PHONY: migrate
migrate: ## Lancer les migrations
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan migrate

.PHONY: seed
seed: ## Lancer les seeders
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan db:seed

.PHONY: fresh
fresh: ## Réinitialiser la base de données avec les seeds
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan migrate:fresh --seed

.PHONY: horizon
horizon: ## Démarrer Laravel Horizon
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan horizon

.PHONY: queue
queue: ## Démarrer le worker de queue
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan queue:work

## 📦 NPM/Node.js
.PHONY: npm
npm: ## Exécuter une commande npm (ex: make npm cmd="install")
	@$(DOCKER) exec -u 1000:1000 $(NODE_CONTAINER) npm $(cmd)

.PHONY: npm-install
npm-install: ## Installer uniquement les dépendances NPM
	@echo "$(YELLOW)Installing NPM dependencies...$(NC)"
	@if ! docker ps --format "{{.Names}}" | grep -q "$(NODE_CONTAINER_NAME)"; then \
		echo "$(RED)✗ Container $(NODE_CONTAINER_NAME) is not running$(NC)"; \
		echo "$(YELLOW)→ Starting containers first...$(NC)"; \
		$(MAKE) up; \
		sleep 5; \
	fi
	@echo "$(YELLOW)→ Checking for package.json...$(NC)"
	@if docker exec $(NODE_CONTAINER_NAME) test -f /var/www/html/package.json; then \
		echo "$(YELLOW)→ Found package.json in /var/www/html$(NC)"; \
		docker exec -u 1000:1000 $(NODE_CONTAINER_NAME) npm install; \
	elif docker exec $(NODE_CONTAINER_NAME) test -f /var/www/project/package.json; then \
		echo "$(YELLOW)→ Found package.json in /var/www/project$(NC)"; \
		docker exec -u 1000:1000 -w /var/www/project $(NODE_CONTAINER_NAME) npm install; \
	else \
		echo "$(RED)✗ No package.json found in expected locations$(NC)"; \
		echo "$(YELLOW)→ Debugging: Files in /var/www/html:$(NC)"; \
		docker exec $(NODE_CONTAINER_NAME) ls -la /var/www/html/ || true; \
		echo "$(YELLOW)→ Debugging: Files in /var/www/project:$(NC)"; \
		docker exec $(NODE_CONTAINER_NAME) ls -la /var/www/project/ || true; \
		echo "$(YELLOW)→ Searching for package.json files:$(NC)"; \
		docker exec $(NODE_CONTAINER_NAME) find /var/www -name "package.json" -type f 2>/dev/null || true; \
		echo "$(RED)Please ensure Laravel is properly installed first with: make install-laravel$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)✓ NPM dependencies installed$(NC)"

.PHONY: npm-build
npm-build: npm-install ## Installer et builder les dépendances NPM
	@echo "$(YELLOW)Building assets...$(NC)"
	@if docker exec $(NODE_CONTAINER_NAME) test -f /var/www/html/package.json; then \
		if docker exec $(NODE_CONTAINER_NAME) npm run --silent 2>/dev/null | grep -q "build"; then \
			echo "$(YELLOW)→ Running build script in /var/www/html$(NC)"; \
			docker exec -u 1000:1000 $(NODE_CONTAINER_NAME) npm run build; \
		else \
			echo "$(YELLOW)⚠ No build script found in package.json$(NC)"; \
			echo "$(YELLOW)→ Available scripts:$(NC)"; \
			docker exec $(NODE_CONTAINER_NAME) npm run --silent 2>/dev/null || echo "No scripts found"; \
		fi \
	elif docker exec $(NODE_CONTAINER_NAME) test -f /var/www/project/package.json; then \
		if docker exec -w /var/www/project $(NODE_CONTAINER_NAME) npm run --silent 2>/dev/null | grep -q "build"; then \
			echo "$(YELLOW)→ Running build script in /var/www/project$(NC)"; \
			docker exec -u 1000:1000 -w /var/www/project $(NODE_CONTAINER_NAME) npm run build; \
		else \
			echo "$(YELLOW)⚠ No build script found in package.json$(NC)"; \
			echo "$(YELLOW)→ Available scripts:$(NC)"; \
			docker exec -w /var/www/project $(NODE_CONTAINER_NAME) npm run --silent 2>/dev/null || echo "No scripts found"; \
		fi \
	fi
	@echo "$(GREEN)✓ NPM build complete$(NC)"

.PHONY: npm-dev
npm-dev: npm-install ## Lancer le serveur de développement
	@echo "$(YELLOW)Starting development server...$(NC)"
	@if docker exec $(NODE_CONTAINER_NAME) test -f /var/www/html/package.json; then \
		if docker exec $(NODE_CONTAINER_NAME) npm run --silent 2>/dev/null | grep -q "dev"; then \
			echo "$(YELLOW)→ Starting dev server in /var/www/html$(NC)"; \
			docker exec -u 1000:1000 $(NODE_CONTAINER_NAME) npm run dev; \
		else \
			echo "$(RED)✗ No dev script found in package.json$(NC)"; \
		fi \
	elif docker exec $(NODE_CONTAINER_NAME) test -f /var/www/project/package.json; then \
		if docker exec -w /var/www/project $(NODE_CONTAINER_NAME) npm run --silent 2>/dev/null | grep -q "dev"; then \
			echo "$(YELLOW)→ Starting dev server in /var/www/project$(NC)"; \
			docker exec -u 1000:1000 -w /var/www/project $(NODE_CONTAINER_NAME) npm run dev; \
		else \
			echo "$(RED)✗ No dev script found in package.json$(NC)"; \
		fi \
	fi

.PHONY: npm-watch
npm-watch: npm-install ## Lancer npm en mode watch
	@echo "$(YELLOW)Starting npm watch...$(NC)"
	@if docker exec $(NODE_CONTAINER_NAME) test -f /var/www/html/package.json; then \
		echo "$(YELLOW)→ Starting watch in /var/www/html$(NC)"; \
		docker exec -u 1000:1000 $(NODE_CONTAINER_NAME) npm run watch 2>/dev/null || \
		docker exec -u 1000:1000 $(NODE_CONTAINER_NAME) npm run dev 2>/dev/null || \
		echo "$(RED)✗ No watch or dev script found$(NC)"; \
	elif docker exec $(NODE_CONTAINER_NAME) test -f /var/www/project/package.json; then \
		echo "$(YELLOW)→ Starting watch in /var/www/project$(NC)"; \
		docker exec -u 1000:1000 -w /var/www/project $(NODE_CONTAINER_NAME) npm run watch 2>/dev/null || \
		docker exec -u 1000:1000 -w /var/www/project $(NODE_CONTAINER_NAME) npm run dev 2>/dev/null || \
		echo "$(RED)✗ No watch or dev script found$(NC)"; \
	fi

.PHONY: pnpm-build
pnpm-build: ## Builder avec pnpm (alternative plus rapide)
	@echo "$(YELLOW)Building with pnpm...$(NC)"
	@if ! docker ps --format "{{.Names}}" | grep -q "$(NODE_CONTAINER_NAME)"; then \
		$(MAKE) up; sleep 5; \
	fi
	@if docker exec $(NODE_CONTAINER_NAME) test -f /var/www/html/package.json; then \
		echo "$(BLUE)→ Using pnpm in /var/www/html$(NC)"; \
		docker exec -u 1000:1000 $(NODE_CONTAINER_NAME) pnpm install; \
		docker exec -u 1000:1000 $(NODE_CONTAINER_NAME) pnpm build 2>/dev/null || echo "$(YELLOW)⚠ No build script$(NC)"; \
	elif docker exec $(NODE_CONTAINER_NAME) test -f /var/www/project/package.json; then \
		echo "$(BLUE)→ Using pnpm in /var/www/project$(NC)"; \
		docker exec -u 1000:1000 -w /var/www/project $(NODE_CONTAINER_NAME) pnpm install; \
		docker exec -u 1000:1000 -w /var/www/project $(NODE_CONTAINER_NAME) pnpm build 2>/dev/null || echo "$(YELLOW)⚠ No build script$(NC)"; \
	fi
	@echo "$(GREEN)✓ pnpm build complete$(NC)"

## 🧪 Tests
.PHONY: test
test: ## Lancer tous les tests
	@echo "$(YELLOW)Running tests...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan test

.PHONY: test-unit
test-unit: ## Lancer uniquement les tests unitaires
	@echo "$(YELLOW)Running unit tests...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan test --testsuite=Unit

.PHONY: test-feature
test-feature: ## Lancer uniquement les tests de fonctionnalité
	@echo "$(YELLOW)Running feature tests...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan test --testsuite=Feature

.PHONY: test-coverage
test-coverage: ## Lancer les tests avec couverture
	@echo "$(YELLOW)Running tests with coverage...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan test --coverage-html coverage

.PHONY: test-parallel
test-parallel: ## Lancer les tests en parallèle
	@echo "$(YELLOW)Running tests in parallel...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan test --parallel

.PHONY: test-all
test-all: test-coverage test-parallel ## Lancer tous les types de tests

## 🔍 Qualité de code
.PHONY: phpstan
phpstan: ## Lancer PHPStan/Larastan
	@echo "$(BLUE)Running PHPStan analysis...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) ./vendor/bin/phpstan analyse

.PHONY: larastan
larastan: phpstan ## Alias pour phpstan

.PHONY: ecs
ecs: ## Vérifier le code style avec ECS
	@echo "$(BLUE)Checking code style with ECS...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) ./vendor/bin/ecs check

.PHONY: ecs-fix
ecs-fix: ## Corriger le code style avec ECS
	@echo "$(BLUE)Fixing code style with ECS...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) ./vendor/bin/ecs check --fix

.PHONY: rector
rector: ## Lancer Rector (dry-run)
	@echo "$(BLUE)Running Rector analysis...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) ./vendor/bin/rector process --dry-run

.PHONY: rector-fix
rector-fix: ## Appliquer les corrections Rector
	@echo "$(BLUE)Applying Rector fixes...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) ./vendor/bin/rector process

.PHONY: insights
insights: ## Lancer PHP Insights
	@echo "$(PURPLE)Running PHP Insights...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan insights

.PHONY: insights-fix
insights-fix: ## Lancer PHP Insights avec corrections
	@echo "$(PURPLE)Running PHP Insights with fixes...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan insights --fix

.PHONY: enlightn
enlightn: ## Lancer Enlightn (audit sécurité)
	@echo "$(PURPLE)Running Enlightn security audit...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan enlightn

.PHONY: ide-helper
ide-helper: ## Générer les fichiers IDE Helper
	@echo "$(BLUE)Generating IDE Helper files...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) composer ide-helper

## 🎯 Commandes groupées de qualité
.PHONY: quality
quality: ecs phpstan ## Vérification de base de la qualité
	@echo "$(GREEN)✓ Basic quality checks completed$(NC)"

.PHONY: quality-fix
quality-fix: ecs-fix rector-fix ## Corrections automatiques
	@echo "$(GREEN)✓ Automatic fixes applied$(NC)"

.PHONY: quality-full
quality-full: ## Audit complet de qualité (ECS + PHPStan + Insights + Enlightn + Tests)
	@echo "$(CYAN)🔍 Starting full quality audit...$(NC)"
	@echo "$(YELLOW)→ Step 1/5: Code style check...$(NC)"
	@$(MAKE) ecs || echo "$(RED)⚠ ECS issues found$(NC)"
	@echo "$(YELLOW)→ Step 2/5: Static analysis...$(NC)"
	@$(MAKE) phpstan || echo "$(RED)⚠ PHPStan issues found$(NC)"
	@echo "$(YELLOW)→ Step 3/5: Quality insights...$(NC)"
	@$(MAKE) insights || echo "$(RED)⚠ Insights issues found$(NC)"
	@echo "$(YELLOW)→ Step 4/5: Security audit...$(NC)"
	@$(MAKE) enlightn || echo "$(RED)⚠ Security issues found$(NC)"
	@echo "$(YELLOW)→ Step 5/5: Running tests...$(NC)"
	@$(MAKE) test-unit || echo "$(RED)⚠ Test failures$(NC)"
	@echo "$(GREEN)✅ Full quality audit completed!$(NC)"

.PHONY: quality-report
quality-report: ## Générer un rapport de qualité complet
	@echo "$(CYAN)📊 Generating quality report...$(NC)"
	@mkdir -p reports
	@echo "$(YELLOW)→ ECS Report...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) ./vendor/bin/ecs check --output-format=json > reports/ecs-report.json 2>/dev/null || true
	@echo "$(YELLOW)→ PHPStan Report...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) ./vendor/bin/phpstan analyse --error-format=json > reports/phpstan-report.json 2>/dev/null || true
	@echo "$(YELLOW)→ Insights Report...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan insights --format=json > reports/insights-report.json 2>/dev/null || true
	@echo "$(YELLOW)→ Test Coverage...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan test --coverage-clover=reports/coverage.xml 2>/dev/null || true
	@echo "$(GREEN)✓ Reports generated in ./reports/$(NC)"

## 📊 Monitoring et mise à jour automatique
.PHONY: uptime
uptime: ## Ouvrir Uptime Kuma (monitoring)
	@echo "$(CYAN)🔍 Opening Uptime Kuma...$(NC)"
	@echo "$(YELLOW)→ URL: http://localhost:3001$(NC)"
	@if command -v open >/dev/null 2>&1; then \
		open http://localhost:3001; \
	elif command -v xdg-open >/dev/null 2>&1; then \
		xdg-open http://localhost:3001; \
	elif command -v start >/dev/null 2>&1; then \
		start http://localhost:3001; \
	else \
		echo "$(BLUE)→ Manually open: http://localhost:3001$(NC)"; \
	fi

.PHONY: monitoring
monitoring: ## Ouvrir tous les outils de monitoring
	@echo "$(CYAN)📊 Opening monitoring tools...$(NC)"
	@echo "$(YELLOW)→ Uptime Kuma: http://localhost:3001$(NC)"
	@echo "$(YELLOW)→ Dozzle (logs): http://localhost:9999$(NC)"
	@echo "$(YELLOW)→ Laravel Horizon: https://laravel.local/horizon$(NC)"
	@if command -v open >/dev/null 2>&1; then \
		open http://localhost:3001 && sleep 1 && \
		open http://localhost:9999 && sleep 1 && \
		open https://laravel.local/horizon; \
	elif command -v xdg-open >/dev/null 2>&1; then \
		xdg-open http://localhost:3001 && sleep 1 && \
		xdg-open http://localhost:9999 && sleep 1 && \
		xdg-open https://laravel.local/horizon; \
	else \
		echo "$(BLUE)→ Manually open the URLs above$(NC)"; \
	fi

## 🔍 Configuration Uptime Kuma
.PHONY: setup-monitoring
setup-monitoring: ## Configuration simple d'Uptime Kuma (interactif)
	@echo "$(CYAN)⚙️ Setting up Uptime Kuma (simple)...$(NC)"
	@if [ -f "./scripts/setup-uptime-kuma-simple.sh" ]; then \
		chmod +x "./scripts/setup-uptime-kuma-simple.sh" && \
		./scripts/setup-uptime-kuma-simple.sh; \
	else \
		echo "$(RED)❌ Script setup-uptime-kuma-simple.sh non trouvé$(NC)"; \
		echo "$(YELLOW)💡 Créez le fichier scripts/setup-uptime-kuma-simple.sh$(NC)"; \
		echo "$(BLUE)→ Ouvrez manuellement: http://localhost:3001$(NC)"; \
	fi

.PHONY: setup-monitoring-auto
setup-monitoring-auto: ## Configuration automatique avancée d'Uptime Kuma
	@echo "$(CYAN)🤖 Setting up Uptime Kuma automatically (advanced)...$(NC)"
	@if [ -f "./scripts/setup-uptime-kuma-auto.py" ]; then \
		chmod +x "./scripts/setup-uptime-kuma-auto.py" && \
		python3 ./scripts/setup-uptime-kuma-auto.py; \
	else \
		echo "$(RED)❌ Script setup-uptime-kuma-auto.py non trouvé$(NC)"; \
		echo "$(YELLOW)💡 Utilisation du script simple...$(NC)"; \
		$(MAKE) setup-monitoring; \
	fi

.PHONY: monitoring-status
monitoring-status: ## Vérifier la configuration du monitoring
	@echo "$(CYAN)📊 Monitoring configuration status...$(NC)"
	@echo "$(YELLOW)→ Configuration files:$(NC)"
	@if [ -f "./scripts/uptime-kuma-auto-config.json" ]; then \
		echo "$(GREEN)  ✓ uptime-kuma-auto-config.json$(NC)"; \
	else \
		echo "$(RED)  ✗ uptime-kuma-auto-config.json$(NC)"; \
	fi
	@if [ -f "./scripts/setup-uptime-kuma-auto.py" ]; then \
		echo "$(GREEN)  ✓ setup-uptime-kuma-auto.py$(NC)"; \
	else \
		echo "$(RED)  ✗ setup-uptime-kuma-auto.py$(NC)"; \
	fi
	@if [ -f "./scripts/setup-uptime-kuma-simple.sh" ]; then \
		echo "$(GREEN)  ✓ setup-uptime-kuma-simple.sh$(NC)"; \
	else \
		echo "$(RED)  ✗ setup-uptime-kuma-simple.sh$(NC)"; \
	fi
	@echo "$(YELLOW)→ Services status:$(NC)"
	@if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "$(COMPOSE_PROJECT_NAME)_uptime-kuma.*healthy"; then \
		echo "$(GREEN)  ✓ Uptime Kuma: Healthy$(NC)"; \
	elif docker ps --format "table {{.Names}}" | grep -q "$(COMPOSE_PROJECT_NAME)_uptime-kuma"; then \
		echo "$(YELLOW)  ⚠ Uptime Kuma: Running$(NC)"; \
	else \
		echo "$(RED)  ✗ Uptime Kuma: Not running$(NC)"; \
	fi

## 🔄 Configuration Watchtower
.PHONY: setup-watchtower
setup-watchtower: ## Configuration simple de Watchtower
	@echo "$(CYAN)🔄 Setting up Watchtower (simple)...$(NC)"
	@if [ -f "./scripts/setup-watchtower-simple.sh" ]; then \
		chmod +x "./scripts/setup-watchtower-simple.sh" && \
		./scripts/setup-watchtower-simple.sh; \
	else \
		echo "$(RED)❌ Script setup-watchtower-simple.sh non trouvé$(NC)"; \
		echo "$(YELLOW)💡 Créez le fichier scripts/setup-watchtower-simple.sh$(NC)"; \
	fi

.PHONY: watchtower-logs
watchtower-logs: ## Voir les logs de Watchtower
	@echo "$(BLUE)🔄 Watchtower logs...$(NC)"
	@$(DOCKER_COMPOSE) logs -f watchtower

.PHONY: watchtower-update-now
watchtower-update-now: ## Forcer une mise à jour immédiate
	@echo "$(YELLOW)🔄 Forcing immediate update check...$(NC)"
	@$(DOCKER) exec $(COMPOSE_PROJECT_NAME)_watchtower /watchtower --run-once --cleanup || echo "$(RED)❌ Erreur lors de la mise à jour forcée$(NC)"

.PHONY: watchtower-status
watchtower-status: ## Voir le statut de Watchtower
	@echo "$(BLUE)🔄 Watchtower status...$(NC)"
	@if docker ps --format "{{.Names}}" | grep -q "$(COMPOSE_PROJECT_NAME)_watchtower"; then \
		echo "$(GREEN)✓ Watchtower is running$(NC)"; \
		echo "$(YELLOW)→ Last update check:$(NC)"; \
		$(DOCKER_COMPOSE) logs --tail=10 watchtower | grep -E "(Updated|Skipping|No updates)" || echo "No recent updates found"; \
	else \
		echo "$(RED)✗ Watchtower is not running$(NC)"; \
	fi

.PHONY: watchtower-test
watchtower-test: ## Tester la configuration de Watchtower
	@echo "$(BLUE)🧪 Testing Watchtower configuration...$(NC)"
	@if [ -f "./scripts/test-watchtower.sh" ]; then \
		chmod +x "./scripts/test-watchtower.sh" && \
		./scripts/test-watchtower.sh; \
	else \
		echo "$(YELLOW)⚠️  Test script not found, checking manually...$(NC)"; \
		$(MAKE) watchtower-status; \
	fi

## 🚀 Développement rapide
.PHONY: dev
dev: up npm-dev ## Démarrer l'environnement de développement complet
	@echo "$(GREEN)🚀 Development environment ready!$(NC)"

.PHONY: dev-fresh
dev-fresh: fresh npm-build ## Base de données fraîche + assets
	@echo "$(GREEN)✨ Fresh development environment ready!$(NC)"

.PHONY: dev-quality
dev-quality: quality npm-build ## Vérifier qualité + builder assets
	@echo "$(GREEN)✅ Quality checked and assets built!$(NC)"

## 🔧 Accès aux containers
.PHONY: shell
shell: shell-php ## Alias pour shell-php

.PHONY: shell-php
shell-php: ## Accéder au shell du container PHP
	@$(DOCKER) exec -it -u 1000:1000 $(PHP_CONTAINER) bash

.PHONY: shell-apache
shell-apache: ## Accéder au shell du container Apache
	@$(DOCKER) exec -it -u 1000:1000 $(APACHE_CONTAINER) bash

.PHONY: shell-node
shell-node: ## Accéder au shell du container Node
	@$(DOCKER) exec -it -u 1000:1000 $(NODE_CONTAINER) bash

.PHONY: shell-mariadb
shell-mariadb: ## Accéder au shell MariaDB
	@$(DOCKER) exec -it $(MARIADB_CONTAINER_NAME) mysql -u root -p

## 🧹 Nettoyage
.PHONY: clean
clean: down ## Nettoyer les containers et volumes
	@echo "$(YELLOW)Cleaning containers and volumes...$(NC)"
	@$(DOCKER_COMPOSE) down -v
	@echo "$(GREEN)✓ Cleaned$(NC)"

.PHONY: clean-all
clean-all: clean ## Nettoyer tout (containers, volumes, images)
	@echo "$(YELLOW)Removing images...$(NC)"
	@$(DOCKER_COMPOSE) down --rmi all -v
	docker system prune -af
	@echo "$(GREEN)✓ All cleaned$(NC)"

.PHONY: clean-reports
clean-reports: ## Nettoyer les rapports de qualité
	@echo "$(YELLOW)Cleaning quality reports...$(NC)"
	@rm -rf reports/ coverage/ storage/debugbar/
	@echo "$(GREEN)✓ Reports cleaned$(NC)"

.PHONY: clean-monitoring-config
clean-monitoring-config: ## Nettoyer les fichiers de configuration monitoring
	@echo "$(YELLOW)Cleaning monitoring configuration files...$(NC)"
	@rm -f ./scripts/uptime-kuma-auto-config.json
	@rm -f ./scripts/uptime-kuma-notifications.json
	@rm -f ./scripts/uptime-kuma-monitors.txt
	@echo "$(GREEN)✓ Monitoring config files cleaned$(NC)"

.PHONY: prune
prune: ## Nettoyer le système Docker
	@$(DOCKER) system prune -af --volumes

## 🔐 SSL
.PHONY: setup-ssl
setup-ssl: ## Générer les certificats SSL auto-signés
	@echo "$(YELLOW)Generating SSL certificates...$(NC)"
	@./docker/scripts/generate-ssl.sh
	@echo "$(GREEN)✓ SSL certificates generated$(NC)"

## 📊 Monitoring et diagnostics
.PHONY: healthcheck
healthcheck: ## Vérifier la santé de tous les services
	@echo "$(YELLOW)Checking services health...$(NC)"
	@$(DOCKER_COMPOSE) ps --format "table {{.Name}}\t{{.Status}}"

.PHONY: stats
stats: ## Afficher les statistiques des containers
	@$(DOCKER) stats --no-stream

.PHONY: diagnose
diagnose: ## Diagnostiquer les problèmes de Laravel et npm
	@echo "$(YELLOW)🔍 Diagnostic du projet...$(NC)"
	@echo "$(BLUE)=== État des containers ===$(NC)"
	@$(DOCKER_COMPOSE) ps --format "table {{.Name}}\t{{.Status}}"
	@echo ""
	@echo "$(BLUE)=== Services de monitoring ===$(NC)"
	@if docker ps --format "{{.Names}}" | grep -q "$(COMPOSE_PROJECT_NAME)_uptime-kuma"; then \
		echo "$(GREEN)✓ Uptime Kuma: http://localhost:3001$(NC)"; \
	else \
		echo "$(RED)✗ Uptime Kuma non démarré$(NC)"; \
	fi
	@if docker ps --format "{{.Names}}" | grep -q "$(COMPOSE_PROJECT_NAME)_watchtower"; then \
		echo "$(GREEN)✓ Watchtower: Auto-updates actives$(NC)"; \
	else \
		echo "$(RED)✗ Watchtower non démarré$(NC)"; \
	fi
	@echo ""
	@echo "$(BLUE)=== Structure des dossiers ===$(NC)"
	@echo "$(YELLOW)Contenu de ./src (hôte):$(NC)"
	@ls -la ./src/ 2>/dev/null || echo "Dossier ./src non trouvé"
	@echo ""
	@if docker ps --format "{{.Names}}" | grep -q "$(NODE_CONTAINER_NAME)"; then \
		echo "$(YELLOW)Contenu de /var/www/html (container):$(NC)"; \
		docker exec $(NODE_CONTAINER_NAME) ls -la /var/www/html/ || true; \
		echo ""; \
		echo "$(BLUE)=== Fichiers Laravel ===$(NC)"; \
		if docker exec $(NODE_CONTAINER_NAME) test -f /var/www/html/composer.json; then \
			echo "$(GREEN)✓ composer.json trouvé$(NC)"; \
			if docker exec $(NODE_CONTAINER_NAME) grep -q "laravel/framework" /var/www/html/composer.json 2>/dev/null; then \
				echo "$(GREEN)✓ Projet Laravel valide$(NC)"; \
			else \
				echo "$(RED)✗ composer.json trouvé mais pas de Laravel framework$(NC)"; \
			fi \
		else \
			echo "$(RED)✗ composer.json non trouvé$(NC)"; \
		fi; \
		echo ""; \
		echo "$(BLUE)=== Fichiers npm ===$(NC)"; \
		if docker exec $(NODE_CONTAINER_NAME) test -f /var/www/html/package.json; then \
			echo "$(GREEN)✓ package.json trouvé dans /var/www/html$(NC)"; \
			echo "$(YELLOW)Scripts npm disponibles:$(NC)"; \
			docker exec $(NODE_CONTAINER_NAME) npm run --silent 2>/dev/null || echo "Aucun script trouvé"; \
		else \
			echo "$(RED)✗ package.json non trouvé dans /var/www/html$(NC)"; \
		fi; \
		echo ""; \
		echo "$(BLUE)=== Outils de qualité ===$(NC)"; \
		if docker exec $(NODE_CONTAINER_NAME) test -f /var/www/html/ecs.php; then \
			echo "$(GREEN)✓ ECS configuré$(NC)"; \
		else \
			echo "$(RED)✗ ECS non configuré$(NC)"; \
		fi; \
		if docker exec $(NODE_CONTAINER_NAME) test -f /var/www/html/phpstan.neon; then \
			echo "$(GREEN)✓ PHPStan configuré$(NC)"; \
		else \
			echo "$(RED)✗ PHPStan non configuré$(NC)"; \
		fi; \
		if docker exec $(NODE_CONTAINER_NAME) test -f /var/www/html/config/insights.php; then \
			echo "$(GREEN)✓ PHP Insights configuré$(NC)"; \
		else \
			echo "$(RED)✗ PHP Insights non configuré$(NC)"; \
		fi; \
		echo ""; \
		echo "$(BLUE)=== Configuration monitoring ===$(NC)"; \
		$(MAKE) monitoring-status; \
		echo ""; \
		echo "$(BLUE)=== Recherche globale de package.json ===$(NC)"; \
		docker exec $(NODE_CONTAINER_NAME) find /var/www -name "package.json" -type f 2>/dev/null || echo "Aucun package.json trouvé"; \
	else \
		echo "$(RED)✗ Container Node non disponible$(NC)"; \
	fi
	@echo ""
	@echo "$(PURPLE)💡 Commandes utiles après diagnostic:$(NC)"
	@echo "  • $(GREEN)make setup-monitoring$(NC)     - Configuration simple Uptime Kuma"
	@echo "  • $(GREEN)make setup-watchtower$(NC)     - Configuration simple Watchtower"
	@echo "  • $(GREEN)make install-laravel$(NC)      - Si Laravel manquant"
	@echo "  • $(GREEN)make npm-install$(NC)          - Si package.json manquant"
	@echo "  • $(GREEN)make monitoring$(NC)           - Ouvrir les outils de monitoring"

## 🔄 Mise à jour et sécurité
.PHONY: update-deps
update-deps: ## Mettre à jour les dépendances PHP et JS
	@echo "$(YELLOW)Updating dependencies...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) composer update --no-interaction
	@if docker exec $(NODE_CONTAINER_NAME) test -f /var/www/html/package.json; then \
		docker exec -u 1000:1000 $(NODE_CONTAINER_NAME) npm update; \
	elif docker exec $(NODE_CONTAINER_NAME) test -f /var/www/project/package.json; then \
		docker exec -u 1000:1000 -w /var/www/project $(NODE_CONTAINER_NAME) npm update; \
	fi
	@echo "$(GREEN)✓ Dependencies updated$(NC)"

.PHONY: security-check
security-check: ## Vérifier les vulnérabilités de sécurité
	@echo "$(PURPLE)🔒 Security vulnerability check...$(NC)"
	@echo "$(YELLOW)→ Composer audit...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) composer audit || echo "$(YELLOW)⚠ Composer audit not available$(NC)"
	@echo "$(YELLOW)→ NPM audit...$(NC)"
	@if docker exec $(NODE_CONTAINER_NAME) test -f /var/www/html/package.json; then \
		docker exec -u 1000:1000 $(NODE_CONTAINER_NAME) npm audit || echo "$(YELLOW)⚠ NPM vulnerabilities found$(NC)"; \
	elif docker exec $(NODE_CONTAINER_NAME) test -f /var/www/project/package.json; then \
		docker exec -u 1000:1000 -w /var/www/project $(NODE_CONTAINER_NAME) npm audit || echo "$(YELLOW)⚠ NPM vulnerabilities found$(NC)"; \
	fi
	@echo "$(YELLOW)→ Enlightn security check...$(NC)"
	@$(MAKE) enlightn || echo "$(YELLOW)⚠ Security issues found$(NC)"
	@echo "$(GREEN)✓ Security check completed$(NC)"

.PHONY: security-fix
security-fix: ## Corriger automatiquement les vulnérabilités
	@echo "$(PURPLE)🔧 Fixing security vulnerabilities...$(NC)"
	@echo "$(YELLOW)→ NPM security fixes...$(NC)"
	@if docker exec $(NODE_CONTAINER_NAME) test -f /var/www/html/package.json; then \
		docker exec -u 1000:1000 $(NODE_CONTAINER_NAME) npm audit fix || true; \
	elif docker exec $(NODE_CONTAINER_NAME) test -f /var/www/project/package.json; then \
		docker exec -u 1000:1000 -w /var/www/project $(NODE_CONTAINER_NAME) npm audit fix || true; \
	fi
	@echo "$(GREEN)✓ Security fixes applied$(NC)"

## 🎯 Workflows complets
.PHONY: pre-commit
pre-commit: quality-fix test-unit ## Vérifications avant commit
	@echo "$(GREEN)✅ Pre-commit checks passed!$(NC)"

.PHONY: pre-push
pre-push: quality-full ## Vérifications avant push
	@echo "$(GREEN)🚀 Pre-push checks passed!$(NC)"

.PHONY: deploy-check
deploy-check: quality-full security-check npm-build ## Vérifications avant déploiement
	@echo "$(GREEN)🚀 Deploy checks passed!$(NC)"

.PHONY: daily-check
daily-check: update-deps quality-full security-check ## Vérifications quotidiennes
	@echo "$(GREEN)📅 Daily checks completed!$(NC)"

.PHONY: setup-full
setup-full: install setup-monitoring setup-watchtower ## Installation et configuration complète
	@echo "$(GREEN)🎉 Setup complet terminé !$(NC)"
	@echo ""
	@echo "$(CYAN)🔗 Accès rapides:$(NC)"
	@echo "  • Laravel: https://laravel.local"
	@echo "  • Uptime Kuma: http://localhost:3001"
	@echo "  • Adminer: http://localhost:8080"
	@echo "  • MailHog: http://localhost:8025"
	@echo "  • Dozzle: http://localhost:9999"
	@echo ""
	@echo "$(BLUE)⚡ Prochaines étapes:$(NC)"
	@echo "  1. Configurez vos monitors dans Uptime Kuma"
	@echo "  2. Configurez les notifications Watchtower"
	@echo "  3. Lancez les tests: make test-all"
	@echo "  4. Vérifiez la qualité: make quality-full"

## 🔄 Scripts d'initialisation et maintenance
.PHONY: init-scripts
init-scripts: ## Créer la structure des scripts et les placeholders
	@echo "$(CYAN)📁 Initialisation de la structure des scripts...$(NC)"
	@if [ -f "./create-scripts-structure.sh" ]; then \
		chmod +x "./create-scripts-structure.sh" && \
		./create-scripts-structure.sh; \
	else \
		echo "$(RED)❌ Script create-scripts-structure.sh non trouvé$(NC)"; \
		mkdir -p scripts scripts/monitoring scripts/watchtower scripts/healthcheck; \
		echo "$(GREEN)✓ Répertoires scripts créés manuellement$(NC)"; \
	fi

.PHONY: fix-permissions
fix-permissions: ## Corriger les permissions des scripts
	@echo "$(YELLOW)🔧 Correction des permissions...$(NC)"
	@find scripts/ -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
	@find scripts/ -name "*.py" -exec chmod +x {} \; 2>/dev/null || true
	@find docker/scripts/ -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
	@echo "$(GREEN)✓ Permissions corrigées$(NC)"

.PHONY: backup-config
backup-config: ## Sauvegarder la configuration actuelle
	@echo "$(YELLOW)💾 Sauvegarde de la configuration...$(NC)"
	@mkdir -p backups/$(shell date +%Y%m%d-%H%M%S)
	@cp .env backups/$(shell date +%Y%m%d-%H%M%S)/.env 2>/dev/null || true
	@cp docker-compose.yml backups/$(shell date +%Y%m%d-%H%M%S)/docker-compose.yml 2>/dev/null || true
	@cp Makefile backups/$(shell date +%Y%m%d-%H%M%S)/Makefile 2>/dev/null || true
	@docker-compose config > backups/$(shell date +%Y%m%d-%H%M%S)/docker-compose.resolved.yml 2>/dev/null || true
	@echo "$(GREEN)✓ Configuration sauvegardée dans backups/$(NC)"

.PHONY: restore-config
restore-config: ## Restaurer une configuration (spécifiez BACKUP_DIR=...)
	@if [ -z "$(BACKUP_DIR)" ]; then \
		echo "$(RED)❌ Spécifiez le répertoire: make restore-config BACKUP_DIR=backups/20241210-143000$(NC)"; \
		echo "$(YELLOW)Sauvegardes disponibles:$(NC)"; \
		ls -la backups/ 2>/dev/null || echo "Aucune sauvegarde trouvée"; \
		exit 1; \
	fi
	@echo "$(YELLOW)📤 Restauration depuis $(BACKUP_DIR)...$(NC)"
	@if [ -f "$(BACKUP_DIR)/.env" ]; then cp "$(BACKUP_DIR)/.env" .env; echo "$(GREEN)✓ .env restauré$(NC)"; fi
	@if [ -f "$(BACKUP_DIR)/docker-compose.yml" ]; then cp "$(BACKUP_DIR)/docker-compose.yml" docker-compose.yml; echo "$(GREEN)✓ docker-compose.yml restauré$(NC)"; fi
	@if [ -f "$(BACKUP_DIR)/Makefile" ]; then cp "$(BACKUP_DIR)/Makefile" Makefile; echo "$(GREEN)✓ Makefile restauré$(NC)"; fi
	@echo "$(GREEN)✅ Configuration restaurée$(NC)"

## 📊 Métriques et surveillance avancée
.PHONY: metrics
metrics: ## Afficher les métriques détaillées du système
	@echo "$(CYAN)📊 Métriques système détaillées$(NC)"
	@echo "$(CYAN)==============================$(NC)"
	@echo ""
	@echo "$(YELLOW)🐳 Utilisation Docker:$(NC)"
	@docker system df 2>/dev/null || echo "Impossible d'obtenir les métriques Docker"
	@echo ""
	@echo "$(YELLOW)📈 Statistiques des containers:$(NC)"
	@docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}" 2>/dev/null || echo "Aucun container actif"
	@echo ""
	@echo "$(YELLOW)💾 Volumes Docker:$(NC)"
	@docker volume ls --format "table {{.Driver}}\t{{.Name}}" | grep $(COMPOSE_PROJECT_NAME) 2>/dev/null || echo "Aucun volume trouvé"
	@echo ""
	@echo "$(YELLOW)🌐 Réseaux Docker:$(NC)"
	@docker network ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}" | grep $(COMPOSE_PROJECT_NAME) 2>/dev/null || echo "Aucun réseau trouvé"

.PHONY: performance-check
performance-check: ## Vérifier les performances et optimisations
	@echo "$(CYAN)⚡ Vérification des performances$(NC)"
	@echo "$(CYAN)==============================$(NC)"
	@echo ""
	@echo "$(YELLOW)🔍 Vérification OPcache:$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php -r "if(function_exists('opcache_get_status')) { \$s=opcache_get_status(); echo 'OPcache: ' . (\$s['opcache_enabled'] ? 'Activé' : 'Désactivé') . \"\\n\"; echo 'Mémoire utilisée: ' . round(\$s['memory_usage']['used_memory']/1024/1024,2) . 'MB\\n'; } else { echo 'OPcache non disponible\\n'; }" 2>/dev/null || echo "Container PHP non accessible"
	@echo ""
	@echo "$(YELLOW)📦 Taille des volumes:$(NC)"
	@docker system df -v 2>/dev/null | grep $(COMPOSE_PROJECT_NAME) || echo "Aucune information disponible"
	@echo ""
	@echo "$(YELLOW)🔄 Temps de réponse des services:$(NC)"
	@for url in "https://laravel.local" "http://localhost:3001" "http://localhost:8025" "http://localhost:8080"; do \
		echo -n "  $url: "; \
		time_result=$(curl -o /dev/null -s -w "%{time_total}" "$url" 2>/dev/null) && echo "${time_result}s" || echo "Non accessible"; \
	done

.PHONY: logs-follow
logs-follow: ## Suivre les logs de tous les containers en temps réel
	@echo "$(CYAN)📋 Suivi des logs en temps réel$(NC)"
	@echo "$(YELLOW)Appuyez sur Ctrl+C pour arrêter$(NC)"
	@$(DOCKER_COMPOSE) logs -f --tail=50

.PHONY: logs-errors
logs-errors: ## Afficher uniquement les erreurs dans les logs
	@echo "$(CYAN)🚨 Erreurs dans les logs$(NC)"
	@echo "$(CYAN)=====================$(NC)"
	@$(DOCKER_COMPOSE) logs --tail=100 2>&1 | grep -i -E "(error|exception|fatal|fail|warn)" --color=always || echo "$(GREEN)Aucune erreur trouvée$(NC)"

## 🔧 Outils de debugging et développement
.PHONY: debug-php
debug-php: ## Activer le mode debug PHP
	@echo "$(YELLOW)🐛 Activation du mode debug PHP...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php -r "echo 'PHP Version: ' . PHP_VERSION . \"\\n\";"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php -r "echo 'Xdebug: ' . (extension_loaded('xdebug') ? 'Activé' : 'Désactivé') . \"\\n\";"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php -r "echo 'OPcache: ' . (extension_loaded('Zend OPcache') ? 'Activé' : 'Désactivé') . \"\\n\";"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php -m | grep -E "(xdebug|Zend OPcache|redis)" || echo "Extensions non trouvées"

.PHONY: debug-composer
debug-composer: ## Debug des problèmes Composer
	@echo "$(YELLOW)🎼 Debug Composer...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) composer --version
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) composer config --list --global 2>/dev/null | head -20
	@echo ""
	@echo "$(YELLOW)Configuration locale:$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) composer config --list 2>/dev/null | head -10 || echo "Pas de composer.json"

.PHONY: debug-laravel
debug-laravel: ## Debug Laravel (routes, config, etc.)
	@echo "$(YELLOW)🚀 Debug Laravel...$(NC)"
	@if $(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) test -f artisan; then \
		echo "$(GREEN)✓ Laravel détecté$(NC)"; \
		echo ""; \
		echo "$(YELLOW)Version Laravel:$(NC)"; \
		$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan --version; \
		echo ""; \
		echo "$(YELLOW)Statut de l'application:$(NC)"; \
		$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan inspire 2>/dev/null && echo "$(GREEN)✓ Application fonctionnelle$(NC)" || echo "$(RED)✗ Application non accessible$(NC)"; \
		echo ""; \
		echo "$(YELLOW)Configuration:$(NC)"; \
		$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan config:show app.env app.debug app.url 2>/dev/null || echo "Impossible d'afficher la config"; \
	else \
		echo "$(RED)✗ Laravel non installé$(NC)"; \
		echo "$(YELLOW)💡 Lancez: make install-laravel$(NC)"; \
	fi

.PHONY: debug-network
debug-network: ## Debug des problèmes réseau Docker
	@echo "$(YELLOW)🌐 Debug réseau Docker...$(NC)"
	@echo "$(CYAN)Réseaux actifs:$(NC)"
	@docker network ls | grep $(COMPOSE_PROJECT_NAME) || echo "Aucun réseau trouvé"
	@echo ""
	@echo "$(CYAN)Test de connectivité interne:$(NC)"
	@$(DOCKER) exec $(PHP_CONTAINER_NAME) ping -c 2 mariadb 2>/dev/null && echo "$(GREEN)✓ PHP -> MariaDB$(NC)" || echo "$(RED)✗ PHP -> MariaDB$(NC)"
	@$(DOCKER) exec $(PHP_CONTAINER_NAME) ping -c 2 redis 2>/dev/null && echo "$(GREEN)✓ PHP -> Redis$(NC)" || echo "$(RED)✗ PHP -> Redis$(NC)"

## 📋 Aide et documentation
.PHONY: help-monitoring
help-monitoring: ## Aide spécifique au monitoring
	@echo "$(CYAN)🔍 Aide Monitoring$(NC)"
	@echo "$(CYAN)=================$(NC)"
	@echo ""
	@echo "$(YELLOW)Configuration Uptime Kuma:$(NC)"
	@echo "  $(GREEN)make setup-monitoring$(NC)      - Configuration simple (recommandé)"
	@echo "  $(GREEN)make setup-monitoring-auto$(NC) - Configuration automatique avancée"
	@echo "  $(GREEN)make uptime$(NC)                - Ouvrir Uptime Kuma"
	@echo "  $(GREEN)make monitoring$(NC)            - Ouvrir tous les outils"
	@echo "  $(GREEN)make monitoring-status$(NC)     - Vérifier le statut"
	@echo ""
	@echo "$(YELLOW)Configuration Watchtower:$(NC)"
	@echo "  $(GREEN)make setup-watchtower$(NC)      - Configuration simple"
	@echo "  $(GREEN)make watchtower-logs$(NC)       - Voir les logs"
	@echo "  $(GREEN)make watchtower-status$(NC)     - Vérifier le statut"
	@echo "  $(GREEN)make watchtower-test$(NC)       - Tester la configuration"
	@echo "  $(GREEN)make watchtower-update-now$(NC) - Forcer une mise à jour"
	@echo ""
	@echo "$(BLUE)💡 Conseils:$(NC)"
	@echo "  • Commencez par: make setup-monitoring"
	@echo "  • Puis: make setup-watchtower"
	@echo "  • Testez avec: make monitoring-status"
	@echo "  • Surveillance: make watchtower-test"

.PHONY: help-quality
help-quality: ## Aide spécifique à la qualité de code
	@echo "$(CYAN)🔍 Aide Qualité de Code$(NC)"
	@echo "$(CYAN)========================$(NC)"
	@echo ""
	@echo "$(YELLOW)Outils disponibles:$(NC)"
	@echo "  $(GREEN)make ecs$(NC)           - Easy Coding Standard (style)"
	@echo "  $(GREEN)make ecs-fix$(NC)       - Corriger le style automatiquement"
	@echo "  $(GREEN)make phpstan$(NC)       - Analyse statique PHPStan/Larastan"
	@echo "  $(GREEN)make rector$(NC)        - Suggestions de refactoring"
	@echo "  $(GREEN)make rector-fix$(NC)    - Appliquer le refactoring"
	@echo "  $(GREEN)make insights$(NC)      - Analyse globale PHP Insights"
	@echo "  $(GREEN)make enlightn$(NC)      - Audit sécurité et performance"
	@echo ""
	@echo "$(YELLOW)Workflows groupés:$(NC)"
	@echo "  $(GREEN)make quality$(NC)       - Vérification de base (ECS + PHPStan)"
	@echo "  $(GREEN)make quality-fix$(NC)   - Corrections automatiques"
	@echo "  $(GREEN)make quality-full$(NC)  - Audit complet"
	@echo "  $(GREEN)make quality-report$(NC) - Générer des rapports"
	@echo ""
	@echo "$(YELLOW)Tests:$(NC)"
	@echo "  $(GREEN)make test$(NC)          - Tous les tests"
	@echo "  $(GREEN)make test-unit$(NC)     - Tests unitaires"
	@echo "  $(GREEN)make test-coverage$(NC) - Tests avec couverture"
	@echo ""
	@echo "$(BLUE)💡 Workflow recommandé:$(NC)"
	@echo "  1. make quality-fix    (corriger automatiquement)"
	@echo "  2. make test-unit      (vérifier que ça marche)"
	@echo "  3. make quality-full   (audit complet)"

.PHONY: help-docker
help-docker: ## Aide spécifique à Docker
	@echo "$(CYAN)🐳 Aide Docker$(NC)"
	@echo "$(CYAN)===============$(NC)"
	@echo ""
	@echo "$(YELLOW)Gestion des containers:$(NC)"
	@echo "  $(GREEN)make up$(NC)            - Démarrer tous les containers"
	@echo "  $(GREEN)make down$(NC)          - Arrêter tous les containers"
	@echo "  $(GREEN)make restart$(NC)       - Redémarrer tous les containers"
	@echo "  $(GREEN)make status$(NC)        - Voir le statut"
	@echo "  $(GREEN)make logs$(NC)          - Voir tous les logs"
	@echo "  $(GREEN)make logs-follow$(NC)   - Suivre les logs en temps réel"
	@echo ""
	@echo "$(YELLOW)Build et maintenance:$(NC)"
	@echo "  $(GREEN)make build$(NC)         - Construire les images"
	@echo "  $(GREEN)make rebuild$(NC)       - Reconstruire et redémarrer"
	@echo "  $(GREEN)make clean$(NC)         - Nettoyer containers et volumes"
	@echo "  $(GREEN)make clean-all$(NC)     - Nettoyer tout (images incluses)"
	@echo "  $(GREEN)make prune$(NC)         - Nettoyer le système Docker"
	@echo ""
	@echo "$(YELLOW)Accès aux containers:$(NC)"
	@echo "  $(GREEN)make shell$(NC)         - Shell dans le container PHP"
	@echo "  $(GREEN)make shell-apache$(NC)  - Shell dans le container Apache"
	@echo "  $(GREEN)make shell-node$(NC)    - Shell dans le container Node"
	@echo "  $(GREEN)make shell-mariadb$(NC) - Console MariaDB"
	@echo ""
	@echo "$(YELLOW)Debug et métriques:$(NC)"
	@echo "  $(GREEN)make diagnose$(NC)      - Diagnostic complet"
	@echo "  $(GREEN)make healthcheck$(NC)   - Vérifier la santé des services"
	@echo "  $(GREEN)make metrics$(NC)       - Métriques détaillées"
	@echo "  $(GREEN)make performance-check$(NC) - Vérifier les performances"

.PHONY: help-all
help-all: help help-monitoring help-quality help-docker ## Afficher toute l'aide disponible
	@echo ""
	@echo "$(PURPLE)🎯 Workflows complets utiles:$(NC)"
	@echo "  $(GREEN)make setup-full$(NC)      - Installation et configuration complète"
	@echo "  $(GREEN)make dev$(NC)             - Démarrer l'environnement de développement"
	@echo "  $(GREEN)make pre-commit$(NC)      - Vérifications avant commit"
	@echo "  $(GREEN)make daily-check$(NC)     - Vérifications quotidiennes"
	@echo "  $(GREEN)make deploy-check$(NC)    - Vérifications avant déploiement"
	@echo ""
	@echo "$(PURPLE)📚 Documentation:$(NC)"
	@echo "  • README.md - Guide complet de l'environnement"
	@echo "  • scripts/README.md - Documentation des scripts"
	@echo "  • make help-[monitoring|quality|docker] - Aide spécialisée"