# =============================================================================
# LARAVEL DEV ENVIRONMENT - Makefile Simplifié Sans Uptime Kuma
# =============================================================================

# Variables
DOCKER_COMPOSE = docker-compose
DOCKER = docker
COMPOSE_PROJECT_NAME ?= laravel-app
SCRIPT_DIR = ./scripts

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
	@echo "  $(GREEN)make up-local$(NC)          - Démarrer en développement local (recommandé)"
	@echo "  $(GREEN)make dev$(NC)               - Environnement de développement"
	@echo "  $(GREEN)make quality-all$(NC)       - Audit complet qualité"
	@echo ""
	@echo "$(BLUE)📚 Aide détaillée :$(NC)"
	@echo "  $(GREEN)make help-docker$(NC)       - Commandes Docker"
	@echo "  $(GREEN)make help-profiles$(NC)     - Architecture modulaire (profiles)"
	@echo "  $(GREEN)make help-quality$(NC)      - Outils qualité"
	@echo "  $(GREEN)make help-watchtower$(NC)   - Mises à jour auto"

# =============================================================================
# INSTALLATION & BUILD
# =============================================================================

# Installation développement (avec Node et tous les outils)
.PHONY: install
install: install-dev ## Alias pour install-dev (par défaut en développement)

.PHONY: install-dev
install-dev: build up-dev install-laravel npm-install setup-ssl ## Installation complète DÉVELOPPEMENT (avec Node, Mailpit, Adminer, etc.)
	@echo "$(GREEN)🎉 Installation DÉVELOPPEMENT terminée !$(NC)"
	@echo "$(CYAN)📦 Services actifs: PHP, Apache, MariaDB, Redis, Node, Mailpit, Adminer$(NC)"
	@$(MAKE) _show_urls

.PHONY: install-dev-full
install-dev-full: build up-dev-full install-laravel npm-install setup-ssl ## Installation DÉVELOPPEMENT COMPLÈTE (+ Dozzle, IT-Tools, Watchtower)
	@echo "$(GREEN)🎉 Installation DÉVELOPPEMENT COMPLÈTE terminée !$(NC)"
	@echo "$(CYAN)📦 Services actifs: Tous les services + monitoring$(NC)"
	@$(MAKE) _show_urls

# Installation production (sans Node ni outils dev)
.PHONY: install-prod
install-prod: build up install-laravel-prod setup-ssl ## Installation PRODUCTION (services essentiels uniquement)
	@echo "$(GREEN)🎉 Installation PRODUCTION terminée !$(NC)"
	@echo "$(CYAN)📦 Services actifs: PHP, Apache, MariaDB, Redis$(NC)"
	@echo "$(YELLOW)⚠️  Node, Mailpit, Adminer NON démarrés (profil dev désactivé)$(NC)"
	@$(MAKE) _show_urls

# Versions rapides avec cache
.PHONY: install-fast
install-fast: install-dev-fast ## Alias pour install-dev-fast

.PHONY: install-dev-fast
install-dev-fast: build-fast up-dev install-laravel npm-install-fast setup-ssl ## Installation DEV optimisée avec cache (recommandé)
	@echo "$(GREEN)🎉 Installation DÉVELOPPEMENT rapide terminée !$(NC)"
	@$(MAKE) _show_urls

.PHONY: install-prod-fast
install-prod-fast: build-fast up install-laravel-prod setup-ssl ## Installation PROD optimisée avec cache
	@echo "$(GREEN)🎉 Installation PRODUCTION rapide terminée !$(NC)"
	@$(MAKE) _show_urls

.PHONY: install-incremental
install-incremental: ## Mise à jour incrémentale (si déjà installé)
	@if [ -f "src/vendor/autoload.php" ]; then \
		echo "$(CYAN)✓ Vendor exists, updating dependencies...$(NC)"; \
		$(DOCKER) exec -u www-data $(PHP_CONTAINER_NAME) composer update --no-interaction --optimize-autoloader --no-progress; \
	else \
		echo "$(YELLOW)→ Vendor not found, running full install...$(NC)"; \
		$(MAKE) install-laravel; \
	fi
	@if [ -f "src/node_modules/.package-lock.json" ]; then \
		echo "$(CYAN)✓ node_modules exists, updating...$(NC)"; \
		$(MAKE) npm-install-fast; \
	else \
		echo "$(YELLOW)→ node_modules not found, running full install...$(NC)"; \
		$(MAKE) npm-install; \
	fi
	@echo "$(GREEN)✓ Incremental update complete$(NC)"

.PHONY: setup-quick
setup-quick: up install-laravel ## Installation rapide sans SSL
	@echo "$(GREEN)⚡ Installation rapide terminée !$(NC)"

.PHONY: build
build: ## Construire tous les containers (sans cache)
	@echo "$(YELLOW)Building containers...$(NC)"
	@$(DOCKER_COMPOSE) build --no-cache

.PHONY: build-fast
build-fast: ## Construire avec cache BuildKit (recommandé)
	@echo "$(CYAN)⚡ Building containers with cache...$(NC)"
	@DOCKER_BUILDKIT=1 COMPOSE_DOCKER_CLI_BUILD=1 $(DOCKER_COMPOSE) build

.PHONY: rebuild
rebuild: down build up ## Reconstruire et redémarrer (sans cache)

.PHONY: rebuild-fast
rebuild-fast: down build-fast up ## Reconstruire avec cache (rapide)

.PHONY: enable-xdebug
enable-xdebug: rebuild ## Activer xdebug (reconstruction Docker requise)
	@echo "$(CYAN)🐛 Vérification de l'activation de Xdebug...$(NC)"
	@if docker exec $(PHP_CONTAINER_NAME) php -m | grep -q xdebug; then \
		echo "$(GREEN)✅ Xdebug activé avec succès$(NC)"; \
		echo "$(BLUE)ℹ️  Configuration Xdebug:$(NC)"; \
		docker exec $(PHP_CONTAINER_NAME) php -r "if (extension_loaded('xdebug')) { echo 'Mode: ' . ini_get('xdebug.mode') . PHP_EOL; echo 'Client Host: ' . ini_get('xdebug.client_host') . PHP_EOL; echo 'Client Port: ' . ini_get('xdebug.client_port') . PHP_EOL; }"; \
	else \
		echo "$(RED)❌ Xdebug non activé - vérifiez la configuration Docker$(NC)"; \
	fi

# =============================================================================
# INSTALLATION INTERACTIVE ET PROFILS
# =============================================================================

.PHONY: fix-scripts-permissions
fix-scripts-permissions: ## Corriger les permissions de tous les scripts
	@echo "$(YELLOW)🔧 Correction des permissions des scripts...$(NC)"
	@mkdir -p scripts/setup scripts/security config
	@find scripts/ docker/ -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true
	@echo "$(GREEN)✅ Permissions des scripts corrigées$(NC)"

.PHONY: fix-composer
fix-composer: ## Corriger les problèmes Composer (cache, config, PHP 8.4)
	@echo "$(YELLOW)🔧 Correction des problèmes Composer pour PHP 8.4...$(NC)"
	@if [ -f "./scripts/install/05-composer-setup.sh" ]; then \
		chmod +x "./scripts/install/05-composer-setup.sh"; \
		./scripts/install/05-composer-setup.sh; \
	else \
		echo "$(RED)❌ Module de configuration Composer non trouvé$(NC)"; \
		exit 1; \
	fi

.PHONY: setup-interactive
setup-interactive: fix-scripts-permissions ## Installation interactive avec choix de configuration
	@echo "$(CYAN)🚀 Démarrage de l'installation interactive...$(NC)"
	@if [ -f "./scripts/setup/interactive-setup.sh" ]; then \
		chmod +x "./scripts/setup/interactive-setup.sh"; \
		./scripts/setup/interactive-setup.sh; \
	else \
		echo "$(RED)❌ Script d'installation non trouvé$(NC)"; \
		exit 1; \
	fi

.PHONY: setup-full
setup-full: setup-interactive ## Installation complète (alias pour setup-interactive)

.PHONY: setup-minimal
setup-minimal: ## Installation minimale (local + services essentiels)
	@echo "$(CYAN)🚀 Installation minimale...$(NC)"
	@if [ -f "./scripts/setup/interactive-setup.sh" ]; then \
		chmod +x "./scripts/setup/interactive-setup.sh"; \
		./scripts/setup/interactive-setup.sh --env local --batch; \
	else \
		echo "$(RED)❌ Script d'installation non trouvé$(NC)"; \
		exit 1; \
	fi

.PHONY: setup-dev
setup-dev: ## Installation développement (development + tous outils dev)
	@echo "$(CYAN)🚀 Installation développement...$(NC)"
	@if [ -f "./scripts/setup/interactive-setup.sh" ]; then \
		chmod +x "./scripts/setup/interactive-setup.sh"; \
		./scripts/setup/interactive-setup.sh --env development --batch; \
	else \
		echo "$(RED)❌ Script d'installation non trouvé$(NC)"; \
		exit 1; \
	fi

.PHONY: setup-prod
setup-prod: ## Installation production (optimisée pour la production)
	@echo "$(CYAN)🚀 Installation production...$(NC)"
	@if [ -f "./scripts/setup/interactive-setup.sh" ]; then \
		chmod +x "./scripts/setup/interactive-setup.sh"; \
		./scripts/setup/interactive-setup.sh --env production --batch; \
	else \
		echo "$(RED)❌ Script d'installation non trouvé$(NC)"; \
		exit 1; \
	fi

# =============================================================================
# CONFIGURATION MANUELLE (si besoin)
# =============================================================================

.PHONY: generate-config
generate-config: ## Générer la configuration pour un environnement (usage: make generate-config ENV=local)
	@if [ -z "$(ENV)" ]; then \
		echo "$(RED)❌ Spécifiez l'environnement: make generate-config ENV=local$(NC)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)🔧 Génération de la configuration pour $(ENV)...$(NC)"
	@if [ -f "./scripts/setup/generate-configs.sh" ]; then \
		chmod +x "./scripts/setup/generate-configs.sh"; \
		./scripts/setup/generate-configs.sh $(ENV); \
	else \
		echo "$(RED)❌ Script de génération non trouvé$(NC)"; \
		exit 1; \
	fi

# =============================================================================
# CONTAINER MANAGEMENT
# =============================================================================

.PHONY: up
up: ## Démarrer tous les containers
	@echo "$(YELLOW)Starting containers...$(NC)"
	@$(DOCKER_COMPOSE) up -d
	@echo "$(GREEN)✓ Containers started$(NC)"

.PHONY: down
down: ## Arrêter tous les containers (tous profiles)
	@echo "$(YELLOW)Stopping containers (all profiles)...$(NC)"
	@$(DOCKER_COMPOSE) --profile dev --profile tools --profile dev-extra down
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
# DOCKER PROFILES MANAGEMENT (Modular Architecture)
# =============================================================================
# Profiles disponibles:
#   - AUCUN       : Production (apache, php, mariadb, redis)
#   - dev         : Outils développement (node, mailpit, adminer)
#   - tools       : Utilitaires (dozzle, it-tools, watchtower)
#   - dev-extra   : Outils additionnels (phpmyadmin, redis-commander)
# =============================================================================

.PHONY: up-prod
up-prod: ## Production - Services essentiels uniquement (apache, php, mariadb, redis)
	@echo "$(CYAN)🚀 Démarrage en mode PRODUCTION (services essentiels uniquement)$(NC)"
	@$(DOCKER_COMPOSE) -f docker-compose.yml -f docker-compose.prod.yml up -d
	@echo "$(GREEN)✓ Services production démarrés$(NC)"
	@$(MAKE) _show-active-services

.PHONY: up-dev
up-dev: ## Développement - Essentiels + dev tools (+ node, mailpit, adminer)
	@echo "$(CYAN)🚀 Démarrage en mode DÉVELOPPEMENT (services + dev tools)$(NC)"
	@$(DOCKER_COMPOSE) -f docker-compose.yml -f docker-compose.dev.yml --profile dev up -d
	@echo "$(GREEN)✓ Services développement démarrés$(NC)"
	@$(MAKE) _show-active-services

.PHONY: up-dev-full
up-dev-full: ## Développement complet - Essentiels + dev + tools (+ dozzle, watchtower, it-tools)
	@echo "$(CYAN)🚀 Démarrage en mode DÉVELOPPEMENT COMPLET (tous les outils)$(NC)"
	@$(DOCKER_COMPOSE) -f docker-compose.yml -f docker-compose.dev.yml --profile dev --profile tools up -d
	@echo "$(GREEN)✓ Tous les services démarrés$(NC)"
	@$(MAKE) _show-active-services

.PHONY: up-dev-extra
up-dev-extra: ## Développement avec outils extra (+ phpmyadmin, redis-commander)
	@echo "$(CYAN)🚀 Démarrage DÉVELOPPEMENT + outils extra$(NC)"
	@$(DOCKER_COMPOSE) -f docker-compose.yml -f docker-compose.dev.yml --profile dev --profile tools --profile dev-extra up -d
	@echo "$(GREEN)✓ Tous les services + outils extra démarrés$(NC)"
	@$(MAKE) _show-active-services

.PHONY: up-local
up-local: up-dev-full ## Alias pour développement local complet (recommandé)

.PHONY: up-tools
up-tools: ## Démarrer uniquement les outils de monitoring (dozzle, it-tools, watchtower)
	@echo "$(CYAN)🔧 Démarrage des outils de monitoring uniquement$(NC)"
	@$(DOCKER_COMPOSE) --profile tools up -d dozzle it-tools watchtower
	@echo "$(GREEN)✓ Outils de monitoring démarrés$(NC)"

.PHONY: ps-profiles
ps-profiles: ## Afficher les services actifs avec leurs profiles
	@echo "$(CYAN)📋 Services actifs par profile:$(NC)"
	@echo ""
	@echo "$(YELLOW)🏭 PRODUCTION (aucun profile):$(NC)"
	@$(DOCKER_COMPOSE) ps --filter "name=apache" --filter "name=php" --filter "name=mariadb" --filter "name=redis" --format "  ✓ {{.Name}}" 2>/dev/null || echo "  ○ Aucun"
	@echo ""
	@echo "$(YELLOW)🛠️  DEV (profile: dev):$(NC)"
	@$(DOCKER_COMPOSE) ps --filter "name=node" --filter "name=mailpit" --filter "name=adminer" --format "  ✓ {{.Name}}" 2>/dev/null || echo "  ○ Aucun"
	@echo ""
	@echo "$(YELLOW)🔧 TOOLS (profile: tools):$(NC)"
	@$(DOCKER_COMPOSE) ps --filter "name=dozzle" --filter "name=it-tools" --filter "name=watchtower" --format "  ✓ {{.Name}}" 2>/dev/null || echo "  ○ Aucun"
	@echo ""
	@echo "$(YELLOW)➕ DEV-EXTRA (profile: dev-extra):$(NC)"
	@$(DOCKER_COMPOSE) ps --filter "name=phpmyadmin" --filter "name=redis-commander" --format "  ✓ {{.Name}}" 2>/dev/null || echo "  ○ Aucun"

.PHONY: stop-profile
stop-profile: ## Arrêter un profile spécifique (usage: make stop-profile PROFILE=dev)
	@if [ -z "$(PROFILE)" ]; then \
		echo "$(RED)❌ Spécifiez le profile: make stop-profile PROFILE=dev|tools|dev-extra$(NC)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)🛑 Arrêt du profile: $(PROFILE)$(NC)"
	@$(DOCKER_COMPOSE) --profile $(PROFILE) stop
	@echo "$(GREEN)✓ Profile $(PROFILE) arrêté$(NC)"

# =============================================================================
# LARAVEL MANAGEMENT
# =============================================================================

.PHONY: install-laravel
install-laravel: ## Installer Laravel avec outils qualité (version refactorisée)
	$(call check_container,$(PHP_CONTAINER_NAME))
	@echo "$(YELLOW)Installing Laravel (refactored)...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) bash -c "cd /var/www/html && /var/www/project/scripts/install.sh"
	@echo "$(GREEN)✓ Laravel installed$(NC)"

.PHONY: install-laravel-php84
install-laravel-php84: ## Installation Laravel optimisée pour PHP 8.4 avec corrections
	$(call check_container,$(PHP_CONTAINER_NAME))
	@echo "$(CYAN)🚀 Installation Laravel optimisée PHP 8.4...$(NC)"
	@echo "$(BLUE)→ Étape 1: Diagnostic et correction Composer$(NC)"
	@if [ -f "./scripts/install/05-composer-setup.sh" ]; then \
		chmod +x "./scripts/install/05-composer-setup.sh"; \
		./scripts/install/05-composer-setup.sh; \
	fi
	@echo "$(BLUE)→ Étape 2: Test rapide compatibilité$(NC)"
	@if [ -f "./scripts/diagnostic-tools.sh" ]; then \
		chmod +x "./scripts/diagnostic-tools.sh"; \
		./scripts/diagnostic-tools.sh --quick-test; \
	fi
	@echo "$(BLUE)→ Étape 3: Installation Laravel avec scripts refactorisés$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) bash -c "cd /var/www/html && /var/www/project/scripts/install.sh"
	@echo "$(GREEN)✅ Installation Laravel PHP 8.5.1 terminée !$(NC)"

