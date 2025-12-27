#!/bin/bash

# =============================================================================
# ORCHESTRATEUR PRINCIPAL D'INSTALLATION LARAVEL
# =============================================================================
#
# Ce script orchestre l'installation complète de Laravel en exécutant
# séquentiellement tous les modules d'installation. Il gère les erreurs,
# le rollback et fournit un rapport détaillé de l'installation.
#
# Utilisation:
#   ./install.sh [options] [répertoire_cible]
#
# Options:
#   -h, --help          Afficher l'aide
#   -v, --verbose       Mode verbeux (DEBUG=true)
#   -q, --quiet         Mode silencieux
#   --skip-prereq       Ignorer la vérification des prérequis
#   --only MODULE       Exécuter seulement un module spécifique
#   --resume-from MODULE Reprendre depuis un module spécifique
#   --dry-run           Simulation sans exécution réelle
#
# Code de sortie:
#   0: Installation réussie
#   1: Erreur lors de l'installation
#   2: Erreur de paramètres
#
# =============================================================================

set -e

# Charger les dépendances
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/common.sh"

# =============================================================================
# VARIABLES DE CONFIGURATION
# =============================================================================

# Modules d'installation dans l'ordre d'exécution
readonly INSTALL_MODULES=(
    "00-prerequisites:Vérification des prérequis"
    "05-composer-setup:Configuration et réparation Composer"
    "10-laravel-core:Installation du coeur Laravel"
    "20-database:Configuration de la base de données"
    "30-packages-prod:Installation des packages de production"
    "35-configure-spatie-packages:Configuration des packages Spatie"
    "40-packages-dev:Installation des packages de développement"
    "45-configure-pest:Configuration de Pest et plugin Drift"
    "50-quality-tools:Configuration des outils qualité"
    "60-nightwatch:Configuration de Nightwatch"
    "99-finalize:Finalisation et optimisation"
)

# Variables globales
SKIP_PREREQUISITES=false
ONLY_MODULE=""
RESUME_FROM=""
DRY_RUN=false
TARGET_DIR=""
INSTALLATION_ID="$(date +%Y%m%d-%H%M%S)"

# =============================================================================
# FONCTIONS D'AIDE
# =============================================================================

show_help() {
    cat << EOF
ORCHESTRATEUR D'INSTALLATION LARAVEL

Ce script installe et configure un projet Laravel complet avec tous
les outils de développement et de qualité.

UTILISATION:
    $(basename "$0") [options] [répertoire_cible]

OPTIONS:
    -h, --help          Afficher cette aide
    -v, --verbose       Mode verbeux avec logs détaillés
    -q, --quiet         Mode silencieux (erreurs uniquement)
    --skip-prereq       Ignorer la vérification des prérequis
    --only MODULE       Exécuter seulement un module spécifique
    --resume-from MODULE Reprendre l'installation depuis un module
    --dry-run           Simulation sans exécution réelle
    --list-modules      Lister les modules disponibles

MODULES DISPONIBLES:
$(for module in "${INSTALL_MODULES[@]}"; do
    local name="${module%%:*}"
    local desc="${module##*:}"
    printf "    %-20s %s\n" "$name" "$desc"
done)

EXEMPLES:
    $(basename "$0")                          # Installation complète
    $(basename "$0") /var/www/html/app        # Installation dans un répertoire spécifique
    $(basename "$0") --only 10-laravel-core   # Installer seulement Laravel
    $(basename "$0") --resume-from 30-packages-prod # Reprendre à partir des packages
    $(basename "$0") --dry-run                # Simulation
    $(basename "$0") --verbose                # Mode verbeux

ENVIRONNEMENT:
    DEBUG=true          Active le mode debug
    LOG_LEVEL=INFO      Niveau de log (DEBUG|INFO|WARN|ERROR)
    QUIET=true          Mode silencieux

FICHIERS:
    Le fichier de log est créé dans /tmp/laravel-install-YYYYMMDD-HHMMSS.log

CODES DE SORTIE:
    0    Installation réussie
    1    Erreur lors de l'installation
    2    Erreur de paramètres ou utilisation

EOF
}

list_modules() {
    log_separator "MODULES D'INSTALLATION DISPONIBLES"
    
    for module in "${INSTALL_MODULES[@]}"; do
        local name="${module%%:*}"
        local desc="${module##*:}"
        local module_file="$SCRIPT_DIR/install/$name.sh"
        
        if [ -f "$module_file" ]; then
            local status="✅ Disponible"
        else
            local status="❌ Manquant"
        fi
        
        printf "%-20s %-50s %s\n" "$name" "$desc" "$status"
    done
}

# =============================================================================
# FONCTIONS DE GESTION DES PARAMÈTRES
# =============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                export DEBUG=true
                export LOG_LEVEL=DEBUG
                shift
                ;;
            -q|--quiet)
                export QUIET=true
                export LOG_LEVEL=ERROR
                shift
                ;;
            --skip-prereq)
                SKIP_PREREQUISITES=true
                shift
                ;;
            --only)
                ONLY_MODULE="$2"
                if [ -z "$ONLY_MODULE" ]; then
                    log_fatal "Module requis pour --only"
                fi
                shift 2
                ;;
            --resume-from)
                RESUME_FROM="$2"
                if [ -z "$RESUME_FROM" ]; then
                    log_fatal "Module requis pour --resume-from"
                fi
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                export DEBUG=true
                shift
                ;;
            --list-modules)
                list_modules
                exit 0
                ;;
            -*)
                log_fatal "Option inconnue: $1"
                ;;
            *)
                if [ -z "$TARGET_DIR" ]; then
                    TARGET_DIR="$1"
                else
                    log_fatal "Trop d'arguments positionnels"
                fi
                shift
                ;;
        esac
    done
    
    # Définir le répertoire cible par défaut
    if [ -z "$TARGET_DIR" ]; then
        TARGET_DIR=$(detect_working_directory)
    fi
    
    # Valider les paramètres
    validate_arguments
}

validate_arguments() {
    # Valider le module pour --only
    if [ -n "$ONLY_MODULE" ]; then
        local valid=false
        for module in "${INSTALL_MODULES[@]}"; do
            local name="${module%%:*}"
            if [ "$name" = "$ONLY_MODULE" ]; then
                valid=true
                break
            fi
        done
        
        if [ "$valid" = false ]; then
            log_fatal "Module invalide pour --only: $ONLY_MODULE"
        fi
    fi
    
    # Valider le module pour --resume-from
    if [ -n "$RESUME_FROM" ]; then
        local valid=false
        for module in "${INSTALL_MODULES[@]}"; do
            local name="${module%%:*}"
            if [ "$name" = "$RESUME_FROM" ]; then
                valid=true
                break
            fi
        done
        
        if [ "$valid" = false ]; then
            log_fatal "Module invalide pour --resume-from: $RESUME_FROM"
        fi
    fi
    
    # Valider et configurer le répertoire cible
    if [ -n "$TARGET_DIR" ]; then
        # Dans un environnement Docker, les permissions sont gérées différemment
        if is_docker_environment; then
            log_debug "Environnement Docker détecté - configuration proactive des permissions"
            
            # Créer le répertoire s'il n'existe pas
            if [ ! -d "$TARGET_DIR" ]; then
                log_debug "Création du répertoire cible: $TARGET_DIR"
                mkdir -p "$TARGET_DIR" 2>/dev/null || true
            fi
            
            # Corriger les permissions de manière proactive
            log_debug "Correction proactive des permissions Docker pour $TARGET_DIR"
            chown -R www-data:www-data "$TARGET_DIR" 2>/dev/null || true
            chmod -R 755 "$TARGET_DIR" 2>/dev/null || true
            
            # Vérifier que les permissions sont maintenant correctes
            if [ ! -w "$TARGET_DIR" ]; then
                log_warn "Permissions encore incorrectes, tentative de correction forcée"
                chmod -R 777 "$TARGET_DIR" 2>/dev/null || true
                
                if [ ! -w "$TARGET_DIR" ]; then
                    log_fatal "Impossible de corriger les permissions pour: $TARGET_DIR"
                fi
            fi
            
            log_debug "Permissions Docker configurées avec succès pour $TARGET_DIR"
        else
            # Validation classique pour les environnements non-Docker
            local parent_dir="$(dirname "$TARGET_DIR")"
            if [ ! -d "$parent_dir" ]; then
                log_fatal "Répertoire parent inexistant: $parent_dir"
            fi
            
            if [ ! -w "$parent_dir" ]; then
                log_fatal "Pas de permission d'écriture dans: $parent_dir"
            fi
        fi
    fi
}

# =============================================================================
# FONCTIONS D'EXÉCUTION DES MODULES
# =============================================================================

