#!/bin/bash

# Script de scan de sécurité avec Snyk
# Usage: ./scripts/security/snyk-scan.sh [options]

set -e

# Couleurs pour les logs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Configuration par défaut
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPORTS_DIR="$PROJECT_ROOT/reports/security"
ENV_FILE="$PROJECT_ROOT/.env"

# Variables de configuration
SNYK_TOKEN=""
SNYK_SEVERITY_THRESHOLD="high"
SNYK_FAIL_ON_ISSUES="false"
SNYK_MONITOR_ENABLED="true"
SNYK_ORG_ID=""
SNYK_EXCLUDE_PATHS="vendor/,node_modules/,tests/,storage/"
SNYK_INCLUDE_DEV_DEPS="true"
SNYK_PRINT_DEPS="false"
SNYK_DOCKER_SCAN_ENABLED="false"
SNYK_PROJECT_NAME_PHP=""
SNYK_PROJECT_NAME_NODE=""

# Fonction de logging
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case $level in
        "INFO")
            echo -e "${BLUE}[INFO $timestamp]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN $timestamp]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR $timestamp]${NC} $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS $timestamp]${NC} $message"
            ;;
        "DEBUG")
            if [ "$VERBOSE" = "true" ]; then
                echo -e "${PURPLE}[DEBUG $timestamp]${NC} $message"
            fi
            ;;
    esac
}

# Fonction pour charger la configuration depuis .env
load_env_config() {
    log "INFO" "📋 Chargement de la configuration depuis .env..."

    if [ -f "$ENV_FILE" ]; then
        # Charger les variables depuis .env en évitant les conflits
        while IFS= read -r line; do
            # Ignorer les commentaires et lignes vides
            if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "$line" ]]; then
                continue
            fi

            # Extraire la variable et sa valeur
            if [[ "$line" =~ ^([A-Z_]+)=(.*)$ ]]; then
                var_name="${BASH_REMATCH[1]}"
                var_value="${BASH_REMATCH[2]}"

                # Supprimer les guillemets si présents
                var_value=$(echo "$var_value" | sed 's/^["'\'']//' | sed 's/["'\'']$//')

                # Assigner les variables Snyk
                case $var_name in
                    "SNYK_TOKEN")
                        SNYK_TOKEN="$var_value"
                        ;;
                    "SNYK_SEVERITY_THRESHOLD")
                        SNYK_SEVERITY_THRESHOLD="$var_value"
                        ;;
                    "SNYK_FAIL_ON_ISSUES")
                        SNYK_FAIL_ON_ISSUES="$var_value"
                        ;;
                    "SNYK_MONITOR_ENABLED")
                        SNYK_MONITOR_ENABLED="$var_value"
                        ;;
                    "SNYK_ORG_ID")
                        SNYK_ORG_ID="$var_value"
                        ;;
                    "SNYK_EXCLUDE_PATHS")
                        SNYK_EXCLUDE_PATHS="$var_value"
                        ;;
                    "SNYK_INCLUDE_DEV_DEPS")
                        SNYK_INCLUDE_DEV_DEPS="$var_value"
                        ;;
                    "SNYK_PRINT_DEPS")
                        SNYK_PRINT_DEPS="$var_value"
                        ;;
                    "SNYK_DOCKER_SCAN_ENABLED")
                        SNYK_DOCKER_SCAN_ENABLED="$var_value"
                        ;;
                    "SNYK_PROJECT_NAME_PHP")
                        SNYK_PROJECT_NAME_PHP="$var_value"
                        ;;
                    "SNYK_PROJECT_NAME_NODE")
                        SNYK_PROJECT_NAME_NODE="$var_value"
                        ;;
                    "APP_NAME")
                        # Utiliser APP_NAME pour générer les noms de projet par défaut
                        if [ -z "$SNYK_PROJECT_NAME_PHP" ]; then
                            SNYK_PROJECT_NAME_PHP="${var_value}-php"
                        fi
                        if [ -z "$SNYK_PROJECT_NAME_NODE" ]; then
                            SNYK_PROJECT_NAME_NODE="${var_value}-node"
                        fi
                        ;;
                esac
            fi
        done < "$ENV_FILE"

        log "SUCCESS" "Configuration chargée depuis .env"
    else
        log "WARN" "Fichier .env non trouvé, utilisation des valeurs par défaut"
    fi

    # Configuration par défaut pour les noms de projet si non définis
    if [ -z "$SNYK_PROJECT_NAME_PHP" ]; then
        SNYK_PROJECT_NAME_PHP="laravel-php"
    fi
    if [ -z "$SNYK_PROJECT_NAME_NODE" ]; then
        SNYK_PROJECT_NAME_NODE="laravel-node"
    fi
}

