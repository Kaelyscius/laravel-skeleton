#!/bin/bash

# =============================================================================
# INSTALLATION INTERACTIVE LARAVEL TEMPLATE
# =============================================================================
# Script d'installation qui pose les bonnes questions avant de configurer

set -e

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Variables de configuration collectées
SELECTED_ENV=""
SELECTED_SERVICES=()
INSTALL_WATCHTOWER="true"
INSTALL_GIT_HOOKS="true"
NON_INTERACTIVE=false
YQ_AVAILABLE=false

log() {
    local level=$1
    shift
    local message="$*"
    
    case $level in
        "INFO")  echo -e "${BLUE}ℹ️  $message${NC}" ;;
        "WARN")  echo -e "${YELLOW}⚠️  $message${NC}" ;;
        "SUCCESS") echo -e "${GREEN}✅ $message${NC}" ;;
        "ERROR") echo -e "${RED}❌ $message${NC}" ;;
        "HEADER") echo -e "${CYAN}🚀 $message${NC}" ;;
    esac
}

# Afficher le header
show_header() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║                    LARAVEL TEMPLATE SETUP                   ║${NC}"
    echo -e "${PURPLE}║                   Installation Interactive                  ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Détecter le mode non-interactif
detect_non_interactive() {
    if [ ! -t 0 ] || [ "$CI" = "true" ] || [ -n "$BATCH_MODE" ]; then
        NON_INTERACTIVE=true
        log "INFO" "Mode non-interactif détecté"
    fi
}

# Installer yq automatiquement selon l'OS
install_yq_automatically() {
    log "INFO" "📦 Installation automatique de yq..."
    
    # Détecter l'OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux (WSL, Ubuntu, Debian) - Installation directe du binaire (plus fiable)
        log "INFO" "🐧 Linux détecté - installation directe du binaire yq..."
        local yq_url="https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
        
        # Télécharger et installer
        if command -v wget &> /dev/null; then
            if [ "$EUID" -eq 0 ]; then
                wget -qO /usr/local/bin/yq "$yq_url" && chmod +x /usr/local/bin/yq
            else
                sudo wget -qO /usr/local/bin/yq "$yq_url" && sudo chmod +x /usr/local/bin/yq
            fi
        elif command -v curl &> /dev/null; then
            if [ "$EUID" -eq 0 ]; then
                curl -sL "$yq_url" -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq
            else
                sudo curl -sL "$yq_url" -o /usr/local/bin/yq && sudo chmod +x /usr/local/bin/yq
            fi
        else
            log "ERROR" "❌ wget ou curl requis pour télécharger yq"
            return 1
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            log "INFO" "🍎 macOS détecté - installation via Homebrew"
            brew install yq >/dev/null 2>&1
        else
            log "ERROR" "❌ Homebrew requis sur macOS pour installer yq"
            return 1
        fi
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        # Windows (Git Bash, Cygwin)
        log "INFO" "🪟 Windows détecté - installation manuelle recommandée"
        log "INFO" "💡 Téléchargez yq depuis: https://github.com/mikefarah/yq/releases"
        return 1
    else
        log "WARN" "⚠️ OS non reconnu - tentative d'installation générique"
        local yq_url="https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
        wget -qO /tmp/yq "$yq_url" && chmod +x /tmp/yq && sudo mv /tmp/yq /usr/local/bin/yq
    fi
    
    # Vérifier que l'installation a réussi
    if command -v yq &> /dev/null; then
        local yq_version=$(yq --version 2>/dev/null | head -1)
        if [[ "$yq_version" == *"0.0.0"* ]] || [[ -z "$yq_version" ]]; then
            log "ERROR" "❌ Version yq invalide détectée"
            return 1
        else
            log "SUCCESS" "✅ yq installé avec succès ($yq_version)"
            return 0
        fi
    else
        log "ERROR" "❌ Échec de l'installation automatique de yq"
        return 1
    fi
}

