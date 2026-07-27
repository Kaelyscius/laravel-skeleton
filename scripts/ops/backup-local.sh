#!/bin/bash
# =============================================================================
# BACKUP LOCAL VPS - PostgreSQL daily dump + 14-day rotation
# =============================================================================
#
# Usage : à appeler par cron sur le VPS prod
#   0 3 * * * /var/www/myLaravelSkeleton/scripts/ops/backup-local.sh
#
# Couvre : erreurs humaines (DROP TABLE, migration cassée), bugs applicatifs.
# NE COUVRE PAS : panne disque VPS, ransomware, perte VPS — voir backup-offsite.sh
#
# Output : /var/backups/postgres/backup-YYYYMMDD.sql.gz
# Logs   : /var/log/myapp-backup-local.log
# =============================================================================

set -euo pipefail

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/var/backups/postgres}"
LOG_FILE="${LOG_FILE:-/var/log/myapp-backup-local.log}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-laravel-app}"
POSTGRES_CONTAINER="${COMPOSE_PROJECT_NAME}_postgres"

# Lire .env si présent (pour DB_USERNAME, DB_DATABASE)
if [ -f "$(dirname "$0")/../../.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$(dirname "$0")/../../.env"
    set +a
fi

DB_USERNAME="${DB_USERNAME:-laravel}"
DB_DATABASE="${DB_DATABASE:-laravel}"

# Helpers
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

# Préconditions
mkdir -p "$BACKUP_DIR"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

if ! docker ps --format '{{.Names}}' | grep -q "^${POSTGRES_CONTAINER}$"; then
    log "ERROR: Postgres container ${POSTGRES_CONTAINER} not running. Skipping backup."
    exit 1
fi

# Backup
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/backup-${TIMESTAMP}.sql.gz"

log "Starting backup → ${BACKUP_FILE}"

if docker exec -t "$POSTGRES_CONTAINER" pg_dump -U "$DB_USERNAME" -d "$DB_DATABASE" 2>>"$LOG_FILE" | gzip > "$BACKUP_FILE"; then
    SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    log "✓ Backup OK (${SIZE}) → ${BACKUP_FILE}"
else
    log "ERROR: pg_dump failed"
    rm -f "$BACKUP_FILE"
    exit 2
fi

# Rotation
log "Applying ${RETENTION_DAYS}-day rotation..."
DELETED=$(find "$BACKUP_DIR" -name "backup-*.sql.gz" -mtime "+${RETENTION_DAYS}" -delete -print 2>/dev/null | wc -l || echo 0)
if [ "$DELETED" -gt 0 ]; then
    log "✓ Deleted ${DELETED} backup(s) older than ${RETENTION_DAYS} days"
fi

# Sanity check : alerter si dernière backup > 26h (cron raté ?)
LATEST=$(find "$BACKUP_DIR" -name "backup-*.sql.gz" -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2- || echo "")
if [ -n "$LATEST" ]; then
    AGE_HOURS=$(( ($(date +%s) - $(stat -c %Y "$LATEST")) / 3600 ))
    if [ "$AGE_HOURS" -gt 26 ]; then
        log "WARN: Latest backup is ${AGE_HOURS}h old (expected daily). Check cron."
    fi
fi

log "Backup local complete."
exit 0