# Fonction pour afficher la configuration
show_config() {
    log "INFO" "🔧 Configuration Snyk active:"
    echo -e "  ${CYAN}• Token configuré:${NC} $([ -n "$SNYK_TOKEN" ] && echo "✅ Oui (${SNYK_TOKEN:0:10}...)" || echo "❌ Non")"
    echo -e "  ${CYAN}• Seuil de sévérité:${NC} $SNYK_SEVERITY_THRESHOLD"
    echo -e "  ${CYAN}• Échec sur vulnérabilités:${NC} $SNYK_FAIL_ON_ISSUES"
    echo -e "  ${CYAN}• Monitoring activé:${NC} $SNYK_MONITOR_ENABLED"
    echo -e "  ${CYAN}• Organisation:${NC} $([ -n "$SNYK_ORG_ID" ] && echo "$SNYK_ORG_ID" || echo "Par défaut")"
    echo -e "  ${CYAN}• Nom projet PHP:${NC} $SNYK_PROJECT_NAME_PHP"
    echo -e "  ${CYAN}• Nom projet Node:${NC} $SNYK_PROJECT_NAME_NODE"
    echo -e "  ${CYAN}• Inclure dev deps:${NC} $SNYK_INCLUDE_DEV_DEPS"
    echo -e "  ${CYAN}• Scan Docker:${NC} $SNYK_DOCKER_SCAN_ENABLED"
}

# Fonction pour vérifier les prérequis
check_prerequisites() {
    log "INFO" "🔍 Vérification des prérequis..."

    # Vérifier si Snyk CLI est installé
    if ! command -v snyk &> /dev/null; then
        log "ERROR" "Snyk CLI n'est pas installé"
        log "INFO" "💡 Installation avec npm: npm install -g snyk"
        log "INFO" "💡 Ou avec Homebrew: brew install snyk/tap/snyk"
        exit 1
    fi

    # Vérifier la version de Snyk
    local snyk_version=$(snyk --version 2>/dev/null || echo "unknown")
    log "SUCCESS" "Snyk CLI installé (version: $snyk_version)"

    # Authentification Snyk
    if [ -n "$SNYK_TOKEN" ]; then
        log "INFO" "🔐 Authentification avec le token Snyk..."
        if echo "$SNYK_TOKEN" | snyk auth --stdin 2>/dev/null; then
            log "SUCCESS" "Authentification Snyk réussie"
        else
            log "WARN" "Échec de l'authentification Snyk, scan en mode limité"
        fi
    else
        log "WARN" "Token Snyk non configuré, scan en mode limité"
        log "INFO" "💡 Configurez SNYK_TOKEN dans .env pour toutes les fonctionnalités"
    fi
}

# Fonction pour créer le répertoire des rapports
prepare_reports_dir() {
    mkdir -p "$REPORTS_DIR"
    log "DEBUG" "Répertoire des rapports créé: $REPORTS_DIR"
}

# Fonction pour scanner les dépendances Composer (PHP)
scan_composer_dependencies() {
    local composer_file="$PROJECT_ROOT/src/composer.json"
    local composer_lock="$PROJECT_ROOT/src/composer.lock"

    if [ ! -f "$composer_file" ]; then
        log "WARN" "📦 Pas de composer.json trouvé dans src/, skip du scan PHP"
        return 0
    fi

    log "INFO" "🐘 Scan des dépendances Composer (PHP)..."

    # Construire les options Snyk
    local snyk_options=(
        "--file=$composer_file"
        "--severity-threshold=$SNYK_SEVERITY_THRESHOLD"
        "--json"
    )

    # Ajouter l'organisation si configurée
    if [ -n "$SNYK_ORG_ID" ]; then
        snyk_options+=("--org=$SNYK_ORG_ID")
    fi

    # Inclure les dépendances de développement si configuré
    if [ "$SNYK_INCLUDE_DEV_DEPS" = "true" ]; then
        snyk_options+=("--dev")
    fi

    # Exécuter le scan avec gestion des erreurs
    local report_file="$REPORTS_DIR/snyk-composer-$(date +%Y%m%d-%H%M%S).json"
    local exit_code=0

    cd "$PROJECT_ROOT/src"

    if snyk test "${snyk_options[@]}" > "$report_file" 2>&1; then
        log "SUCCESS" "✅ Aucune vulnérabilité critique trouvée dans les dépendances PHP"
    else
        exit_code=$?
        log "WARN" "⚠️ Vulnérabilités trouvées dans les dépendances PHP"

        # Extraire et afficher un résumé
        if command -v jq &> /dev/null && [ -f "$report_file" ]; then
            local high_count=$(jq -r '.vulnerabilities[] | select(.severity=="high") | .id' "$report_file" 2>/dev/null | wc -l)
            local critical_count=$(jq -r '.vulnerabilities[] | select(.severity=="critical") | .id' "$report_file" 2>/dev/null | wc -l)
            log "INFO" "📊 Résumé PHP: $critical_count critiques, $high_count élevées"
        fi
    fi

    log "INFO" "📄 Rapport sauvegardé: $report_file"
    cd "$PROJECT_ROOT"

    # Gestion de l'échec selon la configuration
    if [ "$SNYK_FAIL_ON_ISSUES" = "true" ] && [ $exit_code -ne 0 ]; then
        log "ERROR" "Scan PHP échoué et SNYK_FAIL_ON_ISSUES=true"
        return $exit_code
    fi

    return 0
}

# Fonction pour scanner les dépendances NPM (Node.js)
scan_npm_dependencies() {
    local package_file="$PROJECT_ROOT/src/package.json"
    local package_lock="$PROJECT_ROOT/src/package-lock.json"

    if [ ! -f "$package_file" ]; then
        log "WARN" "📦 Pas de package.json trouvé dans src/, skip du scan Node.js"
        return 0
    fi

    log "INFO" "📦 Scan des dépendances NPM (Node.js)..."

    # Construire les options Snyk
    local snyk_options=(
        "--file=$package_file"
        "--severity-threshold=$SNYK_SEVERITY_THRESHOLD"
        "--json"
    )

    # Ajouter l'organisation si configurée
    if [ -n "$SNYK_ORG_ID" ]; then
        snyk_options+=("--org=$SNYK_ORG_ID")
    fi

    # Inclure les dépendances de développement si configuré
    if [ "$SNYK_INCLUDE_DEV_DEPS" = "true" ]; then
        snyk_options+=("--dev")
    fi

    # Exécuter le scan avec gestion des erreurs
    local report_file="$REPORTS_DIR/snyk-npm-$(date +%Y%m%d-%H%M%S).json"
    local exit_code=0

    cd "$PROJECT_ROOT/src"

    if snyk test "${snyk_options[@]}" > "$report_file" 2>&1; then
        log "SUCCESS" "✅ Aucune vulnérabilité critique trouvée dans les dépendances Node.js"
    else
        exit_code=$?
        log "WARN" "⚠️ Vulnérabilités trouvées dans les dépendances Node.js"

        # Extraire et afficher un résumé
        if command -v jq &> /dev/null && [ -f "$report_file" ]; then
            local high_count=$(jq -r '.vulnerabilities[] | select(.severity=="high") | .id' "$report_file" 2>/dev/null | wc -l)
            local critical_count=$(jq -r '.vulnerabilities[] | select(.severity=="critical") | .id' "$report_file" 2>/dev/null | wc -l)
            log "INFO" "📊 Résumé Node.js: $critical_count critiques, $high_count élevées"
        fi
    fi

    log "INFO" "📄 Rapport sauvegardé: $report_file"
    cd "$PROJECT_ROOT"

    # Gestion de l'échec selon la configuration
    if [ "$SNYK_FAIL_ON_ISSUES" = "true" ] && [ $exit_code -ne 0 ]; then
        log "ERROR" "Scan Node.js échoué et SNYK_FAIL_ON_ISSUES=true"
        return $exit_code
    fi

    return 0
}

# Fonction pour scanner les images Docker (optionnel)
scan_docker_images() {
    if [ "$SNYK_DOCKER_SCAN_ENABLED" != "true" ]; then
        log "DEBUG" "Scan Docker désactivé"
        return 0
    fi

    log "INFO" "🐳 Scan des images Docker..."

    # Liste des images à scanner
    local images=(
        "php:8.4-fpm-alpine"
        "httpd:2.4-alpine"
        "mariadb:latest"
        "redis:alpine"
        "node:20-alpine"
    )

    for image in "${images[@]}"; do
        log "INFO" "🔍 Scan de l'image: $image"

        local report_file="$REPORTS_DIR/snyk-docker-$(echo $image | tr ':/' '-')-$(date +%Y%m%d-%H%M%S).json"

        if snyk container test "$image" --severity-threshold="$SNYK_SEVERITY_THRESHOLD" --json > "$report_file" 2>&1; then
            log "SUCCESS" "✅ Image $image: aucune vulnérabilité critique"
        else
            log "WARN" "⚠️ Vulnérabilités trouvées dans l'image $image"
            log "INFO" "📄 Rapport: $report_file"
        fi
    done
}

# Fonction pour activer le monitoring Snyk
enable_monitoring() {
    if [ "$SNYK_MONITOR_ENABLED" != "true" ] || [ -z "$SNYK_TOKEN" ]; then
        log "DEBUG" "Monitoring Snyk désactivé ou token manquant"
        return 0
    fi

    log "INFO" "📊 Activation du monitoring Snyk..."

    # Monitoring des dépendances PHP
    if [ -f "$PROJECT_ROOT/src/composer.json" ]; then
        cd "$PROJECT_ROOT/src"

        local monitor_options=(
            "--file=composer.json"
            "--project-name=$SNYK_PROJECT_NAME_PHP"
        )

        if [ -n "$SNYK_ORG_ID" ]; then
            monitor_options+=("--org=$SNYK_ORG_ID")
        fi

        if snyk monitor "${monitor_options[@]}" 2>/dev/null; then
            log "SUCCESS" "✅ Monitoring PHP activé: $SNYK_PROJECT_NAME_PHP"
        else
            log "WARN" "⚠️ Échec de l'activation du monitoring PHP"
        fi

        cd "$PROJECT_ROOT"
    fi

    # Monitoring des dépendances Node.js
    if [ -f "$PROJECT_ROOT/src/package.json" ]; then
        cd "$PROJECT_ROOT/src"

        local monitor_options=(
            "--file=package.json"
            "--project-name=$SNYK_PROJECT_NAME_NODE"
        )

        if [ -n "$SNYK_ORG_ID" ]; then
            monitor_options+=("--org=$SNYK_ORG_ID")
        fi

        if snyk monitor "${monitor_options[@]}" 2>/dev/null; then
            log "SUCCESS" "✅ Monitoring Node.js activé: $SNYK_PROJECT_NAME_NODE"
        else
            log "WARN" "⚠️ Échec de l'activation du monitoring Node.js"
        fi

        cd "$PROJECT_ROOT"
    fi
}

# Fonction pour générer un rapport consolidé
generate_summary_report() {
    log "INFO" "📋 Génération du rapport de synthèse..."

    local summary_file="$REPORTS_DIR/snyk-summary-$(date +%Y%m%d-%H%M%S).md"

    cat > "$summary_file" << EOF
# 🛡️ Rapport de Sécurité Snyk

**Date**: $(date '+%Y-%m-%d %H:%M:%S')
**Projet**: $(basename "$PROJECT_ROOT")
**Configuration**: $SNYK_SEVERITY_THRESHOLD et plus

## 📊 Résumé

### Dépendances PHP (Composer)
$([ -f "$PROJECT_ROOT/src/composer.json" ] && echo "✅ Scanné" || echo "⚠️ Non trouvé")

### Dépendances Node.js (NPM)
$([ -f "$PROJECT_ROOT/src/package.json" ] && echo "✅ Scanné" || echo "⚠️ Non trouvé")

### Images Docker
$([ "$SNYK_DOCKER_SCAN_ENABLED" = "true" ] && echo "✅ Scanné" || echo "❌ Désactivé")

### Monitoring Snyk
$([ "$SNYK_MONITOR_ENABLED" = "true" ] && [ -n "$SNYK_TOKEN" ] && echo "✅ Activé" || echo "❌ Désactivé")

## 📁 Rapports détaillés

Les rapports JSON détaillés sont disponibles dans:
\`$REPORTS_DIR\`

## 🔧 Configuration

- **Token Snyk**: $([ -n "$SNYK_TOKEN" ] && echo "Configuré" || echo "Non configuré")
- **Seuil de sévérité**: $SNYK_SEVERITY_THRESHOLD
- **Échec sur vulnérabilités**: $SNYK_FAIL_ON_ISSUES
- **Organisation**: $([ -n "$SNYK_ORG_ID" ] && echo "$SNYK_ORG_ID" || echo "Par défaut")

## 💡 Actions recommandées

1. Consultez les rapports JSON pour les détails
2. Mettez à jour les dépendances vulnérables
3. Configurez le monitoring pour un suivi continu
4. Intégrez les scans dans votre CI/CD

---
*Généré par le script Snyk de l'environnement Laravel*
EOF

    log "SUCCESS" "📄 Rapport de synthèse généré: $summary_file"
}

# Fonction d'affichage de l'aide
show_help() {
    cat << EOF
🛡️ Script de scan de sécurité Snyk pour Laravel

USAGE:
    ./scripts/security/snyk-scan.sh [OPTIONS]

OPTIONS:
    -h, --help              Afficher cette aide
    -v, --verbose           Mode verbeux (debug)
    --config                Afficher la configuration active
    --php-only              Scanner uniquement les dépendances PHP
    --node-only             Scanner uniquement les dépendances Node.js
    --docker-only           Scanner uniquement les images Docker
    --no-monitor            Désactiver le monitoring pour cette exécution
    --fail-on-issues        Faire échouer le script en cas de vulnérabilités
    --severity LEVEL        Seuil de sévérité (low|medium|high|critical)
    --report-dir DIR        Répertoire des rapports (défaut: reports/security)

EXAMPLES:
    # Scan complet avec configuration .env
    ./scripts/security/snyk-scan.sh

    # Scan des dépendances PHP uniquement
    ./scripts/security/snyk-scan.sh --php-only

    # Scan avec seuil critique seulement
    ./scripts/security/snyk-scan.sh --severity critical

    # Scan sans monitoring
    ./scripts/security/snyk-scan.sh --no-monitor

CONFIGURATION:
    Le script utilise les variables du fichier .env:
    - SNYK_TOKEN: Token d'authentification Snyk
    - SNYK_SEVERITY_THRESHOLD: Seuil de sévérité (défaut: high)
    - SNYK_FAIL_ON_ISSUES: Échec en cas de vulnérabilités (défaut: false)
    - SNYK_MONITOR_ENABLED: Activation du monitoring (défaut: true)

    Obtenez votre token sur: https://app.snyk.io/account

EOF
}

# Fonction principale
main() {
    local php_only=false
    local node_only=false
    local docker_only=false
    local no_monitor=false
    local show_config_only=false

    # Parse des arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --config)
                show_config_only=true
                shift
                ;;
            --php-only)
                php_only=true
                shift
                ;;
            --node-only)
                node_only=true
                shift
                ;;
            --docker-only)
                docker_only=true
                shift
                ;;
            --no-monitor)
                no_monitor=true
                shift
                ;;
            --fail-on-issues)
                SNYK_FAIL_ON_ISSUES=true
                shift
                ;;
            --severity)
                SNYK_SEVERITY_THRESHOLD="$2"
                shift 2
                ;;
            --report-dir)
                REPORTS_DIR="$2"
                shift 2
                ;;
            *)
                log "ERROR" "Option inconnue: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Initialisation
    log "INFO" "🛡️ Démarrage du scan de sécurité Snyk"

    load_env_config

    if [ "$show_config_only" = "true" ]; then
        show_config
        exit 0
    fi

    show_config
    check_prerequisites
    prepare_reports_dir

    # Exécution des scans selon les options
    local scan_count=0
    local failed_scans=0

    if [ "$docker_only" = "true" ]; then
        scan_docker_images || ((failed_scans++))
        ((scan_count++))
    elif [ "$php_only" = "true" ]; then
        scan_composer_dependencies || ((failed_scans++))
        ((scan_count++))
    elif [ "$node_only" = "true" ]; then
        scan_npm_dependencies || ((failed_scans++))
        ((scan_count++))
    else
        # Scan complet
        scan_composer_dependencies || ((failed_scans++))
        ((scan_count++))

        scan_npm_dependencies || ((failed_scans++))
        ((scan_count++))

        scan_docker_images || ((failed_scans++))
        ((scan_count++))
    fi

    # Monitoring (sauf si désactivé)
    if [ "$no_monitor" != "true" ] && [ "$docker_only" != "true" ]; then
        enable_monitoring
    fi

    # Génération du rapport de synthèse
    generate_summary_report

    # Résumé final
    log "INFO" "🎯 Scan terminé - $scan_count scans exécutés"

    if [ $failed_scans -gt 0 ]; then
        log "WARN" "⚠️ $failed_scans scan(s) avec vulnérabilités détectées"
        log "INFO" "📄 Consultez les rapports dans: $REPORTS_DIR"

        if [ "$SNYK_FAIL_ON_ISSUES" = "true" ]; then
            log "ERROR" "Échec du script (SNYK_FAIL_ON_ISSUES=true)"
            exit 1
        fi
    else
        log "SUCCESS" "✅ Aucune vulnérabilité critique détectée"
    fi

    log "INFO" "🔗 Consultez vos projets sur: https://app.snyk.io/projects"
}

# Exécuter le script si appelé directement
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi