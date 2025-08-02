#!/bin/bash

# =============================================================================
# VÉRIFICATION AUTOMATIQUE COMPATIBILITÉ PACKAGES LARAVEL 12
# =============================================================================
#
# Ce script vérifie périodiquement si les packages incompatibles avec Laravel 12
# sont devenus compatibles et les installe automatiquement.
#
# Usage:
#   ./scripts/check-package-compatibility.sh [--auto-install]
#
# Options:
#   --auto-install    Installer automatiquement les packages devenus compatibles
#   --list           Lister seulement les packages à vérifier
#   --help           Afficher cette aide
#
# =============================================================================

set -e

# Couleurs pour les logs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# Charger les dépendances
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
    source "$SCRIPT_DIR/lib/common.sh"
fi

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")  echo -e "${BLUE}[INFO $timestamp]${NC} $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN $timestamp]${NC} $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS $timestamp]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR $timestamp]${NC} $message" ;;
    esac
}

# Packages incompatibles connus avec Laravel 12
readonly INCOMPATIBLE_PACKAGES=(
    "beyondcode/laravel-query-detector"
    "driftingly/rector-laravel"
)

# Fonction d'aide
show_help() {
    echo -e "${CYAN}🔍 Vérification automatique compatibilité packages Laravel 12${NC}"
    echo -e "${CYAN}==========================================================${NC}"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --auto-install    Installer automatiquement les packages devenus compatibles"
    echo "  --list           Lister seulement les packages à vérifier"
    echo "  --help           Afficher cette aide"
    echo ""
    echo "Exemples:"
    echo "  $0                    # Vérifier seulement (dry-run)"
    echo "  $0 --auto-install    # Vérifier et installer automatiquement"
    echo "  $0 --list           # Lister les packages incompatibles"
    echo ""
    echo "Packages actuellement incompatibles avec Laravel 12:"
    for package in "${INCOMPATIBLE_PACKAGES[@]}"; do
        echo "  • $package"
    done
}

# Lister les packages incompatibles
list_packages() {
    echo -e "${CYAN}📦 Packages incompatibles avec Laravel 12:${NC}"
    echo ""
    
    for package in "${INCOMPATIBLE_PACKAGES[@]}"; do
        echo -e "  ${YELLOW}•${NC} $package"
        
        # Vérifier s'il est déjà installé
        if [ -f "composer.json" ] && grep -q "\"$package\"" composer.json; then
            echo -e "    ${GREEN}✓ Actuellement installé${NC}"
        else
            echo -e "    ${RED}✗ Non installé${NC}"
        fi
    done
    echo ""
}

# Vérifier la compatibilité des packages
check_compatibility() {
    local auto_install="${1:-false}"
    
    log "INFO" "🔄 Démarrage vérification compatibilité Laravel 12..."
    
    if [ ! -f "composer.json" ]; then
        log "ERROR" "Fichier composer.json non trouvé"
        return 1
    fi
    
    local compatible_packages=()
    local tested_count=0
    
    for package in "${INCOMPATIBLE_PACKAGES[@]}"; do
        tested_count=$((tested_count + 1))
        log "INFO" "Test $tested_count/${#INCOMPATIBLE_PACKAGES[@]}: $package"
        
        # Vérifier si déjà installé
        if grep -q "\"$package\"" composer.json; then
            log "INFO" "✓ $package déjà installé"
            continue
        fi
        
        # Tester la compatibilité
        if check_package_laravel12_compatibility "$package"; then
            log "SUCCESS" "🎉 $package est maintenant compatible avec Laravel 12!"
            compatible_packages+=("$package")
            
            if [ "$auto_install" = true ]; then
                log "INFO" "📦 Installation de $package..."
                if composer require --dev "$package" --no-interaction; then
                    log "SUCCESS" "✅ $package installé avec succès"
                else
                    log "WARN" "⚠️ Installation de $package échouée"
                fi
            fi
        else
            log "INFO" "⏳ $package pas encore compatible"
        fi
        
        echo ""
    done
    
    # Résumé
    echo -e "${CYAN}📊 RÉSUMÉ:${NC}"
    echo "• Packages testés: $tested_count"
    echo "• Packages compatibles: ${#compatible_packages[@]}"
    
    if [ ${#compatible_packages[@]} -gt 0 ]; then
        echo "• Nouveaux packages compatibles:"
        for package in "${compatible_packages[@]}"; do
            echo "  - $package"
        done
        
        if [ "$auto_install" = false ]; then
            echo ""
            log "INFO" "💡 Relancez avec --auto-install pour installer automatiquement"
        fi
    else
        echo "• Aucun nouveau package compatible trouvé"
    fi
    echo ""
    
    return 0
}

# Fonction principale
main() {
    local auto_install=false
    local list_only=false
    
    # Parser les arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --auto-install)
                auto_install=true
                shift
                ;;
            --list)
                list_only=true
                shift
                ;;
            --help|-h)
                show_help
                return 0
                ;;
            *)
                echo "Argument inconnu: $1"
                show_help
                return 1
                ;;
        esac
    done
    
    echo -e "${CYAN}🔍 Vérification automatique compatibilité Laravel 12${NC}"
    echo -e "${CYAN}=================================================${NC}"
    echo ""
    
    if [ "$list_only" = true ]; then
        list_packages
        return 0
    fi
    
    # Vérifier l'environnement
    if ! command -v composer &> /dev/null; then
        log "ERROR" "Composer non trouvé"
        return 1
    fi
    
    # Changer vers le répertoire src si nécessaire
    if [ -d "src" ] && [ -f "src/composer.json" ]; then
        log "INFO" "🔄 Changement vers le répertoire src/"
        cd src
    fi
    
    # Lancer la vérification
    check_compatibility "$auto_install"
    
    log "SUCCESS" "✅ Vérification terminée"
}

# Exécuter seulement si le script est appelé directement
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi