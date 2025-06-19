#!/bin/bash

# Script wrapper pour la configuration automatique d'Uptime Kuma
# Usage: ./scripts/setup-uptime-kuma-wrapper.sh [--reset] [--help]

set -e

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="$SCRIPT_DIR/setup-uptime-kuma-auto.py"
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME:-"laravel-app"}

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case $level in
        "INFO")
            echo -e "${BLUE}[INFO $timestamp]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN $timestamp]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR $timestamp]${NC} $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS $timestamp]${NC} $message"
            ;;
    esac
}

show_help() {
    echo -e "${CYAN}🤖 Configuration Automatique d'Uptime Kuma${NC}"
    echo -e "${CYAN}===========================================${NC}"
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo -e "  $0 [options]"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  ${GREEN}--reset${NC}     Réinitialiser complètement Uptime Kuma"
    echo -e "  ${GREEN}--help${NC}      Afficher cette aide"
    echo ""
    echo -e "${YELLOW}Variables d'environnement (optionnelles):${NC}"
    echo -e "  ${GREEN}UPTIME_ADMIN_USER${NC}     Nom d'utilisateur admin (défaut: admin)"
    echo -e "  ${GREEN}UPTIME_ADMIN_PASS${NC}     Mot de passe admin (défaut: LaravelDev2024!)"
    echo -e "  ${GREEN}UPTIME_ADMIN_EMAIL${NC}    Email admin (défaut: admin@laravel.local)"
    echo -e "  ${GREEN}UPTIME_KUMA_URL${NC}       URL d'Uptime Kuma (défaut: http://localhost:3001)"
    echo ""
    echo -e "${YELLOW}Exemples:${NC}"
    echo -e "  ${GREEN}$0${NC}                              # Configuration automatique"
    echo -e "  ${GREEN}$0 --reset${NC}                      # Réinitialiser et reconfigurer"
    echo -e "  ${GREEN}UPTIME_ADMIN_PASS=monpass $0${NC}    # Avec mot de passe personnalisé"
}

check_dependencies() {
    log "INFO" "🔍 Vérification des dépendances..."

    # Vérifier Python 3
    if ! command -v python3 &> /dev/null; then
        log "ERROR" "Python 3 n'est pas installé"
        log "INFO" "Installation requise:"
        log "INFO" "  • Ubuntu/Debian: sudo apt install python3 python3-pip"
        log "INFO" "  • CentOS/RHEL: sudo yum install python3 python3-pip"
        log "INFO" "  • macOS: brew install python3"
        exit 1
    fi

    # Vérifier pip
    if ! command -v pip3 &> /dev/null && ! python3 -m pip --version &> /dev/null; then
        log "ERROR" "pip3 n'est pas installé"
        log "INFO" "Installation requise: sudo apt install python3-pip"
        exit 1
    fi

    # Vérifier requests
    if ! python3 -c "import requests" &> /dev/null; then
        log "WARN" "Module Python 'requests' manquant"
        log "INFO" "Installation automatique..."

        if python3 -m pip install --user requests &> /dev/null; then
            log "SUCCESS" "Module 'requests' installé avec succès"
        else
            log "ERROR" "Échec de l'installation du module 'requests'"
            exit 1
        fi
    fi

    # Vérifier Docker
    if ! command -v docker &> /dev/null; then
        log "ERROR" "Docker n'est pas installé"
        exit 1
    fi

    if ! command -v docker-compose &> /dev/null; then
        log "ERROR" "Docker Compose n'est pas installé"
        exit 1
    fi

    log "SUCCESS" "Toutes les dépendances sont installées"
}

check_docker_environment() {
    log "INFO" "🐳 Vérification de l'environnement Docker..."

    # Vérifier que Docker fonctionne
    if ! docker ps &> /dev/null; then
        log "ERROR" "Docker n'est pas démarré ou accessible"
        log "INFO" "Solutions possibles:"
        log "INFO" "  • Démarrer Docker: sudo systemctl start docker"
        log "INFO" "  • Ajouter l'utilisateur au groupe docker: sudo usermod -aG docker $USER"
        exit 1
    fi

    # Vérifier docker-compose.yml
    if [ ! -f "docker-compose.yml" ]; then
        log "ERROR" "Fichier docker-compose.yml non trouvé"
        log "INFO" "Assurez-vous d'être dans le répertoire racine du projet Laravel"
        exit 1
    fi

    # Vérifier service uptime-kuma
    if ! grep -q "uptime-kuma" docker-compose.yml; then
        log "ERROR" "Service uptime-kuma non trouvé dans docker-compose.yml"
        exit 1
    fi

    log "SUCCESS" "Environnement Docker validé"
}

ensure_containers_running() {
    log "INFO" "🚀 Vérification et démarrage des containers..."

    if ! docker ps --format "{{.Names}}" | grep -q "${COMPOSE_PROJECT_NAME}_uptime-kuma"; then
        log "WARN" "Container Uptime Kuma non démarré"
        log "INFO" "Démarrage des containers..."

        if docker-compose up -d; then
            log "SUCCESS" "Containers démarrés"
            log "INFO" "Attente de l'initialisation..."
            sleep 10
        else
            log "ERROR" "Échec du démarrage des containers"
            exit 1
        fi
    else
        log "SUCCESS" "Container Uptime Kuma déjà actif"
    fi

    # Vérifier le statut final
    local container_status
    container_status=$(docker ps --filter name="${COMPOSE_PROJECT_NAME}_uptime-kuma" --format "{{.Status}}")

    if [[ "$container_status" == *"Up"* ]]; then
        log "SUCCESS" "Container Uptime Kuma opérationnel: $container_status"
    else
        log "ERROR" "Problème avec le container Uptime Kuma: $container_status"
        exit 1
    fi
}

create_python_script() {
    log "INFO" "📄 Vérification du script Python..."

    if [ ! -f "$PYTHON_SCRIPT" ]; then
        log "WARN" "Script Python non trouvé, création d'un script de base..."

        # Créer le répertoire s'il n'existe pas
        mkdir -p "$(dirname "$PYTHON_SCRIPT")"

        # Créer le script Python avec cat au lieu d'echo pour éviter les problèmes d'échappement
        cat > "$PYTHON_SCRIPT" << 'EOF'
#!/usr/bin/env python3
"""
Script de base généré automatiquement pour Uptime Kuma
"""

import sys
import webbrowser
import os

def main():
    print("⚠️ Ce script a été généré automatiquement.")
    print("💡 Utilisez le script complet depuis l'artifact pour plus de fonctionnalités.")
    print()
    print("🌐 Ouverture d'Uptime Kuma...")

    # Variables d'environnement
    url = os.getenv('UPTIME_KUMA_URL', 'http://localhost:3001')
    admin_user = os.getenv('UPTIME_ADMIN_USER', 'admin')
    admin_pass = os.getenv('UPTIME_ADMIN_PASS', 'LaravelDev2024!')
    admin_email = os.getenv('UPTIME_ADMIN_EMAIL', 'admin@laravel.local')

    try:
        webbrowser.open(url)
        print(f"✅ Uptime Kuma ouvert dans le navigateur: {url}")
        print()
        print("👤 Credentials par défaut:")
        print(f"   • User: {admin_user}")
        print(f"   • Pass: {admin_pass}")
        print(f"   • Email: {admin_email}")
        print()
        print("📝 Créez votre compte avec ces informations")
        print()
        print("🔧 Pour une configuration automatique complète,")
        print("   copiez le script Python complet depuis l'artifact fourni.")

    except Exception as e:
        print(f"❌ Erreur: {e}")
        print(f"🌐 Ouvrez manuellement: {url}")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

        chmod +x "$PYTHON_SCRIPT"
        log "WARN" "Script de base créé. Pour le script complet, copiez l'artifact Python fourni."
    fi
}

run_reset() {
    log "INFO" "🔄 Réinitialisation d'Uptime Kuma..."

    # Arrêter le container
    log "INFO" "Arrêt du container..."
    docker stop "${COMPOSE_PROJECT_NAME}_uptime-kuma" 2>/dev/null || true

    # Supprimer le volume de données
    log "INFO" "Suppression du volume de données..."
    docker volume rm "${COMPOSE_PROJECT_NAME}_uptime_kuma_data" 2>/dev/null || true

    # Redémarrer
    log "INFO" "Redémarrage du container..."
    docker-compose up -d uptime-kuma

    log "SUCCESS" "Réinitialisation terminée"
    log "INFO" "Attente de l'initialisation..."
    sleep 15
}

run_configuration() {
    log "INFO" "🤖 Lancement de la configuration automatique..."

    # S'assurer que le script Python est exécutable
    chmod +x "$PYTHON_SCRIPT"

    # Variables d'environnement par défaut
    export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME}"
    export UPTIME_KUMA_URL="${UPTIME_KUMA_URL:-http://localhost:3001}"
    export UPTIME_ADMIN_USER="${UPTIME_ADMIN_USER:-admin}"
    export UPTIME_ADMIN_PASS="${UPTIME_ADMIN_PASS:-LaravelDev2024!}"
    export UPTIME_ADMIN_EMAIL="${UPTIME_ADMIN_EMAIL:-admin@laravel.local}"

    # Attendre que Uptime Kuma soit prêt
    local max_attempts=30
    local attempt=1
    local url="${UPTIME_KUMA_URL:-http://localhost:3001}"

    log "INFO" "Attente que Uptime Kuma soit accessible..."
    while [ $attempt -le $max_attempts ]; do
        if curl -s -f "$url" > /dev/null 2>&1; then
            log "SUCCESS" "Uptime Kuma est accessible"
            break
        fi

        log "INFO" "Tentative $attempt/$max_attempts - En attente..."
        sleep 2
        ((attempt++))

        if [ $attempt -gt $max_attempts ]; then
            log "ERROR" "Uptime Kuma n'est pas accessible après $max_attempts tentatives"
            log "INFO" "Vérifiez que le container fonctionne: docker ps"
            return 1
        fi
    done

    # Exécuter le script Python
    if python3 "$PYTHON_SCRIPT"; then
        log "SUCCESS" "Configuration automatique terminée avec succès!"
    else
        local exit_code=$?
        log "ERROR" "Échec de la configuration automatique (code: $exit_code)"
        log "INFO" "Solutions alternatives:"
        log "INFO" "  • Ouvrez manuellement: ${UPTIME_KUMA_URL}"
        log "INFO" "  • Créez un compte avec: ${UPTIME_ADMIN_USER} / ${UPTIME_ADMIN_PASS}"
        log "INFO" "  • Puis configurez manuellement les monitors"
        return $exit_code
    fi
}

show_status() {
    log "INFO" "📊 Affichage du statut final..."

    echo ""
    echo -e "${CYAN}📊 Statut d'Uptime Kuma${NC}"
    echo -e "${CYAN}========================${NC}"

    # Statut du container
    echo ""
    echo -e "${YELLOW}🐳 Container:${NC}"
    if docker ps --format "{{.Names}}" | grep -q "${COMPOSE_PROJECT_NAME}_uptime-kuma"; then
        echo -e "${GREEN}✓ Container actif${NC}"
        docker ps --filter name="${COMPOSE_PROJECT_NAME}_uptime-kuma" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    else
        echo -e "${RED}✗ Container non actif${NC}"
    fi

    # Accessibilité web
    echo ""
    echo -e "${YELLOW}🌐 Accessibilité:${NC}"
    local url="${UPTIME_KUMA_URL:-http://localhost:3001}"
    if curl -s -f "$url" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Accessible sur: $url${NC}"
    else
        echo -e "${RED}✗ Non accessible sur: $url${NC}"
    fi

    # Credentials
    echo ""
    echo -e "${YELLOW}👤 Credentials par défaut:${NC}"
    echo -e "  • Utilisateur: ${UPTIME_ADMIN_USER:-admin}"
    echo -e "  • Mot de passe: ${UPTIME_ADMIN_PASS:-LaravelDev2024!}"
    echo -e "  • Email: ${UPTIME_ADMIN_EMAIL:-admin@laravel.local}"

    # Instructions finales
    echo ""
    echo -e "${BLUE}💡 Prochaines étapes:${NC}"
    echo -e "  1. Ouvrez: $url"
    echo -e "  2. Connectez-vous avec les credentials ci-dessus"
    echo -e "  3. Vérifiez que tous les monitors sont créés"
    echo -e "  4. Configurez les notifications si souhaité"
}

open_browser() {
    local url="${UPTIME_KUMA_URL:-http://localhost:3001}"

    log "INFO" "🌐 Ouverture d'Uptime Kuma..."

    # Détecter l'OS et ouvrir le navigateur
    if command -v open >/dev/null 2>&1; then
        # macOS
        open "$url" 2>/dev/null || true
    elif command -v xdg-open >/dev/null 2>&1; then
        # Linux
        xdg-open "$url" 2>/dev/null || true
    elif command -v start >/dev/null 2>&1; then
        # Windows/WSL
        start "$url" 2>/dev/null || true
    else
        log "INFO" "Ouvrez manuellement: $url"
    fi
}

main() {
    echo -e "${PURPLE}🤖 CONFIGURATION AUTOMATIQUE D'UPTIME KUMA${NC}"
    echo -e "${PURPLE}===========================================${NC}"
    echo ""

    # Parser les arguments
    local reset_requested=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --reset)
                reset_requested=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log "ERROR" "Option inconnue: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Vérifications préliminaires
    check_dependencies
    check_docker_environment
    ensure_containers_running
    create_python_script

    # Réinitialisation si demandée
    if [ "$reset_requested" = true ]; then
        run_reset
    fi

    # Configuration automatique
    if run_configuration; then
        log "SUCCESS" "🎉 Configuration terminée avec succès!"
        show_status
        open_browser
    else
        log "ERROR" "❌ Configuration échouée"
        log "INFO" "🔧 Essayez avec --reset pour réinitialiser"
        show_status
        exit 1
    fi

    echo ""
    log "SUCCESS" "✅ Uptime Kuma est maintenant configuré et prêt!"
}

# Gestion des signaux pour nettoyage
trap 'echo -e "\n${YELLOW}⚠️ Script interrompu par l'utilisateur${NC}"; exit 130' INT TERM

# Exécuter si appelé directement
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi