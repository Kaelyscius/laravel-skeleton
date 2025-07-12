#!/bin/bash

# =============================================================================
# GÉNÉRATEUR DE CONFIGURATION .ENV.{ENVIRONNEMENT} - VERSION FINALE
# =============================================================================
# Ce script génère des fichiers .env spécifiques par environnement
# Workflow: .env racine → .env.{env} → src/.env (via install-laravel.sh)

set -e

# Couleurs pour les logs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/config/installer.yml"
ROOT_ENV_FILE="$PROJECT_ROOT/.env"
TARGET_ENV="${1:-local}"
TARGET_ENV_FILE="$PROJECT_ROOT/.env.$TARGET_ENV"

# Variables pour stocker les valeurs du .env racine existant
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
        "HEADER") echo -e "${PURPLE}[$timestamp]${NC} $message" ;;
    esac
}

# =============================================================================
# FONCTIONS DE GESTION .ENV SANS DOUBLONS
# =============================================================================

# Fonction pour mettre à jour une variable sans créer de doublon
update_env_var() {
    local env_file="$1"
    local var_name="$2"
    local var_value="$3"

    # Créer le fichier s'il n'existe pas
    if [ ! -f "$env_file" ]; then
        touch "$env_file"
    fi

    # Échapper les caractères spéciaux pour sed
    local escaped_value=$(printf '%s\n' "$var_value" | sed 's/[[\.*^$(){}?+|/]/\\&/g')

    # Vérifier si la variable existe déjà
    if grep -q "^${var_name}=" "$env_file"; then
        # Remplacer la valeur existante (compatible macOS et Linux)
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/^${var_name}=.*/${var_name}=${escaped_value}/" "$env_file"
        else
            sed -i "s/^${var_name}=.*/${var_name}=${escaped_value}/" "$env_file"
        fi
    else
        # Ajouter la nouvelle variable
        echo "${var_name}=${var_value}" >> "$env_file"
    fi
}

# Vérifier les prérequis
check_dependencies() {
    if ! command -v yq &> /dev/null; then
        log "WARN" "⚠️ yq n'est pas installé - utilisation de valeurs par défaut"
        USE_DEFAULTS=true
    else
        USE_DEFAULTS=false
        log "SUCCESS" "✅ yq disponible"
    fi

    if [ ! -f "$CONFIG_FILE" ]; then
        log "WARN" "⚠️ Fichier de configuration non trouvé: $CONFIG_FILE"
        USE_DEFAULTS=true
    fi

    # Valider l'environnement
    case "$TARGET_ENV" in
        local|development|staging|production)
            log "SUCCESS" "✅ Environnement valide: $TARGET_ENV"
            ;;
        *)
            log "ERROR" "❌ Environnement invalide: $TARGET_ENV"
            log "INFO" "💡 Environnements supportés: local, development, staging, production"
            exit 1
            ;;
    esac
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
load_existing_root_env() {
    log "INFO" "📋 Lecture du fichier .env RACINE existant..."

    if [ ! -f "$ROOT_ENV_FILE" ]; then
        log "WARN" "⚠️ Aucun fichier .env racine existant"
        return 0
    fi

    # Parser le .env racine ligne par ligne
    while IFS= read -r line; do
        # Ignorer les commentaires et lignes vides
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "$line" ]]; then
            continue
        fi

        # Extraire variable=valeur
        if [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
            local var_name="${BASH_REMATCH[1]}"
            local var_value="${BASH_REMATCH[2]}"

            # Supprimer les guillemets
            var_value=$(echo "$var_value" | sed 's/^["'\'']//' | sed 's/["'\'']$//')
            EXISTING_ENV_VALUES["$var_name"]="$var_value"
        fi
    done < "$ROOT_ENV_FILE"

    local count=${#EXISTING_ENV_VALUES[@]}
    log "SUCCESS" "✅ $count variables lues depuis le .env racine"
}

# Fonction pour obtenir une valeur : .env racine > config YAML > défaut
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

# Obtenir les services activés selon l'environnement
get_enabled_services() {
    local env="$1"
    local enabled_services=()

    case "$env" in
        "production")
            # Prod : Seulement Dozzle pour les logs
            enabled_services=("dozzle")
            ;;
        "staging")
            # Staging : Dozzle + Adminer pour debug DB
            enabled_services=("dozzle" "adminer")
            ;;
        "local"|"development")
            # Dev : Tous les services
            enabled_services=("mailhog" "adminer" "dozzle")
            # IT-Tools optionnel selon config
            local it_tools_enabled=$(get_config ".services.optional.it-tools.enabled" "false")
            if [ "$it_tools_enabled" = "true" ]; then
                enabled_services+=("it-tools")
            fi
            ;;
    esac

    printf '%s\n' "${enabled_services[@]}"
}

# Générer le docker-compose.override.yml selon l'environnement
generate_docker_override() {
    local env="$1"
    local override_file="$PROJECT_ROOT/docker-compose.override.yml"

    log "INFO" "🐳 Génération du docker-compose.override.yml pour $env..."

    # Sauvegarder l'ancien fichier
    if [ -f "$override_file" ]; then
        cp "$override_file" "$override_file.backup.$(date +%Y%m%d-%H%M%S)"
    fi

    cat > "$override_file" << EOF
# =============================================================================
# DOCKER COMPOSE OVERRIDE - Généré pour l'environnement: $env
# =============================================================================
# Ce fichier est généré automatiquement selon l'environnement choisi

services:
EOF

    # Services selon l'environnement
    local enabled_services
    enabled_services=$(get_enabled_services "$env")

    case "$env" in
        "production")
            cat >> "$override_file" << 'EOF'
  # ===========================================
  # PRODUCTION - Services optimisés
  # ===========================================

  php:
    environment:
      - APP_ENV=production
      - APP_DEBUG=false
      - PHP_OPCACHE_VALIDATE_TIMESTAMPS=0
      - PHP_OPCACHE_PRELOAD=/var/www/html/config/opcache-preload.php
    restart: always
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 1G

  # Services de développement désactivés
  mailhog:
    deploy:
      replicas: 0

  adminer:
    deploy:
      replicas: 0

  it-tools:
    deploy:
      replicas: 0

EOF
            ;;
        "staging")
            cat >> "$override_file" << 'EOF'
  # ===========================================
  # STAGING - Pré-production
  # ===========================================

  php:
    environment:
      - APP_ENV=staging
      - APP_DEBUG=false
      - PHP_OPCACHE_VALIDATE_TIMESTAMPS=0
    restart: unless-stopped

  # Services de développement partiellement désactivés
  mailhog:
    deploy:
      replicas: 0

  it-tools:
    deploy:
      replicas: 0

EOF
            ;;
        "local"|"development")
            cat >> "$override_file" << 'EOF'
  # ===========================================
  # DÉVELOPPEMENT - Tous les outils
  # ===========================================

  php:
    environment:
      - APP_ENV=local
      - APP_DEBUG=true
      - XDEBUG_ENABLE=false  # Activable à la demande
      - PHP_OPCACHE_VALIDATE_TIMESTAMPS=1
    volumes:
      - ./docker/php/conf/xdebug.ini:/usr/local/etc/php/conf.d/xdebug.ini.disabled:ro
    extra_hosts:
      - "host.docker.internal:host-gateway"

EOF
            if [[ "$enabled_services" == *"it-tools"* ]]; then
                cat >> "$override_file" << 'EOF'
  # IT-Tools activé pour cet environnement
  it-tools:
    deploy:
      replicas: 1

EOF
            fi
            ;;
    esac

    log "SUCCESS" "✅ Docker override généré pour $env"
}

# Générer le fichier .env.{environnement} spécifique
generate_environment_env() {
    local env="$1"
    local env_file="$PROJECT_ROOT/.env.$env"

    log "HEADER" "🔧 Génération de .env.$env pour l'environnement: $env"

    # Sauvegarder l'ancien fichier
    if [ -f "$env_file" ]; then
        cp "$env_file" "$env_file.backup.$(date +%Y%m%d-%H%M%S)"
        log "INFO" "💾 Sauvegarde créée"
    fi

    # Créer le fichier temporaire
    local temp_env=$(mktemp)

    # En-tête avec commentaires
    cat > "$temp_env" << EOF
# ===========================================
# 🚀 LARAVEL DOCKER ENVIRONMENT - $env
# ===========================================
# Généré automatiquement pour l'environnement: $env
# ⚠️  Ce fichier contient des vraies valeurs - NE PAS VERSIONNER

EOF

    # Variables d'application adaptées à l'environnement
    local app_name=$(get_env_value "APP_NAME" ".project.name" "Laravel")
    local domain=$(get_env_value "SSL_COMMON_NAME" ".project.domain" "laravel.local")

    # Configuration selon l'environnement
    case "$env" in
        "production")
            # Production - Sécurisé et optimisé
            update_env_var "$temp_env" "APP_ENV" "production"
            update_env_var "$temp_env" "APP_DEBUG" "false"
            update_env_var "$temp_env" "LOG_LEVEL" "error"
            update_env_var "$temp_env" "LOG_CHANNEL" "daily"
            update_env_var "$temp_env" "TELESCOPE_ENABLED" "false"
            update_env_var "$temp_env" "SESSION_SECURE_COOKIE" "true"
            ;;
        "staging")
            # Staging - Logs modérés
            update_env_var "$temp_env" "APP_ENV" "staging"
            update_env_var "$temp_env" "APP_DEBUG" "false"
            update_env_var "$temp_env" "LOG_LEVEL" "info"
            update_env_var "$temp_env" "LOG_CHANNEL" "daily"
            update_env_var "$temp_env" "TELESCOPE_ENABLED" "true"
            update_env_var "$temp_env" "SESSION_SECURE_COOKIE" "true"
            ;;
        "development")
            # Développement équipe
            update_env_var "$temp_env" "APP_ENV" "development"
            update_env_var "$temp_env" "APP_DEBUG" "true"
            update_env_var "$temp_env" "LOG_LEVEL" "debug"
            update_env_var "$temp_env" "LOG_CHANNEL" "stack"
            update_env_var "$temp_env" "TELESCOPE_ENABLED" "true"
            update_env_var "$temp_env" "SESSION_SECURE_COOKIE" "false"
            ;;
        "local")
            # Local - Développement personnel
            update_env_var "$temp_env" "APP_ENV" "local"
            update_env_var "$temp_env" "APP_DEBUG" "true"
            update_env_var "$temp_env" "LOG_LEVEL" "debug"
            update_env_var "$temp_env" "LOG_CHANNEL" "stack"
            update_env_var "$temp_env" "TELESCOPE_ENABLED" "true"
            update_env_var "$temp_env" "SESSION_SECURE_COOKIE" "false"
            ;;
    esac

    # Variables communes (préservées du .env racine)
    echo "" >> "$temp_env"
    echo "# Application" >> "$temp_env"
    update_env_var "$temp_env" "APP_NAME" "$app_name"
    update_env_var "$temp_env" "APP_KEY" "$(get_env_value "APP_KEY" "" "")"
    update_env_var "$temp_env" "APP_URL" "https://$domain"
    update_env_var "$temp_env" "APP_TIMEZONE" "UTC"

    # Docker
    echo "" >> "$temp_env"
    echo "# Docker" >> "$temp_env"
    update_env_var "$temp_env" "COMPOSE_PROJECT_NAME" "$(get_env_value "COMPOSE_PROJECT_NAME" "" "laravel-app")"

    # Base de données (valeurs préservées)
    echo "" >> "$temp_env"
    echo "# ===========================================
# 💾 DATABASE (MariaDB)
# ===========================================" >> "$temp_env"
    update_env_var "$temp_env" "DB_CONNECTION" "mysql"
    update_env_var "$temp_env" "DB_HOST" "mariadb"
    update_env_var "$temp_env" "DB_PORT" "3306"
    update_env_var "$temp_env" "DB_DATABASE" "$(get_env_value "DB_DATABASE" "" "laravel")"
    update_env_var "$temp_env" "DB_USERNAME" "$(get_env_value "DB_USERNAME" "" "laravel")"
    update_env_var "$temp_env" "DB_PASSWORD" "$(get_env_value "DB_PASSWORD" "" "secret")"
    update_env_var "$temp_env" "DB_ROOT_PASSWORD" "$(get_env_value "DB_ROOT_PASSWORD" "" "rootsecret")"

    # Redis (valeurs préservées)
    echo "" >> "$temp_env"
    echo "# ===========================================
# 🗄️ REDIS
# ===========================================" >> "$temp_env"
    update_env_var "$temp_env" "REDIS_HOST" "redis"
    update_env_var "$temp_env" "REDIS_PASSWORD" "$(get_env_value "REDIS_PASSWORD" "" "redissecret")"
    update_env_var "$temp_env" "REDIS_PORT" "6379"

    # Email (adapté selon environnement)
    echo "" >> "$temp_env"
    echo "# ===========================================
