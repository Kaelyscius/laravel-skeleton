# Guide de Migration - Architecture Modulaire Docker Profiles

## 🎯 Changements apportés

Votre architecture Docker a été modernisée avec **Docker Compose Profiles** pour une gestion modulaire des services.

### ✅ Ce qui a été fait

1. **docker-compose.yml** - Ajout des profiles sur les services
2. **docker-compose.dev.yml** - Mise à jour pour utiliser les profiles
3. **docker-compose.prod.yml** - Simplification (plus besoin de `deploy.replicas: 0`)
4. **Makefile** - Ajout de nouvelles commandes dédiées aux profiles
5. **DOCKER-ARCHITECTURE.md** - Documentation complète de l'architecture
6. **CLAUDE.md** - Mise à jour avec les nouvelles commandes

---

## 🚀 Migration rapide

### Avant (anciennes commandes)

```bash
# Développement
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up -d

# Production
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

### Après (nouvelles commandes)

```bash
# Développement local (RECOMMANDÉ)
make up-local

# Production
make up-prod

# Développement sans monitoring
make up-dev
```

---

## 📋 Tableau de correspondance

| Ancien | Nouveau | Description |
|--------|---------|-------------|
| `make up` | `make up-local` | Développement local complet |
| `docker-compose up` | `make up-prod` | Services essentiels uniquement |
| `docker-compose -f ... -f ... up` | `make up-dev` | Développement avec profiles |

---

## 🎯 Commandes essentielles à retenir

### Pour le développement local

```bash
# Démarrer avec tous les outils (recommandé)
make up-local

# Voir les services actifs
make ps-profiles

# Voir les logs
make logs
```

### Pour la production

```bash
# Démarrer en production (services essentiels uniquement)
make up-prod

# Vérifier le statut
make status
```

---

## 📦 Comprendre les profiles

### Services toujours actifs (aucun profile)
- **apache** : Serveur web
- **php** : PHP-FPM
- **mariadb** : Base de données
- **redis** : Cache

### Profile "dev" (Outils de développement)
- **node** : Build frontend (Vite/npm)
- **mailhog** : Test emails (port 8025)
- **adminer** : Gestion BDD (port 8080)

### Profile "tools" (Monitoring)
- **dozzle** : Logs en temps réel (port 9999)
- **it-tools** : Utilitaires dev (port 8081)
- **watchtower** : Mises à jour auto

### Profile "dev-extra" (Outils additionnels)
- **phpmyadmin** : Alternative Adminer (port 8083)
- **redis-commander** : Gestion Redis (port 8082)

---

## 🔄 Scénarios de migration

### Scénario 1 : Vous développez localement

**Avant** :
```bash
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up -d
```

**Après** :
```bash
make up-local
```

**Ce qui démarre** :
- ✅ Services essentiels (apache, php, mariadb, redis)
- ✅ Outils dev (node, mailhog, adminer)
- ✅ Outils monitoring (dozzle, it-tools, watchtower)

---

### Scénario 2 : Vous déployez en production

**Avant** :
```bash
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

**Après** :
```bash
make up-prod
```

**Ce qui démarre** :
- ✅ Services essentiels uniquement (apache, php, mariadb, redis)
- ❌ Aucun outil de développement
- ❌ Aucun outil de monitoring

---

### Scénario 3 : Vous voulez seulement les services essentiels + Node.js

**Avant** :
```bash
# Pas facile à faire, nécessitait de modifier les fichiers
```

**Après** :
```bash
make up-dev
```

**Ce qui démarre** :
- ✅ Services essentiels (apache, php, mariadb, redis)
- ✅ Node.js pour builds
- ✅ MailHog et Adminer
- ❌ Pas de monitoring (dozzle, it-tools, watchtower)

---

### Scénario 4 : Ajouter le monitoring à un environnement existant

**Avant** :
```bash
# Nécessitait de redémarrer tout avec un autre fichier compose
```

**Après** :
```bash
make up-tools
```

**Ce qui démarre** :
- ✅ Dozzle, IT-Tools, Watchtower uniquement
- ℹ️ Les autres services continuent de fonctionner normalement

---

## 🛠️ Commandes de diagnostic

### Voir ce qui tourne actuellement

```bash
# Afficher les services par profile
make ps-profiles

# Résultat exemple :
# 📋 Services actifs par profile:
#
# 🏭 PRODUCTION (aucun profile):
#   ✓ laravel-app_apache
#   ✓ laravel-app_php
#   ✓ laravel-app_mariadb
#   ✓ laravel-app_redis
#
# 🛠️ DEV (profile: dev):
#   ✓ laravel-app_node
#   ✓ laravel-app_mailhog
#   ✓ laravel-app_adminer
#
# 🔧 TOOLS (profile: tools):
#   ✓ laravel-app_dozzle
#   ✓ laravel-app_it-tools
#   ✓ laravel-app_watchtower
```

### Statut détaillé

```bash
make status
```

---

## ⚠️ Points d'attention

### 1. Commande `make up` vs `make up-local`

- **`make up`** : Démarre seulement les services essentiels (ancien comportement de base)
- **`make up-local`** : Démarre tous les services (recommandé pour le développement local)

**Recommandation** : Utilisez `make up-local` pour le développement.

### 2. Production : Aucun profile à activer

En production, **ne démarrez AUCUN profile**. Utilisez uniquement :

```bash
make up-prod
```

Cela garantit que seuls les services essentiels démarrent.

### 3. Watchtower maintenant dans le profile "tools"

Si vous voulez les mises à jour automatiques, vous devez activer le profile "tools" :

```bash
make up-dev-full
# ou
make up-tools
```

### 4. docker-compose.override.yml reste compatible

Votre fichier `docker-compose.override.yml` généré automatiquement reste compatible avec cette nouvelle architecture.

---

## 📚 Documentation complète

Pour plus de détails, consultez :

- **[DOCKER-ARCHITECTURE.md](DOCKER-ARCHITECTURE.md)** - Documentation complète de l'architecture
- **[CLAUDE.md](../CLAUDE.md)** - Toutes les commandes disponibles

---

## 🆘 Aide et troubleshooting

### Problème : "Un service ne démarre pas"

**Solution** : Vérifiez que vous avez activé le bon profile

```bash
# Voir les services actifs
make ps-profiles

# Si un service manque, démarrez le profile correspondant
make up-dev      # Pour les outils dev
make up-tools    # Pour le monitoring
make up-dev-extra # Pour les outils extra
```

### Problème : "Je veux tout redémarrer"

```bash
# Arrêter tout
make down

# Redémarrer en mode développement complet
make up-local
```

### Problème : "Comment désactiver un profile ?"

```bash
# Arrêter un profile spécifique
make stop-profile PROFILE=tools

# Ou arrêter tout et redémarrer sans le profile
make down
make up-dev  # Sans le profile tools
```

---

## 💡 Exemples pratiques

### Développement frontend uniquement

```bash
# Services essentiels + Node.js + MailHog + Adminer
make up-dev
```

### Développement avec monitoring complet

```bash
# Tous les services + monitoring
make up-local
```

### Production optimisée

```bash
# Uniquement les services nécessaires
make up-prod
```

### Développement avec TOUS les outils

```bash
# Services + dev + tools + extras (phpmyadmin, redis-commander)
make up-dev-extra
```

---

## ✅ Checklist de migration

- [ ] J'ai lu ce guide de migration
- [ ] J'ai compris les différents profiles disponibles
- [ ] J'ai testé `make up-local` pour le développement local
- [ ] J'ai lu la documentation complète dans [DOCKER-ARCHITECTURE.md](DOCKER-ARCHITECTURE.md)
- [ ] J'ai vérifié que mes scripts CI/CD utilisent `make up-prod`
- [ ] J'ai mis à jour ma documentation projet si nécessaire

---

## 🎉 Avantages de cette nouvelle architecture

✅ **Clarté** : Chaque service a son rôle et son profile
✅ **Performance** : Ne démarrez que ce dont vous avez besoin
✅ **Simplicité** : Commandes claires et explicites
✅ **Flexibilité** : Activez/désactivez des groupes de services facilement
✅ **Standard** : Utilise les fonctionnalités natives de Docker Compose
✅ **Production-ready** : Déploiement propre sans outils de dev

---

**💬 Questions ?** Consultez [DOCKER-ARCHITECTURE.md](DOCKER-ARCHITECTURE.md) ou utilisez `make help-profiles` pour l'aide intégrée.
