#!/bin/bash
set -e

# Couleurs pour les logs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Variables de debug
DEBUG=${DEBUG:-false}
LOG_FILE="/tmp/laravel-install-$(date +%Y%m%d-%H%M%S).log"

# Fonction de logging avec debug
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case $level in
        "DEBUG")
            if [ "$DEBUG" = "true" ]; then
                echo -e "${PURPLE}[DEBUG $timestamp]${NC} $message" | tee -a "$LOG_FILE"
            fi
            ;;
        "INFO")
            echo -e "${BLUE}[INFO $timestamp]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN $timestamp]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR $timestamp]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS $timestamp]${NC} $message" | tee -a "$LOG_FILE"
            ;;
    esac
}

# Fonction pour vérifier les prérequis
check_prerequisites() {
    log "INFO" "🔍 Vérification des prérequis..."

    local missing_tools=()

    # Vérifier les outils nécessaires
    for tool in composer php python3 grep sed; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=($tool)
        fi
    done

    if [ ${#missing_tools[@]} -ne 0 ]; then
        log "ERROR" "Outils manquants: ${missing_tools[*]}"
        log "ERROR" "Installez les outils manquants avant de continuer"
        exit 1
    fi

    # Vérifier la version de Composer
    local composer_version=$(composer --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
    log "DEBUG" "Version de Composer détectée: $composer_version"

    # Vérifier la version de PHP
    local php_version=$(php -v | head -1 | grep -oP '\d+\.\d+\.\d+')
    log "DEBUG" "Version de PHP détectée: $php_version"

    log "SUCCESS" "Tous les prérequis sont satisfaits"
}

# Fonction pour détecter le répertoire de travail correct
detect_working_directory() {
    log "DEBUG" "Détection du répertoire de travail..."

    # Si on est dans un container Docker avec /var/www/html (monté depuis ./src)
    if [ -d "/var/www/html" ] && [ -w "/var/www/html" ]; then
        log "DEBUG" "Répertoire Docker détecté: /var/www/html"
        echo "/var/www/html"
        return
    fi

    # Sinon, utiliser le répertoire courant
    local current_dir=$(pwd)
    log "DEBUG" "Utilisation du répertoire courant: $current_dir"
    echo "$current_dir"
}

# FONCTION CORRIGÉE : Réparer la configuration Composer avec gestion des plugins
fix_composer_config() {
    log "INFO" "🔧 Vérification et réparation de la configuration Composer..."

    # Vérifier si le fichier config existe et est valide
    if [ -f "/var/composer/config.json" ]; then
        if ! python3 -m json.tool /var/composer/config.json >/dev/null 2>&1; then
            log "WARN" "Configuration Composer corrompue, réparation..."
            rm -f /var/composer/config.json
        fi
    fi

    # Créer le répertoire si nécessaire
    mkdir -p /var/composer

    # Initialiser une configuration propre
    composer config --global --no-interaction repos.packagist composer https://packagist.org 2>/dev/null || {
        log "WARN" "Recréation de la configuration Composer..."
        echo '{"config":{},"repositories":{"packagist.org":{"type":"composer","url":"https://packagist.org"}}}' > /var/composer/config.json
    }

    # NOUVEAUTÉ : Autoriser les plugins nécessaires pour les packages Laravel modernes
    log "INFO" "Configuration des plugins Composer autorisés..."

    # Liste des plugins couramment utilisés dans les projets Laravel
    local plugins_to_allow=(
        "dealerdirect/phpcodesniffer-composer-installer"
        "pestphp/pest-plugin"
        "php-http/discovery"
        "bamarni/composer-bin-plugin"
        "ergebnis/composer-normalize"
        "infection/extension-installer"
        "phpstan/extension-installer"
        "rector/extension-installer"
    )

    for plugin in "${plugins_to_allow[@]}"; do
        log "DEBUG" "Autorisation du plugin: $plugin"
        if composer config --global allow-plugins.$plugin true 2>/dev/null; then
            log "DEBUG" "✓ Plugin $plugin autorisé"
        else
            log "WARN" "⚠️ Impossible d'autoriser le plugin $plugin"
        fi
    done

    # Configurer les optimisations Composer
    log "DEBUG" "Configuration des optimisations Composer..."
    composer config --global process-timeout 2000 2>/dev/null || true
    composer config --global prefer-stable true 2>/dev/null || true
    composer config --global minimum-stability stable 2>/dev/null || true

    # Afficher la configuration actuelle (en mode debug)
    if [ "$DEBUG" = "true" ]; then
        log "DEBUG" "Configuration Composer actuelle:"
        composer config --global --list | grep -E "(allow-plugins|process-timeout|prefer-stable)" || true
    fi

    log "SUCCESS" "Configuration Composer mise à jour avec plugins autorisés"
}

# Fonction pour attendre que la base de données soit prête
wait_for_database() {
    log "INFO" "⏳ Attente de la disponibilité de la base de données..."

    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        log "DEBUG" "Tentative de connexion $attempt/$max_attempts"

        if php artisan tinker --execute="DB::connection()->getPdo(); echo 'DB Connected';" 2>/dev/null | grep -q "DB Connected"; then
            log "SUCCESS" "Base de données accessible"
            return 0
        fi

        log "WARN" "Base de données non prête, attente... ($attempt/$max_attempts)"
        sleep 3
        ((attempt++))
    done

    log "ERROR" "Impossible de se connecter à la base de données après $max_attempts tentatives"
    log "INFO" "Vérifiez que MariaDB est démarré: docker-compose ps mariadb"
    return 1
}

# Fonction pour créer un nouveau projet Laravel
create_laravel_project() {
    local target_dir="$1"
    log "INFO" "🆕 Création d'un nouveau projet Laravel dans $target_dir"

    # Vérifier les permissions d'écriture
    if [ ! -w "$target_dir" ]; then
        log "ERROR" "Pas de permission d'écriture dans $target_dir"
        log "INFO" "Essayez avec sudo ou vérifiez les permissions"
        exit 1
    fi

    # Vérifier si le dossier est vide (ignorer les fichiers cachés comme .gitkeep)
    local content_count=$(find "$target_dir" -mindepth 1 -maxdepth 1 ! -name '.*' | wc -l)
    if [ "$content_count" -gt 0 ]; then
        log "ERROR" "Le dossier $target_dir n'est pas vide"
        log "INFO" "Contenu trouvé:"
        ls -la "$target_dir"
        log "INFO" "Veuillez vider le dossier ou supprimer son contenu avant l'installation"
        exit 1
    fi

    # Aller dans le dossier cible et installer Laravel directement dedans
    cd "$target_dir"
    log "DEBUG" "Changement de répertoire vers: $target_dir"

    # Créer le projet Laravel dans le répertoire courant (.)
    log "INFO" "Téléchargement et installation de Laravel..."
    if ! COMPOSER_MEMORY_LIMIT=-1 composer create-project laravel/laravel . --no-interaction; then
        log "ERROR" "Échec de la création du projet Laravel"
        exit 1
    fi

    log "SUCCESS" "Projet Laravel créé avec succès dans : $target_dir"
}

# FONCTION AMÉLIORÉE : installer un package avec gestion d'erreur et debug
install_package() {
    local package=$1
    local type=${2:-"require"}  # require ou require-dev
    local max_attempts=3
    local attempt=1

    log "INFO" "📦 Installation de $package (type: $type)"

    while [ $attempt -le $max_attempts ]; do
        log "DEBUG" "Installation de $package (tentative $attempt/$max_attempts)..."

        # Nettoyer le cache avant l'installation
        log "DEBUG" "Nettoyage du cache Composer..."
        composer clear-cache 2>/dev/null || true

        # Construire la commande Composer
        local composer_cmd
        if [ "$type" = "require-dev" ]; then
            composer_cmd="COMPOSER_MEMORY_LIMIT=-1 composer require --dev \"$package\" --no-interaction --no-scripts --no-progress --with-dependencies"
        else
            composer_cmd="COMPOSER_MEMORY_LIMIT=-1 composer require \"$package\" --no-interaction --no-scripts --no-progress --with-dependencies"
        fi

        log "DEBUG" "Commande: $composer_cmd"

        # Exécuter la commande avec capture des erreurs
        if eval $composer_cmd 2>&1 | tee -a "$LOG_FILE"; then
            log "SUCCESS" "$package installé avec succès"

            # Exécuter les scripts post-installation séparément
            log "DEBUG" "Exécution des scripts post-installation..."
            composer run-script post-autoload-dump --no-interaction 2>&1 | tee -a "$LOG_FILE" || true

            return 0
        else
            local exit_code=$?
            log "ERROR" "Échec de l'installation de $package (code: $exit_code)"

            if [ $attempt -lt $max_attempts ]; then
                log "WARN" "Nouvelle tentative dans 5 secondes..."
                sleep 5
                attempt=$((attempt + 1))
            else
                log "ERROR" "Impossible d'installer $package après $max_attempts tentatives"

                # En mode debug, afficher plus d'informations
                if [ "$DEBUG" = "true" ]; then
                    log "DEBUG" "Diagnostic de l'échec:"
                    composer diagnose 2>&1 | tail -20 | tee -a "$LOG_FILE" || true
                fi

                return 1
            fi
        fi
    done
}

# Fonction pour configurer la base de données MariaDB
configure_database() {
    log "INFO" "🗄️ Configuration de la base de données MariaDB..."

    if [ -f ".env" ]; then
        # Sauvegarder le .env original
        cp .env .env.backup
        log "DEBUG" "Sauvegarde de .env vers .env.backup"

        # Configurer pour MariaDB - plus robuste
        log "DEBUG" "Configuration des paramètres de base de données..."
        sed -i 's/DB_CONNECTION=.*/DB_CONNECTION=mysql/' .env
        sed -i 's/.*DB_HOST=.*/DB_HOST=mariadb/' .env
        sed -i 's/.*DB_PORT=.*/DB_PORT=3306/' .env
        sed -i 's/.*DB_DATABASE=.*/DB_DATABASE=laravel/' .env
        sed -i 's/.*DB_USERNAME=.*/DB_USERNAME=laravel_user/' .env
        sed -i 's/.*DB_PASSWORD=.*/DB_PASSWORD=secure_password/' .env

        # S'assurer que les lignes existent (Laravel 11+ peut les commenter)
        local db_params=("DB_HOST=mariadb" "DB_PORT=3306" "DB_DATABASE=laravel" "DB_USERNAME=laravel_user" "DB_PASSWORD=secure_password")
        for param in "${db_params[@]}"; do
            local key=$(echo $param | cut -d'=' -f1)
            if ! grep -q "^$key=" .env; then
                log "DEBUG" "Ajout du paramètre: $param"
                echo "$param" >> .env
            fi
        done

        # Supprimer la ligne du fichier SQLite si elle existe
        sed -i '/DB_DATABASE=.*\.sqlite/d' .env

        # Configuration des sessions et cache
        log "DEBUG" "Configuration des sessions et cache..."
        sed -i 's/SESSION_DRIVER=.*/SESSION_DRIVER=database/' .env
        sed -i 's/CACHE_STORE=.*/CACHE_STORE=redis/' .env
        sed -i 's/QUEUE_CONNECTION=.*/QUEUE_CONNECTION=redis/' .env

        # Configuration Redis
        local redis_params=("REDIS_HOST=redis" "REDIS_PASSWORD=redis_secret_password" "REDIS_PORT=6379")
        for param in "${redis_params[@]}"; do
            local key=$(echo $param | cut -d'=' -f1)
            if ! grep -q "^$key=" .env; then
                log "DEBUG" "Ajout du paramètre Redis: $param"
                echo "$param" >> .env
            else
                sed -i "s/.*$key=.*/$param/" .env
            fi
        done

        log "SUCCESS" "Base de données configurée pour MariaDB avec sessions DB"

        # En mode debug, afficher la configuration
        if [ "$DEBUG" = "true" ]; then
            log "DEBUG" "Configuration de base de données actuelle:"
            grep -E "^DB_|^REDIS_|^SESSION_|^CACHE_|^QUEUE_" .env | tee -a "$LOG_FILE"
        fi
    else
        log "ERROR" "Fichier .env non trouvé"
        return 1
    fi
}

# Fonction pour créer les fichiers de configuration des outils de qualité
create_quality_tools_config() {
    log "INFO" "⚙️ Création des fichiers de configuration pour les outils de qualité..."

    # Configuration Easy Coding Standard (ECS)
    log "DEBUG" "Création de ecs.php..."
    cat > ecs.php << 'EOF'
<?php

declare(strict_types=1);

use Symplify\EasyCodingStandard\Config\ECSConfig;
use Symplify\EasyCodingStandard\ValueObject\Set\SetList;

return function (ECSConfig $ecsConfig): void {
    $ecsConfig->paths([
        __DIR__ . '/app',
        __DIR__ . '/config',
        __DIR__ . '/database',
        __DIR__ . '/resources',
        __DIR__ . '/routes',
        __DIR__ . '/tests',
    ]);

    $ecsConfig->sets([
        SetList::SPACES,
        SetList::ARRAY,
        SetList::DOCBLOCK,
        SetList::NAMESPACES,
        SetList::COMMENTS,
        SetList::PSR_12,
    ]);

    $ecsConfig->skip([
        __DIR__ . '/bootstrap',
        __DIR__ . '/storage',
        __DIR__ . '/vendor',
        __DIR__ . '/node_modules',
    ]);
};
EOF

    # Configuration Rector
    log "DEBUG" "Création de rector.php..."
    cat > rector.php << 'EOF'
<?php

declare(strict_types=1);

use Rector\Config\RectorConfig;
use Rector\Set\ValueObject\LevelSetList;
use Rector\Laravel\Set\LaravelSetList;
use Rector\TypeDeclaration\Rector\ClassMethod\AddVoidReturnTypeWhereNoReturnRector;

return static function (RectorConfig $rectorConfig): void {
    $rectorConfig->paths([
        __DIR__ . '/app',
        __DIR__ . '/config',
        __DIR__ . '/database',
        __DIR__ . '/resources',
        __DIR__ . '/routes',
        __DIR__ . '/tests',
    ]);

    $rectorConfig->rules([
        AddVoidReturnTypeWhereNoReturnRector::class,
    ]);

    $rectorConfig->sets([
        LevelSetList::UP_TO_PHP_82,
        LaravelSetList::LARAVEL_110,
    ]);

    $rectorConfig->skip([
        __DIR__ . '/bootstrap',
        __DIR__ . '/storage',
        __DIR__ . '/vendor',
        __DIR__ . '/node_modules',
    ]);
};
EOF

    # Configuration PHPStan
    log "DEBUG" "Création de phpstan.neon..."
    cat > phpstan.neon << 'EOF'
includes:
    - vendor/larastan/larastan/extension.neon

parameters:
    level: 6
    paths:
        - app/
        - config/
        - database/
        - routes/
        - tests/

    excludePaths:
        - bootstrap/
        - storage/
        - vendor/
        - node_modules/

    checkMissingIterableValueType: false
    checkGenericClassInNonGenericObjectType: false

    ignoreErrors:
        - '#PHPDoc tag @var#'
        - '#Unsafe usage of new static#'
EOF

    # Configuration Telescope
    if [ -f "config/telescope.php" ]; then
        log "DEBUG" "Configuration de Laravel Telescope..."

        # Activer Telescope en local et staging uniquement
        sed -i "s/'enabled' => env('TELESCOPE_ENABLED', true),/'enabled' => env('TELESCOPE_ENABLED', env('APP_ENV') !== 'production'),/" config/telescope.php

        # Configurer le stockage pour utiliser la base de données
        sed -i "s/'driver' => env('TELESCOPE_DRIVER', 'database'),/'driver' => 'database',/" config/telescope.php
    fi

    # Configuration PHP Insights
    log "DEBUG" "Création de config/insights.php..."
    mkdir -p config
    cat > config/insights.php << 'EOF'
<?php

declare(strict_types=1);

return [
    'preset' => 'laravel',
    'ide' => 'phpstorm',

    'exclude' => [
        'bootstrap',
        'storage',
        'vendor',
        'node_modules',
        'public/build',
        'public/hot',
    ],

    'add' => [
        // Ajoutez des métriques personnalisées ici
    ],

    'remove' => [
        // Désactiver certaines vérifications si nécessaire
        \NunoMaduro\PhpInsights\Domain\Insights\ForbiddenTraits::class,
        \SlevomatCodingStandard\Sniffs\TypeHints\DisallowMixedTypeHintSniff::class,
        \SlevomatCodingStandard\Sniffs\Classes\ForbiddenPublicPropertySniff::class,
    ],

    'config' => [
        \PHP_CodeSniffer\Standards\Generic\Sniffs\Files\LineLengthSniff::class => [
            'lineLimit' => 120,
            'absoluteLineLimit' => 160,
        ],
        \SlevomatCodingStandard\Sniffs\Functions\FunctionLengthSniff::class => [
            'maxLinesLength' => 50,
        ],
        \SlevomatCodingStandard\Sniffs\Classes\ClassLengthSniff::class => [
            'maxLinesLength' => 250,
        ],
    ],

    'requirements' => [
        'min-quality' => 80,
        'min-complexity' => 85,
        'min-architecture' => 80,
        'min-style' => 90,
        'disable-security-check' => false,
    ],

    'threads' => null,
];
EOF

    log "SUCCESS" "Fichiers de configuration créés:"
    log "INFO" "  • ecs.php (Easy Coding Standard)"
    log "INFO" "  • rector.php (Rector)"
    log "INFO" "  • phpstan.neon (PHPStan/Larastan)"
    log "INFO" "  • config/insights.php (PHP Insights)"
    if [ -f "config/telescope.php" ]; then
        log "INFO" "  • config/telescope.php (Telescope configuré)"
    fi
}

# Fonction pour configurer le package.json avec des scripts utiles
configure_package_json() {
    log "INFO" "📝 Configuration des scripts dans package.json..."

    if [ -f "package.json" ]; then
        # Ajouter des scripts personnalisés au package.json
        python3 << 'EOF'
import json
import sys

try:
    with open('package.json', 'r') as f:
        package_data = json.load(f)

    # Ajouter des scripts personnalisés
    if 'scripts' not in package_data:
        package_data['scripts'] = {}

    custom_scripts = {
        "quality": "composer run-script quality",
        "quality:fix": "composer run-script quality:fix",
        "test:coverage": "php artisan test --coverage",
        "analyse": "vendor/bin/phpstan analyse",
        "fix:cs": "vendor/bin/ecs --fix",
        "check:cs": "vendor/bin/ecs",
        "refactor": "vendor/bin/rector process"
    }

    package_data['scripts'].update(custom_scripts)

    with open('package.json', 'w') as f:
        json.dump(package_data, f, indent=2)

    print("Scripts ajoutés au package.json")
except Exception as e:
    print(f"Erreur lors de la modification du package.json: {e}")
    sys.exit(1)
EOF
        if [ $? -eq 0 ]; then
            log "SUCCESS" "Scripts ajoutés au package.json"
        else
            log "ERROR" "Échec de la modification du package.json"
        fi
    else
        log "WARN" "package.json non trouvé"
    fi
}

# Fonction pour configurer les scripts Composer
configure_composer_scripts() {
    log "INFO" "📝 Configuration des scripts Composer..."

    if [ -f "composer.json" ]; then
        # Ajouter des scripts personnalisés au composer.json
        python3 << 'EOF'
import json
import sys

try:
    with open('composer.json', 'r') as f:
        composer_data = json.load(f)

    # Ajouter des scripts personnalisés
    if 'scripts' not in composer_data:
        composer_data['scripts'] = {}

    custom_scripts = {
        "quality": [
            "@check:cs",
            "@analyse",
            "@insights"
        ],
        "quality:fix": [
            "@fix:cs",
            "@refactor"
        ],
        "quality:full": [
            "@check:cs",
            "@analyse",
            "@insights",
            "@enlightn",
            "@test:unit"
        ],
        "check:cs": "vendor/bin/ecs",
        "fix:cs": "vendor/bin/ecs --fix",
        "analyse": "vendor/bin/phpstan analyse",
        "refactor": "vendor/bin/rector process --dry-run",
        "refactor:fix": "vendor/bin/rector process",
        "insights": "php artisan insights",
        "insights:fix": "php artisan insights --fix",
        "enlightn": "php artisan enlightn",
        "ide-helper": [
            "php artisan ide-helper:generate",
            "php artisan ide-helper:meta",
            "php artisan ide-helper:models --write"
        ],
        "test:unit": "php artisan test --testsuite=Unit",
        "test:feature": "php artisan test --testsuite=Feature",
        "test:coverage": "php artisan test --coverage-html coverage",
        "security": "php artisan enlightn --format=github"
    }

    composer_data['scripts'].update(custom_scripts)

    with open('composer.json', 'w') as f:
        json.dump(composer_data, f, indent=2)

    print("Scripts ajoutés au composer.json")
except Exception as e:
    print(f"Erreur lors de la modification du composer.json: {e}")
    sys.exit(1)
EOF
        if [ $? -eq 0 ]; then
            log "SUCCESS" "Scripts ajoutés au composer.json"
        else
            log "ERROR" "Échec de la modification du composer.json"
        fi
    else
        log "ERROR" "composer.json non trouvé"
        return 1
    fi
}

# FONCTION CORRIGÉE : Optimiser Composer
optimize_composer() {
    log "INFO" "⚡ Optimisation de Composer..."

    # Réparer la configuration d'abord
    fix_composer_config

    # CORRECTION : Ne pas désactiver php-http/discovery car il peut être nécessaire
    # composer config --global allow-plugins.php-http/discovery false 2>/dev/null || true

    # Optimiser l'autoloader
    log "DEBUG" "Optimisation de l'autoloader..."
    composer dump-autoload --optimize --no-interaction 2>/dev/null || true

    log "SUCCESS" "Optimisation Composer terminée"
}

# Fonction pour exécuter les migrations et seeders
run_migrations() {
    log "INFO" "🔄 Exécution des migrations..."

    # Attendre que la base de données soit prête
    if ! wait_for_database; then
        log "ERROR" "Impossible de continuer sans base de données"
        return 1
    fi

    # Exécuter les migrations avec --force pour éviter la confirmation en production
    log "DEBUG" "Migration des tables Laravel de base..."
    if php artisan migrate --force --no-interaction 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Migrations de base exécutées"
    else
        log "ERROR" "Échec des migrations de base"
        return 1
    fi

    # Migrations spécifiques aux packages installés
    log "DEBUG" "Migration des tables des packages..."

    # Créer la table sessions si elle n'existe pas (Laravel 11+)
    if ! php artisan tinker --execute="DB::select('SHOW TABLES LIKE \"sessions\"');" 2>/dev/null | grep -q "sessions"; then
        log "DEBUG" "Création de la table sessions..."
        php artisan session:table --force 2>/dev/null || true
        php artisan migrate --force --no-interaction 2>/dev/null || true
    fi

    # Créer la table cache si elle n'existe pas
    if ! php artisan tinker --execute="DB::select('SHOW TABLES LIKE \"cache\"');" 2>/dev/null | grep -q "cache"; then
        log "DEBUG" "Création de la table cache..."
        php artisan cache:table --force 2>/dev/null || true
        php artisan migrate --force --no-interaction 2>/dev/null || true
    fi

    # Créer les tables des queues
    if ! php artisan tinker --execute="DB::select('SHOW TABLES LIKE \"jobs\"');" 2>/dev/null | grep -q "jobs"; then
        log "DEBUG" "Création des tables de queues..."
        php artisan queue:table --force 2>/dev/null || true
        php artisan queue:failed-table --force 2>/dev/null || true
        php artisan migrate --force --no-interaction 2>/dev/null || true
    fi

    # Migration finale pour s'assurer que tout est à jour
    log "DEBUG" "Migration finale..."
    php artisan migrate --force --no-interaction 2>/dev/null || true

    log "SUCCESS" "Toutes les migrations terminées"

    # Optionnel : exécuter les seeders de base (uniquement si ils existent)
    if [ -f "database/seeders/DatabaseSeeder.php" ]; then
        log "DEBUG" "Vérification des seeders..."
        if grep -q "run()" database/seeders/DatabaseSeeder.php; then
            log "DEBUG" "Exécution des seeders..."
            php artisan db:seed --force --no-interaction 2>/dev/null || log "WARN" "Seeders non exécutés (normal pour une nouvelle installation)"
        fi
    fi
}

# Installation principale
main() {
    # Initialiser le logging
    log "INFO" "🚀 Installation complète de Laravel avec outils de qualité"
    log "INFO" "Log file: $LOG_FILE"

    # Activer le mode debug si requis
    if [ "$1" = "--debug" ]; then
        DEBUG=true
        log "INFO" "Mode debug activé"
    fi

    # Vérifier les prérequis
    check_prerequisites

    # Détecter le répertoire de travail (normalement /var/www/html dans le container)
    WORKING_DIR=$(detect_working_directory)
    log "INFO" "Répertoire de travail détecté : $WORKING_DIR"

    # Vérifier la mémoire disponible
    if command -v free &> /dev/null; then
        log "DEBUG" "Mémoire disponible :"
        free -h | grep -E "^Mem|^Swap" | tee -a "$LOG_FILE"
    fi

    # Optimiser Composer
    optimize_composer

    # Vérifier si on a déjà un projet Laravel
    if [ ! -f "$WORKING_DIR/composer.json" ]; then
        log "INFO" "Aucun projet Laravel détecté dans $WORKING_DIR"
        create_laravel_project "$WORKING_DIR"
    else
        log "INFO" "Projet Laravel existant détecté dans $WORKING_DIR"

        # Vérifier si c'est bien un projet Laravel
        if grep -q "laravel/framework" "$WORKING_DIR/composer.json"; then
            log "SUCCESS" "Projet Laravel valide trouvé"
        else
            log "WARN" "Le composer.json existe mais ne semble pas être un projet Laravel"
        fi
    fi

    # Se déplacer dans le répertoire de travail pour les installations
    cd "$WORKING_DIR"
    log "DEBUG" "Changement de répertoire vers: $WORKING_DIR"

    # Configurer la base de données MariaDB
    configure_database

    # Packages de production
    log "INFO" "📦 Installation des packages de production..."
    local production_packages=(
        "laravel/horizon"
        "laravel/telescope"
        "laravel/sanctum"
        "spatie/laravel-permission"
        "spatie/laravel-activitylog"
    )

    local failed_packages=()
    for package in "${production_packages[@]}"; do
        if ! install_package "$package" "require"; then
            failed_packages+=("$package")
            log "WARN" "Échec de l'installation de $package (production)"
        fi
        sleep 2
    done

    # Packages de développement
    log "INFO" "🛠️ Installation des outils de qualité de code..."
    local dev_packages=(
        "symplify/easy-coding-standard"
        "rector/rector"
        "larastan/larastan"
        "pestphp/pest"
        "pestphp/pest-plugin-laravel"
        "nunomaduro/collision"
        "nunomaduro/phpinsights"
        "barryvdh/laravel-ide-helper"
        "beyondcode/laravel-query-detector"
        "enlightn/enlightn"
    )

    for package in "${dev_packages[@]}"; do
        if ! install_package "$package" "require-dev"; then
            failed_packages+=("$package")
            log "WARN" "Échec de l'installation de $package (dev)"
        fi
        sleep 2
    done

    # Rapport des packages qui ont échoué
    if [ ${#failed_packages[@]} -gt 0 ]; then
        log "WARN" "Packages qui ont échoué à l'installation:"
        for package in "${failed_packages[@]}"; do
            log "WARN" "  - $package"
        done
    fi

    # Installation finale et optimisation
    log "INFO" "🔄 Finalisation de l'installation..."
    COMPOSER_MEMORY_LIMIT=-1 composer install --no-interaction --optimize-autoloader 2>&1 | tee -a "$LOG_FILE"

    # Publier les assets et configurations
    if [ -f "artisan" ]; then
        log "INFO" "📋 Publication des assets et configurations..."

        # Liste des commandes de publication
        local publish_commands=(
            "php artisan vendor:publish --tag=horizon-config --force"
            "php artisan vendor:publish --tag=horizon-assets --force"
            "php artisan vendor:publish --tag=telescope-config --force"
            "php artisan vendor:publish --tag=telescope-migrations --force"
            "php artisan vendor:publish --provider=\"Laravel\Sanctum\SanctumServiceProvider\" --force"
            "php artisan vendor:publish --provider=\"Spatie\Permission\PermissionServiceProvider\" --force"
            "php artisan vendor:publish --provider=\"Spatie\Activitylog\ActivitylogServiceProvider\" --tag=\"activitylog-migrations\" --force"
            "php artisan vendor:publish --provider=\"Barryvdh\LaravelIdeHelper\IdeHelperServiceProvider\" --tag=config --force"
            "php artisan vendor:publish --provider=\"BeyondCode\QueryDetector\QueryDetectorServiceProvider\" --force"
            "php artisan vendor:publish --tag=enlightn --force"
        )

        for cmd in "${publish_commands[@]}"; do
            log "DEBUG" "Exécution: $cmd"
            eval "$cmd" 2>/dev/null || log "DEBUG" "Commande ignorée (package peut-être non installé): $cmd"
        done

        # Générer la clé d'application si nécessaire
        if ! grep -q "APP_KEY=.*" .env || grep -q "APP_KEY=$" .env; then
            log "INFO" "Génération de la clé d'application..."
            php artisan key:generate --no-interaction --force
        fi

        # IMPORTANT : Exécuter les migrations maintenant
        log "INFO" "🗄️ Configuration de la base de données..."
        run_migrations

        # Générer les fichiers IDE Helper après les migrations
        log "INFO" "💡 Génération des fichiers IDE Helper..."
        php artisan ide-helper:generate 2>/dev/null || true
        php artisan ide-helper:meta 2>/dev/null || true
        php artisan ide-helper:models --write 2>/dev/null || true
    fi

    # Créer les fichiers de configuration des outils de qualité
    create_quality_tools_config

    # Configurer les scripts
    configure_composer_scripts
    configure_package_json

    # Optimiser les caches
    log "INFO" "⚡ Optimisation des caches..."
    php artisan config:cache 2>/dev/null || true
    php artisan route:cache 2>/dev/null || true
    php artisan view:cache 2>/dev/null || true

    # Afficher un résumé de l'installation
    log "SUCCESS" "Installation terminée avec succès !"
    log "INFO" "📂 Fichiers Laravel installés dans : $WORKING_DIR"
    log "DEBUG" "📊 Structure créée :"
    ls -la "$WORKING_DIR" | head -15

    # Résumé des outils installés
    log "INFO" "🛠️ Outils de qualité installés :"
    log "INFO" "  • Easy Coding Standard (ECS) - Vérification du style de code"
    log "INFO" "  • Rector - Refactoring automatique"
    log "INFO" "  • PHPStan/Larastan - Analyse statique"
    log "INFO" "  • PHP Insights - Analyse globale de la qualité"
    log "INFO" "  • Laravel IDE Helper - Autocomplétion IDE"
    log "INFO" "  • Laravel Query Detector - Détection requêtes N+1"
    log "INFO" "  • Enlightn - Audit de sécurité et performance"
    log "INFO" "  • Pest - Framework de tests"

    log "INFO" "📦 Packages Laravel installés :"
    log "INFO" "  • Laravel Horizon - Gestion des queues"
    log "INFO" "  • Laravel Telescope - Debugging et monitoring"
    log "INFO" "  • Laravel Sanctum - Authentification API"
    log "INFO" "  • Spatie Permission - Gestion des rôles et permissions"
    log "INFO" "  • Spatie Activity Log - Journal d'activité"

    log "INFO" "⚡ Scripts disponibles :"
    log "INFO" "  • composer quality - Vérifier la qualité du code (ECS + PHPStan + Insights)"
    log "INFO" "  • composer quality:fix - Corriger automatiquement"
    log "INFO" "  • composer quality:full - Audit complet (qualité + sécurité + tests)"
    log "INFO" "  • composer insights - Analyse PHP Insights"
    log "INFO" "  • composer enlightn - Audit sécurité et performance"
    log "INFO" "  • composer ide-helper - Générer les fichiers IDE Helper"
    log "INFO" "  • composer test:coverage - Tests avec couverture"

    # Vérifier les fichiers importants
    log "INFO" "📋 Vérification des fichiers :"
    local files_to_check=("package.json" ".env" "ecs.php" "rector.php" "phpstan.neon")
    for file in "${files_to_check[@]}"; do
        if [ -f "$WORKING_DIR/$file" ]; then
            log "SUCCESS" "✓ $file"
        else
            log "WARN" "✗ $file manquant"
        fi
    done

    # Vérifier les tables importantes
    log "INFO" "📋 Vérification des tables importantes :"
    local important_tables=("users" "sessions" "cache" "jobs" "failed_jobs")
    for table in "${important_tables[@]}"; do
        if php artisan tinker --execute="DB::select('SHOW TABLES LIKE \"$table\"');" 2>/dev/null | grep -q "$table"; then
            log "SUCCESS" "✓ Table $table"
        else
            log "WARN" "✗ Table $table manquante"
        fi
    done

    log "SUCCESS" "🎉 Installation complète terminée !"
    log "INFO" "Prochaines étapes :"
    log "INFO" "1. ✅ Base de données configurée et migrée"
    log "INFO" "2. Accéder à l'application : https://laravel.local"
    log "INFO" "3. Lancer les tests : composer test:coverage"
    log "INFO" "4. Vérifier la qualité : composer quality"
    log "INFO" "5. Configurer le monitoring : make setup-monitoring"

    if [ ${#failed_packages[@]} -gt 0 ]; then
        log "WARN" "⚠️ Certains packages ont échoué. Consultez le log: $LOG_FILE"
    fi

    log "INFO" "Log complet disponible: $LOG_FILE"
}

# Afficher l'aide si demandé
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [--debug] [--help]"
    echo ""
    echo "Options:"
    echo "  --debug    Activer le mode debug avec logs détaillés"
    echo "  --help     Afficher cette aide"
    echo ""
    echo "Variables d'environnement:"
    echo "  DEBUG=true    Activer le mode debug (équivalent à --debug)"
    exit 0
fi

# Exécuter l'installation
main "$@"