# 📧 EMAIL
# ===========================================" >> "$temp_env"
    if [ "$env" = "production" ]; then
        # Production : SMTP réel (à configurer)
        update_env_var "$temp_env" "MAIL_MAILER" "smtp"
        update_env_var "$temp_env" "MAIL_HOST" "$(get_env_value "MAIL_HOST" "" "smtp.mailtrap.io")"
        update_env_var "$temp_env" "MAIL_PORT" "$(get_env_value "MAIL_PORT" "" "587")"
        update_env_var "$temp_env" "MAIL_USERNAME" "$(get_env_value "MAIL_USERNAME" "" "")"
        update_env_var "$temp_env" "MAIL_PASSWORD" "$(get_env_value "MAIL_PASSWORD" "" "")"
        update_env_var "$temp_env" "MAIL_ENCRYPTION" "tls"
    else
        # Dev/Staging : MailHog
        update_env_var "$temp_env" "MAIL_MAILER" "smtp"
        update_env_var "$temp_env" "MAIL_HOST" "mailhog"
        update_env_var "$temp_env" "MAIL_PORT" "1025"
        update_env_var "$temp_env" "MAIL_USERNAME" "null"
        update_env_var "$temp_env" "MAIL_PASSWORD" "null"
        update_env_var "$temp_env" "MAIL_ENCRYPTION" "null"
    fi
    update_env_var "$temp_env" "MAIL_FROM_ADDRESS" "hello@$domain"
    update_env_var "$temp_env" "MAIL_FROM_NAME" "\${APP_NAME}"

    # Queues & Cache
    echo "" >> "$temp_env"
    echo "# ===========================================
# 🔍 QUEUES & CACHE & SESSION (Redis)
# ===========================================" >> "$temp_env"
    update_env_var "$temp_env" "QUEUE_CONNECTION" "redis"
    update_env_var "$temp_env" "CACHE_DRIVER" "redis"
    update_env_var "$temp_env" "SESSION_DRIVER" "redis"
    update_env_var "$temp_env" "SESSION_LIFETIME" "120"

    # Logging adapté
    echo "" >> "$temp_env"
    echo "# ===========================================
# 🔧 LOGGING
# ===========================================" >> "$temp_env"
    update_env_var "$temp_env" "LOG_STACK" "single,nightwatch,daily"

    # Nightwatch (secrets préservés)
    echo "" >> "$temp_env"
    echo "# ===========================================
# 🌙 NIGHTWATCH - Monitoring Laravel
# ===========================================" >> "$temp_env"
    update_env_var "$temp_env" "NIGHTWATCH_TOKEN" "$(get_env_value "NIGHTWATCH_TOKEN" "" "\${NIGHTWATCH_TOKEN}")"
    update_env_var "$temp_env" "NIGHTWATCH_EXCEPTION_SAMPLE_RATE" "1.0"
    update_env_var "$temp_env" "NIGHTWATCH_COMMAND_SAMPLE_RATE" "1.0"

    # Sampling selon environnement
    if [ "$env" = "production" ]; then
        update_env_var "$temp_env" "NIGHTWATCH_REQUEST_SAMPLE_RATE" "0.01"  # 1% en prod
    else
        update_env_var "$temp_env" "NIGHTWATCH_REQUEST_SAMPLE_RATE" "0.1"   # 10% en dev
    fi

    # Horizon
    echo "" >> "$temp_env"
    echo "# ===========================================
# 🔭 HORIZON
# ===========================================" >> "$temp_env"
    update_env_var "$temp_env" "HORIZON_PREFIX" "horizon:\${APP_NAME}"
    update_env_var "$temp_env" "HORIZON_DASHBOARD_ENABLED" "true"

    # SSL
    echo "" >> "$temp_env"
    echo "# ===========================================
# 🔐 SÉCURITÉ & SSL
# ===========================================" >> "$temp_env"
    update_env_var "$temp_env" "SESSION_HTTP_ONLY" "true"
    update_env_var "$temp_env" "SESSION_SAME_SITE" "lax"
    update_env_var "$temp_env" "SSL_COMMON_NAME" "$domain"

    # Watchtower (secrets préservés)
    echo "" >> "$temp_env"
    echo "# ===========================================
# 📊 MONITORING - Watchtower
# ===========================================" >> "$temp_env"
    update_env_var "$temp_env" "WATCHTOWER_NOTIFICATIONS" "$(get_env_value "WATCHTOWER_NOTIFICATIONS" "" "")"
    update_env_var "$temp_env" "WATCHTOWER_DEBUG" "false"

    # Snyk (secrets préservés)
    echo "" >> "$temp_env"
    echo "# ===========================================
# 🛡️ SÉCURITÉ - SNYK CONFIGURATION
# ===========================================" >> "$temp_env"
    update_env_var "$temp_env" "SNYK_TOKEN" "$(get_env_value "SNYK_TOKEN" "" "")"
    update_env_var "$temp_env" "SNYK_SEVERITY_THRESHOLD" "high"
    update_env_var "$temp_env" "SNYK_FAIL_ON_ISSUES" "false"
    update_env_var "$temp_env" "SNYK_MONITOR_ENABLED" "true"

    # Vite
    echo "" >> "$temp_env"
    echo "# ===========================================
# ⚡ VITE (Frontend)
# ===========================================" >> "$temp_env"
    update_env_var "$temp_env" "VITE_APP_NAME" "\${APP_NAME}"

    # Remplacer le fichier final
    mv "$temp_env" "$env_file"

    log "SUCCESS" "✅ Fichier .env.$env généré avec succès"
}

# Afficher le résumé des fichiers générés
show_generation_summary() {
    local env="$1"

    echo ""
    log "SUCCESS" "🎉 Génération terminée pour l'environnement: $env"
    echo ""
    echo -e "${CYAN}📁 Fichiers générés :${NC}"
    echo -e "  • ${GREEN}.env.$env${NC} - Configuration spécifique $env"
    echo -e "  • ${GREEN}docker-compose.override.yml${NC} - Services adaptés"
    echo ""

    case "$env" in
        "production")
            echo -e "${YELLOW}🔒 Configuration PRODUCTION :${NC}"
            echo -e "  • APP_DEBUG=false, LOG_LEVEL=error"
            echo -e "  • TELESCOPE_ENABLED=false (sécurité)"
            echo -e "  • Services: Dozzle uniquement"
            echo -e "  • Sampling Nightwatch: 1% (optimisé)"
            ;;
        "staging")
            echo -e "${YELLOW}🧪 Configuration STAGING :${NC}"
            echo -e "  • APP_DEBUG=false, LOG_LEVEL=info"
            echo -e "  • TELESCOPE_ENABLED=true (debug)"
            echo -e "  • Services: Dozzle + Adminer"
            echo -e "  • Sampling Nightwatch: 10%"
            ;;
        "local"|"development")
            echo -e "${YELLOW}🛠️ Configuration DÉVELOPPEMENT :${NC}"
            echo -e "  • APP_DEBUG=true, LOG_LEVEL=debug"
            echo -e "  • TELESCOPE_ENABLED=true"
            echo -e "  • Services: Tous (MailHog, Adminer, Dozzle)"
            echo -e "  • Sampling Nightwatch: 10%"
            echo -e "  • Xdebug: Activable à la demande"
            ;;
    esac

    echo ""
    echo -e "${BLUE}💡 Prochaines étapes :${NC}"
    echo -e "  1. ${GREEN}make install-laravel${NC} - Installer Laravel avec cette config"
    echo -e "  2. Le fichier .env.$env sera copié vers src/.env automatiquement"
    echo -e "  3. Vérifiez les secrets (NIGHTWATCH_TOKEN, SNYK_TOKEN, etc.)"
}

# Fonction principale
main() {
    echo -e "${PURPLE}🔧 GÉNÉRATEUR .ENV SPÉCIFIQUE PAR ENVIRONNEMENT${NC}"
    echo -e "${PURPLE}===============================================${NC}"
    echo ""

    check_dependencies
    load_existing_root_env
    generate_environment_env "$TARGET_ENV"
    generate_docker_override "$TARGET_ENV"
    show_generation_summary "$TARGET_ENV"
}

# Afficher l'aide
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    cat << EOF
🔧 Générateur de configuration .env spécifique par environnement

USAGE:
    ./scripts/setup/generate-configs.sh [ENVIRONNEMENT]

ENVIRONNEMENTS:
    local         Configuration développement local (défaut)
    development   Configuration développement équipe
    staging       Configuration pré-production
    production    Configuration production optimisée

EXEMPLES:
    ./scripts/setup/generate-configs.sh local
    ./scripts/setup/generate-configs.sh production

FICHIERS GÉNÉRÉS:
    .env.[ENVIRONNEMENT]        Configuration spécifique
    docker-compose.override.yml Services adaptés

EOF
    exit 0
fi

# Exécuter
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi