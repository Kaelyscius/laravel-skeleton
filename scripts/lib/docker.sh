#!/bin/bash

# =============================================================================
# UTILITAIRES DOCKER POUR L'INSTALLATION LARAVEL
# =============================================================================
#
# Ce module fournit des utilitaires spécialisés pour la gestion des containers
# Docker dans le contexte de l'installation Laravel. Il complète les fonctions
# de base de common.sh avec des fonctionnalités avancées.
#
# Utilisation:
#   source "$(dirname "$0")/lib/docker.sh"
#
# =============================================================================

# Variables globales Docker
readonly DOCKER_COMPOSE_CMD="${DOCKER_COMPOSE_CMD:-docker-compose}"
readonly DOCKER_CMD="${DOCKER_CMD:-docker}"

# Containers par défaut du projet Laravel
readonly DEFAULT_PHP_CONTAINER="laravel-app_php"
readonly DEFAULT_APACHE_CONTAINER="laravel-app_apache"
readonly DEFAULT_POSTGRES_CONTAINER="laravel-app_postgres"
readonly DEFAULT_REDIS_CONTAINER="laravel-app_redis"
readonly DEFAULT_NODE_CONTAINER="laravel-app_node"

# =============================================================================
# FONCTIONS DE DÉTECTION ET VÉRIFICATION
# =============================================================================

#
# Détecter le nom du projet Docker Compose
#
get_compose_project_name() {
    # Essayer différentes sources pour le nom du projet
    if [ -n "${COMPOSE_PROJECT_NAME:-}" ]; then
        echo "$COMPOSE_PROJECT_NAME"
        return 0
    fi
    
    # Lire depuis le fichier .env s'il existe
    local env_file=$(find_root_env)
    if [ -n "$env_file" ] && [ -f "$env_file" ]; then
        local project_name=$(grep "^COMPOSE_PROJECT_NAME=" "$env_file" 2>/dev/null | cut -d= -f2 | tr -d '"')
        if [ -n "$project_name" ]; then
            echo "$project_name"
            return 0
        fi
    fi
    
    # Fallback sur le nom du répertoire
    echo "$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')"
}

#
# Construire le nom complet d'un container
#
# Arguments:
#   $1: Nom du service (php, apache, postgres, etc.)
#
get_container_name() {
    local service="$1"
    local project_name=$(get_compose_project_name)
    
    echo "${project_name}_${service}"
}

#
# Obtenir l'ID d'un container en cours d'exécution
#
# Arguments:
#   $1: Nom du container ou du service
#
get_container_id() {
    local container_name="$1"
    
    # Si ce n'est pas un nom complet, construire le nom du container
    if [[ "$container_name" != *"_"* ]]; then
        container_name=$(get_container_name "$container_name")
    fi
    
    $DOCKER_CMD ps -qf "name=${container_name}" 2>/dev/null | head -1
}

#
# Vérifier si Docker Compose est disponible et fonctionnel
#
check_docker_compose() {
    log_debug "Vérification de Docker Compose..."
    
    if ! command -v "$DOCKER_COMPOSE_CMD" &> /dev/null; then
        log_error "Docker Compose non trouvé (commande: $DOCKER_COMPOSE_CMD)"
        return 1
    fi
    
    # Vérifier la version
    local version=$($DOCKER_COMPOSE_CMD version --short 2>/dev/null)
    if [ -n "$version" ]; then
        log_debug "Docker Compose version: $version"
        return 0
    else
        log_error "Impossible d'obtenir la version de Docker Compose"
        return 1
    fi
}

#
# Vérifier si Docker est disponible et fonctionnel
#
check_docker() {
    log_debug "Vérification de Docker..."
    
    if ! command -v "$DOCKER_CMD" &> /dev/null; then
        log_error "Docker non trouvé (commande: $DOCKER_CMD)"
        return 1
    fi
    
    # Vérifier que le daemon Docker est accessible
    if ! $DOCKER_CMD info &> /dev/null; then
        log_error "Daemon Docker non accessible (vérifiez les permissions et que Docker est démarré)"
        return 1
    fi
    
    local version=$($DOCKER_CMD version --format '{{.Server.Version}}' 2>/dev/null)
    if [ -n "$version" ]; then
        log_debug "Docker version: $version"
        return 0
    else
        log_error "Impossible d'obtenir la version de Docker"
        return 1
    fi
}

# =============================================================================
# FONCTIONS DE GESTION DES CONTAINERS
# =============================================================================

#
# Attendre qu'un container soit en état "healthy"
#
# Arguments:
#   $1: Nom du container ou du service
#   $2: Timeout en secondes (défaut: 120)
#
wait_for_container_healthy() {
    local container_name="$1"
    local timeout="${2:-120}"
    local count=0
    
    # Obtenir l'ID du container
    local container_id=$(get_container_id "$container_name")
    if [ -z "$container_id" ]; then
        log_error "Container '$container_name' non trouvé"
        return 1
    fi
    
    log_info "Attente de l'état healthy du container '$container_name'..."
    
    while [ $count -lt $timeout ]; do
        local health_status=$($DOCKER_CMD inspect --format='{{.State.Health.Status}}' "$container_id" 2>/dev/null)
        
        case "$health_status" in
            "healthy")
                log_success "Container '$container_name' healthy"
                return 0
                ;;
            "unhealthy")
                log_error "Container '$container_name' unhealthy"
                return 1
                ;;
            "starting")
                log_debug "Container '$container_name' en cours de démarrage..."
                ;;
            "")
                # Pas de healthcheck défini, vérifier juste que le container tourne
                local status=$($DOCKER_CMD inspect --format='{{.State.Status}}' "$container_id" 2>/dev/null)
                if [ "$status" = "running" ]; then
                    log_success "Container '$container_name' running (pas de healthcheck)"
                    return 0
                fi
                ;;
        esac
        
        sleep 2
        count=$((count + 2))
        
        if [ $((count % 20)) -eq 0 ]; then
            log_debug "Attente... ($count/$timeout secondes)"
        fi
    done
    
    log_error "Timeout atteint en attendant le container '$container_name'"
    return 1
}

#
# Exécuter une commande dans un container
#
# Arguments:
#   $1: Nom du container ou du service
#   $2-*: Commande à exécuter
#
docker_exec() {
    local container_name="$1"
    shift
    local command="$*"
    
    local container_id=$(get_container_id "$container_name")
    if [ -z "$container_id" ]; then
        log_error "Container '$container_name' non trouvé pour exécuter: $command"
        return 1
    fi
    
    log_debug "Exécution dans $container_name: $command"
    $DOCKER_CMD exec -u 1000:1000 "$container_id" bash -c "$command"
}

#
# Exécuter une commande PHP/artisan dans le container PHP
#
# Arguments:
#   $1-*: Commande à exécuter
#
docker_php() {
    local php_container=$(get_container_name "php")
    docker_exec "$php_container" "$@"
}

#
# Exécuter une commande Composer dans le container PHP
#
# Arguments:
#   $1-*: Commande composer à exécuter
#
docker_composer() {
    local php_container=$(get_container_name "php")
    docker_exec "$php_container" "composer $*"
}

#
# Exécuter une commande artisan dans le container PHP
#
# Arguments:
#   $1-*: Commande artisan à exécuter
#
docker_artisan() {
    local php_container=$(get_container_name "php")
    docker_exec "$php_container" "php artisan $*"
}

#
# Exécuter une commande npm/node dans le container Node
#
# Arguments:
#   $1-*: Commande npm/node à exécuter
#
docker_npm() {
    local node_container=$(get_container_name "node")
    docker_exec "$node_container" "$@"
}

# =============================================================================
# FONCTIONS DE GESTION DES SERVICES
# =============================================================================

#
# Démarrer tous les services Docker Compose
#
start_docker_services() {
    log_info "Démarrage des services Docker..."
    
    if ! check_docker_compose; then
        return 1
    fi
    
    # Vérifier qu'un fichier docker-compose.yml existe
    if [ ! -f "docker-compose.yml" ]; then
        log_error "Fichier docker-compose.yml non trouvé dans $(pwd)"
        return 1
    fi
    
    if $DOCKER_COMPOSE_CMD up -d 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Services Docker démarrés"
        return 0
    else
        log_error "Échec du démarrage des services Docker"
        return 1
    fi
}

#
# Arrêter tous les services Docker Compose
#
stop_docker_services() {
    log_info "Arrêt des services Docker..."
    
    if ! check_docker_compose; then
        return 1
    fi
    
    if $DOCKER_COMPOSE_CMD down 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Services Docker arrêtés"
        return 0
    else
        log_error "Échec de l'arrêt des services Docker"
        return 1
    fi
}

#
# Redémarrer tous les services Docker Compose
#
restart_docker_services() {
    log_info "Redémarrage des services Docker..."
    
    if stop_docker_services && start_docker_services; then
        log_success "Services Docker redémarrés"
        return 0
    else
        log_error "Échec du redémarrage des services Docker"
        return 1
    fi
}

#
# Vérifier le statut de tous les containers
#
check_all_containers_status() {
    log_info "Vérification du statut des containers..."
    
    local services=("php" "apache" "postgres" "redis")
    local all_ok=true
    
    for service in "${services[@]}"; do
        local container_name=$(get_container_name "$service")
        if check_container "$container_name"; then
            log_debug "✓ $service: OK"
        else
            log_warn "✗ $service: Problème"
            all_ok=false
        fi
    done
    
    if [ "$all_ok" = true ]; then
        log_success "Tous les containers sont opérationnels"
        return 0
    else
        log_warn "Certains containers ont des problèmes"
        return 1
    fi
}

# =============================================================================
# FONCTIONS DE DIAGNOSTIC ET DEBUG
# =============================================================================

#
# Afficher les logs d'un container
#
# Arguments:
#   $1: Nom du container ou du service
#   $2: Nombre de lignes (défaut: 50)
#
show_container_logs() {
    local container_name="$1"
    local lines="${2:-50}"
    
    local container_id=$(get_container_id "$container_name")
    if [ -z "$container_id" ]; then
        log_error "Container '$container_name' non trouvé"
        return 1
    fi
    
    log_info "Logs du container '$container_name' (dernières $lines lignes):"
    $DOCKER_CMD logs --tail "$lines" "$container_id"
}

#
# Afficher des informations détaillées sur l'environnement Docker
#
show_docker_environment_info() {
    log_separator "INFORMATIONS ENVIRONNEMENT DOCKER"
    
    # Informations Docker
    if check_docker; then
        local docker_version=$($DOCKER_CMD version --format '{{.Server.Version}}' 2>/dev/null)
        log_info "🐳 Docker: $docker_version"
    fi
    
    # Informations Docker Compose
    if check_docker_compose; then
        local compose_version=$($DOCKER_COMPOSE_CMD version --short 2>/dev/null)
        log_info "🐙 Docker Compose: $compose_version"
    fi
    
    # Projet actuel
    local project_name=$(get_compose_project_name)
    log_info "📦 Projet: $project_name"
    
    # Containers actifs
    log_info "📋 Containers actifs:"
    local services=("php" "apache" "postgres" "redis" "node")
    for service in "${services[@]}"; do
        local container_name=$(get_container_name "$service")
        local container_id=$(get_container_id "$service")
        
        if [ -n "$container_id" ]; then
            local status=$($DOCKER_CMD inspect --format='{{.State.Status}}' "$container_id" 2>/dev/null)
            log_info "   ✅ $service ($container_name): $status"
        else
            log_info "   ❌ $service ($container_name): non démarré"
        fi
    done
}

#
# Nettoyer les ressources Docker inutilisées
#
cleanup_docker_resources() {
    log_info "Nettoyage des ressources Docker inutilisées..."
    
    # Nettoyer les containers arrêtés
    local stopped_containers=$($DOCKER_CMD ps -aq --filter "status=exited" 2>/dev/null | wc -l)
    if [ "$stopped_containers" -gt 0 ]; then
        log_info "Suppression de $stopped_containers container(s) arrêté(s)..."
        $DOCKER_CMD container prune -f
    fi
    
    # Nettoyer les images non utilisées
    local unused_images=$($DOCKER_CMD images -q --filter "dangling=true" 2>/dev/null | wc -l)
    if [ "$unused_images" -gt 0 ]; then
        log_info "Suppression de $unused_images image(s) non utilisée(s)..."
        $DOCKER_CMD image prune -f
    fi
    
    # Nettoyer les réseaux non utilisés
    $DOCKER_CMD network prune -f &>/dev/null
    
    # Nettoyer les volumes non utilisés (avec prudence)
    log_debug "Nettoyage des volumes non utilisés..."
    $DOCKER_CMD volume prune -f &>/dev/null
    
    log_success "Nettoyage Docker terminé"
}

# =============================================================================
# EXPORT DES FONCTIONS
# =============================================================================

# Rendre les fonctions disponibles pour les scripts qui sourcent ce fichier
export -f get_compose_project_name get_container_name get_container_id
export -f check_docker_compose check_docker
export -f wait_for_container_healthy docker_exec docker_php docker_composer docker_artisan docker_npm
export -f start_docker_services stop_docker_services restart_docker_services check_all_containers_status
export -f show_container_logs show_docker_environment_info cleanup_docker_resources

# Variables exportées
export DOCKER_COMPOSE_CMD DOCKER_CMD
export DEFAULT_PHP_CONTAINER DEFAULT_APACHE_CONTAINER DEFAULT_POSTGRES_CONTAINER DEFAULT_REDIS_CONTAINER DEFAULT_NODE_CONTAINER