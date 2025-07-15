#!/bin/bash
# Script d'installation et de configuration d'Ansible pour Laravel
# Usage: ./install.sh

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

# Fonction pour détecter l'OS
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [[ -f /etc/debian_version ]]; then
            OS="debian"
        elif [[ -f /etc/redhat-release ]]; then
            OS="redhat"
        else
            OS="linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    else
        OS="unknown"
    fi
    
    info "OS détecté: $OS"
}

# Fonction pour installer Python et pip
install_python() {
    log "Installation de Python et pip..."
    
    case "$OS" in
        debian)
            sudo apt-get update
            sudo apt-get install -y python3 python3-pip python3-venv
            ;;
        redhat)
            sudo yum install -y python3 python3-pip
            ;;
        macos)
            if command -v brew &> /dev/null; then
                brew install python3
            else
                error "Homebrew n'est pas installé. Installez-le depuis https://brew.sh/"
                exit 1
            fi
            ;;
        *)
            error "OS non supporté: $OS"
            exit 1
            ;;
    esac
    
    log "✅ Python et pip installés"
}

# Fonction pour installer Ansible
install_ansible() {
    log "Installation d'Ansible..."
    
    # Créer un environnement virtuel
    if [[ ! -d "$ANSIBLE_DIR/venv" ]]; then
        python3 -m venv "$ANSIBLE_DIR/venv"
    fi
    
    # Activer l'environnement virtuel
    source "$ANSIBLE_DIR/venv/bin/activate"
    
    # Mettre à jour pip
    pip install --upgrade pip
    
    # Installer Ansible et les dépendances
    pip install ansible
    pip install docker
    pip install requests
    pip install psutil
    
    log "✅ Ansible installé"
}

# Fonction pour installer les collections Ansible
install_collections() {
    log "Installation des collections Ansible..."
    
    # Activer l'environnement virtuel
    source "$ANSIBLE_DIR/venv/bin/activate"
    
    # Installer les collections nécessaires
    ansible-galaxy collection install community.docker
    ansible-galaxy collection install ansible.posix
    ansible-galaxy collection install community.general
    
    log "✅ Collections installées"
}

# Fonction pour configurer SSH
configure_ssh() {
    log "Configuration SSH..."
    
    # Créer le répertoire .ssh s'il n'existe pas
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    
    # Générer une clé SSH si elle n'existe pas
    if [[ ! -f ~/.ssh/id_rsa ]]; then
        warning "Aucune clé SSH trouvée. Génération d'une nouvelle clé..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
        log "Clé SSH générée: ~/.ssh/id_rsa"
    fi
    
    # Configurer SSH pour ignorer la vérification des clés d'hôte
    if [[ ! -f ~/.ssh/config ]]; then
        cat > ~/.ssh/config << EOF
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
    ControlMaster auto
    ControlPath ~/.ssh/control-%h-%p-%r
    ControlPersist 10m
EOF
        chmod 600 ~/.ssh/config
        log "Configuration SSH créée: ~/.ssh/config"
    fi
    
    log "✅ SSH configuré"
}

# Fonction pour créer la configuration Ansible
create_ansible_config() {
    log "Création de la configuration Ansible..."
    
    # Créer le fichier de configuration local
    cat > "$ANSIBLE_DIR/ansible.cfg" << EOF
[defaults]
inventory = ./inventories/production/hosts.yml
remote_user = root
ask_pass = False
host_key_checking = False
gathering = smart
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_fact_cache
fact_caching_timeout = 3600
timeout = 30
forks = 10
stdout_callback = yaml
stderr_callback = yaml
log_path = ./logs/ansible.log
roles_path = ./roles
become = True
become_method = sudo
become_user = root
become_ask_pass = False

[inventory]
enable_plugins = host_list, script, auto, yaml, ini, toml

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no
pipelining = True
control_path = /tmp/ansible-%%h-%%p-%%r
EOF
    
    log "✅ Configuration Ansible créée"
}

# Fonction pour créer les répertoires nécessaires
create_directories() {
    log "Création des répertoires nécessaires..."
    
    mkdir -p "$ANSIBLE_DIR/logs"
    mkdir -p "$ANSIBLE_DIR/backups"
    mkdir -p "$ANSIBLE_DIR/facts"
    mkdir -p "$ANSIBLE_DIR/tmp"
    mkdir -p "/tmp/ansible_fact_cache"
    
    log "✅ Répertoires créés"
}

# Fonction pour rendre les scripts exécutables
make_scripts_executable() {
    log "Configuration des permissions des scripts..."
    
    chmod +x "$ANSIBLE_DIR/scripts/"*.sh
    
    log "✅ Scripts configurés"
}

# Fonction pour créer un exemple d'inventaire
create_example_inventory() {
    log "Création d'un inventaire d'exemple..."
    
    if [[ ! -f "$ANSIBLE_DIR/inventories/example/hosts.yml" ]]; then
        mkdir -p "$ANSIBLE_DIR/inventories/example"
        
        cat > "$ANSIBLE_DIR/inventories/example/hosts.yml" << EOF
---
# Exemple d'inventaire - Copiez et modifiez selon vos besoins
all:
  children:
    web_servers:
      hosts:
        server1:
          ansible_host: 192.168.1.100
          ansible_user: root
          ansible_ssh_private_key_file: ~/.ssh/id_rsa
          deploy_path: /var/www/laravel-app
          project_name: laravel-example
          
    database_servers:
      hosts:
        server2:
          ansible_host: 192.168.1.101
          ansible_user: root
          ansible_ssh_private_key_file: ~/.ssh/id_rsa

  vars:
    environment: production
    timezone: Europe/Paris
    laravel_env: production
    laravel_debug: false
    laravel_log_level: error
EOF
        
        log "✅ Inventaire d'exemple créé: $ANSIBLE_DIR/inventories/example/hosts.yml"
    fi
}

# Fonction pour créer un script d'activation
create_activation_script() {
    log "Création du script d'activation..."
    
    cat > "$ANSIBLE_DIR/activate.sh" << EOF
#!/bin/bash
# Script d'activation de l'environnement Ansible
# Usage: source ./activate.sh

export ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg"
export ANSIBLE_ROLES_PATH="$ANSIBLE_DIR/roles"
export ANSIBLE_INVENTORY="$ANSIBLE_DIR/inventories/production/hosts.yml"
export ANSIBLE_LOG_PATH="$ANSIBLE_DIR/logs/ansible.log"

# Activer l'environnement virtuel Python
source "$ANSIBLE_DIR/venv/bin/activate"

echo "🚀 Environnement Ansible activé"
echo "Utilisez './scripts/deploy.sh --help' pour voir les options"
EOF
    
    chmod +x "$ANSIBLE_DIR/activate.sh"
    
    log "✅ Script d'activation créé"
}

# Fonction pour tester l'installation
test_installation() {
    log "Test de l'installation..."
    
    # Activer l'environnement virtuel
    source "$ANSIBLE_DIR/venv/bin/activate"
    
    # Vérifier Ansible
    ansible --version
    
    # Vérifier les collections
    ansible-galaxy collection list | grep -E "(community.docker|ansible.posix)"
    
    # Vérifier la syntaxe du playbook
    ansible-playbook \
        --syntax-check \
        "$ANSIBLE_DIR/playbooks/deploy.yml"
    
    log "✅ Installation testée avec succès"
}

# Fonction pour afficher les informations post-installation
show_post_install_info() {
    log "🎉 Installation terminée avec succès !"
    
    cat << EOF

📋 PROCHAINES ÉTAPES:

1. Configurer votre inventaire:
   - Copiez: cp inventories/example/hosts.yml inventories/production/hosts.yml
   - Modifiez: nano inventories/production/hosts.yml
   - Ajoutez vos serveurs et leurs adresses IP

2. Configurer les variables d'environnement:
   - Modifiez: nano group_vars/production/main.yml
   - Adaptez selon vos besoins

3. Activer l'environnement:
   - Exécutez: source ./activate.sh

4. Tester la connexion:
   - Exécutez: ./scripts/deploy.sh production --check

5. Déployer:
   - Exécutez: ./scripts/deploy.sh production

📚 DOCUMENTATION:
   - Technique: ./docs/TECHNICAL.md
   - Utilisation: ./docs/USAGE.md

🔧 OUTILS UTILES:
   - Déploiement: ./scripts/deploy.sh
   - Sauvegarde: ./scripts/deploy.sh backup production
   - Logs: ./scripts/deploy.sh logs production
   - Statut: ./scripts/deploy.sh status production

EOF
}

# Fonction principale
main() {
    log "🚀 Installation d'Ansible pour Laravel"
    log "====================================="
    
    detect_os
    install_python
    install_ansible
    install_collections
    configure_ssh
    create_ansible_config
    create_directories
    make_scripts_executable
    create_example_inventory
    create_activation_script
    test_installation
    show_post_install_info
    
    log "✅ Installation complète terminée"
}

# Exécuter le script principal
main "$@"