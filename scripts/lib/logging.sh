#!/bin/bash

# =============================================================================
# SYSTÈME DE LOGGING UNIFORME
# =============================================================================
#
# Ce module fournit un système de logging uniforme pour tous les modules
# d'installation Laravel. Il gère les niveaux de log, les couleurs et
# l'écriture dans les fichiers de log.
#
# Utilisation:
#   source "$(dirname "$0")/lib/logging.sh"
#   log "INFO" "Message informatif"
#   log "ERROR" "Message d'erreur"
#   log "SUCCESS" "Message de succès"
#
# =============================================================================

# Couleurs pour les logs
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Variables globales de configuration du logging
DEBUG=${DEBUG:-false}
LOG_LEVEL=${LOG_LEVEL:-"INFO"}
LOG_FILE=${LOG_FILE:-"/tmp/laravel-install-$(date +%Y%m%d-%H%M%S).log"}
QUIET=${QUIET:-false}

# Créer le répertoire de logs si nécessaire
mkdir -p "$(dirname "$LOG_FILE")"

# =============================================================================
# FONCTIONS DE LOGGING
# =============================================================================

#
# Fonction principale de logging avec support des niveaux
#
# Arguments:
#   $1: Niveau de log (DEBUG|INFO|WARN|ERROR|SUCCESS)
#   $@: Message à logger
#
# Exemples:
#   log "INFO" "Installation de Laravel en cours..."
#   log "ERROR" "Erreur lors de l'installation"
#   log "SUCCESS" "Installation terminée avec succès"
#
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Vérifier si le niveau est autorisé
    if ! _should_log "$level"; then
        return 0
    fi
    
    # Construire le message formaté
    local formatted_message="[$level $timestamp] $message"
    local colored_message=""
    
    # Appliquer les couleurs selon le niveau
    case "$level" in
        "DEBUG")
            colored_message="${PURPLE}$formatted_message${NC}"
            ;;
        "INFO")
            colored_message="${BLUE}$formatted_message${NC}"
            ;;
        "WARN")
            colored_message="${YELLOW}$formatted_message${NC}"
            ;;
        "ERROR")
            colored_message="${RED}$formatted_message${NC}"
            ;;
        "SUCCESS")
            colored_message="${GREEN}$formatted_message${NC}"
            ;;
        "STEP")
            colored_message="${CYAN}$formatted_message${NC}"
            ;;
        *)
            colored_message="${WHITE}$formatted_message${NC}"
            ;;
    esac
    
    # Écrire dans le fichier de log (sans couleurs)
    echo "$formatted_message" >> "$LOG_FILE"
    
    # Afficher à l'écran si pas en mode silencieux
    if [ "$QUIET" != "true" ]; then
        echo -e "$colored_message"
    fi
}

#
# Fonctions de logging raccourcies pour faciliter l'utilisation
#
log_debug() {
    log "DEBUG" "$@"
}

log_info() {
    log "INFO" "$@"
}

log_warn() {
    log "WARN" "$@"
}

log_error() {
    log "ERROR" "$@"
}

log_success() {
    log "SUCCESS" "$@"
}

log_step() {
    log "STEP" "$@"
}

#
# Afficher un séparateur visuel pour organiser les logs
#
log_separator() {
    local title="$1"
    local separator_char="${2:-=}"
    local length=80
    
    local separator=$(printf "%*s" $length | tr ' ' "$separator_char")
    
    if [ -n "$title" ]; then
        local title_length=${#title}
        local padding=$(((length - title_length - 2) / 2))
        local left_pad=$(printf "%*s" $padding | tr ' ' "$separator_char")
        local right_pad=$(printf "%*s" $((length - title_length - 2 - padding)) | tr ' ' "$separator_char")
        
        log "INFO" "$left_pad $title $right_pad"
    else
        log "INFO" "$separator"
    fi
}

#
# Logger le début d'une étape importante
#
log_step_start() {
    local step_name="$1"
    local description="$2"
    
    log_separator "$step_name"
    if [ -n "$description" ]; then
        log "STEP" "🚀 $description"
    else
        log "STEP" "🚀 Début de l'étape: $step_name"
    fi
}

#
# Logger la fin d'une étape importante
#
log_step_end() {
    local step_name="$1"
    local duration="$2"
    
    if [ -n "$duration" ]; then
        log "SUCCESS" "✅ $step_name terminé en $duration"
    else
        log "SUCCESS" "✅ $step_name terminé"
    fi
}

#
# Logger une erreur fatale et quitter
#
log_fatal() {
    local message="$1"
    local exit_code="${2:-1}"
    
    log "ERROR" "💥 ERREUR FATALE: $message"
    log "ERROR" "🔍 Consultez le fichier de log: $LOG_FILE"
    exit "$exit_code"
}

#
# Afficher un récapitulatif des logs d'erreur
#
log_error_summary() {
    local error_count=$(grep -c "\[ERROR " "$LOG_FILE" 2>/dev/null || echo "0")
    local warn_count=$(grep -c "\[WARN " "$LOG_FILE" 2>/dev/null || echo "0")
    
    if [ "$error_count" -gt 0 ] || [ "$warn_count" -gt 0 ]; then
        log_separator "RÉCAPITULATIF"
        
        if [ "$error_count" -gt 0 ]; then
            log "ERROR" "$error_count erreur(s) détectée(s)"
        fi
        
        if [ "$warn_count" -gt 0 ]; then
            log "WARN" "$warn_count avertissement(s)"
        fi
        
        log "INFO" "📄 Fichier de log complet: $LOG_FILE"
    fi
}

# =============================================================================
# FONCTIONS UTILITAIRES PRIVÉES
# =============================================================================

#
# Déterminer si un niveau de log doit être affiché
#
_should_log() {
    local level="$1"
    
    # Si DEBUG est activé, tout afficher
    if [ "$DEBUG" = "true" ]; then
        return 0
    fi
    
    # Niveaux de priorité (plus le nombre est haut, plus c'est prioritaire)
    case "$level" in
        "DEBUG") local level_num=1 ;;
        "INFO") local level_num=2 ;;
        "STEP") local level_num=2 ;;
        "WARN") local level_num=3 ;;
        "ERROR") local level_num=4 ;;
        "SUCCESS") local level_num=2 ;;
        *) local level_num=2 ;;
    esac
    
    # Niveau minimum configuré
    case "$LOG_LEVEL" in
        "DEBUG") local min_level=1 ;;
        "INFO") local min_level=2 ;;
        "WARN") local min_level=3 ;;
        "ERROR") local min_level=4 ;;
        *) local min_level=2 ;;
    esac
    
    # Retourner 0 si le niveau est suffisant, 1 sinon
    [ "$level_num" -ge "$min_level" ]
}

#
# Initialiser le système de logging
#
init_logging() {
    local module_name="$1"
    
    # Ajouter l'en-tête au fichier de log
    {
        echo "============================================="
        echo "DÉBUT DU LOG - $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Module: ${module_name:-"Inconnu"}"
        echo "Niveau de log: $LOG_LEVEL"
        echo "Mode debug: $DEBUG"
        echo "============================================="
    } >> "$LOG_FILE"
}

# =============================================================================
# EXPORT DES FONCTIONS
# =============================================================================

# Rendre les fonctions disponibles pour les scripts qui sourcent ce fichier
export -f log log_debug log_info log_warn log_error log_success log_step
export -f log_separator log_step_start log_step_end log_fatal log_error_summary
export -f init_logging

# Variables globales exportées
export DEBUG LOG_LEVEL LOG_FILE QUIET