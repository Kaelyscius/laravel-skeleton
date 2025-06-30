# =============================================================================
# LARAVEL DEV ENVIRONMENT - Makefile Simplifié Sans Uptime Kuma
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
	@echo "$(CYAN)║                    avec Mises à Jour Auto                    ║$(NC)"
	@echo "$(CYAN)╚══════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)💡 Commandes essentielles :$(NC)"
	@echo "  $(GREEN)make install$(NC)           - Installation complète"
	@echo "  $(GREEN)make dev$(NC)               - Environnement de développement"
	@echo "  $(GREEN)make quality-all$(NC)       - Audit complet qualité"
	@echo ""
	@echo "$(BLUE)📚 Aide détaillée :$(NC)"
	@echo "  $(GREEN)make help-docker$(NC)       - Commandes Docker"
	@echo "  $(GREEN)make help-quality$(NC)      - Outils qualité"
	@echo "  $(GREEN)make help-watchtower$(NC)   - Mises à jour auto"

# =============================================================================
# INSTALLATION & BUILD
# =============================================================================

.PHONY: install
install: build up install-laravel npm-install setup-ssl ## Installation complète
	@echo "$(GREEN)🎉 Installation terminée !$(NC)"
	@$(MAKE) _show_urls

.PHONY: setup-full
setup-full: install setup-watchtower setup-git-hooks ## Installation et configuration complète
	@echo "$(GREEN)🚀 Configuration complète terminée !$(NC)"
	@echo ""
	@echo "$(CYAN)🎉 Votre environnement Laravel est maintenant complet avec :$(NC)"
	@echo "  $(GREEN)✓ Laravel installé et configuré$(NC)"
	@echo "  $(GREEN)✓ Watchtower configuré pour les mises à jour$(NC)"
	@echo ""

.PHONY: setup-quick
setup-quick: up install-laravel ## Installation rapide
	@echo "$(GREEN)⚡ Installation rapide terminée !$(NC)"

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
# GIT HOOKS
# =============================================================================

.PHONY: setup-git-hooks
setup-git-hooks: ## Installer les hooks Git custom
	@echo "$(BLUE)🔗 Setting up Git hooks...$(NC)"
	@if [ -f "./scripts/setup-git-hooks.sh" ]; then \
		chmod +x "./scripts/setup-git-hooks.sh"; \
		./scripts/setup-git-hooks.sh; \
	else \
		echo "$(RED)✗ Hook script not found$(NC)"; \
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
	$(call quality_step,1,5,Code style,ecs)
	$(call quality_step,2,5,Static analysis,phpstan)
	$(call quality_step,3,5,Security audit,enlightn)
	$(call quality_step,4,5,Quality insights,insights)
	$(call quality_step,5,5,Unit tests,test-unit)
	@echo "$(GREEN)✅ Quality audit completed$(NC)"

.PHONY: pre-commit
pre-commit: quality-fix ## Vérifications pre-commit
	@echo "$(GREEN)✅ Pre-commit checks passed$(NC)"

# =============================================================================
# WATCHTOWER MANAGEMENT (Mises à jour automatiques)
# =============================================================================

.PHONY: setup-watchtower
setup-watchtower: ## Configuration Watchtower
	@echo "$(CYAN)🔄 Configuration de Watchtower...$(NC)"
	@if [ -f "./scripts/setup-watchtower-simple.sh" ]; then \
		chmod +x "./scripts/setup-watchtower-simple.sh"; \
		./scripts/setup-watchtower-simple.sh; \
	else \
		echo "$(YELLOW)⚠ Script Watchtower non trouvé - Watchtower fonctionne automatiquement$(NC)"; \
		echo "$(BLUE)→ Planification: Tous les jours à 3h du matin$(NC)"; \
		echo "$(BLUE)→ Containers surveillés: MariaDB, Redis, MailHog, Adminer, IT-Tools, Dozzle$(NC)"; \
		echo "$(BLUE)→ Containers exclus: PHP, Apache, Node (images custom)$(NC)"; \
	fi

.PHONY: watchtower-logs
watchtower-logs: ## Voir les logs de Watchtower
	@$(DOCKER_COMPOSE) logs -f watchtower

.PHONY: watchtower-status
watchtower-status: ## Statut de Watchtower
	@echo "$(CYAN)🔄 Statut Watchtower$(NC)"
	@if docker ps --format "{{.Names}}" | grep -q "$(COMPOSE_PROJECT_NAME)_watchtower"; then \
		echo "$(GREEN)✓ Watchtower actif$(NC)"; \
		docker ps --filter name=$(COMPOSE_PROJECT_NAME)_watchtower --format "table {{.Names}}\t{{.Status}}"; \
		echo "$(BLUE)→ Planification: Tous les jours à 3h du matin$(NC)"; \
		echo "$(BLUE)→ Nettoyage automatique: Activé$(NC)"; \
		echo "$(BLUE)→ Mode: Label-based (containers autorisés)$(NC)"; \
	else \
		echo "$(RED)✗ Watchtower non actif$(NC)"; \
	fi