.PHONY: install-laravel-prod
install-laravel-prod: ## Installer Laravel PRODUCTION (sans packages dev)
	@echo "$(CYAN)📦 Installation Laravel PRODUCTION (packages essentiels uniquement)$(NC)"
	@echo "$(BLUE)→ Étape 1: Setup Composer$(NC)"
	@if [ -f "./scripts/install/05-composer-setup.sh" ]; then \
		chmod +x "./scripts/install/05-composer-setup.sh"; \
		./scripts/install/05-composer-setup.sh; \
	fi
	@echo "$(BLUE)→ Étape 2: Installation packages production uniquement$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) bash -c "cd /var/www/html && /var/www/project/scripts/install.sh --only 10-laravel-core"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) bash -c "cd /var/www/html && /var/www/project/scripts/install.sh --only 20-database"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) bash -c "cd /var/www/html && /var/www/project/scripts/install.sh --only 30-packages-prod"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) bash -c "cd /var/www/html && /var/www/project/scripts/install.sh --only 35-configure-spatie-packages"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) bash -c "cd /var/www/html && /var/www/project/scripts/install.sh --only 99-finalize"
	@echo "$(GREEN)✅ Installation Laravel PRODUCTION terminée (sans outils dev) !$(NC)"
	@echo "$(YELLOW)⚠️  PHPStan, ECS, Rector, Pest NON installés (environnement production)$(NC)"


.PHONY: test-packages
test-packages: ## Tester compatibilité des packages
	@echo "$(YELLOW)🧪 Test compatibilité packages...$(NC)"
	@if [ -f "./scripts/diagnostic-tools.sh" ]; then \
		chmod +x "./scripts/diagnostic-tools.sh"; \
		./scripts/diagnostic-tools.sh --packages; \
	else \
		echo "$(RED)❌ Script d'outils diagnostic non trouvé$(NC)"; \
	fi

.PHONY: diagnostic
diagnostic: ## Outils de diagnostic unifiés (--all)
	@echo "$(CYAN)🔧 Diagnostic complet PHP 8.4 + Laravel 12...$(NC)"
	@if [ -f "./scripts/diagnostic-tools.sh" ]; then \
		chmod +x "./scripts/diagnostic-tools.sh"; \
		./scripts/diagnostic-tools.sh --all; \
	else \
		echo "$(RED)❌ Script d'outils diagnostic non trouvé$(NC)"; \
	fi

.PHONY: check-extensions
check-extensions: ## Vérifier les extensions PHP 8.4
	@echo "$(YELLOW)🔍 Vérification extensions PHP...$(NC)"
	@if [ -f "./scripts/diagnostic-tools.sh" ]; then \
		chmod +x "./scripts/diagnostic-tools.sh"; \
		./scripts/diagnostic-tools.sh --extensions; \
	else \
		echo "$(RED)❌ Script d'outils diagnostic non trouvé$(NC)"; \
	fi

.PHONY: quick-check
quick-check: ## Test rapide Laravel + PHP 8.4
	@echo "$(YELLOW)⚡ Test rapide Laravel + PHP 8.4...$(NC)"
	@if [ -f "./scripts/diagnostic-tools.sh" ]; then \
		chmod +x "./scripts/diagnostic-tools.sh"; \
		./scripts/diagnostic-tools.sh --quick-test; \
	else \
		echo "$(RED)❌ Script d'outils diagnostic non trouvé$(NC)"; \
	fi

.PHONY: check-compatibility
check-compatibility: ## Vérifier compatibilité packages Laravel 12
	@echo "$(YELLOW)🔍 Vérification compatibilité packages Laravel 12...$(NC)"
	@if [ -f "./scripts/check-package-compatibility.sh" ]; then \
		chmod +x "./scripts/check-package-compatibility.sh"; \
		./scripts/check-package-compatibility.sh; \
	else \
		echo "$(RED)❌ Script de vérification compatibilité non trouvé$(NC)"; \
	fi

.PHONY: update-packages
update-packages: ## Vérifier et installer packages devenus compatibles
	@echo "$(YELLOW)📦 Installation packages devenus compatibles Laravel 12...$(NC)"
	@if [ -f "./scripts/check-package-compatibility.sh" ]; then \
		chmod +x "./scripts/check-package-compatibility.sh"; \
		./scripts/check-package-compatibility.sh --auto-install; \
	else \
		echo "$(RED)❌ Script de vérification compatibilité non trouvé$(NC)"; \
	fi

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

.PHONY: clean-telescope-migrations
clean-telescope-migrations: ## Nettoyer les entrées de migrations Telescope en double
	@echo "$(YELLOW)🧹 Nettoyage des migrations Telescope en double...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan tinker --execute="\
		DB::table('migrations')->where('migration', 'like', '%create_telescope%')->delete();\
		echo 'Migrations Telescope supprimées de la table migrations';\
	" 2>/dev/null || echo "$(RED)Erreur lors du nettoyage$(NC)"
	@echo "$(GREEN)✓ Nettoyage terminé - relancez: make migrate$(NC)"

# =============================================================================
# NPM/NODE MANAGEMENT
# =============================================================================

.PHONY: npm-install
npm-install: ## Installer les dépendances NPM
	$(call check_container,$(NODE_CONTAINER_NAME))
	@echo "$(YELLOW)Installing NPM dependencies...$(NC)"
	$(call run_npm_command,install)
	@echo "$(GREEN)✓ NPM dependencies installed$(NC)"

.PHONY: npm-install-fast
npm-install-fast: ## Installer avec npm ci (plus rapide)
	$(call check_container,$(NODE_CONTAINER_NAME))
	@echo "$(CYAN)⚡ Installing NPM with ci (optimized)...$(NC)"
	$(call run_npm_command,ci --prefer-offline --no-audit --no-fund)
	@echo "$(GREEN)✓ NPM dependencies installed (fast)$(NC)"

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

.PHONY: test-drift
test-drift: ## Tests avec détection de code non couvert (Drift)
	@echo "$(CYAN)🎯 Exécution des tests avec Drift...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan test --drift

.PHONY: test-feature
test-feature: ## Tests fonctionnels
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan test --testsuite=Feature

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
enlightn: ## Audit sécurité (PHPStan - Enlightn supprimé, non compatible Laravel 12)
	@echo "$(YELLOW)ℹ️  Enlightn retiré du projet (fork communautaire non maintenu).$(NC)"
	@echo "$(CYAN)→ Utilisez 'make phpstan' pour l'analyse statique et 'make security-scan' pour la sécurité.$(NC)"

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
		echo "$(BLUE)→ Containers surveillés: MariaDB, Redis, Mailpit, Adminer, IT-Tools, Dozzle$(NC)"; \
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

.PHONY: fix-permissions
fix-permissions: ## Corriger les permissions pour PhpStorm (containers doivent être démarrés)
	@echo "$(CYAN)🔧 Correction des permissions Docker pour PhpStorm$(NC)"
	@if docker ps --format "{{.Names}}" | grep -q "$(PHP_CONTAINER_NAME)"; then \
		$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) /var/www/project/scripts/fix-permissions.sh; \
		echo "$(GREEN)✅ Permissions corrigées - redémarrez PhpStorm si nécessaire$(NC)"; \
	else \
		echo "$(YELLOW)⚠️ Containers non démarrés - lancement direct du script$(NC)"; \
		/var/www/html/myLaravelSkeleton/scripts/fix-permissions.sh; \
	fi

# =============================================================================
# MAINTENANCE & CLEANUP
# =============================================================================

.PHONY: clean
clean: ## Nettoyer containers et volumes (tous profiles)
	@echo "$(YELLOW)🧹 Arrêt de tous les containers (tous profiles)...$(NC)"
	@$(DOCKER_COMPOSE) --profile dev --profile tools --profile dev-extra down -v
	@echo "$(GREEN)✓ Cleaned$(NC)"

.PHONY: clean-all
clean-all: ## Nettoyage complet (inclut tous les profiles)
	@echo "$(YELLOW)🧹 Arrêt de tous les containers (tous profiles)...$(NC)"
	@$(DOCKER_COMPOSE) --profile dev --profile tools --profile dev-extra down --rmi all -v
	@echo "$(YELLOW)🧹 Nettoyage système Docker...$(NC)"
	@$(DOCKER) system prune -af
	@echo "$(GREEN)✓ Deep clean completed$(NC)"

.PHONY: clean-cache
clean-cache: ## Nettoyer tous les caches (Composer, NPM, Laravel)
	@echo "$(YELLOW)🧹 Cleaning all caches...$(NC)"
	@if [ -d "$$HOME/.cache/composer" ]; then \
		echo "$(CYAN)→ Cleaning Composer cache...$(NC)"; \
		rm -rf $$HOME/.cache/composer/*; \
	fi
	@if [ -d "$$HOME/.composer/cache" ]; then \
		echo "$(CYAN)→ Cleaning Composer cache (old location)...$(NC)"; \
		rm -rf $$HOME/.composer/cache/*; \
	fi
	@if docker ps -q -f name=$(PHP_CONTAINER_NAME) >/dev/null 2>&1; then \
		echo "$(CYAN)→ Cleaning Laravel cache...$(NC)"; \
		$(DOCKER) exec $(PHP_CONTAINER_NAME) php artisan cache:clear 2>/dev/null || true; \
		$(DOCKER) exec $(PHP_CONTAINER_NAME) php artisan config:clear 2>/dev/null || true; \
		$(DOCKER) exec $(PHP_CONTAINER_NAME) php artisan route:clear 2>/dev/null || true; \
		$(DOCKER) exec $(PHP_CONTAINER_NAME) php artisan view:clear 2>/dev/null || true; \
	fi
	@if [ -d "src/node_modules/.cache" ]; then \
		echo "$(CYAN)→ Cleaning NPM cache...$(NC)"; \
		rm -rf src/node_modules/.cache; \
	fi
	@echo "$(GREEN)✅ All caches cleaned$(NC)"

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

.PHONY: health
health: ## Health check Laravel (spatie/laravel-health)
	@echo "$(CYAN)🏥 Exécution des health checks Laravel...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan health:check

.PHONY: schedule-monitor-sync
schedule-monitor-sync: ## Synchroniser les moniteurs de tâches planifiées
	@echo "$(CYAN)⏰ Synchronisation des moniteurs de tâches...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan schedule-monitor:sync

.PHONY: schedule-monitor-list
schedule-monitor-list: ## Lister les tâches planifiées monitorées
	@echo "$(CYAN)📋 Liste des tâches monitorées:$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan schedule-monitor:list

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
	@echo ""
	@echo "$(YELLOW)🎯 Pour l'architecture modulaire, voir:$(NC)"
	@echo "  $(GREEN)make help-profiles$(NC)"

.PHONY: help-profiles
help-profiles: ## Aide pour l'architecture modulaire (profiles)
	@echo "$(CYAN)🎯 Architecture Modulaire avec Docker Profiles$(NC)"
	@echo "$(CYAN)===============================================$(NC)"
	@echo ""
	@echo "$(YELLOW)📦 Profiles disponibles:$(NC)"
	@echo ""
	@echo "  $(PURPLE)Aucun profile$(NC) (Production)"
	@echo "    • Services: apache, php, mariadb, redis"
	@echo "    • Usage: Services essentiels uniquement"
	@echo ""
	@echo "  $(PURPLE)dev$(NC) (Développement)"
	@echo "    • Services: node, mailpit, adminer"
	@echo "    • Usage: Outils de développement"
	@echo ""
	@echo "  $(PURPLE)tools$(NC) (Utilitaires)"
	@echo "    • Services: dozzle, it-tools, watchtower"
	@echo "    • Usage: Monitoring et outils de diagnostic"
	@echo ""
	@echo "  $(PURPLE)dev-extra$(NC) (Outils additionnels)"
	@echo "    • Services: phpmyadmin, redis-commander"
	@echo "    • Usage: Outils supplémentaires de développement"
	@echo ""
	@echo "$(YELLOW)🚀 Commandes de démarrage:$(NC)"
	@echo "  $(GREEN)make up-prod$(NC)           - Production (services essentiels uniquement)"
	@echo "  $(GREEN)make up-dev$(NC)            - Développement (essentiels + dev)"
	@echo "  $(GREEN)make up-dev-full$(NC)       - Développement complet (essentiels + dev + tools)"
	@echo "  $(GREEN)make up-dev-extra$(NC)      - Développement + tous les outils extra"
	@echo "  $(GREEN)make up-local$(NC)          - Alias pour développement local (recommandé)"
	@echo "  $(GREEN)make up-tools$(NC)          - Démarrer uniquement les outils de monitoring"
	@echo ""
	@echo "$(YELLOW)🔍 Commandes d'information:$(NC)"
	@echo "  $(GREEN)make ps-profiles$(NC)       - Voir les services actifs par profile"
	@echo "  $(GREEN)make status$(NC)            - Statut détaillé de tous les containers"
	@echo ""
	@echo "$(YELLOW)🛑 Gestion des profiles:$(NC)"
	@echo "  $(GREEN)make stop-profile PROFILE=dev$(NC)    - Arrêter un profile spécifique"
	@echo "  $(GREEN)make down$(NC)                        - Arrêter tous les services"
	@echo ""
	@echo "$(YELLOW)💡 Exemples d'usage:$(NC)"
	@echo ""
	@echo "  $(CYAN)# Développement local avec tous les outils$(NC)"
	@echo "  $(GREEN)make up-local$(NC)"
	@echo ""
	@echo "  $(CYAN)# Production (serveur)$(NC)"
	@echo "  $(GREEN)make up-prod$(NC)"
	@echo ""
	@echo "  $(CYAN)# Développement sans outils de monitoring$(NC)"
	@echo "  $(GREEN)make up-dev$(NC)"
	@echo ""
	@echo "  $(CYAN)# Ajouter les outils de monitoring à un environnement existant$(NC)"
	@echo "  $(GREEN)make up-tools$(NC)"
	@echo ""
	@echo "$(BLUE)📖 Documentation complète: DOCKER-ARCHITECTURE.md$(NC)"

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
	@echo "  • Containers surveillés: MariaDB, Redis, Mailpit, Adminer, IT-Tools, Dozzle"
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
	@if docker ps --format "{{.Names}}" | grep -q "adminer"; then \
		echo "  • Adminer: http://localhost:8080"; \
	fi
	@if docker ps --format "{{.Names}}" | grep -q "mailpit"; then \
		echo "  • Mailpit: http://localhost:8025"; \
	fi
	@if docker ps --format "{{.Names}}" | grep -q "it-tools"; then \
		echo "  • IT-Tools: http://localhost:8081"; \
	fi
	@if docker ps --format "{{.Names}}" | grep -q "dozzle"; then \
		echo "  • Dozzle: http://localhost:9999"; \
	fi
	@if docker ps --format "{{.Names}}" | grep -q "phpmyadmin"; then \
		echo "  • PHPMyAdmin: http://localhost:8083"; \
	fi
	@if docker ps --format "{{.Names}}" | grep -q "redis-commander"; then \
		echo "  • Redis Commander: http://localhost:8082"; \
	fi

.PHONY: _show-active-services
_show-active-services:
	@echo ""
	@echo "$(CYAN)📦 Services actifs:$(NC)"
	@$(DOCKER_COMPOSE) ps --format "  ✓ {{.Name}} ({{.Status}})"
	@echo ""
	@echo "$(BLUE)💡 Commandes utiles:$(NC)"
	@echo "  • $(GREEN)make ps-profiles$(NC)     - Voir les services par profile"
	@echo "  • $(GREEN)make status$(NC)          - Statut détaillé"
	@echo "  • $(GREEN)make logs$(NC)            - Voir les logs"

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

# =============================================================================
# SÉCURITÉ ET SNYK
# =============================================================================

.PHONY: security-install
security-install: ## Installer Snyk CLI
	@echo "$(YELLOW)📦 Installation de Snyk CLI...$(NC)"
	@if command -v npm >/dev/null 2>&1; then \
		npm install -g snyk; \
		echo "$(GREEN)✓ Snyk CLI installé$(NC)"; \
	else \
		echo "$(RED)❌ npm requis pour installer Snyk$(NC)"; \
		echo "$(BLUE)→ Installez Node.js puis relancez: make security-install$(NC)"; \
		exit 1; \
	fi

.PHONY: security-auth
security-auth: ## Authentifier Snyk avec le token du .env
	@echo "$(YELLOW)🔐 Authentification Snyk...$(NC)"
	@if [ -f ".env" ] && grep -q "^SNYK_TOKEN=" .env; then \
		SNYK_TOKEN=$$(grep "^SNYK_TOKEN=" .env | cut -d'=' -f2- | sed 's/^["'\'']//' | sed 's/["'\'']$$//'); \
		if [ -n "$$SNYK_TOKEN" ] && [ "$$SNYK_TOKEN" != "" ]; then \
			echo "$$SNYK_TOKEN" | snyk auth --stdin; \
			echo "$(GREEN)✓ Authentification Snyk réussie$(NC)"; \
		else \
			echo "$(YELLOW)⚠ SNYK_TOKEN vide dans .env$(NC)"; \
			echo "$(BLUE)→ Configurez votre token sur https://app.snyk.io/account$(NC)"; \
		fi; \
	else \
		echo "$(YELLOW)⚠ SNYK_TOKEN non trouvé dans .env$(NC)"; \
		echo "$(BLUE)→ Ajoutez SNYK_TOKEN=votre_token dans votre .env$(NC)"; \
	fi

.PHONY: security-setup-check
security-setup-check: ## Vérifier la configuration Snyk
	@echo "$(CYAN)🔧 Vérification de la configuration Snyk$(NC)"
	@if command -v snyk >/dev/null 2>&1; then \
		echo "$(GREEN)✓ Snyk CLI installé (version: $$(snyk --version))$(NC)"; \
	else \
		echo "$(RED)❌ Snyk CLI non installé$(NC)"; \
		echo "$(BLUE)→ Installez avec: make security-install$(NC)"; \
		exit 1; \
	fi
	@if [ -f "./scripts/security/snyk-scan.sh" ]; then \
		chmod +x "./scripts/security/snyk-scan.sh"; \
		./scripts/security/snyk-scan.sh --config; \
	else \
		echo "$(RED)❌ Script Snyk non trouvé$(NC)"; \
	fi

.PHONY: security-scan
security-scan: ## Scanner les vulnérabilités avec Snyk (complet)
	@echo "$(PURPLE)🛡️ Scan de sécurité complet avec Snyk$(NC)"
	@if [ -f "./scripts/security/snyk-scan.sh" ]; then \
		chmod +x "./scripts/security/snyk-scan.sh"; \
		./scripts/security/snyk-scan.sh; \
	else \
		echo "$(RED)❌ Script Snyk non trouvé: ./scripts/security/snyk-scan.sh$(NC)"; \
		echo "$(BLUE)→ Vérifiez que le script existe et est exécutable$(NC)"; \
		exit 1; \
	fi

.PHONY: security-scan-php
security-scan-php: ## Scanner uniquement les dépendances PHP
	@echo "$(PURPLE)🐘 Scan des dépendances PHP avec Snyk$(NC)"
	@if [ -f "./scripts/security/snyk-scan.sh" ]; then \
		chmod +x "./scripts/security/snyk-scan.sh"; \
		./scripts/security/snyk-scan.sh --php-only; \
	else \
		echo "$(RED)❌ Script Snyk non trouvé$(NC)"; \
		exit 1; \
	fi

.PHONY: security-scan-node
security-scan-node: ## Scanner uniquement les dépendances Node.js
	@echo "$(PURPLE)📦 Scan des dépendances Node.js avec Snyk$(NC)"
	@if [ -f "./scripts/security/snyk-scan.sh" ]; then \
		chmod +x "./scripts/security/snyk-scan.sh"; \
		./scripts/security/snyk-scan.sh --node-only; \
	else \
		echo "$(RED)❌ Script Snyk non trouvé$(NC)"; \
		exit 1; \
	fi

.PHONY: security-scan-docker
security-scan-docker: ## Scanner les images Docker avec Snyk
	@echo "$(PURPLE)🐳 Scan des images Docker avec Snyk$(NC)"
	@if [ -f "./scripts/security/snyk-scan.sh" ]; then \
		chmod +x "./scripts/security/snyk-scan.sh"; \
		./scripts/security/snyk-scan.sh --docker-only; \
	else \
		echo "$(RED)❌ Script Snyk non trouvé$(NC)"; \
		exit 1; \
	fi

.PHONY: security-scan-critical
security-scan-critical: ## Scanner uniquement les vulnérabilités critiques
	@echo "$(PURPLE)🚨 Scan des vulnérabilités critiques avec Snyk$(NC)"
	@if [ -f "./scripts/security/snyk-scan.sh" ]; then \
		chmod +x "./scripts/security/snyk-scan.sh"; \
		./scripts/security/snyk-scan.sh --severity critical; \
	else \
		echo "$(RED)❌ Script Snyk non trouvé$(NC)"; \
		exit 1; \
	fi

.PHONY: security-monitor
security-monitor: ## Activer le monitoring Snyk pour le projet
	@echo "$(CYAN)📊 Activation du monitoring Snyk...$(NC)"
	$(call check_container,$(PHP_CONTAINER_NAME))
	@if [ -f "src/composer.json" ]; then \
		echo "$(YELLOW)→ Monitoring des dépendances PHP...$(NC)"; \
		cd src && snyk monitor --file=composer.json; \
	fi
	@if [ -f "src/package.json" ]; then \
		echo "$(YELLOW)→ Monitoring des dépendances Node.js...$(NC)"; \
		cd src && snyk monitor --file=package.json; \
	fi
	@echo "$(GREEN)✓ Monitoring configuré$(NC)"
	@echo "$(BLUE)→ Consultez vos projets: https://app.snyk.io/projects$(NC)"

.PHONY: security-reports
security-reports: ## Afficher les derniers rapports de sécurité
	@echo "$(CYAN)📋 Rapports de sécurité Snyk$(NC)"
	@if [ -d "reports/security" ]; then \
		echo "$(YELLOW)📁 Rapports disponibles:$(NC)"; \
		ls -la reports/security/ | grep -E '\.(json|md)$$' | tail -10; \
		echo ""; \
		if [ -f "$$(ls -t reports/security/*.md 2>/dev/null | head -1)" ]; then \
			echo "$(CYAN)📄 Dernier rapport de synthèse:$(NC)"; \
			cat "$$(ls -t reports/security/*.md | head -1)"; \
		fi; \
	else \
		echo "$(YELLOW)⚠ Aucun rapport trouvé$(NC)"; \
		echo "$(BLUE)→ Lancez un scan: make security-scan$(NC)"; \
	fi

.PHONY: security-clean
security-clean: ## Nettoyer les anciens rapports de sécurité
	@echo "$(YELLOW)🧹 Nettoyage des rapports de sécurité...$(NC)"
	@if [ -d "reports/security" ]; then \
		find reports/security -name "*.json" -mtime +30 -delete 2>/dev/null || true; \
		find reports/security -name "*.md" -mtime +30 -delete 2>/dev/null || true; \
		echo "$(GREEN)✓ Rapports de plus de 30 jours supprimés$(NC)"; \
	else \
		echo "$(BLUE)→ Aucun répertoire de rapports à nettoyer$(NC)"; \
	fi

.PHONY: security-setup
security-setup: ## Configuration complète de Snyk
	@echo "$(CYAN)🛡️ Configuration complète de Snyk$(NC)"
	@echo "$(CYAN)================================$(NC)"
	@$(MAKE) security-install
	@echo ""
	@$(MAKE) security-auth
	@echo ""
	@$(MAKE) security-setup-check
	@echo ""
	@echo "$(GREEN)✅ Configuration Snyk terminée !$(NC)"
	@echo ""
	@echo "$(YELLOW)📋 Prochaines étapes :$(NC)"
	@echo "  $(GREEN)make security-scan$(NC)          - Lancer un scan complet"
	@echo "  $(GREEN)make security-monitor$(NC)       - Activer le monitoring"
	@echo "  $(GREEN)make security-reports$(NC)       - Voir les rapports"
	@echo ""
	@echo "$(BLUE)🔗 Ressources utiles :$(NC)"
	@echo "  • Dashboard Snyk: https://app.snyk.io/projects"
	@echo "  • Documentation: https://docs.snyk.io/"
	@echo "  • Token API: https://app.snyk.io/account"

# =============================================================================
# AIDE SÉCURITÉ
# =============================================================================

.PHONY: help-security
help-security: ## Aide pour les commandes de sécurité Snyk
	@echo "$(CYAN)🛡️ Commandes de Sécurité Snyk$(NC)"
	@echo "$(CYAN)==============================$(NC)"
	@echo ""
	@echo "$(YELLOW)🚀 Configuration initiale :$(NC)"
	@echo "  $(GREEN)make security-setup$(NC)         - Configuration complète (install + auth + check)"
	@echo "  $(GREEN)make security-install$(NC)       - Installer Snyk CLI"
	@echo "  $(GREEN)make security-auth$(NC)          - Authentifier avec le token .env"
	@echo "  $(GREEN)make security-setup-check$(NC)   - Vérifier la configuration Snyk"
	@echo ""
	@echo "$(YELLOW)🔍 Scans de sécurité :$(NC)"
	@echo "  $(GREEN)make security-scan$(NC)          - Scan complet (PHP + Node.js + Docker)"
	@echo "  $(GREEN)make security-scan-php$(NC)      - Scan des dépendances PHP uniquement"
	@echo "  $(GREEN)make security-scan-node$(NC)     - Scan des dépendances Node.js uniquement"
	@echo "  $(GREEN)make security-scan-docker$(NC)   - Scan des images Docker uniquement"
	@echo "  $(GREEN)make security-scan-critical$(NC) - Scan des vulnérabilités critiques uniquement"
	@echo ""
	@echo "$(YELLOW)📊 Monitoring et rapports :$(NC)"
	@echo "  $(GREEN)make security-monitor$(NC)       - Activer le monitoring continu"
	@echo "  $(GREEN)make security-reports$(NC)       - Afficher les derniers rapports"
	@echo "  $(GREEN)make security-clean$(NC)         - Nettoyer les anciens rapports"
	@echo ""
	@echo "$(YELLOW)⚙️ Configuration dans .env :$(NC)"
	@echo "  $(CYAN)SNYK_TOKEN$(NC)                  - Token d'authentification Snyk"
	@echo "  $(CYAN)SNYK_SEVERITY_THRESHOLD$(NC)     - Seuil de sévérité (low|medium|high|critical)"
	@echo "  $(CYAN)SNYK_FAIL_ON_ISSUES$(NC)         - Faire échouer en cas de vulnérabilités"
	@echo "  $(CYAN)SNYK_MONITOR_ENABLED$(NC)        - Activer le monitoring automatique"
	@echo "  $(CYAN)SNYK_ORG_ID$(NC)                 - ID de votre organisation Snyk"
	@echo ""
	@echo "$(YELLOW)💡 Workflow recommandé :$(NC)"
	@echo "  1. $(GREEN)make security-setup$(NC)      - Configuration initiale"
	@echo "  2. $(GREEN)make security-scan$(NC)       - Premier scan complet"
	@echo "  3. $(GREEN)make security-monitor$(NC)    - Activer le monitoring"
	@echo "  4. Intégrer dans votre CI/CD"
	@echo ""
	@echo "$(BLUE)🔗 Liens utiles :$(NC)"
	@echo "  • Dashboard: https://app.snyk.io/projects"
	@echo "  • Token API: https://app.snyk.io/account"
	@echo "  • Documentation: https://docs.snyk.io/"
# =============================================================================
# GESTION DES IMAGES DOCKER CUSTOM
# =============================================================================

# Mise à jour des images custom (alternative à Watchtower)
update-images:
	@echo "$(YELLOW)🔄 Mise à jour des images Docker custom...$(NC)"
	@bash $(SCRIPT_DIR)/update-custom-images.sh

# Vérification des mises à jour disponibles
check-image-updates:
	@echo "$(BLUE)🔍 Vérification des mises à jour disponibles...$(NC)"
	@bash $(SCRIPT_DIR)/update-custom-images.sh --check-only

# Configuration de la mise à jour automatique
setup-auto-update:
	@echo "$(YELLOW)⚙️ Configuration de la mise à jour automatique...$(NC)"
	@bash $(SCRIPT_DIR)/setup-auto-update.sh

# Rebuild force de toutes les images custom
rebuild-all-images:
	@echo "$(YELLOW)🔨 Reconstruction forcée de toutes les images...$(NC)"
	@$(DOCKER_COMPOSE) build --pull --no-cache php apache node
	@$(DOCKER_COMPOSE) up -d

# Nettoyage des anciennes images
clean-images:
	@echo "$(YELLOW)🧹 Nettoyage des anciennes images...$(NC)"
	@docker image prune -f
	@docker builder prune -f

# Status des images et conteneurs
images-status:
	@echo "$(BLUE)📊 Status des images Docker :$(NC)"
	@echo ""
	@echo "$(YELLOW)Images custom :$(NC)"
	@docker images | grep -E "(laravel-app|php|apache|node)" | head -10 || echo "Aucune image custom trouvée"
	@echo ""
	@echo "$(YELLOW)Conteneurs actifs :$(NC)" 
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
	@echo ""
	@echo "$(YELLOW)Utilisation disque :$(NC)"
	@docker system df

