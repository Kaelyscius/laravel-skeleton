# Guide d'utilisation - Déploiement Ansible Laravel

## Table des matières
1. [Introduction](#introduction)
2. [Installation](#installation)
3. [Configuration](#configuration)
4. [Premier déploiement](#premier-déploiement)
5. [Gestion des environnements](#gestion-des-environnements)
6. [Commandes utiles](#commandes-utiles)
7. [Monitoring](#monitoring)
8. [Maintenance](#maintenance)
9. [FAQ](#faq)

## Introduction

Ce guide vous explique comment utiliser la solution de déploiement Ansible pour votre application Laravel. Cette solution automatise le déploiement sur différents environnements (développement, staging, production) avec Docker.

### Prérequis
- Ubuntu/Debian (recommandé) ou macOS
- Python 3.8+
- Accès SSH aux serveurs cibles
- Git installé

### Fonctionnalités
- ✅ Déploiement automatisé multi-environnement
- ✅ Configuration Docker complète
- ✅ SSL automatique avec Let's Encrypt
- ✅ Monitoring intégré (Dozzle, logs)
- ✅ Sauvegardes automatiques
- ✅ Sécurité renforcée (firewall, fail2ban)
- ✅ Outils de développement (Adminer, Mailhog)

## Installation

### Installation automatique

```bash
# Cloner le projet
git clone https://github.com/votre-username/myLaravelSkeleton.git
cd myLaravelSkeleton/ansible

# Lancer l'installation
./scripts/install.sh
```

Le script d'installation va :
1. Installer Python et pip
2. Créer un environnement virtuel
3. Installer Ansible et ses dépendances
4. Configurer SSH
5. Créer la configuration de base

### Installation manuelle

Si vous préférez installer manuellement :

```bash
# Installer Ansible
pip3 install ansible

# Installer les dépendances
pip3 install docker requests psutil

# Installer les collections Ansible
ansible-galaxy collection install community.docker
ansible-galaxy collection install ansible.posix
```

## Configuration

### 1. Configuration des serveurs

Copiez l'inventaire d'exemple :
```bash
cp inventories/example/hosts.yml inventories/production/hosts.yml
```

Modifiez le fichier avec vos serveurs :
```yaml
all:
  children:
    web_servers:
      hosts:
        mon-serveur-web:
          ansible_host: 192.168.1.100    # IP de votre serveur
          ansible_user: root              # Utilisateur SSH
          deploy_path: /var/www/mon-app   # Chemin de déploiement
          project_name: mon-app-prod      # Nom du projet
```

### 2. Configuration des variables

Adaptez les variables selon votre environnement :
```bash
nano group_vars/production/main.yml
```

Variables importantes à modifier :
```yaml
# Configuration SSL
ssl:
  enabled: true
  email: admin@votre-domaine.com

# Configuration notifications
notifications:
  email:
    enabled: true
    recipients:
      - admin@votre-domaine.com
```

### 3. Configuration SSH

Assurez-vous que votre clé SSH est configurée :
```bash
# Générer une clé SSH si nécessaire
ssh-keygen -t rsa -b 4096

# Copier la clé sur vos serveurs
ssh-copy-id root@192.168.1.100
```

### 4. Configuration du repository Git

Modifiez l'URL du repository dans le playbook de déploiement ou utilisez les variables promptées.

## Premier déploiement

### 1. Activer l'environnement

```bash
# Activer l'environnement Ansible
source ./activate.sh
```

### 2. Tester la configuration

```bash
# Valider la configuration complète
./scripts/validate.sh production

# Vérifier la syntaxe
./scripts/deploy.sh production --check

# Tester la connectivité
ansible all -i inventories/production/hosts.yml -m ping
```

### 3. Déployer

```bash
# Déploiement complet
./scripts/deploy.sh production
```

Le script vous demandera :
- URL du repository Git
- Branche à déployer
- Chemin de déploiement
- Nom du projet
- Nom de domaine

### 4. Vérifier le déploiement

Une fois le déploiement terminé, l'application sera accessible via :
- **Application principale** : http://votre-domaine ou http://ip-serveur
- **Logs Docker** : http://ip-serveur:9999 (Dozzle)
- **Mailcatcher** : http://ip-serveur:8025 (si activé)
- **Adminer** : http://ip-serveur:8080 (si activé)

### 5. Tester le déploiement

```bash
# Tests post-déploiement complets
./scripts/test.sh production

# Tests sur un serveur spécifique
./scripts/test.sh production mon-serveur-web
```

## Gestion des environnements

### Environnement de développement

```bash
# Déploiement sur serveur de développement
./scripts/deploy.sh development

# Déploiement local
./scripts/deploy.sh development --limit localhost
```

Caractéristiques :
- Debug activé
- Tous les outils de développement
- Sécurité relaxée
- Logs verbeux

### Environnement de staging

```bash
# Déploiement sur staging
./scripts/deploy.sh staging
```

Caractéristiques :
- Configuration proche de la production
- Certificats SSL de test
- Monitoring activé
- Outils de debug limités

### Environnement de production

```bash
# Déploiement en production
./scripts/deploy.sh production
```

Caractéristiques :
- Debug désactivé
- Certificats SSL réels
- Sécurité maximale
- Monitoring complet
- Sauvegardes automatiques

## Commandes utiles

### Déploiement

```bash
# Déploiement complet
./scripts/deploy.sh production

# Déploiement avec vérification préalable
./scripts/deploy.sh production --check

# Déploiement avec tags spécifiques
./scripts/deploy.sh production --tags docker,laravel

# Déploiement sur un serveur spécifique
./scripts/deploy.sh production --limit mon-serveur-web
```

### Maintenance

```bash
# Validation complète
./scripts/validate.sh production

# Tests post-déploiement
./scripts/test.sh production

# Voir les logs
./scripts/deploy.sh logs production

# Voir le statut des serveurs
./scripts/deploy.sh status production

# Créer une sauvegarde
./scripts/deploy.sh backup production

# Vérifier la configuration
./scripts/deploy.sh check production
```

### Gestion des conteneurs

```bash
# Se connecter au serveur
ssh root@192.168.1.100

# Voir les conteneurs
docker ps

# Logs d'un conteneur
docker logs mon-app-prod_apache

# Redémarrer les conteneurs
cd /var/www/mon-app
docker-compose restart

# Arrêter les conteneurs
docker-compose down

# Reconstruire les conteneurs
docker-compose up -d --build
```

### Gestion de l'application Laravel

```bash
# Entrer dans le conteneur PHP
docker exec -it mon-app-prod_php bash

# Commandes Artisan
docker exec -it mon-app-prod_php php artisan migrate
docker exec -it mon-app-prod_php php artisan config:cache
docker exec -it mon-app-prod_php php artisan queue:work

# Logs Laravel
docker exec -it mon-app-prod_php tail -f storage/logs/laravel.log
```

## Monitoring

### Dozzle (Logs Docker)

Accessible via : http://ip-serveur:9999

Fonctionnalités :
- Visualisation des logs en temps réel
- Filtrage par conteneur
- Recherche dans les logs
- Export des logs

### Logs système

```bash
# Logs Ansible
tail -f ansible/logs/ansible.log

# Logs des services
journalctl -u docker.service -f
journalctl -u nginx.service -f
```

### Monitoring des ressources

```bash
# Utilisation des ressources
docker stats

# Espace disque
df -h

# Mémoire
free -h

# Processus
htop
```

## Maintenance

### Mises à jour

```bash
# Mettre à jour uniquement le code
./scripts/deploy.sh production --tags laravel

# Mettre à jour Docker
./scripts/deploy.sh production --tags docker

# Mise à jour système
./scripts/deploy.sh production --tags common
```

### Sauvegardes

```bash
# Sauvegarde manuelle
./scripts/deploy.sh backup production

# Programmer une sauvegarde automatique
crontab -e
# Ajouter : 0 2 * * * /path/to/ansible/scripts/deploy.sh backup production
```

### Restauration

```bash
# Lister les sauvegardes
ls -la ansible/backups/production/

# Restaurer une sauvegarde
ansible-playbook -i inventories/production/hosts.yml playbooks/restore.yml \
  --extra-vars "backup_date=20240101_120000"
```

### Nettoyage

```bash
# Nettoyer les logs
ansible all -i inventories/production/hosts.yml -m shell -a "find /var/log -name '*.log' -mtime +30 -delete"

# Nettoyer Docker
ansible all -i inventories/production/hosts.yml -m shell -a "docker system prune -f"
```

## FAQ

### Q: Comment changer l'URL du repository Git ?
**R**: Modifiez la variable `app_git_repo` dans le playbook ou utilisez les prompts lors du déploiement.

### Q: Comment ajouter un nouveau serveur ?
**R**: Ajoutez le serveur dans l'inventaire correspondant (`inventories/[env]/hosts.yml`).

### Q: Comment désactiver SSL ?
**R**: Modifiez `ssl.enabled: false` dans `group_vars/[env]/main.yml`.

### Q: Comment changer les ports exposés ?
**R**: Modifiez la section `network.ports` dans `group_vars/all/main.yml`.

### Q: Comment activer les notifications ?
**R**: Configurez la section `notifications` dans `group_vars/[env]/main.yml`.

### Q: Comment gérer les variables sensibles ?
**R**: Utilisez Ansible Vault :
```bash
ansible-vault create group_vars/production/vault.yml
ansible-vault edit group_vars/production/vault.yml
```

### Q: Comment déployer une branche spécifique ?
**R**: Utilisez la variable `app_git_branch` ou répondez au prompt lors du déploiement.

### Q: Comment voir les logs d'un déploiement ?
**R**: Les logs sont dans `ansible/logs/ansible.log` et `ansible/logs/deploy_[env].log`.

### Q: Comment tester sans impacter la production ?
**R**: Utilisez l'option `--check` pour un dry-run.

### Q: Comment déployer sur plusieurs serveurs ?
**R**: Ajoutez les serveurs dans l'inventaire, Ansible déploiera sur tous automatiquement.

### Q: Comment personnaliser la configuration Docker ?
**R**: Modifiez les templates dans `roles/laravel-app/templates/` et les variables Docker.

### Q: Comment gérer les migrations de base de données ?
**R**: Les migrations sont automatiques, mais vous pouvez les désactiver avec `--skip-tags database`.

### Q: Comment configurer un load balancer ?
**R**: Ajoutez des serveurs dans le groupe `load_balancers` de l'inventaire et activez le rôle `nginx-proxy`.

### Q: Comment mettre à jour seulement l'application ?
**R**: 
```bash
./scripts/deploy.sh production --tags laravel
```

### Q: Comment déboguer un déploiement qui échoue ?
**R**: 
```bash
./scripts/deploy.sh production --verbose
# Ou consultez les logs
tail -f ansible/logs/ansible.log
```

## Support

### Documentation
- [Documentation technique](TECHNICAL.md)
- [Guide de développement](DEVELOPMENT.md)

### Aide
- Consultez les logs Ansible
- Vérifiez la connectivité réseau
- Testez les commandes manuellement
- Créez un ticket GitHub

### Ressources utiles
- [Documentation Ansible](https://docs.ansible.com/)
- [Documentation Docker](https://docs.docker.com/)
- [Documentation Laravel](https://laravel.com/docs)

---

*Ce guide a été généré automatiquement par Ansible. Pour des questions spécifiques, consultez la documentation technique ou contactez l'équipe de développement.*