#!/bin/bash
set -e

# Couleurs pour les logs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Fonction pour détecter le répertoire de travail correct
detect_working_directory() {
    # Si on est dans un container Docker avec /var/www/html (monté depuis ./src)
    if [ -d "/var/www/html" ] && [ -w "/var/www/html" ]; then
        echo "/var/www/html"
        return
    fi

    # Sinon, utiliser le répertoire courant
    echo "$(pwd)"
}

# Fonction pour réparer la configuration Composer
fix_composer_config() {
    echo -e "${YELLOW}Vérification de la configuration Composer...${NC}"

    # Vérifier si le fichier config existe et est valide
    if [ -f "/var/composer/config.json" ]; then
        if ! python3 -m json.tool /var/composer/config.json >/dev/null 2>&1; then
            echo -e "${RED}Configuration Composer corrompue, réparation...${NC}"
            rm -f /var/composer/config.json
        fi
    fi

    # Créer le répertoire si nécessaire
    mkdir -p /var/composer

    # Initialiser une configuration propre
    composer config --global --no-interaction repos.packagist composer https://packagist.org 2>/dev/null || {
        echo -e "${YELLOW}Recréation de la configuration Composer...${NC}"
        echo '{"config":{},"repositories":{"packagist.org":{"type":"composer","url":"https://packagist.org"}}}' > /var/composer/config.json
    }
}

# Fonction pour attendre que la base de données soit prête
wait_for_database() {
    echo -e "${YELLOW}Attente de la disponibilité de la base de données...${NC}"

    max_attempts=30
    attempt=1

    while [ $attempt -le $max_attempts ]; do
        if php artisan tinker --execute="DB::connection()->getPdo(); echo 'DB Connected';" 2>/dev/null | grep -q "DB Connected"; then
            echo -e "${GREEN}✓ Base de données accessible${NC}"
            return 0
        fi

        echo -e "${YELLOW}⏳ Tentative $attempt/$max_attempts - Base de données non prête...${NC}"
        sleep 3
        ((attempt++))
    done

    echo -e "${RED}❌ Impossible de se connecter à la base de données après $max_attempts tentatives${NC}"
    echo -e "${YELLOW}💡 Vérifiez que MariaDB est démarré: docker-compose ps mariadb${NC}"
    return 1
}

# Fonction pour créer un nouveau projet Laravel
create_laravel_project() {
    local target_dir="$1"

    echo -e "${YELLOW}Création d'un nouveau projet Laravel dans $target_dir${NC}"

    # Vérifier les permissions d'écriture
    if [ ! -w "$target_dir" ]; then
        echo -e "${RED}Erreur : Pas de permission d'écriture dans $target_dir${NC}"
        echo -e "${YELLOW}Essayez avec sudo ou vérifiez les permissions${NC}"
        exit 1
    fi

    # Vérifier si le dossier est vide (ignorer les fichiers cachés comme .gitkeep)
    if [ "$(find "$target_dir" -mindepth 1 -maxdepth 1 ! -name '.*' | wc -l)" -gt 0 ]; then
        echo -e "${RED}Erreur : Le dossier $target_dir n'est pas vide${NC}"
        echo -e "${YELLOW}Contenu trouvé :${NC}"
        ls -la "$target_dir"
        echo -e "${YELLOW}Veuillez vider le dossier ou supprimer son contenu avant l'installation${NC}"
        exit 1
    fi

    # Aller dans le dossier cible et installer Laravel directement dedans
    cd "$target_dir"

    # Créer le projet Laravel dans le répertoire courant (.)
    if ! COMPOSER_MEMORY_LIMIT=-1 composer create-project laravel/laravel . --no-interaction; then
        echo -e "${RED}Échec de la création du projet Laravel${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Projet Laravel créé avec succès dans : $target_dir${NC}"
}

# Fonction pour installer un package avec gestion d'erreur
install_package() {
    local package=$1
    local type=${2:-"require"}  # require ou require-dev
    local max_attempts=3
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        echo -e "${YELLOW}Installation de $package (tentative $attempt/$max_attempts)...${NC}"

        # Nettoyer le cache avant l'installation
        composer clear-cache 2>/dev/null || true

        # Essayer d'installer le package
        local composer_cmd="COMPOSER_MEMORY_LIMIT=-1 composer $type \"$package\" --no-interaction --no-scripts --no-progress"

        if eval $composer_cmd 2>&1; then
            echo -e "${GREEN}✓ $package installé avec succès${NC}"

            # Exécuter les scripts post-installation séparément
            composer run-script post-autoload-dump --no-interaction 2>&1 || true

            return 0
        else
            echo -e "${RED}✗ Échec de l'installation de $package${NC}"

            if [ $attempt -lt $max_attempts ]; then
                echo -e "${YELLOW}Nouvelle tentative dans 5 secondes...${NC}"
                sleep 5
                attempt=$((attempt + 1))
            else
                echo -e "${RED}Impossible d'installer $package après $max_attempts tentatives${NC}"
                return 1
            fi
        fi
    done
}

