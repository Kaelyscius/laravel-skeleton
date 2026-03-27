#!/bin/bash

# =============================================================================
# MODULE D'INSTALLATION DES PACKAGES DE PRODUCTION
# =============================================================================
#
# Ce module installe les packages Laravel nécessaires en production,
# incluant les packages de base, optimisation, monitoring, etc.
#
# Utilisation:
#   ./30-packages-prod.sh [répertoire_laravel]
#
# =============================================================================

set -e

# Charger les dépendances
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/laravel.sh"

# Initialiser le logging
init_logging "30-packages-prod"

# =============================================================================
# PACKAGES DE PRODUCTION
# =============================================================================

# NOTE: Les packages de production sont maintenant lus depuis config/installer.yml
# via get_packages_from_config() (CONFORMÉMENT AU PROMPT)

#
# Configurer Laravel Telescope de manière adaptative (EXACTE DE L'ORIGINAL)
#
configure_telescope() {
    if [ -f "config/telescope.php" ]; then
        log_info "🔭 Configuration de Laravel Telescope..."
        
        # Configuration adaptative selon l'environnement
        # Désactiver Telescope en production par défaut
        sed -i "s/'enabled' => env('TELESCOPE_ENABLED', true),/'enabled' => env('TELESCOPE_ENABLED', env('APP_ENV') !== 'production'),/" config/telescope.php
        
        # Forcer le driver database pour plus de stabilité
        sed -i "s/'driver' => env('TELESCOPE_DRIVER', 'database'),/'driver' => 'database',/" config/telescope.php
        
        log_success "✅ Configuration Telescope adaptée"
        log_info "   • Désactivé automatiquement en production"
        log_info "   • Driver forcé sur 'database'"
    else
        log_debug "config/telescope.php non trouvé, configuration ignorée"
    fi
}

main() {
    local laravel_dir="${1:-$(detect_working_directory)}"
    local start_time=$(date +%s)
    
    log_separator "INSTALLATION PACKAGES PRODUCTION"
    log_info "📦 Installation des packages de production dans: $laravel_dir"
    
    cd "$laravel_dir"
    
    # Vérifier que nous sommes dans un projet Laravel
    if ! is_laravel_project "$laravel_dir"; then
        log_fatal "Pas un projet Laravel: $laravel_dir"
    fi
    
    # Lire les packages depuis config/installer.yml (CONFORMÉMENT AU PROMPT)
    log_info "📋 Lecture des packages de production depuis config/installer.yml..."
    
    # Obtenir la liste des packages depuis le YAML
    local packages_list
    if ! packages_list=$(get_packages_from_config "production"); then
        log_error "Impossible de lire les packages de production depuis la configuration"
        return 1
    fi
    
    # Installer chaque package
    while IFS= read -r package_name; do
        # Ignorer les lignes vides
        [ -z "$package_name" ] && continue
        
        # Obtenir la version depuis la configuration
        local version=$(get_package_version "$package_name" "production")
        
        # Vérifier si le package est requis
        if is_package_required "$package_name" "production"; then
            log_debug "📦 Package requis: $package_name:$version"
        else
            log_debug "📦 Package optionnel: $package_name:$version"
        fi
        
        if ! is_package_installed "$package_name"; then
            log_info "Installation de $package_name:$version..."
            if install_composer_package "$package_name" "$version" "require"; then
                log_success "✅ $package_name installé"
            else
                if is_package_required "$package_name" "production"; then
                    log_error "❌ Échec installation package requis: $package_name"
                else
                    log_warn "⚠️ Échec installation package optionnel: $package_name"
                fi
            fi
        else
            log_debug "✓ $package_name déjà installé"
        fi
    done <<< "$packages_list"
    
    # Publier les configurations sélectivement pour éviter les erreurs Flysystem
    log_info "Publication des configurations des packages..."
    
    # Publication sélective des packages critiques
    # NOTE: Ne publier QUE les configs et migrations nécessaires
    # Telescope et Horizon chargent automatiquement leurs migrations depuis vendor
    local publish_packages=(
        "sanctum-config"
        "laravel-permission-migrations"
        "activitylog-migrations"
    )

    for tag in "${publish_packages[@]}"; do
        if php artisan vendor:publish --tag="$tag" --force 2>/dev/null; then
            log_debug "✓ Configuration publiée: $tag"
        else
            log_debug "Configuration $tag non trouvée ou déjà publiée"
        fi
    done
    
    # Publication générale des configs sans forcer pour éviter les conflits
    # NOTE: Ne PAS publier les migrations - Laravel les charge automatiquement depuis vendor
    if php artisan vendor:publish --tag="horizon-config" 2>/dev/null; then
        log_debug "✓ Horizon config publié"
    fi

    # Publier UNIQUEMENT la config de Telescope, PAS les migrations (évite les duplicatas)
    if php artisan vendor:publish --tag="telescope-config" 2>/dev/null; then
        log_debug "✓ Telescope config publié (sans migrations)"
    fi
    
    # Configuration spécifique de Telescope
    configure_telescope
    
    local duration=$(calculate_duration $start_time)
    log_success "✅ Packages de production installés en $duration"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi