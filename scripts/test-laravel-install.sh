#!/bin/bash

# =============================================================================
# SCRIPT DE TEST RAPIDE INSTALLATION LARAVEL
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

log "INFO" "🧪 Test rapide installation Laravel avec PHP 8.4"
echo ""

# 1. Vérifier les containers
log "INFO" "📦 Vérification des containers..."
if ! docker-compose ps | grep -q "Up"; then
    log "ERROR" "Containers non démarrés - lancement..."
    docker-compose up -d
    sleep 10
fi

# 2. Vérifier PHP et extensions
log "INFO" "🔍 Vérification de PHP et extensions..."
docker-compose exec php php -v
echo ""

log "INFO" "Extensions PHP critiques :"
for ext in dom xml xmlwriter xmlreader simplexml tokenizer ctype fileinfo iconv mbstring; do
    if docker-compose exec php php -m | grep -q "^$ext$"; then
        log "SUCCESS" "Extension $ext: installée"
    else
        log "ERROR" "Extension $ext: manquante"
    fi
done

# 3. Test Composer avec diagnostic
log "INFO" "🎵 Test Composer..."
docker-compose exec php composer --version
echo ""

# 4. Tester la résolution des packages problématiques
log "INFO" "🧪 Test résolution packages PHP 8.4..."

# Créer un composer.json test
docker-compose exec php bash -c 'cat > /tmp/test-packages.json << EOF
{
    "require-dev": {
        "symplify/easy-coding-standard": "^12.5",
        "rector/rector": "^2.1",
        "nunomaduro/phpinsights": "^2.13"
    },
    "minimum-stability": "stable",
    "prefer-stable": true
}
EOF'

# Test dry-run
if docker-compose exec php composer install --dry-run --working-dir=/tmp --file=/tmp/test-packages.json --no-interaction; then
    log "SUCCESS" "Résolution des packages OK !"
else
    log "WARN" "Problèmes de résolution détectés"
fi

# 5. Nettoyage
docker-compose exec php rm -f /tmp/test-packages.json

log "SUCCESS" "🎉 Test terminé !"
echo ""
log "INFO" "💡 Si tout est OK, lancez: make install-laravel"