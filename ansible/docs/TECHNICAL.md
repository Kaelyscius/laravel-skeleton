# Documentation Technique - Déploiement Ansible Laravel

## Table des matières
1. [Architecture générale](#architecture-générale)
2. [Structure des fichiers](#structure-des-fichiers)
3. [Configuration](#configuration)
4. [Rôles Ansible](#rôles-ansible)
5. [Variables](#variables)
6. [Sécurité](#sécurité)
7. [Monitoring](#monitoring)
8. [Dépannage](#dépannage)
9. [Développement](#développement)

## Architecture générale

Cette solution de déploiement Ansible est conçue pour déployer une application Laravel avec Docker sur différents environnements (développement, staging, production).

### Composants principaux
- **Ansible** : Orchestration du déploiement
- **Docker** : Conteneurisation des services
- **Laravel** : Application web PHP
- **MariaDB** : Base de données
- **Redis** : Cache et sessions
- **Apache** : Serveur web
- **Node.js** : Compilation des assets

### Flux de déploiement
```
1. Préparation du serveur (rôle common)
2. Installation Docker (rôle docker)
3. Configuration sécurité (rôle security)
4. Déploiement application (rôle laravel-app)
5. Configuration proxy (rôle nginx-proxy)
6. Mise en place monitoring (rôle monitoring)
```

## Structure des fichiers

```
ansible/
├── ansible.cfg                 # Configuration Ansible
├── activate.sh                 # Script d'activation environnement
├── inventories/                # Inventaires par environnement
│   ├── production/
│   │   └── hosts.yml
│   ├── staging/
│   │   └── hosts.yml
│   └── development/
│       └── hosts.yml
├── playbooks/                  # Playbooks principaux
│   └── deploy.yml
├── roles/                      # Rôles Ansible
│   ├── common/
│   ├── docker/
│   ├── laravel-app/
│   ├── nginx-proxy/
│   ├── monitoring/
│   └── security/
├── group_vars/                 # Variables par environnement
│   ├── all/
│   ├── production/
│   ├── staging/
│   └── development/
├── host_vars/                  # Variables par hôte
├── scripts/                    # Scripts utilitaires
│   ├── deploy.sh
│   ├── install.sh
│   ├── validate.sh
│   └── test.sh
├── templates/                  # Templates globaux
├── logs/                       # Logs Ansible
├── backups/                    # Sauvegardes
├── docs/                       # Documentation
├── CHANGELOG.md                # Historique des modifications
├── .gitignore                  # Protection des secrets
└── .env.example                # Template de configuration
```

## Configuration

### Fichier ansible.cfg
Configuration principale d'Ansible avec les paramètres optimisés pour le déploiement Laravel.

```ini
[defaults]
inventory = ./inventories/production/hosts.yml
remote_user = root
host_key_checking = False
gathering = smart
fact_caching = jsonfile
timeout = 30
forks = 10
```

### Inventaires
Définition des serveurs par environnement avec leurs paramètres spécifiques.

```yaml
all:
  children:
    web_servers:
      hosts:
        server1:
          ansible_host: 192.168.1.100
          deploy_path: /var/www/laravel-app
          project_name: laravel-prod
```

## Rôles Ansible

### Rôle Common
**Fichier**: `roles/common/tasks/main.yml`

**Responsabilités**:
- Mise à jour système
- Installation paquets de base
- Configuration timezone/locale
- Création utilisateurs
- Configuration limites système

**Variables principales**:
```yaml
system:
  timezone: "Europe/Paris"
  locale: "fr_FR.UTF-8"
  packages: [curl, wget, git, ...]
```

### Rôle Docker
**Fichier**: `roles/docker/tasks/main.yml`

**Responsabilités**:
- Installation Docker Engine
- Configuration daemon Docker
- Installation Docker Compose
- Configuration réseau Docker
- Scripts de nettoyage

**Variables principales**:
```yaml
docker:
  version: "24.0"
  compose_version: "2.21.0"
  daemon_options:
    storage-driver: overlay2
    log-driver: json-file
```

### Rôle Laravel-App
**Fichier**: `roles/laravel-app/tasks/main.yml`

**Responsabilités**:
- Clone du repository Git
- Configuration environnement (.env)
- Gestion des conteneurs Docker
- Installation dépendances (Composer, npm)
- Migrations base de données
- Optimisations Laravel

**Variables principales**:
```yaml
app_git_repo: "https://github.com/user/repo.git"
app_deploy_path: "/var/www/laravel-app"
app_project_name: "laravel-app"
laravel_env: "production"
```

### Rôle Security
**Fichier**: `roles/security/tasks/main.yml`

**Responsabilités**:
- Configuration firewall (UFW)
- Installation Fail2Ban
- Configuration SSH sécurisée
- Mise à jour automatiques
- Audit sécurité

### Rôle Nginx-Proxy
**Fichier**: `roles/nginx-proxy/tasks/main.yml`

**Responsabilités**:
- Configuration reverse proxy
- Gestion certificats SSL
- Load balancing
- Compression gzip
- Cache statique

### Rôle Monitoring
**Fichier**: `roles/monitoring/tasks/main.yml`

**Responsabilités**:
- Configuration Dozzle (logs Docker)
- Monitoring des services
- Alertes système
- Rotation des logs

## Variables

### Variables globales (group_vars/all/main.yml)
```yaml
system:
  timezone: "Europe/Paris"
  locale: "fr_FR.UTF-8"
  packages: [...]

docker:
  version: "24.0"
  compose_version: "2.21.0"

laravel:
  php_version: "8.2"
  node_version: "18"
```

### Variables par environnement
**Production** (`group_vars/production/main.yml`):
```yaml
environment: production
laravel_env: production
laravel_debug: false
laravel_log_level: error
ssl:
  enabled: true
  provider: letsencrypt
```

**Staging** (`group_vars/staging/main.yml`):
```yaml
environment: staging
laravel_env: staging
laravel_debug: false
laravel_log_level: info
ssl:
  enabled: true
  staging: true
```

**Development** (`group_vars/development/main.yml`):
```yaml
environment: development
laravel_env: local
laravel_debug: true
laravel_log_level: debug
ssl:
  enabled: false
```

## Sécurité

### Configuration SSH
```yaml
security:
  ssh:
    port: 22
    permit_root_login: "no"
    password_authentication: "no"
    pubkey_authentication: "yes"
    max_auth_tries: 3
```

### Firewall (UFW)
```yaml
security:
  ufw:
    enabled: true
    default_policy: deny
    logging: "on"
network:
  firewall:
    allowed_ports: ["22", "80", "443"]
    blocked_ports: ["3306", "6379"]
```

### Fail2Ban
```yaml
security:
  fail2ban:
    enabled: true
    bantime: 3600
    maxretry: 5
    findtime: 600
```

### Gestion des secrets
- Utilisation d'Ansible Vault pour les mots de passe
- Variables d'environnement pour les clés API
- Génération automatique des mots de passe

## Monitoring

### Dozzle (Logs Docker)
- Interface web pour visualiser les logs
- Accessible sur le port 9999
- Filtrage par conteneur

### Monitoring des services
```yaml
monitoring:
  enabled: true
  retention_days: 30
  services:
    - docker
    - nginx
    - mysql
    - redis
    - php-fpm
```

### Rotation des logs
```yaml
backup:
  enabled: true
  retention_days: 7
  schedule: "0 2 * * *"
  targets:
    - database
    - uploads
    - logs
```

## Scripts utilitaires

### Script de validation (validate.sh)
Script de validation complète de la configuration Ansible :
- Vérification de la syntaxe YAML
- Validation des structures de rôles
- Détection des secrets
- Vérification des permissions
- Test de la connectivité

```bash
./scripts/validate.sh production
./scripts/validate.sh all  # Tous les environnements
```

### Script de tests (test.sh)
Script de tests post-déploiement :
- Tests de connectivité
- Vérification des services
- Tests des conteneurs Docker
- Validation des URLs
- Tests de performance
- Vérification de la sécurité

```bash
./scripts/test.sh production
./scripts/test.sh production mon-serveur  # Serveur spécifique
```

### Script d'installation (install.sh)
Installation automatique d'Ansible et des dépendances :
- Installation Python et pip
- Création environnement virtuel
- Installation Ansible
- Configuration SSH
- Installation des collections

### Script de déploiement (deploy.sh)
Déploiement multi-environnement avec options avancées :
- Déploiement par environnement
- Support des tags
- Modes check et verbose
- Gestion des logs
- Sauvegardes

## Dépannage

### Logs Ansible
```bash
# Voir les logs en temps réel
tail -f ansible/logs/ansible.log

# Logs par environnement
tail -f ansible/logs/deploy_production.log
```

### Vérification des conteneurs
```bash
# Statut des conteneurs
docker ps

# Logs d'un conteneur
docker logs laravel-app_apache

# Logs en temps réel
docker logs -f laravel-app_apache
```

### Tests de connectivité
```bash
# Test ping Ansible
ansible all -i inventories/production/hosts.yml -m ping

# Test de connectivité réseau
ansible all -i inventories/production/hosts.yml -m setup
```

### Commandes de debug
```bash
# Mode verbeux
./scripts/deploy.sh production --verbose

# Mode check (dry-run)
./scripts/deploy.sh production --check

# Exécuter des tags spécifiques
./scripts/deploy.sh production --tags docker,laravel
```

## Développement

### Ajout d'un nouveau rôle
1. Créer la structure : `mkdir -p roles/nouveau-role/{tasks,templates,vars,handlers,files,defaults,meta}`
2. Créer le fichier principal : `roles/nouveau-role/tasks/main.yml`
3. Ajouter le rôle dans le playbook : `playbooks/deploy.yml`

### Ajout d'une nouvelle variable
1. Variables globales : `group_vars/all/main.yml`
2. Variables par environnement : `group_vars/[env]/main.yml`
3. Variables par hôte : `host_vars/[hostname].yml`

### Tests
```bash
# Validation complète
./scripts/validate.sh production

# Tests post-déploiement
./scripts/test.sh production

# Vérification syntaxe
ansible-playbook --syntax-check playbooks/deploy.yml

# Mode check
ansible-playbook -i inventories/development/hosts.yml playbooks/deploy.yml --check

# Exécution sur un hôte spécifique
ansible-playbook -i inventories/development/hosts.yml playbooks/deploy.yml --limit localhost
```

### Bonnes pratiques
1. Utiliser des tags pour les tâches
2. Gérer les erreurs avec `ignore_errors` et `failed_when`
3. Utiliser `changed_when` pour les tâches idempotentes
4. Documenter les variables dans `defaults/main.yml`
5. Utiliser des templates pour la configuration
6. Versionner les playbooks et rôles

### Structure d'un rôle
```
roles/mon-role/
├── tasks/
│   └── main.yml        # Tâches principales
├── templates/
│   └── config.j2       # Templates Jinja2
├── vars/
│   └── main.yml        # Variables du rôle
├── defaults/
│   └── main.yml        # Variables par défaut
├── handlers/
│   └── main.yml        # Gestionnaires d'événements
├── files/
│   └── fichier.txt     # Fichiers statiques
└── meta/
    └── main.yml        # Métadonnées du rôle
```

## Performance et optimisation

### Optimisations Ansible
- Utilisation du cache des facts
- Pipelines SSH activés
- Parallélisation avec `forks`
- Stratégie de gathering smart

### Optimisations Laravel
- Cache de configuration en production
- Cache des routes et vues
- Optimisation de l'autoloader
- Preload OPcache

### Optimisations Docker
- Multi-stage builds
- Volumes pour les données persistantes
- Réseau bridge optimisé
- Limits de ressources

## Sauvegarde et restauration

### Sauvegarde automatique
```bash
# Créer une sauvegarde
./scripts/deploy.sh backup production

# Programmer une sauvegarde
crontab -e
0 2 * * * /path/to/ansible/scripts/deploy.sh backup production
```

### Restauration
```bash
# Restaurer depuis une sauvegarde
ansible-playbook -i inventories/production/hosts.yml playbooks/restore.yml \
  --extra-vars "backup_date=20240101_120000"
```

## Contribution

Pour contribuer à ce projet :
1. Fork le repository
2. Créer une branche feature
3. Tester les modifications
4. Soumettre une pull request

## Support

Pour obtenir de l'aide :
1. Consulter la documentation
2. Vérifier les logs
3. Créer un ticket GitHub
4. Contacter l'équipe technique