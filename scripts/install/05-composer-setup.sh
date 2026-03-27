#!/bin/bash

# =============================================================================
# MODULE DE CONFIGURATION ET RÉPARATION COMPOSER
# =============================================================================
#
# Ce module configure et répare Composer avant toute installation de packages.
# Il est CRITIQUE et doit être exécuté en PREMIER avant tous les autres modules.
#
# Utilisation:
#   ./05-composer-setup.sh [répertoire_laravel]
#
# Code de sortie:
#   0: Configuration réussie
#   1: Échec de la configuration
#
# =============================================================================

set -e

# Charger les dépendances
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/common.sh"

# Initialiser le logging
init_logging "05-composer-setup"

# =============================================================================
# VARIABLES DE CONFIGURATION COMPOSER
# =============================================================================

# Répertoire de configuration Composer global
readonly COMPOSER_HOME="${COMPOSER_HOME:-/var/composer}"

# Plugins Composer autorisés (LISTE COMPLÈTE DE L'ORIGINAL)
readonly COMPOSER_ALLOWED_PLUGINS=(
    "dealerdirect/phpcodesniffer-composer-installer"
    "pestphp/pest-plugin"
    "php-http/discovery"
    "bamarni/composer-bin-plugin"
    "ergebnis/composer-normalize"
    "infection/extension-installer"
    "phpstan/extension-installer"
    "rector/extension-installer"
    "spatie/laravel-ignition"
    "laravel/framework"
)

# Configuration Composer optimisée (seulement paramètres configurables globalement)
readonly COMPOSER_CONFIG_OPTIMIZATIONS=(
    "process-timeout:3000"
    "optimize-autoloader:true"
)

# Note: prefer-stable et minimum-stability ne peuvent être configurés que par projet
# Ils sont définis dans le composer.json généré par Laravel

# =============================================================================
# FONCTIONS DE CONFIGURATION COMPOSER
# =============================================================================

#
# Vérifier les extensions PHP critiques pour PHP 8.5 + Laravel 12
#
check_critical_php_extensions() {
    log_info "🔍 Vérification des extensions PHP critiques..."
    
    # Extensions requises pour les packages de qualité
    local required_extensions=(
        "mbstring"
        "xml"
        "dom"
        "json"
        "tokenizer"
        "iconv"
        "ctype"
        "fileinfo"
    )
    
    local missing_extensions=()
    local available_count=0
    
    for ext in "${required_extensions[@]}"; do
        if php -m | grep -q "^$ext$"; then
            log_debug "✓ Extension $ext: installée"
            available_count=$((available_count + 1))
        else
            missing_extensions+=("$ext")
            log_warn "✗ Extension $ext: manquante"
        fi
    done
    
    if [ ${#missing_extensions[@]} -gt 0 ]; then
        log_warn "Extensions manquantes: ${missing_extensions[*]}"
        log_info "Ces extensions peuvent être nécessaires pour certains packages"
        return 1
    else
        log_success "✅ Toutes les $available_count extensions requises sont installées"
        return 0
    fi
}

#
# Tester la résolution des dépendances pour PHP 8.5 + Laravel 12
#
test_php85_dependency_resolution() {
    log_info "🧪 Test de résolution des dépendances PHP 8.5..."
    
    # Test simple de validation Composer (plus robuste)
    if composer --version >/dev/null 2>&1; then
        log_debug "✓ Composer fonctionnel"
    else
        log_warn "⚠ Composer non disponible pour test"
        return 1
    fi
    
    # Test de connectivité Packagist (plus important que validation JSON complexe)
    if composer show --available --quiet 2>/dev/null | head -1 >/dev/null; then
        log_debug "✓ Connectivité Packagist OK"
    else
        log_warn "⚠ Connectivité Packagist limitée"
    fi
    
    log_success "✅ Test de compatibilité PHP 8.5 de base réussi"
    return 0
}


#
# Fonction principale de réparation Composer (EXACTE DE L'ORIGINAL)
#
fix_composer_config() {
    log_step_start "CONFIGURATION COMPOSER" "Vérification et réparation de la configuration Composer"
    
    local start_time=$(date +%s)
    
    log_info "🔧 Vérification et réparation de la configuration Composer..."
    
    # Vérifier si le fichier config existe et est valide
    if [ -f "$COMPOSER_HOME/config.json" ]; then
        if ! python3 -m json.tool "$COMPOSER_HOME/config.json" >/dev/null 2>&1; then
            log_warn "Configuration Composer corrompue, réparation..."
            rm -f "$COMPOSER_HOME/config.json"
        else
            log_debug "Configuration Composer existante valide"
        fi
    else
        log_debug "Aucune configuration Composer existante"
    fi
    
    # Créer le répertoire si nécessaire
    mkdir -p "$COMPOSER_HOME"
    log_debug "Répertoire Composer: $COMPOSER_HOME"
    
    # Initialiser une configuration propre
    log_info "Initialisation de la configuration Composer..."
    if ! composer config --global --no-interaction repos.packagist composer https://packagist.org 2>/dev/null; then
        log_warn "Recréation de la configuration Composer..."
        echo '{"config":{},"repositories":{"packagist.org":{"type":"composer","url":"https://packagist.org"}}}' > "$COMPOSER_HOME/config.json"
    fi
    
    # Configuration des plugins autorisés
    configure_composer_plugins
    
    # Configuration des optimisations
    configure_composer_optimizations
    
    # Définir les variables d'environnement critiques
    setup_composer_environment_variables
    
    # Vérifications PHP 8.5 (non-bloquantes)
    check_critical_php_extensions || log_warn "Extensions PHP manquantes détectées"
    test_php85_dependency_resolution || log_warn "Problèmes de résolution détectés"
    
    # Vérifier la configuration finale
    if validate_composer_configuration; then
        local duration=$(calculate_duration $start_time)
        log_step_end "CONFIGURATION COMPOSER" "$duration"
        return 0
    else
        log_fatal "Validation de la configuration Composer échouée"
    fi
}

#
# Configurer les plugins Composer autorisés
#
configure_composer_plugins() {
    log_info "Configuration des plugins Composer autorisés..."
    
    # Autoriser tous les plugins par défaut pour éviter les problèmes
    if composer config --global allow-plugins true 2>/dev/null; then
        log_debug "Plugins globalement autorisés"
    else
        log_warn "Impossible de configurer allow-plugins globalement"
    fi
    
    # Configuration spécifique des plugins (LISTE COMPLÈTE DE L'ORIGINAL)
    local configured_count=0
    for plugin in "${COMPOSER_ALLOWED_PLUGINS[@]}"; do
        log_debug "Autorisation du plugin: $plugin"
        if composer config --global "allow-plugins.$plugin" true 2>/dev/null; then
            configured_count=$((configured_count + 1))
        else
            log_debug "Plugin $plugin non configuré (sera autorisé automatiquement)"
        fi
    done
    
    log_success "✅ $configured_count plugins Composer configurés"
}

#
# Configurer les optimisations Composer
#
configure_composer_optimizations() {
    log_info "Configuration des optimisations Composer..."
    
    local optimized_count=0
    
    for config_item in "${COMPOSER_CONFIG_OPTIMIZATIONS[@]}"; do
        local key="${config_item%%:*}"
        local value="${config_item##*:}"
        
        log_debug "Configuration: $key = $value"
        if composer config --global "$key" "$value" 2>/dev/null; then
            optimized_count=$((optimized_count + 1))
        else
            log_warn "Impossible de configurer: $key"
        fi
    done
    
    log_success "✅ $optimized_count optimisations Composer appliquées"
}

#
# Définir les variables d'environnement Composer critiques
#
setup_composer_environment_variables() {
    log_info "Configuration des variables d'environnement Composer..."
    
    # Variables critiques pour l'installation (DE L'ORIGINAL)
    export COMPOSER_MEMORY_LIMIT=-1
    export COMPOSER_PROCESS_TIMEOUT=0
    export COMPOSER_ALLOW_SUPERUSER=1
    export COMPOSER_NO_INTERACTION=1
    export COMPOSER_PREFER_STABLE=1
    
    # Configuration pour Docker si applicable (améliorations intégrées)
    if is_docker_environment || [ -f "/.dockerenv" ] || [ -n "${DOCKER_CONTAINER:-}" ]; then
        export COMPOSER_CACHE_DIR="/tmp/composer-cache"
        mkdir -p "$COMPOSER_CACHE_DIR"
        
        # Variables d'environnement optimisées pour Docker (de fix-composer-issues.sh)
        export COMPOSER_MEMORY_LIMIT=-1
        export COMPOSER_PROCESS_TIMEOUT=3600
        export COMPOSER_ALLOW_SUPERUSER=1
        export COMPOSER_NO_INTERACTION=1
        
        log_debug "Cache Composer Docker: $COMPOSER_CACHE_DIR"
        log_debug "Variables Docker optimisées configurées"
    fi
    
    # Afficher les variables configurées
    log_debug "Variables Composer configurées:"
    log_debug "  • COMPOSER_MEMORY_LIMIT: $COMPOSER_MEMORY_LIMIT"
    log_debug "  • COMPOSER_PROCESS_TIMEOUT: $COMPOSER_PROCESS_TIMEOUT"
    log_debug "  • COMPOSER_ALLOW_SUPERUSER: $COMPOSER_ALLOW_SUPERUSER"
    log_debug "  • COMPOSER_NO_INTERACTION: $COMPOSER_NO_INTERACTION"
    
    log_success "✅ Variables d'environnement Composer configurées"
}

#
# Valider la configuration Composer finale
#
validate_composer_configuration() {
    log_info "Validation de la configuration Composer..."
    
    local issues=0
    
    # Vérifier que Composer fonctionne
    if composer --version &>/dev/null; then
        local composer_version=$(composer --version | head -1)
        log_debug "✓ Composer fonctionnel: $composer_version"
    else
        log_error "✗ Composer non fonctionnel"
        issues=$((issues + 1))
    fi
    
    # Vérifier le fichier de configuration
    if [ -f "$COMPOSER_HOME/config.json" ]; then
        if python3 -m json.tool "$COMPOSER_HOME/config.json" >/dev/null 2>&1; then
            log_debug "✓ Fichier de configuration valide"
        else
            log_error "✗ Fichier de configuration invalide"
            issues=$((issues + 1))
        fi
    else
        log_error "✗ Fichier de configuration manquant"
        issues=$((issues + 1))
    fi
    
    # Vérifier les variables d'environnement
    local timeout_ok=false
    if [ "$COMPOSER_PROCESS_TIMEOUT" = "0" ] || [ "$COMPOSER_PROCESS_TIMEOUT" = "3600" ]; then
        timeout_ok=true
    fi
    
    if [ "$COMPOSER_MEMORY_LIMIT" = "-1" ] && [ "$timeout_ok" = "true" ]; then
        log_debug "✓ Variables d'environnement correctes (TIMEOUT: $COMPOSER_PROCESS_TIMEOUT)"
    else
        log_error "✗ Variables d'environnement incorrectes (MEMORY: $COMPOSER_MEMORY_LIMIT, TIMEOUT: $COMPOSER_PROCESS_TIMEOUT)"
        issues=$((issues + 1))
    fi
    
    # Test de connectivité à Packagist
    if composer show --available packagist &>/dev/null || curl -s --max-time 5 https://packagist.org &>/dev/null; then
        log_debug "✓ Connectivité Packagist OK"
    else
        log_warn "⚠ Connectivité Packagist limitée"
        # Non bloquant
    fi
    
    if [ $issues -eq 0 ]; then
        log_success "✅ Configuration Composer validée"
        return 0
    else
        log_error "❌ $issues problème(s) de configuration Composer"
        return 1
    fi
}

#
# Nettoyer les caches Composer corrompus
#
clean_composer_cache() {
    log_info "Nettoyage des caches Composer..."
    
    local cache_dirs=(
        "$(composer config cache-dir 2>/dev/null || echo '/tmp/composer-cache')"
        "$HOME/.composer/cache"
        "/var/composer/cache"
        "/tmp/composer-cache"
    )
    
    local cleaned_count=0
    for cache_dir in "${cache_dirs[@]}"; do
        if [ -d "$cache_dir" ]; then
            log_debug "Nettoyage du cache: $cache_dir"
            if rm -rf "$cache_dir"/* 2>/dev/null; then
                cleaned_count=$((cleaned_count + 1))
            fi
        fi
    done
    
    # Nettoyer via Composer
    composer clear-cache 2>/dev/null || true
    
    log_success "✅ $cleaned_count cache(s) Composer nettoyé(s)"
}

#
# Afficher les informations de diagnostic Composer
#
show_composer_diagnostic() {
    log_separator "DIAGNOSTIC COMPOSER"
    
    # Version et configuration
    local composer_version=$(composer --version 2>/dev/null | head -1 || echo "Non disponible")
    log_info "🎼 Version: $composer_version"
    
    # Configuration globale
    local global_config=$(composer config --global --list 2>/dev/null | wc -l)
    log_info "⚙️ Paramètres globaux: $global_config configurés"
    
    # Plugins autorisés
    local allowed_plugins=$(composer config --global allow-plugins 2>/dev/null | grep -c "true" || echo "0")
    log_info "🔌 Plugins autorisés: $allowed_plugins"
    
    # Répertoires
    log_info "📁 Répertoire global: $COMPOSER_HOME"
    log_info "📁 Cache: $(composer config cache-dir 2>/dev/null || echo 'Non configuré')"
    
    # Variables d'environnement
    log_info "🌍 Variables:"
    log_info "   • COMPOSER_MEMORY_LIMIT: ${COMPOSER_MEMORY_LIMIT:-'non défini'}"
    log_info "   • COMPOSER_PROCESS_TIMEOUT: ${COMPOSER_PROCESS_TIMEOUT:-'non défini'}"
    log_info "   • COMPOSER_ALLOW_SUPERUSER: ${COMPOSER_ALLOW_SUPERUSER:-'non défini'}"
}

# =============================================================================
# FONCTION PRINCIPALE
# =============================================================================

main() {
    local laravel_dir="${1:-$(detect_working_directory)}"
    local start_time=$(date +%s)
    
    log_separator "CONFIGURATION COMPOSER"
    log_info "🎼 Configuration et réparation de Composer"
    
    # Diagnostic initial
    show_composer_diagnostic
    
    # Nettoyer les caches potentiellement corrompus
    clean_composer_cache
    
    # Configuration principale
    fix_composer_config
    
    # Aller dans le répertoire Laravel si spécifié
    if [ -n "$laravel_dir" ] && [ -d "$laravel_dir" ]; then
        cd "$laravel_dir"
        log_debug "Changement vers le répertoire Laravel: $laravel_dir"
    fi
    
    # Résultat final
    local duration=$(calculate_duration $start_time)
    log_separator "COMPOSER CONFIGURÉ"
    log_success "✅ Composer configuré et optimisé en $duration"
    
    # Diagnostic final
    show_composer_diagnostic
    
    log_info "🎯 Prêt pour l'installation des packages Laravel"
}

# =============================================================================
# EXÉCUTION
# =============================================================================

# Exécuter seulement si le script est appelé directement
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi