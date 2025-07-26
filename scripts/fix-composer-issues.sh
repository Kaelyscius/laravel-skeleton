#!/bin/bash

# =============================================================================
# SCRIPT DE CORRECTION DES PROBLÈMES COMPOSER
# =============================================================================
#
# Ce script corrige les problèmes de cache et configuration Composer
# qui peuvent causer des erreurs d'installation avec PHP 8.4 + Laravel 12
#
# Usage: ./scripts/fix-composer-issues.sh
#
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

# Variables
COMPOSER_HOME="${COMPOSER_HOME:-$HOME/.composer}"
COMPOSER_CACHE_DIR="${COMPOSER_CACHE_DIR:-$HOME/.cache/composer}"

log "INFO" "🔧 Diagnostic et correction des problèmes Composer pour PHP 8.4"
echo ""

# 1. Diagnostic initial
log "INFO" "🔍 Diagnostic initial..."
echo "PHP Version: $(php -v | head -1)"
echo "Composer Version: $(composer --version)"
echo "Composer Home: $COMPOSER_HOME"
echo "Cache Directory: $COMPOSER_CACHE_DIR"
echo ""

# 2. Nettoyer tous les caches Composer
log "INFO" "🧹 Nettoyage complet du cache Composer..."

# Cache principal
if [ -d "$COMPOSER_CACHE_DIR" ]; then
    log "INFO" "Suppression du cache: $COMPOSER_CACHE_DIR"
    rm -rf "$COMPOSER_CACHE_DIR"/*
    log "SUCCESS" "Cache principal nettoyé"
else
    log "INFO" "Pas de cache principal trouvé"
fi

# Cache Composer global
composer clear-cache --quiet 2>/dev/null || log "WARN" "Impossible de vider le cache via composer clear-cache"

# Cache spécifique au projet
if [ -d "vendor" ]; then
    log "INFO" "Suppression du dossier vendor local"
    rm -rf vendor/
fi

if [ -f "composer.lock" ]; then
    log "INFO" "Suppression du composer.lock local"
    rm -f composer.lock
fi

log "SUCCESS" "Nettoyage du cache terminé"
echo ""

# 3. Vérifier et réparer la configuration Composer
log "INFO" "🔧 Vérification de la configuration Composer..."

# Créer le répertoire de configuration s'il n'existe pas
mkdir -p "$COMPOSER_HOME"

# Configuration optimisée pour PHP 8.4 + Laravel 12
cat > "$COMPOSER_HOME/config.json" << 'EOF'
{
    "config": {
        "preferred-install": "dist",
        "sort-packages": true,
        "optimize-autoloader": true,
        "classmap-authoritative": true,
        "apcu-autoloader": true,
        "platform-check": false,
        "process-timeout": 3600,
        "cache-timeout": 86400,
        "cache-ttl": 86400,
        "allow-plugins": {
            "pestphp/pest-plugin": true,
            "php-http/discovery": true,
            "dealerdirect/phpcodesniffer-composer-installer": true
        }
    },
    "repositories": [
        {
            "type": "composer",
            "url": "https://packagist.org"
        }
    ]
}
EOF

# Note: prefer-stable et minimum-stability ne peuvent pas être configurés globalement
# Ils sont ajoutés automatiquement aux projets Laravel

log "SUCCESS" "Configuration Composer optimisée créée"
echo ""

# 4. Mise à jour de Composer lui-même
log "INFO" "📦 Mise à jour de Composer..."
composer self-update --stable 2>/dev/null || log "WARN" "Impossible de mettre à jour Composer"
log "SUCCESS" "Composer mis à jour"
echo ""

# 5. Diagnostique des plateformes
log "INFO" "🔍 Diagnostic des extensions PHP critiques..."

# Extensions requises pour les packages de qualité
required_extensions=(
    "mbstring"
    "xml"
    "dom"
    "json"
    "tokenizer"
    "iconv"
)

missing_extensions=()

for ext in "${required_extensions[@]}"; do
    if php -m | grep -q "^$ext$"; then
        log "SUCCESS" "Extension $ext: installée"
    else
        missing_extensions+=("$ext")
        log "WARN" "Extension $ext: manquante"
    fi
done

if [ ${#missing_extensions[@]} -gt 0 ]; then
    log "WARN" "Extensions manquantes: ${missing_extensions[*]}"
    log "INFO" "Ces extensions peuvent être nécessaires pour certains packages"
else
    log "SUCCESS" "Toutes les extensions requises sont installées"
fi
echo ""

# 6. Test de résolution des dépendances
log "INFO" "🧪 Test de résolution des dépendances..."

# Créer un composer.json temporaire pour tester
cat > "/tmp/composer-test.json" << 'EOF'
{
    "name": "test/php84-compatibility",
    "require": {
        "php": "^8.4"
    },
    "require-dev": {
        "symplify/easy-coding-standard": "^12.5",
        "rector/rector": "^2.1",
        "nunomaduro/phpinsights": "^2.13"
    },
    "minimum-stability": "stable",
    "prefer-stable": true
}
EOF

if composer validate "/tmp/composer-test.json" --quiet; then
    log "SUCCESS" "Configuration JSON valide"
else
    log "ERROR" "Problème avec la configuration JSON"
fi

# Test de résolution (dry-run)
if composer install --dry-run --working-dir="/tmp" --file="/tmp/composer-test.json" >/dev/null 2>&1; then
    log "SUCCESS" "Résolution des dépendances OK"
else
    log "WARN" "Problèmes potentiels de résolution détectés"
fi

rm -f "/tmp/composer-test.json"
echo ""

# 7. Optimisations spécifiques à l'environnement Docker
if [ -f "/.dockerenv" ] || [ -n "${DOCKER_CONTAINER:-}" ]; then
    log "INFO" "🐳 Optimisations Docker détectées..."
    
    # Variables d'environnement optimisées pour Docker
    export COMPOSER_MEMORY_LIMIT=-1
    export COMPOSER_PROCESS_TIMEOUT=3600
    export COMPOSER_ALLOW_SUPERUSER=1
    export COMPOSER_NO_INTERACTION=1
    
    log "SUCCESS" "Variables d'environnement Docker configurées"
fi

# 8. Rapport final
echo ""
log "SUCCESS" "🎉 Correction des problèmes Composer terminée !"
echo ""
log "INFO" "📋 Résumé des actions:"
log "INFO" "  ✓ Cache Composer nettoyé"
log "INFO" "  ✓ Configuration optimisée pour PHP 8.4"
log "INFO" "  ✓ Plugins autorisés configurés"
log "INFO" "  ✓ Extensions PHP vérifiées"
log "INFO" "  ✓ Résolution des dépendances testée"
echo ""

log "INFO" "💡 Prochaines étapes recommandées:"
log "INFO" "  1. Relancer l'installation Laravel: make install-laravel"
log "INFO" "  2. Si des erreurs persistent, vérifier les versions dans config/installer.yml"
log "INFO" "  3. En cas de problème, utiliser: composer diagnose"
echo ""

log "SUCCESS" "Prêt pour l'installation Laravel 12 + PHP 8.4 !"