.PHONY: watchtower-update-now
watchtower-update-now: ## Forcer une mise à jour Watchtower
	@echo "$(YELLOW)🔄 Déclenchement manuel des mises à jour...$(NC)"
	@$(DOCKER) exec $(COMPOSE_PROJECT_NAME)_watchtower /watchtower --run-once --cleanup 2>/dev/null || echo "$(YELLOW)⚠ Commande non disponible, vérifiez les logs$(NC)"

# =============================================================================
# DEVELOPMENT WORKFLOWS
# =============================================================================

.PHONY: dev
dev: up npm-dev ## Environnement de développement
	@echo "$(GREEN)🚀 Development ready!$(NC)"

.PHONY: dev-full
dev-full: setup-full npm-dev ## Environnement de développement complet
	@echo "$(GREEN)🚀 Environnement de développement complet prêt !$(NC)"

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
	@echo ""
	@echo "$(YELLOW)🔄 Watchtower:$(NC)"
	@$(MAKE) watchtower-status
	@echo ""
	@echo "$(BLUE)💡 Quick fixes:$(NC)"
	@echo "  • make install-laravel"
	@echo "  • make setup-git-hooks"
	@echo "  • make setup-watchtower"

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
	@if [ -f "./docker/scripts/generate-ssl.sh" ]; then \
		chmod +x "./docker/scripts/generate-ssl.sh"; \
		./docker/scripts/generate-ssl.sh; \
		echo "$(GREEN)✓ SSL certificates generated$(NC)"; \
	else \
		echo "$(RED)❌ Script SSL non trouvé: ./docker/scripts/generate-ssl.sh$(NC)"; \
		exit 1; \
	fi

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
	@echo "  $(GREEN)make pre-commit$(NC)       - Pre-commit checks"

.PHONY: help-watchtower
help-watchtower: ## Aide Watchtower (mises à jour auto)
	@echo "$(CYAN)🔄 Watchtower - Mises à Jour Automatiques$(NC)"
	@echo "$(CYAN)=========================================$(NC)"
	@echo ""
	@echo "$(YELLOW)🚀 Configuration:$(NC)"
	@echo "  $(GREEN)make setup-watchtower$(NC)        - Configuration initiale"
	@echo "  $(GREEN)make watchtower-status$(NC)       - Vérifier le statut"
	@echo "  $(GREEN)make watchtower-logs$(NC)         - Voir les logs"
	@echo "  $(GREEN)make watchtower-update-now$(NC)   - Forcer une mise à jour"
	@echo ""
	@echo "$(YELLOW)⚙️ Fonctionnement:$(NC)"
	@echo "  • Planification: Tous les jours à 3h du matin"
	@echo "  • Containers surveillés: MariaDB, Redis, MailHog, Adminer, IT-Tools, Dozzle"
	@echo "  • Containers exclus: PHP, Apache, Node (images custom)"
	@echo "  • Nettoyage automatique des anciennes images"
	@echo "  • Rollback automatique en cas de problème"
	@echo ""
	@echo "$(YELLOW)📧 Notifications (optionnel):$(NC)"
	@echo "  • Configurez WATCHTOWER_NOTIFICATION_URL dans .env"
	@echo "  • Discord: discord://token@channel"
	@echo "  • Slack: slack://webhook_url"
	@echo "  • Email: smtp://user:pass@host:port/?from=...&to=..."

# =============================================================================
# PRIVATE HELPERS
# =============================================================================

.PHONY: _show_urls
_show_urls:
	@echo "$(CYAN)🔗 Quick Access$(NC)"
	@echo "  • Laravel: https://laravel.local"
	@echo "  • Horizon: https://laravel.local/horizon"
	@echo "  • Telescope: https://laravel.local/telescope"
	@echo "  • Adminer: http://localhost:8080"
	@echo "  • MailHog: http://localhost:8025"
	@echo "  • IT-Tools: http://localhost:8081"
	@echo "  • Dozzle: http://localhost:9999"

.PHONY: _open_url
_open_url:
	@if command -v open >/dev/null 2>&1; then \
		open $(url); \
	elif command -v xdg-open >/dev/null 2>&1; then \
		xdg-open $(url); \
	else \
		echo "$(BLUE)→ Open: $(url)$(NC)"; \
	fi

# =============================================================================
# NIGHTWATCH MANAGEMENT
# =============================================================================

