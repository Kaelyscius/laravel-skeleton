#!/bin/bash

# Script de mise à jour automatique des images Docker custom
# Alternative à Watchtower pour les images construites localement

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly LOG_FILE="$PROJECT_ROOT/logs/image-updates.log"

# Couleurs pour les logs
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Images custom à surveiller
readonly CUSTOM_IMAGES=(
    "php"
    "apache" 
    "node"
)

# Images de base à vérifier
readonly BASE_IMAGES=(
    "php:8.5-fpm-alpine"
    "httpd:2.4-alpine"
    "node:24-alpine"
)

# Logging
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${BLUE}[INFO ${timestamp}]${NC} $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN ${timestamp}]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR ${timestamp}]${NC} $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS ${timestamp}]${NC} $message" ;;
    esac
    
    # Log vers fichier
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$level $timestamp] $message" >> "$LOG_FILE"
}

# Vérifier si une image de base a été mise à jour
check_base_image_update() {
    local base_image="$1"
    
    log "INFO" "🔍 Vérification de $base_image..."
    
    # Récupérer le SHA de l'image locale
    local local_sha
    if local_sha=$(docker images --format "{{.ID}}" "$base_image" 2>/dev/null | head -1); then
        if [[ -z "$local_sha" ]]; then
            log "INFO" "Image $base_image pas encore présente localement"
            return 0  # Considérer comme mise à jour nécessaire
        fi
    else
        log "INFO" "Image $base_image pas encore présente localement"
        return 0
    fi
    
    # Récupérer le SHA de l'image distante
    log "INFO" "Vérification de la version distante de $base_image..."
    docker pull "$base_image" --quiet 2>/dev/null || {
        log "WARN" "Impossible de vérifier $base_image"
        return 1
    }
    
    # Comparer les SHA
    local remote_sha
    remote_sha=$(docker images --format "{{.ID}}" "$base_image" | head -1)
    
    if [[ "$local_sha" != "$remote_sha" ]]; then
        log "INFO" "✅ Nouvelle version détectée pour $base_image"
        return 0
    else
        log "INFO" "✅ $base_image est à jour"
        return 1
    fi
}

# Rebuilder une image custom
rebuild_custom_image() {
    local service="$1"
    
    log "INFO" "🔨 Reconstruction de l'image $service..."
    
    cd "$PROJECT_ROOT"
    
    # Arrêter le service
    docker compose stop "$service" 2>/dev/null || true
    
    # Rebuilder avec --pull pour récupérer les dernières images de base
    if docker compose build --pull --no-cache "$service"; then
        log "SUCCESS" "✅ Image $service reconstruite avec succès"
        
        # Redémarrer le service
        if docker compose up -d "$service"; then
            log "SUCCESS" "✅ Service $service redémarré"
            return 0
        else
            log "ERROR" "❌ Échec du redémarrage de $service"
            return 1
        fi
    else
        log "ERROR" "❌ Échec de la reconstruction de $service"
        return 1
    fi
}

# Vérifier la santé des services après mise à jour
check_services_health() {
    log "INFO" "🔍 Vérification de la santé des services..."
    
    sleep 30  # Attendre que les services démarrent
    
    local failed_services=0
    
    for service in "${CUSTOM_IMAGES[@]}"; do
        local container_name="${COMPOSE_PROJECT_NAME:-laravel-app}_${service}"
        
        if docker ps --filter "name=$container_name" --filter "status=running" --format "{{.Names}}" | grep -q "$container_name"; then
            log "SUCCESS" "✅ $service fonctionne correctement"
        else
            log "ERROR" "❌ $service ne fonctionne pas correctement"
            ((failed_services++))
        fi
    done
    
    return $failed_services
}

# Nettoyer les anciennes images
cleanup_old_images() {
    log "INFO" "🧹 Nettoyage des anciennes images..."
    
    # Supprimer les images dangangling
    if docker images -f "dangling=true" -q | grep -q .; then
        docker rmi $(docker images -f "dangling=true" -q) 2>/dev/null || true
        log "SUCCESS" "✅ Images orphelines supprimées"
    fi
    
    # Nettoyer le cache de build
    docker builder prune -f >/dev/null 2>&1 || true
    log "SUCCESS" "✅ Cache de build nettoyé"
}

# Fonction principale
main() {
    local check_only=false
    
    # Traiter les arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --check-only)
                check_only=true
                shift
                ;;
            *)
                echo "Usage: $0 [--check-only]"
                exit 1
                ;;
        esac
    done
    
    if [[ "$check_only" == "true" ]]; then
        log "INFO" "🔍 Vérification des mises à jour disponibles (mode lecture seule)"
    else
        log "INFO" "🚀 Démarrage de la vérification des mises à jour d'images custom"
    fi
    
    local updates_needed=false
    local updated_services=()
    
    # Vérifier chaque image de base
    for i in "${!BASE_IMAGES[@]}"; do
        local base_image="${BASE_IMAGES[$i]}"
        local custom_service="${CUSTOM_IMAGES[$i]}"
        
        if check_base_image_update "$base_image"; then
            log "INFO" "📦 Mise à jour nécessaire pour $custom_service (base: $base_image)"
            updates_needed=true
            
            if [[ "$check_only" == "false" ]]; then
                if rebuild_custom_image "$custom_service"; then
                    updated_services+=("$custom_service")
                else
                    log "ERROR" "❌ Échec de la mise à jour de $custom_service"
                fi
            else
                log "INFO" "ℹ️  Mode vérification uniquement - aucune mise à jour effectuée"
            fi
        fi
    done
    
    # Si aucune mise à jour nécessaire
    if [[ "$updates_needed" == "false" ]]; then
        log "SUCCESS" "✅ Toutes les images custom sont à jour"
        return 0
    fi
    
    # En mode check-only, arrêter ici
    if [[ "$check_only" == "true" ]]; then
        log "INFO" "🔍 Vérification terminée - des mises à jour sont disponibles"
        log "INFO" "💡 Exécutez 'make update-images' pour appliquer les mises à jour"
        return 0
    fi
    
    # Vérifier la santé après mises à jour
    if [[ ${#updated_services[@]} -gt 0 ]]; then
        log "INFO" "Services mis à jour: ${updated_services[*]}"
        
        if check_services_health; then
            log "SUCCESS" "✅ Tous les services fonctionnent correctement après mise à jour"
            cleanup_old_images
        else
            log "ERROR" "❌ Certains services ont des problèmes après mise à jour"
            return 1
        fi
    fi
    
    log "SUCCESS" "🎉 Mise à jour des images custom terminée"
}

# Point d'entrée
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi