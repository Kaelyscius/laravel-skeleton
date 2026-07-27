# ADR-0003 — Backup local-only + offsite hands-off gratuit (v1)

> **Statut** : ✅ Accepted — 2026-05-08
> **Décideurs** : Alex (PO), Winston (architect), Murat (test architect)
> **Source débat** : `docs/roundtable-decisions.md` §8 (Backup strategy)
> **⚠️ Warning verrou** : *"Backup strategy v1 = LOCAL-ONLY. UPGRADE TO PAID OFFSITE BEFORE HOSTING THIRD-PARTY DATA."*

---

## Contexte

Le projet v1 est un site personnel + skeleton OSS, **zéro budget infra payant** assumé. Pourtant les données à préserver sont stratégiques :

- Articles (reviews) : 10-15 articles à M+6, chaque article = ~1200 mots + cover + metadata
- Comments modérés
- Configuration Filament + permissions
- Streamer profile (bio FR+EN, presse kit)

Trois niveaux de backup étaient sur la table :

| Couche | Coût | Effort | Bénéfice |
|---|---|---|---|
| **A. Local VPS** (`pg_dump` cron) | 0€ | ~1h script | Restaure incident applicatif, pas hardware |
| **B. Offsite gratuit hands-off** (Mega/Drive/pCloud free tier via rclone) | 0€ | ~2h script + ~10 min activation | Restaure incident VPS total |
| **C. Backblaze B2 payant** | ~0.50€/mois | ~2h | Pro-grade, multi-region, SLA |

Question : faut-il activer B et/ou C dès v1 ?

---

## Décision

### Couche A — Backup local VPS : **ACTIVÉE par défaut**

- Script : `scripts/ops/backup-local.sh`
- Méthode : `pg_dump` quotidien à 03:00 via cron → `/var/backups/postgres/`
- Compression : `gzip -9`
- Rotation : 14 jours (suppression du plus ancien si > 14)
- **Exclusions** : DB `postgres-pulse` (regénérable, cf. ADR-0004)
- Test : Bats `tests/bats/backup-local.bats` lance dump + vérifie integrity `pg_restore --list`

### Couche B — Backup offsite hands-off gratuit : **DÉSACTIVÉE par défaut, activable en 5 min**

- Script : `scripts/ops/backup-offsite.sh`
- Flag : `BACKUP_OFFSITE_ENABLED=false` dans `.env` par défaut
- Activation : remplir `BACKUP_OFFSITE_ENABLED=true` + `BACKUP_OFFSITE_RCLONE_REMOTE=mega:streamer-backup` + `rclone config` (one-time)
- Free tier supporté : Mega 20GB, Google Drive 15GB, pCloud 10GB
- Quotidien post-dump local, conservé 30 jours sur remote

### Couche C — Backblaze B2 payant : **REPORTÉE à M+6**

Triggers d'activation (à graver — premier qui sonne, on active) :
1. Premier streamer ami hébergé sur l'instance d'Alex (M+6 attendu)
2. Volume données > 5 GB (cap free tier le plus restrictif)
3. Incident VPS qui pousse Alex à reconsidérer

Coût estimé activation : ~0.50€/mois pour < 10 GB.

---

## Conséquences

### Positives

- **0€ budget v1** respecté
- **Restauration possible** dès jour 1 (couche A)
- **Restauration offsite trivialisée** : flag à `true`, `rclone config` 5 min, basta
- **Pas de dépendance** à un service payant pour démarrer
- **Cohérence "Plausible-style"** : opinion claire, preset fort, le forker active s'il veut

### Négatives / acceptées

- **Incident VPS total entre M0 et M+6** sans offsite activé = perte potentielle 14 jours données (mitigation : activer offsite gratuit en 5 min recommandé dès M+1)
- **Free tier rclone peut throttle ou expirer** → documenter signal d'alerte (test job nightly qui vérifie présence du dernier backup remote)
- **Avant M+6 si Alex héberge un tiers** : RGPD + responsabilité légale → upgrade B2 obligatoire

### Verrou contractuel

Cet ADR doit rester en `docs/adr/` pour signaler aux forkers :
**Si tu héberges les données d'un tiers, upgrade vers B2 (ou équivalent payant) AVANT.**

Un check Spatie Health `BackupOffsiteCheck` peut être ajouté en S5 si le besoin se confirme.

---

## Référence débat complet

- `docs/roundtable-decisions.md` §8 (Backup strategy zéro budget v1)
- Land-and-expand timeline §10 (M+6 critique = premier streamer ami)
