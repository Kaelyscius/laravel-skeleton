#!/bin/bash

# =============================================================================
# MODULE DE VÉRIFICATION DES PRÉREQUIS
# =============================================================================
#
# Ce module vérifie que tous les prérequis sont satisfaits avant de commencer
# l'installation de Laravel. Il contrôle les outils système, versions,
# extensions PHP, et la connectivité réseau.
#
# Utilisation:
#   ./00-prerequisites.sh
#
# Code de sortie:
#   0: Tous les prérequis sont satisfaits
#   1: Des prérequis manquent ou sont invalides
#
# =============================================================================

set -e

# Charger les dépendances
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/common.sh"

# Initialiser le logging
init_logging "00-prerequisites"

# =============================================================================
# VARIABLES DE CONFIGURATION
# =============================================================================

# Versions minimales requises
# PHP 8.3 minimum : requis par pest ^4, phpinsights ^2.14, symplify/ecs ^13, spatie/laravel-csp ^3
readonly MIN_PHP_VERSION="8.3"
readonly MIN_COMPOSER_VERSION="2.0"
# Node 22 minimum : Node 18 est EOL depuis avril 2025 ; Docker utilise Node 24
readonly MIN_NODE_VERSION="22.0"

# Outils système requis
readonly REQUIRED_TOOLS=(
    "composer"
    "php"
    "python3"
    "grep"
    "sed"
    "curl"
    "git"
)

# Extensions PHP requises
readonly REQUIRED_PHP_EXTENSIONS=(
    "openssl"
    "pdo"
    "mbstring"
    "tokenizer"
    "xml"
    "ctype"
    "json"
    "curl"
    "zip"
    "bcmath"
    "gd"
    "redis"
)

# Extensions PHP optionnelles (recommandées)
readonly OPTIONAL_PHP_EXTENSIONS=(
    "imagick"
    "intl"
    "xdebug"
)

# =============================================================================
# FONCTIONS DE VÉRIFICATION SYSTÈME
# =============================================================================

#
# Vérifier les outils système requis
#
check_system_tools() {
    log_step_start "OUTILS SYSTÈME" "Vérification des outils système requis"
    
    local missing_tools=()
    local start_time=$(date +%s)
    
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if command -v "$tool" &> /dev/null; then
            log_debug "✓ $tool: trouvé"
        else
            missing_tools+=("$tool")
            log_error "✗ $tool: manquant"
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Outils manquants: ${missing_tools[*]}"
        log_error "Installez les outils manquants avant de continuer"
        return 1
    fi
    
    local duration=$(calculate_duration $start_time)
    log_step_end "OUTILS SYSTÈME" "$duration"
    return 0
}

#
# Vérifier les versions des outils
#
check_tool_versions() {
    log_step_start "VERSIONS" "Vérification des versions des outils"
    
    local start_time=$(date +%s)
    local has_errors=false
    
    # Vérifier la version de PHP
    local php_version=$(get_php_version)
    log_debug "Version PHP détectée: $php_version"
    
    if version_compare "$php_version" "$MIN_PHP_VERSION"; then
        log_success "✓ PHP $php_version (>= $MIN_PHP_VERSION)"
    else
        log_error "✗ PHP $php_version < $MIN_PHP_VERSION (minimum requis)"
        has_errors=true
    fi
    
    # Vérifier la version de Composer
    local composer_version=$(composer --version 2>/dev/null | sed 's/.*version \([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/' | head -1)
    log_debug "Version Composer détectée: $composer_version"
    
    if version_compare "$composer_version" "$MIN_COMPOSER_VERSION"; then
        log_success "✓ Composer $composer_version (>= $MIN_COMPOSER_VERSION)"
    else
        log_error "✗ Composer $composer_version < $MIN_COMPOSER_VERSION (minimum requis)"
        has_errors=true
    fi
    
    # Vérifier la version de Node.js si disponible
    if command -v node &> /dev/null; then
        local node_version=$(node --version 2>/dev/null | sed 's/v\([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/')
        log_debug "Version Node.js détectée: $node_version"
        
        if version_compare "$node_version" "$MIN_NODE_VERSION"; then
            log_success "✓ Node.js $node_version (>= $MIN_NODE_VERSION)"
        else
            log_warn "⚠ Node.js $node_version < $MIN_NODE_VERSION (recommandé pour le frontend)"
        fi
    else
        log_warn "⚠ Node.js non disponible (requis pour le développement frontend)"
    fi
    
    # Vérifier Git
    if command -v git &> /dev/null; then
        local git_version=$(git --version | sed 's/git version \([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/')
        log_debug "Version Git détectée: $git_version"
        log_success "✓ Git $git_version"
    fi
    
    local duration=$(calculate_duration $start_time)
    
    if [ "$has_errors" = true ]; then
        log_error "Des versions d'outils ne respectent pas les prérequis"
        return 1
    fi
    
    log_step_end "VERSIONS" "$duration"
    return 0
}

#
# Vérifier les extensions PHP
#
check_php_extensions() {
    log_step_start "EXTENSIONS PHP" "Vérification des extensions PHP"
    
    local start_time=$(date +%s)
    local missing_required=()
    local missing_optional=()
    
    # Vérifier les extensions requises
    for ext in "${REQUIRED_PHP_EXTENSIONS[@]}"; do
        if php -m | grep -qi "^$ext\$"; then
            log_debug "✓ $ext: disponible"
        else
            missing_required+=("$ext")
            log_error "✗ $ext: manquant (requis)"
        fi
    done
    
    # Vérifier les extensions optionnelles
    for ext in "${OPTIONAL_PHP_EXTENSIONS[@]}"; do
        if php -m | grep -qi "^$ext\$"; then
            log_debug "✓ $ext: disponible (optionnel)"
        else
            missing_optional+=("$ext")
            log_debug "⚠ $ext: manquant (optionnel)"
        fi
    done
    
    # Afficher les résultats
    if [ ${#missing_required[@]} -ne 0 ]; then
        log_error "Extensions PHP requises manquantes: ${missing_required[*]}"
        log_error "Installez ces extensions avant de continuer"
        return 1
    fi
    
    if [ ${#missing_optional[@]} -ne 0 ]; then
        log_warn "Extensions PHP optionnelles manquantes: ${missing_optional[*]}"
        log_warn "Ces extensions améliorent les fonctionnalités mais ne sont pas critiques"
    fi
    
    local duration=$(calculate_duration $start_time)
    log_step_end "EXTENSIONS PHP" "$duration"
    return 0
}

#
# Vérifier l'environnement Docker
#
check_docker_environment() {
    log_step_start "ENVIRONNEMENT DOCKER" "Vérification de l'environnement Docker"
    
    local start_time=$(date +%s)
    
    if is_docker_environment; then
        log_success "✓ Environnement Docker détecté"
        
        # Vérifier les variables d'environnement Docker essentielles
        local docker_vars=("DOCKER_CONTAINER" "DB_HOST" "DB_DATABASE" "DB_USERNAME")
        local missing_vars=()
        
        for var in "${docker_vars[@]}"; do
            if [ -n "${!var:-}" ]; then
                log_debug "✓ Variable $var définie"
            else
                missing_vars+=("$var")
            fi
        done
        
        if [ ${#missing_vars[@]} -ne 0 ]; then
            log_warn "Variables Docker manquantes: ${missing_vars[*]}"
        fi
        
        # Vérifier l'espace disque disponible
        local available_space=$(df -h /var/www/html | awk 'NR==2 {print $4}' | sed 's/[^0-9.]//g')
        log_debug "Espace disque disponible: ${available_space}GB"
        
        if [ "${available_space%.*}" -lt 1 ]; then
            log_warn "⚠ Espace disque faible: ${available_space}GB"
        else
            log_success "✓ Espace disque suffisant: ${available_space}GB"
        fi
    else
        log_info "Environnement non-Docker détecté"
    fi
    
    local duration=$(calculate_duration $start_time)
    log_step_end "ENVIRONNEMENT DOCKER" "$duration"
    return 0
}

#
# Vérifier la connectivité réseau et les dépôts
#
check_network_connectivity() {
    log_step_start "CONNECTIVITÉ" "Vérification de la connectivité réseau"
    
    local start_time=$(date +%s)
    local repositories=(
        "packagist.org"
        "github.com"
        "raw.githubusercontent.com"
    )
    
    for repo in "${repositories[@]}"; do
        if curl -s --max-time 10 --head "https://$repo" > /dev/null 2>&1; then
            log_debug "✓ $repo: accessible"
        else
            log_warn "⚠ $repo: non accessible (pourrait affecter l'installation de packages)"
        fi
    done
    
    # Tester la résolution DNS
    if nslookup google.com > /dev/null 2>&1; then
        log_debug "✓ Résolution DNS: fonctionnelle"
    else
        log_warn "⚠ Résolution DNS: problématique"
    fi
    
    local duration=$(calculate_duration $start_time)
    log_step_end "CONNECTIVITÉ" "$duration"
    return 0
}

#
# Vérifier les permissions de fichier
#
check_file_permissions() {
    log_step_start "PERMISSIONS" "Vérification des permissions de fichier"
    
    local start_time=$(date +%s)
    local work_dir=$(detect_working_directory)
    
    # Vérifier les permissions d'écriture dans le répertoire de travail
    if [ -w "$work_dir" ]; then
        log_debug "✓ Permissions d'écriture: $work_dir"
    else
        log_error "✗ Permissions d'écriture manquantes: $work_dir"
        return 1
    fi
    
    # Vérifier les répertoires critiques s'ils existent
    local critical_dirs=(
        "$work_dir/storage"
        "$work_dir/bootstrap/cache"
        "$work_dir/public"
    )
    
    for dir in "${critical_dirs[@]}"; do
        if [ -d "$dir" ]; then
            if [ -w "$dir" ]; then
                log_debug "✓ Permissions d'écriture: $dir"
            else
                log_error "✗ Permissions d'écriture manquantes: $dir"
                return 1
            fi
        fi
    done
    
    local duration=$(calculate_duration $start_time)
    log_step_end "PERMISSIONS" "$duration"
    return 0
}

# =============================================================================
# FONCTIONS UTILITAIRES
# =============================================================================

# NOTE: La fonction version_compare() est maintenant disponible dans common.sh

#
# Afficher un récapitulatif des prérequis
#
show_prerequisites_summary() {
    log_separator "RÉCAPITULATIF DES PRÉREQUIS"
    
    log_info "🔧 Outils système: ${#REQUIRED_TOOLS[@]} requis"
    log_info "🐘 Extensions PHP: ${#REQUIRED_PHP_EXTENSIONS[@]} requises, ${#OPTIONAL_PHP_EXTENSIONS[@]} optionnelles"
    log_info "📋 Versions minimales:"
    log_info "   • PHP >= $MIN_PHP_VERSION"
    log_info "   • Composer >= $MIN_COMPOSER_VERSION"
    log_info "   • Node.js >= $MIN_NODE_VERSION (recommandé)"
}

# =============================================================================
# FONCTION PRINCIPALE
# =============================================================================

main() {
    local start_time=$(date +%s)
    local has_errors=false
    
    log_separator "VÉRIFICATION DES PRÉREQUIS"
    log_info "🔍 Début de la vérification des prérequis pour Laravel..."
    
    # Afficher le récapitulatif
    show_prerequisites_summary
    
    # Exécuter toutes les vérifications
    if ! check_system_tools; then
        has_errors=true
    fi
    
    if ! check_tool_versions; then
        has_errors=true
    fi
    
    if ! check_php_extensions; then
        has_errors=true
    fi
    
    check_docker_environment || true  # Non bloquant
    check_network_connectivity || true  # Non bloquant
    
    if ! check_file_permissions; then
        has_errors=true
    fi
    
    # Résultat final
    local duration=$(calculate_duration $start_time)
    
    if [ "$has_errors" = true ]; then
        log_error "❌ Vérification des prérequis échouée en $duration"
        log_error "Corrigez les erreurs ci-dessus avant de continuer"
        log_error_summary
        return 1
    else
        log_success "✅ Tous les prérequis sont satisfaits en $duration"
        log_info "🚀 Prêt pour l'installation de Laravel !"
        return 0
    fi
}

# =============================================================================
# EXÉCUTION
# =============================================================================

# Exécuter seulement si le script est appelé directement
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi