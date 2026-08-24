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
POSTGRES_CONTAINER = $$(docker ps -qf "name=$(COMPOSE_PROJECT_NAME)_postgres")

# Containers par nom
PHP_CONTAINER_NAME = $(COMPOSE_PROJECT_NAME)_php

# =============================================================================
# ⛔ L'UID DU CONTENEUR EST CELUI DE L'HÔTE — ET C'EST STRUCTUREL, PAS UN RÉGLAGE
# =============================================================================
# 🔴 CE QUI A ÉTÉ MESURÉ, ET DEUX FOIS PLUTÔT QU'UNE. L'arbre `./src` est
# bind-monté : il est écrit par DEUX écrivains, le conteneur php (qui tournait en
# `1000:1000` codé en dur) et l'hôte (`scripts/install-lockfile.sh` n'a aucun
# `docker exec`). Sur la machine de développement l'hôte EST 1000 : les deux
# coïncident, et rien ne se voit. Sur un runner GitHub l'hôte est **1001**, et
# alors UN SEUL des deux peut posséder l'arbre :
#   • avec le `chown` large de l'entrypoint, l'arbre passait à 1000 et
#     l'installeur écrivait — mais l'hôte perdait son `mktemp` (run 32742873104) ;
#   • sans lui, l'hôte gardait l'arbre et c'est l'installeur qui ne pouvait plus
#     écrire (run 32745286801, échec dès l'étape 1/5).
# Les deux pansements se contredisent. Aucun réglage du `chown` ne les concilie :
# le conflit est dans les uid, il se règle dans les uid.
#
# ⚖️ ON ALIGNE DONC L'UID DU CONTENEUR SUR CELUI DE L'HÔTE. Il n'y a plus deux
# propriétaires possibles, il n'y en a qu'un — le conflit disparaît par
# construction plutôt que par arbitrage.
#
# ⚠️ DÉFAUT 1000 PARTOUT SI LA VARIABLE EST ABSENTE : sur un hôte en uid 1000
# — la configuration WSL2/PhpStorm documentée — le comportement est
# STRICTEMENT INCHANGÉ, et les images déjà construites restent valides.
# `export` est indispensable : c'est par l'environnement que Compose interpole
# `${HOST_UID}` dans les `args:` de build.
HOST_UID := $(shell id -u)
HOST_GID := $(shell id -g)
export HOST_UID
export HOST_GID

# L'utilisateur passé à `docker exec`. Une seule définition : les 43 sites qui
# portaient l'utilisateur en dur ne pouvaient pas suivre l'hôte, et aucun test
# ne pouvait le dire puisque l'hôte de développement vaut précisément 1000.
DOCKER_USER = $(HOST_UID):$(HOST_GID)

# Patience du redémarrage post-installation (voir `post-install-restart-php`).
# Surchargeables en ligne de commande — c'est par là que les tests réduisent
# l'attente à zéro plutôt que de dupliquer la boucle dans une fixture.
PHP_RESTART_ATTEMPTS ?= 90
PHP_RESTART_DELAY ?= 2

# Témoin écrit par l'entrypoint À CHAQUE passage complet dans sa branche
# « bootable ». Il vit DANS le conteneur — surtout pas sous `./src`, qui est
# bind-monté et dont le contenu survivrait au redémarrage qu'on veut mesurer.
PHP_BOOTABLE_MARKER ?= /tmp/laravel-entrypoint-bootable
APACHE_CONTAINER_NAME = $(COMPOSE_PROJECT_NAME)_apache
NODE_CONTAINER_NAME = $(COMPOSE_PROJECT_NAME)_node
POSTGRES_CONTAINER_NAME = $(COMPOSE_PROJECT_NAME)_postgres
BROWSER_CONTAINER_NAME = $(COMPOSE_PROJECT_NAME)_test_browser

# Borne dure des tests navigateur, en secondes. Voir ADR-0013 : le plugin Pest
# ne rend pas toujours la main après la fin des tests.
BROWSER_TEST_TIMEOUT ?= 300

# =============================================================================
# DRAPEAUX DE SIMULATION ET DE REPRISE — PASS-THROUGH VERS scripts/install.sh
# =============================================================================
#
# `--dry-run` et `--resume-from` EXISTENT dans `scripts/install.sh` depuis
# longtemps ; ce qui manquait, c'est une porte d'entrée `make`. Sans elle, un
# fork-streamer doit connaître le chemin du script — et le chemin réel passe par
# `docker exec … /var/www/project/scripts/install.sh`, ce que personne ne tape
# de tête.
#
#   make install-laravel DRY_RUN=true
#   make install-laravel DRY_RUN=true RESUME_FROM=20-database
#   make install-laravel RESUME_FROM=30-packages-prod
#
# ⚠️ Le plan est réparti sur STDOUT et STDERR : capture complète avec
# `> plan.txt 2>&1` ou `2>&1 | tee plan.txt`.

EMPTY :=
SPACE := $(EMPTY) $(EMPTY)

DRY_RUN_VALUE := $(strip $(DRY_RUN))
RESUME_FROM_VALUE := $(strip $(RESUME_FROM))

# 🔴 TOUTE LA VALIDATION EST PORTÉE PAR LES CIBLES, JAMAIS ÉVALUÉE AU PARSE
# GLOBAL. `DRY_RUN` et `RESUME_FROM` sont des noms GÉNÉRIQUES : exportés dans le
# shell de l'opérateur (ou hérités d'un CI), une validation inconditionnelle
# faisait sortir en 2 des cibles qui n'ont rien à voir — mesuré :
# `DRY_RUN=1 make help` et `RESUME_FROM=x make status` tuaient le Makefile
# entier. Le bloc ci-dessous ne s'ouvre QUE si l'une des deux variables est
# posée, et ne refuse QUE sur une cible d'installation (même discipline que le
# garde composite, qui filtrait déjà `MAKECMDGOALS`).
#
# Effet de bord voulu : quand ni l'une ni l'autre n'est posée — le cas de
# `make test`, `make up`, `make help` — RIEN ci-dessous n'est expansé, donc ni
# le `sed` des modules ni l'`awk` du graphe ne tournent.
ifneq ($(DRY_RUN_VALUE)$(RESUME_FROM_VALUE),)

# Points d'entrée qui relaient réellement les drapeaux à `install.sh`.
INSTALL_ENTRYPOINTS := install-laravel install-laravel-prod

# ⛔ LES CHAÎNES COMPOSITES SONT DÉRIVÉES DU GRAPHE DE DÉPENDANCES, PAS ÉNUMÉRÉES.
# 🔴 Mesuré : avec une liste écrite à la main, ajouter au Makefile
# `install-dev-turbo: build up-dev install-laravel npm-install` produisait une
# cible ACCEPTÉE sous `DRY_RUN=true` — elle bâtit des images, démarre des
# conteneurs, puis lance une « simulation » — et la suite restait VERTE. Une
# énumération ne peut pas garder ce qu'elle ne connaît pas.
#
# Règle : est composite toute cible dont les prérequis contiennent À LA FOIS un
# `build*`/`up*` et un `install-laravel*` — ou un prérequis lui-même composite
# (les alias `install: install-dev` doivent suivre). La fermeture transitive est
# obtenue en repassant cinq fois sur le graphe, ce qui couvre très largement la
# profondeur réelle (2).
#
# ⚠️ LA DÉRIVATION NE VOIT QUE LES PRÉREQUIS. Une cible qui appelle
# `$(MAKE) install-laravel` depuis sa RECETTE est invisible du graphe : celles-là
# sont listées à la main, et cette liste-ci est courte parce qu'elle est le
# résidu, pas la règle.
COMPOSITE_RECIPE_TARGETS := install-incremental

COMPOSITE_INSTALL_TARGETS = $(sort $(COMPOSITE_RECIPE_TARGETS) $(shell awk ' \
	/^[A-Za-z0-9_.\/-]+[ \t]*:[^=]/ { \
		line = $$0; sub(/#.*/, "", line); \
		idx = index(line, ":"); \
		tgt = substr(line, 1, idx - 1); gsub(/[ \t]/, "", tgt); \
		deps[tgt] = substr(line, idx + 1); \
		if (!(tgt in seen)) { seen[tgt] = 1; order[++n] = tgt } \
	} \
	END { \
		for (pass = 1; pass <= 5; pass++) { \
			for (i = 1; i <= n; i++) { \
				t = order[i]; c = split(deps[t], p, /[ \t]+/); b = 0; inst = 0; \
				for (j = 1; j <= c; j++) { \
					if (p[j] ~ /^(build|up)/) b = 1; \
					if (p[j] ~ /^install-laravel/) inst = 1; \
					if (p[j] in comp) { b = 1; inst = 1 } \
				} \
				if (b && inst) comp[t] = 1; \
			} \
		} \
		for (t in comp) print t; \
	}' $(firstword $(MAKEFILE_LIST))))

INSTALL_GOALS = $(filter $(INSTALL_ENTRYPOINTS) $(COMPOSITE_INSTALL_TARGETS),$(MAKECMDGOALS))

ifneq ($(strip $(INSTALL_GOALS)),)

# ⛔ `DRY_RUN` EST VALIDÉE PAR COMPARAISON LITTÉRALE, PAS PAR `$(filter)`.
# 🔴 `$(filter $(V),true false)` traite `%` comme un JOKER : `DRY_RUN=%` passait
# la validation, puis n'était égal ni à `true` ni à `false` — donc installation
# RÉELLE, en silence, sous un drapeau que l'opérateur croyait posé. `ifeq` est
# une égalité de chaînes, sans motif.
# Et sans validation du tout, `DRY_RUN=1`, `yes` ou `TRUE` faisaient exactement
# la même chose : le pire mode de défaillance possible pour ce drapeau —
# silencieux, et dans le sens destructeur.
ifeq ($(DRY_RUN_VALUE),true)
else ifeq ($(DRY_RUN_VALUE),false)
else ifeq ($(DRY_RUN_VALUE),)
else
$(error DRY_RUN=« $(DRY_RUN) » invalide sur « $(INSTALL_GOALS) » — seules « true » et « false » sont acceptées. Une valeur comme 1, yes, TRUE ou % serait interprétée comme « pas de simulation » et lancerait une INSTALLATION RÉELLE en silence.)
endif

# ⛔ `RESUME_FROM` EST VALIDÉE CONTRE LA LISTE RÉELLE DES MODULES, LUE SUR DISQUE.
# Trois raisons, et aucune n'est cosmétique :
#   • la valeur est interpolée dans `docker exec … bash -c "… install.sh …"`,
#     donc dans une chaîne passée à un shell : n'accepter qu'un identifiant
#     connu ferme la question du quoting plutôt que de la déplacer ;
#   • une liste RÉÉCRITE ici en dur divergerait d'`INSTALL_MODULES` au premier
#     module ajouté ou renommé, sans que rien ne rougisse. Elle est donc
#     EXTRAITE de `scripts/install.sh`, comme `ShellProbe::installModules()` le
#     fait côté tests ;
#   • l'appartenance est testée par `findstring` sur une liste DÉLIMITÉE, pas
#     par `$(filter)` : là encore, `RESUME_FROM=%` passait le filtre.
# ⚠️ Affectation RÉCURSIVE (`=`) : le `sed` ne tourne que si la valeur est posée.
INSTALL_MODULE_IDS = $(shell sed -n '/^readonly INSTALL_MODULES=(/,/^)/p' $(SCRIPT_DIR)/install.sh \
	| sed -n 's/^[[:space:]]*"\([^":]*\):.*/\1/p')

ifneq ($(RESUME_FROM_VALUE),)
ifeq ($(strip $(INSTALL_MODULE_IDS)),)
$(error RESUME_FROM=« $(RESUME_FROM) » ne peut pas être validé : la liste INSTALL_MODULES n'a pas pu être lue dans $(SCRIPT_DIR)/install.sh. Refus plutôt que passage à l'aveugle.)
endif
ifeq ($(findstring |$(RESUME_FROM_VALUE)|,|$(subst $(SPACE),|,$(INSTALL_MODULE_IDS))|),)
$(error RESUME_FROM=« $(RESUME_FROM) » n'est pas un module connu. Modules valides : $(INSTALL_MODULE_IDS))
endif
ifneq ($(filter install-laravel-prod install-prod install-prod-fast,$(MAKECMDGOALS)),)
$(error RESUME_FROM n'a pas de sens sur « $(filter install-laravel-prod install-prod install-prod-fast,$(MAKECMDGOALS)) » : cette cible enchaîne cinq « install.sh --only <module> », et « --only X --resume-from Y » est contradictoire. Utilisez : make install-laravel RESUME_FROM=$(RESUME_FROM_VALUE))
endif
endif

# ⛔ `DRY_RUN=true` SUR UNE CHAÎNE COMPOSITE EST REFUSÉ, BRUYAMMENT ET TÔT.
# `install-dev-full` et ses cousines ont `build up-dev-full …` en PRÉREQUIS :
# make les exécute AVANT toute recette, donc un garde posé dans le corps de la
# règle arriverait après la construction des images et le démarrage des
# conteneurs — exactement les effets de bord que `--dry-run` promet d'éviter.
# Le refus est évalué à l'ANALYSE du Makefile : `$(error)` sort non-0 sans avoir
# rien lancé.
ifeq ($(DRY_RUN_VALUE),true)
ifneq ($(filter $(COMPOSITE_INSTALL_TARGETS),$(MAKECMDGOALS)),)
$(error DRY_RUN=true n'est pas supporté par « $(filter $(COMPOSITE_INSTALL_TARGETS),$(MAKECMDGOALS)) » : cette chaîne BÂTIT des images et DÉMARRE des conteneurs avant d'atteindre install.sh — une simulation n'y simulerait rien. Utilisez plutôt : make install-laravel DRY_RUN=true [RESUME_FROM=<module>])
endif
endif

endif
endif

# Drapeaux relayés à l'invocation NOMINALE d'`install.sh` (`install-laravel`).
INSTALL_FLAGS :=

ifeq ($(DRY_RUN_VALUE),true)
INSTALL_FLAGS += --dry-run
endif

ifneq ($(RESUME_FROM_VALUE),)
INSTALL_FLAGS += --resume-from $(RESUME_FROM_VALUE)
endif

# Drapeaux relayés aux invocations `--only` (`install-laravel-prod`).
# ⛔ JAMAIS `--resume-from` : `--only X --resume-from Y` est une combinaison
# contradictoire dont la précédence n'est spécifiée nulle part. La cible entière
# est refusée plus haut ; ce tableau distinct est la ceinture de cette bretelle.
INSTALL_ONLY_FLAGS :=

ifeq ($(DRY_RUN_VALUE),true)
INSTALL_ONLY_FLAGS += --dry-run
endif

# Colors
GREEN = \033[0;32m
YELLOW = \033[0;33m
RED = \033[0;31m
BLUE = \033[0;34m
PURPLE = \033[0;35m
CYAN = \033[0;36m
NC = \033[0m

# ⛔ CE MAKEFILE N'EST PAS PARALLÉLISABLE, ET C'EST DÉCLARÉ PLUTÔT QUE SUPPOSÉ.
# Les chaînes d'installation reposent sur l'ORDRE de leurs prérequis — `setup-ssl`
# avant tout `up*` (apache sort en 1 sans certificats), `install-laravel` avant
# `post-install-restart-php` (redémarrer avant l'install rejouerait un état sans
# `vendor/`), `npm-install` avant `install-lockfile`. Deux gardes assertent cet
# ordre ; or `make -j` ne garantit RIEN sur l'ordre des prérequis, si bien que
# les gardes resteraient verts pendant que l'installation partirait en désordre.
# `.NOTPARALLEL` rend la contrainte exécutable au lieu de la laisser à la
# discipline de l'opérateur. Gardé par `InstallSentinelsTest`.
.NOTPARALLEL:

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
		docker exec -u $(DOCKER_USER) -w $(NPM_PATH) $(NODE_CONTAINER_NAME) npm $(1); \
	else \
		docker exec -u $(DOCKER_USER) $(NODE_CONTAINER_NAME) npm $(1); \
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

# =============================================================================
# ⛔ `setup-ssl` PASSE AVANT TOUT `up-*` — ET CE N'EST PAS COSMÉTIQUE.
# =============================================================================
# `docker/apache/scripts/docker-entrypoint.sh:23-33` sort en **1** quand
# `laravel.local.crt` / `.key` manquent. `setup-ssl` était le DERNIER prérequis
# de ces chaînes : sur un clone neuf, apache démarrait donc systématiquement
# sans certificats, échouait, et `restart: unless-stopped` le rebouclait pendant
# toute l'installation. Le script est purement HÔTE (openssl + écriture dans
# `docker/apache/conf/ssl/`) : il n'a besoin d'aucun conteneur, rien ne
# justifiait qu'il vienne après eux.
# ⚠️ `npm-install` → `install-lockfile` reste dans cet ordre, et les chaînes
# prod restent sans `install-lockfile` (gardé par InstallSentinelsTest).
#
# =============================================================================
# ⛔ `post-install-restart-php` PASSE JUSTE APRÈS L'INSTALL LARAVEL — ET SANS LUI
#    UNE INSTALL DE CLONE NEUF EST INCOMPLÈTE *EN RESTANT VERTE*.
# =============================================================================
# Sur un clone neuf, `vendor/` est absent au démarrage : l'entrypoint php part
# en état « sans-vendor », démarre php-fpm et — c'est tout son objet — ne joue
# AUCUNE commande artisan. `install-laravel` peuple ensuite `vendor/`… mais rien
# ne repasse par l'entrypoint, donc sa branche « bootable » n'est jamais
# atteinte de toute l'installation.
#
# 🔴 LA CONSÉQUENCE DÉPASSE LES CACHES. `php artisan storage:link` n'existe qu'à
# UN SEUL endroit du dépôt — `docker/php/scripts/docker-entrypoint.sh`, branche
# « bootable ». Aucun module d'installation ne le joue. Une install de clone
# neuf ne créait donc JAMAIS le lien `public/storage`, et comme `/health` ne le
# regarde pas, le nightly pouvait conclure VERT sur une application incomplète :
# exactement la classe de défaut que cet epic existe pour interdire.
#
# ⚖️ ON REDÉMARRE PLUTÔT QUE DE DUPLIQUER. Rejouer `storage:link` + les clears
# depuis un module d'installation créerait un second endroit où cette logique
# vit, donc deux vérités capables de diverger. Le message que l'entrypoint
# imprime déjà en « sans-vendor » PROMET un rejeu au prochain démarrage : on
# rend la promesse vraie. Et le redémarrage est idempotent — `storage:link` est
# gardé par `[ ! -L … ]`, `horizon:publish` par la présence du paquet — donc
# rejouer une chaîne d'installation ne régresse pas l'idempotence de la 2.2.
# ⚠️ La fatalité du chemin non-dev est INCHANGÉE : si `proxies:check` refuse au
# redémarrage, le conteneur meurt et cette cible échoue en le disant.
#
# 🔴 ET LA LISTE DES CHAÎNES CONCERNÉES N'EST PLUS ÉCRITE À LA MAIN. Le premier
# jet en câblait CINQ ; `make` en dérive NEUF. Deux manquaient, et pas des
# théoriques : `setup-quick` (juste au-dessus) et la branche `else` de
# `install-incremental` lancent toutes deux l'installeur contre un conteneur
# parti en « sans-vendor », sans jamais le redémarrer — donc `public/storage`
# jamais créé, donc l'installation incomplète-mais-verte que cette story existe
# pour rendre impossible. Le garde est désormais piloté par
# `ShellProbe::makefileComposites()`, exactement comme le commentaire de
# `COMPOSITE_INSTALL_TARGETS` le prescrit : « une énumération ne peut pas garder
# ce qu'elle ne connaît pas ».
# =============================================================================

# Installation développement (avec Node et tous les outils)
.PHONY: install
install: install-dev ## Alias pour install-dev (par défaut en développement)

.PHONY: install-dev
install-dev: build setup-ssl up-dev install-laravel post-install-restart-php npm-install install-lockfile ## Installation complète DÉVELOPPEMENT (avec Node, Mailpit, Adminer, etc.)
	@echo "$(GREEN)🎉 Installation DÉVELOPPEMENT terminée !$(NC)"
	@echo "$(CYAN)📦 Services actifs: PHP, Apache, PostgreSQL, Redis, Node, Mailpit, Adminer$(NC)"
	@$(MAKE) _show_urls

.PHONY: install-dev-full
install-dev-full: build setup-ssl up-dev-full install-laravel post-install-restart-php npm-install install-lockfile ## Installation DÉVELOPPEMENT COMPLÈTE (+ Dozzle, IT-Tools, Watchtower)
	@echo "$(GREEN)🎉 Installation DÉVELOPPEMENT COMPLÈTE terminée !$(NC)"
	@echo "$(CYAN)📦 Services actifs: Tous les services + monitoring$(NC)"
	@$(MAKE) _show_urls

# Installation production (sans Node ni outils dev)
.PHONY: install-prod
install-prod: build setup-ssl up install-laravel-prod post-install-restart-php ## Installation PRODUCTION (services essentiels uniquement)
	@echo "$(GREEN)🎉 Installation PRODUCTION terminée !$(NC)"
	@echo "$(CYAN)📦 Services actifs: PHP, Apache, PostgreSQL, Redis$(NC)"
	@echo "$(YELLOW)⚠️  Node, Mailpit, Adminer NON démarrés (profil dev désactivé)$(NC)"
	@$(MAKE) _show_urls

# Versions rapides avec cache
.PHONY: install-fast
install-fast: install-dev-fast ## Alias pour install-dev-fast

.PHONY: install-dev-fast
install-dev-fast: build-fast setup-ssl up-dev install-laravel post-install-restart-php npm-install-fast install-lockfile ## Installation DEV optimisée avec cache (recommandé)
	@echo "$(GREEN)🎉 Installation DÉVELOPPEMENT rapide terminée !$(NC)"
	@$(MAKE) _show_urls

.PHONY: install-prod-fast
install-prod-fast: build-fast setup-ssl up install-laravel-prod post-install-restart-php ## Installation PROD optimisée avec cache
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
		$(MAKE) post-install-restart-php; \
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
setup-quick: up install-laravel post-install-restart-php ## Installation rapide sans SSL
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
#   - AUCUN       : Production (apache, php, postgres, redis)
#   - dev         : Outils développement (node, mailpit, adminer)
#   - tools       : Utilitaires (dozzle, it-tools, watchtower)
#   - dev-extra   : Outils additionnels (redis-commander)
# =============================================================================

.PHONY: up-prod
up-prod: ## Production - Services essentiels uniquement (apache, php, postgres, redis)
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
up-dev-extra: ## Développement avec outils extra (+ redis-commander)
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
	@docker ps --filter "name=apache" --filter "name=php" --filter "name=postgres" --filter "name=redis$$" --format "  ✓ {{.Names}}" 2>/dev/null | grep . || echo "  ○ Aucun"
	@echo ""
	@echo "$(YELLOW)🛠️  DEV (profile: dev):$(NC)"
	@docker ps --filter "name=node" --filter "name=mailpit" --filter "name=adminer" --format "  ✓ {{.Names}}" 2>/dev/null | grep . || echo "  ○ Aucun"
	@echo ""
	@echo "$(YELLOW)🔧 TOOLS (profile: tools):$(NC)"
	@docker ps --filter "name=dozzle" --filter "name=it-tools" --filter "name=watchtower" --format "  ✓ {{.Names}}" 2>/dev/null | grep . || echo "  ○ Aucun"
	@echo ""
	@echo "$(YELLOW)➕ DEV-EXTRA (profile: dev-extra):$(NC)"
	@docker ps --filter "name=redis_commander" --format "  ✓ {{.Names}}" 2>/dev/null | grep . || echo "  ○ Aucun"

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

.PHONY: post-install-restart-php
post-install-restart-php: ## Redémarrer php après l'install pour rejouer clears + storage:link
	@echo "$(CYAN)🔄 Redémarrage du conteneur PHP — l'entrypoint doit rejouer sa branche « bootable »...$(NC)"
	@$(DOCKER) exec $(PHP_CONTAINER_NAME) rm -f $(PHP_BOOTABLE_MARKER) > /dev/null 2>&1 || { \
		echo "$(RED)❌ Impossible d'EFFACER le témoin dans $(PHP_CONTAINER_NAME) avant le redémarrage.$(NC)"; \
		echo "$(YELLOW)   Le conteneur ne répond pas à « docker exec » — il est absent, arrêté, ou déjà$(NC)"; \
		echo "$(YELLOW)   en boucle de redémarrage. Sans effacement, tout vestige passerait pour un$(NC)"; \
		echo "$(YELLOW)   témoin neuf : on REFUSE de mesurer plutôt que de mesurer faux.$(NC)"; \
		echo "$(YELLOW)   Diagnostic : make logs service=php$(NC)"; \
		exit 1; \
	}
	@$(DOCKER) restart $(PHP_CONTAINER_NAME) > /dev/null || { \
		echo "$(RED)❌ Redémarrage impossible : $(PHP_CONTAINER_NAME) est introuvable ou refuse de repartir.$(NC)"; \
		echo "$(YELLOW)   L'installation ne peut pas être déclarée complète. Diagnostic : make logs service=php$(NC)"; \
		exit 1; \
	}
	@echo "$(YELLOW)   Attente d'un témoin FRAIS, pas d'un délai ni d'un vestige...$(NC)"
	@attempt=1; \
	while [ "$$attempt" -le "$(PHP_RESTART_ATTEMPTS)" ]; do \
		obtenu="$$($(DOCKER) exec $(PHP_CONTAINER_NAME) cat $(PHP_BOOTABLE_MARKER) 2>/dev/null || true)"; \
		if [ -n "$$obtenu" ]; then \
			echo "$(GREEN)✓ L'entrypoint a rejoué sa branche « bootable » jusqu'au bout (témoin renouvelé)$(NC)"; \
			exit 0; \
		fi; \
		sleep $(PHP_RESTART_DELAY); \
		attempt=$$((attempt + 1)); \
	done; \
	echo "$(RED)❌ Le témoin de démarrage n'a PAS été réécrit après le redémarrage.$(NC)"; \
	echo "$(YELLOW)   L'entrypoint n'a pas atteint la fin de sa branche « bootable » : l'installation est INCOMPLÈTE.$(NC)"; \
	echo "$(YELLOW)   Causes possibles : dépendances non installées, application non bootable, ou$(NC)"; \
	echo "$(YELLOW)   « proxies:check » qui refuse de démarrer hors local. Diagnostic : make logs service=php$(NC)"; \
	exit 1
# ⛔ CE QU'ON ATTEND EST UNE POST-CONDITION, PAS UNE DURÉE — ET C'EST LA
#    DEUXIÈME RÉDACTION.
#
# 🔴 LA PREMIÈRE MENTAIT SUR TOUTE RÉEXÉCUTION. Elle attendait l'apparition de
# `public/storage`. Or `./src` est bind-monté (`docker-compose.yml`) et ce lien
# est créé sur l'HÔTE : il survit au conteneur. Dès la deuxième exécution — la
# machine d'un développeur, et le test d'idempotence du E2E — le tout premier
# sondage réussissait et la cible imprimait « ✓ Entrypoint rejoué » sans avoir
# rien mesuré. Elle ne disait vrai que sur un clone neuf, c'est-à-dire une fois.
#
# ⚖️ LE TÉMOIN EST DONC FRAIS PAR CONSTRUCTION — ET C'EST LA TROISIÈME
# RÉDACTION, parce que la deuxième laissait encore passer le vestige DANS LE
# CAS QUI COMPTE (2ᵉ revue). Elle RELEVAIT la valeur d'avant puis comparait :
# si ce relevé échouait, la valeur attendue devenait VIDE et n'importe quel
# vestige non vide satisfaisait « différent de attendu » dès le premier
# sondage. Or ce relevé échoue précisément quand le conteneur BOUCLE EN
# REDÉMARRAGE — la panne même que cette cible existe pour attraper. La
# post-condition n'était donc vraie que lorsque tout allait déjà bien.
#
# ⛔ ON EFFACE PLUTÔT QUE DE COMPARER. Le témoin est SUPPRIMÉ avant le
# redémarrage, et l'échec de cette suppression est FATAL : ne pas pouvoir
# établir la pré-condition, c'est ne pas pouvoir vérifier la post-condition —
# on refuse de mesurer au lieu de mesurer faux. Après quoi « le fichier existe
# et n'est pas vide » ne peut plus vouloir dire qu'une chose : l'entrypoint
# vient de le réécrire.
# ⚠️ Et il est écrit par l'entrypoint en DERNIÈRE LIGNE AVANT `exec` — pas en
# fin de branche : `mkdir -p` du répertoire supervisor, fatal sous `set -e`,
# vit entre les deux.
# ⚠️ Et l'échec est FATAL. Un `|| true` ici rendrait la chaîne verte sur
# exactement l'état qu'elle est chargée de rendre impossible.

.PHONY: install-laravel
install-laravel: ## Installer Laravel complet [DRY_RUN=true] [RESUME_FROM=<module>] (packages + permissions + MCP)
	$(call check_container,$(PHP_CONTAINER_NAME))
	@echo "$(CYAN)🚀 Installation Laravel 12 + PHP 8.5...$(NC)"
	@echo ""
	@echo "$(BLUE)━━━ Étape 1/5 : Installation des packages et configuration ━━━$(NC)"
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) bash -c "cd /var/www/html && /var/www/project/scripts/install.sh $(INSTALL_FLAGS)"
# ⛔ SOUS SIMULATION, LA RECETTE S'ARRÊTE ICI — ET C'EST LE MÊME RAISONNEMENT
# QUE POUR LES CHAÎNES COMPOSITES, MOT POUR MOT (relevé revue 1).
# `DRY_RUN=true` n'atteignait que l'étape 1/5. Les étapes 2 à 5 s'exécutaient
# ensuite POUR DE VRAI sur l'application de l'opérateur : `chown -R
# www-data:www-data /var/www/html`, deux `find -exec chmod 775/664`,
# `chmod +x artisan`, `chmod -R 775 storage bootstrap/cache`, puis
# `fix-permissions-host` EN SUDO côté hôte. La porte d'entrée `make` de cette
# story réintroduisait donc exactement la classe d'effet de bord qu'elle venait
# de retirer de `validate_arguments`.
#
# ⚠️ Le branchement est fait à l'ANALYSE, pas dans le shell de la recette : un
# `exit 0` dans une ligne de recette ne sort que de CETTE ligne, les suivantes
# tournent quand même. Sous `DRY_RUN=true`, les lignes ci-dessous n'existent
# tout simplement pas dans la recette.
ifeq ($(DRY_RUN_VALUE),true)
	@echo ""
	@echo "$(YELLOW)🔍 DRY_RUN=true — étapes 2/5 à 5/5 SAUTÉES (permissions container, fix-permissions-host en sudo, MCP).$(NC)"
	@echo "$(YELLOW)   Aucune de ces étapes ne simule quoi que ce soit : elles MUTENT l'arbre applicatif.$(NC)"
	@echo "$(CYAN)   Plan complet : /tmp/laravel-install-*.log, ou capture des DEUX flux : make install-laravel DRY_RUN=true > plan.txt 2>&1$(NC)"
	@echo ""
else
	@echo ""
	@echo "$(BLUE)━━━ Étape 2/5 : Correction des permissions (dans le container) ━━━$(NC)"
	@$(DOCKER) exec $(PHP_CONTAINER_NAME) sh -c "\
		chown -R www-data:www-data /var/www/html 2>/dev/null || true && \
		find /var/www/html -type d -not -path '*/vendor/*' -not -path '*/node_modules/*' -exec chmod 775 {} + 2>/dev/null || true && \
		find /var/www/html -type f -not -path '*/vendor/*' -not -path '*/node_modules/*' -exec chmod 664 {} + 2>/dev/null || true && \
		chmod +x /var/www/html/artisan 2>/dev/null || true && \
		chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache 2>/dev/null || true && \
		find /var/www/html/vendor/bin -type f -exec chmod +x {} + 2>/dev/null || true"
	@echo "$(GREEN)✓ Permissions corrigées dans le container (775/664, www-data = UID $(HOST_UID))$(NC)"
	@echo ""
	@echo "$(BLUE)━━━ Étape 3/5 : Correction des permissions côté hôte WSL2 ━━━$(NC)"
	@$(MAKE) fix-permissions-host || echo "$(YELLOW)⚠️  fix-permissions-host ignoré (sudo non disponible) — relancez manuellement: make fix-permissions-host$(NC)"
	@echo ""
	@echo "$(BLUE)━━━ Étape 4/5 : Configuration MCP Laravel Boost (Claude Code) ━━━$(NC)"
	@if command -v claude >/dev/null 2>&1; then \
		claude mcp add -s local -t stdio laravel-boost -- docker exec -i $(PHP_CONTAINER_NAME) php artisan boost:mcp 2>/dev/null \
			&& echo "$(GREEN)✓ MCP Laravel Boost configuré pour Claude Code$(NC)" \
			|| echo "$(YELLOW)⚠️  MCP déjà configuré ou erreur — vérifiez avec: claude mcp list$(NC)"; \
	else \
		echo "$(YELLOW)⚠️  CLI Claude Code non trouvée — configurez manuellement: make boost-mcp$(NC)"; \
	fi
	@echo ""
	@echo "$(BLUE)━━━ Étape 5/5 : Résumé ━━━$(NC)"
	@echo "$(GREEN)✅ Installation terminée !$(NC)"
	@echo ""
	@echo "$(CYAN)Prochaines étapes :$(NC)"
	@echo "  $(YELLOW)make migrate$(NC)        → Migrations si pas encore faites"
	@echo "  $(YELLOW)make npm-install$(NC)     → Dépendances frontend"
	@echo "  $(YELLOW)make npm-dev$(NC)         → Lancer Vite en mode watch"
	@echo "  $(YELLOW)make quality-all$(NC)     → Vérifier la qualité du code"
	@echo ""
endif

# =============================================================================
# LOCKFILE D'INSTALLATION
# =============================================================================
#
# Écrit src/.install-state/lock.yml : empreinte de composer.lock + versions PHP
# et Node RÉELLEMENT installées, plus la fenêtre started_at/finished_at.
#
# ⚠️ Cible HÔTE, et non une étape d'`install.sh`. Deux raisons mesurées :
#   • le conteneur php n'a ni CLI docker ni socket, il ne peut donc pas
#     interroger le conteneur node — or c'est le node du conteneur NODE qui
#     produit node_modules/ ;
#   • `npm-install` tourne APRÈS `install-laravel` dans toutes les chaînes
#     ci-dessus : un lockfile écrit en fin d'install.sh décrirait un
#     node_modules/ inexistant.
#
# ⛔ `install-prod` / `install-prod-fast` NE L'APPELLENT PAS, et c'est écrit
# plutôt que subi : ces chaînes ne jouent pas `npm-install`, donc le conteneur
# node n'y est pas démarré (profil `dev` éteint). Le script refuserait
# bruyamment — ce qui est le bon comportement, mais ferait échouer une
# installation de production correcte.
.PHONY: install-lockfile
install-lockfile: ## Écrire src/.install-state/lock.yml (empreintes + versions réelles)
	$(call check_container,$(PHP_CONTAINER_NAME))
	$(call check_container,$(NODE_CONTAINER_NAME))
	@echo "$(CYAN)🔒 Génération du lockfile d'installation...$(NC)"
	@COMPOSE_PROJECT_NAME=$(COMPOSE_PROJECT_NAME) \
		PHP_CONTAINER_NAME=$(PHP_CONTAINER_NAME) \
		NODE_CONTAINER_NAME=$(NODE_CONTAINER_NAME) \
		$(SCRIPT_DIR)/install-lockfile.sh

.PHONY: install-laravel-prod
install-laravel-prod: ## Installer Laravel PRODUCTION [DRY_RUN=true] (sans packages dev)
	$(call check_container,$(PHP_CONTAINER_NAME))
	@echo "$(CYAN)📦 Installation Laravel PRODUCTION (packages essentiels uniquement)$(NC)"
	@echo "$(BLUE)→ Installation packages production$(NC)"
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) bash -c "cd /var/www/html && /var/www/project/scripts/install.sh --only 10-laravel-core $(INSTALL_ONLY_FLAGS)"
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) bash -c "cd /var/www/html && /var/www/project/scripts/install.sh --only 20-database $(INSTALL_ONLY_FLAGS)"
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) bash -c "cd /var/www/html && /var/www/project/scripts/install.sh --only 30-packages-prod $(INSTALL_ONLY_FLAGS)"
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) bash -c "cd /var/www/html && /var/www/project/scripts/install.sh --only 35-configure-spatie-packages $(INSTALL_ONLY_FLAGS)"
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) bash -c "cd /var/www/html && /var/www/project/scripts/install.sh --only 99-finalize $(INSTALL_ONLY_FLAGS)"
# ⛔ Même raison qu'`install-laravel` : ce bloc `chown -R` + `find -exec chmod`
# MUTE l'arbre applicatif, il ne le simule pas.
ifeq ($(DRY_RUN_VALUE),true)
	@echo "$(YELLOW)🔍 DRY_RUN=true — correction des permissions SAUTÉE (elle mute l'arbre applicatif).$(NC)"
	@echo "$(GREEN)✅ Simulation d'installation PRODUCTION terminée — rien n'a été installé$(NC)"
else
	@echo "$(BLUE)→ Correction des permissions$(NC)"
	@$(DOCKER) exec $(PHP_CONTAINER_NAME) sh -c "\
		chown -R www-data:www-data /var/www/html 2>/dev/null || true && \
		find /var/www/html -type d -not -path '*/vendor/*' -exec chmod 775 {} + 2>/dev/null || true && \
		find /var/www/html -type f -not -path '*/vendor/*' -exec chmod 664 {} + 2>/dev/null || true && \
		chmod +x /var/www/html/artisan 2>/dev/null || true && \
		chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache 2>/dev/null || true"
	@echo "$(GREEN)✅ Installation Laravel PRODUCTION terminée$(NC)"
	@echo "$(YELLOW)⚠️  PHPStan, ECS, Rector, Pest NON installés (environnement production)$(NC)"
endif


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
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) php artisan $(cmd)

.PHONY: bmad-doctor
bmad-doctor: ## Vérifier que les commandes BMad prescrites par les docs peuvent DÉMARRER
	@# ─────────────────────────────────────────────────────────────────────────
	@# Ce contrôle vit ICI, sur l'hôte, et pas dans la suite Pest — et c'est mesuré.
	@#
	@# `bmad-build` s'exécute dans le shell de la session ; Pest s'exécute dans le
	@# conteneur `php`. Le 2026-08-20 : `uv` présent sur l'hôte, absent du conteneur.
	@# Un test écrit côté conteneur serait donc resté rouge pour toujours alors que
	@# le problème est réglé — le défaut Q4 corrigé le matin même.
	@#
	@# Complément de `src/tests/Unit/BmadCommandReferentsTest.php`, qui garde la
	@# RÉSOLUTION et la DÉPRÉCIATION. Celui-ci garde l'EXÉCUTABILITÉ.
	@#
	@# ⚠️ ON CHERCHE `render_skill.py`, PAS `uv run` — et la première rédaction se
	@# trompait. `uv run` apparaît dans 44 SKILL.md sur 74, presque toujours pour
	@# `resolve_customization.py`, AVEC une échappatoire documentée (« si le script
	@# échoue, lis les fichiers de customisation toi-même »). Ces skills tournent
	@# sans `uv`. Seule l'amorce `render_skill.py` — 2 skills, `bmad-build` et
	@# `bmad-build-auto` — ordonne « HALT. Do not run any workflow source directly ».
	@# Un contrôle qui déclare 44 succès là où 2 comptent est du bruit, et le bruit
	@# est la façon dont un garde-fou cesse d'être lu.
	@# ─────────────────────────────────────────────────────────────────────────
	@echo "$(CYAN)🩺 BMad — les commandes prescrites peuvent-elles démarrer ?$(NC)"
	@fail=0; \
	if [ ! -d .claude/skills ]; then \
		echo "$(YELLOW)   ⚠️  .claude/skills/ absent (gitignoré) — contrôle impossible ici.$(NC)"; \
		exit 0; \
	fi; \
	for cmd in $$(grep -ohE '(^|[^A-Za-z0-9_/])/bmad-[a-z0-9-]+' docs/process/02-bmad-workflow.md docs/process/03-boucle-qualite.md 2>/dev/null | grep -oE 'bmad-[a-z0-9-]+' | sort -u); do \
		manifest=".claude/skills/$$cmd/SKILL.md"; \
		[ -f "$$manifest" ] || continue; \
		if grep -q 'render_skill.py' "$$manifest"; then \
			if ! command -v uv >/dev/null 2>&1; then \
				echo "$(RED)   ⛔ /$$cmd exige \`uv\`, introuvable sur le PATH — son SKILL.md lui ordonne de HALT.$(NC)"; \
				fail=1; \
			else \
				echo "$(GREEN)   ✅ /$$cmd (amorce uv — uv présent)$(NC)"; \
			fi; \
		fi; \
	done; \
	if [ $$fail -eq 1 ]; then \
		echo ""; \
		echo "$(YELLOW)   Installer : curl -LsSf https://astral.sh/uv/install.sh | sh$(NC)"; \
		echo "$(YELLOW)   Ou cesser de prescrire ces commandes dans docs/process/.$(NC)"; \
		exit 1; \
	fi; \
	echo "$(GREEN)✔ Toutes les commandes BMad prescrites peuvent démarrer.$(NC)"

.PHONY: artisan-it
artisan-it: ## Exécuter artisan en INTERACTIF (usage: make artisan-it cmd="make:filament-user")
	@# ⚠️ `-it` est indispensable pour toute commande qui POSE DES QUESTIONS.
	@# `make artisan` n'alloue ni stdin ni TTY : `make:filament-user` y meurt sans
	@# poser sa première question. Trois documents recommandaient pourtant
	@# `make artisan cmd="make:filament-user"` — relevé en revue le 2026-08-20
	@# (finding Q16), sur le chemin de création du PREMIER administrateur.
	@$(DOCKER) exec -it -u $(DOCKER_USER) $(PHP_CONTAINER) php artisan $(cmd)

.PHONY: filament-user
filament-user: ## Créer le premier administrateur du panel /admin (interactif)
	@echo "$(CYAN)👤 Création d'un utilisateur Filament — le rôle super-admin doit exister ($(YELLOW)make artisan cmd=\"db:seed\"$(CYAN)).$(NC)"
	@$(DOCKER) exec -it -u $(DOCKER_USER) $(PHP_CONTAINER) php artisan make:filament-user
	@echo "$(YELLOW)⚠️  Le compte n'a encore AUCUN rôle : /admin lui répondra 403.$(NC)"
	@echo "$(CYAN)   Assignez-le : $(NC)make artisan cmd=\"tinker\"$(CYAN) puis$(NC)"
	@echo "$(CYAN)   User::query()->where('email','vous@exemple.test')->firstOrFail()->assignRole('super-admin');$(NC)"

.PHONY: composer
composer: ## Exécuter composer (usage: make composer cmd="install")
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) composer $(cmd)

.PHONY: migrate
migrate: ## Lancer les migrations
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) php artisan migrate

.PHONY: fresh
fresh: ## Reset DB avec seeds
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) php artisan migrate:fresh --seed

.PHONY: clean-telescope-migrations
clean-telescope-migrations: ## Nettoyer les entrées de migrations Telescope en double
	@echo "$(YELLOW)🧹 Nettoyage des migrations Telescope en double...$(NC)"
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) php artisan tinker --execute="\
		DB::table('migrations')->where('migration', 'like', '%create_telescope%')->delete();\
		echo 'Migrations Telescope supprimées de la table migrations';\
	" 2>/dev/null || echo "$(RED)Erreur lors du nettoyage$(NC)"
	@echo "$(GREEN)✓ Nettoyage terminé - relancez: make migrate$(NC)"

.PHONY: db-snapshot
db-snapshot: ## Snapshot rapide DB (pg_dump avant ops risquées)
	@mkdir -p ./storage/db-snapshots
	@SNAPSHOT="./storage/db-snapshots/snapshot-$$(date +%Y%m%d-%H%M%S).sql.gz"; \
	$(DOCKER) exec -t $(POSTGRES_CONTAINER_NAME) pg_dump -U $${DB_USERNAME:-laravel} -d $${DB_DATABASE:-laravel} | gzip > "$$SNAPSHOT" && \
	echo "$(GREEN)✓ Snapshot saved: $$SNAPSHOT$(NC)"

.PHONY: db-restore
db-restore: ## Restaurer DB depuis snapshot (usage: make db-restore FILE=storage/db-snapshots/xxx.sql.gz)
	@if [ -z "$(FILE)" ]; then echo "$(RED)❌ Usage: make db-restore FILE=path/to/snapshot.sql.gz$(NC)"; exit 1; fi
	@echo "$(YELLOW)⚠️  Restoring $(FILE) into database$(NC)"
	@gunzip -c $(FILE) | $(DOCKER) exec -i $(POSTGRES_CONTAINER_NAME) psql -U $${DB_USERNAME:-laravel} -d $${DB_DATABASE:-laravel}
	@echo "$(GREEN)✓ Database restored from $(FILE)$(NC)"

.PHONY: destroy-db
destroy-db: ## ⚠️  DANGER : supprime définitivement le volume DB (avec confirmation interactive)
	@echo "$(RED)⚠️  This will DROP the postgres-data volume PERMANENTLY.$(NC)"
	@echo "$(YELLOW)All Postgres data will be lost (volume: $(COMPOSE_PROJECT_NAME)_postgres_data)$(NC)"
	@read -p "Type 'DROP IT' to confirm: " confirm; \
	if [ "$$confirm" = "DROP IT" ]; then \
		$(DOCKER_COMPOSE) down postgres && \
		$(DOCKER) volume rm $(COMPOSE_PROJECT_NAME)_postgres_data && \
		echo "$(GREEN)✓ Volume destroyed. Run 'make up' to recreate empty.$(NC)"; \
	else \
		echo "$(YELLOW)Aborted.$(NC)"; \
	fi

.PHONY: db-backup-local
db-backup-local: ## Backup local DB vers /var/backups/postgres/ (pour cron VPS prod)
	@mkdir -p /var/backups/postgres 2>/dev/null || true
	@$(DOCKER) exec -t $(POSTGRES_CONTAINER_NAME) pg_dump -U $${DB_USERNAME:-laravel} -d $${DB_DATABASE:-laravel} | gzip > /var/backups/postgres/backup-$$(date +%Y%m%d).sql.gz
	@find /var/backups/postgres -name "backup-*.sql.gz" -mtime +14 -delete 2>/dev/null || true
	@echo "$(GREEN)✓ Local backup done + 14-day rotation applied$(NC)"

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
# NB: `-e TELESCOPE_ENABLED=false` est indispensable, pas cosmétique.
# `php artisan test` boote l'application AVANT que les <env> de phpunit.xml
# s'appliquent : le process artisan lit donc le .env de dev, où Telescope est
# actif. Telescope tente ensuite de journaliser la commande dans
# `telescope_entries` (absente de la base de dev) et `make test` sortait en
# non-zéro alors que 100 % des tests passaient — un code de sortie qui ment
# invalide toute automatisation en aval (hook pre-commit, CI, ratchet).

.PHONY: test
test: ## Lancer tous les tests
	@$(DOCKER) exec -u $(DOCKER_USER) -e TELESCOPE_ENABLED=false $(PHP_CONTAINER) php artisan test

.PHONY: test-unit
test-unit: ## Tests unitaires
	@$(DOCKER) exec -u $(DOCKER_USER) -e TELESCOPE_ENABLED=false $(PHP_CONTAINER) php artisan test --testsuite=Unit

.PHONY: test-coverage
test-coverage: ## Tests avec couverture
	@$(DOCKER) exec -u $(DOCKER_USER) -e TELESCOPE_ENABLED=false $(PHP_CONTAINER) php artisan test --coverage-html coverage

.PHONY: test-drift
test-drift: ## ⛔ DESTRUCTIF — migre les tests PHPUnit vers Pest (RÉÉCRIT tests/). Pas une analyse.
	@echo "$(RED)⛔ ATTENTION — 'pest --drift' N'EST PAS UN OUTIL D'ANALYSE.$(NC)"
	@echo "$(YELLOW)   C'est le MIGRATEUR PHPUnit → Pest de pestphp/pest-plugin-drift.$(NC)"
	@echo "$(YELLOW)   Il RÉÉCRIT les fichiers de tests/ sur place, sans demander.$(NC)"
	@echo ""
	@echo "$(YELLOW)   Mesuré le 2026-08-09 (Story 1.10a) : un seul appel a réécrit 7 fichiers,$(NC)"
	@echo "$(YELLOW)   supprimé l'invariant délibéré de tests/Unit/ExampleTest.php avec toute sa$(NC)"
	@echo "$(YELLOW)   justification, et injecté des imports cassés dans deux autres.$(NC)"
	@echo ""
	@echo "$(YELLOW)   Ce dépôt est DÉJÀ entièrement en Pest : cette commande n'a plus d'objet.$(NC)"
	@echo "$(YELLOW)   Pour éprouver un garde-fou, la méthode du projet est la campagne de$(NC)"
	@echo "$(YELLOW)   mutation manuelle — docs/process/03-boucle-qualite.md §Étape 5.$(NC)"
	@echo ""
	@echo "$(YELLOW)   Pour l'exécuter malgré tout : COMMITTEZ D'ABORD, puis relisez le diff.$(NC)"
	@echo "$(CYAN)   Confirmez avec : make test-drift-force$(NC)"
	@echo ""
	@echo "$(RED)   Cette cible sort en ERREUR volontairement : un pas de CI ou un script$(NC)"
	@echo "$(RED)   qui l'appelle ne doit pas lire un succès là où rien n'a été exécuté.$(NC)"
	@exit 1

.PHONY: test-drift-force
test-drift-force: ## Exécute réellement la migration Drift (voir l'avertissement de test-drift)
	@echo "$(YELLOW)🎯 Migration Drift (destructive) — le diff de tests/ est à relire.$(NC)"
	@git diff --quiet -- src/tests || { \
		echo "$(RED)⛔ L'arbre de travail porte des modifications non committées sous src/tests.$(NC)"; \
		echo "$(RED)   Drift RÉÉCRIT ces fichiers sur place : sans commit, le diff est irrécupérable.$(NC)"; \
		echo "$(YELLOW)   Committez d'abord, puis relancez.$(NC)"; \
		exit 1; \
	}
	@$(DOCKER) exec -u $(DOCKER_USER) -e TELESCOPE_ENABLED=false $(PHP_CONTAINER) php artisan test --drift

.PHONY: test-feature
test-feature: ## Tests fonctionnels
	@$(DOCKER) exec -u $(DOCKER_USER) -e TELESCOPE_ENABLED=false $(PHP_CONTAINER) php artisan test --testsuite=Feature

# Tests navigateur — délibérément HORS de `make test`.
#
# `tests/Browser` n'est pas déclaré comme testsuite dans phpunit.xml : le
# déclarer suffirait à ce que `php artisan test` le lance, donc à exiger un
# Chromium là où il n'y en a pas (CI, image de production). Il se lance ici,
# par chemin explicite, dans son conteneur dédié.
#
# Le verdict ne vient PAS du code de sortie de pest : le plugin ne rend pas la
# main environ une fois sur deux, donc un run vert peut sortir en 137. Il vient
# du rapport JUnit, écrit avant le teardown qui se bloque.
# Toute la logique est dans docker/php/scripts/run-browser-tests.sh et
# browser-verdict.php — commentée, et refusant de conclure au vert faute de
# preuve. Voir ADR-0013.
.PHONY: test-browser
test-browser: ## Tests navigateur (Chromium, profil test)
	@echo "$(CYAN)🌐 Démarrage du runner navigateur...$(NC)"
	@$(DOCKER) compose --profile test up -d test-browser
	@$(DOCKER) exec $(BROWSER_CONTAINER_NAME) /usr/local/bin/link-alpine-chromium.sh
	@$(DOCKER) exec -u $(DOCKER_USER) -e TELESCOPE_ENABLED=false $(BROWSER_CONTAINER_NAME) \
		/usr/local/bin/run-browser-tests.sh $(BROWSER_TEST_TIMEOUT)

.PHONY: test-browser-down
test-browser-down: ## Arrêter le runner navigateur
	@$(DOCKER) compose --profile test down test-browser

# =============================================================================
# TESTS SHELL — BATS (Story 2.4)
# =============================================================================
#
# ⛔ POURQUOI BATS EN PLUS DE `ShellProbe` (src/tests/Support/ShellProbe.php).
# `ShellProbe` lance du bash DEPUIS Pest, donc depuis le conteneur php : elle
# éprouve des FONCTIONS shell, jamais une installation. Or ce que la story 2.4
# doit prouver — `make install-dev-full` sur un clone neuf — exige Docker,
# compose et l'hôte, c'est-à-dire tout ce que le conteneur php n'a pas
# (ni CLI docker, ni socket : mesuré en story 2.2). Bats COMPLÈTE ShellProbe,
# il ne la remplace pas.
#
# ⚖️ DEUX CIBLES, ET LA SÉPARATION EST DÉLIBÉRÉE :
#   • `test-bats`     — les primitives de verdict (tests/bats/unit), 1 seconde,
#                       sans Docker : c'est là que les MUTATIONS se rejouent ;
#   • `test-bats-e2e` — l'installation réelle (tests/bats/install.bats), 20 à
#                       40 minutes, avec Docker. C'est ce que joue le nightly.
# Un `make test-bats` qui lancerait le E2E serait un `make test-bats` que
# personne ne lance, donc un garde-fou que personne ne rejoue.

# Épinglage : le TAG sert au clone, le COMMIT le VÉRIFIE. Un tag est un pointeur
# mutable chez un tiers — même raisonnement que l'épinglage par SHA des actions
# GitHub (.github/workflows/ci.yml).
BATS_VERSION ?= v1.14.0
BATS_COMMIT  ?= eb7f42f8d608ac693d7a4b67474f6714ea68cfc5
# ⛔ VERSION MINIMALE EXIGÉE D'UN bats DÉJÀ INSTALLÉ. `BATS_TEST_TMPDIR` n'existe
# que depuis 1.4.0 : sous un bats ancien il vaut la CHAÎNE VIDE, `$$BATS_TEST_TMPDIR/lock.yml`
# devient `/lock.yml`, et la suite échoue (ou pire, écrit à la racine) pour une
# raison qui n'a rien à voir avec ce qu'elle mesure. Relevé en revue 1.
BATS_MIN_VERSION ?= 1.5.0
BATS_HOME    ?= .tools/bats-core
BATS_BIN      = $(BATS_HOME)/bin/bats

# Résout un bats utilisable, puis exécute $(1).
#
# ⚖️ TROIS CORRECTIFS DE REVUE 1 VIVENT DANS CETTE RECETTE :
#   • le bats DU SYSTÈME n'est plus accepté sur sa seule présence — sa version
#     est comparée à $(BATS_MIN_VERSION) ; trop ancien, on retombe sur le clone
#     épinglé plutôt que d'exécuter la suite sur un outil qui ment ;
#   • le clone est RÉESSAYÉ (3 fois) et son échec est nommé INFRASTRUCTURE :
#     c'est une porte BLOQUANTE en CI, et un hoquet réseau chez un tiers ne doit
#     pas se lire comme un défaut du dépôt ;
#   • le `rm -rf` est GARDÉ : `BATS_HOME` est surchargeable, et un
#     `make test-bats BATS_HOME=/` effaçait la machine. Le chemin doit être
#     relatif, non vide, et sans `..`.
define run_bats
	@set -e; \
	BATS_EXE=""; \
	if command -v bats > /dev/null 2>&1; then \
		found="$$(bats --version 2>/dev/null | awk '{print $$2}')"; \
		oldest="$$(printf '%s\n%s\n' "$(BATS_MIN_VERSION)" "$$found" | sort -V | head -n 1)"; \
		if [ -n "$$found" ] && [ "$$oldest" = "$(BATS_MIN_VERSION)" ]; then \
			BATS_EXE="$$(command -v bats)"; \
		else \
			echo "$(YELLOW)⚠️  bats du système en $$found — la suite exige >= $(BATS_MIN_VERSION). Repli sur le clone épinglé.$(NC)"; \
		fi; \
	fi; \
	if [ -z "$$BATS_EXE" ]; then \
		if [ ! -x "$(BATS_BIN)" ]; then \
			case "$(BATS_HOME)" in \
				""|/*|*..*) echo "$(RED)⛔ BATS_HOME=« $(BATS_HOME) » refusé : un chemin RELATIF au dépôt, sans « .. », est exigé (cette recette y fait un rm -rf).$(NC)"; exit 1 ;; \
			esac; \
			echo "$(YELLOW)📥 bats absent — installation épinglée $(BATS_VERSION) dans $(BATS_HOME)$(NC)"; \
			rm -rf -- "$(BATS_HOME)"; \
			mkdir -p "$$(dirname "$(BATS_HOME)")"; \
			cloned=1; \
			for attempt in 1 2 3; do \
				if git -c advice.detachedHead=false clone --quiet --depth 1 --branch $(BATS_VERSION) \
					https://github.com/bats-core/bats-core.git "$(BATS_HOME)"; then \
					cloned=0; break; \
				fi; \
				echo "$(YELLOW)   tentative $$attempt/3 échouée, nouvel essai…$(NC)"; \
				rm -rf -- "$(BATS_HOME)"; \
				sleep 5; \
			done; \
			if [ "$$cloned" -ne 0 ]; then \
				echo "$(RED)INFRASTRUCTURE_FAILURE: clone de bats-core impossible après 3 tentatives (réseau ou github.com).$(NC)"; \
				echo "$(RED)   Ce n'est PAS un défaut du dépôt. Relancez, ou installez bats >= $(BATS_MIN_VERSION) sur la machine.$(NC)"; \
				exit 1; \
			fi; \
			actual="$$(git -C "$(BATS_HOME)" rev-parse HEAD)"; \
			if [ "$$actual" != "$(BATS_COMMIT)" ]; then \
				rm -rf -- "$(BATS_HOME)"; \
				echo "$(RED)⛔ bats $(BATS_VERSION) résout sur $$actual, attendu $(BATS_COMMIT).$(NC)"; \
				echo "$(RED)   Le tag a bougé chez le fournisseur : rien n'est installé, rien n'est exécuté.$(NC)"; \
				exit 1; \
			fi; \
		fi; \
		BATS_EXE="$(BATS_BIN)"; \
	fi; \
	echo "$(CYAN)🦇 $$($$BATS_EXE --version) — $(1)$(NC)"; \
	"$$BATS_EXE" $(1)
endef

.PHONY: test-bats
test-bats: ## Tests shell Bats rapides (primitives du E2E, sans Docker)
	$(call run_bats,tests/bats/unit)

.PHONY: test-bats-uid
test-bats-uid: ## 🐳 Vérifie que l'UID demandé est RÉELLEMENT appliqué dans les images (exige Docker, ~10 s)
	@echo "$(CYAN)   Exige un démon Docker — rejoue le bloc d'ajustement d'utilisateur dans l'image de base.$(NC)"
	$(call run_bats,tests/bats/uid.bats)

.PHONY: test-bats-e2e
test-bats-e2e: ## ⏱️ Installation E2E réelle sur un clone neuf (20-40 min, exige les ports 80/443 libres)
	@echo "$(YELLOW)⚠️  Ce test CLONE le dépôt, BÂTIT les images et INSTALLE pour de vrai.$(NC)"
	@echo "$(YELLOW)   Il exige les ports 80 et 443 LIBRES : lancez « make down » d'abord.$(NC)"
	@echo "$(CYAN)   E2E_KEEP=true conserve la pile et le répertoire de travail.$(NC)"
	$(call run_bats,tests/bats/install.bats)

# =============================================================================
# CODE QUALITY
# =============================================================================

.PHONY: ecs
ecs: ## Vérifier le style de code
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) ./vendor/bin/ecs check

.PHONY: ecs-fix
ecs-fix: ## Corriger le style automatiquement
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) ./vendor/bin/ecs check --fix

.PHONY: phpstan
phpstan: ## Analyse statique
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) ./vendor/bin/phpstan analyse

.PHONY: rector
rector: ## Refactoring suggestions
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) ./vendor/bin/rector process --dry-run

.PHONY: rector-fix
rector-fix: ## Appliquer refactoring
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) ./vendor/bin/rector process

.PHONY: insights
insights: ## PHP Insights
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) php artisan insights

.PHONY: archeology
archeology: ## PhpCodeArcheology - analyse architecture + métriques (rapport HTML + JSON)
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) ./vendor/bin/phpcodearcheology --report-type=html,json

.PHONY: archeology-quick
archeology-quick: ## PhpCodeArcheology - résumé rapide dans le terminal
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) ./vendor/bin/phpcodearcheology --quick

.PHONY: archeology-init
archeology-init: ## PhpCodeArcheology - initialiser la configuration interactivement
	@$(DOCKER) exec -it $(PHP_CONTAINER_NAME) ./vendor/bin/phpcodearcheology init

.PHONY: archeology-baseline
archeology-baseline: ## PhpCodeArcheology - créer une baseline (projets existants)
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) ./vendor/bin/phpcodearcheology baseline create app

.PHONY: reading-room
reading-room: ## Régénérer les données de la reading room (docs/reading-room/data/plan.js)
	@# ⚠️ Tourne sur l'HÔTE, pas dans le conteneur php, et ce n'est pas un oubli :
	@# le script lit `_bmad-output/`, qui est gitignoré et vit hors de `src/` —
	@# donc hors du volume monté dans le conteneur.
	@#
	@# Le fichier produit est VERSIONNÉ, à dessein : ses deux sources sont
	@# gitignorées, donc sans ce rendu figé la reading room serait vide sur un
	@# clone. Le prix est un instantané daté, et les pages le disent.
	@command -v python3 >/dev/null 2>&1 || { \
		echo "$(RED)✖ python3 est requis pour régénérer la reading room.$(NC)"; exit 1; }
	@python3 docs/reading-room/tools/build-plan.py
	@echo "$(GREEN)→ Ouvrir : docs/reading-room/index.html$(NC)"

.PHONY: ide-helper
ide-helper: ## Générer les fichiers IDE Helper (autocomplétion PhpStorm/VSCode)
	$(call check_container,$(PHP_CONTAINER_NAME))
	@echo "$(BLUE)🔧 Generating IDE helpers...$(NC)"
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) php artisan ide-helper:generate
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) php artisan ide-helper:meta
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) php artisan ide-helper:models --nowrite
	@echo "$(GREEN)✓ IDE helpers generated$(NC)"

.PHONY: boost-setup
boost-setup: ## Configurer Laravel Boost guidelines AI (interactif)
	$(call check_container,$(PHP_CONTAINER_NAME))
	@echo "$(CYAN)🤖 Laravel Boost - configuration des guidelines AI...$(NC)"
	@$(DOCKER) exec -it $(PHP_CONTAINER_NAME) php artisan boost:install
	@echo "$(GREEN)✓ Boost guidelines configurées$(NC)"
	@echo "$(YELLOW)💡 Configurez le MCP Claude Code avec: make boost-mcp$(NC)"

# ⚠️ SEUL point d'entrée de `boost:update` depuis le 2026-08-09.
#
# Il était déclaré dans `post-update-cmd` de src/composer.json, donc il
# réécrivait src/CLAUDE.md — un fichier VERSIONNÉ — à chaque `composer update`,
# hors de toute revue. La montée 2.4.13 → 2.5.3 en a profité pour y injecter une
# consigne impérative pointant vers un `.ai/rules` inexistant.
#
# Retiré de post-update-cmd. Il se lance donc explicitement, et son diff se relit
# comme n'importe quel autre. Après l'avoir lancé : `make test` — le garde-fou
# `src/tests/Unit/BoostGuidelinesTest.php` rougit si l'amont a réintroduit une
# consigne sans référent.
.PHONY: boost-update
boost-update: ## Mettre à jour les guidelines Laravel Boost (explicite — relire le diff !)
	$(call check_container,$(PHP_CONTAINER_NAME))
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) php artisan boost:update --ansi
	@echo "$(GREEN)✓ Boost guidelines à jour$(NC)"
	@echo "$(YELLOW)⚠️  src/CLAUDE.md est VERSIONNÉ : relisez 'git diff src/CLAUDE.md' puis lancez 'make test'.$(NC)"

.PHONY: boost-mcp
boost-mcp: ## Ajouter le MCP Laravel Boost à Claude Code (commande hôte)
	@echo "$(CYAN)🔌 Configuration MCP Laravel Boost pour Claude Code...$(NC)"
	claude mcp add -s local -t stdio laravel-boost -- docker exec -i $(PHP_CONTAINER_NAME) php artisan boost:mcp
	@echo "$(GREEN)✓ MCP Laravel Boost configuré$(NC)"
	@echo "$(YELLOW)💡 Redémarrez Claude Code pour activer le MCP$(NC)"

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

.PHONY: hooks-install
hooks-install: ## Activer les hooks git versionnés (.githooks/)
	@git config core.hooksPath .githooks
	@chmod +x .githooks/* 2>/dev/null || true
	@echo "$(GREEN)✓ core.hooksPath = .githooks$(NC)"
	@echo "$(YELLOW)💡 .git/hooks/ n'est jamais cloné : cette commande est à relancer sur chaque fork$(NC)"

.PHONY: hooks-check
hooks-check: ## Vérifier que les hooks versionnés sont bien actifs
	@if [ "$$(git config core.hooksPath)" = ".githooks" ] && [ -x .githooks/pre-commit ]; then \
		echo "$(GREEN)✓ hooks versionnés actifs et exécutables$(NC)"; \
	else \
		echo "$(RED)✗ hooks inactifs — lancez : make hooks-install$(NC)"; \
		exit 1; \
	fi

.PHONY: quality-ratchet
quality-ratchet: ## Vérifier le plafond de dette qualité (ECS + PHPStan, monotone)
	@./scripts/quality-ratchet.sh

.PHONY: quality-ratchet-update
quality-ratchet-update: ## Figer le plafond de dette sur les compteurs actuels
	@TODAY=$$(date +%F) ./scripts/quality-ratchet.sh --update

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
	$(call quality_step,3,5,Quality insights,insights)
	$(call quality_step,4,5,Architecture metrics,archeology-quick)
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
		echo "$(BLUE)→ Containers surveillés: PostgreSQL, Redis, Mailpit, Adminer, IT-Tools, Dozzle$(NC)"; \
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
	@$(DOCKER) exec -it -u $(DOCKER_USER) $(PHP_CONTAINER) bash

.PHONY: shell-node
shell-node: ## Shell Node
	@$(DOCKER) exec -it -u $(DOCKER_USER) $(NODE_CONTAINER) bash

.PHONY: shell-db
shell-db: ## Console PostgreSQL (psql)
	@$(DOCKER) exec -it $(POSTGRES_CONTAINER_NAME) psql -U $${DB_USERNAME:-laravel} -d $${DB_DATABASE:-laravel}

.PHONY: fix-permissions
fix-permissions: ## Corriger les permissions pour PhpStorm/WSL2 (tourne en root dans le container)
	@echo "$(CYAN)🔧 Correction des permissions pour PhpStorm + WSL2...$(NC)"
	@if docker ps --format "{{.Names}}" | grep -q "$(PHP_CONTAINER_NAME)"; then \
		$(DOCKER) exec $(PHP_CONTAINER_NAME) sh -c "\
			chown -R www-data:www-data /var/www/html 2>/dev/null || true && \
			find /var/www/html -type d -not -path '*/vendor/*' -not -path '*/node_modules/*' -exec chmod 775 {} + 2>/dev/null || true && \
			find /var/www/html -type f -not -path '*/vendor/*' -not -path '*/node_modules/*' -exec chmod 664 {} + 2>/dev/null || true && \
			chmod +x /var/www/html/artisan 2>/dev/null || true && \
			chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache 2>/dev/null || true && \
			find /var/www/html/vendor/bin -type f -exec chmod +x {} + 2>/dev/null || true"; \
		echo "$(GREEN)✅ Permissions corrigées (www-data:www-data, 775/664)$(NC)"; \
		echo "$(YELLOW)💡 Si PhpStorm affiche encore 'read-only': File → Invalidate Caches and Restart$(NC)"; \
	else \
		echo "$(RED)❌ Container PHP non démarré. Lance 'make up-local' d'abord.$(NC)"; \
		exit 1; \
	fi

.PHONY: fix-permissions-host
fix-permissions-host: ## Corriger les permissions depuis l'hôte WSL2 (sans Docker, requiert sudo)
	@echo "$(CYAN)🔧 Correction des permissions depuis l'hôte WSL2...$(NC)"
	@HOST_USER=$$(id -un); \
	HOST_UID=$$(id -u); \
	HOST_GID=$$(id -g); \
	echo "$(YELLOW)👤 Utilisateur: $$HOST_USER ($$HOST_UID:$$HOST_GID)$(NC)"; \
	echo "$(YELLOW)📁 Répertoire: ./src$(NC)"; \
	sudo chown -R $$HOST_UID:$$HOST_GID ./src && \
	find ./src -type d -exec chmod 775 {} + 2>/dev/null || true && \
	find ./src -type f -not -path '*/vendor/bin/*' -exec chmod 664 {} + 2>/dev/null || true && \
	find ./src/vendor/bin -type f -exec chmod 775 {} + 2>/dev/null || true && \
	chmod 775 ./src/artisan 2>/dev/null || true && \
	chmod -R 775 ./src/storage ./src/bootstrap/cache 2>/dev/null || true && \
	echo "$(GREEN)✅ Permissions corrigées depuis l'hôte (775/664, $$HOST_USER:$$HOST_USER)$(NC)"

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
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) composer update --no-interaction
	$(call run_npm_command,update)
	@echo "$(GREEN)✓ Dependencies updated$(NC)"

.PHONY: security-check
security-check: ## Audit de sécurité
	@echo "$(PURPLE)🔒 Security audit$(NC)"
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) composer audit || true
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
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) php artisan health:check

.PHONY: schedule-monitor-sync
schedule-monitor-sync: ## Synchroniser les moniteurs de tâches planifiées
	@echo "$(CYAN)⏰ Synchronisation des moniteurs de tâches...$(NC)"
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) php artisan schedule-monitor:sync

.PHONY: schedule-monitor-list
schedule-monitor-list: ## Lister les tâches planifiées monitorées
	@echo "$(CYAN)📋 Liste des tâches monitorées:$(NC)"
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) php artisan schedule-monitor:list

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
	@echo "    • Services: apache, php, postgres, redis"
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
	@echo "    • Services: redis-commander"
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
	@echo "  • Containers surveillés: PostgreSQL, Redis, Mailpit, Adminer, IT-Tools, Dozzle"
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
	@if docker ps --format "{{.Names}}" | grep -q "redis_commander"; then \
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
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) bash -c "\
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
	@$(DOCKER) exec -u $(DOCKER_USER) $(PHP_CONTAINER) bash -c "\
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

