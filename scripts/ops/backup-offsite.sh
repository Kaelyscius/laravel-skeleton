#!/bin/bash
# =============================================================================
# BACKUP OFFSITE - Hands-off : DÉSACTIVÉ par défaut
# =============================================================================
#
# Statut : codé mais NON ACTIF tant que BACKUP_OFFSITE_ENABLED=true dans .env
#
# Pourquoi désactivé par défaut : Alex a refusé Backblaze B2 payant en v1
# tant que le projet n'est pas validé. Ce script est codé hands-off pour
# pouvoir être activé en 5 min quand voulu, sans bloquer le scaffolding.
#
# Activation v1 (gratuit) :
#   1. Installer rclone : curl https://rclone.org/install.sh | sudo bash
#   2. Configurer un remote gratuit : rclone config
#      - Mega (20GB free) : type=mega, login Mega
#      - Google Drive (15GB free) : type=drive
#      - pCloud (10GB free) : type=pcloud
#   3. Tester : rclone lsd <remote>:
#   4. Activer : ajouter dans .env :
#        BACKUP_OFFSITE_ENABLED=true
#        BACKUP_OFFSITE_REMOTE=mega-perso  # ou autre nom rclone
#        BACKUP_OFFSITE_PATH=myapp-backups/
#   5. Décommenter la ligne crontab dans crontab.example puis crontab -e
#
# Migration vers backup payant (Backblaze B2) en v2+ :
#   - Configurer rclone avec backend B2 (rclone config → b2)
#   - Garder ce script (compatible n'importe quel remote rclone)
#   - Mettre à jour BACKUP_OFFSITE_REMOTE dans .env
#
# Couvre : panne disque VPS, ransomware, perte VPS, faillite provider VPS
# Coût v1 : 0€ (free tiers)
# Coût v2+ : ~0.50€/mois (Backblaze B2 1TB)
# =============================================================================

set -euo pipefail

# Lire .env
if [ -f "$(dirname "$0")/../../.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$(dirname "$0")/../../.env"
    set +a
fi

# Kill-switch : désactivé par défaut
if [ "${BACKUP_OFFSITE_ENABLED:-false}" != "true" ]; then
    echo "[backup-offsite] Disabled (BACKUP_OFFSITE_ENABLED is not 'true'). Exiting."
    exit 0
fi

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/var/backups/postgres}"
LOG_FILE="${LOG_FILE:-/var/log/myapp-backup-offsite.log}"
REMOTE="${BACKUP_OFFSITE_REMOTE:-}"
REMOTE_PATH="${BACKUP_OFFSITE_PATH:-myapp-backups/}"
RETENTION_WEEKS="${BACKUP_OFFSITE_RETENTION_WEEKS:-8}"

# Helpers
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

# Préconditions
if ! command -v rclone >/dev/null 2>&1; then
    log "ERROR: rclone not installed. Install via: curl https://rclone.org/install.sh | sudo bash"
    exit 1
fi

if [ -z "$REMOTE" ]; then
    log "ERROR: BACKUP_OFFSITE_REMOTE not set in .env. Configure with: rclone config"
    exit 1
fi

if ! rclone lsd "${REMOTE}:" >/dev/null 2>&1; then
    log "ERROR: Cannot access rclone remote '${REMOTE}'. Check rclone config."
    exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

# Trouver le dernier backup local
LATEST_LOCAL=$(find "$BACKUP_DIR" -name "backup-*.sql.gz" -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)

if [ -z "$LATEST_LOCAL" ]; then
    log "ERROR: No local backup found in ${BACKUP_DIR}. Run backup-local.sh first."
    exit 2
fi

log "Uploading ${LATEST_LOCAL} → ${REMOTE}:${REMOTE_PATH}"

# Upload
if rclone copy "$LATEST_LOCAL" "${REMOTE}:${REMOTE_PATH}" --log-file="$LOG_FILE" --log-level INFO; then
    SIZE=$(du -h "$LATEST_LOCAL" | cut -f1)
    log "✓ Offsite upload OK (${SIZE}) → ${REMOTE}:${REMOTE_PATH}$(basename "$LATEST_LOCAL")"
else
    log "ERROR: rclone upload failed"
    exit 3
fi

# Rotation offsite (garde N semaines)
log "Applying offsite rotation (${RETENTION_WEEKS} weeks)..."
RETENTION_DAYS=$((RETENTION_WEEKS * 7))
rclone delete "${REMOTE}:${REMOTE_PATH}" --min-age "${RETENTION_DAYS}d" --log-file="$LOG_FILE" --log-level INFO 2>/dev/null || true

log "Offsite backup complete."
exit 0
