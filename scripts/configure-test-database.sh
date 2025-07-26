#!/bin/bash

# =============================================================================
# CONFIGURATION BASE DE DONNÉES DE TEST (Remplacer SQLite)
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

log "INFO" "🗄️ Configuration de la base de données de test"
echo ""

# Variables
DB_HOST="${DB_HOST:-mariadb}"
DB_USERNAME="${DB_USERNAME:-laravel}"
DB_PASSWORD="${DB_PASSWORD:-laravel}"
DB_DATABASE="${DB_DATABASE:-laravel}"
DB_TEST_DATABASE="${DB_DATABASE}_test"

# 1. Créer la base de données de test
log "INFO" "Création de la base de données de test: $DB_TEST_DATABASE"

# Créer la base de données de test dans MariaDB
mysql -h"$DB_HOST" -u"$DB_USERNAME" -p"$DB_PASSWORD" -e "
    CREATE DATABASE IF NOT EXISTS \`$DB_TEST_DATABASE\` 
    CHARACTER SET utf8mb4 
    COLLATE utf8mb4_unicode_ci;
    
    GRANT ALL PRIVILEGES ON \`$DB_TEST_DATABASE\`.* TO '$DB_USERNAME'@'%';
    FLUSH PRIVILEGES;
" 2>/dev/null || {
    log "ERROR" "Impossible de créer la base de données de test"
    log "INFO" "Vérifiez que MariaDB est démarré et accessible"
    exit 1
}

log "SUCCESS" "Base de données de test créée: $DB_TEST_DATABASE"

# 2. Configurer Laravel pour utiliser la base de données de test
log "INFO" "Configuration de Laravel pour les tests"

# Vérifier si phpunit.xml existe
if [ ! -f "phpunit.xml" ]; then
    log "INFO" "Création de phpunit.xml depuis phpunit.xml.dist"
    cp phpunit.xml.dist phpunit.xml 2>/dev/null || {
        log "WARN" "phpunit.xml.dist non trouvé, création d'un phpunit.xml de base"
        cat > phpunit.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<phpunit xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:noNamespaceSchemaLocation="vendor/phpunit/phpunit/phpunit.xsd"
         bootstrap="vendor/autoload.php"
         colors="true">
    <testsuites>
        <testsuite name="Unit">
            <directory suffix="Test.php">./tests/Unit</directory>
        </testsuite>
        <testsuite name="Feature">
            <directory suffix="Test.php">./tests/Feature</directory>
        </testsuite>
    </testsuites>
    <source>
        <include>
            <directory suffix=".php">./app</directory>
        </include>
    </source>
    <php>
        <env name="APP_ENV" value="testing"/>
        <env name="APP_KEY" value="base64:SGVsbG8gV29ybGQgVGVzdCBLZXkgMTIzNDU2Nzg5"/>
        <env name="BCRYPT_ROUNDS" value="4"/>
        <env name="CACHE_DRIVER" value="array"/>
        <env name="DB_CONNECTION" value="mysql_testing"/>
        <env name="MAIL_MAILER" value="array"/>
        <env name="QUEUE_CONNECTION" value="sync"/>
        <env name="SESSION_DRIVER" value="array"/>
        <env name="TELESCOPE_ENABLED" value="false"/>
    </php>
</phpunit>
EOF
    }
fi

# Modifier phpunit.xml pour utiliser la base de données de test
if ! grep -q "mysql_testing" phpunit.xml; then
    log "INFO" "Mise à jour de phpunit.xml pour la base de données de test"
    
    # Backup
    cp phpunit.xml phpunit.xml.backup
    
    # Remplacer SQLite par MySQL de test
    sed -i 's/<env name="DB_CONNECTION" value="sqlite"\/>/<env name="DB_CONNECTION" value="mysql_testing"\/>/' phpunit.xml
    sed -i 's/<env name="DB_DATABASE" value=":memory:"\/>/<env name="DB_DATABASE" value="'$DB_TEST_DATABASE'"\/>/' phpunit.xml
    
    # Ajouter les variables si elles n'existent pas
    if ! grep -q "DB_CONNECTION.*mysql_testing" phpunit.xml; then
        sed -i '/<php>/a\        <env name="DB_CONNECTION" value="mysql_testing"\/>' phpunit.xml
    fi
    
    if ! grep -q "DB_DATABASE.*'$DB_TEST_DATABASE'" phpunit.xml; then
        sed -i '/<php>/a\        <env name="DB_DATABASE" value="'$DB_TEST_DATABASE'"\/>' phpunit.xml
    fi
fi

# 3. Configurer la connexion de test dans config/database.php
log "INFO" "Configuration de la connexion de test dans config/database.php"

if [ -f "config/database.php" ]; then
    # Backup
    cp config/database.php config/database.php.backup
    
    # Ajouter la connexion mysql_testing si elle n'existe pas
    if ! grep -q "mysql_testing" config/database.php; then
        log "INFO" "Ajout de la connexion mysql_testing"
        
        # Créer un script PHP temporaire pour modifier le fichier
        cat > /tmp/add_test_connection.php << 'EOPHP'
<?php
$file = 'config/database.php';
$content = file_get_contents($file);

// Chercher la position après la connexion mysql
$mysqlPos = strpos($content, "'mysql' => [");
if ($mysqlPos === false) {
    echo "Configuration MySQL non trouvée\n";
    exit(1);
}

// Trouver la fin de la configuration mysql
$braceCount = 0;
$pos = $mysqlPos;
$start = false;
while ($pos < strlen($content)) {
    if ($content[$pos] === '[') {
        if (!$start) $start = true;
        $braceCount++;
    } elseif ($content[$pos] === ']') {
        $braceCount--;
        if ($start && $braceCount === 0) {
            $pos++;
            break;
        }
    }
    $pos++;
}

// Ajouter la connexion de test
$testConfig = "\n\n        'mysql_testing' => [\n" .
    "            'driver' => 'mysql',\n" .
    "            'url' => env('DB_TEST_URL'),\n" .
    "            'host' => env('DB_HOST', '127.0.0.1'),\n" .
    "            'port' => env('DB_PORT', '3306'),\n" .
    "            'database' => env('DB_DATABASE') . '_test',\n" .
    "            'username' => env('DB_USERNAME', 'forge'),\n" .
    "            'password' => env('DB_PASSWORD', ''),\n" .
    "            'unix_socket' => env('DB_SOCKET', ''),\n" .
    "            'charset' => 'utf8mb4',\n" .
    "            'collation' => 'utf8mb4_unicode_ci',\n" .
    "            'prefix' => '',\n" .
    "            'prefix_indexes' => true,\n" .
    "            'strict' => true,\n" .
    "            'engine' => null,\n" .
    "            'options' => extension_loaded('pdo_mysql') ? array_filter([\n" .
    "                PDO::MYSQL_ATTR_SSL_CA => env('MYSQL_ATTR_SSL_CA'),\n" .
    "            ]) : [],\n" .
    "        ],";

$newContent = substr_replace($content, $testConfig, $pos, 0);
file_put_contents($file, $newContent);
echo "Connexion mysql_testing ajoutée avec succès\n";
EOPHP

        php /tmp/add_test_connection.php
        rm -f /tmp/add_test_connection.php
    fi
else
    log "WARN" "config/database.php non trouvé - sera créé lors de l'installation Laravel"
fi

# 4. Test de connexion
log "INFO" "Test de connexion à la base de données de test"

# Test de connexion
if mysql -h"$DB_HOST" -u"$DB_USERNAME" -p"$DB_PASSWORD" "$DB_TEST_DATABASE" -e "SELECT 1;" >/dev/null 2>&1; then
    log "SUCCESS" "✅ Connexion à la base de données de test OK"
else
    log "ERROR" "❌ Impossible de se connecter à la base de données de test"
    exit 1
fi

echo ""
log "SUCCESS" "🎉 Configuration de la base de données de test terminée !"
echo ""
log "INFO" "📋 Résumé:"
log "INFO" "   Base de données de test: $DB_TEST_DATABASE"
log "INFO" "   Connexion Laravel: mysql_testing"
log "INFO" "   Configuration: phpunit.xml et config/database.php"
echo ""
log "INFO" "💡 Pour exécuter les tests: php artisan test"