#!/bin/bash

# =============================================================================
# MODULE DE CONFIGURATION NIGHTWATCH
# =============================================================================
#
# Ce module configure Laravel Nightwatch pour le monitoring applicatif
#
# =============================================================================

set -e

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/laravel.sh"

init_logging "60-nightwatch"

main() {
    local laravel_dir="${1:-$(detect_working_directory)}"
    local start_time=$(date +%s)
    
    log_separator "CONFIGURATION NIGHTWATCH"
    log_info "🌙 Configuration de Nightwatch dans: $laravel_dir"
    
    cd "$laravel_dir"
    
    if ! is_laravel_project "$laravel_dir"; then
        log_fatal "Pas un projet Laravel: $laravel_dir"
    fi
    
    # Installation du package Nightwatch si disponible
    if ! is_package_installed "laravel/nightwatch"; then
        log_info "Installation de Laravel Nightwatch..."
        if install_composer_package "laravel/nightwatch" "*" "require"; then
            log_success "✅ Nightwatch installé"
        else
            log_warn "❌ Nightwatch non disponible - ignoré"
            local duration=$(calculate_duration $start_time)
            log_success "✅ Nightwatch ignoré en $duration"
            return 0
        fi
    else
        log_debug "✓ Nightwatch déjà installé"
    fi
    
    # ⭐ ÉTAPE CRITIQUE : Configuration et démarrage automatique Nightwatch
    if is_package_installed "laravel/nightwatch"; then
        local current_token=$(grep "^NIGHTWATCH_TOKEN=" .env 2>/dev/null | cut -d'=' -f2- | sed 's/^["'\'']//' | sed 's/["'\'']$//' | xargs)
        
        log_info "🌙 Configuration de Nightwatch..."
        
        # Publier la configuration
        php artisan vendor:publish --provider="Laravel\\Nightwatch\\NightwatchServiceProvider" --tag=config --force 2>/dev/null || true
        
        if [ -n "$current_token" ] && [ "$current_token" != "\${NIGHTWATCH_TOKEN}" ] && [ "$current_token" != "" ]; then
            log_success "✅ Token Nightwatch configuré: ${current_token:0:10}..."
            
            # Arrêter un éventuel agent existant
            if [ -f "nightwatch.pid" ]; then
                local old_pid=$(cat nightwatch.pid)
                if kill -0 "$old_pid" 2>/dev/null; then
                    log_info "Arrêt de l'ancien agent (PID: $old_pid)..."
                    kill "$old_pid" 2>/dev/null || true
                fi
                rm -f nightwatch.pid
            fi
            
            # Démarrer l'agent en arrière-plan
            if php artisan list 2>/dev/null | grep -q "nightwatch:agent"; then
                log_info "Démarrage de l'agent Nightwatch en arrière-plan..."
                nohup php artisan nightwatch:agent > nightwatch.log 2>&1 &
                local nightwatch_pid=$!
                echo $nightwatch_pid > nightwatch.pid
                
                # Vérifier que l'agent a bien démarré
                sleep 2
                if kill -0 $nightwatch_pid 2>/dev/null; then
                    log_success "🎉 Agent Nightwatch démarré avec succès !"
                    log_info "  • PID: $nightwatch_pid"
                    log_info "  • Logs: tail -f nightwatch.log"
                    log_info "  • Arrêter: kill \$(cat nightwatch.pid)"
                else
                    log_warn "⚠️ L'agent semble s'être arrêté, consultez nightwatch.log"
                fi
            else
                log_error "❌ Commande nightwatch:agent non disponible"
                log_info "Vérifiez l'installation avec: php artisan list | grep nightwatch"
            fi
        else
            log_warn "⚠️ Token Nightwatch non configuré"
            log_info "L'agent ne peut pas démarrer sans token valide"
            log_info "Vérifiez NIGHTWATCH_TOKEN dans votre .env racine"
        fi
    else
        log_info "Laravel Nightwatch non installé"
    fi
    
    local duration=$(calculate_duration $start_time)
    log_success "✅ Nightwatch configuré en $duration"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi