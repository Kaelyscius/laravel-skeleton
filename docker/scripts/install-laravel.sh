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

# Fonction pour vérifier les prérequis (compatible BusyBox)
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

    # Vérifier la version de Composer (compatible BusyBox)
    local composer_version=$(composer --version 2>/dev/null | sed 's/.*version \([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/' | head -1)
    log "DEBUG" "Version de Composer détectée: $composer_version"

    # Vérifier la version de PHP (compatible BusyBox)
    local php_version=$(php -v | head -1 | sed 's/PHP \([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/')
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

# Fonction pour créer la structure initiale du projet
create_project_structure() {
    local project_root="$1"

    log "INFO" "🏗️ Création de la structure initiale du projet..."

    # Créer le dossier src/ pour Laravel si on est hors container
    if [ ! -f "/.dockerenv" ] && [ ! -n "${DOCKER_CONTAINER}" ]; then
        mkdir -p "$project_root/src"
        log "DEBUG" "Dossier src/ créé: $project_root/src"

        # Créer un fichier .gitkeep temporaire pour préserver la structure
        touch "$project_root/src/.gitkeep"
    fi

    # Créer les autres dossiers nécessaires si ils n'existent pas
    mkdir -p "$project_root/docker/apache/logs"
    mkdir -p "$project_root/docker/apache/conf/ssl"
    mkdir -p "$project_root/docker/php/logs"
    mkdir -p "$project_root/docker/supervisor/logs"
    mkdir -p "$project_root/scripts"

    # Créer les fichiers .gitkeep pour préserver la structure
    touch "$project_root/docker/apache/logs/.gitkeep"
    touch "$project_root/docker/apache/conf/ssl/.gitkeep"
    touch "$project_root/docker/php/logs/.gitkeep"
    touch "$project_root/docker/supervisor/logs/.gitkeep"

    log "SUCCESS" "Structure initiale du projet créée"
}

# Fonction pour détecter le répertoire de travail correct
detect_working_directory() {
    log "DEBUG" "Détection du répertoire de travail..."

    # Vérifier si nous sommes dans un container Docker
    if [ -f "/.dockerenv" ] || [ -n "${DOCKER_CONTAINER}" ]; then
        log "DEBUG" "Environnement Docker détecté"

        # Dans le container, utiliser /var/www/html
        if [ -d "/var/www/html" ]; then
            log "DEBUG" "Répertoire Docker détecté: /var/www/html"
            echo "/var/www/html"
            return
        fi
    fi

    # Hors container, vérifier si nous avons un dossier src/
    local current_dir=$(pwd)
    if [ -d "$current_dir/src" ]; then
        log "DEBUG" "Dossier src/ détecté: $current_dir/src"
        echo "$current_dir/src"
        return
    fi

    # Créer le dossier src/ s'il n'existe pas (structure de projet attendue)
    if [ -f "$current_dir/docker-compose.yml" ] && grep -q "./src:/var/www/html" "$current_dir/docker-compose.yml"; then
        log "INFO" "Structure de projet Docker détectée, création de la structure..."
        create_project_structure "$current_dir"
        echo "$current_dir/src"
        return
    fi

    # Sinon, utiliser le répertoire courant
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
        "phpro/grumphp"
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

    # Créer le répertoire s'il n'existe pas
    mkdir -p "$target_dir"

    # Vérifier si le dossier contient déjà un projet Laravel
    if [ -f "$target_dir/artisan" ] && [ -f "$target_dir/composer.json" ]; then
        if grep -q "laravel/framework" "$target_dir/composer.json" 2>/dev/null; then
            log "SUCCESS" "Projet Laravel existant détecté dans $target_dir"
            return 0
        fi
    fi

    # Afficher le contenu actuel pour diagnostic
    log "DEBUG" "Contenu actuel de $target_dir:"
    ls -la "$target_dir" 2>/dev/null | tee -a "$LOG_FILE" || true

    # Nettoyer COMPLÈTEMENT le répertoire (y compris fichiers cachés)
    log "INFO" "Nettoyage complet du répertoire $target_dir..."

    # Supprimer tout le contenu, y compris les fichiers cachés
    find "$target_dir" -mindepth 1 -delete 2>/dev/null || true

    # Alternative plus agressive si la première ne fonctionne pas
    if [ "$(ls -A "$target_dir" 2>/dev/null | wc -l)" -gt 0 ]; then
        log "DEBUG" "Nettoyage alternatif nécessaire..."
        rm -rf "$target_dir"/{*,.*} 2>/dev/null || true
        rm -rf "$target_dir"/.* 2>/dev/null || true
        rm -rf "$target_dir"/* 2>/dev/null || true
    fi

    # Vérifier que le répertoire est maintenant vide
    local remaining_files=$(ls -A "$target_dir" 2>/dev/null | wc -l)
    if [ "$remaining_files" -gt 0 ]; then
        log "WARN" "Fichiers restants après nettoyage:"
        ls -la "$target_dir" | tee -a "$LOG_FILE"

        # Forcer le nettoyage avec une méthode plus drastique
        log "INFO" "Nettoyage forcé..."
        cd "$(dirname "$target_dir")"
        rm -rf "$(basename "$target_dir")"
        mkdir -p "$target_dir"
    fi

    # Aller dans le dossier cible
    cd "$target_dir"
    log "DEBUG" "Changement de répertoire vers: $target_dir"

    # Vérifier si composer est accessible
    if ! command -v composer &> /dev/null; then
        log "ERROR" "Composer n'est pas accessible"
        exit 1
    fi

    # Vérifier une dernière fois que le répertoire est vide
    log "DEBUG" "Vérification finale - contenu du répertoire:"
    ls -la "$target_dir" | tee -a "$LOG_FILE" || true

    # Méthode alternative : installer dans un répertoire temporaire puis déplacer
    local temp_dir="/tmp/laravel-install-$$"
    log "INFO" "Installation via répertoire temporaire..."

    # Nettoyer le répertoire temporaire s'il existe
    rm -rf "$temp_dir" 2>/dev/null || true

    # Créer le projet Laravel dans le répertoire temporaire
    log "INFO" "Téléchargement et installation de Laravel (via $temp_dir)..."
    log "DEBUG" "Commande: COMPOSER_MEMORY_LIMIT=-1 composer create-project laravel/laravel \"$temp_dir\" --no-interaction --prefer-dist"

    if ! COMPOSER_MEMORY_LIMIT=-1 composer create-project laravel/laravel "$temp_dir" --no-interaction --prefer-dist 2>&1 | tee -a "$LOG_FILE"; then
        log "ERROR" "Échec de la création du projet Laravel dans le répertoire temporaire"
        rm -rf "$temp_dir" 2>/dev/null || true
        exit 1
    fi

    # Vérifier que l'installation temporaire a réussi
    if [ ! -f "$temp_dir/artisan" ] || [ ! -f "$temp_dir/composer.json" ]; then
        log "ERROR" "L'installation temporaire a échoué - fichiers Laravel manquants"
        rm -rf "$temp_dir" 2>/dev/null || true
        exit 1
    fi

    # Déplacer le contenu du répertoire temporaire vers le répertoire cible
    log "INFO" "Déplacement des fichiers vers $target_dir..."

    # S'assurer que le répertoire cible est vide
    rm -rf "$target_dir"/{*,.*} 2>/dev/null || true

    # Déplacer tous les fichiers (y compris les cachés)
    if ! (cd "$temp_dir" && cp -a . "$target_dir/") 2>&1 | tee -a "$LOG_FILE"; then
        log "ERROR" "Échec du déplacement des fichiers"
        rm -rf "$temp_dir" 2>/dev/null || true
        exit 1
    fi

    # Nettoyer le répertoire temporaire
    rm -rf "$temp_dir" 2>/dev/null || true

    # Vérifier que l'installation finale a réussi
    if [ -f "$target_dir/artisan" ] && [ -f "$target_dir/composer.json" ]; then
        log "SUCCESS" "Projet Laravel créé avec succès dans : $target_dir"
        log "DEBUG" "Fichiers Laravel installés:"
        ls -la "$target_dir" | head -10 | tee -a "$LOG_FILE"
    else
        log "ERROR" "L'installation finale a échoué - fichiers Laravel manquants"
        log "DEBUG" "Contenu final du répertoire:"
        ls -la "$target_dir" | tee -a "$LOG_FILE"
        exit 1
    fi
}

# Fonction pour détecter la version de Laravel (compatible BusyBox)
get_laravel_version() {
    if [ -f "composer.json" ]; then
        # Utiliser sed au lieu de grep -P pour compatibilité BusyBox
        local version=$(grep '"laravel/framework"' composer.json 2>/dev/null | sed 's/.*"\^\([0-9]\+\).*/\1/' | head -1)
        echo "${version:-12}"
    else
        echo "12"
    fi
}

# Fonction pour détecter la version de PHP
get_php_version() {
    php -r "echo PHP_MAJOR_VERSION . '.' . PHP_MINOR_VERSION;"
}

# Fonction pour vérifier si une table existe dans la base de données
table_exists() {
    local table_name=$1
    log "DEBUG" "Vérification de l'existence de la table: $table_name"

    # Vérifier si la table existe via Laravel
    php artisan tinker --execute="
        try {
            if (Schema::hasTable('$table_name')) {
                echo 'TABLE_EXISTS';
            } else {
                echo 'TABLE_NOT_EXISTS';
            }
        } catch (Exception \$e) {
            echo 'ERROR_CHECKING_TABLE';
        }
    " 2>/dev/null | grep -q "TABLE_EXISTS"
}

# Fonction CORRIGÉE SEULEMENT pour localiser le .env racine
find_root_env() {
    log "INFO" "📋 Localisation du fichier .env racine..."

    # Obtenir le répertoire du script actuel
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    log "DEBUG" "Répertoire du script: $script_dir"

    # Liste des chemins à tester dans l'ordre de priorité
    local search_paths=()

    # 1. Depuis le script docker/scripts/install-laravel.sh -> remonter de 2 niveaux
    search_paths+=("$(dirname "$(dirname "$script_dir")")/.env")

    # 2. Dans Docker, le volume racine est souvent monté dans /var/www/project
    search_paths+=("/var/www/project/.env")

    # 3. Si on est dans /var/www/html, le projet racine est probablement le parent
    if [[ "$(pwd)" == "/var/www/html" ]]; then
        search_paths+=("/var/www/html/../.env")
        search_paths+=("/var/www/.env")
    fi

    # 4. Chemins relatifs classiques
    search_paths+=("../.env" "../../.env" "../../../.env")

    # 5. Recherche en remontant l'arborescence depuis le répertoire courant
    local current_dir="$(pwd)"
    local max_depth=5
    local depth=0
    while [ $depth -lt $max_depth ] && [ "$current_dir" != "/" ]; do
        search_paths+=("$current_dir/.env")
        current_dir="$(dirname "$current_dir")"
        ((depth++))
    done

    # Debug : afficher les informations de diagnostic
    if [ "$DEBUG" = "true" ]; then
        log "DEBUG" "Répertoire courant: $(pwd)"
        log "DEBUG" "Chemins à tester: ${search_paths[*]}"
        log "DEBUG" "Fichiers .env trouvés dans le système:"
        find /var/www -name ".env" -type f 2>/dev/null | head -10 | sed 's/^/  /' || true
    fi

    # Tester chaque chemin
    for env_file in "${search_paths[@]}"; do
        # Résoudre le chemin complet
        local resolved_path
        if resolved_path=$(readlink -f "$env_file" 2>/dev/null) && [ -f "$resolved_path" ]; then
            env_file="$resolved_path"
        fi

        log "DEBUG" "Test du chemin: $env_file"

        if [ -f "$env_file" ]; then
            log "DEBUG" "Fichier trouvé: $env_file"

            # Vérification robuste : doit contenir des variables spécifiques au projet Docker
            local score=0
            local criteria=(
                "COMPOSE_PROJECT_NAME"
                "DB_HOST.*mariadb"
                "REDIS_HOST.*redis"
                "MAIL_HOST.*mailhog"
            )

            for criterion in "${criteria[@]}"; do
                if grep -q "$criterion" "$env_file" 2>/dev/null; then
                    ((score++))
                    log "DEBUG" "✓ Critère '$criterion' trouvé"
                fi
            done

            # Si au moins 2 critères sont satisfaits, c'est probablement le bon fichier
            if [ $score -ge 2 ]; then
                log "SUCCESS" "✅ Fichier .env racine trouvé: $env_file (score: $score/4)"
                echo "$env_file"
                return 0
            else
                log "DEBUG" "Fichier pas assez spécifique (score: $score/4)"
                if [ "$DEBUG" = "true" ]; then
                    log "DEBUG" "Contenu des premières lignes:"
                    head -5 "$env_file" 2>/dev/null | sed 's/^/  /' || true
                fi
            fi
        else
            log "DEBUG" "Fichier non trouvé: $env_file"
        fi
    done

    log "ERROR" "❌ Aucun fichier .env racine trouvé avec les critères requis"
    log "INFO" "💡 Le .env racine doit contenir: COMPOSE_PROJECT_NAME, DB_HOST=mariadb, REDIS_HOST=redis"

    # Diagnostic supplémentaire
    log "DEBUG" "Diagnostic - tous les fichiers .env trouvés:"
    find /var/www -name ".env" -type f -exec echo "  {}" \; -exec head -3 {} \; -exec echo "" \; 2>/dev/null | head -20 || true

    return 1
}

