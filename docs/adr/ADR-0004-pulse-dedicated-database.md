# ADR-0004 — Pulse sur base de données isolée (`postgres-pulse`)

> **Statut** : ✅ Accepted — 2026-05-08
> **Décideurs** : Winston (architect), Murat (test architect)
> **Source débat** : `docs/roundtable-decisions.md` R4 — 3 infra decisions Winston LOCKED-pending

---

## Contexte

Laravel Pulse écrit en haute fréquence (snapshots minute par minute, slow queries, exceptions, jobs lents). Sur une stack mono-instance, deux choix :

1. **Tout dans la DB applicative** (`postgres`) — défaut Laravel
2. **DB dédiée** (`postgres-pulse`) — séparation propre

Coûts opérationnels mesurés en interne sur projets similaires :

| Métrique | DB partagée | DB dédiée |
|---|---|---|
| Contention I/O sur tables app | Sensible si spike trafic | Aucune |
| Backup DB app (taille) | Pulse pollue `pg_dump` | DB app pure |
| Restauration partielle | Pulse réapparaît même si on voulait juste app | Restaure ce qu'on veut |
| Rotation données Pulse | Doit slalomer entre tables app | Truncate trivial |
| Overhead opérationnel | 0 (rien à gérer) | +1 container + +~50 MB RAM |

---

## Décision

**Pulse écrit sur une base de données PostgreSQL dédiée**, dans un conteneur Docker séparé `postgres-pulse`.

Implémentation :

1. **Nouveau container** dans `docker-compose.yml` :
   ```yaml
   postgres-pulse:
     image: postgres:17-alpine
     restart: unless-stopped
     environment:
       POSTGRES_DB: pulse
       POSTGRES_USER: pulse
       POSTGRES_PASSWORD: ${DB_PULSE_PASSWORD}
     volumes:
       - postgres-pulse-data:/var/lib/postgresql/data
     networks:
       - internal
   ```

2. **Connexion Laravel** dans `config/database.php` :
   ```php
   'pgsql_pulse' => [
       'driver' => 'pgsql',
       'host' => env('DB_PULSE_HOST', 'postgres-pulse'),
       'database' => env('DB_PULSE_DATABASE', 'pulse'),
       'username' => env('DB_PULSE_USERNAME', 'pulse'),
       'password' => env('DB_PULSE_PASSWORD'),
       // ...
   ],
   ```

3. **Configuration Pulse** dans `config/pulse.php` :
   ```php
   'storage' => [
       'driver' => 'database',
       'connection' => 'pgsql_pulse',
   ],
   ```

4. **Exclusion backup** : `scripts/ops/backup-local.sh` skip `postgres-pulse` explicitement.

5. **Rotation interne Pulse** : conserver 7 jours max (`pulse:trim --hours=168` via Laravel scheduler quotidien).

---

## Conséquences

### Positives

- **Performance** : aucune contention I/O Pulse sur DB applicative en cas de spike
- **Backup propre** : `pg_dump` de la DB app reste léger et focus
- **Rotation triviale** : on truncate `postgres-pulse` sans risque pour l'app
- **Restauration sélective** : on peut perdre toute la DB Pulse sans impact métier
- **Conforme philosophie observabilité jetable** : les métriques sont regénérables, l'historique long terme n'est pas un besoin

### Négatives / acceptées

- **+1 container** à monitorer (mais Watchtower auto-update Postgres officiel)
- **+~50 MB RAM** dédié (négligeable sur VPS standard 2 GB+)
- **Secret de plus** (`DB_PULSE_PASSWORD`) à gérer via `env:encrypt` (cf. ADR-0006)
- **Phase 2 / S0 P0** : effort estimé ~1h (config + test connexion + ajout backup-local exclusion)

### Garde-fous

- Spatie Health check `DatabaseConnectionCheck` sur `pgsql_pulse` ajouté en S2
- Alert Discord si `postgres-pulse` disk usage > 80% (via Uptime-Kuma + métrique custom)
- Test Bats `tests/bats/pulse-isolation.bats` vérifie que `pg_dump` de la DB app ne contient AUCUNE table `pulse_*`

---

## Référence débat complet

- `docs/roundtable-decisions.md` Round 4 — 3 NEW infra decisions Winston LOCKED-pending (point 1)
