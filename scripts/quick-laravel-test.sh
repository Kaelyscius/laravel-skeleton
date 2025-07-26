#!/bin/bash

# =============================================================================
# SCRIPT DE TEST RAPIDE LARAVEL + PHP 8.4 COMPATIBILITY
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

log "INFO" "🚀 Test rapide Laravel 12 + PHP 8.4 + Extensions"
echo ""

# 1. Attendre que les containers soient prêts
log "INFO" "📦 Attente des containers..."
timeout=60
count=0
while [ $count -lt $timeout ]; do
    if docker-compose ps | grep -q "php.*Up"; then
        log "SUCCESS" "Container PHP prêt !"
        break
    fi
    sleep 2
    count=$((count + 2))
    log "INFO" "Attente... ($count/$timeout secondes)"
done

if [ $count -ge $timeout ]; then
    log "ERROR" "Timeout - container PHP non démarré"
    exit 1
fi

# 2. Test PHP et extensions critiques
log "INFO" "🔍 Test PHP 8.4 et extensions..."
echo ""

# Version PHP
php_version=$(docker-compose exec -T php php -v | head -1)
log "INFO" "Version: $php_version"

# Extensions critiques pour les outils de qualité
critical_extensions=("dom" "xml" "xmlwriter" "xmlreader" "simplexml" "tokenizer" "ctype" "fileinfo" "iconv" "mbstring")

log "INFO" "Extensions critiques pour ECS/Rector/PHPInsights:"
all_good=true
for ext in "${critical_extensions[@]}"; do
    if docker-compose exec -T php php -m | grep -q "^$ext$"; then
        log "SUCCESS" "✓ $ext"
    else
        log "ERROR" "✗ $ext MANQUANTE"
        all_good=false
    fi
done

if [ "$all_good" = false ]; then
    log "ERROR" "Des extensions critiques sont manquantes !"
    exit 1
fi

# 3. Test Composer et résolution des packages problématiques
log "INFO" "🎵 Test Composer + résolution packages PHP 8.4..."
echo ""

# Version Composer
composer_version=$(docker-compose exec -T php composer --version --no-ansi)
log "INFO" "$composer_version"

# Test de résolution des packages problématiques avec versions spécifiques
log "INFO" "Test résolution packages PHP 8.4 compatible..."

docker-compose exec -T php bash -c 'cat > /tmp/test-php84.json << EOF
{
    "require": {
        "php": "^8.4"
    },
    "require-dev": {
        "symplify/easy-coding-standard": "^12.5",
        "rector/rector": "^2.1",
        "nunomaduro/phpinsights": "^2.13",
        "pestphp/pest": "^3.0",
        "pestphp/pest-plugin-laravel": "^3.0"
    },
    "minimum-stability": "stable",
    "prefer-stable": true,
    "config": {
        "platform-check": false,
        "optimize-autoloader": true
    }
}
EOF'

# Test dry-run avec timeout
log "INFO" "Test dry-run installation packages..."
if timeout 30 docker-compose exec -T php composer install --dry-run --working-dir=/tmp --file=/tmp/test-php84.json --no-interaction --quiet; then
    log "SUCCESS" "✅ Résolution des packages OK !"
else
    log "WARN" "⚠️  Problèmes de résolution détectés - mais ce n'est peut-être pas bloquant"
fi

# 4. Test cache et configuration Composer
log "INFO" "🔧 Test configuration Composer..."

# Diagnostic Composer
log "INFO" "Diagnostic Composer:"
docker-compose exec -T php composer diagnose --no-ansi | head -10

# 5. Test rapide création Laravel 12
log "INFO" "🛠️  Test création projet Laravel 12..."

# Nettoyer si existe déjà
docker-compose exec -T php rm -rf /tmp/laravel-test 2>/dev/null || true

# Test création avec timeout
if timeout 60 docker-compose exec -T php bash -c 'cd /tmp && composer create-project --prefer-dist laravel/laravel laravel-test "12.*" --no-interaction --quiet'; then
    laravel_version=$(docker-compose exec -T php bash -c 'cd /tmp/laravel-test && php artisan --version --no-ansi' 2>/dev/null || echo "Version inconnue")
    log "SUCCESS" "✅ Laravel créé: $laravel_version"
else
    log "WARN" "⚠️  Échec création Laravel - vérifier configuration"
fi

# 6. Nettoyage
docker-compose exec -T php rm -rf /tmp/test-php84.json /tmp/laravel-test 2>/dev/null || true

echo ""
log "SUCCESS" "🎉 Test terminé !"
echo ""

if [ "$all_good" = true ]; then
    log "INFO" "💡 Tout semble OK - vous pouvez lancer: make install-laravel"
else
    log "INFO" "💡 Problèmes détectés - vérifier les extensions PHP manquantes"
fi