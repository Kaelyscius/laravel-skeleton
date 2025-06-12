#!/usr/bin/env python3
"""
Script de configuration automatique avancée pour Uptime Kuma
Utilise l'API Python pour créer automatiquement les monitors
"""

import os
import sys
import time
import requests
import json
from urllib.parse import urlparse

# Couleurs pour les logs
class Colors:
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    RED = '\033[0;31m'
    BLUE = '\033[0;34m'
    CYAN = '\033[0;36m'
    NC = '\033[0m'

def print_colored(message, color):
    print(f"{color}{message}{Colors.NC}")

def check_uptime_kuma_api():
    """Vérifier si Uptime Kuma est accessible"""
    url = "http://localhost:3001"
    max_attempts = 30

    print_colored("🔍 Vérification d'Uptime Kuma...", Colors.YELLOW)

    for attempt in range(1, max_attempts + 1):
        try:
            response = requests.get(url, timeout=5)
            if response.status_code == 200:
                print_colored("✓ Uptime Kuma est accessible", Colors.GREEN)
                return True
        except requests.exceptions.RequestException:
            pass

        print_colored(f"⏳ Tentative {attempt}/{max_attempts} - Uptime Kuma non accessible...", Colors.YELLOW)
        time.sleep(2)

    print_colored("❌ Uptime Kuma n'est pas accessible", Colors.RED)
    return False

def install_uptime_kuma_api():
    """Installer l'API Uptime Kuma si nécessaire"""
    try:
        import uptime_kuma_api
        print_colored("✓ API Uptime Kuma déjà installée", Colors.GREEN)
        return True
    except ImportError:
        print_colored("📦 Installation de l'API Uptime Kuma...", Colors.YELLOW)

        try:
            import subprocess
            result = subprocess.run([
                sys.executable, "-m", "pip", "install", "uptime-kuma-api"
            ], capture_output=True, text=True)

            if result.returncode == 0:
                print_colored("✓ API Uptime Kuma installée avec succès", Colors.GREEN)
                return True
            else:
                print_colored(f"❌ Erreur d'installation: {result.stderr}", Colors.RED)
                return False
        except Exception as e:
            print_colored(f"❌ Erreur lors de l'installation: {str(e)}", Colors.RED)
            return False

def get_compose_project_name():
    """Récupérer le nom du projet Docker Compose"""
    return os.getenv('COMPOSE_PROJECT_NAME', 'laravel-app')

def create_monitors_config():
    """Créer la configuration des monitors"""
    project_name = get_compose_project_name()

    return {
        "critical": [
            {
                "name": "Laravel Application",
                "type": "http",
                "url": "https://laravel.local",
                "interval": 60,
                "maxretries": 3,
                "keyword": "Laravel",
                "tags": ["critical", "laravel", "web"]
            },
            {
                "name": "Laravel HTTP Fallback",
                "type": "http",
                "url": "http://localhost",
                "interval": 60,
                "maxretries": 3,
                "tags": ["critical", "laravel", "web"]
            }
        ],
        "important": [
            {
                "name": "MariaDB Database",
                "type": "port",
                "hostname": "localhost",
                "port": 3306,
                "interval": 120,
                "tags": ["important", "database"]
            },
            {
                "name": "Redis Cache",
                "type": "port",
                "hostname": "localhost",
                "port": 6379,
                "interval": 120,
                "tags": ["important", "cache"]
            },
            {
                "name": "Laravel Horizon",
                "type": "http",
                "url": "https://laravel.local/horizon",
                "interval": 180,
                "tags": ["important", "laravel", "queues"]
            },
            {
                "name": "Laravel Telescope",
                "type": "http",
                "url": "https://laravel.local/telescope",
                "interval": 300,
                "tags": ["important", "laravel", "debug"]
            }
        ],
        "tools": [
            {
                "name": "MailHog",
                "type": "http",
                "url": "http://localhost:8025",
                "interval": 300,
                "tags": ["tools", "dev", "email"]
            },
            {
                "name": "Adminer",
                "type": "http",
                "url": "http://localhost:8080",
                "interval": 300,
                "tags": ["tools", "database", "admin"]
            },
            {
                "name": "IT-Tools",
                "type": "http",
                "url": "http://localhost:8081",
                "interval": 300,
                "tags": ["tools", "dev", "utilities"]
            },
            {
                "name": "Dozzle (Logs)",
                "type": "http",
                "url": "http://localhost:9999",
                "interval": 300,
                "tags": ["tools", "monitoring", "logs"]
            }
        ],
        "infrastructure": [
            {
                "name": "Uptime Kuma Self",
                "type": "http",
                "url": "http://localhost:3001",
                "interval": 600,
                "tags": ["infrastructure", "monitoring"]
            }
        ]
    }

def create_manual_config_file():
    """Créer un fichier de configuration manuelle de sauvegarde"""
    config = create_monitors_config()

    config_file = "./scripts/uptime-kuma-auto-config.json"
    os.makedirs("./scripts", exist_ok=True)

    with open(config_file, 'w') as f:
        json.dump(config, f, indent=2)

    print_colored(f"✓ Configuration sauvegardée: {config_file}", Colors.GREEN)
    return config_file

def create_monitors_with_curl():
    """Créer les monitors en utilisant curl (méthode de fallback)"""
    print_colored("🔧 Utilisation de la méthode de fallback avec curl...", Colors.YELLOW)

    # Créer le fichier de configuration pour import manuel
    config_file = create_manual_config_file()

    print_colored("📋 Instructions pour import manuel:", Colors.BLUE)
    print_colored("===================================", Colors.BLUE)
    print()
    print_colored("1. Ouvrez Uptime Kuma: http://localhost:3001", Colors.YELLOW)
    print_colored("2. Créez votre compte administrateur", Colors.YELLOW)
    print_colored("3. Utilisez le fichier de configuration créé:", Colors.YELLOW)
    print_colored(f"   → {config_file}", Colors.CYAN)
    print()

    # Afficher les monitors à créer
    config = create_monitors_config()

    for category, monitors in config.items():
        print_colored(f"📊 {category.upper()}:", Colors.BLUE)
        for monitor in monitors:
            print_colored(f"  • {monitor['name']}", Colors.GREEN)
            if monitor['type'] == 'http':
                print_colored(f"    URL: {monitor['url']}", Colors.CYAN)
            elif monitor['type'] == 'port':
                print_colored(f"    Host: {monitor['hostname']}:{monitor['port']}", Colors.CYAN)
            print_colored(f"    Intervalle: {monitor['interval']}s", Colors.CYAN)
            print_colored(f"    Tags: {', '.join(monitor['tags'])}", Colors.CYAN)
            print()

def create_monitors_with_api():
    """Créer les monitors en utilisant l'API Python"""
    try:
        from uptime_kuma_api import UptimeKumaApi, MonitorType

        print_colored("🤖 Configuration automatique avec l'API...", Colors.YELLOW)

        # Note: L'API nécessite des credentials, ce qui n'est pas idéal pour l'automatisation
        # En pratique, il faudrait soit:
        # 1. Pré-configurer un utilisateur API
        # 2. Utiliser des variables d'environnement
        # 3. Demander les credentials interactivement

        print_colored("⚠️  La configuration automatique via API nécessite des credentials", Colors.YELLOW)
        print_colored("    Utilisation de la méthode de fallback...", Colors.YELLOW)

        return create_monitors_with_curl()

        # Code pour l'API (désactivé pour le moment):
        """
        with UptimeKumaApi('http://localhost:3001') as api:
            # Tentative de connexion
            api.login('admin', 'password')  # Credentials nécessaires

            config = create_monitors_config()

            for category, monitors in config.items():
                print_colored(f"📊 Création des monitors {category}...", Colors.BLUE)

                for monitor_config in monitors:
                    try:
                        if monitor_config['type'] == 'http':
                            monitor = api.add_monitor(
                                type=MonitorType.HTTP,
                                name=monitor_config['name'],
                                url=monitor_config['url'],
                                interval=monitor_config['interval'],
                                maxretries=monitor_config.get('maxretries', 1)
                            )
                        elif monitor_config['type'] == 'port':
                            monitor = api.add_monitor(
                                type=MonitorType.PORT,
                                name=monitor_config['name'],
                                hostname=monitor_config['hostname'],
                                port=monitor_config['port'],
                                interval=monitor_config['interval']
                            )

                        print_colored(f"  ✓ {monitor_config['name']}", Colors.GREEN)

                    except Exception as e:
                        print_colored(f"  ✗ {monitor_config['name']}: {str(e)}", Colors.RED)

        print_colored("✅ Configuration automatique terminée!", Colors.GREEN)
        """

    except ImportError:
        print_colored("❌ API Uptime Kuma non disponible", Colors.RED)
        return create_monitors_with_curl()
    except Exception as e:
        print_colored(f"❌ Erreur API: {str(e)}", Colors.RED)
        return create_monitors_with_curl()

def show_status():
    """Afficher le statut des services"""
    print_colored("📊 Statut des services à monitorer", Colors.BLUE)
    print_colored("==================================", Colors.BLUE)
    print()

    # Services web à vérifier
    web_services = [
        ("Laravel HTTPS", "https://laravel.local"),
        ("Laravel HTTP", "http://localhost"),
        ("MailHog", "http://localhost:8025"),
        ("Adminer", "http://localhost:8080"),
        ("IT-Tools", "http://localhost:8081"),
        ("Dozzle", "http://localhost:9999"),
        ("Uptime Kuma", "http://localhost:3001")
    ]

    print_colored("🌐 Services Web:", Colors.YELLOW)
    for name, url in web_services:
        try:
            response = requests.get(url, timeout=5, verify=False)
            if response.status_code == 200:
                print_colored(f"  ✓ {name}", Colors.GREEN)
            else:
                print_colored(f"  ⚠ {name} (status: {response.status_code})", Colors.YELLOW)
        except requests.exceptions.RequestException:
            print_colored(f"  ✗ {name} (non accessible)", Colors.RED)

    print()

    # Ports à vérifier
    import socket
    ports = [
        ("MariaDB", "localhost", 3306),
        ("Redis", "localhost", 6379),
        ("Apache HTTP", "localhost", 80),
        ("Apache HTTPS", "localhost", 443)
    ]

    print_colored("🔌 Ports:", Colors.YELLOW)
    for name, host, port in ports:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(2)
        result = sock.connect_ex((host, port))
        sock.close()

        if result == 0:
            print_colored(f"  ✓ {name} ({port})", Colors.GREEN)
        else:
            print_colored(f"  ✗ {name} ({port}) (non accessible)", Colors.RED)

def create_notification_templates():
    """Créer des templates de notifications"""
    templates = {
        "discord": {
            "name": "Discord Alerts",
            "type": "discord",
            "description": "Notifications Discord pour les alertes critiques",
            "config": {
                "webhookURL": "https://discord.com/api/webhooks/YOUR_WEBHOOK_URL",
                "username": "Uptime Kuma",
                "content": "🚨 **Alert** 🚨\n**{monitor.name}** is {monitor.status}\n**URL:** {monitor.url}\n**Time:** {monitor.localDateTime}"
            }
        },
        "slack": {
            "name": "Slack Alerts",
            "type": "slack",
            "description": "Notifications Slack pour l'équipe",
            "config": {
                "webhookURL": "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK",
                "channel": "#alerts",
                "username": "Uptime Kuma",
                "text": "🚨 Alert: {monitor.name} is {monitor.status}"
            }
        },
        "email": {
            "name": "Email Alerts",
            "type": "smtp",
            "description": "Notifications email pour tous les alertes",
            "config": {
                "host": "localhost",
                "port": 1025,
                "secure": False,
                "from": "alerts@laravel.local",
                "to": "admin@laravel.local",
                "subject": "🚨 Uptime Alert: {monitor.name}"
            }
        }
    }

    templates_file = "./scripts/uptime-kuma-notifications.json"
    with open(templates_file, 'w') as f:
        json.dump(templates, f, indent=2)

    print_colored(f"✓ Templates de notifications créés: {templates_file}", Colors.GREEN)
    return templates_file

def main():
    """Fonction principale"""
    print_colored("🤖 Configuration automatique avancée d'Uptime Kuma", Colors.CYAN)
    print_colored("=================================================", Colors.CYAN)
    print()

    # Vérifier Uptime Kuma
    if not check_uptime_kuma_api():
        print_colored("Impossible de continuer sans Uptime Kuma accessible", Colors.RED)
        print_colored("💡 Démarrez d'abord l'environnement: make up", Colors.YELLOW)
        sys.exit(1)

    # Afficher le statut des services
    show_status()
    print()

    # Tenter d'installer l'API
    if not install_uptime_kuma_api():
        print_colored("⚠️  Impossible d'installer l'API, utilisation de la méthode manuelle", Colors.YELLOW)

    # Créer les monitors
    create_monitors_with_api()

    # Créer les templates de notifications
    create_notification_templates()

    print()
    print_colored("✅ Configuration avancée terminée!", Colors.GREEN)
    print_colored("📱 Prochaines étapes:", Colors.YELLOW)
    print_colored("1. Ouvrez Uptime Kuma: http://localhost:3001", Colors.CYAN)
    print_colored("2. Créez votre compte administrateur", Colors.CYAN)
    print_colored("3. Configurez les notifications selon vos besoins", Colors.CYAN)
    print_colored("4. Importez les monitors depuis le fichier de configuration", Colors.CYAN)
    print()
    print_colored("💡 Fichiers créés:", Colors.BLUE)
    print_colored("  • ./scripts/uptime-kuma-auto-config.json", Colors.CYAN)
    print_colored("  • ./scripts/uptime-kuma-notifications.json", Colors.CYAN)

if __name__ == "__main__":
    main()