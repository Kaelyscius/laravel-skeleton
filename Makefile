# =============================================================================
# LARAVEL DEV ENVIRONMENT - Makefile Optimisé
# =============================================================================

# Variables
DOCKER_COMPOSE = docker-compose
DOCKER = docker
COMPOSE_PROJECT_NAME ?= laravel-app

# Containers dynamiques
PHP_CONTAINER = $$(docker ps -qf "name=$(COMPOSE_PROJECT_NAME)_php")
APACHE_CONTAINER = $$(docker ps -qf "name=$(COMPOSE_PROJECT_NAME)_apache")
NODE_CONTAINER = $$(docker ps -qf "name=$(COMPOSE_PROJECT_NAME)_node")
MARIADB_CONTAINER = $$(docker ps -qf "name=$(COMPOSE_PROJECT_NAME)_mariadb")

# Containers par nom
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

# Helper Functions
define check_container
	@if ! docker ps --format "{{.Names}}" | grep -q "$(1)"; then \
		echo "$(RED)✗ Container $(1) is not running$(NC)"; \
		echo "$(YELLOW)→ Starting containers...$(NC)"; \
		$(MAKE) up; \
		sleep 5; \
	fi
endef

define find_npm_path
	$(shell if docker exec $(NODE_CONTAINER_NAME) test -f /var/www/html/package.json 2>/dev/null; then \
		echo "/var/www/html"; \
	elif docker exec $(NODE_CONTAINER_NAME) test -f /var/www/project/package.json 2>/dev/null; then \
		echo "/var/www/project"; \
	else \
		echo ""; \
	fi)
endef

define run_npm_command
	$(eval NPM_PATH := $(call find_npm_path))
	@if [ -z "$(NPM_PATH)" ]; then \
		echo "$(RED)✗ No package.json found$(NC)"; \
		echo "$(BLUE)→ Run: make install-laravel$(NC)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)→ Running npm $(1) in $(NPM_PATH)$(NC)"
	@if [ "$(NPM_PATH)" = "/var/www/project" ]; then \
		docker exec -u 1000:1000 -w $(NPM_PATH) $(NODE_CONTAINER_NAME) npm $(1); \
	else \
		docker exec -u 1000:1000 $(NODE_CONTAINER_NAME) npm $(1); \
	fi
endef

define quality_step
	@echo "$(YELLOW)→ Step $(1)/$(2): $(3)...$(NC)"
	@$(MAKE) $(4) || echo "$(RED)⚠ $(3) issues found$(NC)"
endef

# =============================================================================
# HELP & DOCUMENTATION
# =============================================================================

.PHONY: help
help: ## Afficher l'aide principale
	@echo "$(CYAN)╔══════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(CYAN)║                    LARAVEL DEV ENVIRONMENT                   ║$(NC)"
	@echo "$(CYAN)║                   avec Monitoring Intégré                    ║$(NC)"
	@echo "$(CYAN)╚══════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)💡 Commandes essentielles :$(NC)"
	@echo "  $(GREEN)make install$(NC)           - Installation complète"
	@echo "  $(GREEN)make dev$(NC)               - Environnement de développement"
	@echo "  $(GREEN)make quality-all$(NC)       - Audit complet qualité"
	@echo "  $(GREEN)make setup-git-hooks$(NC)   - Configurer GrumPHP"
	@echo ""
	@echo "$(BLUE)📚 Aide détaillée :$(NC)"
	@echo "  $(GREEN)make help-docker$(NC)       - Commandes Docker"
	@echo "  $(GREEN)make help-quality$(NC)      - Outils qualité"
	@echo "  $(GREEN)make help-monitoring$(NC)   - Surveillance"

# =============================================================================
# INSTALLATION & BUILD
# =============================================================================

.PHONY: install
install: build up install-laravel npm-install setup-ssl ## Installation complète
	@echo "$(GREEN)🎉 Installation terminée !$(NC)"
	@$(MAKE) _show_urls

.PHONY: setup-full
setup-full: install setup-monitoring setup-watchtower setup-git-hooks ## Installation et configuration complète
	@echo "$(GREEN)🚀 Configuration complète terminée !$(NC)"

.PHONY: build
build: ## Construire tous les containers
	@echo "$(YELLOW)Building containers...$(NC)"
	@$(DOCKER_COMPOSE) build --no-cache

.PHONY: rebuild
rebuild: down build up ## Reconstruire et redémarrer

# =============================================================================
# CONTAINER MANAGEMENT
# =============================================================================

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
	@$(DOCKER_COMPOSE) ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

.PHONY: logs
logs: ## Afficher les logs (usage: make logs service=php)
	@if [ -n "$(service)" ]; then \
		$(DOCKER_COMPOSE) logs -f $(service); \
	else \
		$(DOCKER_COMPOSE) logs -f; \
	fi

# =============================================================================
# LARAVEL MANAGEMENT
# =============================================================================

.PHONY: install-laravel
install-laravel: ## Installer Laravel avec outils qualité
	$(call check_container,$(PHP_CONTAINER_NAME))
	@echo "$(YELLOW)Installing Laravel...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) bash -c "cd /var/www/html && /docker/scripts/install-laravel.sh"
	@echo "$(GREEN)✓ Laravel installed$(NC)"

.PHONY: artisan
artisan: ## Exécuter artisan (usage: make artisan cmd="migrate")
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan $(cmd)

.PHONY: composer
composer: ## Exécuter composer (usage: make composer cmd="install")
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) composer $(cmd)

.PHONY: migrate
migrate: ## Lancer les migrations
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan migrate

.PHONY: fresh
fresh: ## Reset DB avec seeds
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan migrate:fresh --seed

# =============================================================================
# NPM/NODE MANAGEMENT
# =============================================================================

.PHONY: npm-install
npm-install: ## Installer les dépendances NPM
	$(call check_container,$(NODE_CONTAINER_NAME))
	@echo "$(YELLOW)Installing NPM dependencies...$(NC)"
	$(call run_npm_command,install)
	@echo "$(GREEN)✓ NPM dependencies installed$(NC)"

.PHONY: npm-build
npm-build: npm-install ## Builder les assets
	@echo "$(YELLOW)Building assets...$(NC)"
	$(call run_npm_command,run build)
	@echo "$(GREEN)✓ Build complete$(NC)"

.PHONY: npm-dev
npm-dev: npm-install ## Lancer le dev server
	@echo "$(YELLOW)Starting dev server...$(NC)"
	$(call run_npm_command,run dev)

.PHONY: npm-watch
npm-watch: npm-install ## Mode watch
	$(call run_npm_command,run watch)

# =============================================================================
# TESTING
# =============================================================================

.PHONY: test
test: ## Lancer tous les tests
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan test

.PHONY: test-unit
test-unit: ## Tests unitaires
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan test --testsuite=Unit

.PHONY: test-coverage
test-coverage: ## Tests avec couverture
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan test --coverage-html coverage

# =============================================================================
# CODE QUALITY
# =============================================================================

.PHONY: ecs
ecs: ## Vérifier le style de code
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) ./vendor/bin/ecs check

.PHONY: ecs-fix
ecs-fix: ## Corriger le style automatiquement
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) ./vendor/bin/ecs check --fix

.PHONY: phpstan
phpstan: ## Analyse statique
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) ./vendor/bin/phpstan analyse

.PHONY: rector
rector: ## Refactoring suggestions
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) ./vendor/bin/rector process --dry-run

.PHONY: rector-fix
rector-fix: ## Appliquer refactoring
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) ./vendor/bin/rector process

.PHONY: insights
insights: ## PHP Insights
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan insights

.PHONY: enlightn
enlightn: ## Audit sécurité
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan enlightn

# =============================================================================
# GRUMPHP & GIT HOOKS
# =============================================================================

.PHONY: setup-git-hooks
setup-git-hooks: ## Installer les hooks Git GrumPHP
	@echo "$(BLUE)🔗 Setting up Git hooks...$(NC)"
	@if $(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) test -f vendor/bin/grumphp; then \
		$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) vendor/bin/grumphp git:init; \
		echo "$(GREEN)✓ Git hooks installed$(NC)"; \
	else \
		echo "$(RED)✗ GrumPHP not found$(NC)"; \
		echo "$(BLUE)→ Install with: composer require --dev phpro/grumphp$(NC)"; \
	fi

.PHONY: grumphp-check
grumphp-check: ## Vérifier avec GrumPHP
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) vendor/bin/grumphp run --no-interaction

.PHONY: grumphp-status
grumphp-status: ## Statut GrumPHP
	@echo "$(BLUE)📊 GrumPHP Status$(NC)"
	@if $(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) test -f vendor/bin/grumphp; then \
		echo "$(GREEN)✓ GrumPHP installed$(NC)"; \
		if $(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) test -f .git/hooks/pre-commit; then \
			echo "$(GREEN)✓ Git hooks active$(NC)"; \
		else \
			echo "$(YELLOW)⚠ Git hooks not installed$(NC)"; \
		fi; \
	else \
		echo "$(RED)✗ GrumPHP not found$(NC)"; \
	fi

# =============================================================================
# QUALITY WORKFLOWS
# =============================================================================

