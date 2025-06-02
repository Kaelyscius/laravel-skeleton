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
NC = \033[0m

.PHONY: help
help: ## Afficher l'aide
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

## 🚀 Installation et Build
.PHONY: install
install: build up install-laravel npm-install setup-ssl ## Installation complète du projet
	@echo "$(GREEN)✓ Installation terminée !$(NC)"
	@echo "$(YELLOW)→ Accédez à l'application : https://laravel.local$(NC)"
	@echo "$(YELLOW)→ MailHog : http://localhost:8025$(NC)"
	@echo "$(YELLOW)→ Adminer : http://localhost:8080$(NC)"
	@echo "$(YELLOW)→ IT Tools : http://localhost:8081$(NC)"
	@echo "$(YELLOW)→ Dozzle (logs) : http://localhost:9999$(NC)"
	@echo "$(BLUE)→ Pour builder les assets : make npm-build$(NC)"
	@echo "$(BLUE)→ Pour lancer le dev server : make npm-dev$(NC)"

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
install-laravel: ## Installer Laravel
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

## 🧪 Tests et Qualité
.PHONY: test
test: ## Lancer tous les tests
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan test

.PHONY: test-coverage
test-coverage: ## Lancer les tests avec couverture
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) php artisan test --coverage

.PHONY: phpstan
phpstan: ## Lancer PHPStan
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) ./vendor/bin/phpstan analyse

.PHONY: larastan
larastan: ## Lancer Larastan
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) ./vendor/bin/phpstan analyse --configuration=phpstan.neon

.PHONY: ecs
ecs: ## Vérifier le code style avec ECS
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) ./vendor/bin/ecs check

.PHONY: ecs-fix
ecs-fix: ## Corriger le code style avec ECS
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) ./vendor/bin/ecs check --fix

.PHONY: rector
rector: ## Lancer Rector (dry-run)
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) ./vendor/bin/rector process --dry-run

.PHONY: rector-fix
rector-fix: ## Appliquer les corrections Rector
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) ./vendor/bin/rector process

.PHONY: quality
quality: ecs phpstan test ## Lancer tous les outils de qualité

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

.PHONY: prune
prune: ## Nettoyer le système Docker
	@$(DOCKER) system prune -af --volumes

## 🔐 SSL
.PHONY: setup-ssl
setup-ssl: ## Générer les certificats SSL auto-signés
	@echo "$(YELLOW)Generating SSL certificates...$(NC)"
	@./docker/scripts/generate-ssl.sh
	@echo "$(GREEN)✓ SSL certificates generated$(NC)"

## 📊 Monitoring
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
		echo "$(BLUE)=== Recherche globale de package.json ===$(NC)"; \
		docker exec $(NODE_CONTAINER_NAME) find /var/www -name "package.json" -type f 2>/dev/null || echo "Aucun package.json trouvé"; \
	else \
		echo "$(RED)✗ Container Node non disponible$(NC)"; \
	fi

## 🔄 Mise à jour
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
	@echo "$(YELLOW)Checking security vulnerabilities...$(NC)"
	@$(DOCKER) exec -u 1000:1000 $(PHP_CONTAINER) composer audit || echo "$(YELLOW)⚠ Composer audit not available$(NC)"
	@if docker exec $(NODE_CONTAINER_NAME) test -f /var/www/html/package.json; then \
		docker exec -u 1000:1000 $(NODE_CONTAINER_NAME) npm audit || echo "$(YELLOW)⚠ NPM vulnerabilities found$(NC)"; \
	elif docker exec $(NODE_CONTAINER_NAME) test -f /var/www/project/package.json; then \
		docker exec -u 1000:1000 -w /var/www/project $(NODE_CONTAINER_NAME) npm audit || echo "$(YELLOW)⚠ NPM vulnerabilities found$(NC)"; \
	fi