execute_module() {
    local module_name="$1"
    local module_desc="${2:-Installation du module $module_name}"
    local module_file="$SCRIPT_DIR/install/$module_name.sh"
    
    # Vérifier que le module existe
    if [ ! -f "$module_file" ]; then
        log_error "Module non trouvé: $module_file"
        return 1
    fi
    
    # Vérifier que le module est exécutable
    if [ ! -x "$module_file" ]; then
        log_debug "Module non exécutable, correction..."
        chmod +x "$module_file"
    fi
    
    log_step_start "$module_name" "$module_desc"
    local start_time=$(date +%s)
    
    # Mode dry-run
    if [ "$DRY_RUN" = true ]; then
        log_info "🔍 [DRY-RUN] Simulation du module $module_name"
        log_info "📂 Répertoire cible: $TARGET_DIR"
        log_info "📜 Script: $module_file"
        sleep 1  # Simuler un temps d'exécution
        local duration=$(calculate_duration $start_time)
        log_step_end "$module_name" "$duration"
        return 0
    fi
    
    # Exécution réelle du module
    local exit_code=0
    
    # Exécuter le module et capturer le vrai code de retour
    "$module_file" "$TARGET_DIR" 2>&1 | tee -a "$LOG_FILE"
    exit_code=${PIPESTATUS[0]}  # Capturer le code de retour du script, pas de tee
    
    if [ $exit_code -ne 0 ]; then
        log_error "Échec du module $module_name (code: $exit_code)"
        log_error "🔍 Consultez le fichier de log: $LOG_FILE"
        return $exit_code
    fi
    
    local duration=$(calculate_duration $start_time)
    log_step_end "$module_name" "$duration"
    
    return 0
}

run_installation() {
    local start_time=$(date +%s)
    local executed_modules=()
    local resume_found=false
    
    log_separator "DÉBUT DE L'INSTALLATION"
    log_info "🚀 Installation Laravel - ID: $INSTALLATION_ID"
    log_info "📍 Répertoire cible: $TARGET_DIR"
    log_info "📄 Fichier de log: $LOG_FILE"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "🔍 MODE SIMULATION (DRY-RUN)"
    fi
    
    # Afficher la configuration
    show_installation_config
    
    # Exécuter les modules
    for module_entry in "${INSTALL_MODULES[@]}"; do
        local module_name="${module_entry%%:*}"
        local module_desc="${module_entry##*:}"
        
        # Gestion du mode --only
        if [ -n "$ONLY_MODULE" ]; then
            if [ "$module_name" != "$ONLY_MODULE" ]; then
                continue
            fi
        fi
        
        # Gestion du mode --resume-from
        if [ -n "$RESUME_FROM" ]; then
            if [ "$resume_found" = false ]; then
                if [ "$module_name" = "$RESUME_FROM" ]; then
                    resume_found=true
                else
                    log_debug "Module ignoré (resume-from): $module_name"
                    continue
                fi
            fi
        fi
        
        # Skip des prérequis si demandé
        if [ "$SKIP_PREREQUISITES" = true ] && [ "$module_name" = "00-prerequisites" ]; then
            log_warn "⚠️ Vérification des prérequis ignorée (--skip-prereq)"
            continue
        fi
        
        # Exécuter le module
        if execute_module "$module_name" "$module_desc"; then
            executed_modules+=("$module_name")
            log_debug "Module $module_name exécuté avec succès"
        else
            local exit_code=$?
            log_error "Échec du module $module_name"
            
            # Afficher le rapport d'erreur
            show_error_report "$module_name" "${executed_modules[@]}"
            
            return $exit_code
        fi
        
        # En mode --only, s'arrêter après le module
        if [ -n "$ONLY_MODULE" ]; then
            break
        fi
    done
    
    # Rapport de succès
    local duration=$(calculate_duration $start_time)
    show_success_report "$duration" "${executed_modules[@]}"
    
    return 0
}

# =============================================================================
# FONCTIONS DE RAPPORT
# =============================================================================

show_installation_config() {
    log_separator "CONFIGURATION DE L'INSTALLATION"
    
    log_info "📋 Paramètres:"
    log_info "   • Répertoire cible: $TARGET_DIR"
    log_info "   • Mode debug: ${DEBUG:-false}"
    log_info "   • Mode silencieux: ${QUIET:-false}"
    log_info "   • Skip prérequis: $SKIP_PREREQUISITES"
    
    if [ -n "$ONLY_MODULE" ]; then
        log_info "   • Module unique: $ONLY_MODULE"
    fi
    
    if [ -n "$RESUME_FROM" ]; then
        log_info "   • Reprendre depuis: $RESUME_FROM"
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_info "   • Mode simulation: activé"
    fi
    
    log_info "🏗️ Modules à exécuter:"
    for module_entry in "${INSTALL_MODULES[@]}"; do
        local module_name="${module_entry%%:*}"
        local module_desc="${module_entry##*:}"
        local status="✅"
        
        # Vérifier les conditions d'exécution
        if [ -n "$ONLY_MODULE" ] && [ "$module_name" != "$ONLY_MODULE" ]; then
            status="⏸️ Ignoré (--only)"
        elif [ "$SKIP_PREREQUISITES" = true ] && [ "$module_name" = "00-prerequisites" ]; then
            status="⏸️ Ignoré (--skip-prereq)"
        elif [ -n "$RESUME_FROM" ]; then
            # Logique de resume
            local found=false
            for check_module in "${INSTALL_MODULES[@]}"; do
                local check_name="${check_module%%:*}"
                if [ "$check_name" = "$RESUME_FROM" ]; then
                    found=true
                elif [ "$check_name" = "$module_name" ] && [ "$found" = false ]; then
                    status="⏸️ Ignoré (--resume-from)"
                fi
            done
        fi
        
        log_info "   $status $module_name: $module_desc"
    done
}

show_success_report() {
    local duration="$1"
    shift
    local executed_modules=("$@")
    
    log_separator "INSTALLATION TERMINÉE AVEC SUCCÈS"
    
    log_success "🎉 Installation Laravel terminée en $duration"
    log_info "📍 Répertoire: $TARGET_DIR"
    log_info "🔢 Modules exécutés: ${#executed_modules[@]}"
    
    if [ ${#executed_modules[@]} -gt 0 ]; then
        log_info "📋 Modules installés:"
        for module in "${executed_modules[@]}"; do
            log_info "   ✅ $module"
        done
    fi
    
    # Informations finales
    if [ -d "$TARGET_DIR" ] && [ -f "$TARGET_DIR/artisan" ]; then
        cd "$TARGET_DIR"
        local laravel_version=$(get_laravel_version)
        local php_version=$(get_php_version)
        
        log_info "🔧 Versions installées:"
        log_info "   • Laravel: $laravel_version"
        log_info "   • PHP: $php_version"
    fi
    
    log_info "📄 Log complet: $LOG_FILE"
    
    # Prochaines étapes
    log_separator "PROCHAINES ÉTAPES"
    log_info "🚀 Pour commencer le développement:"
    log_info "   cd $TARGET_DIR"
    log_info "   php artisan serve"
    log_info ""
    log_info "🔧 Commandes utiles:"
    log_info "   make artisan cmd=\"migrate\"    # Migrations base de données"
    log_info "   make npm-dev                   # Développement frontend"
    log_info "   make test                      # Lancer les tests"
    log_info "   make quality-all               # Audit qualité complet"
}

show_error_report() {
    local failed_module="$1"
    shift
    local executed_modules=("$@")
    
    log_separator "ÉCHEC DE L'INSTALLATION"
    
    log_error "💥 Installation échouée au module: $failed_module"
    
    if [ ${#executed_modules[@]} -gt 0 ]; then
        log_info "✅ Modules réussis avant l'échec:"
        for module in "${executed_modules[@]}"; do
            log_info "   ✅ $module"
        done
    fi
    
    log_info "🔧 Pour reprendre l'installation:"
    log_info "   $(basename "$0") --resume-from $failed_module"
    
    log_info "🔍 Pour déboguer le problème:"
    log_info "   $(basename "$0") --only $failed_module --verbose"
    
    log_info "📄 Log complet: $LOG_FILE"
    
    # Afficher les dernières erreurs
    log_error_summary
}

# =============================================================================
# FONCTION PRINCIPALE
# =============================================================================

main() {
    # Capturer les signaux pour un nettoyage propre
    trap 'log_fatal "Installation interrompue par l'\''utilisateur"' INT TERM
    
    # Parser les arguments
    parse_arguments "$@"
    
    # Initialiser le logging avec l'ID d'installation
    export LOG_FILE="/tmp/laravel-install-$INSTALLATION_ID.log"
    init_logging "install-orchestrator"
    
    log_info "🔧 Orchestrateur d'installation Laravel démarré"
    
    # Vérifier l'environnement
    if ! is_docker_environment; then
        log_warn "⚠️ Environnement non-Docker détecté"
    fi
    
    # Lancer l'installation
    if run_installation; then
        log_success "✅ Installation terminée avec succès"
        return 0
    else
        log_fatal "❌ Installation échouée"
    fi
}

# =============================================================================
# EXÉCUTION
# =============================================================================

# Exécuter seulement si le script est appelé directement
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi