# 4. Architecture données

## 4.1 PostgreSQL 17 — app principale

**Pourquoi Postgres et pas MariaDB** (décision LOCKED 2026-05-08) :
- RLS native (assurance pivot SaaS gratuite — cf. ADR-0002)
- `JSONB` + index GIN pour metadata Reviews
- Full-text search FR natif (`to_tsvector('french', ...)`)
- Signal moderne 2026 dans l'écosystème OSS

**Conventions schéma** :
- `streamer_id BIGINT NOT NULL` sur toutes les tables métier
- Index composite `(streamer_id, created_at DESC)` sur tables fréquemment listées
- `slug VARCHAR(180) UNIQUE` pour Reviews (cf. §6.1 SEO)
- `published_at TIMESTAMP NULL` pour différentiation brouillon/publié
- `cover_url TEXT NULL` (pas de stockage local v1 — embed/CDN externe)

## 4.2 PostgreSQL 17 — Pulse isolé (cf. ADR-0004)

Container séparé `postgres-pulse` :
- DB dédiée aux écritures haute fréquence Pulse (snapshots, slow queries, exceptions)
- **Exclue des backups quotidiens** (données éphémères, regénérables)
- Évite la contention I/O sur la DB applicative en cas de spike

Connexion Laravel :
```php
// config/database.php
'pgsql_pulse' => [
    'driver' => 'pgsql',
    'host' => env('DB_PULSE_HOST', 'postgres-pulse'),
    'port' => env('DB_PULSE_PORT', '5432'),
    'database' => env('DB_PULSE_DATABASE', 'pulse'),
    // ...
],

// config/pulse.php
'storage' => ['driver' => 'database', 'connection' => 'pgsql_pulse'],
```

## 4.3 Redis 8.6 — cache, queue, sessions

Single instance, base 0 par défaut. Pas de cluster v1 (YAGNI). 
- `CACHE_STORE=redis` ⚠️ *(clé corrigée le 2026-08-23 : Laravel 11+ lit `CACHE_STORE`. `CACHE_DRIVER` était lu par personne, et une application qui l'annonçait tournait en réalité sur le pilote `database` — mesuré par la sonde `/health` du cache, restée verte avec Redis arrêté.)*
- `QUEUE_CONNECTION=redis` (sauf batches → PostgreSQL via Horizon config)
- `SESSION_DRIVER=redis`
- `BROADCAST_DRIVER=redis` (si Echo activé en v1.5)

## 4.4 Stockage fichiers — local + symlink

- v1 : `storage/app/public` + symlink `public/storage` (Laravel standard)
- Covers Reviews : uploadées via Filament, stockées localement
- OG images pré-générées : `public/og/{slug}.png` (générées au publish, cf. §6.4)
- VOD : **embed YouTube uniquement** (pas de S3/Backblaze v1)

---
