#!/bin/bash

# =============================================================================
# MODULE D'INSTALLATION DES PACKAGES DE DÉVELOPPEMENT
# =============================================================================
#
# Ce module installe les packages Laravel pour le développement,
# incluant les outils de debug, test, IDE helpers, etc.
#
# =============================================================================

set -e

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/laravel.sh"

init_logging "40-packages-dev"

# NOTE: Les packages de développement sont maintenant lus depuis config/installer.yml
# via get_packages_from_config() (CONFORMÉMENT AU PROMPT)

main() {
    local laravel_dir="${1:-$(detect_working_directory)}"
    local start_time=$(date +%s)
    
    log_separator "INSTALLATION PACKAGES DÉVELOPPEMENT"
    log_info "🛠️ Installation des packages de développement dans: $laravel_dir"
    
    cd "$laravel_dir"
    
    if ! is_laravel_project "$laravel_dir"; then
        log_fatal "Pas un projet Laravel: $laravel_dir"
    fi
    
    # Lire les packages depuis config/installer.yml (CONFORMÉMENT AU PROMPT)
    log_info "📋 Lecture des packages de développement depuis config/installer.yml..."
    
    # Obtenir la liste des packages depuis le YAML
    local packages_list
    if ! packages_list=$(get_packages_from_config "development"); then
        log_error "Impossible de lire les packages de développement depuis la configuration"
        return 1
    fi
    
    # Installer chaque package
    while IFS= read -r package_name; do
        # Ignorer les lignes vides
        [ -z "$package_name" ] && continue
        
        # Vérifier la compatibilité Laravel générale
        if ! is_package_laravel_compatible "$package_name" "development"; then
            local max_laravel=$(get_package_max_laravel_version "$package_name" "development")
            local current_laravel=$(get_laravel_version | cut -d. -f1)
            log_warn "⚠️ $package_name ignoré - Laravel <= $max_laravel requis, vous avez Laravel $current_laravel"
            continue
        fi
        
        # Vérifier la compatibilité PHP
        if ! is_package_php_compatible "$package_name" "development"; then
            local required_php=$(get_package_php_version "$package_name" "development")
            local current_php=$(get_php_version)
            log_warn "⚠️ $package_name ignoré - PHP $required_php requis, vous avez $current_php"
            continue
        fi
        
        # Obtenir la version depuis la configuration
        local version=$(get_package_version "$package_name" "development")
        
        # Vérifier si le package est requis
        if is_package_required "$package_name" "development"; then
            log_debug "📦 Package requis: $package_name:$version"
        else
            log_debug "📦 Package optionnel: $package_name:$version"
        fi
        
        if ! is_package_installed "$package_name"; then
            log_info "Installation de $package_name:$version..."
            if install_composer_package "$package_name" "$version" "require-dev"; then
                log_success "✅ $package_name installé"
            else
                if is_package_required "$package_name" "development"; then
                    log_error "❌ Échec installation package requis: $package_name"
                else
                    log_warn "⚠️ Échec installation package optionnel: $package_name"
                fi
            fi
        else
            log_debug "✓ $package_name déjà installé"
        fi
    done <<< "$packages_list"
    
    # Générer les IDE helpers
    log_info "Génération des IDE helpers..."
    php artisan ide-helper:generate 2>&1 | tee -a "$LOG_FILE" || log_debug "IDE helper:generate ignoré"
    php artisan ide-helper:models --nowrite 2>&1 | tee -a "$LOG_FILE" || log_debug "IDE helper:models ignoré"
    
    local duration=$(calculate_duration $start_time)
    log_success "✅ Packages de développement installés en $duration"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi