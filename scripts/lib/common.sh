#!/bin/bash

# =============================================================================
# FONCTIONS COMMUNES POUR L'INSTALLATION LARAVEL
# =============================================================================
#
# Ce module contient les fonctions utilitaires communes utilisées par tous
# les modules d'installation. Il fournit des helpers pour Docker, la gestion
# des packages, les vérifications système, etc.
#
# Utilisation:
#   source "$(dirname "$0")/lib/common.sh"
#
# =============================================================================

# Variables globales
if [ -z "$SCRIPT_DIR" ]; then
    readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [ -z "$PROJECT_ROOT" ]; then
    readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

if [ -z "$CONFIG_FILE" ]; then
    readonly CONFIG_FILE="$PROJECT_ROOT/config/installer.yml"
fi

# =============================================================================
# FONCTIONS DE GESTION DE CONFIGURATION
# =============================================================================

#
# Lire une valeur depuis le fichier de configuration YAML
#
# Arguments:
#   $1: Clé à lire (format: section.subsection.key)
#
# Exemple:
#   get_config_value "project.name"
#
get_config_value() {
    local key="$1"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log_warn "Fichier de configuration non trouvé: $CONFIG_FILE"
        return 1
    fi
    
    # Utiliser yq si disponible, sinon fallback sur grep/sed
    if command -v yq &> /dev/null; then
        yq eval ".$key" "$CONFIG_FILE" 2>/dev/null
    else
        log_debug "yq non disponible, utilisation de grep/sed pour lire la configuration"
        # Fallback simple pour les configurations basiques
        grep "^${key##*.}:" "$CONFIG_FILE" | sed 's/.*: *"\?\([^"]*\)"\?.*/\1/' | head -1
    fi
}

#
# Vérifier si une valeur de configuration existe
#
config_exists() {
    local key="$1"
    local value=$(get_config_value "$key")
    
    [ -n "$value" ] && [ "$value" != "null" ]
}

# =============================================================================
# FONCTIONS DE GESTION D'ENVIRONNEMENT
# =============================================================================

#
# Détecter le répertoire de travail correct selon l'environnement
#
detect_working_directory() {
    log_debug "Détection du répertoire de travail..."
    
    # Vérifier si nous sommes dans un container Docker
    if is_docker_environment; then
        log_debug "Environnement Docker détecté"
        
        # Dans le container, utiliser /var/www/html
        if [ -d "/var/www/html" ]; then
            log_debug "Répertoire Docker détecté: /var/www/html"
            echo "/var/www/html"
            return 0
        fi
    fi
    
    # Hors container, vérifier si nous avons un dossier src/
    local current_dir=$(pwd)
    if [ -d "$current_dir/src" ]; then
        log_debug "Dossier src/ détecté: $current_dir/src"
        echo "$current_dir/src"
        return 0
    fi
    
    # Créer le dossier src/ s'il n'existe pas (structure de projet attendue)
    if [ -f "$current_dir/docker-compose.yml" ] && grep -q "./src:/var/www/html" "$current_dir/docker-compose.yml"; then
        log_info "Structure de projet Docker détectée, création de la structure..."
        create_project_structure "$current_dir"
        echo "$current_dir/src"
        return 0
    fi
    
    # Par défaut, utiliser le répertoire courant
    log_warn "Structure de projet non reconnue, utilisation du répertoire courant"
    echo "$current_dir"
}

#
# Vérifier si nous sommes dans un environnement Docker
#
is_docker_environment() {
    [ -f "/.dockerenv" ] || [ -n "${DOCKER_CONTAINER:-}" ]
}

#
# Obtenir l'environnement actuel (local, development, staging, production)
#
get_current_environment() {
    local env="${LARAVEL_ENV:-${APP_ENV:-local}}"
    
    # Valider l'environnement
    case "$env" in
        local|development|staging|production) echo "$env" ;;
        *) echo "local" ;;
    esac
}

# =============================================================================
# FONCTIONS DE GESTION DES CONTAINERS DOCKER
# =============================================================================

#
# Vérifier si un container Docker est en cours d'exécution
#
# Arguments:
#   $1: Nom du container à vérifier
#
check_container() {
    local container_name="$1"
    
    if [ -z "$container_name" ]; then
        log_error "Nom de container requis"
        return 1
    fi
    
    if ! docker ps --format "table {{.Names}}" | grep -q "^${container_name}$"; then
        log_error "Container '$container_name' non trouvé ou non démarré"
        log_info "Lancez: make up"
        return 1
    fi
    
    log_debug "Container '$container_name' trouvé et en cours d'exécution"
    return 0
}

#
# Attendre qu'un container soit prêt
#
# Arguments:
#   $1: Nom du container
#   $2: Timeout en secondes (défaut: 60)
#
wait_for_container() {
    local container_name="$1"
    local timeout="${2:-60}"
    local count=0
    
    log_info "Attente du container '$container_name'..."
    
    while [ $count -lt $timeout ]; do
        if check_container "$container_name"; then
            log_success "Container '$container_name' prêt"
            return 0
        fi
        
        sleep 1
        count=$((count + 1))
        
        if [ $((count % 10)) -eq 0 ]; then
            log_debug "Attente... ($count/$timeout secondes)"
        fi
    done
    
    log_error "Timeout atteint en attendant le container '$container_name'"
    return 1
}

# =============================================================================
# FONCTIONS DE GESTION DE BASE DE DONNÉES
# =============================================================================

#
# Attendre que la base de données soit prête
#
# Arguments:
#   $1: Nombre maximum de tentatives (défaut: 30)
#
wait_for_database() {
    local max_attempts="${1:-30}"
    local attempt=1
    
    log_info "Attente de la disponibilité de la base de données..."
    
    while [ $attempt -le $max_attempts ]; do
        if php -r "
            try {
                \$pdo = new PDO('mysql:host=' . getenv('DB_HOST') . ';port=' . getenv('DB_PORT'), getenv('DB_USERNAME'), getenv('DB_PASSWORD'));
                echo 'OK';
                exit(0);
            } catch (Exception \$e) {
                exit(1);
            }
        " 2>/dev/null; then
            log_success "Base de données disponible"
            return 0
        fi
        
        log_debug "Tentative $attempt/$max_attempts - Base de données non disponible"
        sleep 2
        attempt=$((attempt + 1))
    done
    
    log_error "Impossible de se connecter à la base de données après $max_attempts tentatives"
    return 1
}

#
# Vérifier si une table existe dans la base de données
#
# Arguments:
#   $1: Nom de la table à vérifier
#
table_exists() {
    local table_name="$1"
    
    if [ -z "$table_name" ]; then
        log_error "Nom de table requis"
        return 1
    fi
    
    local result=$(php -r "
        try {
            \$pdo = new PDO('mysql:host=' . getenv('DB_HOST') . ';dbname=' . getenv('DB_DATABASE') . ';port=' . getenv('DB_PORT'), getenv('DB_USERNAME'), getenv('DB_PASSWORD'));
            \$stmt = \$pdo->query(\"SHOW TABLES LIKE '$table_name'\");
            echo \$stmt->rowCount() > 0 ? 'EXISTS' : 'NOT_EXISTS';
        } catch (Exception \$e) {
            echo 'ERROR';
        }
    " 2>/dev/null)
    
    case "$result" in
        "EXISTS")
            log_debug "Table '$table_name' existe"
            return 0
            ;;
        "NOT_EXISTS")
            log_debug "Table '$table_name' n'existe pas"
            return 1
            ;;
        *)
            log_error "Erreur lors de la vérification de la table '$table_name'"
            return 1
            ;;
    esac
}

# =============================================================================
# FONCTIONS DE GESTION DES PACKAGES
# =============================================================================

#
# Vérifier si un package Composer est installé
#
# Arguments:
#   $1: Nom du package à vérifier
#   $2: Répertoire de travail (optionnel)
#
is_package_installed() {
    local package_name="$1"
    local work_dir="${2:-$(pwd)}"
    
    if [ -z "$package_name" ]; then
        log_error "Nom de package requis"
        return 1
    fi
    
    if [ ! -f "$work_dir/composer.json" ]; then
        log_debug "Fichier composer.json non trouvé dans $work_dir"
        return 1
    fi
    
    # Vérifier dans composer.json
    if grep -q "\"$package_name\"" "$work_dir/composer.json" 2>/dev/null; then
        log_debug "Package '$package_name' trouvé dans composer.json"
        return 0
    fi
    
    # Vérifier dans composer.lock si disponible
    if [ -f "$work_dir/composer.lock" ]; then
        if grep -q "\"name\": \"$package_name\"" "$work_dir/composer.lock" 2>/dev/null; then
            log_debug "Package '$package_name' trouvé dans composer.lock"
            return 0
        fi
    fi
    
    log_debug "Package '$package_name' non installé"
    return 1
}

#
# Vérifier la compatibilité d'un package avec la version PHP/Laravel
#
# Arguments:
#   $1: Nom du package
#   $2: Version (optionnel)
#
check_package_compatibility() {
    local package_name="$1"
    local package_version="${2:-}"
    
    # Version PHP actuelle
    local php_version=$(get_php_version)
    local laravel_version=$(get_laravel_version)
    
    log_debug "Vérification de compatibilité pour $package_name"
    log_debug "PHP: $php_version, Laravel: $laravel_version"
    
    # TODO: Implémenter des vérifications spécifiques selon les packages
    # Pour l'instant, toujours compatible
    return 0
}

# =============================================================================
# FONCTIONS UTILITAIRES SYSTÈME
# =============================================================================

#
# Obtenir la version de PHP
#
get_php_version() {
    php -v | head -1 | sed 's/PHP \([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/'
}

#
# Obtenir la version de Laravel installée
#
get_laravel_version() {
    local work_dir="${1:-$(pwd)}"
    
    if [ -f "$work_dir/artisan" ]; then
        # Essayer d'obtenir la version via artisan
        php "$work_dir/artisan" --version 2>/dev/null | sed 's/Laravel Framework \([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/' || echo "unknown"
    elif [ -f "$work_dir/composer.json" ]; then
        # Fallback sur composer.json
        grep '"laravel/framework"' "$work_dir/composer.json" | sed 's/.*"\^\?\([0-9]\+\.[0-9]\+\).*/\1/' | head -1
    else
        echo "unknown"
    fi
}

#
# Créer la structure initiale du projet
#
# Arguments:
#   $1: Répertoire racine du projet
#
create_project_structure() {
    local project_root="$1"
    
    log_debug "Création de la structure initiale du projet..."
    
    # Créer le dossier src/ pour Laravel si on est hors container
    if ! is_docker_environment; then
        mkdir -p "$project_root/src"
        log_debug "Dossier src/ créé: $project_root/src"
        
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
    
    log_debug "Structure initiale du projet créée"
}

#
# Vérifier si un fichier de configuration existe
#
find_root_env() {
    local project_root="$1"
    local env_files=(".env" ".env.local" ".env.example")
    
    for env_file in "${env_files[@]}"; do
        if [ -f "$project_root/$env_file" ]; then
            echo "$project_root/$env_file"
            return 0
        fi
    done
    
    log_warn "Aucun fichier .env trouvé dans $project_root"
    return 1
}

#
# Calculer la durée d'exécution
#
# Arguments:
#   $1: Timestamp de début
#
calculate_duration() {
    local start_time="$1"
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [ $duration -lt 60 ]; then
        echo "${duration}s"
    elif [ $duration -lt 3600 ]; then
        echo "$((duration / 60))m $((duration % 60))s"
    else
        echo "$((duration / 3600))h $((duration % 3600 / 60))m $((duration % 60))s"
    fi
}

#
# Créer un backup d'un fichier avant modification
#
backup_file() {
    local file_path="$1"
    local backup_suffix="${2:-.backup.$(date +%Y%m%d-%H%M%S)}"
    
    if [ -f "$file_path" ]; then
        cp "$file_path" "${file_path}${backup_suffix}"
        log_debug "Backup créé: ${file_path}${backup_suffix}"
        return 0
    else
        log_warn "Fichier à sauvegarder non trouvé: $file_path"
        return 1
    fi
}

# =============================================================================
# FONCTIONS DE CONFIGURATION YAML (DEMANDÉ DANS LE PROMPT)
# =============================================================================

# Répertoire de configuration du projet
readonly CONFIG_DIR="${CONFIG_DIR:-$(dirname "$SCRIPT_DIR")/../config}"
readonly INSTALLER_CONFIG="$CONFIG_DIR/installer.yml"

#
# Lire les packages depuis config/installer.yml avec yq (DEMANDÉ DANS LE PROMPT)
#
# Arguments:
#   $1: Type de packages (production|development)
#
get_packages_from_config() {
    local package_type="$1"
    
    if [ -z "$package_type" ]; then
        log_error "Type de package requis (production|development)"
        return 1
    fi
    
    if [ ! -f "$INSTALLER_CONFIG" ]; then
        log_error "Fichier de configuration non trouvé: $INSTALLER_CONFIG"
        return 1
    fi
    
    log_debug "Lecture des packages $package_type depuis $INSTALLER_CONFIG"
    
    # Méthode préférée: yq
    if command -v yq >/dev/null 2>&1; then
        log_debug "Utilisation de yq pour lire la configuration YAML"
        yq eval ".packages.$package_type[].name" "$INSTALLER_CONFIG" 2>/dev/null
        return $?
    fi
    
    # Fallback: utiliser PHP avec une solution de parsing YAML simple
    if command -v php >/dev/null 2>&1; then
        [ "$LOG_LEVEL" = "debug" ] && echo "[DEBUG] yq non disponible, utilisation de PHP pour lire le YAML" >&2
        
        # Créer un script PHP temporaire pour éviter les problèmes d'échappement
        local php_script="/tmp/yaml_parser_$$.php"
        cat > "$php_script" << 'EOF'
<?php
$yaml = file_get_contents($argv[1]);
$package_type = $argv[2];

$lines = explode("\n", $yaml);
$in_packages = false;
$in_type = false;
$indent_level = 0;

foreach ($lines as $line) {
    $trimmed = trim($line);
    if (empty($trimmed) || $trimmed[0] === '#') continue;
    
    if (strpos($line, 'packages:') === 0) {
        $in_packages = true;
        continue;
    }
    
    if ($in_packages && strpos($line, "  $package_type:") === 0) {
        $in_type = true;
        $indent_level = strlen($line) - strlen(ltrim($line));
        continue;
    }
    
    if ($in_type) {
        $current_indent = strlen($line) - strlen(ltrim($line));
        
        // Si on retourne au même niveau d'indentation ou moins, on sort du type
        if ($current_indent <= $indent_level && $trimmed !== '') {
            break;
        }
        
        // Extraire le nom du package
        if (preg_match('/- name:\s*["\']?([^"\'\s]+)["\']?/', $line, $matches)) {
            echo $matches[1] . "\n";
        }
    }
}
EOF
        
        # Exécuter le script PHP et nettoyer
        php "$php_script" "$INSTALLER_CONFIG" "$package_type" 2>/dev/null
        local result=$?
        rm -f "$php_script" 2>/dev/null
        return $result
    fi
    
    log_error "Ni yq ni php ne sont disponibles pour lire la configuration YAML"
    return 1
}

#
# Vérifier si un package est requis selon la configuration
#
# Arguments:
#   $1: Nom du package
#   $2: Type de packages (production|development)
#
is_package_required() {
    local package_name="$1"
    local package_type="$2"
    
    if [ ! -f "$INSTALLER_CONFIG" ] || ! command -v yq >/dev/null 2>&1; then
        # Fallback: considérer comme requis si pas de config
        return 0
    fi
    
    local required=$(yq eval ".packages.$package_type[] | select(.name == \"$package_name\") | .required" "$INSTALLER_CONFIG" 2>/dev/null)
    
    [ "$required" = "true" ]
}

#
# Obtenir la version d'un package depuis la configuration
#
# Arguments:
#   $1: Nom du package
#   $2: Type de packages (production|development)
#
get_package_version() {
    local package_name="$1"
    local package_type="$2"
    
    if [ ! -f "$INSTALLER_CONFIG" ] || ! command -v yq >/dev/null 2>&1; then
        echo "*"  # Fallback
        return 0
    fi
    
    local version=$(yq eval ".packages.$package_type[] | select(.name == \"$package_name\") | .version" "$INSTALLER_CONFIG" 2>/dev/null)
    
    echo "${version:-*}"
}

#
# Obtenir la version PHP requise d'un package depuis la configuration
#
# Arguments:
#   $1: Nom du package
#   $2: Type de packages (production|development)
#
get_package_php_version() {
    local package_name="$1"
    local package_type="$2"
    
    if [ ! -f "$INSTALLER_CONFIG" ] || ! command -v yq >/dev/null 2>&1; then
        echo ""  # Pas de contrainte
        return 0
    fi
    
    local php_version=$(yq eval ".packages.$package_type[] | select(.name == \"$package_name\") | .php_version" "$INSTALLER_CONFIG" 2>/dev/null)
    
    if [ "$php_version" = "null" ]; then
        echo ""
    else
        echo "$php_version"
    fi
}

#
# Obtenir la version Laravel maximale supportée par un package
#
# Arguments:
#   $1: Nom du package
#   $2: Type de packages (production|development)
#
get_package_max_laravel_version() {
    local package_name="$1"
    local package_type="$2"
    
    if [ ! -f "$INSTALLER_CONFIG" ] || ! command -v yq >/dev/null 2>&1; then
        echo ""  # Pas de limite
        return 0
    fi
    
    local max_laravel=$(yq eval ".packages.$package_type[] | select(.name == \"$package_name\") | .max_laravel_version" "$INSTALLER_CONFIG" 2>/dev/null)
    
    if [ "$max_laravel" = "null" ]; then
        echo ""
    else
        echo "$max_laravel"
    fi
}

#
# Vérifier si un package est compatible avec la version Laravel actuelle
#
# Arguments:
#   $1: Nom du package
#   $2: Type de packages (production|development)
#
# Retourne:
#   0 si compatible ou pas de contrainte
#   1 si incompatible
#
is_package_laravel_compatible() {
    local package_name="$1"
    local package_type="$2"
    
    local max_laravel=$(get_package_max_laravel_version "$package_name" "$package_type")
    
    # Pas de contrainte = compatible
    if [ -z "$max_laravel" ]; then
        return 0
    fi
    
    local current_laravel=$(get_laravel_version | cut -d. -f1)
    
    # Vérifier si la version actuelle dépasse la limite
    if [ "$current_laravel" -gt "$max_laravel" ]; then
        return 1
    fi
    
    return 0
}

#
# Vérifier si un package est compatible avec la version PHP actuelle
#
# Arguments:
#   $1: Nom du package
#   $2: Type de packages (production|development)
#
# Retourne:
#   0 si compatible ou pas de contrainte
#   1 si incompatible
#
is_package_php_compatible() {
    local package_name="$1"
    local package_type="$2"
    
    local required_php=$(get_package_php_version "$package_name" "$package_type")
    
    # Pas de contrainte = compatible
    if [ -z "$required_php" ]; then
        return 0
    fi
    
    local current_php=$(get_php_version)
    
    # Parser la contrainte PHP (supporte >=, ^, ~, etc.)
    case "$required_php" in
        ">=*")
            local min_version="${required_php#>=}"
            version_compare "$current_php" "$min_version"
            ;;
        "^*")
            # Contrainte Caret: ^8.1 = >=8.1.0 <9.0.0
            local base_version="${required_php#^}"
            local major=$(echo "$base_version" | cut -d. -f1)
            local next_major=$((major + 1))
            
            version_compare "$current_php" "$base_version" && \
            ! version_compare "$current_php" "$next_major.0.0"
            ;;
        "~*")
            # Contrainte Tilde: ~8.1 = >=8.1.0 <8.2.0
            local base_version="${required_php#~}"
            local major=$(echo "$base_version" | cut -d. -f1)
            local minor=$(echo "$base_version" | cut -d. -f2)
            local next_minor=$((minor + 1))
            
            version_compare "$current_php" "$base_version" && \
            ! version_compare "$current_php" "$major.$next_minor.0"
            ;;
        *)
            # Version exacte ou simple comparaison
            version_compare "$current_php" "$required_php"
            ;;
    esac
}

# =============================================================================
# FONCTIONS DE COMPARAISON DE VERSIONS
# =============================================================================

#
# Comparer deux versions selon le format semver (x.y.z)
#
# Arguments:
#   $1: Version actuelle
#   $2: Version requise minimale
#
# Retourne:
#   0 si la version actuelle >= version requise
#   1 sinon
#
version_compare() {
    local current="$1"
    local required="$2"
    
    if [ -z "$current" ] || [ -z "$required" ]; then
        log_debug "Version vide dans version_compare: current='$current', required='$required'"
        return 1
    fi
    
    log_debug "Comparaison versions: '$current' >= '$required'"
    
    # Conversion en nombres pour comparaison
    local current_num=$(echo "$current" | awk -F. '{printf "%d%03d%03d", $1, $2, $3}')
    local required_num=$(echo "$required" | awk -F. '{printf "%d%03d%03d", $1, $2, $3}')
    
    log_debug "Versions numériques: current=$current_num, required=$required_num"
    
    [ "$current_num" -ge "$required_num" ]
}

# =============================================================================
# EXPORT DES FONCTIONS
# =============================================================================

#
# Vérifier automatiquement si les packages incompatibles sont devenus compatibles Laravel 12
#
# Arguments:
#   $1: Nom du package
#
# Retourne:
#   0 si compatible maintenant, 1 sinon
#
check_package_laravel12_compatibility() {
    local package_name="$1"
    
    # Utiliser Composer pour vérifier la compatibilité en ligne
    if command -v composer &> /dev/null; then
        # Test avec Laravel 12 simulé
        local temp_dir="/tmp/laravel12-compat-test"
        local test_file="$temp_dir/composer.json"
        
        # Créer un projet test temporaire
        mkdir -p "$temp_dir"
        cat > "$test_file" << EOF
{
    "name": "test/laravel12-compatibility",
    "require": {
        "laravel/framework": "^12.0",
        "$package_name": "*"
    },
    "minimum-stability": "stable",
    "prefer-stable": true
}
EOF
        
        # Tester la résolution (sans installation)
        if composer validate "$test_file" --quiet 2>/dev/null && \
           timeout 30 composer install --dry-run --working-dir="$temp_dir" --no-interaction --quiet 2>/dev/null; then
            rm -rf "$temp_dir"
            return 0  # Compatible
        fi
        
        rm -rf "$temp_dir"
    fi
    
    return 1  # Pas compatible ou test impossible
}

#
# Mettre à jour automatiquement les packages devenus compatibles
#
# Arguments:
#   $1: Liste des packages à vérifier (séparés par des espaces)
#
update_compatible_packages() {
    local packages=($1)
    local updated_packages=()
    
    log_info "🔄 Vérification automatique compatibilité Laravel 12..."
    
    for package in "${packages[@]}"; do
        log_debug "Test: $package"
        
        if check_package_laravel12_compatibility "$package"; then
            log_success "✅ $package est maintenant compatible avec Laravel 12!"
            
            # Tenter l'installation
            if composer require --dev "$package" --no-interaction 2>/dev/null; then
                updated_packages+=("$package")
                log_success "📦 $package installé avec succès"
            else
                log_warn "⚠️ $package compatible mais installation échouée"
            fi
        else
            log_debug "⏳ $package pas encore compatible"
        fi
    done
    
    if [ ${#updated_packages[@]} -gt 0 ]; then
        log_success "🎉 Packages mis à jour: ${updated_packages[*]}"
        
        # Mettre à jour la liste des packages incompatibles
        update_incompatible_packages_list "${updated_packages[@]}"
    else
        log_info "ℹ️ Aucun nouveau package compatible trouvé"
    fi
}

#
# Mettre à jour la liste des packages incompatibles après installation réussie
#
update_incompatible_packages_list() {
    local installed_packages=("$@")
    local config_file="config/installer.yml"
    
    if [ ! -f "$config_file" ]; then
        return 0
    fi
    
    # Marquer les packages comme compatibles dans la config
    for package in "${installed_packages[@]}"; do
        # Commenter ou supprimer la contrainte max_laravel_version
        if command -v yq &> /dev/null; then
            # Utiliser yq si disponible
            yq eval ".development[] |= select(.name == \"$package\").laravel_12_compatible = true" -i "$config_file" 2>/dev/null || true
        fi
    done
    
    log_info "📝 Configuration mise à jour pour: ${installed_packages[*]}"
}

# Rendre les fonctions disponibles pour les scripts qui sourcent ce fichier
export -f get_config_value config_exists
export -f detect_working_directory is_docker_environment get_current_environment
export -f check_container wait_for_container
export -f wait_for_database table_exists
export -f is_package_installed check_package_compatibility
export -f get_php_version get_laravel_version create_project_structure
export -f find_root_env calculate_duration backup_file
export -f get_packages_from_config is_package_required get_package_version
export -f get_package_php_version is_package_php_compatible
export -f get_package_max_laravel_version is_package_laravel_compatible
export -f check_package_laravel12_compatibility update_compatible_packages update_incompatible_packages_list
export -f version_compare

# Variables globales exportées
export SCRIPT_DIR PROJECT_ROOT CONFIG_FILE