.PHONY: nightwatch-start
nightwatch-start: ## Démarrer l'agent Nightwatch
	$(call check_container,$(PHP_CONTAINER_NAME))
	@echo "$(YELLOW)🌙 Démarrage de l'agent Nightwatch...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) bash -c "\
		if [ -f nightwatch.pid ] && kill -0 \$$(cat nightwatch.pid) 2>/dev/null; then \
			echo '⚠️ Agent déjà en cours (PID: '\$$(cat nightwatch.pid)')'; \
			exit 0; \
		fi; \
		if ! grep -q 'NIGHTWATCH_TOKEN=' .env || grep -q 'NIGHTWATCH_TOKEN=\$$' .env; then \
			echo '❌ Token Nightwatch non configuré dans .env'; \
			exit 1; \
		fi; \
		echo 'Démarrage de l agent Nightwatch...'; \
		nohup php artisan nightwatch:agent > nightwatch.log 2>&1 & \
		echo \$$! > nightwatch.pid; \
		sleep 2; \
		if kill -0 \$$(cat nightwatch.pid) 2>/dev/null; then \
			echo \"✅ Agent démarré avec succès (PID: \$$(cat nightwatch.pid))\"; \
			echo 'Logs en temps réel: make nightwatch-logs'; \
		else \
			echo '❌ Échec du démarrage, consultez les logs'; \
			cat nightwatch.log 2>/dev/null || true; \
		fi"

.PHONY: nightwatch-stop
nightwatch-stop: ## Arrêter l'agent Nightwatch
	$(call check_container,$(PHP_CONTAINER_NAME))
	@echo "$(YELLOW)🌙 Arrêt de l'agent Nightwatch...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) bash -c "\
		if [ -f nightwatch.pid ]; then \
			pid=\$$(cat nightwatch.pid); \
			if kill -0 \$$pid 2>/dev/null; then \
				kill \$$pid && echo \"✅ Agent arrêté (PID: \$$pid)\"; \
			else \
				echo '⚠️ Agent déjà arrêté'; \
			fi; \
			rm -f nightwatch.pid; \
		else \
			echo '○ Aucun agent en cours'; \
		fi"

.PHONY: nightwatch-restart
nightwatch-restart: nightwatch-stop nightwatch-start ## Redémarrer l'agent Nightwatch

.PHONY: nightwatch-status
nightwatch-status: ## Statut de l'agent Nightwatch
	$(call check_container,$(PHP_CONTAINER_NAME))
	@echo "$(CYAN)🌙 Statut Nightwatch$(NC)"
	@$(DOCKER) exec $(PHP_CONTAINER) bash -c "\
		echo '📦 Package:'; \
		if [ -d vendor/laravel/nightwatch ]; then \
			echo '  ✓ laravel/nightwatch installé'; \
		else \
			echo '  ✗ laravel/nightwatch non installé'; \
			exit 1; \
		fi; \
		echo '🔑 Token:'; \
		if token=\$$(grep '^NIGHTWATCH_TOKEN=' .env 2>/dev/null | cut -d'=' -f2- | xargs); then \
			if [ -n \"\$$token\" ] && [ \"\$$token\" != '\${NIGHTWATCH_TOKEN}' ]; then \
				echo \"  ✓ Configuré: \$${token:0:10}...\"; \
			else \
				echo '  ✗ Non configuré ou invalide'; \
			fi; \
		else \
			echo '  ✗ Variable non trouvée'; \
		fi; \
		echo '🤖 Agent:'; \
		if [ -f nightwatch.pid ]; then \
			pid=\$$(cat nightwatch.pid); \
			if kill -0 \$$pid 2>/dev/null; then \
				echo \"  ✓ En cours (PID: \$$pid)\"; \
			else \
				echo '  ✗ Arrêté (PID obsolète)'; \
			fi; \
		else \
			echo '  ○ Non démarré'; \
		fi"

.PHONY: nightwatch-logs
nightwatch-logs: ## Voir les logs Nightwatch en temps réel
	$(call check_container,$(PHP_CONTAINER_NAME))
	@echo "$(CYAN)📋 Logs Nightwatch (Ctrl+C pour arrêter)$(NC)"
	@$(DOCKER) exec $(PHP_CONTAINER) bash -c "\
		if [ -f nightwatch.log ]; then \
			tail -f nightwatch.log; \
		else \
			echo 'Aucun log Nightwatch trouvé'; \
			echo 'Démarrez l agent avec: make nightwatch-start'; \
		fi"

.PHONY: nightwatch-logs-tail
nightwatch-logs-tail: ## Voir les dernières lignes des logs
	$(call check_container,$(PHP_CONTAINER_NAME))
	@$(DOCKER) exec $(PHP_CONTAINER) bash -c "\
		if [ -f nightwatch.log ]; then \
			echo '📋 Dernières 20 lignes:'; \
			tail -20 nightwatch.log; \
		else \
			echo 'Aucun log disponible'; \
		fi"