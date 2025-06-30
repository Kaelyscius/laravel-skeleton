# 🚀 Environnement Docker Laravel 12

Environnement de développement Docker complet et optimisé pour Laravel 12 avec PHP 8.4, MariaDB, Redis, Apache, Node.js et des outils de monitoring et d'industrialisation.

## 📋 Prérequis

- Docker >= 24.0
- Docker Compose >= 2.20
- Make
- Git
- WSL2 (pour Windows)
- Au moins 4GB de RAM disponible
- 10GB d'espace disque libre

## 🛠️ Stack Technique

### Containers principaux
- **Apache 2.4** (HTTPS, HTTP/2, SSL) - Ports 80/443
- **PHP 8.4** (FPM + Supervisor + OPcache)
- **MariaDB** (dernière version stable)
- **Redis Alpine** (cache, sessions, queues)
- **Node.js 20 LTS** (build des assets frontend)

### Outils de développement et monitoring
- **MailHog** - Capture des emails de développement
- **Adminer** - Interface web pour les bases de données
- **IT-Tools** - Boîte à outils pour développeurs
- **Dozzle** - Monitoring des logs en temps réel
- **🔄 Watchtower** - Mises à jour automatiques des containers

### Extensions et packages Laravel
- **Laravel Horizon** - Gestion avancée des queues
- **Laravel Telescope** - Débogage et monitoring
- **Laravel Sanctum** - Authentification API
- **PHPStan/Larastan** - Analyse statique de code
- **Rector** - Refactoring automatique PHP
- **ECS** - Code style et formatage
- **PHP Insights** - Analyse globale de qualité
- **Laravel IDE Helper** - Autocomplétion IDE
- **Laravel Query Detector** - Détection requêtes N+1
- **Enlightn** - Audit sécurité et performance
- **Pest** - Framework de tests moderne
- **Xdebug** - Débogage (activable à la demande)

## 🌐 Accès aux services

Une fois le projet démarré, voici tous les accès disponibles :

### Application principale
- **🏠 Laravel** : https://laravel.local
- **📊 Laravel Horizon** : https://laravel.local/horizon
- **🔭 Laravel Telescope** : https://laravel.local/telescope

### Outils de développement
- **🛠️ IT-Tools** : http://localhost:8081
  - Convertisseurs, générateurs, encodeurs
  - Hash, Base64, JWT, UUID, etc.
  - Outils réseau et développement
- **💾 Adminer** : http://localhost:8080
  - Interface graphique pour MariaDB
  - Serveur : `mariadb`, utilisateur selon votre `.env`
- **📧 MailHog** : http://localhost:8025
  - Capture tous les emails envoyés par Laravel
  - Interface web pour consulter les emails
- **📋 Dozzle** : http://localhost:9999
  - Logs en temps réel de tous les containers
  - Interface web moderne et responsive

### 📊 Monitoring et maintenance
- **🔄 Watchtower** : Service automatique (pas d'interface)
  - Mises à jour automatiques des containers
  - Planifié tous les jours à 3h du matin
  - Notifications des mises à jour (configurables)
  - Rollback automatique en cas de problème

## 🚀 Installation rapide

```bash
# Cloner le projet
git clone [votre-repo]
cd [votre-projet]

# Copier et configurer l'environnement
cp .env.example .env
# Éditer .env selon vos besoins

# Installation complète automatique (avec monitoring)
make install

# Configurer le monitoring (après installation)
make setup-monitoring

# Ou installation manuelle
make setup-ssl           # Génère les certificats SSL
make build              # Construit les images Docker
make up                 # Démarre les containers
make install-laravel    # Installe Laravel et ses dépendances
make migrate            # Lance les migrations
```

**Important :** Ajouter à votre `/etc/hosts` :
```
127.0.0.1 laravel.local
```

## 📚 Commandes Make disponibles

### 🏗️ Installation et Build
```bash
make install          # Installation complète du projet
make build           # Construire tous les containers
make build-parallel  # Build en parallèle (plus rapide)
make rebuild         # Reconstruire et redémarrer
make setup-ssl       # Générer les certificats SSL
```

### 🎮 Contrôle des containers
```bash
make up              # Démarrer tous les containers
make down            # Arrêter tous les containers
make restart         # Redémarrer tous les containers
make status          # Voir le statut des containers
make logs            # Voir tous les logs
make logs-php        # Logs PHP uniquement
make logs-apache     # Logs Apache uniquement
make logs-node       # Logs Node uniquement
```

### 🐘 Laravel et PHP
```bash
make artisan cmd="migrate"        # Commande artisan
make artisan cmd="make:model User" # Créer un modèle
make composer cmd="install"       # Commande composer
make composer cmd="require package" # Installer un package
make migrate                     # Lancer les migrations
make seed                        # Lancer les seeders
make fresh                       # Reset DB + migrations + seeds
make horizon                     # Démarrer Horizon
make queue                       # Démarrer les workers
```

### 🎨 Frontend et Assets
```bash
make npm cmd="install"           # Installer les dépendances npm
make npm-install                # Installer les dépendances NPM
make npm-build                  # Build de production
make npm-dev                    # Démarrer le serveur de développement
make npm-watch                  # Watch des changements
make pnpm-build                 # Builder avec pnpm (plus rapide)
```

### 🧪 Tests et Qualité de code
```bash
make test            # Lancer tous les tests
make test-unit       # Tests unitaires uniquement
make test-feature    # Tests de fonctionnalités
make test-coverage   # Tests avec rapport de couverture
make test-parallel   # Tests en parallèle
make test-all        # Tous les types de tests

# Outils de qualité
make phpstan         # Analyse statique PHPStan/Larastan
make ecs             # Vérifier le code style
make ecs-fix         # Corriger automatiquement le style
make rector          # Analyse Rector (dry-run)
make rector-fix      # Appliquer les suggestions Rector
make insights        # Analyse PHP Insights
make insights-fix    # PHP Insights avec corrections
make enlightn        # Audit sécurité et performance
make ide-helper      # Générer les fichiers IDE Helper

# Commandes groupées
make quality         # Vérification de base (ECS + PHPStan)
make quality-fix     # Corrections automatiques
make quality-full    # Audit complet (ECS + PHPStan + Insights + Enlightn + Tests)
make quality-report  # Générer des rapports de qualité
make security-check  # Vérifier les vulnérabilités
make security-fix    # Corriger les vulnérabilités
```

### 📊 Monitoring et maintenance
```bash

# Watchtower (mises à jour automatiques)
make watchtower-logs     # Voir les logs des mises à jour
make watchtower-update-now   # Forcer une mise à jour immédiate
make watchtower-status   # Statut de Watchtower
```

### 🚀 Workflows de développement
```bash
make dev             # Environnement de développement complet
make dev-fresh       # Base de données fraîche + assets
make dev-quality     # Vérifier qualité + builder assets
make pre-commit      # Vérifications avant commit
make pre-push        # Vérifications avant push
make deploy-check    # Vérifications avant déploiement
make daily-check     # Vérifications quotidiennes
```

### 🔍 Accès aux containers
```bash
make shell           # Shell dans le container PHP
make shell-php       # Shell PHP (alias)
make shell-apache    # Shell dans le container Apache
make shell-node      # Shell dans le container Node
make shell-mariadb   # Console MySQL/MariaDB
```

### 🧹 Maintenance et nettoyage
```bash
make clean           # Nettoyer containers et volumes
make clean-all       # Tout nettoyer (avec images)
make clean-reports   # Nettoyer les rapports de qualité
make prune           # Nettoyer Docker (images inutilisées)
make healthcheck     # Vérifier la santé des services
make stats           # Statistiques des containers
make diagnose        # Diagnostic complet du projet
make update-deps     # Mettre à jour les dépendances
```

## ⚙️ Configuration

### Variables d'environnement

Copiez `.env.example` vers `.env` et configurez :

```env
# Application
APP_NAME=Laravel
APP_ENV=local
APP_KEY=base64:your-app-key-here
APP_DEBUG=true
APP_URL=https://laravel.local

# Docker
COMPOSE_PROJECT_NAME=laravel-app

# Base de données
DB_CONNECTION=mysql
DB_HOST=mariadb
DB_PORT=3306
DB_DATABASE=laravel
DB_USERNAME=laravel_user
DB_PASSWORD=secure_password
DB_ROOT_PASSWORD=root_password

# Redis
REDIS_HOST=redis
REDIS_PASSWORD=redis_secret_password
REDIS_PORT=6379

# Email (développement)
MAIL_MAILER=smtp
MAIL_HOST=mailhog
MAIL_PORT=1025
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_ENCRYPTION=null

# Monitoring - Watchtower Notifications (optionnel)
WATCHTOWER_NOTIFICATION_URL=

# Exemples de notifications Watchtower :
# Discord: discord://token@channel_id
# Slack: slack://hook_url  
# Email: smtp://username:password@host:port/?from=from@example.com&to=to@example.com

# Xdebug (optionnel)
XDEBUG_ENABLE=false
XDEBUG_MODE=debug
XDEBUG_CLIENT_HOST=host.docker.internal
```

### Environnements spécialisés

#### 🛠️ Développement
```bash
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up -d
```
**Inclut :**
- Xdebug activé
- OPcache désactivé pour le développement
- Logs verbeux et détaillés
- Volumes en mode `:delegated` pour de meilleures performances

#### 🚀 Production
```bash
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```
**Optimisé pour :**
- OPcache activé avec preload
- Logs limités et rotatifs
- Ressources CPU/mémoire limitées
- Services de développement désactivés
- Sécurité renforcée

### 🔐 SSL/HTTPS

Le projet utilise HTTPS par défaut avec des certificats auto-signés.

#### Génération des certificats
```bash
make setup-ssl
```

#### Installation des certificats (éviter les avertissements)
- **🐧 Linux** :
  ```bash
  sudo cp docker/apache/conf/ssl/laravel.local.crt /usr/local/share/ca-certificates/
  sudo update-ca-certificates
  ```
- **🍎 macOS** :
  ```bash
  sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain docker/apache/conf/ssl/laravel.local.crt
  ```
- **🪟 Windows** : Importer le certificat dans le magasin de certificats de confiance


### 🔍 Configuration initiale

```bash
# Démarrer tous les services
make up

# Lancer la configuration assistée
make setup-monitoring
```

### Interface de monitoring

1. **Ouvrez** http://localhost:3001
2. **Créez** votre compte administrateur (première connexion)
3. **Configurez** votre profil et préférences

### 📱 Moniteurs recommandés

#### Services critiques (alertes immédiates)
```
Laravel Application
- URL: https://laravel.local
- Type: HTTP(s)
- Interval: 60 secondes
- Tag: critical

Base de données MariaDB
- Host: localhost
- Port: 3306  
- Type: Port
- Interval: 120 secondes
- Tag: critical

Redis Cache
- Host: localhost
- Port: 6379
- Type: Port
- Interval: 120 secondes
- Tag: critical
```

#### Services importants (alertes après 3 échecs)
```
Laravel Horizon: https://laravel.local/horizon
Laravel Telescope: https://laravel.local/telescope
Adminer: http://localhost:8080
MailHog: http://localhost:8025
IT-Tools: http://localhost:8081
Dozzle: http://localhost:9999
```

#### Sécurité (alerte 30 jours avant expiration)
```
Certificat SSL Laravel
- URL: https://laravel.local
- Type: SSL Certificate
- Interval: 1 jour
- Alerte: 30 jours avant expiration
```

### 🔔 Configuration des notifications

#### Discord
1. Créez un webhook dans votre serveur Discord
2. Settings → Notifications → Add Discord
3. Collez l'URL du webhook

#### Slack
1. Créez une app Slack avec webhook
2. Settings → Notifications → Add Slack
3. Collez l'URL du webhook

#### Email
1. Settings → Notifications → Add Email (SMTP)
2. Configurez votre serveur SMTP
3. Testez la notification

### 📈 Status Page (optionnel)
1. Status Pages → Add New Status Page
2. Sélectionnez les moniteurs à afficher
3. Personnalisez l'apparence
4. Partagez l'URL avec votre équipe

## 🔄 Mises à jour automatiques avec Watchtower

### Fonctionnement
- **Planification** : Tous les jours à 3h du matin
- **Vérification** : Nouvelles versions des images Docker
- **Mise à jour** : Automatique avec rollback si échec
- **Nettoyage** : Suppression des anciennes images

### Containers surveillés
**✅ Mis à jour automatiquement :**
- MariaDB
- Redis
- MailHog
- Adminer
- IT-Tools
- Dozzle

**❌ Exclus (images custom) :**
- PHP (contient votre code applicatif)
- Apache (configuration SSL personnalisée)
- Node (outils de build personnalisés)

### 📧 Configuration des notifications

Ajoutez dans votre `.env` pour recevoir des notifications de mises à jour :

```env
# Discord
WATCHTOWER_NOTIFICATION_URL=discord://token@channel_id

# Slack
WATCHTOWER_NOTIFICATION_URL=slack://hook_url

# Email
WATCHTOWER_NOTIFICATION_URL=smtp://user:pass@host:port/?from=from@example.com&to=to@example.com

# Microsoft Teams
WATCHTOWER_NOTIFICATION_URL=teams://token@tenant/altId/groupOwner?host=outlook.office.com
```

Puis redémarrez Watchtower :
```bash
make restart
```

### Commandes utiles
```bash
# Voir les logs des mises à jour
make watchtower-logs

# Forcer une mise à jour immédiate
make watchtower-update-now

# Vérifier le statut
make watchtower-status
```

## 🐛 Débogage avec Xdebug

### Activation
```bash
# Méthode 1 : Variable d'environnement
XDEBUG_ENABLE=true docker-compose up -d php

# Méthode 2 : Modifier .env
echo "XDEBUG_ENABLE=true" >> .env
make restart
```

### Configuration VSCode
Créer `.vscode/launch.json` :
```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Listen for Xdebug",
      "type": "php",
      "request": "launch",
      "port": 9003,
      "pathMappings": {
        "/var/www/html": "${workspaceFolder}/src"
      },
      "ignore": ["**/vendor/**/*.php"]
    }
  ]
}
```

### Configuration PhpStorm
1. **File → Settings → PHP → Servers**
2. **Name** : `laravel.local`
3. **Host** : `laravel.local`
4. **Port** : `443`
5. **Path mappings** : `./src` → `/var/www/html`

## 📊 Monitoring et observabilité

### 📋 Logs
- **Dozzle** : http://localhost:9999 - Interface moderne pour tous les logs
- **Commandes** : `make logs`, `make logs-follow`
- **Laravel logs** : `src/storage/logs/`

### 🏥 Health checks
```bash
make healthcheck    # Vérifier tous les services
make status        # État des containers
make stats         # Statistiques de performance
make diagnose      # Diagnostic complet avec monitoring
make monitoring-status  # État du monitoring spécifiquement
```

### 📈 Métriques
- **Docker stats** : `make stats`
- **Horizon dashboard** : https://laravel.local/horizon

### 💾 Bases de données
- **Adminer** : http://localhost:8080
  - Interface moderne et complète
  - Support MySQL/MariaDB, PostgreSQL, SQLite
  - Import/export, éditeur SQL avancé

### 📧 Gestion des emails
- **MailHog** : http://localhost:8025
- Capture automatique de tous les emails
- Interface web pour consultation
- API REST disponible

### 🗄️ Cache et queues
- **Horizon** : https://laravel.local/horizon (queues Laravel)
- **Redis** : Accessible via CLI avec `make shell` puis `redis-cli`

## 🔧 Outils de développement

### 🛠️ IT-Tools (http://localhost:8081)
Boîte à outils complète pour développeurs :
- **Encodeurs/Décodeurs** : Base64, URL, HTML
- **Générateurs** : UUID, mots de passe, couleurs
- **Hash et crypto** : MD5, SHA, JWT decoder
- **Convertisseurs** : JSON, YAML, timestamps
- **Outils réseau** : IP info, QR codes
- **Et bien plus !**

### 🔍 Analyseurs de code
```bash
make phpstan      # Analyse statique PHPStan/Larastan
make ecs          # Style de code (ECS)
make rector       # Modernisation du code (Rector)
make insights     # Analyse globale (PHP Insights)
make enlightn     # Audit sécurité et performance
```

### 🧪 Tests
```bash
make test                    # Tous les tests
make test-coverage          # Avec couverture
make test-unit             # Tests unitaires
make test-feature          # Tests d'intégration
make test-parallel         # Tests en parallèle
```

## 🔐 Sécurité

### Mesures implémentées
- ✅ Containers non-root avec utilisateurs dédiés
- ✅ HTTPS obligatoire avec HTTP/2
- ✅ Headers de sécurité configurés (HSTS, CSP, etc.)
- ✅ Secrets isolés dans `.env` (non versionné)
- ✅ Healthchecks sur tous les services
- ✅ Certificats SSL avec chiffrement fort
- ✅ Isolation réseau entre containers
- ✅ Monitoring 24/7 avec alertes
- ✅ Mises à jour automatiques de sécurité

### Scan de sécurité
```bash
make security-check    # Scanner les vulnérabilités
make enlightn         # Audit sécurité Laravel
make security-fix     # Corriger automatiquement
```

## 🚢 CI/CD avec GitHub Actions

Le projet inclut un workflow complet :

### Tests automatiques
- ✅ Tests unitaires et d'intégration
- ✅ Couverture de code (minimum 80%)
- ✅ Tests de performance

### Analyse de code
- ✅ PHPStan/Larastan
- ✅ ECS (code style)
- ✅ PHP Insights (qualité globale)
- ✅ Rector (suggestions)

### Sécurité
- ✅ Enlightn (audit Laravel)
- ✅ Audit des dépendances
- ✅ Scan des vulnérabilités

### Déploiement
- ✅ Build et push des images
- ✅ Déploiement automatique
- ✅ Rollback en cas d'échec

## 📂 Structure du projet

```
project/
├── 🐳 docker/                    # Configuration Docker
│   ├── apache/                  # Container Apache + SSL
│   ├── php/                     # Container PHP + extensions
│   ├── node/                    # Container Node.js
│   ├── mariadb/                 # Configuration MariaDB
│   ├── supervisor/              # Configuration Supervisor
│   └── scripts/                 # Scripts d'installation
├── 🔧 scripts/                   # Scripts utilitaires
├── 🎯 src/                       # Code source Laravel
├── ⚙️ .github/workflows/         # GitHub Actions
├── 📊 docker-compose.yml         # Configuration principale
├── 🛠️ docker-compose.dev.yml     # Configuration développement
├── 🚀 docker-compose.prod.yml    # Configuration production
├── 🏗️ Makefile                   # Commandes make
├── 📋 .env.example               # Variables d'environnement
└── 📖 README.md                  # Cette documentation
```

## 🐞 Dépannage

### Problèmes courants

#### Container n'arrive pas à démarrer
```bash
make logs           # Voir les erreurs
make healthcheck    # Vérifier l'état
make diagnose       # Diagnostic complet
make rebuild        # Reconstruire si nécessaire
```

#### Watchtower ne fonctionne pas
```bash
make watchtower-logs            # Voir les logs
make watchtower-status          # Vérifier le statut
docker-compose restart watchtower   # Redémarrer
```

#### Certificats SSL invalides
```bash
make setup-ssl      # Régénérer les certificats
sudo rm -rf docker/apache/conf/ssl/
make setup-ssl
```

#### Problèmes de permissions
```bash
# Linux/macOS
sudo chown -R $USER:$USER src/
sudo chmod -R 755 src/

# Voir les permissions dans le container
make shell
ls -la /var/www/html
```

#### Problèmes de mémoire
```bash
# Augmenter la mémoire Docker
# Windows/macOS : Docker Desktop → Settings → Resources
# Linux : Modifier /etc/docker/daemon.json
```

#### Base de données non accessible
```bash
make shell-mariadb                    # Vérifier la connexion
make logs mariadb                     # Voir les logs MariaDB
docker-compose exec mariadb mysql -u root -p${DB_ROOT_PASSWORD}
```

### Commandes de diagnostic
```bash
make healthcheck      # État de tous les services
make diagnose         # Diagnostic complet avec vérifications
make monitoring-status # État du monitoring
make stats           # Utilisation des ressources
docker system df     # Espace Docker détaillé
docker system prune  # Nettoyer Docker
```
Créez un hook git à la racine du projet pour automatiser les vérifications :
# Depuis la racine du projet (pas src/)
mkdir -p .git/hooks

cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash

echo "🔍 Vérifications de qualité avant commit..."

# Aller à la racine du projet
cd "$(git rev-parse --show-toplevel)"

# Vérifier que Docker est en cours
if ! docker ps >/dev/null 2>&1; then
echo "❌ Docker n'est pas en cours d'exécution"
exit 1
fi

# Lancer les vérifications de qualité
echo "→ Vérification du style de code..."
if ! make ecs; then
echo "❌ Erreurs de style détectées"
echo "💡 Corrigez avec: make ecs-fix"
exit 1
fi

echo "→ Analyse statique..."
if ! make phpstan; then
echo "❌ Erreurs PHPStan détectées"
echo "💡 Consultez les erreurs ci-dessus"
exit 1
fi

echo "→ Tests unitaires..."
if ! make test-unit; then
echo "❌ Tests unitaires échoués"
exit 1
fi

echo "✅ Toutes les vérifications sont passées !"
echo "🚀 Commit autorisé"
EOF

# Rendre le hook exécutable
chmod +x .git/hooks/pre-commit

## 🚀 Optimisations de performance

### Développement
- Volumes en mode `:delegated` (macOS/Windows)
- OPcache désactivé pour les changements instantanés
- Xdebug activable à la demande

### Production
- OPcache optimisé avec preload
- Assets minifiés et compressés
- Redis pour cache et sessions
- Compression Gzip/Brotli


## 🤝 Contribution

1. **Fork** le projet
2. **Créer** une branche (`git checkout -b feature/amazing-feature`)
3. **Commit** vos changements (`git commit -m 'Add amazing feature'`)
4. **Push** vers la branche (`git push origin feature/amazing-feature`)
5. **Créer** une Pull Request

### Standards de code
- Suivre PSR-12
- Tests obligatoires pour les nouvelles fonctionnalités
- Documentation à jour
- Passage des vérifications qualité (`make quality-full`)

## 📄 Licence

[Votre licence]

## 🙏 Support et aide

### Documentation
- **Laravel** : https://laravel.com/docs
- **Docker** : https://docs.docker.com
- **Docker Compose** : https://docs.docker.com/compose
- **Watchtower** : https://containrrr.dev/watchtower/

### Communauté
- Ouvrir une [issue](issues) pour les bugs
- Consulter les [discussions](discussions) pour les questions
- Rejoindre notre [Discord/Slack] pour l'aide en temps réel

### Maintenance
Ce projet est activement maintenu. Les mises à jour incluent :
- Nouvelles versions de Laravel
- Mises à jour de sécurité Docker
- Optimisations de performance
- Nouveaux outils de développement
- Amélioration du monitoring et des alertes

---

*Fait avec ❤️ pour la communauté Laravel*