# Créer un fichier de configuration par défaut
create_default_config() {
    # S'assurer que CONFIG_FILE est défini
    if [ -z "$CONFIG_FILE" ]; then
        CONFIG_FILE="$PROJECT_ROOT/config/installer.yml"
        log "INFO" "🔧 CONFIG_FILE redéfini: $CONFIG_FILE"
    fi
    
    local config_file="$CONFIG_FILE"
    
    log "INFO" "📝 Création du fichier: $config_file"
    
    # S'assurer que le répertoire existe
    mkdir -p "$(dirname "$config_file")"
    
    cat > "$config_file" << 'EOF'
# Configuration Laravel Template par défaut
project:
  name: "Laravel"
  domain: "laravel.local"

services:
  optional:
    mailpit:
      enabled: true
      environments: ["local", "development"]
    adminer:
      enabled: true
      environments: ["local", "development"]
    it-tools:
      enabled: false
      environments: ["local", "development"]
    dozzle:
      enabled: true
      environments: ["local", "development", "staging"]

network:
  ports:
    mariadb: 3306
    redis: 6379
    dozzle: 9999

environments:
  local:
    debug: true
    log_level: "debug"
  development:
    debug: true
    log_level: "debug"
  staging:
    debug: false
    log_level: "info"
  production:
    debug: false
    log_level: "error"

security:
  snyk:
    severity_threshold: "high"
    fail_on_issues: false
    monitor_enabled: true
EOF
    
    if [ -f "$config_file" ]; then
        log "SUCCESS" "✅ Configuration par défaut créée: $config_file"
    else
        log "ERROR" "❌ Échec de création du fichier: $config_file"
        return 1
    fi
}

# Vérifier et installer les prérequis
check_dependencies() {
    log "INFO" "🔍 Vérification des prérequis..."
    
    # Debug: Afficher les chemins et s'assurer que CONFIG_FILE est défini
    log "INFO" "📁 Répertoire projet: $PROJECT_ROOT"
    
    # S'assurer que CONFIG_FILE est toujours défini
    if [ -z "$CONFIG_FILE" ]; then
        CONFIG_FILE="$PROJECT_ROOT/config/installer.yml"
        log "WARN" "🔧 CONFIG_FILE redéfini: $CONFIG_FILE"
    fi
    
    log "INFO" "📁 Fichier config: $CONFIG_FILE"
    
    # Vérifier yq et l'installer si nécessaire
    local yq_version=""
    if command -v yq &> /dev/null; then
        yq_version=$(yq --version 2>/dev/null | head -1)
        log "INFO" "🔍 Version yq détectée: $yq_version"
        
        # Vérifier si c'est une version valide
        if [[ "$yq_version" == *"0.0.0"* ]] || [[ -z "$yq_version" ]] || [[ "$yq_version" == *"snap"* ]]; then
            log "WARN" "⚠️ Version yq invalide détectée ($yq_version)"
            log "INFO" "🔄 Remplacement par une version valide..."
            
            # Supprimer l'ancienne version si possible
            if command -v snap &> /dev/null && snap list yq &> /dev/null; then
                log "INFO" "🗑️ Suppression de la version snap..."
                sudo snap remove yq >/dev/null 2>&1 || true
            fi
            
            if ! install_yq_automatically; then
                log "ERROR" "❌ Impossible d'installer yq automatiquement"
                log "INFO" "💡 Le script continuera avec des valeurs par défaut"
                YQ_AVAILABLE=false
            else
                YQ_AVAILABLE=true
            fi
        else
            log "SUCCESS" "✅ yq version valide détectée"
            YQ_AVAILABLE=true
        fi
    else
        log "WARN" "⚠️ yq n'est pas installé"
        
        if [ "$NON_INTERACTIVE" = "true" ]; then
            # Mode automatique : installer sans demander
            log "INFO" "🤖 Mode automatique - installation de yq..."
            if ! install_yq_automatically; then
                log "ERROR" "❌ Impossible d'installer yq automatiquement"
                log "INFO" "💡 Le script continuera avec des valeurs par défaut"
                YQ_AVAILABLE=false
            else
                YQ_AVAILABLE=true
            fi
        else
            # Mode interactif : demander à l'utilisateur
            echo -e "${YELLOW}yq est requis pour parser la configuration YAML${NC}"
            read -p "Installer yq automatiquement ? [Y/n]: " install_yq
            install_yq=${install_yq:-y}
            
            if [[ "$install_yq" =~ ^[Yy]$ ]]; then
                if ! install_yq_automatically; then
                    log "WARN" "⚠️ Installation échouée - utilisation de valeurs par défaut"
                    YQ_AVAILABLE=false
                else
                    YQ_AVAILABLE=true
                fi
            else
                log "INFO" "⚠️ Installation de yq refusée - utilisation de valeurs par défaut"
                YQ_AVAILABLE=false
            fi
        fi
    fi
    
    # Vérifier autres outils essentiels
    local missing_tools=()
    for tool in make docker docker-compose git; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log "ERROR" "❌ Outils manquants: ${missing_tools[*]}"
        log "INFO" "💡 Sur Debian/Ubuntu: sudo apt install make docker.io docker-compose git"
        exit 1
    fi
    
    # Créer le fichier de config s'il n'existe pas
    if [ ! -f "$CONFIG_FILE" ]; then
        log "INFO" "📝 Création du fichier de configuration par défaut..."
        mkdir -p "$(dirname "$CONFIG_FILE")"
        create_default_config
    else
        log "SUCCESS" "✅ Fichier de configuration trouvé: $CONFIG_FILE"
    fi
    
    log "SUCCESS" "✅ Tous les prérequis sont satisfaits"
}

# Question sur l'environnement
ask_environment() {
    if [ "$NON_INTERACTIVE" = "true" ]; then
        SELECTED_ENV="local"
        log "INFO" "Environnement par défaut: $SELECTED_ENV"
        return 0
    fi
    
    echo -e "${CYAN}🎯 Quel environnement voulez-vous configurer ?${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} ${BLUE}local${NC}       - Développement local (défaut)"
    echo -e "  ${GREEN}2)${NC} ${BLUE}development${NC} - Environnement de développement complet"
    echo -e "  ${GREEN}3)${NC} ${BLUE}staging${NC}     - Environnement de pré-production"
    echo -e "  ${GREEN}4)${NC} ${BLUE}production${NC}  - Environnement de production"
    echo ""
    
    local choice
    read -p "Votre choix [1-4, défaut: 1]: " choice
    
    case $choice in
        1|"") SELECTED_ENV="local" ;;
        2) SELECTED_ENV="development" ;;
        3) SELECTED_ENV="staging" ;;
        4) SELECTED_ENV="production" ;;
        *) 
            echo -e "${RED}Choix invalide, utilisation de 'local' par défaut${NC}"
            SELECTED_ENV="local"
            ;;
    esac
    
    log "SUCCESS" "Environnement sélectionné: $SELECTED_ENV"
}

