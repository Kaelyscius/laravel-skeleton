#!/bin/bash
# Script de validation de la configuration Ansible
# Usage: ./validate.sh [environment]

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(dirname "$SCRIPT_DIR")"

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

# Fonction pour vérifier la présence d'un fichier
check_file() {
    local file="$1"
    local description="$2"
    
    if [[ -f "$file" ]]; then
        log "✅ $description: $file"
        return 0
    else
        error "❌ $description manquant: $file"
        return 1
    fi
}

# Fonction pour vérifier la présence d'un répertoire
check_directory() {
    local dir="$1"
    local description="$2"
    
    if [[ -d "$dir" ]]; then
        log "✅ $description: $dir"
        return 0
    else
        error "❌ $description manquant: $dir"
        return 1
    fi
}

# Fonction pour vérifier la syntaxe YAML
check_yaml_syntax() {
    local file="$1"
    local description="$2"
    
    if [[ -f "$file" ]]; then
        if python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
            log "✅ Syntaxe YAML valide: $description"
            return 0
        else
            error "❌ Syntaxe YAML invalide: $description ($file)"
            return 1
        fi
    else
        warning "⚠️  Fichier non trouvé pour vérification YAML: $file"
        return 1
    fi
}

# Fonction pour vérifier les permissions
check_permissions() {
    local file="$1"
    local expected_perm="$2"
    local description="$3"
    
    if [[ -f "$file" ]]; then
        local actual_perm=$(stat -c "%a" "$file")
        if [[ "$actual_perm" == "$expected_perm" ]]; then
            log "✅ Permissions correctes ($expected_perm): $description"
            return 0
        else
            warning "⚠️  Permissions incorrectes ($actual_perm au lieu de $expected_perm): $description"
            return 1
        fi
    else
        error "❌ Fichier non trouvé pour vérification permissions: $file"
        return 1
    fi
}

# Fonction pour vérifier les secrets
check_secrets() {
    local file="$1"
    local description="$2"
    
    if [[ -f "$file" ]]; then
        # Vérifier la présence de secrets en dur
        local secrets_found=false
        
        # Patterns à rechercher
        local patterns=(
            "password.*=.*['\"][^'\"]*['\"]"
            "secret.*=.*['\"][^'\"]*['\"]"
            "key.*=.*['\"][^'\"]*['\"]"
            "token.*=.*['\"][^'\"]*['\"]"
            "api_key.*=.*['\"][^'\"]*['\"]"
        )
        
        for pattern in "${patterns[@]}"; do
            if grep -i -E "$pattern" "$file" >/dev/null 2>&1; then
                warning "⚠️  Possible secret détecté dans $description: $file"
                secrets_found=true
            fi
        done
        
        if [[ "$secrets_found" == false ]]; then
            log "✅ Aucun secret détecté: $description"
            return 0
        else
            return 1
        fi
    else
        info "ℹ️  Fichier non trouvé pour vérification secrets: $file"
        return 0
    fi
}

# Fonction pour vérifier la structure des rôles
check_role_structure() {
    local role_name="$1"
    local role_path="$ANSIBLE_DIR/roles/$role_name"
    
    log "Vérification du rôle: $role_name"
    
    # Vérifier la présence des répertoires
    local required_dirs=("tasks" "handlers" "templates" "vars" "defaults" "meta" "files")
    local missing_dirs=()
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$role_path/$dir" ]]; then
            missing_dirs+=("$dir")
        fi
    done
    
    if [[ ${#missing_dirs[@]} -eq 0 ]]; then
        log "✅ Structure du rôle $role_name complète"
    else
        warning "⚠️  Répertoires manquants pour le rôle $role_name: ${missing_dirs[*]}"
    fi
    
    # Vérifier les fichiers principaux
    check_file "$role_path/tasks/main.yml" "Tasks du rôle $role_name"
    check_file "$role_path/defaults/main.yml" "Defaults du rôle $role_name"
    check_file "$role_path/meta/main.yml" "Meta du rôle $role_name"
    
    # Vérifier la syntaxe YAML
    check_yaml_syntax "$role_path/tasks/main.yml" "Tasks du rôle $role_name"
    check_yaml_syntax "$role_path/defaults/main.yml" "Defaults du rôle $role_name"
    check_yaml_syntax "$role_path/meta/main.yml" "Meta du rôle $role_name"
    
    # Vérifier les secrets
    check_secrets "$role_path/tasks/main.yml" "Tasks du rôle $role_name"
    check_secrets "$role_path/defaults/main.yml" "Defaults du rôle $role_name"
}

# Fonction pour vérifier un environnement
check_environment() {
    local env="$1"
    
    log "Vérification de l'environnement: $env"
    
    # Vérifier l'inventaire
    check_file "$ANSIBLE_DIR/inventories/$env/hosts.yml" "Inventaire $env"
    check_yaml_syntax "$ANSIBLE_DIR/inventories/$env/hosts.yml" "Inventaire $env"
    check_secrets "$ANSIBLE_DIR/inventories/$env/hosts.yml" "Inventaire $env"
    
    # Vérifier les variables d'environnement
    check_file "$ANSIBLE_DIR/group_vars/$env/main.yml" "Variables $env"
    check_yaml_syntax "$ANSIBLE_DIR/group_vars/$env/main.yml" "Variables $env"
    check_secrets "$ANSIBLE_DIR/group_vars/$env/main.yml" "Variables $env"
}

# Fonction pour vérifier les playbooks
check_playbooks() {
    log "Vérification des playbooks"
    
    # Vérifier le playbook principal
    check_file "$ANSIBLE_DIR/playbooks/deploy.yml" "Playbook de déploiement"
    check_yaml_syntax "$ANSIBLE_DIR/playbooks/deploy.yml" "Playbook de déploiement"
    check_secrets "$ANSIBLE_DIR/playbooks/deploy.yml" "Playbook de déploiement"
}

# Fonction pour vérifier les scripts
check_scripts() {
    log "Vérification des scripts"
    
    local scripts=("deploy.sh" "install.sh" "validate.sh")
    
    for script in "${scripts[@]}"; do
        check_file "$ANSIBLE_DIR/scripts/$script" "Script $script"
        check_permissions "$ANSIBLE_DIR/scripts/$script" "755" "Script $script"
    done
}

# Fonction pour vérifier la configuration générale
check_general_config() {
    log "Vérification de la configuration générale"
    
    # Vérifier la configuration Ansible
    check_file "$ANSIBLE_DIR/ansible.cfg" "Configuration Ansible"
    
    # Vérifier la documentation
    check_file "$ANSIBLE_DIR/README.md" "Documentation principale"
    check_file "$ANSIBLE_DIR/docs/USAGE.md" "Guide d'utilisation"
    check_file "$ANSIBLE_DIR/docs/TECHNICAL.md" "Documentation technique"
    
    # Vérifier les fichiers de sécurité
    check_file "$ANSIBLE_DIR/.gitignore" "Fichier .gitignore"
    check_file "$ANSIBLE_DIR/.env.example" "Exemple de configuration"
    
    # Vérifier que .env n'existe pas (sécurité)
    if [[ -f "$ANSIBLE_DIR/.env" ]]; then
        warning "⚠️  Fichier .env détecté. Assurez-vous qu'il n'est pas committé dans Git"
    else
        log "✅ Aucun fichier .env détecté (sécurité)"
    fi
}

# Fonction pour vérifier les prérequis
check_prerequisites() {
    log "Vérification des prérequis"
    
    # Vérifier Python
    if command -v python3 &> /dev/null; then
        log "✅ Python3 installé: $(python3 --version)"
    else
        error "❌ Python3 non installé"
        return 1
    fi
    
    # Vérifier Ansible (si installé)
    if command -v ansible &> /dev/null; then
        log "✅ Ansible installé: $(ansible --version | head -n1)"
    else
        warning "⚠️  Ansible non installé. Utilisez ./scripts/install.sh pour l'installer"
    fi
    
    # Vérifier Git
    if command -v git &> /dev/null; then
        log "✅ Git installé: $(git --version)"
    else
        error "❌ Git non installé"
        return 1
    fi
}

# Fonction pour vérifier la syntaxe Ansible
check_ansible_syntax() {
    log "Vérification de la syntaxe Ansible"
    
    if command -v ansible-playbook &> /dev/null; then
        # Vérifier chaque environnement
        for env in production staging development; do
            if [[ -f "$ANSIBLE_DIR/inventories/$env/hosts.yml" ]]; then
                info "Vérification syntaxe pour l'environnement: $env"
                if ansible-playbook \
                    -i "$ANSIBLE_DIR/inventories/$env/hosts.yml" \
                    "$ANSIBLE_DIR/playbooks/deploy.yml" \
                    --syntax-check >/dev/null 2>&1; then
                    log "✅ Syntaxe Ansible valide pour $env"
                else
                    error "❌ Syntaxe Ansible invalide pour $env"
                fi
            fi
        done
    else
        warning "⚠️  Ansible non installé, impossible de vérifier la syntaxe"
    fi
}

# Fonction principale
main() {
    local environment="${1:-all}"
    local failed_checks=0
    
    log "🔍 Début de la validation de la configuration Ansible"
    log "Environnement: $environment"
    log "Répertoire: $ANSIBLE_DIR"
    
    # Vérifications générales
    check_prerequisites || ((failed_checks++))
    check_general_config || ((failed_checks++))
    check_playbooks || ((failed_checks++))
    check_scripts || ((failed_checks++))
    
    # Vérifier les rôles
    local roles=("common" "docker" "laravel-app" "security" "monitoring" "nginx-proxy")
    for role in "${roles[@]}"; do
        check_role_structure "$role" || ((failed_checks++))
    done
    
    # Vérifier les environnements
    if [[ "$environment" == "all" ]]; then
        for env in production staging development; do
            if [[ -d "$ANSIBLE_DIR/inventories/$env" ]]; then
                check_environment "$env" || ((failed_checks++))
            fi
        done
    else
        check_environment "$environment" || ((failed_checks++))
    fi
    
    # Vérifier la syntaxe Ansible
    check_ansible_syntax || ((failed_checks++))
    
    # Résumé final
    echo ""
    if [[ $failed_checks -eq 0 ]]; then
        log "🎉 Validation terminée avec succès ! Aucune erreur détectée."
    else
        error "❌ Validation terminée avec $failed_checks erreur(s) détectée(s)."
        exit 1
    fi
}

# Exécuter le script principal
main "$@"