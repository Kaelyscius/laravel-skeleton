# 🚀 Getting Started — Lancer le projet

> Document destiné à Alex (et aux forkers OSS) pour passer de "je clone le repo" à "j'ai un site streamer fonctionnel en local".

## 🎯 Vue d'ensemble du process

```
git clone           → 1 min
make install-dev-full → 5-15 min (build Docker + install Laravel)
✅ App fonctionnelle  → http://localhost / https://laravel.local
```

Le projet est conçu pour être **démarrable en une commande** depuis un repo fraîchement cloné.

## ✅ Prérequis machine

- Docker >= 24.0
- Docker Compose >= 2.20
- `make`
- `git`
- WSL2 (si Windows)
- 4 GB RAM minimum, 10 GB disque libre

Pas besoin d'avoir PHP, Postgres, Node, ou Composer installés sur l'hôte — tout est containerisé.

## 🆕 Premier lancement (machine vierge)

```bash
# 1. Cloner le repo
git clone https://github.com/<owner>/myLaravelSkeleton.git
cd myLaravelSkeleton

# 2. (Optionnel) Setup interactif pour customiser l'environnement
make setup-interactive

# 3. Installation complète : build + up + Laravel + npm + SSL
make install-dev-full
```

Durée typique : 5-15 minutes (premier build Docker = ~5-10 min, install Laravel ~3-5 min, npm ~2 min).

### Ce que `make install-dev-full` fait

1. **Build** des images Docker custom (PHP 8.5.4 Alpine, Apache 2.4, Node 24)
2. **Up** des containers : `apache`, `php`, `postgres`, `redis`, `node`, `mailpit`, `adminer`, `dozzle`, `it-tools`, `watchtower`
3. **Install Laravel 12** dans `src/` via `composer create-project`
4. **Patch** du skeleton (Pest 4, retire phpunit/pint/sail, configure phpunit.xml pour Postgres)
5. **Install des packages** prod + dev (Horizon, Telescope, Sanctum, Pulse, Spatie suite, Pest, etc.)
6. **NPM install** + Vite setup
7. **SSL** local (Apache HTTPS sur https://laravel.local)

### Critères de succès attendus

- ✅ `docker ps` montre 10 containers `Up` et `(healthy)`
- ✅ Postgres accepte la connexion : `make shell-db` ouvre `psql`
- ✅ Laravel boote : https://laravel.local répond
- ✅ /health endpoint retourne JSON `{"status":"ok"}`
- ✅ Adminer sur http://localhost:8080 (pré-configuré pour Postgres `pgsql` driver)

## 🔁 Reprise (déjà installé, après une pause)

Si le projet est déjà installé et que tu veux juste le redémarrer :

```bash
make up-local    # démarre tous les containers (dev + tools)
# ou
make up-dev      # démarre seulement essentiels + dev tools (sans monitoring)
# ou
make up-prod     # démarre seulement les services essentiels (apache + php + postgres + redis)
```

Pour vérifier l'état :

```bash
make status         # statut containers
make ps-profiles    # services groupés par profile
```

## 🧰 Workflow quotidien dev

```bash
# Démarrer la stack
make up-local

# Lancer un shell dans le container PHP
make shell

# Lancer artisan
make artisan cmd="migrate"
make artisan cmd="make:model Article"

# Composer
make composer cmd="require spatie/laravel-tags"

# NPM
make npm-install
make npm-dev          # dev server Vite
make npm-build        # build production

# Tests
make test             # tous les tests Pest
make test-unit
make test-feature

# Qualité
make quality-quick    # ECS + PHPStan
make quality-all      # ECS + PHPStan + Rector + Insights
make quality-fix      # auto-fix ce qui peut l'être

# Database ops
make migrate          # migrations
make fresh            # reset DB + seed
make shell-db         # console psql
make db-snapshot      # pg_dump rapide avant op risquée
make db-restore FILE=storage/db-snapshots/xxx.sql.gz
```

## 🛡️ Backup (en local et prod)

### Local dev

Pas de backup automatique en dev (data jetable, `make fresh` régénère).

### Production VPS

Le skeleton inclut 2 scripts de backup :

```bash
# Backup local quotidien (cron VPS) — couche 1, par défaut
scripts/ops/backup-local.sh

# Backup offsite hebdo (rclone vers Mega/Drive/pCloud free tier) — couche 2, désactivé par défaut
# Pour activer : voir scripts/ops/backup-offsite.sh + .env BACKUP_OFFSITE_ENABLED=true
scripts/ops/backup-offsite.sh
```

À ajouter au crontab du VPS (hors container, sur l'host) :

```cron
# Backup local quotidien à 3h du matin
0 3 * * * /var/www/myLaravelSkeleton/scripts/ops/backup-local.sh

# Backup offsite hebdo (dimanche 4h) — décommenter quand BACKUP_OFFSITE_ENABLED=true
# 0 4 * * 0 /var/www/myLaravelSkeleton/scripts/ops/backup-offsite.sh
```

## 🆘 Troubleshooting commun

### Container PHP `unhealthy`

```bash
make logs service=php          # voir les logs
make rebuild                   # rebuild complet
```

### Permissions PhpStorm + WSL2

```bash
make fix-permissions           # corriger depuis le container
make fix-permissions-host      # corriger depuis l'hôte WSL2
./FIX-PHPSTORM-WSL.sh          # script complet (voir WSL-PHPSTORM.md)
```

### Postgres ne se connecte pas

```bash
docker logs laravel-app_postgres   # voir si erreur startup
make shell-db                       # tester connexion psql
```

Vérifier que `.env` a bien :

```env
DB_CONNECTION=pgsql
DB_HOST=postgres
DB_PORT=5432
DB_DATABASE=laravel
DB_USERNAME=laravel
DB_PASSWORD=secret
```

### Adminer affiche MySQL au lieu de Postgres

C'est probablement une ancienne valeur `ADMINER_DEFAULT_DRIVER`. Sur le panel Adminer (http://localhost:8080), sélectionner manuellement `PostgreSQL` dans le dropdown Type. Le défaut devrait être `pgsql` après le switch.

### Reset complet (table rase)

```bash
make down                                                # stop tous containers
docker volume rm laravel-app_postgres_data               # supprime data DB
docker volume rm laravel-app_redis_data                  # supprime cache Redis
find src/ -mindepth 1 -delete && touch src/.gitkeep      # vide /src
make install-dev-full                                    # repart de zéro
```

## 🔗 Pour aller plus loin

- **[02-bmad-workflow.md](02-bmad-workflow.md)** : comment utiliser BMAD pour coder le projet de A à Z
- **[../roundtable-decisions.md](../roundtable-decisions.md)** : pourquoi telle décision archi/produit a été prise
- **[../DOCKER-ARCHITECTURE.md](../DOCKER-ARCHITECTURE.md)** : architecture modulaire Docker complète
