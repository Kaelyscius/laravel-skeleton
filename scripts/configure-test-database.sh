#!/bin/bash

# =============================================================================
# CONFIGURATION BASE DE DONNÉES DE TEST — PostgreSQL 17 (ADR-0007)
# =============================================================================
#
# Ce script crée la base de test et VÉRIFIE que la configuration Laravel la
# vise bien. Il ne la réécrit plus.
#
# Historique : la version précédente était un hybride cassé. L'étape de création
# avait été migrée vers psql, mais les étapes suivantes écrivaient encore une
# connexion « mysql_testing » dans phpunit.xml et l'injectaient dans
# config/database.php en cherchant le bloc `'mysql' => [`. Depuis que la stack
# est PostgreSQL-only (ADR-0007), ce bloc n'existe plus et phpunit.xml est
# versionné avec la bonne configuration : ces étapes ne pouvaient que dégrader
# un état sain. Elles sont remplacées par des assertions.

set -euo pipefail

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

log "INFO" "🗄️ Configuration de la base de données de test (PostgreSQL)"
echo ""

# Variables
DB_HOST="${DB_HOST:-postgres}"
DB_PORT="${DB_PORT:-5432}"
DB_USERNAME="${DB_USERNAME:-laravel}"
DB_PASSWORD="${DB_PASSWORD:-laravel}"
DB_DATABASE="${DB_DATABASE:-laravel}"
DB_TEST_DATABASE="${DB_TEST_DATABASE:-laravel_test}"

# Où trouver psql ?
#
# Vérifié à la migration PostgreSQL : le client `psql` est absent de l'hôte ET
# du conteneur php (qui n'a que l'extension pdo_pgsql). Il n'existe que dans le
# conteneur postgres. Un fork-streamer sur machine vierge est dans le même cas —
# c'est la promesse d'ADR-0001. On route donc par le conteneur, avec repli sur
# un psql local s'il existe.
if command -v psql >/dev/null 2>&1; then
    export PGPASSWORD="$DB_PASSWORD"
    psql_run() { psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" "$@"; }
    log "INFO" "Client psql local détecté"
else
    COMPOSE_BIN="${COMPOSE_BIN:-docker compose}"
    psql_run() {
        $COMPOSE_BIN exec -T -e PGPASSWORD="$DB_PASSWORD" postgres \
            psql -U "$DB_USERNAME" "$@"
    }
    log "INFO" "psql absent de l'hôte — passage par le conteneur postgres"
fi

# -----------------------------------------------------------------------------
# 1. Créer la base de données de test
# -----------------------------------------------------------------------------
log "INFO" "Création de la base de données de test : $DB_TEST_DATABASE"

if ! psql_run -d "$DB_DATABASE" -c "SELECT 1" >/dev/null 2>&1; then
    log "ERROR" "Impossible de joindre PostgreSQL sur $DB_HOST:$DB_PORT"
    log "INFO" "Vérifiez que le service postgres est démarré (make status)"
    exit 1
fi

# CREATE DATABASE ne peut pas tourner dans une transaction : on teste d'abord.
if psql_run -d "$DB_DATABASE" -tAc \
        "SELECT 1 FROM pg_database WHERE datname = '$DB_TEST_DATABASE'" | grep -q 1; then
    log "INFO" "Base déjà présente — rien à faire (idempotent)"
else
    psql_run -d "$DB_DATABASE" -c \
        "CREATE DATABASE \"$DB_TEST_DATABASE\" ENCODING 'UTF8' TEMPLATE template0;" >/dev/null || {
        log "ERROR" "Échec de la création de $DB_TEST_DATABASE"
        exit 1
    }
    log "SUCCESS" "Base de données de test créée : $DB_TEST_DATABASE"
fi

psql_run -d "$DB_DATABASE" -c \
    "GRANT ALL PRIVILEGES ON DATABASE \"$DB_TEST_DATABASE\" TO \"$DB_USERNAME\";" >/dev/null 2>&1 || true

# -----------------------------------------------------------------------------
# 2. Vérifier que phpunit.xml vise bien cette base (assertion, pas réécriture)
# -----------------------------------------------------------------------------
log "INFO" "Vérification de phpunit.xml"

if [ ! -f "phpunit.xml" ]; then
    log "ERROR" "phpunit.xml introuvable — il est versionné, un clone devrait le fournir"
    exit 1
fi

if ! grep -q '<env name="DB_CONNECTION" value="pgsql"/>' phpunit.xml; then
    log "ERROR" "phpunit.xml ne déclare pas DB_CONNECTION=pgsql"
    log "INFO" "La stack est PostgreSQL-only (ADR-0007) — corrigez phpunit.xml"
    exit 1
fi

if ! grep -q "<env name=\"DB_DATABASE\" value=\"$DB_TEST_DATABASE\"/>" phpunit.xml; then
    log "ERROR" "phpunit.xml ne vise pas la base $DB_TEST_DATABASE"
    exit 1
fi

log "SUCCESS" "phpunit.xml vise bien pgsql / $DB_TEST_DATABASE"

# -----------------------------------------------------------------------------
# 3. Vérifier la connexion applicative
# -----------------------------------------------------------------------------
log "INFO" "Test de connexion à la base de test"

if psql_run -d "$DB_TEST_DATABASE" -c "SELECT 1;" >/dev/null 2>&1; then
    log "SUCCESS" "Connexion à $DB_TEST_DATABASE OK"
else
    log "ERROR" "Impossible de se connecter à $DB_TEST_DATABASE"
    exit 1
fi

echo ""
log "SUCCESS" "🎉 Base de données de test prête"
log "INFO" "   Base       : $DB_TEST_DATABASE"
log "INFO" "   Connexion  : pgsql (déclarée dans phpunit.xml, versionné)"
echo ""