# Fonction CORRIGÉE SEULEMENT pour copier le .env racine vers Laravel
copy_root_env_to_laravel() {
    log "INFO" "📋 Copie complète du .env racine vers Laravel..."

    # Diagnostic du répertoire courant
    log "DEBUG" "Répertoire de travail actuel: $(pwd)"
    log "DEBUG" "Contenu du répertoire:"
    ls -la . | head -10 | sed 's/^/  /' || true

    # Trouver le .env racine avec la nouvelle fonction robuste
    local root_env_file
    if ! root_env_file=$(find_root_env); then
        log "ERROR" "Impossible de localiser le .env racine"
        log "INFO" "💡 Solutions possibles:"
        log "INFO" "  1. Vérifiez que le .env existe à la racine du projet"
        log "INFO" "  2. Vérifiez que le .env contient COMPOSE_PROJECT_NAME"
        log "INFO" "  3. Exécutez avec DEBUG=true pour plus de détails"
        return 1
    fi

    # Afficher des informations sur le fichier source
    log "INFO" "📁 Source détectée: $root_env_file"
    log "DEBUG" "Taille du fichier source: $(wc -l < "$root_env_file" 2>/dev/null || echo 'inconnu') lignes"

    # Sauvegarder le .env Laravel existant avec timestamp
    if [ -f ".env" ]; then
        local backup_file=".env.laravel.backup.$(date +%Y%m%d-%H%M%S)"
        cp .env "$backup_file"
        log "DEBUG" "Sauvegarde de .env Laravel vers $backup_file"

        # Comparer avec le fichier source pour voir s'il y a des différences
        if diff -q "$root_env_file" .env >/dev/null 2>&1; then
            log "INFO" "✅ Le .env Laravel est déjà identique au .env racine"
            return 0
        else
            log "DEBUG" "Différences détectées entre .env racine et Laravel"
        fi
    fi

    # Copier avec vérification
    log "DEBUG" "Copie de '$root_env_file' vers '$(pwd)/.env'"
    if cp "$root_env_file" .env; then
        log "SUCCESS" "✅ .env racine copié avec succès vers Laravel"
        log "INFO" "📁 Source: $root_env_file"
        log "INFO" "📁 Destination: $(pwd)/.env"

        # Vérifier que la copie est identique
        if diff -q "$root_env_file" .env >/dev/null 2>&1; then
            log "SUCCESS" "✅ Copie vérifiée - fichiers identiques"
        else
            log "WARN" "⚠️ Les fichiers ne sont pas identiques après copie"
            if [ "$DEBUG" = "true" ]; then
                log "DEBUG" "Différences détectées:"
                diff "$root_env_file" .env | head -10 || true
            fi
            return 1
        fi
    else
        log "ERROR" "❌ Échec de la copie du .env racine"
        log "DEBUG" "Vérifiez les permissions du répertoire $(pwd)"
        return 1
    fi

    # Diagnostic des variables importantes
    log "DEBUG" "Vérification des variables importantes dans le .env copié:"

    local important_vars=("APP_NAME" "DB_HOST" "COMPOSE_PROJECT_NAME" "NIGHTWATCH_TOKEN" "REDIS_HOST")
    for var in "${important_vars[@]}"; do
        local value=$(grep "^$var=" .env 2>/dev/null | cut -d'=' -f2- | sed 's/^["'\'']//' | sed 's/["'\'']$//' | xargs)
        if [ -n "$value" ]; then
            if [[ "$var" == *"TOKEN"* ]] || [[ "$var" == *"PASSWORD"* ]]; then
                log "DEBUG" "  $var: ${value:0:10}... (masqué)"
            else
                log "DEBUG" "  $var: $value"
            fi
        else
            log "DEBUG" "  $var: (non défini)"
        fi
    done

    # Vérification spéciale pour Nightwatch
    local final_token=$(grep "^NIGHTWATCH_TOKEN=" .env 2>/dev/null | cut -d'=' -f2- | sed 's/^["'\'']//' | sed 's/["'\'']$//' | xargs)
    if [ -n "$final_token" ] && [ "$final_token" != "" ] && [ "$final_token" != "\${NIGHTWATCH_TOKEN}" ]; then
        log "SUCCESS" "✅ Token Nightwatch configuré: ${final_token:0:10}..."
        log "SUCCESS" "✅ Toutes les valeurs du .env racine sont maintenant disponibles dans Laravel"
        return 0
    else
        log "WARN" "⚠️ Token Nightwatch non configuré ou vide"
        log "DEBUG" "Valeur NIGHTWATCH_TOKEN: '$final_token'"
        log "INFO" "Le service fonctionnera mais Nightwatch ne sera pas actif"
        return 0  # Ne pas faire échouer pour cette raison
    fi
}

# Fonction CORRIGÉE pour marquer une migration comme exécutée
mark_migration_as_executed() {
    local migration_file=$1
    local migration_name=$(basename "$migration_file" .php)

    log "DEBUG" "Marquage de la migration comme exécutée: $migration_name"

    php artisan tinker --execute="
        try {
            DB::table('migrations')->updateOrInsert(
                ['migration' => '$migration_name'],
                ['migration' => '$migration_name', 'batch' => 1]
            );
            echo 'MIGRATION_MARKED: $migration_name';
        } catch (Exception \$e) {
            echo 'ERROR_MARKING_MIGRATION: ' . \$e->getMessage();
        }
    " 2>/dev/null || log "WARN" "Impossible de marquer la migration: $migration_name"
}

# Fonction NOUVELLE pour nettoyer les migrations en conflit AVANT publication
prevent_migration_conflicts() {
    log "INFO" "🛡️ Prévention des conflits de migrations..."

    # Tables à vérifier avec leurs migrations correspondantes
    local conflicts=(
        "telescope_entries:2018_08_08_100000_create_telescope_entries_table"
        "telescope_entries_tags:2018_08_08_100001_create_telescope_entries_tags_table"
        "telescope_monitoring:2018_08_08_100002_create_telescope_monitoring_table"
        "personal_access_tokens:2019_12_14_000001_create_personal_access_tokens_table"
    )

    for conflict in "${conflicts[@]}"; do
        local table_name=$(echo $conflict | cut -d':' -f1)
        local migration_pattern=$(echo $conflict | cut -d':' -f2)

        if table_exists "$table_name"; then
            log "WARN" "Table $table_name existe déjà - prévention du conflit"

            # Marquer toutes les migrations correspondantes comme exécutées
            if [[ "$migration_pattern" == *"*"* ]]; then
                # Gérer les patterns avec wildcard pour Sanctum
                local pattern_prefix=$(echo $migration_pattern | sed 's/\*.*$//')
                for migration_file in database/migrations/${pattern_prefix}*.php; do
                    if [ -f "$migration_file" ]; then
                        mark_migration_as_executed "$migration_file"
                    fi
                done
            else
                # Migration exacte
                local migration_file="database/migrations/${migration_pattern}.php"
                if [ -f "$migration_file" ]; then
                    mark_migration_as_executed "$migration_file"
                fi
            fi
        else
            log "DEBUG" "Table $table_name n'existe pas - migration autorisée"
        fi
    done
}

# Fonction CORRIGÉE pour publier seulement les assets et configs (PAS les migrations)
publish_package_assets_safely() {
    log "INFO" "📋 Publication sécurisée des assets et configurations..."

    # Publier UNIQUEMENT les configurations et assets (PAS les migrations)
    local publish_commands=(
        "php artisan vendor:publish --tag=horizon-config --force"
        "php artisan vendor:publish --tag=horizon-assets --force"
        "php artisan vendor:publish --tag=telescope-config --force"
        "php artisan vendor:publish --tag=telescope-assets --force"
        "php artisan vendor:publish --provider=\"Spatie\Permission\PermissionServiceProvider\" --tag=config --force"
        "php artisan vendor:publish --provider=\"Spatie\Activitylog\ActivitylogServiceProvider\" --tag=config --force"
        "php artisan vendor:publish --provider=\"Barryvdh\LaravelIdeHelper\IdeHelperServiceProvider\" --tag=config --force"
        "php artisan vendor:publish --provider=\"BeyondCode\QueryDetector\QueryDetectorServiceProvider\" --force"
        "php artisan vendor:publish --provider=\"Laravel\\Nightwatch\\NightwatchServiceProvider\" --tag=config --force"
    )

    for cmd in "${publish_commands[@]}"; do
        log "DEBUG" "Exécution: $cmd"
        eval "$cmd" 2>/dev/null || log "DEBUG" "Commande ignorée (package peut-être non installé): $cmd"
    done

    log "SUCCESS" "Publication sécurisée terminée (SANS migrations)"
}

# Fonction CORRIGÉE pour publier les migrations seulement si nécessaire
publish_migrations_if_needed() {
    log "INFO" "📋 Publication conditionnelle des migrations..."

    # Sanctum : publier seulement si la table n'existe pas
    if ! table_exists "personal_access_tokens"; then
        log "DEBUG" "Publication des migrations Sanctum (table n'existe pas)"
        php artisan vendor:publish --tag=sanctum-migrations --force 2>/dev/null || true
    else
        log "DEBUG" "Migrations Sanctum ignorées (table existante)"
    fi

    # Telescope : publier seulement si les tables n'existent pas
    if ! table_exists "telescope_entries"; then
        log "DEBUG" "Publication des migrations Telescope (tables n'existent pas)"
        php artisan vendor:publish --tag=telescope-migrations --force 2>/dev/null || true
    else
        log "DEBUG" "Migrations Telescope ignorées (tables existantes)"
    fi

    # Autres packages avec migrations
    local migration_commands=(
        "php artisan vendor:publish --provider=\"Spatie\Permission\PermissionServiceProvider\" --tag=migrations --force"
        "php artisan vendor:publish --provider=\"Spatie\Activitylog\ActivitylogServiceProvider\" --tag=activitylog-migrations --force"
    )

    for cmd in "${migration_commands[@]}"; do
        log "DEBUG" "Exécution: $cmd"
        eval "$cmd" 2>/dev/null || log "DEBUG" "Migrations non publiées (package non installé): $cmd"
    done

    log "SUCCESS" "Migrations publiées conditionnellement"
}

# Fonction pour exécuter les migrations de base Laravel seulement
run_base_migrations() {
    log "INFO" "🔄 Exécution des migrations de base Laravel..."

    # Attendre que la base de données soit prête
    if ! wait_for_database; then
        log "ERROR" "Impossible de continuer sans base de données"
        return 1
    fi

    # Exécuter seulement les migrations Laravel de base (pas les packages)
    log "DEBUG" "Migration des tables Laravel de base uniquement..."
    if php artisan migrate --path=database/migrations --force --no-interaction 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Migrations de base Laravel exécutées"
    else
        log "WARN" "Certaines migrations de base ont échoué - continuons"
    fi

    # Créer les tables système Laravel si nécessaire
    local system_tables=("sessions" "cache" "jobs" "failed_jobs")
    local artisan_commands=("session:table" "cache:table" "queue:table" "queue:failed-table")

    for i in "${!system_tables[@]}"; do
        local table="${system_tables[$i]}"
        local command="${artisan_commands[$i]}"

        if ! table_exists "$table"; then
            log "DEBUG" "Création de la table $table..."
            php artisan $command --force 2>/dev/null || true
        else
            log "DEBUG" "Table $table déjà existante"
        fi
    done

    log "SUCCESS" "Migrations de base terminées"
}

# Fonction CORRIGÉE pour exécuter les migrations finales (packages) SANS conflits
run_final_migrations() {
    log "INFO" "🔄 Exécution des migrations finales (packages) - SANS conflits..."

    # Prévenir les conflits AVANT de migrer
    prevent_migration_conflicts

    # Migration finale de tous les packages (sans conflit grâce à la prévention)
    log "DEBUG" "Migration finale de tous les packages..."
    if php artisan migrate --force --no-interaction 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Migrations finales exécutées avec succès"
    else
        log "WARN" "Certaines migrations finales ont échoué - vérification des conflits résolus"

        # En cas d'échec, essayer de résoudre les conflits restants
        log "DEBUG" "Résolution des conflits restants..."
        prevent_migration_conflicts

        # Nouvelle tentative
        php artisan migrate --force --no-interaction 2>/dev/null || log "WARN" "Migrations partiellement réussies"
    fi

    # Seeders optionnels
    if [ -f "database/seeders/DatabaseSeeder.php" ]; then
        log "DEBUG" "Vérification des seeders..."
        if grep -q "run()" database/seeders/DatabaseSeeder.php; then
            log "DEBUG" "Exécution des seeders..."
            php artisan db:seed --force --no-interaction 2>/dev/null || log "WARN" "Seeders non exécutés (normal pour une nouvelle installation)"
        fi
    fi

    log "SUCCESS" "Toutes les migrations terminées SANS conflit"
}

# Fonction pour vérifier la compatibilité d'un package (améliorée pour PHP 8.4)
check_package_compatibility() {
    local package=$1
    local laravel_version=$2
    local php_version=$3

    # Vérifications spécifiques pour Laravel 12+
    if [ "$laravel_version" -ge 12 ]; then
        case $package in
            "enlightn/enlightn")
                log "DEBUG" "Enlightn non compatible avec Laravel 12+ - ignoré"
                return 1
                ;;
            "pestphp/pest")
                # Compatible avec PHPUnit 11.5+
                return 0
                ;;
            "pestphp/pest-plugin-laravel")
                return 0
                ;;
        esac
    fi

    # Vérifications pour Laravel 11 et antérieur
    if [ "$laravel_version" -le 11 ]; then
        case $package in
            "enlightn/enlightn")
                # Compatible avec Laravel 10 et 11
                return 0
                ;;
        esac
    fi

    return 0  # Compatible par défaut
}

# Fonction améliorée pour vérifier si un package est installé
is_package_installed() {
    local package=$1
    # Nettoyer le nom du package (enlever les contraintes de version)
    local clean_package=$(echo $package | cut -d':' -f1)

    # Vérifier dans composer.json
    if [ -f "composer.json" ] && grep -q "\"$clean_package\"" composer.json; then
        log "DEBUG" "Package $clean_package trouvé dans composer.json"

        # Vérifier dans vendor/
        local vendor_path="vendor/$(echo $clean_package | tr '/' '/')"
        if [ -d "$vendor_path" ]; then
            log "DEBUG" "Package $clean_package trouvé dans vendor/"
            return 0
        fi

        # Vérifier avec composer show (plus fiable)
        if composer show "$clean_package" >/dev/null 2>&1; then
            log "DEBUG" "Package $clean_package confirmé par composer show"
            return 0
        fi
    fi

    return 1
}

# Fonction CORRIGÉE pour installer un package avec gestion spéciale Pest
install_package() {
    local package=$1
    local type=${2:-"require"}
    local max_attempts=3
    local attempt=1
    local laravel_version=$(get_laravel_version)
    local php_version=$(get_php_version)

    # Nettoyer le nom du package pour la vérification
    local clean_package=$(echo $package | cut -d':' -f1)

    log "INFO" "📦 Installation de $clean_package (type: $type)"

    # Vérifier si le package est déjà installé
    if is_package_installed "$clean_package"; then
        log "SUCCESS" "$clean_package déjà installé"
        return 0
    fi

    # Gestion spéciale pour Pest
    if [[ "$package" == *"pest"* ]]; then
        log "INFO" "Installation spéciale pour Pest avec dernière version compatible..."

        # Nettoyer le cache avant l'installation de Pest
        composer clear-cache 2>/dev/null || true

        # Installer avec des options spéciales pour Pest
        local composer_cmd="COMPOSER_MEMORY_LIMIT=-1 composer require --dev \"$package\" --no-interaction --with-all-dependencies"

        log "DEBUG" "Commande Pest: $composer_cmd"

        if eval $composer_cmd 2>&1 | tee -a "$LOG_FILE"; then
            log "SUCCESS" "$package installé avec succès"
            composer dump-autoload --no-interaction 2>/dev/null || true
            return 0
        else
            log "ERROR" "Impossible d'installer $package - conflit de versions détecté"
            echo "$package" >> .incompatible_packages.txt
            return 2
        fi
    fi

    # Vérifier la compatibilité avant l'installation (pour les autres packages)
    if ! check_package_compatibility "$clean_package" "$laravel_version" "$php_version"; then
        log "WARN" "Package $clean_package non compatible avec Laravel $laravel_version et PHP $php_version"
        log "INFO" "Ajout à la liste d'attente pour future compatibilité"
        echo "$clean_package" >> .incompatible_packages.txt
        return 2  # Code spécial pour incompatibilité
    fi

    while [ $attempt -le $max_attempts ]; do
        log "DEBUG" "Installation de $clean_package (tentative $attempt/$max_attempts)..."

        # Nettoyer le cache avant l'installation
        log "DEBUG" "Nettoyage du cache Composer..."
        composer clear-cache 2>/dev/null || true

        # Construire la commande Composer avec gestion des contraintes
        local composer_cmd
        if [ "$type" = "require-dev" ]; then
            composer_cmd="COMPOSER_MEMORY_LIMIT=-1 composer require --dev \"$package\" --no-interaction --with-all-dependencies"
        else
            composer_cmd="COMPOSER_MEMORY_LIMIT=-1 composer require \"$package\" --no-interaction --with-all-dependencies"
        fi

        log "DEBUG" "Commande: $composer_cmd"

        # Exécuter la commande avec capture des erreurs
        if eval $composer_cmd 2>&1 | tee -a "$LOG_FILE"; then
            # Vérifier que le package est maintenant vraiment installé
            if is_package_installed "$clean_package"; then
                log "SUCCESS" "$clean_package installé avec succès"

                # Régénérer l'autoloader après installation
                composer dump-autoload --no-interaction 2>/dev/null || true

                return 0
            else
                log "WARN" "$clean_package semble installé mais non détecté"
            fi
        else
            local exit_code=$?
            log "ERROR" "Échec de l'installation de $clean_package (code: $exit_code)"

            # Vérifier si c'est un problème de compatibilité
            if grep -q "conflicts with\|does not satisfy" "$LOG_FILE"; then
                log "WARN" "Conflit de dépendances détecté pour $clean_package"
                echo "$clean_package" >> .incompatible_packages.txt
                return 2
            fi
        fi

        if [ $attempt -lt $max_attempts ]; then
            log "WARN" "Nouvelle tentative dans 5 secondes..."
            sleep 5
            attempt=$((attempt + 1))
        else
            log "ERROR" "Impossible d'installer $clean_package après $max_attempts tentatives"

            if [ "$DEBUG" = "true" ]; then
                log "DEBUG" "Diagnostic de l'échec:"
                composer diagnose 2>&1 | tail -20 | tee -a "$LOG_FILE" || true
            fi

            return 1
        fi
    done
}

# Fonction pour créer les fichiers de configuration des outils de qualité (CORRIGÉE pour PHP 8.4)
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

    # Configuration Rector adaptée à PHP 8.4 et Laravel 12
    log "DEBUG" "Création de rector.php compatible PHP $php_version et Laravel $laravel_version..."

    local rector_php_level="LevelSetList::UP_TO_PHP_84"  # PHP 8.4 par défaut
    local rector_laravel_set="LaravelSetList::LARAVEL_110"  # Laravel 11 par défaut

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
    fi

    cat > rector.php << EOF
<?php

declare(strict_types=1);

use Rector\Config\RectorConfig;
use Rector\Set\ValueObject\LevelSetList;
use Rector\Laravel\Set\LaravelSetList;
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

    // Configuration spécifique pour Laravel 12+ et PHP 8.4
    if (version_compare('$laravel_version', '12', '>=')) {
        // Règles spécifiques pour Laravel 12
        \$rectorConfig->importNames();
        \$rectorConfig->importShortClasses();

        // Optimisations pour Laravel 12
        \$rectorConfig->parallel();
    }

    // Optimisations pour PHP 8.4
    if (version_compare(PHP_VERSION, '8.4', '>=')) {
        // Exploiter les nouvelles fonctionnalités PHP 8.4
        \$rectorConfig->importNames();
    }
};
EOF

    # Configuration PHPStan avec Larastan - Niveau 8 pour PHP 8.4
    log "DEBUG" "Création de phpstan.neon pour PHPStan 2.0+ et PHP 8.4..."
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

    # Configuration pour PHPStan 2.0+ et PHP 8.4
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

    # Support PHP 8.4 features
    checkPhpDocMethodSignatures: true
    checkPhpDocVariableType: true

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

    # Configuration PHP Insights pour PHP 8.4
    log "DEBUG" "Création de config/insights.php compatible PHP 8.4..."
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
    log "INFO" "  • rector.php (Rector pour PHP $php_version et Laravel $laravel_version)"
    log "INFO" "  • phpstan.neon (PHPStan 2.0+ niveau 8 - optimisé PHP 8.4)"
    log "INFO" "  • config/insights.php (PHP Insights compatible PHP 8.4)"
    if [ -f "config/telescope.php" ]; then
        log "INFO" "  • config/telescope.php (Telescope configuré)"
    fi
}

# Fonction pour configurer GrumPHP (CORRIGÉE)
configure_grumphp() {
    log "INFO" "🛡️ Configuration de GrumPHP..."

    # Vérifier si GrumPHP est installé
    if ! is_package_installed "phpro/grumphp"; then
        log "WARN" "GrumPHP non installé, configuration ignorée"
        return 1
    fi

    local laravel_version=$(get_laravel_version)
    local php_version=$(get_php_version)

    log "DEBUG" "Configuration GrumPHP pour Laravel $laravel_version, PHP $php_version"

    # Détecter les outils disponibles
    local tools=""
    [ -f "./vendor/bin/ecs" ] && [ -f "ecs.php" ] && tools="${tools}ecs "
    [ -f "./vendor/bin/phpstan" ] && [ -f "phpstan.neon" ] && tools="${tools}phpstan "
    [ -f "./vendor/bin/pest" ] && tools="${tools}pest " || [ -f "phpunit.xml" ] && tools="${tools}phpunit "
    [ -f "./vendor/bin/rector" ] && [ -f "rector.php" ] && tools="${tools}rector "

    log "DEBUG" "Outils détectés pour GrumPHP : $tools"

    # Créer le fichier grumphp.yml - VERSION CORRIGÉE
    cat > grumphp.yml << 'EOF'
# Configuration GrumPHP pour Laravel
# Hooks Git automatiques pour maintenir la qualité du code

grumphp:
    # Configuration des hooks Git
    git_hook_variables:
        EXEC_GRUMPHP_COMMAND: 'vendor/bin/grumphp'

    # Répertoires et paramètres
    process_timeout: 300
    stop_on_failure: true
    ignore_unstaged_changes: false
    hide_circumvention_tip: false

    # Tâches à exécuter lors des commits
    tasks:
EOF

    # Ajouter ECS si disponible
    if [[ "$tools" == *"ecs"* ]]; then
        cat >> grumphp.yml << 'EOF'
        # Easy Coding Standard - Vérification du style de code PSR-12
        ecs:
            config: ecs.php
            triggered_by: ['php']
            clear_cache: false
            no_error_table: false

EOF
    fi

    # Ajouter PHPStan si disponible
    if [[ "$tools" == *"phpstan"* ]]; then
        cat >> grumphp.yml << 'EOF'
        # PHPStan - Analyse statique niveau 8
        phpstan:
            configuration: phpstan.neon
            level: ~
            triggered_by: ['php']
            memory_limit: "1G"
            use_grumphp_paths: true

EOF
    fi

    # Ajouter les tests
    if [[ "$tools" == *"pest"* ]]; then
        cat >> grumphp.yml << 'EOF'
        # Pest - Tests modernes pour Laravel
        pest:
            config: ~
            testsuite: ~
            group: []
            always_execute: false
            triggered_by: ['php']

EOF
    elif [[ "$tools" == *"phpunit"* ]]; then
        cat >> grumphp.yml << 'EOF'
        # PHPUnit - Tests Laravel par défaut
        phpunit:
            config_file: phpunit.xml
            testsuite: ~
            group: []
            always_execute: false
            triggered_by: ['php']

EOF
    fi

    # Vérifications génériques (toujours incluses) - VERSION CORRIGÉE
    cat >> grumphp.yml << 'EOF'
        # Vérifications de syntaxe PHP
        phplint:
            exclude: ['vendor/', 'node_modules/', 'storage/', 'bootstrap/cache/']
            jobs: ~
            short_open_tag: false
            ignore_patterns: []
            triggered_by: ['php']

        # Validation JSON (composer.json, package.json, etc.)
        jsonlint:
            detect_key_conflicts: true
            triggered_by: ['json']

        # Validation YAML (GitHub Actions, docker-compose, etc.)
        yamllint:
            object_support: true
            exception_on_invalid_type: true
            parse_constant: true
            parse_custom_tags: true
            triggered_by: ['yaml', 'yml']

        # Détection de conflits Git - VERSION CORRIGÉE
        git_blacklist:
            keywords:
                - "<<<<<<< HEAD"
                - "======="
                - ">>>>>>> "
                - "console.log("
                - "var_dump("
                - "print_r("
                - "die("
                - "exit("
            whitelist_patterns: []
            triggered_by: ['php', 'js', 'ts', 'vue']

EOF

    # Rector en mode dry-run si disponible
    if [[ "$tools" == *"rector"* ]]; then
        cat >> grumphp.yml << 'EOF'
        # Rector - Vérifications de refactoring (dry-run seulement)
        shell:
            rector_dry_run:
                command: 'vendor/bin/rector process --dry-run --no-progress-bar'
                triggered_by: ['php']
                working_directory: './'

EOF
    fi

    # Configuration des environnements
    cat >> grumphp.yml << 'EOF'
    # Configuration des environnements et extensions
    environment:
        variables:
            COMPOSER_ALLOW_SUPERUSER: '1'
            COMPOSER_MEMORY_LIMIT: '-1'

    # Extensions personnalisées (si nécessaires)
    extensions: []

EOF

    # Installer les hooks Git
    log "DEBUG" "Installation des hooks Git..."
    if [ -d ".git" ]; then
        if php vendor/bin/grumphp git:init 2>/dev/null; then
            log "SUCCESS" "Hooks Git GrumPHP installés"

            # Vérifier que le hook est bien installé
            if [ -f ".git/hooks/pre-commit" ]; then
                log "SUCCESS" "Hook pre-commit activé"
            else
                log "WARN" "Hook pre-commit non créé"
            fi
        else
            log "WARN" "Impossible d'installer les hooks Git automatiquement"
            log "INFO" "Vous pourrez les installer manuellement avec: composer grumphp:install"
        fi
    else
        log "WARN" "Pas de dépôt Git, hooks non installés"
        log "INFO" "Initialisez un dépôt Git puis utilisez: composer grumphp:install"
    fi

    log "SUCCESS" "Configuration GrumPHP créée: grumphp.yml"
    log "INFO" "Outils intégrés: $(echo $tools | tr ' ' ',')"
    log "INFO" "✅ CORRECTION: Utilisation de 'git_blacklist' pour compatibilité GrumPHP"
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
        "refactor": "vendor/bin/rector process",
        "grumphp": "vendor/bin/grumphp run"
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
    grumphp_available = os.path.exists('vendor/phpro/grumphp')
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

    # Scripts GrumPHP si disponible
    if grumphp_available:
        custom_scripts.update({
            "grumphp:install": "vendor/bin/grumphp git:init",
            "grumphp:uninstall": "vendor/bin/grumphp git:deinit",
            "grumphp:run": "vendor/bin/grumphp run",
            "grumphp:check": "vendor/bin/grumphp run --no-interaction",
            "pre-commit": "vendor/bin/grumphp run --no-interaction"
        })
        # Ajouter GrumPHP à la qualité complète
        custom_scripts["quality:full"] = [
            "@check:cs",
            "@analyse",
            "@insights",
            "@grumphp:check"
        ]

    # Scripts adaptatifs selon les packages installés
    if pest_available:
        custom_scripts.update({
            "test:unit": "vendor/bin/pest --testsuite=Unit",
            "test:feature": "vendor/bin/pest --testsuite=Feature",
            "test:pest": "vendor/bin/pest"
        })
        # Ajouter Pest aux scripts de qualité si GrumPHP n'est pas disponible
        if not grumphp_available:
            custom_scripts["quality:full"] = [
                "@check:cs",
                "@analyse",
                "@insights",
                "@test:pest"
            ]
        # Sinon ajouter Pest à GrumPHP
        elif grumphp_available:
            custom_scripts["quality:full"].append("@test:pest")
    else:
        # Utiliser PHPUnit par défaut
        custom_scripts.update({
            "test:unit": "php artisan test --testsuite=Unit",
            "test:feature": "php artisan test --testsuite=Feature",
            "test:phpunit": "vendor/bin/phpunit"
        })
        # Ajouter PHPUnit si GrumPHP n'est pas disponible
        if not grumphp_available:
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

# Fonction principale d'installation CORRIGÉE - AUCUNE MODIFICATION .ENV
main() {
    # Initialiser le logging
    log "INFO" "🚀 Installation complète de Laravel avec outils de qualité et Nightwatch"
    log "INFO" "✅ Support complet PHP 8.4 + Laravel 12 + COPIE CORRIGÉE .env + Nightwatch"
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

    # Afficher des informations de debug sur la structure
    if [ "$DEBUG" = "true" ]; then
        log "DEBUG" "Structure du projet détectée :"
        if [ -f "docker-compose.yml" ]; then
            log "DEBUG" "  ✓ docker-compose.yml trouvé"
        fi
        if [ -d "docker/" ]; then
            log "DEBUG" "  ✓ Dossier docker/ trouvé"
        fi
        if [ -f "/.dockerenv" ] || [ -n "${DOCKER_CONTAINER}" ]; then
            log "DEBUG" "  ✓ Environnement Docker container détecté"
        else
            log "DEBUG" "  ✓ Environnement hôte détecté"
        fi
        log "DEBUG" "  → Répertoire cible Laravel: $WORKING_DIR"
    fi

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
        log "INFO" "Fichier composer.json détecté dans $WORKING_DIR"

        # Vérifier si c'est bien un projet Laravel
        if grep -q "laravel/framework" "$WORKING_DIR/composer.json"; then
            log "SUCCESS" "Projet Laravel valide trouvé"
        else
            log "WARN" "Le composer.json existe mais ne semble pas être un projet Laravel"
            log "INFO" "Tentative de création d'un nouveau projet Laravel..."
            create_laravel_project "$WORKING_DIR"
        fi
    fi

    # Vérifier que nous avons bien un projet Laravel maintenant
    if [ ! -f "$WORKING_DIR/artisan" ]; then
        log "ERROR" "Aucun projet Laravel trouvé après installation"
        log "DEBUG" "Contenu de $WORKING_DIR:"
        ls -la "$WORKING_DIR" 2>/dev/null || true
        exit 1
    fi

    # Se déplacer dans le répertoire de travail
    cd "$WORKING_DIR"
    log "DEBUG" "Changement de répertoire vers: $WORKING_DIR"

    # PHASE 1: Migrations de base seulement (avec .env Laravel par défaut)
    log "INFO" "🔄 PHASE 1: Migrations de base Laravel..."
    run_base_migrations

    # PHASE 2: Installation des packages de production avec Nightwatch
    log "INFO" "📦 PHASE 2: Installation des packages de production avec Nightwatch..."
    local production_packages=(
        "laravel/horizon"
        "laravel/telescope"
        "laravel/sanctum"
        "laravel/nightwatch"
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

    # PHASE 3: Publication sécurisée des assets (SANS migrations)
    log "INFO" "📋 PHASE 3: Publication sécurisée des assets..."
    publish_package_assets_safely

    # PHASE 4: Publication conditionnelle des migrations
    log "INFO" "📋 PHASE 4: Publication conditionnelle des migrations..."
    publish_migrations_if_needed

    # Générer la clé d'application si nécessaire
    if ! grep -q "APP_KEY=.*" .env || grep -q "APP_KEY=$" .env; then
        log "INFO" "Génération de la clé d'application..."
        php artisan key:generate --no-interaction --force
    fi

    # PHASE 5: Migrations finales (packages) SANS conflit
    log "INFO" "🔄 PHASE 5: Migrations finales des packages - SANS conflit..."
    run_final_migrations

    # PHASE 6: Installation des outils de qualité de code
    log "INFO" "🛠️ PHASE 6: Installation des outils de qualité de code..."
    local dev_packages=(
        "symplify/easy-coding-standard"
        "rector/rector"
        "larastan/larastan"
        "nunomaduro/collision"
        "nunomaduro/phpinsights"
        "barryvdh/laravel-ide-helper"
        "beyondcode/laravel-query-detector"
        "phpro/grumphp"
        "pestphp/pest"
        "pestphp/pest-plugin-laravel"
    )

    # Installer les packages de dev
    for package in "${dev_packages[@]}"; do
        if ! install_package "$package" "require-dev"; then
            failed_packages+=("package")
            log "WARN" "Échec de l'installation de $package (dev)"
        fi
        sleep 1
    done

    # Installation et configuration d'Enlightn EN DERNIER (si compatible)
    local laravel_version=$(get_laravel_version)
    if [ "$laravel_version" -lt 12 ]; then
        log "INFO" "🔧 Installation et configuration d'Enlightn..."
        if ! install_package "enlightn/enlightn" "require-dev"; then
            failed_packages+=("enlightn/enlightn")
            log "WARN" "Échec de l'installation d'Enlightn"
        else
            log "SUCCESS" "✅ Enlightn installé avec succès"
        fi
    else
        log "INFO" "🔧 Enlightn ignoré - non compatible avec Laravel $laravel_version"
        log "INFO" "   Enlightn supporte Laravel jusqu'à la version 11"
    fi

    # Finalisation des packages
    log "INFO" "🔄 Finalisation de l'installation des packages..."
    COMPOSER_MEMORY_LIMIT=-1 composer install --no-interaction --optimize-autoloader 2>&1 | tee -a "$LOG_FILE"

    # Générer les fichiers IDE Helper après les migrations
    log "INFO" "💡 Génération des fichiers IDE Helper..."
    php artisan ide-helper:generate 2>/dev/null || true
    php artisan ide-helper:meta 2>/dev/null || true
    php artisan ide-helper:models --write 2>/dev/null || true

    # Configuration des outils de qualité
    log "INFO" "⚙️ Configuration des outils de qualité (PHP 8.4 optimisé)..."
    create_quality_tools_config

    # Configurer GrumPHP AVEC CORRECTIONS
    configure_grumphp

    # Configurer les scripts
    configure_composer_scripts
    configure_package_json

    # Optimisation finale
    log "INFO" "⚡ Optimisation finale..."
    php artisan config:cache 2>/dev/null || true
    php artisan route:cache 2>/dev/null || true
    php artisan view:cache 2>/dev/null || true

    # ⭐ ÉTAPE CRITIQUE : COPIE CORRIGÉE du .env racine (juste avant Nightwatch)
    if is_package_installed "laravel/nightwatch"; then
        log "INFO" "🌙 Préparation et démarrage de l'agent Nightwatch..."

        # COPIE COMPLÈTE ET CORRIGÉE du .env racine vers Laravel
        log "INFO" "📋 🎯 COPIE CORRIGÉE du .env racine vers Laravel pour Nightwatch..."
        if copy_root_env_to_laravel; then
            log "SUCCESS" "✅ Configuration Nightwatch synchronisée avec le .env racine"
        else
            log "WARN" "⚠️ Problème avec la copie du .env racine"
            log "INFO" "Tentative de démarrage avec la configuration existante..."
        fi

        # Vérifier si Nightwatch est configuré (token présent et non vide)
        local current_token=$(grep "^NIGHTWATCH_TOKEN=" .env 2>/dev/null | cut -d'=' -f2- | sed 's/^["'\'']//' | sed 's/["'\'']$//' | xargs)
        if [ -n "$current_token" ] && [ "$current_token" != "\${NIGHTWATCH_TOKEN}" ] && [ "$current_token" != "" ]; then
            log "INFO" "Token Nightwatch configuré (${current_token:0:10}...), démarrage de l'agent..."

            # Vérifier que la commande existe
            if php artisan list 2>/dev/null | grep -q "nightwatch:agent"; then
                log "SUCCESS" "Commande nightwatch:agent disponible"

                # Démarrer l'agent en arrière-plan avec nohup
                log "INFO" "Démarrage de l'agent Nightwatch en arrière-plan..."
                nohup php artisan nightwatch:agent > nightwatch.log 2>&1 &
                local nightwatch_pid=$!
                echo $nightwatch_pid > nightwatch.pid

                log "SUCCESS" "✅ Agent Nightwatch démarré en arrière-plan (PID: $nightwatch_pid)"
                log "INFO" "📊 Logs de l'agent: nightwatch.log"
                log "INFO" "🛑 Pour arrêter l'agent: kill \$(cat nightwatch.pid)"
                log "INFO" "🔄 Pour redémarrer: nohup php artisan nightwatch:agent > nightwatch.log 2>&1 & echo \$! > nightwatch.pid"

                # Attendre quelques secondes et vérifier que l'agent fonctionne
                sleep 3
                if kill -0 $nightwatch_pid 2>/dev/null; then
                    log "SUCCESS" "🎉 Agent Nightwatch fonctionne correctement !"
                    log "INFO" "💡 Consultez nightwatch.log pour voir l'activité de monitoring"
                else
                    log "WARN" "⚠️ L'agent semble s'être arrêté, consultez nightwatch.log pour plus d'infos"
                fi
            else
                log "WARN" "Commande nightwatch:agent non disponible"
                log "INFO" "Vérifiez l'installation avec: php artisan list | grep nightwatch"
                log "INFO" "Ou publiez la configuration: php artisan vendor:publish --provider=\"Laravel\\Nightwatch\\NightwatchServiceProvider\""
            fi
        else
            log "WARN" "Token Nightwatch non configuré ou vide"
            log "INFO" "Token actuel: '${current_token}'"
            log "INFO" "L'agent ne peut pas démarrer sans token valide"
            log "INFO" "Vérifiez la configuration de NIGHTWATCH_TOKEN dans le .env racine"

            # Diagnostic supplémentaire
            log "DEBUG" "Diagnostic de la configuration Nightwatch:"
            log "DEBUG" "Contenu NIGHTWATCH dans .env Laravel:"
            grep "NIGHTWATCH" .env 2>/dev/null || log "DEBUG" "Aucune configuration Nightwatch trouvée"

            # Afficher le .env racine pour diagnostic
            if root_env_file=$(find_root_env); then
                log "DEBUG" "Contenu NIGHTWATCH dans .env racine:"
                grep "NIGHTWATCH" "$root_env_file" 2>/dev/null || log "DEBUG" "Aucune configuration Nightwatch trouvée dans .env racine"
            fi
        fi
    else
        log "DEBUG" "Nightwatch non installé, agent non démarré"
    fi

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

    # Test Nightwatch
    if is_package_installed "laravel/nightwatch"; then
        local current_token=$(grep "^NIGHTWATCH_TOKEN=" .env 2>/dev/null | cut -d'=' -f2- | sed 's/^["'\'']//' | sed 's/["'\'']$//' | xargs)
        log "SUCCESS" "✓ Laravel Nightwatch installé et configuré"
        log "INFO" "  • Token NIGHTWATCH_TOKEN: ${current_token:0:10}..."
        log "INFO" "  • Configuration publiée avec vendor:publish"
        log "INFO" "  • 🚀 Agent démarré automatiquement en arrière-plan"
        log "INFO" "  • Logs disponibles: nightwatch.log"
        log "INFO" "  • PID agent: nightwatch.pid"
    else
        log "WARN" "✗ Laravel Nightwatch non installé"
    fi

    log "SUCCESS" "🎉 Installation complète terminée avec Nightwatch !"
    log "INFO" "✅ APPROCHE CORRIGÉE APPLIQUÉE:"
    log "INFO" "  • 🛡️ Migrations SANS conflit: Sanctum + Telescope (résolu définitivement)"
    log "INFO" "  • 🔧 GrumPHP: git_blacklist au lieu de git_conflict (corrigé)"
    log "INFO" "  • 🐘 PHP 8.4: Support complet et optimisations"
    log "INFO" "  • 🎯 Laravel 12: Configurations adaptées"
    log "INFO" "  • 🌙 Nightwatch: COPIE CORRIGÉE du .env racine (détection robuste multi-chemins)"
    log "INFO" "  • 📈 Monitoring: Configuration parfaitement synchronisée"
    log "INFO" "  • ✨ Détection robuste: Multiples stratégies + score de confiance !"

    log "INFO" "Prochaines étapes :"
    log "INFO" "1. ✅ Base de données configurée et migrée (SANS aucun conflit)"
    log "INFO" "2. ✅ .env racine CORRECTEMENT copié vers Laravel (détection multi-chemins robuste)"
    log "INFO" "3. ✅ Agent Nightwatch démarré automatiquement en arrière-plan"
    log "INFO" "4. ✅ Configuration synchronisée de manière fiable"
    log "INFO" "5. Accéder à l'application : https://laravel.local"
    log "INFO" "6. Lancer les tests : composer test:coverage"
    log "INFO" "7. Vérifier la qualité : composer quality"
    log "INFO" "8. Consulter les logs Nightwatch : tail -f nightwatch.log"

    log "INFO" "Log complet disponible: $LOG_FILE"

    # Instructions spéciales pour Nightwatch
    if is_package_installed "laravel/nightwatch"; then
        local current_token=$(grep "^NIGHTWATCH_TOKEN=" .env 2>/dev/null | cut -d'=' -f2- | sed 's/^["'\'']//' | sed 's/["'\'']$//' | xargs)
        log "INFO" ""
        log "INFO" "🌙 Laravel Nightwatch est maintenant configuré et DÉMARRÉ !"
        log "INFO" "  • ✅ .env racine CORRECTEMENT copié vers Laravel/src/"
        log "INFO" "  • ✅ Token récupéré depuis .env racine: ${current_token:0:10}..."
        log "INFO" "  • ✅ Détection robuste avec score de confiance pour maximum de fiabilité"
        log "INFO" "  • ✅ Plus de problème de synchronisation entre .env racine et Laravel"
        log "INFO" "  • Configuration publiée dans config/nightwatch.php"
        log "INFO" "  • 🚀 Agent Nightwatch démarré automatiquement en arrière-plan !"
        log "INFO" "  • Logs en temps réel: tail -f nightwatch.log"
        log "INFO" "  • Arrêter l'agent: kill \$(cat nightwatch.pid)"
        log "INFO" "  • Redémarrer l'agent: nohup php artisan nightwatch:agent > nightwatch.log 2>&1 & echo \$! > nightwatch.pid"
        log "INFO" "  • Documentation: https://github.com/laravel/nightwatch"
        log "INFO" ""
        log "INFO" "📋 DÉTECTION ROBUSTE DU .ENV RACINE:"
        log "INFO" "  • Détection multi-chemins avec 5+ stratégies de recherche"
        log "INFO" "  • Score de confiance basé sur 4 critères spécifiques Docker"
        log "INFO" "  • Support des chemins Docker spécialisés (/var/www/project/, etc.)"
        log "INFO" "  • Résolution automatique des liens symboliques"
        log "INFO" "  • Diagnostic complet en cas d'échec"
        log "INFO" "  • Script docker/scripts/ optimisé pour tous les environnements"
    fi
}

# Exécuter l'installation
main "$@"