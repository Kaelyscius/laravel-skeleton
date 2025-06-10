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
	@echo "  $(GREEN)make setup-monitoring-auto$(NC) - Configurer le monitoring automatiquement"
	@echo "  $(GREEN)make quality-full$(NC)         - Audit complet de qualité"
	@echo "  $(GREEN)make dev$(NC)                  - Démarrer le développement"
	@echo "  $(GREEN)make monitoring$(NC)           - Ouvrir les outils de monitoring"
	@echo "  $(GREEN)make test-all$(NC)             - Tous les tests"

## 🚀 Installation et Build
.PHONY: install
install: build up install-laravel npm-install setup-ssl setup-monitoring-auto ## Installation complète du projet
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
	@echo "  • $(GREEN)make monitoring$(NC)           - Ouvrir tous les outils de monitoring"
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
Avoiquality: ecs phpstan ## Vérification de base de la qualité
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

.PHONY: setup-monitoring
setup-monitoring: ## Configurer les moniteurs Uptime Kuma (interactif)
	@echo "$(CYAN)⚙️ Setting up monitoring (interactive)...$(NC)"
	@if [ -f "./scripts/setup-monitoring.sh" ]; then \
		chmod +x "./scripts/setup-monitoring.sh" && \
		./scripts/setup-monitoring.sh; \
	else \
		echo "$(RED)❌ Script setup-monitoring.sh non trouvé$(NC)"; \
		echo "$(YELLOW)💡 Créez le fichier scripts/setup-monitoring.sh$(NC)"; \
		echo "$(BLUE)→ Ouvrez manuellement: http://localhost:3001$(NC)"; \
	fi

.PHONY: setup-monitoring-auto
setup-monitoring-auto: ## Configurer automatiquement les moniteurs Uptime Kuma
	@echo "$(CYAN)🤖 Setting up monitoring automatically...$(NC)"
	@if [ -f "./scripts/uptime-kuma-auto-config.sh" ]; then \
		chmod +x "./scripts/uptime-kuma-auto-config.sh" && \
		./scripts/uptime-kuma-auto-config.sh; \
	else \
		echo "$(RED)❌ Script uptime-kuma-auto-config.sh non trouvé$(NC)"; \
		echo "$(YELLOW)💡 Utilisation du script interactif...$(NC)"; \
		$(MAKE) setup-monitoring; \
	fi

.PHONY: import-monitoring-config
import-monitoring-config: ## Importer la configuration Uptime Kuma via Python
	@echo "$(PURPLE)📥 Importing Uptime Kuma configuration...$(NC)"
	@if [ -f "./scripts/import-uptime-kuma-config.py" ]; then \
		echo "$(YELLOW)→ Using Python script...$(NC)"; \
		python3 ./scripts/import-uptime-kuma-config.py; \
	elif [ -f "./scripts/simple-uptime-import.sh" ]; then \
		echo "$(YELLOW)→ Using simple bash script...$(NC)"; \
		chmod +x "./scripts/simple-uptime-import.sh" && \
		./scripts/simple-uptime-import.sh; \
	else \
		echo "$(RED)❌ Aucun script d'importation trouvé$(NC)"; \
		echo "$(YELLOW)💡 Exécutez d'abord: make setup-monitoring-auto$(NC)"; \
	fi

.PHONY: monitoring-config-status
monitoring-config-status: ## Vérifier la configuration du monitoring
	@echo "$(CYAN)📊 Monitoring configuration status...$(NC)"
	@echo "$(YELLOW)→ Configuration files:$(NC)"
	@if [ -f "./scripts/uptime-kuma-config.json" ]; then \
		echo "$(GREEN)  ✓ uptime-kuma-config.json$(NC)"; \
	else \
		echo "$(RED)  ✗ uptime-kuma-config.json$(NC)"; \
	fi
	@if [ -f "./scripts/import-uptime-kuma-config.py" ]; then \
		echo "$(GREEN)  ✓ import-uptime-kuma-config.py$(NC)"; \
	else \
		echo "$(RED)  ✗ import-uptime-kuma-config.py$(NC)"; \
	fi
	@if [ -f "./scripts/simple-uptime-import.sh" ]; then \
		echo "$(GREEN)  ✓ simple-uptime-import.sh$(NC)"; \
	else \
		echo "$(RED)  ✗ simple-uptime-import.sh$(NC)"; \
	fi
	@echo "$(YELLOW)→ Setup scripts:$(NC)"
	@if [ -f "./scripts/setup-monitoring.sh" ]; then \
		echo "$(GREEN)  ✓ setup-monitoring.sh$(NC)"; \
	else \
		echo "$(RED)  ✗ setup-monitoring.sh$(NC)"; \
	fi
	@if [ -f "./scripts/uptime-kuma-auto-config.sh" ]; then \
		echo "$(GREEN)  ✓ uptime-kuma-auto-config.sh$(NC)"; \
	else \
		echo "$(RED)  ✗ uptime-kuma-auto-config.sh$(NC)"; \
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

.PHONY: monitoring-status
monitoring-status: ## Vérifier le statut des outils de monitoring
	@echo "$(CYAN)📊 Monitoring services status...$(NC)"
	@echo "$(YELLOW)→ Uptime Kuma:$(NC)"
	@if docker ps --format "{{.Names}}" | grep -q "$(COMPOSE_PROJECT_NAME)_uptime-kuma"; then \
		echo "$(GREEN)  ✓ Running on http://localhost:3001$(NC)"; \
		if curl -s -f http://localhost:3001 > /dev/null 2>&1; then \
			echo "$(GREEN)  ✓ Service accessible$(NC)"; \
		else \
			echo "$(YELLOW)  ⚠ Container running but service not ready$(NC)"; \
		fi \
	else \
		echo "$(RED)  ✗ Not running$(NC)"; \
	fi
	@echo "$(YELLOW)→ Watchtower:$(NC)"
	@if docker ps --format "{{.Names}}" | grep -q "$(COMPOSE_PROJECT_NAME)_watchtower"; then \
		echo "$(GREEN)  ✓ Running (auto-updates enabled)$(NC)"; \
	else \
		echo "$(RED)  ✗ Not running$(NC)"; \
	fi
	@echo "$(YELLOW)→ Dozzle:$(NC)"
	@if docker ps --format "{{.Names}}" | grep -q "$(COMPOSE_PROJECT_NAME)_dozzle"; then \
		echo "$(GREEN)  ✓ Running on http://localhost:9999$(NC)"; \
	else \
		echo "$(RED)  ✗ Not running$(NC)"; \
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
	@rm -f ./scripts/uptime-kuma-config.json
	@rm -f ./scripts/import-uptime-kuma-config.py
	@rm -f ./scripts/simple-uptime-import.sh
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
		$(MAKE) monitoring-config-status; \
		echo ""; \
		echo "$(BLUE)=== Recherche globale de package.json ===$(NC)"; \
		docker exec $(NODE_CONTAINER_NAME) find /var/www -name "package.json" -type f 2>/dev/null || echo "Aucun package.json trouvé"; \
	else \
		echo "$(RED)✗ Container Node non disponible$(NC)"; \
	fi
	@echo ""
	@echo "$(PURPLE)💡 Commandes utiles après diagnostic:$(NC)"
	@echo "  • $(GREEN)make setup-monitoring-auto$(NC) - Configuration automatique du monitoring"
	@echo "  • $(GREEN)make install-laravel$(NC)       - Si Laravel manquant"
	@echo "  • $(GREEN)make npm-install$(NC)           - Si package.json manquant"
	@echo "  • $(GREEN)make monitoring$(NC)            - Ouvrir les outils de monitoring"

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