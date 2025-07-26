#!/bin/bash

# =============================================================================
# SCRIPT DE VALIDATION COMPLÈTE - TOUTES LES CORRECTIONS
# =============================================================================

set -e

# Couleurs pour les logs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

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
        "STEP") echo -e "${CYAN}[STEP $timestamp]${NC} $message" ;;
        "CHECK") echo -e "${PURPLE}[CHECK $timestamp]${NC} $message" ;;
    esac
}

echo ""
echo "================================================================="
log "STEP" "🔍 VALIDATION COMPLÈTE DES CORRECTIONS PHP 8.4 + LARAVEL 12"
echo "================================================================="
echo ""

# Variables de validation
total_checks=0
passed_checks=0

check() {
    local name="$1"
    local command="$2"
    local is_critical="${3:-false}"
    
    ((total_checks++))
    log "CHECK" "Test: $name"
    
    if eval "$command" >/dev/null 2>&1; then
        log "SUCCESS" "✅ $name"
        ((passed_checks++))
        return 0
    else
        if [ "$is_critical" = "true" ]; then
            log "ERROR" "❌ $name (CRITIQUE)"
        else
            log "WARN" "⚠️ $name (non-critique)"
        fi
        return 1
    fi
}

check_container() {
    local container="$1"
    docker-compose ps | grep -q "$container.*Up"
}

check_php_extension() {
    local ext="$1"
    docker-compose exec -T php php -m | grep -q "^$ext$"
}

check_package_compatibility() {
    local package="$1"
    local version="$2"
    
    # Test dry-run d'installation
    docker-compose exec -T php bash -c "
        cd /tmp && 
        echo '{\"require-dev\":{\"$package\":\"$version\"}}' > test.json &&
        composer install --dry-run --file=test.json --no-interaction --quiet &&
        rm -f test.json
    "
}

# 1. TESTS CONTAINERS
log "STEP" "🐳 Tests des containers Docker"
check "Container PHP" "check_container php" true
check "Container MariaDB" "check_container mariadb" true
check "Container Redis" "check_container redis" false

# 2. TESTS PHP ET EXTENSIONS
log "STEP" "🐘 Tests PHP 8.4 et extensions"
check "PHP 8.4" "docker-compose exec -T php php -v | grep -q 'PHP 8.4'" true

# Extensions critiques pour outils qualité
critical_extensions=("dom" "xml" "xmlwriter" "xmlreader" "tokenizer" "ctype" "fileinfo" "iconv" "mbstring")
for ext in "${critical_extensions[@]}"; do
    check "Extension $ext" "check_php_extension $ext" true
done

# Extensions ajoutées
added_extensions=("imagick" "xdebug")
for ext in "${added_extensions[@]}"; do
    check "Extension $ext" "check_php_extension $ext" false
done

# 3. TESTS ENVIRONNEMENT DOCKER
log "STEP" "🔧 Tests variables environnement"
check "Variable DOCKER_CONTAINER" "docker-compose exec -T php printenv DOCKER_CONTAINER" false
check "Variable CONTAINER_TYPE" "docker-compose exec -T php printenv CONTAINER_TYPE" false

# 4. TESTS NODE.JS
log "STEP" "🟢 Tests Node.js"
check "Node.js disponible" "docker-compose exec -T php node --version" false
check "NPM disponible" "docker-compose exec -T php npm --version" false

# 5. TESTS COMPOSER
log "STEP" "🎵 Tests Composer et configurations"
check "Composer fonctionnel" "docker-compose exec -T php composer --version" true
check "Configuration Composer" "docker-compose exec -T php test -f /var/composer/config.json" false

# Script de correction Composer
if [ -f "./scripts/fix-composer-issues.sh" ]; then
    check "Script fix-composer-issues.sh" "test -x ./scripts/fix-composer-issues.sh" false
fi

# 6. TESTS COMPATIBILITÉ PACKAGES PHP 8.4
log "STEP" "📦 Tests compatibilité packages PHP 8.4"

# Packages avec versions corrigées
declare -A packages=(
    ["symplify/easy-coding-standard"]="^12.5"
    ["rector/rector"]="^2.1"
    ["nunomaduro/phpinsights"]="^2.13"
    ["ivqonsanada/enlightn"]="^2.0"
)

for package in "${!packages[@]}"; do
    version="${packages[$package]}"
    check "Compatibilité $package:$version" "check_package_compatibility $package $version" false
done

# 7. TESTS BASE DE DONNÉES
log "STEP" "🗄️ Tests base de données"
check "Connexion MariaDB" "docker-compose exec -T mariadb mysql -uroot -p\${DB_ROOT_PASSWORD} -e 'SELECT 1;'" true

# Test base de données de test
db_test_name="${DB_DATABASE:-laravel}_test"
check "Base données test existe" "docker-compose exec -T mariadb mysql -uroot -p\${DB_ROOT_PASSWORD} -e 'USE $db_test_name; SELECT 1;'" false

# Script de configuration DB test
if [ -f "./scripts/configure-test-database.sh" ]; then
    check "Script configure-test-database.sh" "test -x ./scripts/configure-test-database.sh" false
fi

# 8. TESTS LARAVEL 12
log "STEP" "🛠️ Tests Laravel 12"

# Test création projet Laravel 12
log "CHECK" "Test création Laravel 12 (peut prendre du temps)..."
if timeout 120 docker-compose exec -T php bash -c "
    cd /tmp && 
    rm -rf laravel12-validation-test 2>/dev/null &&
    composer create-project --prefer-dist laravel/laravel laravel12-validation-test '12.*' --no-interaction --quiet &&
    cd laravel12-validation-test &&
    php artisan --version | grep -q 'Laravel Framework 12' &&
    rm -rf /tmp/laravel12-validation-test
"; then
    log "SUCCESS" "✅ Création Laravel 12"
    ((passed_checks++))
else
    log "ERROR" "❌ Création Laravel 12 (CRITIQUE)"
fi
((total_checks++))

# 9. TESTS SCRIPTS ET OUTILS
log "STEP" "⚙️ Tests scripts et outils"

# Scripts créés/modifiés
scripts_to_check=(
    "./scripts/check-php84-extensions.sh"
    "./scripts/quick-laravel-test.sh"
    "./scripts/test-installation-complete.sh"
    "./scripts/validate-all-fixes.sh"
)

for script in "${scripts_to_check[@]}"; do
    if [ -f "$script" ]; then
        check "Script $(basename $script)" "test -x $script" false
    fi
done

# Commande Makefile
check "Commande make install-laravel-php84" "grep -q 'install-laravel-php84' Makefile" false

# 10. RÉSUMÉ FINAL
echo ""
echo "================================================================="
log "STEP" "📊 RÉSULTATS DE LA VALIDATION"
echo "================================================================="
echo ""

# Calcul pourcentage
percentage=$((passed_checks * 100 / total_checks))

log "INFO" "Tests passés: $passed_checks/$total_checks ($percentage%)"
echo ""

if [ $percentage -ge 90 ]; then
    log "SUCCESS" "🎉 EXCELLENT ! Toutes les corrections majeures fonctionnent"
    echo ""
    log "INFO" "💡 Prêt pour l'installation complète:"
    log "INFO" "   make install-laravel-php84"
    echo ""
    exit_code=0
elif [ $percentage -ge 75 ]; then
    log "SUCCESS" "✅ BON ! La plupart des corrections fonctionnent"
    echo ""
    log "WARN" "⚠️ Quelques optimisations mineures à faire"
    log "INFO" "💡 Vous pouvez procéder à l'installation:"
    log "INFO" "   make install-laravel-php84"
    echo ""
    exit_code=0
else
    log "ERROR" "❌ PROBLÈMES CRITIQUES détectés"
    echo ""
    log "ERROR" "🚨 Vérifiez les erreurs ci-dessus avant de continuer"
    log "INFO" "💡 Relancez le build Docker si nécessaire:"
    log "INFO" "   make build && make up"
    echo ""
    exit_code=1
fi

# Informations supplémentaires
echo ""
log "INFO" "📋 Actions recommandées:"
if [ $exit_code -eq 0 ]; then
    log "INFO" "   1. Lancer: make install-laravel-php84"
    log "INFO" "   2. Tester: php artisan test"
    log "INFO" "   3. Vérifier: make quality-all"
else
    log "INFO" "   1. Corriger les erreurs critiques"
    log "INFO" "   2. Relancer: make build && make up"
    log "INFO" "   3. Re-valider: ./scripts/validate-all-fixes.sh"
fi

echo ""
echo "================================================================="
echo ""

exit $exit_code