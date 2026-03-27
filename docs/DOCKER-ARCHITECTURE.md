# Architecture Modulaire Docker avec Profiles

## 🎯 Vue d'ensemble

Ce projet utilise **Docker Compose Profiles** pour une architecture modulaire permettant de démarrer uniquement les services nécessaires selon l'environnement (développement local, staging, production).

### Avantages de cette architecture

✅ **Séparation claire** : Services essentiels vs outils de développement
✅ **Économie de ressources** : Ne démarrez que ce dont vous avez besoin
✅ **Déploiement simplifié** : Production sans outils de développement
✅ **Flexibilité** : Activez/désactivez des groupes de services facilement
✅ **Standard Docker** : Utilise les fonctionnalités natives de Docker Compose

---

## 📦 Profiles disponibles

### 🏭 **Aucun profile** (Services essentiels - Production)

Services toujours actifs sans profile spécifique :

| Service | Description | Port(s) |
|---------|-------------|---------|
| `apache` | Serveur web Apache 2.4 + HTTPS/HTTP2 | 80, 443 |
| `php` | PHP 8.5.1 FPM + Supervisor + OPcache | - |
| `mariadb` | Base de données MariaDB | 3306 |
| `redis` | Cache et sessions Redis | 6379 |

**Usage** : Production, serveurs distants

```bash
# Démarrer en production
make up-prod
# ou
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

---

### 🛠️ **Profile "dev"** (Outils de développement)

Services de développement essentiels :

| Service | Description | Port(s) |
|---------|-------------|---------|
| `node` | Node.js 24 LTS pour builds frontend | - |
| `mailhog` | Capture d'emails pour tests | 8025 |
| `adminer` | Interface de gestion base de données | 8080 |

**Usage** : Développement local, nécessite build frontend

```bash
# Démarrer avec outils dev
make up-dev
# ou
docker-compose -f docker-compose.yml -f docker-compose.dev.yml --profile dev up -d
```

---

### 🔧 **Profile "tools"** (Outils utilitaires)

Services de monitoring et diagnostic :

| Service | Description | Port(s) |
|---------|-------------|---------|
| `dozzle` | Visualisation logs en temps réel | 9999 |
| `it-tools` | Boîte à outils développeur | 8081 |
| `watchtower` | Mises à jour automatiques des images | - |

**Usage** : Développement local avec monitoring complet

```bash
# Démarrer avec tous les outils
make up-dev-full
# ou
docker-compose -f docker-compose.yml -f docker-compose.dev.yml --profile dev --profile tools up -d
```

---

### ➕ **Profile "dev-extra"** (Outils additionnels)

Services supplémentaires pour le développement :

| Service | Description | Port(s) |
|---------|-------------|---------|
| `phpmyadmin` | Alternative à Adminer (interface riche) | 8083 |
| `redis-commander` | Interface de gestion Redis | 8082 |

**Usage** : Développement avec tous les outils disponibles

```bash
# Démarrer avec tous les outils extra
make up-dev-extra
# ou
docker-compose --profile dev --profile tools --profile dev-extra up -d
```

---

## 🚀 Guide d'utilisation rapide

### Commandes principales

```bash
# 🏭 PRODUCTION - Services essentiels uniquement
make up-prod

# 🛠️ DÉVELOPPEMENT - Services essentiels + dev tools
make up-dev

# 🎯 DÉVELOPPEMENT COMPLET - Tous les services (recommandé pour local)
make up-local  # ou make up-dev-full

# ➕ DÉVELOPPEMENT + EXTRA - Tous les outils disponibles
make up-dev-extra

# 🔧 OUTILS UNIQUEMENT - Monitoring sans redémarrer les autres services
make up-tools
```

### Commandes d'information

```bash
# Voir les services actifs par profile
make ps-profiles

# Statut détaillé de tous les containers
make status

# Voir les logs
make logs
make logs service=php
```

### Gestion des profiles

```bash
# Arrêter un profile spécifique
make stop-profile PROFILE=dev
make stop-profile PROFILE=tools

# Arrêter tous les services
make down
```

---

## 📖 Scénarios d'usage

### 🏠 Développement Local (Recommandé)

**Besoin** : Tous les outils pour développer confortablement

```bash
make up-local
```

**Services démarrés** :
- ✅ Services essentiels (apache, php, mariadb, redis)
- ✅ Outils dev (node, mailhog, adminer)
- ✅ Outils monitoring (dozzle, it-tools, watchtower)

**Accès** :
- Laravel : https://laravel.local
- Adminer : http://localhost:8080
- MailHog : http://localhost:8025
- IT-Tools : http://localhost:8081
- Dozzle : http://localhost:9999

---

### 🏭 Production / Serveur Distant

**Besoin** : Uniquement les services nécessaires pour l'application

```bash
make up-prod
```

**Services démarrés** :
- ✅ Services essentiels uniquement (apache, php, mariadb, redis)
- ❌ Pas d'outils de développement
- ❌ Pas d'outils de monitoring

**Avantages** :
- Moins de ressources consommées
- Surface d'attaque réduite
- Déploiement plus rapide

---

### 🔨 Développement Backend uniquement

**Besoin** : Développer sans build frontend

```bash
docker-compose up -d  # Sans profiles
```

**Services démarrés** :
- ✅ Services essentiels (apache, php, mariadb, redis)
- ❌ Pas de Node.js
- ❌ Pas d'outils

---

### 🎨 Développement avec build frontend

**Besoin** : Développer avec Vite/npm

```bash
make up-dev
```

**Services démarrés** :
- ✅ Services essentiels
- ✅ Node.js pour builds
- ✅ MailHog et Adminer
- ❌ Pas d'outils monitoring

---

### 🔍 Ajouter le monitoring à un environnement existant

**Besoin** : Activer Dozzle, IT-Tools et Watchtower sans tout redémarrer

```bash
make up-tools
```

**Services démarrés** :
- ✅ Dozzle, IT-Tools, Watchtower uniquement
- ℹ️ Les autres services continuent de fonctionner

---

## 🔄 Migration depuis l'ancienne architecture

### Avant (système deploy.replicas: 0)

```bash
# Développement
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up -d

# Production
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

**Problème** : Tous les services étaient définis, juste désactivés en production

### Après (système profiles)

```bash
# Développement local
make up-local

# Production
make up-prod
```

**Avantage** : Les services non nécessaires ne sont même pas instanciés

---

## ⚙️ Configuration technique

### Structure des fichiers

```
myLaravelSkeleton/
├── docker-compose.yml          # Configuration de base + profiles
├── docker-compose.dev.yml      # Overrides pour développement
├── docker-compose.prod.yml     # Overrides pour production
└── docker-compose.override.yml # Overrides locaux (généré automatiquement)
```

### Définition des profiles dans docker-compose.yml

```yaml
services:
  # Services essentiels (pas de profile = toujours actif)
  apache:
    # ...
  php:
    # ...
  mariadb:
    # ...
  redis:
    # ...

  # Profile "dev"
  node:
    profiles: ["dev"]
    # ...

  mailhog:
    profiles: ["dev"]
    # ...

  adminer:
    profiles: ["dev"]
    # ...

  # Profile "tools"
  dozzle:
    profiles: ["tools"]
    # ...

  it-tools:
    profiles: ["tools"]
    # ...

  watchtower:
    profiles: ["tools"]
    # ...

  # Profile "dev-extra" (dans docker-compose.dev.yml)
  phpmyadmin:
    profiles: ["dev-extra"]
    # ...

  redis-commander:
    profiles: ["dev-extra"]
    # ...
```

---

## 🎓 Commandes Docker Compose avancées

### Activer plusieurs profiles

```bash
# Dev + Tools
docker-compose --profile dev --profile tools up -d

# Dev + Tools + Extra
docker-compose --profile dev --profile tools --profile dev-extra up -d
```

### Voir tous les services disponibles (même non démarrés)

```bash
docker-compose config --services
```

### Lister les services d'un profile spécifique

```bash
docker-compose --profile dev config --services
```

### Combiner profiles et fichiers override

```bash
docker-compose \
  -f docker-compose.yml \
  -f docker-compose.dev.yml \
  --profile dev \
  --profile tools \
  up -d
```

---

## 🛡️ Bonnes pratiques

### ✅ À faire

1. **Production** : N'activer AUCUN profile
   ```bash
   make up-prod
   ```

2. **Développement local** : Activer tous les profiles nécessaires
   ```bash
   make up-local
   ```

3. **CI/CD** : Utiliser `up-prod` pour les tests d'intégration

4. **Monitoring temporaire** : Utiliser `up-tools` pour ajouter le monitoring

### ❌ À éviter

1. **NE PAS** activer les profiles `dev` ou `tools` en production

2. **NE PAS** modifier directement `docker-compose.yml` pour activer des services

3. **NE PAS** utiliser `deploy.replicas: 0` (obsolète avec les profiles)

---

## 🔧 Troubleshooting

### Problème : Un service ne démarre pas

**Vérifier le profile requis :**

```bash
docker-compose config | grep -A 5 "nom_du_service"
```

**Solution :**

```bash
# Si le service nécessite le profile "dev"
make up-dev

# Si le service nécessite le profile "tools"
make up-tools
```

### Problème : Comment savoir quels services sont actifs ?

```bash
# Voir tous les services actifs
make status

# Voir les services par profile
make ps-profiles
```

### Problème : Je veux redémarrer un profile spécifique

```bash
# Arrêter le profile
make stop-profile PROFILE=dev

# Redémarrer avec le profile
make up-dev
```

### Problème : Les outils de monitoring ne sont pas accessibles

**Vérifier que le profile "tools" est actif :**

```bash
make ps-profiles
```

**Si absent, démarrer les outils :**

```bash
make up-tools
```

---

## 📊 Comparaison des modes de démarrage

| Commande | Services essentiels | node | mailhog/adminer | dozzle/it-tools/watchtower | phpmyadmin/redis-commander |
|----------|---------------------|------|-----------------|----------------------------|---------------------------|
| `make up-prod` | ✅ | ❌ | ❌ | ❌ | ❌ |
| `make up-dev` | ✅ | ✅ | ✅ | ❌ | ❌ |
| `make up-dev-full` | ✅ | ✅ | ✅ | ✅ | ❌ |
| `make up-dev-extra` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `make up-local` | ✅ | ✅ | ✅ | ✅ | ❌ |
| `make up-tools` | - | - | - | ✅ | - |

**Légende** :
- ✅ = Services démarrés
- ❌ = Services non démarrés
- `-` = N'affecte pas ces services

---

## 🔗 Ressources

- [Docker Compose Profiles Documentation](https://docs.docker.com/compose/profiles/)
- [Docker Compose File Reference](https://docs.docker.com/compose/compose-file/)
- [Makefile Commands Reference](../CLAUDE.md)

---

## ❓ Questions fréquentes

### Q: Puis-je créer mes propres profiles ?

**R:** Oui ! Ajoutez simplement `profiles: ["mon-profile"]` à un service dans `docker-compose.yml` ou les fichiers d'override.

Exemple pour un profile "staging" :

```yaml
# docker-compose.staging.yml
services:
  apache:
    profiles: ["staging"]
    environment:
      - APP_ENV=staging
```

Puis démarrer avec :

```bash
docker-compose -f docker-compose.yml -f docker-compose.staging.yml --profile staging up -d
```

### Q: Comment désactiver watchtower temporairement ?

**R:** Watchtower fait partie du profile "tools". Ne démarrez pas avec ce profile ou arrêtez-le spécifiquement :

```bash
docker-compose stop watchtower
```

### Q: Peut-on mélanger les profiles avec l'ancien système ?

**R:** L'ancien système `deploy.replicas: 0` a été supprimé de `docker-compose.prod.yml`. Tout est maintenant géré par les profiles.

### Q: Comment voir la configuration finale avec tous les overrides ?

**R:** Utilisez la commande `config` :

```bash
# Configuration développement avec profiles
docker-compose -f docker-compose.yml -f docker-compose.dev.yml --profile dev --profile tools config
```

---

## 📝 Changelog

### Version 2.0 (Janvier 2026)

- ✨ Introduction des Docker Compose Profiles
- ♻️ Refactoring complet de l'architecture modulaire
- 🗑️ Suppression du système `deploy.replicas: 0`
- 📚 Documentation complète de l'architecture
- 🛠️ Ajout des commandes Makefile dédiées
- ➕ Ajout du profile "dev-extra" pour outils additionnels

### Version 1.0 (Décembre 2025)

- Architecture basique avec fichiers d'override
- Système `deploy.replicas: 0` pour désactiver les services

---

**💡 Conseil** : Pour le développement local, utilisez toujours `make up-local` pour bénéficier de tous les outils disponibles !
