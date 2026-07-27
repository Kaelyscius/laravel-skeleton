# 8. Architecture backup (cf. ADR-0003)

## 8.1 Couche 1 — Backup local VPS (activée par défaut)

- Script : `scripts/ops/backup-local.sh`
- Méthode : `pg_dump` quotidien (cron 03:00) → `/var/backups/postgres/`
- Rotation : 14 jours
- Compression : `gzip -9`
- **Exclus** : `postgres-pulse` DB (regénérable)

## 8.2 Couche 2 — Backup offsite hands-off (désactivée par défaut)

- Script : `scripts/ops/backup-offsite.sh`
- Flag : `BACKUP_OFFSITE_ENABLED=false` par défaut
- Activation : 5 min via `rclone` + Mega 20GB / Google Drive 15GB / pCloud 10GB free tier

## 8.3 Couche 3 — B2 payant

**Reporté à M+6** (cf. land-and-expand) ou si Alex héberge la donnée d'un tiers.

**ADR-0003 lock** : *"UPGRADE TO PAID OFFSITE BEFORE HOSTING THIRD-PARTY DATA."*

---