# Question sur les services optionnels
ask_optional_services() {
    if [ "$NON_INTERACTIVE" = "true" ]; then
        # En mode non-interactif, activer les services selon l'environnement
        if [ "$SELECTED_ENV" = "production" ]; then
            SELECTED_SERVICES=("dozzle")  # Seulement Dozzle en prod
        else
            SELECTED_SERVICES=("mailpit" "adminer" "dozzle")  # Services de dev
        fi
        log "INFO" "Services par défaut pour $SELECTED_ENV: ${SELECTED_SERVICES[*]}"
        return 0
    fi
    
    echo ""
    echo -e "${CYAN}📦 Quels services optionnels voulez-vous installer ?${NC}"
    echo ""
    
    # Adapter les questions selon l'environnement
    if [ "$SELECTED_ENV" = "production" ]; then
        echo -e "${YELLOW}⚠️  Mode production détecté - services de développement désactivés${NC}"
        echo ""
    fi
    
    local services_config=(
        "mailpit:Capture des emails de développement:dev"
        "adminer:Interface web pour les bases de données:dev"
        "it-tools:Boîte à outils pour développeurs (encodeurs, générateurs):optional"
        "dozzle:Monitoring des logs en temps réel:all"
    )
    
    SELECTED_SERVICES=()
    
    for service_info in "${services_config[@]}"; do
        IFS=':' read -r service_name service_desc service_env <<< "$service_info"
        
        # Filtrer selon l'environnement
        if [ "$service_env" = "dev" ] && [ "$SELECTED_ENV" = "production" ]; then
            continue
        fi
        
        local default_choice
        case $service_name in
            "mailpit"|"adminer"|"dozzle")
                default_choice="y"
                ;;
            "it-tools")
                default_choice="n"
                ;;
        esac
        
        echo -e "${BLUE}$service_name${NC} - $service_desc"
        read -p "Installer $service_name ? [y/N, défaut: $default_choice]: " choice
        
        choice=${choice:-$default_choice}
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            SELECTED_SERVICES+=("$service_name")
            echo -e "  ${GREEN}✓ $service_name sélectionné${NC}"
        else
            echo -e "  ${YELLOW}○ $service_name ignoré${NC}"
        fi
        echo ""
    done
    
    if [ ${#SELECTED_SERVICES[@]} -eq 0 ]; then
        log "INFO" "Aucun service optionnel sélectionné"
    else
        log "SUCCESS" "Services sélectionnés: ${SELECTED_SERVICES[*]}"
    fi
}

# Question sur les outils supplémentaires
ask_additional_tools() {
    if [ "$NON_INTERACTIVE" = "true" ]; then
        log "INFO" "Outils supplémentaires activés par défaut"
        return 0
    fi
    
    echo ""
    echo -e "${CYAN}🛠️ Outils supplémentaires${NC}"
    echo ""
    
    echo -e "${BLUE}Watchtower${NC} - Mises à jour automatiques des containers"
    read -p "Installer Watchtower ? [Y/n, défaut: Y]: " choice
    choice=${choice:-y}
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        INSTALL_WATCHTOWER="true"
        echo -e "  ${GREEN}✓ Watchtower activé${NC}"
    else
        INSTALL_WATCHTOWER="false"
        echo -e "  ${YELLOW}○ Watchtower désactivé${NC}"
    fi
    echo ""
    
    echo -e "${BLUE}Hooks Git${NC} - Vérifications automatiques avant commit"
    read -p "Installer les hooks Git ? [Y/n, défaut: Y]: " choice
    choice=${choice:-y}
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        INSTALL_GIT_HOOKS="true"
        echo -e "  ${GREEN}✓ Hooks Git activés${NC}"
    else
        INSTALL_GIT_HOOKS="false"
        echo -e "  ${YELLOW}○ Hooks Git désactivés${NC}"
    fi
}

# Mettre à jour le fichier installer.yml avec les choix
update_installer_config() {
    log "INFO" "📝 Mise à jour de la configuration..."
    
    local config_file="$PROJECT_ROOT/config/installer.yml"
    
    # Créer une sauvegarde
    if [ -f "$config_file" ]; then
        cp "$config_file" "$config_file.backup.$(date +%Y%m%d-%H%M%S)"
    fi
    
    # Mettre à jour les services optionnels
    for service in mailpit adminer it-tools dozzle; do
        local enabled="false"
        if [[ " ${SELECTED_SERVICES[*]} " =~ " $service " ]]; then
            enabled="true"
        fi
        
        # Utiliser yq si disponible, sinon fallback
        if [ "$YQ_AVAILABLE" = "true" ]; then
            yq eval ".services.optional.$service.enabled = $enabled" -i "$config_file"
        else
            log "WARN" "yq non disponible - mise à jour manuelle du service $service"
        fi
    done
    
    log "SUCCESS" "Configuration mise à jour"
}

# Générer la configuration
generate_configuration() {
    log "INFO" "🔧 Génération de la configuration pour $SELECTED_ENV..."
    
    # Chercher le script de génération (avec ou sans 's')
    local config_script=""
    if [ -f "$PROJECT_ROOT/scripts/setup/generate-configs.sh" ]; then
        config_script="$PROJECT_ROOT/scripts/setup/generate-configs.sh"
    elif [ -f "$PROJECT_ROOT/scripts/setup/generate-config.sh" ]; then
        config_script="$PROJECT_ROOT/scripts/setup/generate-config.sh"
    else
        log "ERROR" "Script de génération non trouvé"
        log "INFO" "Cherché dans :"
        log "INFO" "  - $PROJECT_ROOT/scripts/setup/generate-configs.sh"
        log "INFO" "  - $PROJECT_ROOT/scripts/setup/generate-config.sh"
        exit 1
    fi

    log "INFO" "📄 Script trouvé: $config_script"
    chmod +x "$config_script"
    "$config_script" "$SELECTED_ENV"
}

# Lancer l'installation
run_installation() {
    log "HEADER" "Démarrage de l'installation..."
    
    cd "$PROJECT_ROOT"
    
    # Installation Laravel de base
    log "INFO" "📦 Installation Laravel..."
    if command -v make &> /dev/null; then
        make install
    else
        log "ERROR" "Make non disponible"
        exit 1
    fi
    
    # Watchtower si demandé
    if [ "$INSTALL_WATCHTOWER" = "true" ]; then
        log "INFO" "🔄 Configuration Watchtower..."
        make setup-watchtower 2>/dev/null || log "WARN" "Configuration Watchtower échouée"
    fi
    
    # Hooks Git si demandés
    if [ "$INSTALL_GIT_HOOKS" = "true" ]; then
        log "INFO" "🔗 Installation des hooks Git..."
        make setup-git-hooks 2>/dev/null || log "WARN" "Installation hooks Git échouée"
    fi
}

# Afficher le résumé final
show_summary() {
    echo ""
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║                    INSTALLATION TERMINÉE                    ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    log "SUCCESS" "🎉 Installation Laravel terminée !"
    echo ""
    echo -e "${CYAN}📊 Résumé de votre configuration :${NC}"
    echo -e "  ${BLUE}• Environnement :${NC} $SELECTED_ENV"
    echo -e "  ${BLUE}• Services installés :${NC} ${SELECTED_SERVICES[*]:-aucun}"
    echo -e "  ${BLUE}• Watchtower :${NC} $INSTALL_WATCHTOWER"
    echo -e "  ${BLUE}• Hooks Git :${NC} $INSTALL_GIT_HOOKS"
    echo ""
    
    echo -e "${CYAN}🔗 Accès rapides :${NC}"
    echo -e "  • Laravel : ${GREEN}https://laravel.local${NC}"
    echo -e "  • Horizon : ${GREEN}https://laravel.local/horizon${NC}"
    echo -e "  • Telescope : ${GREEN}https://laravel.local/telescope${NC}"
    
    if [[ " ${SELECTED_SERVICES[*]} " =~  mailpit  ]]; then
        echo -e "  • Mailpit : ${GREEN}http://localhost:8025${NC}"
    fi
    if [[ " ${SELECTED_SERVICES[*]} " =~ " adminer " ]]; then
        echo -e "  • Adminer : ${GREEN}http://localhost:8080${NC}"
    fi
    if [[ " ${SELECTED_SERVICES[*]} " =~ " it-tools " ]]; then
        echo -e "  • IT-Tools : ${GREEN}http://localhost:8081${NC}"
    fi
    if [[ " ${SELECTED_SERVICES[*]} " =~ " dozzle " ]]; then
        echo -e "  • Dozzle : ${GREEN}http://localhost:9999${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}💡 Prochaines étapes :${NC}"
    echo -e "  1. Ajoutez '127.0.0.1 laravel.local' à votre /etc/hosts"
    echo -e "  2. Visitez https://laravel.local"
    echo -e "  3. Consultez la documentation : ${GREEN}cat README.md${NC}"
}

# Fonction principale
main() {
    detect_non_interactive
    
    if [ "$NON_INTERACTIVE" = "false" ]; then
        show_header
    fi
    
    log "HEADER" "Configuration de votre environnement Laravel"
    
    # Vérifier et installer les prérequis AVANT tout
    check_dependencies
    
    ask_environment
    ask_optional_services
    ask_additional_tools
    
    if [ "$NON_INTERACTIVE" = "false" ]; then
        echo ""
        echo -e "${CYAN}📋 Résumé de votre configuration :${NC}"
        echo -e "  • Environnement : ${GREEN}$SELECTED_ENV${NC}"
        echo -e "  • Services : ${GREEN}${SELECTED_SERVICES[*]:-aucun}${NC}"
        echo -e "  • Watchtower : ${GREEN}$INSTALL_WATCHTOWER${NC}"
        echo -e "  • Hooks Git : ${GREEN}$INSTALL_GIT_HOOKS${NC}"
        echo ""
        
        read -p "Confirmer l'installation ? [Y/n]: " confirm
        confirm=${confirm:-y}
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log "WARN" "Installation annulée"
            exit 0
        fi
    fi
    
    update_installer_config
    generate_configuration
    run_installation
    show_summary
}

# Mode arguments en ligne de commande
if [ "$1" = "--env" ]; then
    SELECTED_ENV="$2"
    NON_INTERACTIVE=true
    shift 2
fi

if [ "$1" = "--batch" ]; then
    NON_INTERACTIVE=true
    shift
fi

# Afficher l'aide
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    cat << EOF
🚀 Installation interactive Laravel Template

USAGE:
    ./scripts/setup/interactive-setup.sh [options]

OPTIONS:
    --env ENV        Spécifier l'environnement (local|development|staging|production)
    --batch          Mode non-interactif avec valeurs par défaut
    -h, --help       Afficher cette aide

EXEMPLES:
    # Installation interactive
    ./scripts/setup/interactive-setup.sh
    
    # Installation automatique pour production
    ./scripts/setup/interactive-setup.sh --env production --batch
    
    # Installation locale avec sélection
    ./scripts/setup/interactive-setup.sh --env local

EOF
    exit 0
fi

# Exécuter
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi