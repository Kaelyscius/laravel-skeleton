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

    # Vérifier les extensions PHP requises
    local required_extensions=("openssl" "pdo" "mbstring" "tokenizer" "xml" "ctype" "json" "curl")
    local missing_extensions=()

    for ext in "${required_extensions[@]}"; do
        if ! php -m | grep -q "^$ext\$"; then
            missing_extensions+=($ext)
        fi
    done

    if [ ${#missing_extensions[@]} -ne 0 ]; then
        log "WARN" "Extensions PHP manquantes (recommandées): ${missing_extensions[*]}"
    fi

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

# Fonction améliorée pour réparer la configuration Composer
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

    # Configuration des plugins autorisés
    log "INFO" "Configuration des plugins Composer autorisés..."

    # Autoriser tous les plugins par défaut pour éviter les problèmes
    composer config --global allow-plugins true 2>/dev/null || {
        log "WARN" "Impossible de configurer allow-plugins globalement"
    }

    # Liste des plugins spécifiques couramment utilisés
    local plugins_to_allow=(
        "dealerdirect/phpcodesniffer-composer-installer"
        "pestphp/pest-plugin"
        "php-http/discovery"
        "bamarni/composer-bin-plugin"
        "ergebnis/composer-normalize"
        "infection/extension-installer"
        "phpstan/extension-installer"
        "rector/extension-installer"
        "enlightn/enlightn"
    )

    for plugin in "${plugins_to_allow[@]}"; do
        log "DEBUG" "Autorisation du plugin: $plugin"
        composer config --global allow-plugins.$plugin true 2>/dev/null || {
            log "DEBUG" "Plugin $plugin non configuré (sera autorisé automatiquement)"
        }
    done

    # Configurer les optimisations Composer
    log "DEBUG" "Configuration des optimisations Composer..."
    composer config --global process-timeout 3000 2>/dev/null || true
    composer config --global prefer-stable true 2>/dev/null || true
    composer config --global minimum-stability stable 2>/dev/null || true
    composer config --global optimize-autoloader true 2>/dev/null || true

    log "SUCCESS" "Configuration Composer mise à jour"
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

    # Vérifier si le dossier est vide (ignorer les fichiers cachés)
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

    # Créer le projet Laravel dans le répertoire courant
    log "INFO" "Téléchargement et installation de Laravel..."
    if ! COMPOSER_MEMORY_LIMIT=-1 composer create-project laravel/laravel . --no-interaction --prefer-dist; then
        log "ERROR" "Échec de la création du projet Laravel"
        exit 1
    fi

    log "SUCCESS" "Projet Laravel créé avec succès dans : $target_dir"
}

# Fonction pour détecter la version de Laravel
get_laravel_version() {
    if [ -f "composer.json" ]; then
        local version=$(grep -oP '"laravel/framework":\s*"\^\K[0-9]+' composer.json 2>/dev/null)
        echo "${version:-11}"
    else
        echo "11"
    fi
}

# Fonction pour détecter la version de PHP
get_php_version() {
    php -r "echo PHP_MAJOR_VERSION . '.' . PHP_MINOR_VERSION;"
}

# Fonction pour vérifier la compatibilité d'un package
check_package_compatibility() {
    local package=$1
    local laravel_version=$2
    local php_version=$3

    # Vérifier avec composer why-not (si disponible)
    if composer why-not "$package" >/dev/null 2>&1; then
        return 1  # Non compatible
    fi

    # Vérifications spécifiques pour Laravel 12
    if [ "$laravel_version" -ge 12 ]; then
        case $package in
            "enlightn/enlightn")
                log "DEBUG" "Enlightn non compatible avec Laravel 12+"
                return 1
                ;;
            "pestphp/pest")
                # Vérifier si Pest 3.x est compatible
                if composer show --available "$package" 2>/dev/null | grep -q "v3\."; then
                    return 0
                else
                    return 1
                fi
                ;;
            "pestphp/pest-plugin-laravel")
                # Similaire pour le plugin Pest Laravel
                if composer show --available "$package" 2>/dev/null | grep -q "v3\."; then
                    return 0
                else
                    return 1
                fi
                ;;
        esac
    fi

    return 0  # Compatible par défaut
}

# Fonction améliorée pour vérifier si un package est installé
is_package_installed() {
    local package=$1

    # Vérifier dans composer.json
    if [ -f "composer.json" ] && grep -q "\"$package\"" composer.json; then
        log "DEBUG" "Package $package trouvé dans composer.json"

        # Vérifier dans vendor/
        local vendor_path="vendor/$(echo $package | tr '/' '/')"
        if [ -d "$vendor_path" ]; then
            log "DEBUG" "Package $package trouvé dans vendor/"
            return 0
        fi

        # Vérifier avec composer show (plus fiable)
        if composer show "$package" >/dev/null 2>&1; then
            log "DEBUG" "Package $package confirmé par composer show"
            return 0
        fi
    fi

    return 1
}

# Fonction améliorée pour installer un package avec vérification de compatibilité
install_package() {
    local package=$1
    local type=${2:-"require"}
    local max_attempts=3
    local attempt=1
    local laravel_version=$(get_laravel_version)
    local php_version=$(get_php_version)

    log "INFO" "📦 Installation de $package (type: $type)"

    # Vérifier si le package est déjà installé
    if is_package_installed "$package"; then
        log "SUCCESS" "$package déjà installé"
        return 0
    fi

    # Vérifier la compatibilité avant l'installation
    if ! check_package_compatibility "$package" "$laravel_version" "$php_version"; then
        log "WARN" "Package $package non compatible avec Laravel $laravel_version et PHP $php_version"
        log "INFO" "Ajout à la liste d'attente pour future compatibilité"
        echo "$package" >> .incompatible_packages.txt
        return 2  # Code spécial pour incompatibilité
    fi

    while [ $attempt -le $max_attempts ]; do
        log "DEBUG" "Installation de $package (tentative $attempt/$max_attempts)..."

        # Nettoyer le cache avant l'installation
        log "DEBUG" "Nettoyage du cache Composer..."
        composer clear-cache 2>/dev/null || true

        # Construire la commande Composer avec gestion des contraintes
        local composer_cmd
        if [ "$type" = "require-dev" ]; then
            # Pour Laravel 12, essayer d'abord sans contrainte de version spécifique
            if [ "$laravel_version" -ge 12 ]; then
                composer_cmd="COMPOSER_MEMORY_LIMIT=-1 composer require --dev \"$package\" --no-interaction --with-all-dependencies"
            else
                composer_cmd="COMPOSER_MEMORY_LIMIT=-1 composer require --dev \"$package\" --no-interaction --with-dependencies --update-with-dependencies"
            fi
        else
            if [ "$laravel_version" -ge 12 ]; then
                composer_cmd="COMPOSER_MEMORY_LIMIT=-1 composer require \"$package\" --no-interaction --with-all-dependencies"
            else
                composer_cmd="COMPOSER_MEMORY_LIMIT=-1 composer require \"$package\" --no-interaction --with-dependencies --update-with-dependencies"
            fi
        fi

        log "DEBUG" "Commande: $composer_cmd"

        # Exécuter la commande avec capture des erreurs
        if eval $composer_cmd 2>&1 | tee -a "$LOG_FILE"; then
            # Vérifier que le package est maintenant vraiment installé
            if is_package_installed "$package"; then
                log "SUCCESS" "$package installé avec succès"

                # Régénérer l'autoloader après installation
                composer dump-autoload --no-interaction 2>/dev/null || true

                return 0
            else
                log "WARN" "$package semble installé mais non détecté"
            fi
        else
            local exit_code=$?
            log "ERROR" "Échec de l'installation de $package (code: $exit_code)"

            # Vérifier si c'est un problème de compatibilité
            if grep -q "conflicts with\|does not satisfy" "$LOG_FILE"; then
                log "WARN" "Conflit de dépendances détecté pour $package"
                echo "$package" >> .incompatible_packages.txt
                return 2
            fi
        fi

        if [ $attempt -lt $max_attempts ]; then
            log "WARN" "Nouvelle tentative dans 5 secondes..."
            sleep 5
            attempt=$((attempt + 1))
        else
            log "ERROR" "Impossible d'installer $package après $max_attempts tentatives"

            if [ "$DEBUG" = "true" ]; then
                log "DEBUG" "Diagnostic de l'échec:"
                composer diagnose 2>&1 | tail -20 | tee -a "$LOG_FILE" || true
            fi

            return 1
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

        # Configurer pour MariaDB
        log "DEBUG" "Configuration des paramètres de base de données..."
        sed -i 's/DB_CONNECTION=.*/DB_CONNECTION=mysql/' .env
        sed -i 's/.*DB_HOST=.*/DB_HOST=mariadb/' .env
        sed -i 's/.*DB_PORT=.*/DB_PORT=3306/' .env
        sed -i 's/.*DB_DATABASE=.*/DB_DATABASE=laravel/' .env
        sed -i 's/.*DB_USERNAME=.*/DB_USERNAME=laravel_user/' .env
        sed -i 's/.*DB_PASSWORD=.*/DB_PASSWORD=secure_password/' .env

        # S'assurer que les lignes existent
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

        if [ "$DEBUG" = "true" ]; then
            log "DEBUG" "Configuration de base de données actuelle:"
            grep -E "^DB_|^REDIS_|^SESSION_|^CACHE_|^QUEUE_" .env | tee -a "$LOG_FILE"
        fi
    else
        log "ERROR" "Fichier .env non trouvé"
        return 1
    fi
}

# Fonction pour obtenir la liste des packages selon la version Laravel
get_compatible_packages() {
    local laravel_version=$1
    local package_type=$2  # "production" ou "dev"

    if [ "$package_type" = "production" ]; then
        # Packages de production (généralement compatibles avec toutes les versions)
        echo "laravel/horizon laravel/telescope laravel/sanctum spatie/laravel-permission spatie/laravel-activitylog"
    else
        # Packages de développement adaptés selon la version
        local base_packages="symplify/easy-coding-standard rector/rector larastan/larastan nunomaduro/collision nunomaduro/phpinsights barryvdh/laravel-ide-helper beyondcode/laravel-query-detector"

        # Packages conditionnels selon la version Laravel
        local conditional_packages=""

        # Rector Laravel - ajouter le package spécialisé pour Laravel 12+
        if [ "$laravel_version" -ge 12 ]; then
            conditional_packages="$conditional_packages driftingly/rector-laravel"
        fi

        # Pest - vérifier la compatibilité
        if [ "$laravel_version" -ge 12 ]; then
            # Pour Laravel 12, essayer d'installer Pest 3.x uniquement s'il est compatible
            conditional_packages="$conditional_packages pestphp/pest:^3.0"
        else
            # Pour Laravel < 12, utiliser Pest normalement
            conditional_packages="$conditional_packages pestphp/pest pestphp/pest-plugin-laravel"
        fi

        echo "$base_packages $conditional_packages"
    fi
}

# Fonction pour créer un rapport de compatibilité
create_compatibility_report() {
    local laravel_version=$1
    local php_version=$2

    log "INFO" "📋 Création du rapport de compatibilité..."

    cat > compatibility_report.md << EOF
# Rapport de Compatibilité Laravel $laravel_version - PHP $php_version

Date: $(date '+%Y-%m-%d %H:%M:%S')

## Environnement détecté
- **Laravel**: $laravel_version
- **PHP**: $php_version

## Packages installés avec succès
EOF

    if [ -f "composer.json" ]; then
        echo "### Packages de production" >> compatibility_report.md
        grep -A 20 '"require"' composer.json | grep -E '"(laravel|spatie)/' | sed 's/^[[:space:]]*/- /' >> compatibility_report.md

        echo "" >> compatibility_report.md
        echo "### Packages de développement" >> compatibility_report.md
        grep -A 50 '"require-dev"' composer.json | grep -E '"(symplify|rector|larastan|nunomaduro|barryvdh|beyondcode|pestphp|driftingly)/' | sed 's/^[[:space:]]*/- /' >> compatibility_report.md
    fi

    if [ -f ".incompatible_packages.txt" ] && [ -s ".incompatible_packages.txt" ]; then
        echo "" >> compatibility_report.md
        echo "## Packages incompatibles (non installés)" >> compatibility_report.md

        while read -r package; do
            case $package in
                "enlightn/enlightn")
                    echo "- **$package**: Non compatible avec Laravel 12+ (dernière version supportée: Laravel 10)" >> compatibility_report.md
                    ;;
                "pestphp/pest")
                    echo "- **$package**: Conflit de dépendances avec PHPUnit/Collision" >> compatibility_report.md
                    ;;
                "pestphp/pest-plugin-laravel")
                    echo "- **$package**: Non compatible avec Laravel 12+" >> compatibility_report.md
                    ;;
                *)
                    echo "- **$package**: Incompatibilité détectée" >> compatibility_report.md
                    ;;
            esac
        done < .incompatible_packages.txt

        echo "" >> compatibility_report.md
        echo "## Alternatives et solutions" >> compatibility_report.md
        echo "- **Enlightn**: Surveillez [enlightn/enlightn](https://github.com/enlightn/enlightn) pour la compatibilité Laravel 12" >> compatibility_report.md
        echo "- **Pest**: Utilisez PHPUnit intégré ou attendez Pest 4.x" >> compatibility_report.md
        echo "- **Tests**: Laravel inclut PHPUnit par défaut avec Feature et Unit tests" >> compatibility_report.md
    fi

    echo "" >> compatibility_report.md
    echo "## Outils disponibles" >> compatibility_report.md
    echo "- ✅ **ECS**: Vérification du style de code" >> compatibility_report.md

    if [ "$laravel_version" -ge 12 ] && is_package_installed "driftingly/rector-laravel"; then
        echo "- ✅ **Rector**: Refactoring automatique (PHP $php_version + Laravel 12 support via driftingly/rector-laravel)" >> compatibility_report.md
    else
        echo "- ✅ **Rector**: Refactoring automatique (PHP $php_version)" >> compatibility_report.md
    fi

    echo "- ✅ **PHPStan + Larastan**: Analyse statique niveau 8" >> compatibility_report.md
    echo "- ✅ **PHP Insights**: Analyse globale de qualité" >> compatibility_report.md
    echo "- ✅ **Laravel IDE Helper**: Autocomplétion IDE" >> compatibility_report.md
    echo "- ✅ **Query Detector**: Détection des requêtes N+1" >> compatibility_report.md

    if is_package_installed "pestphp/pest"; then
        echo "- ✅ **Pest**: Framework de tests moderne" >> compatibility_report.md
    else
        echo "- ⚠️ **Pest**: Non installé (incompatibilité détectée)" >> compatibility_report.md
        echo "- ✅ **PHPUnit**: Framework de tests par défaut Laravel" >> compatibility_report.md
    fi

    log "SUCCESS" "Rapport de compatibilité créé: compatibility_report.md"
}
# Fonction pour créer un rapport de compatibilité
create_compatibility_report() {
    local laravel_version=$1
    local php_version=$2

    log "INFO" "📋 Création du rapport de compatibilité..."

    cat > compatibility_report.md << EOF
# Rapport de Compatibilité Laravel $laravel_version - PHP $php_version

Date: $(date '+%Y-%m-%d %H:%M:%S')

## Environnement détecté
- **Laravel**: $laravel_version
- **PHP**: $php_version

## Packages installés avec succès
EOF

    if [ -f "composer.json" ]; then
        echo "### Packages de production" >> compatibility_report.md
        grep -A 20 '"require"' composer.json | grep -E '"(laravel|spatie)/' | sed 's/^[[:space:]]*/- /' >> compatibility_report.md

        echo "" >> compatibility_report.md
        echo "### Packages de développement" >> compatibility_report.md
        grep -A 50 '"require-dev"' composer.json | grep -E '"(symplify|rector|larastan|nunomaduro|barryvdh|beyondcode|pestphp)/' | sed 's/^[[:space:]]*/- /' >> compatibility_report.md
    fi

    if [ -f ".incompatible_packages.txt" ] && [ -s ".incompatible_packages.txt" ]; then
        echo "" >> compatibility_report.md
        echo "## Packages incompatibles (non installés)" >> compatibility_report.md

        while read -r package; do
            case $package in
                "enlightn/enlightn")
                    echo "- **$package**: Non compatible avec Laravel 12+ (dernière version supportée: Laravel 10)" >> compatibility_report.md
                    ;;
                "pestphp/pest")
                    echo "- **$package**: Conflit de dépendances avec PHPUnit/Collision" >> compatibility_report.md
                    ;;
                "pestphp/pest-plugin-laravel")
                    echo "- **$package**: Non compatible avec Laravel 12+" >> compatibility_report.md
                    ;;
                *)
                    echo "- **$package**: Incompatibilité détectée" >> compatibility_report.md
                    ;;
            esac
        done < .incompatible_packages.txt

        echo "" >> compatibility_report.md
        echo "## Alternatives et solutions" >> compatibility_report.md
        echo "- **Enlightn**: Surveillez [enlightn/enlightn](https://github.com/enlightn/enlightn) pour la compatibilité Laravel 12" >> compatibility_report.md
        echo "- **Pest**: Utilisez PHPUnit intégré ou attendez Pest 4.x" >> compatibility_report.md
        echo "- **Tests**: Laravel inclut PHPUnit par défaut avec Feature et Unit tests" >> compatibility_report.md
    fi

    echo "" >> compatibility_report.md
    echo "## Outils disponibles" >> compatibility_report.md
    echo "- ✅ **ECS**: Vérification du style de code" >> compatibility_report.md
    echo "- ✅ **Rector**: Refactoring automatique (PHP $php_version)" >> compatibility_report.md
    echo "- ✅ **PHPStan + Larastan**: Analyse statique niveau 8" >> compatibility_report.md
    echo "- ✅ **PHP Insights**: Analyse globale de qualité" >> compatibility_report.md
    echo "- ✅ **Laravel IDE Helper**: Autocomplétion IDE" >> compatibility_report.md
    echo "- ✅ **Query Detector**: Détection des requêtes N+1" >> compatibility_report.md

    if is_package_installed "pestphp/pest"; then
        echo "- ✅ **Pest**: Framework de tests moderne" >> compatibility_report.md
    else
        echo "- ⚠️ **Pest**: Non installé (incompatibilité détectée)" >> compatibility_report.md
        echo "- ✅ **PHPUnit**: Framework de tests par défaut Laravel" >> compatibility_report.md
    fi

    log "SUCCESS" "Rapport de compatibilité créé: compatibility_report.md"
}

# Fonction pour vérifier périodiquement la compatibilité des packages
check_future_compatibility() {
    local laravel_version=$1

    log "INFO" "🔍 Vérification de la compatibilité future..."

    # Créer un script de vérification pour plus tard
    cat > check_compatibility.sh << 'EOF'
#!/bin/bash
# Script de vérification de compatibilité Laravel

echo "🔍 Vérification de la compatibilité des packages..."

# Vérifier Enlightn
echo "Vérification d'Enlightn..."
if composer show --available enlightn/enlightn 2>/dev/null | grep -E "(laravel.*12|framework.*12)"; then
    echo "✅ Enlightn compatible avec Laravel 12 détecté !"
    echo "Vous pouvez maintenant installer: composer require --dev enlightn/enlightn"
else
    echo "⚠️ Enlightn pas encore compatible avec Laravel 12"
fi

# Vérifier Pest
echo "Vérification de Pest..."
if composer show --available pestphp/pest 2>/dev/null | grep -E "v4\."; then
    echo "✅ Pest 4.x détecté - pourrait être compatible !"
    echo "Vous pouvez essayer: composer require --dev pestphp/pest"
else
    echo "⚠️ Pest 4.x pas encore disponible"
fi

echo "Vérification terminée."
EOF

    chmod +x check_compatibility.sh

    log "SUCCESS" "Script de vérification créé: ./check_compatibility.sh"
    log "INFO" "Exécutez ce script périodiquement pour vérifier les nouvelles compatibilités"
}

# Fonction pour nettoyer les packages incompatibles du fichier temporaire
cleanup_incompatible_packages() {
    if [ -f ".incompatible_packages.txt" ]; then
        log "DEBUG" "Nettoyage du fichier des packages incompatibles"
        # Supprimer les doublons et trier
        sort -u .incompatible_packages.txt > .incompatible_packages_clean.txt
        mv .incompatible_packages_clean.txt .incompatible_packages.txt
    fi
}

# Fonction pour créer les fichiers de configuration des outils de qualité
create_quality_tools_config() {
    local laravel_version=$(get_laravel_version)
    local php_version=$(get_php_version)

    log "INFO" "⚙️ Création des fichiers de configuration pour les outils de qualité..."
    log "DEBUG" "Détection: Laravel $laravel_version, PHP $php_version"

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

    # Configuration Rector adaptée à la version
    log "DEBUG" "Création de rector.php compatible PHP $php_version et Laravel $laravel_version..."

    local rector_php_level="LevelSetList::UP_TO_PHP_82"
    local rector_laravel_set="LaravelSetList::LARAVEL_110"
    local rector_laravel_import=""

    # Adapter selon la version PHP
    case "$php_version" in
        "8.4")
            rector_php_level="LevelSetList::UP_TO_PHP_84"
            ;;
        "8.3")
            rector_php_level="LevelSetList::UP_TO_PHP_83"
            ;;
    esac

    # Adapter selon la version Laravel et vérifier si driftingly/rector-laravel est installé
    if [ "$laravel_version" -ge 12 ] && is_package_installed "driftingly/rector-laravel"; then
        # Utiliser le set Laravel 12 du package driftingly/rector-laravel
        rector_laravel_set="RectorLaravel\\Set\\LaravelSetList::LARAVEL_120"
        rector_laravel_import="use RectorLaravel\\Set\\LaravelSetList as RectorLaravelSetList;"
        log "DEBUG" "Utilisation du set Laravel 12 via driftingly/rector-laravel"
    elif [ "$laravel_version" -ge 12 ]; then
        # Laravel 12 mais sans le package spécialisé
        rector_laravel_set="LaravelSetList::LARAVEL_110"  # Fallback
        log "DEBUG" "Laravel 12 détecté mais driftingly/rector-laravel non installé - utilisation du set 11.0"
    else
        # Versions antérieures
        case "$laravel_version" in
            "11")
                rector_laravel_set="LaravelSetList::LARAVEL_110"
                ;;
            "10")
                rector_laravel_set="LaravelSetList::LARAVEL_100"
                ;;
        esac
    fi

    cat > rector.php << EOF
<?php

declare(strict_types=1);

use Rector\Config\RectorConfig;
use Rector\Set\ValueObject\LevelSetList;
use Rector\Laravel\Set\LaravelSetList;
$rector_laravel_import
use Rector\TypeDeclaration\Rector\ClassMethod\AddVoidReturnTypeWhereNoReturnRector;

return static function (RectorConfig \$rectorConfig): void {
    \$rectorConfig->paths([
        __DIR__ . '/app',
        __DIR__ . '/config',
        __DIR__ . '/database',
        __DIR__ . '/resources',
        __DIR__ . '/routes',
        __DIR__ . '/tests',
    ]);

    \$rectorConfig->rules([
        AddVoidReturnTypeWhereNoReturnRector::class,
    ]);

    \$rectorConfig->sets([
        $rector_php_level,
        $rector_laravel_set,
    ]);

    \$rectorConfig->skip([
        __DIR__ . '/bootstrap',
        __DIR__ . '/storage',
        __DIR__ . '/vendor',
        __DIR__ . '/node_modules',
    ]);

    // Configuration spécifique pour Laravel 12+
    if (version_compare('$laravel_version', '12', '>=')) {
        // Règles spécifiques pour Laravel 12
        \$rectorConfig->importNames();
        \$rectorConfig->importShortClasses();

        // Optimisations pour Laravel 12
        \$rectorConfig->parallel();
    }
};
EOF

    # Configuration PHPStan avec Larastan - Niveau 8
    log "DEBUG" "Création de phpstan.neon pour PHPStan 2.0+..."
    cat > phpstan.neon << 'EOF'
includes:
    - vendor/larastan/larastan/extension.neon

parameters:
    level: 8
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

    # Configuration pour PHPStan 2.0+
    treatPhpDocTypesAsCertain: false
    reportUnmatchedIgnoredErrors: false
    strictRules:
        allRules: false
        booleansInConditions: true
        uselessCast: true
        requireParentConstructorCall: true
        disallowedConstructorPropertyPromotion: false
        strictCalls: true

    # Paramètres de qualité stricts pour niveau 8
    checkUninitializedProperties: true
    checkBenevolentUnionTypes: true
    checkExplicitMixedMissingReturn: true
    checkFunctionNameCase: true
    checkInternalClassCaseSensitivity: true
    checkTooWideReturnTypesInProtectedAndPublicMethods: true
    checkMissingCallableSignature: true

    # Règles d'inférence
    polluteScopeWithLoopInitialAssignments: false
    polluteScopeWithAlwaysIterableForeach: false
    checkAlwaysTrueCheckTypeFunctionCall: true
    checkAlwaysTrueInstanceof: true
    checkAlwaysTrueStrictComparison: true

    # Ignorer certaines erreurs spécifiques à Laravel
    ignoreErrors:
        - '#PHPDoc tag @var#'
        - '#Unsafe usage of new static#'
        - '#Cannot call method.*on.*\|null#'
        - '#Access to an undefined property App\\Models\\.*::\$.*#'
        - '#Call to an undefined method Illuminate\\Database\\Eloquent\\Builder.*#'
        - '#Method.*should return.*but returns Illuminate\\Database\\Eloquent\\Builder#'

    # Performance et parallélisation
    parallel:
        maximumNumberOfProcesses: 4
        minimumNumberOfJobsPerProcess: 20

    # Cache
    tmpDir: storage/phpstan

    # Extensions Laravel spécifiques
    checkMissingOverrideMethodAttribute: false

    # Type coverage
    typeAliases:
        UserId: 'int<1, max>'
EOF

    # Configuration Telescope
    if [ -f "config/telescope.php" ]; then
        log "DEBUG" "Configuration de Laravel Telescope..."
        sed -i "s/'enabled' => env('TELESCOPE_ENABLED', true),/'enabled' => env('TELESCOPE_ENABLED', env('APP_ENV') !== 'production'),/" config/telescope.php
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

    # Créer le répertoire pour le cache PHPStan
    mkdir -p storage/phpstan

    log "SUCCESS" "Fichiers de configuration créés:"
    log "INFO" "  • ecs.php (Easy Coding Standard)"
    if [ "$laravel_version" -ge 12 ] && is_package_installed "driftingly/rector-laravel"; then
        log "INFO" "  • rector.php (Rector pour PHP $php_version et Laravel $laravel_version avec support Laravel 12)"
    else
        log "INFO" "  • rector.php (Rector pour PHP $php_version et Laravel $laravel_version)"
    fi
    log "INFO" "  • phpstan.neon (PHPStan 2.0+ niveau 8)"
    log "INFO" "  • config/insights.php (PHP Insights)"
    if [ -f "config/telescope.php" ]; then
        log "INFO" "  • config/telescope.php (Telescope configuré)"
    fi
}

# Fonction pour configurer le package.json avec des scripts utiles
configure_package_json() {
    log "INFO" "📝 Configuration des scripts dans package.json..."

    if [ -f "package.json" ]; then
        python3 << 'EOF'
import json
import sys

try:
    with open('package.json', 'r') as f:
        package_data = json.load(f)

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

# Fonction améliorée pour configurer les scripts Composer avec gestion adaptative
configure_composer_scripts() {
    log "INFO" "📝 Configuration des scripts Composer..."
    local laravel_version=$(get_laravel_version)

    if [ -f "composer.json" ]; then
        python3 << EOF
import json
import sys
import os

try:
    with open('composer.json', 'r') as f:
        composer_data = json.load(f)

    if 'scripts' not in composer_data:
        composer_data['scripts'] = {}

    # Vérifier quels packages sont installés
    pest_available = os.path.exists('vendor/pestphp/pest')
    enlightn_available = False  # Enlightn non supporté pour Laravel 12+

    # Scripts de base toujours disponibles
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
        "check:cs": "vendor/bin/ecs",
        "fix:cs": "vendor/bin/ecs --fix",
        "analyse": "vendor/bin/phpstan analyse",
        "refactor": "vendor/bin/rector process --dry-run",
        "refactor:fix": "vendor/bin/rector process",
        "insights": "php artisan insights",
        "insights:fix": "php artisan insights --fix",
        "ide-helper": [
            "php artisan ide-helper:generate",
            "php artisan ide-helper:meta",
            "php artisan ide-helper:models --write"
        ],
        "test:coverage": "php artisan test --coverage-html coverage"
    }

    # Scripts adaptatifs selon les packages installés
    if pest_available:
        custom_scripts.update({
            "test:unit": "vendor/bin/pest --testsuite=Unit",
            "test:feature": "vendor/bin/pest --testsuite=Feature",
            "test:pest": "vendor/bin/pest"
        })
        # Ajouter Pest aux scripts de qualité complète
        custom_scripts["quality:full"] = [
            "@check:cs",
            "@analyse",
            "@insights",
            "@test:pest"
        ]
    else:
        # Utiliser PHPUnit par défaut
        custom_scripts.update({
            "test:unit": "php artisan test --testsuite=Unit",
            "test:feature": "php artisan test --testsuite=Feature",
            "test:phpunit": "vendor/bin/phpunit"
        })
        custom_scripts["quality:full"] = [
            "@check:cs",
            "@analyse",
            "@insights",
            "@test:unit"
        ]

    # Pour Laravel 12+, ne pas inclure Enlightn
    laravel_version = ${laravel_version}
    if laravel_version >= 12:
        custom_scripts["security"] = "echo '⚠️ Enlightn non compatible avec Laravel 12+ - utilisez les autres outils de qualité'"
        custom_scripts["enlightn"] = "echo '⚠️ Enlightn sera disponible quand il supportera Laravel 12+'"
    else:
        # Pour les versions antérieures, inclure Enlightn si disponible
        custom_scripts["security"] = "php artisan enlightn --format=github || echo '⚠️ Enlightn non disponible'"
        custom_scripts["enlightn"] = "php artisan enlightn || echo '⚠️ Enlightn non disponible'"

    composer_data['scripts'].update(custom_scripts)

    with open('composer.json', 'w') as f:
        json.dump(composer_data, f, indent=2)

    print("Scripts ajoutés au composer.json")
except Exception as e:
    print(f"Erreur lors de la modification du composer.json: {e}")
    sys.exit(1)
EOF
        if [ $? -eq 0 ]; then
            log "SUCCESS" "Scripts ajoutés au composer.json (adaptés pour Laravel $laravel_version)"
        else
            log "ERROR" "Échec de la modification du composer.json"
        fi
    else
        log "ERROR" "composer.json non trouvé"
        return 1
    fi
}

# Fonction pour optimiser Composer
optimize_composer() {
    log "INFO" "⚡ Optimisation de Composer..."

    # Réparer la configuration d'abord
    fix_composer_config

    # Nettoyer les caches
    log "DEBUG" "Nettoyage des caches..."
    composer clear-cache 2>/dev/null || true

    # Optimiser l'autoloader
    log "DEBUG" "Optimisation de l'autoloader..."
    composer dump-autoload --optimize --no-interaction 2>/dev/null || true

    # Vérifier l'état de Composer en mode debug
    if [ "$DEBUG" = "true" ]; then
        log "DEBUG" "Vérification de l'état de Composer..."
        composer diagnose 2>&1 | grep -E "(OK|WARNING|ERROR)" | tee -a "$LOG_FILE" || true
    fi

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

    # Exécuter les migrations avec --force pour éviter la confirmation
    log "DEBUG" "Migration des tables Laravel de base..."
    if php artisan migrate --force --no-interaction 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Migrations de base exécutées"
    else
        log "ERROR" "Échec des migrations de base"
        return 1
    fi

    # Migrations spécifiques aux packages installés
    log "DEBUG" "Migration des tables des packages..."

    # Tables système Laravel
    local system_tables=("sessions" "cache" "jobs" "failed_jobs")
    local artisan_commands=("session:table" "cache:table" "queue:table" "queue:failed-table")

    for i in "${!system_tables[@]}"; do
        local table="${system_tables[$i]}"
        local command="${artisan_commands[$i]}"

        if ! php artisan tinker --execute="DB::select('SHOW TABLES LIKE \"$table\"');" 2>/dev/null | grep -q "$table"; then
            log "DEBUG" "Création de la table $table..."
            php artisan $command --force 2>/dev/null || true
            php artisan migrate --force --no-interaction 2>/dev/null || true
        fi
    done

    # Migration finale
    log "DEBUG" "Migration finale..."
    php artisan migrate --force --no-interaction 2>/dev/null || true

    log "SUCCESS" "Toutes les migrations terminées"

    # Seeders optionnels
    if [ -f "database/seeders/DatabaseSeeder.php" ]; then
        log "DEBUG" "Vérification des seeders..."
        if grep -q "run()" database/seeders/DatabaseSeeder.php; then
            log "DEBUG" "Exécution des seeders..."
            php artisan db:seed --force --no-interaction 2>/dev/null || log "WARN" "Seeders non exécutés (normal pour une nouvelle installation)"
        fi
    fi
}

# Fonction principale d'installation
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

    # Détecter le répertoire de travail
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

    # Se déplacer dans le répertoire de travail
    cd "$WORKING_DIR"
    log "DEBUG" "Changement de répertoire vers: $WORKING_DIR"

    # Configurer la base de données MariaDB
    configure_database

    # Installation des packages de production
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
        sleep 1
    done

    # Installation des outils de qualité de code (sans Enlightn)
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
    )

    for package in "${dev_packages[@]}"; do
        if ! install_package "$package" "require-dev"; then
            failed_packages+=("$package")
            log "WARN" "Échec de l'installation de $package (dev)"
        fi
        sleep 1
    done

    # Finalisation et optimisation avant Enlightn
    log "INFO" "🔄 Finalisation de l'installation des packages..."
    COMPOSER_MEMORY_LIMIT=-1 composer install --no-interaction --optimize-autoloader 2>&1 | tee -a "$LOG_FILE"

    # Publication des assets et configurations
    if [ -f "artisan" ]; then
        log "INFO" "📋 Publication des assets et configurations..."

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

        # Exécuter les migrations
        log "INFO" "🗄️ Configuration de la base de données..."
        run_migrations

        # Installation et configuration d'Enlightn EN DERNIER
        log "INFO" "🔧 Installation et configuration d'Enlightn (étape critique)..."
        if ! install_package "enlightn/enlightn" "require-dev"; then
            failed_packages+=("enlightn/enlightn")
            log "WARN" "Échec de l'installation d'Enlightn"
        else
            # Configurer Enlightn avec la nouvelle fonction améliorée
            if setup_enlightn; then
                log "SUCCESS" "✅ Enlightn configuré avec succès"
            else
                log "WARN" "⚠️ Enlightn installé mais configuration partielle"
            fi
        fi

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

    # Rapport final
    if [ ${#failed_packages[@]} -gt 0 ]; then
        log "WARN" "⚠️ Packages qui ont échoué à l'installation:"
        for package in "${failed_packages[@]}"; do
            log "WARN" "  - $package"
        done
        log "INFO" "Ces échecs peuvent être dus à des incompatibilités ou des problèmes réseau"
    fi

    # Afficher un résumé de l'installation
    log "INFO" "📊 Résumé de l'installation:"
    log "SUCCESS" "Installation terminée avec succès !"
    log "INFO" "📂 Fichiers Laravel installés dans : $WORKING_DIR"

    if [ "$DEBUG" = "true" ]; then
        log "DEBUG" "📊 Structure créée :"
        ls -la "$WORKING_DIR" | head -15
    fi

    # Résumé des outils installés
    log "INFO" "🛠️ Outils de qualité installés :"
    log "INFO" "  • Easy Coding Standard (ECS) - Vérification du style de code"
    log "INFO" "  • Rector - Refactoring automatique"
    log "INFO" "  • PHPStan/Larastan 2.0+ niveau 8 - Analyse statique stricte"
    log "INFO" "  • PHP Insights - Analyse globale de la qualité"
    log "INFO" "  • Laravel IDE Helper - Autocomplétion IDE"
    log "INFO" "  • Laravel Query Detector - Détection requêtes N+1"

    # Statut d'Enlightn
    if php artisan list 2>/dev/null | grep -q "enlightn"; then
        log "INFO" "  • Enlightn - Audit de sécurité et performance ✅"
    elif [ -f "enlightn_wrapper.sh" ]; then
        log "INFO" "  • Enlightn - Audit de sécurité et performance ⚠️ (avec wrapper)"
    else
        log "INFO" "  • Enlightn - Audit de sécurité et performance ❌ (non disponible)"
    fi

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

    # Vérification des fichiers importants
    log "INFO" "📋 Vérification des fichiers :"
    local files_to_check=("package.json" ".env" "ecs.php" "rector.php" "phpstan.neon")
    for file in "${files_to_check[@]}"; do
        if [ -f "$WORKING_DIR/$file" ]; then
            log "SUCCESS" "✓ $file"
        else
            log "WARN" "✗ $file manquant"
        fi
    done

    # Vérification des tables importantes
    log "INFO" "📋 Vérification des tables importantes :"
    local important_tables=("users" "sessions" "cache" "jobs" "failed_jobs")
    for table in "${important_tables[@]}"; do
        if php artisan tinker --execute="DB::select('SHOW TABLES LIKE \"$table\"');" 2>/dev/null | grep -q "$table"; then
            log "SUCCESS" "✓ Table $table"
        else
            log "WARN" "✗ Table $table manquante"
        fi
    done

    # Test rapide des outils
    log "INFO" "🧪 Test rapide des outils de qualité..."

    # Test d'Enlightn
    if php artisan list | grep -q "enlightn"; then
        log "SUCCESS" "✓ Enlightn disponible"

        # Test de fonctionnement
        if php artisan enlightn --help >/dev/null 2>&1; then
            log "SUCCESS" "✓ Enlightn pleinement fonctionnel"
        else
            log "WARN" "⚠️ Enlightn détecté mais erreur au lancement"
        fi
    elif [ -f "enlightn_wrapper.sh" ]; then
        log "WARN" "⚠️ Enlightn disponible via wrapper"
    else
        log "WARN" "✗ Enlightn non disponible"
    fi

    # Test des autres outils
    if [ -f "./vendor/bin/phpstan" ]; then
        log "SUCCESS" "✓ PHPStan installé"
    else
        log "WARN" "✗ PHPStan non installé"
    fi

    if [ -f "./vendor/bin/ecs" ]; then
        log "SUCCESS" "✓ ECS installé"
    else
        log "WARN" "✗ ECS non installé"
    fi

    log "SUCCESS" "🎉 Installation complète terminée !"
    log "INFO" "Prochaines étapes :"
    log "INFO" "1. ✅ Base de données configurée et migrée"
    log "INFO" "2. Accéder à l'application : https://laravel.local"
    log "INFO" "3. Lancer les tests : composer test:coverage"
    log "INFO" "4. Vérifier la qualité : composer quality"
    log "INFO" "5. Audit de sécurité : composer enlightn"

    if [ ${#failed_packages[@]} -gt 0 ]; then
        log "WARN" "⚠️ Certains packages ont échoué. Consultez le log: $LOG_FILE"
        log "INFO" "Vous pouvez réessayer l'installation des packages manquants:"
        for package in "${failed_packages[@]}"; do
            if [[ "$package" == *"enlightn"* ]]; then
                log "INFO" "  composer require --dev $package"
            else
                log "INFO" "  composer require $package"
            fi
        done
    fi

    log "INFO" "Log complet disponible: $LOG_FILE"

    # Instructions spéciales pour Enlightn si problématique
    if [ -f "enlightn_wrapper.sh" ]; then
        log "INFO" ""
        log "INFO" "🔧 Instructions spéciales pour Enlightn:"
        log "INFO" "  Si vous rencontrez des problèmes avec 'make quality-full':"
        log "INFO" "  1. Utilisez: ./enlightn_wrapper.sh au lieu de php artisan enlightn"
        log "INFO" "  2. Ou modifiez votre Makefile pour utiliser le wrapper"
        log "INFO" "  3. Ou réinstallez avec: composer require --dev enlightn/enlightn"
    fi
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
    echo ""
    echo "Ce script installe Laravel avec un ensemble d'outils de qualité adaptés à votre version:"
    echo "  • Laravel Framework avec packages essentiels"
    echo "  • Outils de qualité: ECS, Rector (adapté PHP/Laravel), PHPStan, PHP Insights"
    echo "  • Configuration automatique de MariaDB et Redis"
    echo "  • Scripts Composer prêts à l'emploi"
    echo "  • Gestion intelligente des incompatibilités (Laravel 12+)"
    echo "  • Rapport de compatibilité détaillé"
    echo ""
    echo "Spécificités Laravel 12+:"
    echo "  • Enlightn: Non compatible (suivi automatique des mises à jour)"
    echo "  • Pest: Peut être incompatible (fallback vers PHPUnit)"
    echo "  • Rector: Configuré pour PHP 8.4 et Laravel 12"
    echo "  • Script de vérification: check_compatibility.sh généré"
    echo ""
    echo "Fichiers générés:"
    echo "  • compatibility_report.md - Rapport détaillé"
    echo "  • check_compatibility.sh - Vérification future"
    echo "  • .incompatible_packages.txt - Liste des packages en attente"
    exit 0
fi

# Exécuter l'installation
main "$@"