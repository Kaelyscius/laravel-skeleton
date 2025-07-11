#!/bin/bash

# =============================================================================
# GÉNÉRATEUR DE CONFIGURATION .ENV RACINE - VERSION CORRIGÉE
# =============================================================================
# Ce script met à jour UNIQUEMENT le .env racine
# La copie vers src/.env est gérée par install-laravel.sh

set -e

# Couleurs pour les logs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/config/installer.yml"
ENV_FILE="$PROJECT_ROOT/.env"  # UNIQUEMENT le .env racine
TARGET_ENV="${1:-local}"

# Variables pour stocker les valeurs du .env existant
declare -A EXISTING_ENV_VALUES

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%H:%M:%S')

    case $level in
        "INFO")  echo -e "${BLUE}[$timestamp]${NC} $message" ;;
        "WARN")  echo -e "${YELLOW}[$timestamp]${NC} $message" ;;
        "SUCCESS") echo -e "${GREEN}[$timestamp]${NC} $message" ;;
        "ERROR") echo -e "${RED}[$timestamp]${NC} $message" ;;
    esac
}

# Vérifier les prérequis
check_dependencies() {
    if ! command -v yq &> /dev/null; then
        log "WARN" "⚠️ yq n'est pas installé - utilisation de valeurs par défaut"
        log "INFO" "💡 Pour installer yq: brew install yq (macOS) ou apt install yq (Ubuntu)"
        USE_DEFAULTS=true
    else
        USE_DEFAULTS=false
        log "SUCCESS" "✅ yq disponible"
    fi

    if [ ! -f "$CONFIG_FILE" ]; then
        log "WARN" "⚠️ Fichier de configuration non trouvé: $CONFIG_FILE"
        log "INFO" "💡 Utilisation de valeurs par défaut"
        USE_DEFAULTS=true
    fi
}

# Fonction pour lire une valeur du YAML (avec fallback)
get_config() {
    local path="$1"
    local default="$2"

    if [ "$USE_DEFAULTS" = "true" ]; then
        echo "$default"
        return 0
    fi

    local value=$(yq eval "$path" "$CONFIG_FILE" 2>/dev/null)
    if [ -n "$value" ] && [ "$value" != "null" ]; then
        echo "$value"
    else
        echo "$default"
    fi
}

# Lire le fichier .env racine existant
load_existing_env() {
    log "INFO" "📋 Lecture du fichier .env racine existant..."

    if [ ! -f "$ENV_FILE" ]; then
        log "WARN" "⚠️ Aucun fichier .env racine existant - création depuis zéro"
        return 0
    fi

    # Parser le .env existant ligne par ligne
    while IFS= read -r line; do
        # Ignorer les commentaires et lignes vides
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "$line" ]]; then
            continue
        fi

        # Extraire variable=valeur
        if [[ "$line" =~ ^([A-Z_]+)=(.*)$ ]]; then
            local var_name="${BASH_REMATCH[1]}"
            local var_value="${BASH_REMATCH[2]}"

            # Stocker la valeur (sans guillemets)
            var_value=$(echo "$var_value" | sed 's/^["'\'']//' | sed 's/["'\'']$//')
            EXISTING_ENV_VALUES["$var_name"]="$var_value"
        fi
    done < "$ENV_FILE"

    local count=${#EXISTING_ENV_VALUES[@]}
    log "SUCCESS" "✅ $count variables lues depuis le .env racine"
}

# Fonction pour obtenir une valeur : .env existant > config YAML > défaut
get_env_value() {
    local var_name="$1"
    local yaml_path="$2"
    local default_value="$3"

    # 1. Priorité au .env racine existant
    if [ -n "${EXISTING_ENV_VALUES[$var_name]}" ]; then
        echo "${EXISTING_ENV_VALUES[$var_name]}"
        return 0
    fi

    # 2. Ensuite config YAML
    if [ -n "$yaml_path" ]; then
        local yaml_value=$(get_config "$yaml_path" "$default_value")
        echo "$yaml_value"
        return 0
    fi

    # 3. Enfin valeur par défaut
    echo "$default_value"
}

# Générer le fichier .env racine mis à jour
generate_updated_env() {
    log "INFO" "🔧 Mise à jour du fichier .env RACINE pour l'environnement: $TARGET_ENV"

    # Sauvegarder l'ancien fichier
    if [ -f "$ENV_FILE" ]; then
        cp "$ENV_FILE" "$ENV_FILE.backup.$(date +%Y%m%d-%H%M%S)"
        log "INFO" "📋 Sauvegarde créée"
    fi

    # Valeurs par défaut selon l'environnement
    local debug_value="true"
    local log_level="debug"
    if [ "$TARGET_ENV" = "production" ]; then
        debug_value="false"
        log_level="error"
    fi

    # Extraire le domaine proprement
    local domain=$(get_env_value "SSL_COMMON_NAME" "" "laravel.local")

    # Construire le nouveau .env racine
    cat > "$ENV_FILE" << 'ENVEOF'
# ===========================================
# 🚀 LARAVEL DOCKER ENVIRONMENT - Mis à jour automatiquement
# ===========================================

# Application
APP_NAME=Laravel
APP_ENV=local
APP_KEY=
APP_DEBUG=true
APP_URL=https://laravel.local
APP_TIMEZONE=UTC

# Docker
COMPOSE_PROJECT_NAME=laravel-app
COMPOSE_BAKE=true

# ===========================================
# 💾 DATABASE (MariaDB)
# ===========================================
DB_CONNECTION=mysql
DB_HOST=mariadb
DB_PORT=3306
DB_DATABASE=laravel
DB_USERNAME=laravel
DB_PASSWORD=secret
DB_ROOT_PASSWORD=rootsecret

# ===========================================
# 🗄️ REDIS
# ===========================================
REDIS_HOST=redis
REDIS_PASSWORD=redissecret
REDIS_PORT=6379

# ===========================================
# 📧 EMAIL (Développement avec MailHog)
# ===========================================
MAIL_MAILER=smtp
MAIL_HOST=mailhog
MAIL_PORT=1025
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_ENCRYPTION=null
MAIL_FROM_ADDRESS="hello@laravel.local"
MAIL_FROM_NAME="${APP_NAME}"

# ===========================================
# 🔍 QUEUES & CACHE & SESSION (Redis)
# ===========================================
QUEUE_CONNECTION=redis
CACHE_DRIVER=redis
CACHE_STORE=redis
SESSION_DRIVER=redis
SESSION_LIFETIME=120

# ===========================================
# 📻 BROADCASTING & FILESYSTEM
# ===========================================
BROADCAST_DRIVER=log
FILESYSTEM_DISK=local

# ===========================================
# 🔒 HASHING & PASSWORDS
# ===========================================
BCRYPT_ROUNDS=10

# ===========================================
# 📊 MONITORING - Watchtower & Uptime
# ===========================================
WATCHTOWER_NOTIFICATIONS=
WATCHTOWER_DEBUG=false

# Ports de monitoring
DOZZLE_PORT=9999

# ===========================================
# 🔐 SÉCURITÉ & SSL
# ===========================================
JWT_SECRET=your-jwt-secret-key
SESSION_SECURE_COOKIE=true
SESSION_HTTP_ONLY=true
SESSION_SAME_SITE=lax

# SSL Certificate
SSL_COUNTRY=FR
SSL_STATE=IDF
SSL_LOCALITY=Paris
SSL_ORGANIZATION=Laravel
SSL_ORGANIZATIONAL_UNIT=Development
SSL_COMMON_NAME=laravel.local

# ===========================================
# 🔧 DÉVELOPPEMENT & LOGGING
# ===========================================
LOG_CHANNEL=stack
LOG_STACK=single,nightwatch,daily
LOG_DEPRECATIONS_CHANNEL=null
LOG_LEVEL=debug

# ===========================================
# 🌙 NIGHTWATCH - Monitoring Laravel
# ===========================================
NIGHTWATCH_TOKEN=${NIGHTWATCH_TOKEN}
NIGHTWATCH_EXCEPTION_SAMPLE_RATE=1.0
NIGHTWATCH_COMMAND_SAMPLE_RATE=1.0
NIGHTWATCH_REQUEST_SAMPLE_RATE=0.1

# ===========================================
# 🔭 TELESCOPE & HORIZON
# ===========================================
TELESCOPE_ENABLED=true
HORIZON_PREFIX=horizon:${APP_NAME}
HORIZON_DASHBOARD_ENABLED=true

# ===========================================
# ⚡ VITE (Frontend)
# ===========================================
VITE_APP_NAME="${APP_NAME}"

# ===========================================
# 🛡️ SÉCURITÉ - SNYK CONFIGURATION
# ===========================================
SNYK_TOKEN=
SNYK_SEVERITY_THRESHOLD=high
SNYK_FAIL_ON_ISSUES=false
SNYK_MONITOR_ENABLED=true
SNYK_ORG_ID=
SNYK_EXCLUDE_PATHS=vendor/,node_modules/,tests/,storage/
SNYK_INCLUDE_DEV_DEPS=true
SNYK_PRINT_DEPS=false
SNYK_DOCKER_SCAN_ENABLED=false
SNYK_PROJECT_NAME_PHP=${APP_NAME}-php
SNYK_PROJECT_NAME_NODE=${APP_NAME}-node
ENVEOF

    # Mise à jour dynamique des valeurs selon l'environnement et configuration existante
    update_env_values_dynamically

    log "SUCCESS" "✅ Fichier .env RACINE mis à jour pour l'environnement $TARGET_ENV"
}

# Fonction pour mettre à jour dynamiquement les valeurs
update_env_values_dynamically() {
    local temp_file=$(mktemp)

    # Mise à jour des valeurs spécifiques
    {
        echo "# Valeurs mises à jour dynamiquement"
        echo "APP_ENV=$TARGET_ENV"

        if [ "$TARGET_ENV" = "production" ]; then
            echo "APP_DEBUG=false"
            echo "LOG_LEVEL=error"
        else
            echo "APP_DEBUG=true"
            echo "LOG_LEVEL=debug"
        fi

        # Préserver les valeurs existantes importantes
        for var in NIGHTWATCH_TOKEN SNYK_TOKEN DB_PASSWORD REDIS_PASSWORD; do
            if [ -n "${EXISTING_ENV_VALUES[$var]}" ]; then
                echo "$var=${EXISTING_ENV_VALUES[$var]}"
            fi
        done
    } > "$temp_file"

    # Merger avec le fichier principal
    cat "$temp_file" >> "$ENV_FILE"
    rm -f "$temp_file"
}

# Fonction principale
main() {
    echo -e "${CYAN}🔧 Mise à jour du fichier .env RACINE${NC}"
    echo -e "${CYAN}Environnement cible: $TARGET_ENV${NC}"
    echo ""

    check_dependencies
    load_existing_env
    generate_updated_env

    log "SUCCESS" "🎉 Configuration .env racine mise à jour !"
    echo ""
    echo -e "${YELLOW}💡 Ce script ne modifie QUE le .env racine${NC}"
    echo -e "${YELLOW}💡 La copie vers src/.env sera faite par install-laravel.sh${NC}"
}

# Exécuter
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi