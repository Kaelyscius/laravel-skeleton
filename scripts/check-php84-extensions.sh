#!/bin/bash

# =============================================================================
# SCRIPT DE VÉRIFICATION DES EXTENSIONS PHP 8.4
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
log "INFO" "🔍 Vérification des extensions PHP 8.4 dans le container"
echo ""

# Extensions compilées manuellement
compiled_extensions=("gd" "pdo" "pdo_mysql" "mysqli" "zip" "intl" "opcache" "bcmath" "xml" "dom" "xmlwriter" "xmlreader" "simplexml" "mbstring" "exif" "pcntl" "sockets")

# Extensions intégrées par défaut dans PHP 8.4
builtin_extensions=("tokenizer" "ctype" "fileinfo" "iconv" "json" "libxml" "openssl" "pcre" "reflection" "spl" "standard")

# Extensions PECL
pecl_extensions=("redis" "apcu" "xdebug")

log "INFO" "📦 Extensions compilées manuellement:"
for ext in "${compiled_extensions[@]}"; do
    if docker-compose exec -T php php -m | grep -q "^$ext$"; then
        log "SUCCESS" "✓ $ext"
    else
        log "ERROR" "✗ $ext MANQUANTE"
    fi
done

echo ""
log "INFO" "🔧 Extensions intégrées par défaut dans PHP 8.4:"
for ext in "${builtin_extensions[@]}"; do
    if docker-compose exec -T php php -m | grep -q "^$ext$"; then
        log "SUCCESS" "✓ $ext (intégrée)"
    else
        log "WARN" "⚠️  $ext non détectée"
    fi
done

echo ""
log "INFO" "⚡ Extensions PECL (Redis, APCu, Xdebug):"
for ext in "${pecl_extensions[@]}"; do
    if docker-compose exec -T php php -m | grep -q "^$ext$"; then
        log "SUCCESS" "✓ $ext"
    else
        log "WARN" "⚠️  $ext non installée"
    fi
done

echo ""
log "INFO" "📋 Résumé des extensions critiques pour outils qualité:"
critical_for_quality=("dom" "xml" "xmlwriter" "xmlreader" "tokenizer" "ctype" "fileinfo" "iconv" "mbstring")

all_critical_ok=true
for ext in "${critical_for_quality[@]}"; do
    if docker-compose exec -T php php -m | grep -q "^$ext$"; then
        log "SUCCESS" "✓ $ext (requis pour ECS/Rector/PHPInsights)"
    else
        log "ERROR" "✗ $ext MANQUANTE (critique)"
        all_critical_ok=false
    fi
done

echo ""
if [ "$all_critical_ok" = true ]; then
    log "SUCCESS" "🎉 Toutes les extensions critiques sont disponibles !"
    log "INFO" "💡 Prêt pour l'installation Laravel avec outils qualité"
else
    log "ERROR" "🚨 Des extensions critiques sont manquantes"
    log "INFO" "💡 Vérifiez le build du container PHP"
fi

echo ""
log "INFO" "🐘 Version PHP:"
docker-compose exec -T php php -v | head -1