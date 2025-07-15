# 🚀 Déploiement Ansible Laravel avec Docker

Solution complète de déploiement automatisé pour applications Laravel utilisant Ansible et Docker.

## ✨ Fonctionnalités

- **🎯 Multi-environnement** : Development, Staging, Production
- **🐳 Docker** : Conteneurisation complète (Apache, PHP, MariaDB, Redis, Node.js)
- **🔒 SSL automatique** : Let's Encrypt intégré
- **📊 Monitoring** : Dozzle, logs centralisés
- **🛡️ Sécurité** : Firewall, Fail2ban, SSH sécurisé
- **💾 Sauvegardes** : Automatiques et programmables
- **🔧 Outils dev** : Adminer, Mailhog, IT-Tools
- **⚡ Performance** : Cache Redis, optimisations Laravel

## 🚀 Installation rapide

```bash
# 1. Cloner le repository
git clone https://github.com/votre-username/myLaravelSkeleton.git
cd myLaravelSkeleton/ansible

# 2. Installation automatique
./scripts/install.sh

# 3. Configuration des serveurs
cp inventories/example/hosts.yml inventories/production/hosts.yml
nano inventories/production/hosts.yml

# 4. Validation de la configuration
./scripts/validate.sh production

# 5. Déploiement
source ./activate.sh
./scripts/deploy.sh production
```

## 📋 Prérequis

- **OS** : Ubuntu/Debian (recommandé) ou macOS
- **Python** : 3.8+
- **SSH** : Accès aux serveurs cibles
- **Git** : Pour cloner les repositories

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Development   │    │     Staging     │    │   Production    │
│                 │    │                 │    │                 │
│ • Debug ON      │    │ • SSL Test      │    │ • SSL Real      │
│ • All Tools     │    │ • Limited Tools │    │ • Minimal Tools │
│ • Relaxed Sec   │    │ • Medium Sec    │    │ • Max Security  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │   Ansible       │
                    │   Controller    │
                    │                 │
                    │ • Playbooks     │
                    │ • Roles         │
                    │ • Inventories   │
                    └─────────────────┘
```

## 🗂️ Structure du projet

```
ansible/
├── 📁 inventories/          # Configuration des serveurs
│   ├── production/
│   ├── staging/
│   └── development/
├── 📁 playbooks/            # Playbooks principaux
│   └── deploy.yml
├── 📁 roles/                # Rôles Ansible
│   ├── common/              # Configuration de base
│   ├── docker/              # Installation Docker
│   ├── laravel-app/         # Déploiement Laravel
│   ├── nginx-proxy/         # Reverse proxy
│   ├── security/            # Sécurité système
│   └── monitoring/          # Monitoring
├── 📁 group_vars/           # Variables par environnement
├── 📁 scripts/              # Scripts utilitaires
│   ├── install.sh           # Installation
│   ├── deploy.sh            # Déploiement
│   ├── validate.sh          # Validation
│   └── test.sh              # Tests
├── 📁 docs/                 # Documentation
│   ├── USAGE.md             # Guide utilisateur
│   └── TECHNICAL.md         # Documentation technique
├── 📄 CHANGELOG.md          # Historique des modifications
├── 🚫 .gitignore             # Protection des secrets
├── 📋 .env.example          # Template de configuration
└── 📄 README.md             # Ce fichier
```

## 🎯 Déploiement par environnement

### 🔧 Development
```bash
./scripts/deploy.sh development
```
- Debug activé
- Tous les outils de développement
- Sécurité relaxée
- Certificats auto-signés

### 🧪 Staging
```bash
./scripts/deploy.sh staging
```
- Configuration proche production
- Certificats SSL de test
- Monitoring activé
- Outils de debug limités

### 🏭 Production
```bash
./scripts/deploy.sh production
```
- Debug désactivé
- Certificats SSL réels
- Sécurité maximale
- Monitoring complet

## 🛠️ Commandes principales

### Déploiement
```bash
# Validation avant déploiement
./scripts/validate.sh production

# Déploiement complet
./scripts/deploy.sh production

# Vérification sans déploiement
./scripts/deploy.sh production --check

# Tags spécifiques
./scripts/deploy.sh production --tags docker,laravel

# Serveur spécifique
./scripts/deploy.sh production --limit mon-serveur
```

### Maintenance
```bash
# Validation complète
./scripts/validate.sh production

# Tests post-déploiement
./scripts/test.sh production

# Logs
./scripts/deploy.sh logs production

# Statut
./scripts/deploy.sh status production

# Sauvegarde
./scripts/deploy.sh backup production

# Vérification
./scripts/deploy.sh check production
```

## 📊 Monitoring et outils

Une fois déployé, vous aurez accès à :

| Service | URL | Description |
|---------|-----|-------------|
| **Application** | `http://votre-domaine` | Application Laravel |
| **Dozzle** | `http://ip:9999` | Logs Docker en temps réel |
| **Mailhog** | `http://ip:8025` | Capture des emails (dev/staging) |
| **Adminer** | `http://ip:8080` | Interface base de données |
| **IT-Tools** | `http://ip:8081` | Outils utilitaires (dev) |

## 🔒 Sécurité

### Fonctionnalités de sécurité
- **Firewall UFW** : Ports fermés par défaut
- **Fail2ban** : Protection contre les attaques
- **SSH sécurisé** : Clés uniquement, pas de root
- **SSL/TLS** : Let's Encrypt automatique
- **Conteneurs** : Isolation des services

### Configuration SSH recommandée
```bash
# Génération de clés SSH
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa

# Copie sur le serveur
ssh-copy-id -i ~/.ssh/id_rsa.pub user@server

# Test de connexion
ssh -i ~/.ssh/id_rsa user@server
```

## 💾 Sauvegardes

### Sauvegarde automatique
```bash
# Configuration dans group_vars/[env]/main.yml
backup:
  enabled: true
  retention_days: 7
  schedule: "0 2 * * *"  # 2h du matin
  targets:
    - database
    - uploads
    - logs
```

### Sauvegarde manuelle
```bash
# Créer une sauvegarde
./scripts/deploy.sh backup production

# Voir les sauvegardes
ls -la ansible/backups/production/
```

## 🐛 Dépannage

### Problèmes courants

**Erreur de connexion SSH**
```bash
# Vérifier la connectivité
ansible all -i inventories/production/hosts.yml -m ping

# Tester SSH manuellement
ssh -i ~/.ssh/id_rsa user@server
```

**Erreur Docker**
```bash
# Vérifier Docker sur le serveur
ssh user@server 'docker ps'

# Reconstruire les conteneurs
./scripts/deploy.sh production --tags docker
```

**Erreur Laravel**
```bash
# Voir les logs Laravel
ssh user@server 'docker logs project_php'

# Entrer dans le conteneur
ssh user@server 'docker exec -it project_php bash'
```

### Logs utiles
```bash
# Logs Ansible
tail -f ansible/logs/ansible.log

# Logs de déploiement
tail -f ansible/logs/deploy_production.log

# Logs système sur le serveur
journalctl -u docker.service -f
```

## 📚 Documentation

- **[Guide d'utilisation](docs/USAGE.md)** - Instructions détaillées
- **[Documentation technique](docs/TECHNICAL.md)** - Architecture et développement

## 🔧 Configuration avancée

### Variables personnalisées
```yaml
# group_vars/production/main.yml
app_domain: "monapp.com"
ssl_email: "admin@monapp.com"
backup_enabled: true
monitoring_enabled: true
```

### Services optionnels
```yaml
# Activation/désactivation des services
optional_services:
  mailhog:
    enabled: false      # Production
  adminer:
    enabled: true       # Development
  dozzle:
    enabled: true       # Tous environnements
```

## 🤝 Contribution

1. Fork le repository
2. Créer une branche feature
3. Committer les changements
4. Pousser vers la branche
5. Créer une Pull Request

## 📄 Licence

Ce projet est sous licence MIT. Voir le fichier `LICENSE` pour plus de détails.

## 🆘 Support

- **Documentation** : [Guide utilisateur](docs/USAGE.md) | [Documentation technique](docs/TECHNICAL.md)
- **Issues** : [GitHub Issues](https://github.com/votre-username/myLaravelSkeleton/issues)
- **Discussions** : [GitHub Discussions](https://github.com/votre-username/myLaravelSkeleton/discussions)

---

**🚀 Déployez votre Laravel en quelques minutes avec Ansible !**

*Généré avec ❤️ par l'équipe de développement*