.PHONY: quality-quick
quality-quick: ecs phpstan ## Vérification rapide
	@echo "$(GREEN)✓ Quick quality check completed$(NC)"

.PHONY: quality-fix
quality-fix: ecs-fix rector-fix ## Corrections automatiques
	@echo "$(GREEN)✓ Auto-fixes applied$(NC)"

.PHONY: quality-all
quality-all: ## Audit complet de qualité
	@echo "$(CYAN)🔍 Full quality audit$(NC)"
	$(call quality_step,1,6,Code style,ecs)
	$(call quality_step,2,6,Static analysis,phpstan)
	$(call quality_step,3,6,Security audit,enlightn)
	$(call quality_step,4,6,Quality insights,insights)
	$(call quality_step,5,6,Unit tests,test-unit)
	$(call quality_step,6,6,GrumPHP check,grumphp-check)
	@echo "$(GREEN)✅ Quality audit completed$(NC)"

.PHONY: pre-commit
pre-commit: quality-fix grumphp-check ## Vérifications pre-commit
	@echo "$(GREEN)✅ Pre-commit checks passed$(NC)"

# =============================================================================
# MONITORING
# =============================================================================

.PHONY: setup-monitoring
setup-monitoring: ## Configuration Uptime Kuma
	@echo "$(CYAN)⚙️ Setting up monitoring...$(NC)"
	@if [ -f "./scripts/setup-uptime-kuma-simple.sh" ]; then \
		chmod +x "./scripts/setup-uptime-kuma-simple.sh" && ./scripts/setup-uptime-kuma-simple.sh; \
	else \
		echo "$(BLUE)→ Open manually: http://localhost:3001$(NC)"; \
	fi

.PHONY: setup-watchtower
setup-watchtower: ## Configuration Watchtower
	@echo "$(CYAN)🔄 Setting up auto-updates...$(NC)"
	@if [ -f "./scripts/setup-watchtower-simple.sh" ]; then \
		chmod +x "./scripts/setup-watchtower-simple.sh" && ./scripts/setup-watchtower-simple.sh; \
	else \
		echo "$(YELLOW)⚠ Watchtower script not found$(NC)"; \
	fi

.PHONY: monitoring
monitoring: ## Ouvrir les outils de monitoring
	@echo "$(CYAN)📊 Opening monitoring tools...$(NC)"
	@$(MAKE) _open_url url="http://localhost:3001"
	@$(MAKE) _open_url url="http://localhost:9999"
	@$(MAKE) _open_url url="https://laravel.local/horizon"

# =============================================================================
# DEVELOPMENT WORKFLOWS
# =============================================================================

.PHONY: dev
dev: up npm-dev ## Environnement de développement
	@echo "$(GREEN)🚀 Development ready!$(NC)"

.PHONY: dev-fresh
dev-fresh: fresh npm-build ## DB fraîche + assets
	@echo "$(GREEN)✨ Fresh dev environment ready!$(NC)"

.PHONY: daily-check
daily-check: ## Vérifications quotidiennes
	@echo "$(CYAN)📅 Daily maintenance$(NC)"
	@$(MAKE) update-deps
	@$(MAKE) quality-all
	@$(MAKE) security-check
	@echo "$(GREEN)✓ Daily checks completed$(NC)"

# =============================================================================
# SHELL ACCESS
# =============================================================================

.PHONY: shell
shell: ## Shell PHP (défaut)
	@$(DOCKER) exec -it -u 1000:1000 $(PHP_CONTAINER) bash

.PHONY: shell-node
shell-node: ## Shell Node
	@$(DOCKER) exec -it -u 1000:1000 $(NODE_CONTAINER) bash

.PHONY: shell-db
shell-db: ## Console MariaDB
	@$(DOCKER) exec -it $(MARIADB_CONTAINER_NAME) mysql -u root -p

# =============================================================================
# MAINTENANCE & CLEANUP
# =============================================================================

.PHONY: clean
clean: down ## Nettoyer containers et volumes
	@$(DOCKER_COMPOSE) down -v
	@echo "$(GREEN)✓ Cleaned$(NC)"

.PHONY: clean-all
clean-all: clean ## Nettoyage complet
	@$(DOCKER_COMPOSE) down --rmi all -v
	@$(DOCKER) system prune -af
	@echo "$(GREEN)✓ Deep clean completed$(NC)"

.PHONY: update-deps
update-deps: ## Mettre à jour les dépendances
	@echo "$(YELLOW)Updating dependencies...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) composer update --no-interaction
	$(call run_npm_command,update)
	@echo "$(GREEN)✓ Dependencies updated$(NC)"

.PHONY: security-check
security-check: ## Audit de sécurité
	@echo "$(PURPLE)🔒 Security audit$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) composer audit || true
	$(call run_npm_command,audit)
	@$(MAKE) enlightn || true
	@echo "$(GREEN)✓ Security check completed$(NC)"

# =============================================================================
# DIAGNOSTICS & DEBUG
# =============================================================================

.PHONY: diagnose
diagnose: ## Diagnostic complet
	@echo "$(CYAN)🔍 System Diagnostics$(NC)"
	@echo "$(CYAN)==================$(NC)"
	@echo ""
	@echo "$(YELLOW)🐳 Containers:$(NC)"
	@$(DOCKER_COMPOSE) ps --format "table {{.Name}}\t{{.Status}}"
	@echo ""
	@echo "$(YELLOW)📦 Laravel:$(NC)"
	@if $(DOCKER) exec $(PHP_CONTAINER_NAME) test -f composer.json 2>/dev/null; then \
		echo "$(GREEN)✓ Laravel detected$(NC)"; \
	else \
		echo "$(RED)✗ Laravel not found$(NC)"; \
	fi
	@echo ""
	@echo "$(YELLOW)🛡️ Quality Tools:$(NC)"
	@$(MAKE) grumphp-status
	@echo ""
	@echo "$(BLUE)💡 Quick fixes:$(NC)"
	@echo "  • make install-laravel"
	@echo "  • make setup-git-hooks"
	@echo "  • make setup-monitoring"

.PHONY: healthcheck
healthcheck: ## Vérifier la santé des services
	@$(DOCKER_COMPOSE) ps --format "table {{.Name}}\t{{.Status}}"

.PHONY: metrics
metrics: ## Métriques système
	@echo "$(CYAN)📊 System Metrics$(NC)"
	@$(DOCKER) stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# =============================================================================
# SSL & SETUP
# =============================================================================

.PHONY: setup-ssl
setup-ssl: ## Générer certificats SSL
	@./docker/scripts/generate-ssl.sh
	@echo "$(GREEN)✓ SSL certificates generated$(NC)"

# =============================================================================
# HELP SECTIONS
# =============================================================================

.PHONY: help-docker
help-docker: ## Aide Docker
	@echo "$(CYAN)🐳 Docker Commands$(NC)"
	@echo "$(CYAN)=================$(NC)"
	@echo "  $(GREEN)make up/down/restart$(NC)  - Container management"
	@echo "  $(GREEN)make build/rebuild$(NC)    - Image building"
	@echo "  $(GREEN)make logs service=php$(NC) - View logs"
	@echo "  $(GREEN)make shell/shell-node$(NC) - Shell access"
	@echo "  $(GREEN)make clean/clean-all$(NC)  - Cleanup"

.PHONY: help-quality
help-quality: ## Aide qualité
	@echo "$(CYAN)🔍 Quality Tools$(NC)"
	@echo "$(CYAN)===============$(NC)"
	@echo "  $(GREEN)make quality-quick$(NC)    - Fast check (ECS + PHPStan)"
	@echo "  $(GREEN)make quality-all$(NC)      - Complete audit"
	@echo "  $(GREEN)make quality-fix$(NC)      - Auto-fix issues"
	@echo "  $(GREEN)make setup-git-hooks$(NC)  - Install GrumPHP"
	@echo "  $(GREEN)make pre-commit$(NC)       - Pre-commit checks"

.PHONY: help-monitoring
help-monitoring: ## Aide monitoring
	@echo "$(CYAN)📊 Monitoring$(NC)"
	@echo "$(CYAN)============$(NC)"
	@echo "  $(GREEN)make setup-monitoring$(NC) - Configure Uptime Kuma"
	@echo "  $(GREEN)make setup-watchtower$(NC) - Configure auto-updates"
	@echo "  $(GREEN)make monitoring$(NC)       - Open all tools"

# =============================================================================
# PRIVATE HELPERS
# =============================================================================

.PHONY: _show_urls
_show_urls:
	@echo "$(CYAN)🔗 Quick Access$(NC)"
	@echo "  • Laravel: https://laravel.local"
	@echo "  • Adminer: http://localhost:8080"
	@echo "  • MailHog: http://localhost:8025"
	@echo "  • Uptime Kuma: http://localhost:3001"

.PHONY: _open_url
_open_url:
	@if command -v open >/dev/null 2>&1; then \
		open $(url); \
	elif command -v xdg-open >/dev/null 2>&1; then \
		xdg-open $(url); \
	else \
		echo "$(BLUE)→ Open: $(url)$(NC)"; \
	fi