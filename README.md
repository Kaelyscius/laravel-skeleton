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

### Extensions et packages Laravel
- **Laravel Horizon** - Gestion avancée des queues
- **Laravel Telescope** - Débogage et monitoring
- **Laravel Sanctum** - Authentification API
- **Livewire** - Composants réactifs
- **PHPStan/Larastan** - Analyse statique de code
- **Rector** - Refactoring automatique PHP
- **ECS** - Code style et formatage
- **Xdebug** - Débogage (activable à la demande)

## 🌐 Accès aux services

Une fois le projet démarré, voici tous les accès disponibles :

### Application principale
- **🏠 Laravel** : https://laravel.local
- **📊 Laravel Horizon** : https://laravel.local/horizon
- **🔭 Laravel Telescope** : https://laravel.local/telescope

### Outils de développement
- **🛠️ IT-Tools** : http://localhost:8081 *(Nouveau !)*
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

### Environnement de développement
- **📁 PHPMyAdmin** (dev uniquement) : http://localhost:8082
- **🗄️ Redis Commander** (dev uniquement) : http://localhost:8083

## 🚀 Installation rapide

```bash
# Cloner le projet
git clone [votre-repo]
cd [votre-projet]

# Copier et configurer l'environnement
cp .env.example .env
# Éditer .env selon vos besoins

# Installation complète automatique
make install

# Ou installation manuelle
make setup-ssl           # Génère les certificats SSL
make build              # Construit les images Docker
make up                 # Démarre les containers
make laravel-install    # Installe Laravel et ses dépendances
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
make ps              # Liste des containers actifs
make logs            # Voir tous les logs
make logs-php        # Logs PHP uniquement
make logs-apache     # Logs Apache uniquement
make logs-follow     # Suivre les logs en temps réel
```

### 🐘 Laravel et PHP
```bash
make artisan cmd="migrate"        # Commande artisan
make artisan cmd="make:model User" # Créer un modèle
make composer cmd="install"       # Commande composer
make composer cmd="require package" # Installer un package
make migrate                     # Lancer les migrations
make migrate-fresh              # Reset DB + migrations
make seed                        # Lancer les seeders
make fresh                       # Reset DB + migrations + seeds
make tinker                      # Ouvrir Laravel Tinker
make horizon                     # Démarrer Horizon
make queue                       # Démarrer les workers
make cache-clear                # Vider les caches Laravel
make config-clear               # Vider le cache de config
```

### 🎨 Frontend et Assets
```bash
make npm cmd="install"           # Installer les dépendances npm
make npm cmd="run dev"          # Build de développement
make npm cmd="run build"        # Build de production
make npm cmd="run watch"        # Watch des changements
make vite                       # Démarrer Vite en mode dev
```

### 🧪 Tests et Qualité de code
```bash
make test            # Lancer tous les tests
make test-unit       # Tests unitaires uniquement
make test-feature    # Tests de fonctionnalités
make test-coverage   # Tests avec rapport de couverture
make phpstan         # Analyse statique PHPStan
make larastan        # Analyse Larastan (PHPStan pour Laravel)
make ecs             # Vérifier le code style
make ecs-fix         # Corriger automatiquement le style
make rector          # Analyse Rector (dry-run)
make rector-fix      # Appliquer les suggestions Rector
make quality         # Lancer toutes les vérifications qualité
make security-check  # Scanner les vulnérabilités
```

### 🔍 Accès aux containers
```bash
make shell           # Shell dans le container PHP
make shell-php       # Shell PHP (alias)
make shell-apache    # Shell dans le container Apache
make shell-node      # Shell dans le container Node
make shell-mariadb   # Console MySQL/MariaDB
make shell-redis     # Console Redis
```

### 🧹 Maintenance et nettoyage
```bash
make clean           # Nettoyer containers et volumes
make clean-all       # Tout nettoyer (avec images)
make clean-logs      # Vider les logs Docker
make prune           # Nettoyer Docker (images inutilisées)
make healthcheck     # Vérifier la santé des services
make stats           # Statistiques des containers
make disk-usage      # Usage disque de Docker
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
- PHPMyAdmin (port 8082)
- Redis Commander (port 8083)
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

## 🐛 Débogage avec Xdebug

### Activation
```bash
# Méthode 1 : Variable d'environnement
XDEBUG_ENABLE=true docker-compose up -d php

# Méthode 2 : Modifier .env
echo "XDEBUG_ENABLE=true" >> .env
make restart-php
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
```

### 📈 Métriques
- **Docker stats** : `make stats`
- **Disk usage** : `make disk-usage`
- **Horizon dashboard** : https://laravel.local/horizon

### 💾 Bases de données
- **Adminer** : http://localhost:8080 (production-ready)
- **PHPMyAdmin** : http://localhost:8082 (développement uniquement)

### 📧 Gestion des emails
- **MailHog** : http://localhost:8025
- Capture automatique de tous les emails
- Interface web pour consultation
- API REST disponible

### 🗄️ Cache et queues
- **Redis Commander** : http://localhost:8083 (développement)
- **Horizon** : https://laravel.local/horizon (queues Laravel)

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
make phpstan      # Analyse statique
make larastan     # Spécifique à Laravel
make ecs          # Style de code
make rector       # Modernisation du code
```

### 🧪 Tests
```bash
make test                    # Tous les tests
make test-coverage          # Avec couverture
make test-unit             # Tests unitaires
make test-feature          # Tests d'intégration
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

### Scan de sécurité
```bash
make security-check    # Scanner les vulnérabilités
make audit            # Audit des dépendances
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
- ✅ Rector (suggestions)

### Sécurité
- ✅ Snyk (vulnérabilités)
- ✅ Trivy (images Docker)
- ✅ Audit des dépendances

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
make rebuild        # Reconstruire si nécessaire
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
make stats           # Utilisation des ressources
make disk-usage      # Espace disque utilisé
docker system df     # Espace Docker détaillé
docker system prune  # Nettoyer Docker
```

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
- Passage des vérifications qualité (`make quality`)

## 📄 Licence

[Votre licence]

## 🙏 Support et aide

### Documentation
- **Laravel** : https://laravel.com/docs
- **Docker** : https://docs.docker.com
- **Docker Compose** : https://docs.docker.com/compose

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

---

*Fait avec ❤️ pour la communauté Laravel*