# Fonction pour configurer la base de données MariaDB
configure_database() {
    echo -e "${BLUE}Configuration de la base de données MariaDB...${NC}"

    if [ -f ".env" ]; then
        # Sauvegarder le .env original
        cp .env .env.backup

        # Configurer pour MariaDB - plus robuste
        sed -i 's/DB_CONNECTION=.*/DB_CONNECTION=mysql/' .env
        sed -i 's/.*DB_HOST=.*/DB_HOST=mariadb/' .env
        sed -i 's/.*DB_PORT=.*/DB_PORT=3306/' .env
        sed -i 's/.*DB_DATABASE=.*/DB_DATABASE=laravel/' .env
        sed -i 's/.*DB_USERNAME=.*/DB_USERNAME=laravel_user/' .env
        sed -i 's/.*DB_PASSWORD=.*/DB_PASSWORD=secure_password/' .env

        # S'assurer que les lignes existent (Laravel 11+ peut les commenter)
        if ! grep -q "^DB_HOST=" .env; then
            echo "DB_HOST=mariadb" >> .env
        fi
        if ! grep -q "^DB_PORT=" .env; then
            echo "DB_PORT=3306" >> .env
        fi
        if ! grep -q "^DB_DATABASE=" .env; then
            echo "DB_DATABASE=laravel" >> .env
        fi
        if ! grep -q "^DB_USERNAME=" .env; then
            echo "DB_USERNAME=laravel_user" >> .env
        fi
        if ! grep -q "^DB_PASSWORD=" .env; then
            echo "DB_PASSWORD=secure_password" >> .env
        fi

        # Supprimer la ligne du fichier SQLite si elle existe
        sed -i '/DB_DATABASE=.*\.sqlite/d' .env

        # Configuration des sessions pour utiliser la base de données
        sed -i 's/SESSION_DRIVER=.*/SESSION_DRIVER=database/' .env

        # Configuration du cache pour Redis
        sed -i 's/CACHE_STORE=.*/CACHE_STORE=redis/' .env
        sed -i 's/QUEUE_CONNECTION=.*/QUEUE_CONNECTION=redis/' .env

        # Configuration Redis
        if ! grep -q "^REDIS_HOST=" .env; then
            echo "REDIS_HOST=redis" >> .env
        else
            sed -i 's/.*REDIS_HOST=.*/REDIS_HOST=redis/' .env
        fi

        if ! grep -q "^REDIS_PASSWORD=" .env; then
            echo "REDIS_PASSWORD=redis_secret_password" >> .env
        else
            sed -i 's/.*REDIS_PASSWORD=.*/REDIS_PASSWORD=redis_secret_password/' .env
        fi

        if ! grep -q "^REDIS_PORT=" .env; then
            echo "REDIS_PORT=6379" >> .env
        else
            sed -i 's/.*REDIS_PORT=.*/REDIS_PORT=6379/' .env
        fi

        echo -e "${GREEN}✓ Base de données configurée pour MariaDB avec sessions DB${NC}"
    else
        echo -e "${RED}⚠️  Fichier .env non trouvé${NC}"
    fi
}

# Fonction pour créer les fichiers de configuration des outils de qualité
create_quality_tools_config() {
    echo -e "${BLUE}Création des fichiers de configuration pour les outils de qualité...${NC}"

    # Configuration Easy Coding Standard (ECS)
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
        echo -e "${YELLOW}Configuration de Laravel Telescope...${NC}"

        # Activer Telescope en local et staging uniquement
        sed -i "s/'enabled' => env('TELESCOPE_ENABLED', true),/'enabled' => env('TELESCOPE_ENABLED', env('APP_ENV') !== 'production'),/" config/telescope.php

        # Configurer le stockage pour utiliser la base de données
        sed -i "s/'driver' => env('TELESCOPE_DRIVER', 'database'),/'driver' => 'database',/" config/telescope.php
    fi

    # Configuration PHP Insights
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

    echo -e "${GREEN}✓ Fichiers de configuration créés :${NC}"
    echo -e "  • ecs.php (Easy Coding Standard)"
    echo -e "  • rector.php (Rector)"
    echo -e "  • phpstan.neon (PHPStan/Larastan)"
    echo -e "  • config/insights.php (PHP Insights)"
    if [ -f "config/telescope.php" ]; then
        echo -e "  • config/telescope.php (Telescope configuré)"
    fi
}

# Fonction pour configurer le package.json avec des scripts utiles
configure_package_json() {
    echo -e "${BLUE}Configuration des scripts dans package.json...${NC}"

    if [ -f "package.json" ]; then
        # Ajouter des scripts personnalisés au package.json
        python3 << 'EOF'
import json

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
EOF
    fi
}

# Fonction pour configurer les scripts Composer
configure_composer_scripts() {
    echo -e "${BLUE}Configuration des scripts Composer...${NC}"

    if [ -f "composer.json" ]; then
        # Ajouter des scripts personnalisés au composer.json
        python3 << 'EOF'
import json

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
EOF
    fi
}

# Fonction pour optimiser Composer
optimize_composer() {
    echo -e "${YELLOW}Optimisation de Composer...${NC}"

    # Réparer la configuration d'abord
    fix_composer_config

    # Désactiver les plugins non essentiels (avec vérification)
    composer config --global allow-plugins.php-http/discovery false 2>/dev/null || true

    # Optimiser l'autoloader
    composer dump-autoload --optimize --no-interaction 2>/dev/null || true
}

# Fonction pour exécuter les migrations et seeders
run_migrations() {
    echo -e "${BLUE}🔄 Exécution des migrations...${NC}"

    # Attendre que la base de données soit prête
    if ! wait_for_database; then
        echo -e "${RED}❌ Impossible de continuer sans base de données${NC}"
        return 1
    fi

    # Exécuter les migrations avec --force pour éviter la confirmation en production
    echo -e "${YELLOW}→ Migration des tables Laravel de base...${NC}"
    if php artisan migrate --force --no-interaction; then
        echo -e "${GREEN}✓ Migrations de base exécutées${NC}"
    else
        echo -e "${RED}❌ Échec des migrations de base${NC}"
        return 1
    fi

    # Migrations spécifiques aux packages installés
    echo -e "${YELLOW}→ Migration des tables des packages...${NC}"

    # Créer la table sessions si elle n'existe pas (Laravel 11+)
    if ! php artisan tinker --execute="DB::select('SHOW TABLES LIKE \"sessions\"');" 2>/dev/null | grep -q "sessions"; then
        echo -e "${YELLOW}→ Création de la table sessions...${NC}"
        php artisan session:table --force 2>/dev/null || true
        php artisan migrate --force --no-interaction 2>/dev/null || true
    fi

    # Créer la table cache si elle n'existe pas
    if ! php artisan tinker --execute="DB::select('SHOW TABLES LIKE \"cache\"');" 2>/dev/null | grep -q "cache"; then
        echo -e "${YELLOW}→ Création de la table cache...${NC}"
        php artisan cache:table --force 2>/dev/null || true
        php artisan migrate --force --no-interaction 2>/dev/null || true
    fi

    # Créer les tables des queues
    if ! php artisan tinker --execute="DB::select('SHOW TABLES LIKE \"jobs\"');" 2>/dev/null | grep -q "jobs"; then
        echo -e "${YELLOW}→ Création des tables de queues...${NC}"
        php artisan queue:table --force 2>/dev/null || true
        php artisan queue:failed-table --force 2>/dev/null || true
        php artisan migrate --force --no-interaction 2>/dev/null || true
    fi

    # Migration finale pour s'assurer que tout est à jour
    echo -e "${YELLOW}→ Migration finale...${NC}"
    php artisan migrate --force --no-interaction 2>/dev/null || true

    echo -e "${GREEN}✅ Toutes les migrations terminées${NC}"

    # Optionnel : exécuter les seeders de base (uniquement si ils existent)
    if [ -f "database/seeders/DatabaseSeeder.php" ]; then
        echo -e "${YELLOW}→ Vérification des seeders...${NC}"
        if grep -q "run()" database/seeders/DatabaseSeeder.php; then
            echo -e "${YELLOW}→ Exécution des seeders...${NC}"
            php artisan db:seed --force --no-interaction 2>/dev/null || echo -e "${YELLOW}⚠️  Seeders non exécutés (normal pour une nouvelle installation)${NC}"
        fi
    fi
}

# Installation principale
main() {
    echo -e "${YELLOW}🚀 Installation complète de Laravel avec outils de qualité${NC}"

    # Détecter le répertoire de travail (normalement /var/www/html dans le container)
    WORKING_DIR=$(detect_working_directory)
    echo -e "${YELLOW}Répertoire de travail détecté : $WORKING_DIR${NC}"

    # Vérifier la mémoire disponible
    if command -v free &> /dev/null; then
        echo -e "${YELLOW}Mémoire disponible :${NC}"
        free -h | grep -E "^Mem|^Swap"
    fi

    # Optimiser Composer
    optimize_composer

    # Vérifier si on a déjà un projet Laravel
    if [ ! -f "$WORKING_DIR/composer.json" ]; then
        echo -e "${YELLOW}Aucun projet Laravel détecté dans $WORKING_DIR${NC}"
        echo -e "${YELLOW}Création d'un nouveau projet Laravel...${NC}"
        create_laravel_project "$WORKING_DIR"
    else
        echo -e "${GREEN}Projet Laravel existant détecté dans $WORKING_DIR${NC}"

        # Vérifier si c'est bien un projet Laravel
        if grep -q "laravel/framework" "$WORKING_DIR/composer.json"; then
            echo -e "${GREEN}✓ Projet Laravel valide trouvé${NC}"
        else
            echo -e "${YELLOW}⚠️  Le composer.json existe mais ne semble pas être un projet Laravel${NC}"
        fi
    fi

    # Se déplacer dans le répertoire de travail pour les installations
    cd "$WORKING_DIR"

    # Configurer la base de données MariaDB
    configure_database

    # Packages de production
    echo -e "${BLUE}Installation des packages de production...${NC}"
    production_packages=(
        "laravel/horizon"
        "laravel/telescope"
        "laravel/sanctum"
        "spatie/laravel-permission"
        "spatie/laravel-activitylog"
    )

    for package in "${production_packages[@]}"; do
        if ! install_package "$package" "require"; then
            echo -e "${RED}⚠️  Échec de l'installation de $package${NC}"
        fi
        sleep 2
    done

    # Packages de développement
    echo -e "${BLUE}Installation des outils de qualité de code...${NC}"
    dev_packages=(
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
            echo -e "${RED}⚠️  Échec de l'installation de $package${NC}"
        fi
        sleep 2
    done

    # Installation finale et optimisation
    echo -e "${YELLOW}Finalisation de l'installation...${NC}"
    COMPOSER_MEMORY_LIMIT=-1 composer install --no-interaction --optimize-autoloader

    # Publier les assets et configurations
    if [ -f "artisan" ]; then
        echo -e "${YELLOW}Publication des assets et configurations...${NC}"

        # Horizon
        php artisan vendor:publish --tag=horizon-config --force 2>/dev/null || true
        php artisan vendor:publish --tag=horizon-assets --force 2>/dev/null || true

        # Telescope
        php artisan vendor:publish --tag=telescope-config --force 2>/dev/null || true
        php artisan vendor:publish --tag=telescope-migrations --force 2>/dev/null || true

        # Sanctum
        php artisan vendor:publish --provider="Laravel\Sanctum\SanctumServiceProvider" --force 2>/dev/null || true

        # Spatie packages
        php artisan vendor:publish --provider="Spatie\Permission\PermissionServiceProvider" --force 2>/dev/null || true
        php artisan vendor:publish --provider="Spatie\Activitylog\ActivitylogServiceProvider" --tag="activitylog-migrations" --force 2>/dev/null || true

        # Laravel IDE Helper
        php artisan vendor:publish --provider="Barryvdh\LaravelIdeHelper\IdeHelperServiceProvider" --tag=config --force 2>/dev/null || true

        # Laravel Query Detector
        php artisan vendor:publish --provider="BeyondCode\QueryDetector\QueryDetectorServiceProvider" --force 2>/dev/null || true

        # Enlightn
        php artisan vendor:publish --tag=enlightn --force 2>/dev/null || true

        # Générer la clé d'application si nécessaire
        if ! grep -q "APP_KEY=.*" .env || grep -q "APP_KEY=$" .env; then
            echo -e "${YELLOW}Génération de la clé d'application...${NC}"
            php artisan key:generate --no-interaction --force
        fi

        # IMPORTANT : Exécuter les migrations maintenant
        echo -e "${BLUE}🗄️  Configuration de la base de données...${NC}"
        run_migrations

        # Générer les fichiers IDE Helper après les migrations
        echo -e "${YELLOW}Génération des fichiers IDE Helper...${NC}"
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
    echo -e "${YELLOW}Optimisation des caches...${NC}"
    php artisan config:cache 2>/dev/null || true
    php artisan route:cache 2>/dev/null || true
    php artisan view:cache 2>/dev/null || true

    # Afficher un résumé de l'installation
    echo -e "${GREEN}✅ Installation terminée avec succès !${NC}"
    echo -e "${YELLOW}📂 Fichiers Laravel installés dans : $WORKING_DIR${NC}"
    echo -e "${YELLOW}📊 Structure créée :${NC}"
    ls -la "$WORKING_DIR" | head -15

    echo -e "${BLUE}🛠️  Outils de qualité installés :${NC}"
    echo -e "  • Easy Coding Standard (ECS) - Vérification du style de code"
    echo -e "  • Rector - Refactoring automatique"
    echo -e "  • PHPStan/Larastan - Analyse statique"
    echo -e "  • PHP Insights - Analyse globale de la qualité"
    echo -e "  • Laravel IDE Helper - Autocomplétion IDE"
    echo -e "  • Laravel Query Detector - Détection requêtes N+1"
    echo -e "  • Enlightn - Audit de sécurité et performance"
    echo -e "  • Pest - Framework de tests"

    echo -e "${BLUE}📦 Packages Laravel installés :${NC}"
    echo -e "  • Laravel Horizon - Gestion des queues"
    echo -e "  • Laravel Telescope - Debugging et monitoring"
    echo -e "  • Laravel Sanctum - Authentification API"
    echo -e "  • Spatie Permission - Gestion des rôles et permissions"
    echo -e "  • Spatie Activity Log - Journal d'activité"

    echo -e "${BLUE}🗄️  Base de données configurée :${NC}"
    echo -e "  • MariaDB (au lieu de SQLite)"
    echo -e "  • Host: mariadb, Port: 3306"
    echo -e "  • Database: laravel, User: laravel_user"
    echo -e "  • ✅ Toutes les migrations exécutées"
    echo -e "  • ✅ Tables sessions, cache, jobs créées"

    echo -e "${BLUE}⚡ Scripts disponibles :${NC}"
    echo -e "  • composer quality - Vérifier la qualité du code (ECS + PHPStan + Insights)"
    echo -e "  • composer quality:fix - Corriger automatiquement"
    echo -e "  • composer quality:full - Audit complet (qualité + sécurité + tests)"
    echo -e "  • composer insights - Analyse PHP Insights"
    echo -e "  • composer enlightn - Audit sécurité et performance"
    echo -e "  • composer ide-helper - Générer les fichiers IDE Helper"
    echo -e "  • composer test:coverage - Tests avec couverture"

    # Vérifier les fichiers importants
    echo -e "${YELLOW}📋 Vérification des fichiers :${NC}"
    files_to_check=("package.json" ".env" "ecs.php" "rector.php" "phpstan.neon")
    for file in "${files_to_check[@]}"; do
        if [ -f "$WORKING_DIR/$file" ]; then
            echo -e "${GREEN}✓ $file${NC}"
        else
            echo -e "${RED}✗ $file manquant${NC}"
        fi
    done

    # Vérifier les tables importantes
    echo -e "${YELLOW}📋 Vérification des tables importantes :${NC}"
    important_tables=("users" "sessions" "cache" "jobs" "failed_jobs")
    for table in "${important_tables[@]}"; do
        if php artisan tinker --execute="DB::select('SHOW TABLES LIKE \"$table\"');" 2>/dev/null | grep -q "$table"; then
            echo -e "${GREEN}✓ Table $table${NC}"
        else
            echo -e "${RED}✗ Table $table manquante${NC}"
        fi
    done

    echo -e "${GREEN}🎉 Installation complète terminée !${NC}"
    echo -e "${YELLOW}Prochaines étapes :${NC}"
    echo -e "1. ✅ Base de données configurée et migrée"
    echo -e "2. Accéder à l'application : https://laravel.local"
    echo -e "3. Lancer les tests : composer test:coverage"
    echo -e "4. Vérifier la qualité : composer quality"
    echo -e "5. Configurer le monitoring : make setup-monitoring"
}

# Exécuter l'installation
main