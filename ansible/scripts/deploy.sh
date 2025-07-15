#!/bin/bash
# Script de déploiement Ansible pour Laravel
# Usage: ./deploy.sh [environment] [options]

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$ANSIBLE_DIR")"

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction pour afficher les messages
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Fonction d'aide
show_help() {
    cat << EOF
🚀 Script de déploiement Ansible pour Laravel

Usage: $0 [ENVIRONNEMENT] [OPTIONS]

ENVIRONNEMENTS:
  production    Déploiement en production
  staging       Déploiement en staging
  development   Déploiement en développement
  local         Déploiement local

OPTIONS:
  --check       Mode check (dry-run)
  --tags TAG    Exécuter uniquement les tags spécifiés
  --skip-tags   Ignorer les tags spécifiés
  --limit HOST  Limiter à un hôte spécifique
  --verbose     Mode verbeux
  --help        Afficher cette aide

EXEMPLES:
  $0 production
  $0 staging --check
  $0 development --tags docker,laravel
  $0 production --limit production-web-01

AUTRES COMMANDES:
  $0 setup                 Configuration initiale
  $0 check [environnement] Vérifier la configuration
  $0 backup [environnement] Créer une sauvegarde
  $0 logs [environnement]   Voir les logs
  $0 status [environnement] Voir le statut
EOF
}

# Fonction pour vérifier les prérequis
check_prerequisites() {
    log "Vérification des prérequis..."
    
    # Vérifier Ansible
    if ! command -v ansible &> /dev/null; then
        error "Ansible n'est pas installé. Installez-le avec: pip install ansible"
        exit 1
    fi
    
    # Vérifier ansible-playbook
    if ! command -v ansible-playbook &> /dev/null; then
        error "ansible-playbook n'est pas disponible"
        exit 1
    fi
    
    # Vérifier la version d'Ansible
    ansible_version=$(ansible --version | head -n1 | cut -d' ' -f2)
    info "Version d'Ansible: $ansible_version"
    
    # Vérifier la structure des répertoires
    if [[ ! -d "$ANSIBLE_DIR/inventories" ]]; then
        error "Répertoire des inventaires non trouvé: $ANSIBLE_DIR/inventories"
        exit 1
    fi
    
    if [[ ! -d "$ANSIBLE_DIR/playbooks" ]]; then
        error "Répertoire des playbooks non trouvé: $ANSIBLE_DIR/playbooks"
        exit 1
    fi
    
    log "✅ Prérequis vérifiés"
}

# Fonction pour valider l'environnement
validate_environment() {
    local env="$1"
    
    if [[ ! -f "$ANSIBLE_DIR/inventories/$env/hosts.yml" ]]; then
        error "Inventaire non trouvé pour l'environnement: $env"
        error "Fichier attendu: $ANSIBLE_DIR/inventories/$env/hosts.yml"
        exit 1
    fi
    
    if [[ ! -f "$ANSIBLE_DIR/group_vars/$env/main.yml" ]]; then
        warning "Variables d'environnement non trouvées: $ANSIBLE_DIR/group_vars/$env/main.yml"
    fi
}

# Fonction pour configurer l'environnement initial
setup_environment() {
    log "Configuration initiale d'Ansible..."
    
    # Créer les répertoires nécessaires
    mkdir -p "$HOME/.ansible/tmp"
    mkdir -p "$ANSIBLE_DIR/logs"
    
    # Installer les collections Ansible nécessaires
    info "Installation des collections Ansible..."
    ansible-galaxy collection install community.docker
    ansible-galaxy collection install ansible.posix
    
    # Créer un fichier de configuration personnel
    if [[ ! -f "$HOME/.ansible.cfg" ]]; then
        cat > "$HOME/.ansible.cfg" << EOF
[defaults]
host_key_checking = False
retry_files_enabled = False
gathering = smart
fact_caching = jsonfile
fact_caching_connection = ~/.ansible/tmp/facts_cache
fact_caching_timeout = 3600
EOF
        log "Configuration Ansible créée: $HOME/.ansible.cfg"
    fi
    
    log "✅ Configuration terminée"
}

# Fonction pour exécuter le déploiement
run_deployment() {
    local environment="$1"
    shift
    local extra_args="$@"
    
    log "🚀 Déploiement sur l'environnement: $environment"
    
    # Valider l'environnement
    validate_environment "$environment"
    
    # Construire la commande Ansible
    local cmd="ansible-playbook"
    cmd+=" -i $ANSIBLE_DIR/inventories/$environment/hosts.yml"
    cmd+=" $ANSIBLE_DIR/playbooks/deploy.yml"
    cmd+=" $extra_args"
    
    # Afficher la commande
    info "Commande exécutée: $cmd"
    
    # Exécuter le déploiement
    cd "$ANSIBLE_DIR"
    eval "$cmd"
    
    log "✅ Déploiement terminé"
}

# Fonction pour vérifier la configuration
check_configuration() {
    local environment="$1"
    
    log "Vérification de la configuration pour: $environment"
    
    validate_environment "$environment"
    
    # Vérifier la syntaxe du playbook
    ansible-playbook \
        -i "$ANSIBLE_DIR/inventories/$environment/hosts.yml" \
        "$ANSIBLE_DIR/playbooks/deploy.yml" \
        --syntax-check
    
    # Vérifier la connectivité
    ansible all \
        -i "$ANSIBLE_DIR/inventories/$environment/hosts.yml" \
        -m ping
    
    log "✅ Configuration valide"
}

# Fonction pour créer une sauvegarde
create_backup() {
    local environment="$1"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_dir="$ANSIBLE_DIR/backups/$environment/$timestamp"
    
    log "Création d'une sauvegarde pour: $environment"
    
    mkdir -p "$backup_dir"
    
    # Sauvegarder la configuration
    cp -r "$ANSIBLE_DIR/inventories/$environment" "$backup_dir/inventory"
    cp -r "$ANSIBLE_DIR/group_vars/$environment" "$backup_dir/group_vars"
    
    log "✅ Sauvegarde créée: $backup_dir"
}

# Fonction pour voir les logs
view_logs() {
    local environment="$1"
    local log_file="$ANSIBLE_DIR/logs/deploy_$environment.log"
    
    if [[ -f "$log_file" ]]; then
        tail -f "$log_file"
    else
        warning "Fichier de log non trouvé: $log_file"
    fi
}

# Fonction pour voir le statut
show_status() {
    local environment="$1"
    
    log "Statut pour l'environnement: $environment"
    
    validate_environment "$environment"
    
    # Vérifier la connectivité
    ansible all \
        -i "$ANSIBLE_DIR/inventories/$environment/hosts.yml" \
        -m setup \
        --tree "$ANSIBLE_DIR/facts/$environment"
    
    log "✅ Statut affiché"
}

# Fonction principale
main() {
    local environment=""
    local action=""
    local extra_args=""
    
    # Traiter les arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            production|staging|development|local)
                environment="$1"
                shift
                ;;
            setup)
                action="setup"
                shift
                ;;
            check)
                action="check"
                shift
                ;;
            backup)
                action="backup"
                shift
                ;;
            logs)
                action="logs"
                shift
                ;;
            status)
                action="status"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                extra_args+=" $1"
                shift
                ;;
        esac
    done
    
    # Vérifier les prérequis
    check_prerequisites
    
    # Exécuter l'action
    case "$action" in
        setup)
            setup_environment
            ;;
        check)
            if [[ -z "$environment" ]]; then
                error "Environnement requis pour la vérification"
                exit 1
            fi
            check_configuration "$environment"
            ;;
        backup)
            if [[ -z "$environment" ]]; then
                error "Environnement requis pour la sauvegarde"
                exit 1
            fi
            create_backup "$environment"
            ;;
        logs)
            if [[ -z "$environment" ]]; then
                error "Environnement requis pour les logs"
                exit 1
            fi
            view_logs "$environment"
            ;;
        status)
            if [[ -z "$environment" ]]; then
                error "Environnement requis pour le statut"
                exit 1
            fi
            show_status "$environment"
            ;;
        *)
            if [[ -z "$environment" ]]; then
                error "Environnement requis"
                show_help
                exit 1
            fi
            run_deployment "$environment" $extra_args
            ;;
    esac
}

# Exécuter le script principal
main "$@"