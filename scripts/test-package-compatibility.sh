#!/bin/bash

# =============================================================================
# TEST DE COMPATIBILITÉ DES PACKAGES
# =============================================================================

set -e

# Couleurs pour les logs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    local level=$1
    shift
    local message="$*"
    
    case $level in
        "INFO")  echo -e "${BLUE}ℹ️  $message${NC}" ;;
        "WARN")  echo -e "${YELLOW}⚠️  $message${NC}" ;;
        "SUCCESS") echo -e "${GREEN}✅ $message${NC}" ;;
        "ERROR") echo -e "${RED}❌ $message${NC}" ;;
    esac
}

echo ""
log "INFO" "🧪 Test de compatibilité des packages avec Laravel 12 + PHP 8.4"
echo ""

# Source des fonctions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# Packages problématiques identifiés
problematic_packages=(
    "beyondcode/laravel-query-detector"
    "driftingly/rector-laravel"
)

log "INFO" "📦 Test des packages problématiques:"

for package in "${problematic_packages[@]}"; do
    echo ""
    log "INFO" "Test: $package"
    
    # Test compatibilité Laravel
    if is_package_laravel_compatible "$package" "development"; then
        log "SUCCESS" "✓ Compatible Laravel"
    else
        max_laravel=$(get_package_max_laravel_version "$package" "development")
        log "WARN" "✗ Laravel <= $max_laravel requis"
    fi
    
    # Test compatibilité PHP
    if is_package_php_compatible "$package" "development"; then
        log "SUCCESS" "✓ Compatible PHP 8.4"
    else
        required_php=$(get_package_php_version "$package" "development")
        log "WARN" "✗ PHP $required_php requis"
    fi
    
    # Test si requis
    if is_package_required "$package" "development"; then
        log "WARN" "⚠️ Package REQUIS"
    else
        log "INFO" "ℹ️ Package optionnel"
    fi
done

echo ""
log "INFO" "🔧 Test des packages compatibles:"

# Packages qui devraient fonctionner
compatible_packages=(
    "symplify/easy-coding-standard"
    "rector/rector"
    "nunomaduro/phpinsights"
    "ivqonsanada/enlightn"
    "pestphp/pest"
)

for package in "${compatible_packages[@]}"; do
    echo ""
    log "INFO" "Test: $package"
    
    # Test compatibilité Laravel
    if is_package_laravel_compatible "$package" "development"; then
        log "SUCCESS" "✓ Compatible Laravel 12"
    else
        max_laravel=$(get_package_max_laravel_version "$package" "development")
        log "ERROR" "✗ Laravel <= $max_laravel requis"
    fi
    
    # Test compatibilité PHP
    if is_package_php_compatible "$package" "development"; then
        log "SUCCESS" "✓ Compatible PHP 8.4"
    else
        required_php=$(get_package_php_version "$package" "development")
        log "ERROR" "✗ PHP $required_php requis"
    fi
    
    # Version
    version=$(get_package_version "$package" "development")
    log "INFO" "Version: $version"
done

echo ""
log "SUCCESS" "🎉 Test de compatibilité terminé !"
echo ""
log "INFO" "💡 Les packages incompatibles seront automatiquement ignorés lors de l'installation"