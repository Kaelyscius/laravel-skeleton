#!/bin/bash

# =============================================================================
# OUTILS DE DIAGNOSTIC UNIFIÉS - FUSION INTELLIGENTE DE 4 SCRIPTS
# =============================================================================
#
# Fusion de :
# - check-php84-extensions.sh     (95 lignes)
# - quick-laravel-test.sh         (149 lignes) 
# - test-package-compatibility.sh (112 lignes)
# - test-laravel-install.sh       (86 lignes)
#
# Usage: ./scripts/diagnostic-tools.sh [--extensions|--quick-test|--packages|--install-test|--all]
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

log() {
    local level=$1
    shift
    local message="$*"
    
    case $level in
        "INFO")  echo -e "${BLUE}ℹ️  $message${NC}" ;;
        "WARN")  echo -e "${YELLOW}⚠️  $message${NC}" ;;
        "SUCCESS") echo -e "${GREEN}✅ $message${NC}" ;;
        "ERROR") echo -e "${RED}❌ $message${NC}" ;;
        "STEP") echo -e "${CYAN}🚀 $message${NC}" ;;
    esac
}

# =============================================================================
# FONCTION 1 : VÉRIFICATION EXTENSIONS PHP (Ex check-php84-extensions.sh)
# =============================================================================
check_php84_extensions() {
    echo ""
    log "STEP" "🔍 Vérification des extensions PHP 8.4 dans le container"
    echo ""
    
    # Extensions compilées manuellement
    compiled_extensions=("gd" "pdo" "pdo_mysql" "mysqli" "zip" "intl" "opcache" "bcmath" "xml" "dom" "xmlwriter" "xmlreader" "simplexml" "mbstring" "exif" "pcntl" "sockets")

    # Extensions intégrées par défaut dans PHP 8.4
    builtin_extensions=("tokenizer" "ctype" "fileinfo" "iconv" "json" "libxml" "openssl" "pcre" "reflection" "spl" "standard")

    # Extensions PECL
    pecl_extensions=("redis" "apcu" "xdebug" "imagick")

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
    log "INFO" "⚡ Extensions PECL (Redis, APCu, Xdebug, Imagick):"
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
    else
        log "ERROR" "🚨 Des extensions critiques sont manquantes"
    fi

    echo ""
    log "INFO" "🐘 Version PHP:"
    docker-compose exec -T php php -v | head -1
    
    return $([ "$all_critical_ok" = true ] && echo 0 || echo 1)
}

# =============================================================================
# FONCTION 2 : TEST RAPIDE LARAVEL (Ex quick-laravel-test.sh)
# =============================================================================
quick_laravel_test() {
    echo ""
    log "STEP" "🚀 Test rapide Laravel 12 + PHP 8.4 + Extensions"
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
        return 1
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
        return 1
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

    # 5. Nettoyage
    docker-compose exec -T php rm -rf /tmp/test-php84.json 2>/dev/null || true

    echo ""
    log "SUCCESS" "🎉 Test rapide terminé !"
    return 0
}

# =============================================================================
# FONCTION 3 : TEST COMPATIBILITÉ PACKAGES (Ex test-package-compatibility.sh)
# =============================================================================
test_package_compatibility() {
    echo ""
    log "STEP" "🧪 Test de compatibilité des packages avec Laravel 12 + PHP 8.4"
    echo ""

    # Source des fonctions (si disponible)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
        source "$SCRIPT_DIR/lib/common.sh"
    fi

    # Packages problématiques identifiés
    problematic_packages=(
        "beyondcode/laravel-query-detector"
        "driftingly/rector-laravel"
    )

    log "INFO" "📦 Test des packages problématiques:"

    for package in "${problematic_packages[@]}"; do
        echo ""
        log "INFO" "Test: $package"
        
        # Test compatibilité Laravel (si fonctions disponibles)
        if command -v is_package_laravel_compatible &> /dev/null; then
            if is_package_laravel_compatible "$package" "development"; then
                log "SUCCESS" "✓ Compatible Laravel"
            else
                max_laravel=$(get_package_max_laravel_version "$package" "development")
                log "WARN" "✗ Laravel <= $max_laravel requis"
            fi
        else
            log "INFO" "ℹ️ Tests avancés non disponibles (lib/common.sh)"
        fi
    done

    echo ""
    log "INFO" "🔧 Test des packages compatibles:"

    # Packages qui devraient fonctionner
    compatible_packages=(
        "symplify/easy-coding-standard:^12.5"
        "rector/rector:^2.1"
        "nunomaduro/phpinsights:^2.13"
        "ivqonsanada/enlightn:^2.0"
        "pestphp/pest:^3.0"
    )

    for package_version in "${compatible_packages[@]}"; do
        package=$(echo "$package_version" | cut -d: -f1)
        version=$(echo "$package_version" | cut -d: -f2)
        
        echo ""
        log "INFO" "Test: $package"
        log "INFO" "Version: $version"
        
        # Test basic resolution
        if timeout 15 docker-compose exec -T php bash -c "
            cd /tmp && 
            echo '{\"require-dev\":{\"$package\":\"$version\"}}' > test.json &&
            composer install --dry-run --file=test.json --no-interaction --quiet &&
            rm -f test.json
        " >/dev/null 2>&1; then
            log "SUCCESS" "✓ Résolution OK"
        else
            log "WARN" "⚠️ Problème de résolution"
        fi
    done

    echo ""
    log "SUCCESS" "🎉 Test de compatibilité terminé !"
    return 0
}

# =============================================================================
# FONCTION 4 : TEST INSTALLATION LARAVEL (Ex test-laravel-install.sh)
# =============================================================================
test_laravel_install() {
    echo ""
    log "STEP" "🛠️ Test création Laravel 12"
    echo ""

    # Nettoyer
    docker-compose exec -T php rm -rf /tmp/laravel-test 2>/dev/null || true

    # Test création avec timeout
    log "INFO" "Création projet Laravel 12..."
    if timeout 60 docker-compose exec -T php bash -c 'cd /tmp && composer create-project --prefer-dist laravel/laravel laravel-test "12.*" --no-interaction --quiet'; then
        laravel_version=$(docker-compose exec -T php bash -c 'cd /tmp/laravel-test && php artisan --version --no-ansi' 2>/dev/null || echo "Version inconnue")
        log "SUCCESS" "✅ Laravel créé: $laravel_version"
        
        # Test ajout du fork Enlightn
        log "INFO" "Test installation fork Enlightn Laravel 12..."
        if timeout 30 docker-compose exec -T php bash -c 'cd /tmp/laravel-test && composer require --dev ivqonsanada/enlightn --no-interaction --quiet'; then
            log "SUCCESS" "✅ Fork Enlightn installé !"
        else
            log "WARN" "⚠️  Échec installation fork Enlightn"
        fi
    else
        log "ERROR" "❌ Échec création Laravel 12"
        return 1
    fi

    # Nettoyage
    docker-compose exec -T php rm -rf /tmp/laravel-test 2>/dev/null || true

    echo ""
    log "SUCCESS" "🎉 Test installation terminé !"
    return 0
}

# =============================================================================
# FONCTION PRINCIPALE ET INTERFACE EN LIGNE DE COMMANDE
# =============================================================================
show_usage() {
    echo ""
    echo "🔧 OUTILS DE DIAGNOSTIC UNIFIÉS"
    echo "================================"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --extensions     Vérifier les extensions PHP 8.4"
    echo "  --quick-test     Test rapide Laravel + PHP 8.4"
    echo "  --packages       Test compatibilité packages"
    echo "  --install-test   Test création Laravel 12"
    echo "  --all           Exécuter tous les tests"
    echo "  --help          Afficher cette aide"
    echo ""
    echo "Exemples:"
    echo "  $0 --extensions"
    echo "  $0 --quick-test"
    echo "  $0 --all"
    echo ""
}

main() {
    local option="${1:-}"
    
    case "$option" in
        "--extensions")
            check_php84_extensions
            ;;
        "--quick-test") 
            quick_laravel_test
            ;;
        "--packages")
            test_package_compatibility
            ;;
        "--install-test")
            test_laravel_install
            ;;
        "--all")
            echo ""
            log "STEP" "🎯 DIAGNOSTIC COMPLET"
            echo "================================================================="
            echo ""
            
            local all_passed=true
            
            check_php84_extensions || all_passed=false
            quick_laravel_test || all_passed=false  
            test_package_compatibility || all_passed=false
            test_laravel_install || all_passed=false
            
            echo ""
            echo "================================================================="
            if [ "$all_passed" = true ]; then
                log "SUCCESS" "🎉 TOUS LES TESTS RÉUSSIS !"
            else
                log "WARN" "⚠️  Certains tests ont échoué (vérifiez ci-dessus)"
            fi
            echo ""
            ;;
        "--help"|"-h"|"")
            show_usage
            ;;
        *)
            echo "❌ Option inconnue: $option"
            show_usage
            exit 1
            ;;
    esac
}

# Exécuter si script appelé directement
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi