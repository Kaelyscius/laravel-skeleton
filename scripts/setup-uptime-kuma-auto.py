#!/usr/bin/env python3
"""
Script de configuration automatique complète pour Uptime Kuma
Créé automatiquement les monitors pour l'environnement Laravel Docker
"""

import os
import sys
import time
import json
import webbrowser
from datetime import datetime

try:
    import requests
except ImportError:
    print("❌ Module 'requests' requis. Installation...")
    os.system("python3 -m pip install --user requests")
    import requests

# Configuration
UPTIME_KUMA_URL = os.getenv('UPTIME_KUMA_URL', 'http://localhost:3001')
COMPOSE_PROJECT_NAME = os.getenv('COMPOSE_PROJECT_NAME', 'laravel-app')
ADMIN_USER = os.getenv('UPTIME_ADMIN_USER', 'admin')
ADMIN_PASS = os.getenv('UPTIME_ADMIN_PASS', 'LaravelDev2024!')
ADMIN_EMAIL = os.getenv('UPTIME_ADMIN_EMAIL', 'admin@laravel.local')

# Couleurs pour les logs
class Colors:
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    RED = '\033[0;31m'
    BLUE = '\033[0;34m'
    CYAN = '\033[0;36m'
    PURPLE = '\033[0;35m'
    NC = '\033[0m'

def log(level, message):
    """Logger avec couleurs"""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    colors = {
        'INFO': Colors.BLUE,
        'WARN': Colors.YELLOW,
        'ERROR': Colors.RED,
        'SUCCESS': Colors.GREEN,
        'DEBUG': Colors.PURPLE
    }
    color = colors.get(level, Colors.NC)
    print(f"{color}[{level} {timestamp}]{Colors.NC} {message}")

def check_uptime_kuma_accessibility():
    """Vérifier si Uptime Kuma est accessible"""
    log('INFO', '🔍 Vérification d\'Uptime Kuma...')

    max_attempts = 30
    for attempt in range(1, max_attempts + 1):
        try:
            response = requests.get(UPTIME_KUMA_URL, timeout=5)
            if response.status_code == 200:
                log('SUCCESS', '✓ Uptime Kuma est accessible')
                return True
        except requests.exceptions.RequestException:
            pass

        log('INFO', f'⏳ Tentative {attempt}/{max_attempts} - Uptime Kuma non accessible...')
        time.sleep(2)

    log('ERROR', '❌ Uptime Kuma n\'est pas accessible')
    return False

def create_monitors_config():
    """Créer la configuration des monitors"""
    return {
        "critical": [
            {
                "name": "Laravel Application HTTPS",
                "type": "http",
                "url": "https://laravel.local",
                "interval": 60,
                "maxretries": 3,
                "keyword": "Laravel",
                "tags": ["critical", "laravel", "web"],
                "description": "Application Laravel principale (HTTPS)"
            },
            {
                "name": "Laravel Application HTTP",
                "type": "http",
                "url": "http://localhost",
                "interval": 60,
                "maxretries": 3,
                "tags": ["critical", "laravel", "web"],
                "description": "Application Laravel fallback (HTTP)"
            }
        ],
        "important": [
            {
                "name": "MariaDB Database",
                "type": "port",
                "hostname": "localhost",
                "port": 3306,
                "interval": 120,
                "tags": ["important", "database"],
                "description": "Base de données MariaDB"
            },
            {
                "name": "Redis Cache",
                "type": "port",
                "hostname": "localhost",
                "port": 6379,
                "interval": 120,
                "tags": ["important", "cache"],
                "description": "Cache Redis"
            },
            {
                "name": "Laravel Horizon",
                "type": "http",
                "url": "https://laravel.local/horizon",
                "interval": 180,
                "tags": ["important", "laravel", "queues"],
                "description": "Dashboard Laravel Horizon"
            },
            {
                "name": "Laravel Telescope",
                "type": "http",
                "url": "https://laravel.local/telescope",
                "interval": 300,
                "tags": ["important", "laravel", "debug"],
                "description": "Debug Laravel Telescope"
            }
        ],
        "tools": [
            {
                "name": "MailHog",
                "type": "http",
                "url": "http://localhost:8025",
                "interval": 300,
                "tags": ["tools", "dev", "email"],
                "description": "Capture d'emails MailHog"
            },
            {
                "name": "Adminer",
                "type": "http",
                "url": "http://localhost:8080",
                "interval": 300,
                "tags": ["tools", "database", "admin"],
                "description": "Interface Adminer"
            },
            {
                "name": "IT-Tools",
                "type": "http",
                "url": "http://localhost:8081",
                "interval": 300,
                "tags": ["tools", "dev", "utilities"],
                "description": "Boîte à outils IT-Tools"
            },
            {
                "name": "Dozzle (Logs)",
                "type": "http",
                "url": "http://localhost:9999",
                "interval": 300,
                "tags": ["tools", "monitoring", "logs"],
                "description": "Visualisation logs Dozzle"
            }
        ],
        "infrastructure": [
            {
                "name": "Uptime Kuma Self",
                "type": "http",
                "url": "http://localhost:3001",
                "interval": 600,
                "tags": ["infrastructure", "monitoring"],
                "description": "Auto-monitoring Uptime Kuma"
            }
        ]
    }

def test_services():
    """Tester l'accessibilité des services"""
    log('INFO', '📊 Test de l\'accessibilité des services...')

    config = create_monitors_config()
    results = {"accessible": [], "inaccessible": [], "ports_open": [], "ports_closed": []}

    # Tester les services HTTP
    for category, monitors in config.items():
        for monitor in monitors:
            if monitor['type'] == 'http':
                try:
                    response = requests.get(monitor['url'], timeout=5, verify=False)
                    if response.status_code == 200:
                        results["accessible"].append(monitor['name'])
                        log('SUCCESS', f'✓ {monitor["name"]} accessible')
                    else:
                        results["inaccessible"].append(f"{monitor['name']} (HTTP {response.status_code})")
                        log('WARN', f'⚠ {monitor["name"]} retourne HTTP {response.status_code}')
                except requests.exceptions.RequestException:
                    results["inaccessible"].append(monitor['name'])
                    log('ERROR', f'✗ {monitor["name"]} non accessible')

            elif monitor['type'] == 'port':
                import socket
                try:
                    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                    sock.settimeout(2)
                    result = sock.connect_ex((monitor['hostname'], monitor['port']))
                    sock.close()

                    if result == 0:
                        results["ports_open"].append(f"{monitor['name']} ({monitor['port']})")
                        log('SUCCESS', f'✓ {monitor["name"]} port {monitor["port"]} ouvert')
                    else:
                        results["ports_closed"].append(f"{monitor['name']} ({monitor['port']})")
                        log('ERROR', f'✗ {monitor["name"]} port {monitor["port"]} fermé')
                except Exception as e:
                    results["ports_closed"].append(f"{monitor['name']} ({monitor['port']})")
                    log('ERROR', f'✗ {monitor["name"]} erreur: {e}')

    return results

def create_templates_file():
    """Créer un fichier de templates pour configuration manuelle"""
    config = create_monitors_config()

    templates_file = "./scripts/uptime-kuma-monitors-template.txt"
    os.makedirs("./scripts", exist_ok=True)

    with open(templates_file, 'w', encoding='utf-8') as f:
        f.write("# Template de monitors Uptime Kuma pour environnement Laravel Docker\n")
        f.write("# Copiez-collez ces informations dans l'interface Uptime Kuma\n")
        f.write(f"# Généré automatiquement le {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")

        for category, monitors in config.items():
            f.write(f"=== MONITORS {category.upper()} ===\n\n")

            for i, monitor in enumerate(monitors, 1):
                f.write(f"{i}. {monitor['name']}\n")
                if monitor['type'] == 'http':
                    f.write(f"   Type: HTTP(s)\n")
                    f.write(f"   URL: {monitor['url']}\n")
                elif monitor['type'] == 'port':
                    f.write(f"   Type: Port\n")
                    f.write(f"   Hostname: {monitor['hostname']}\n")
                    f.write(f"   Port: {monitor['port']}\n")

                f.write(f"   Intervalle: {monitor['interval']}s\n")
                f.write(f"   Tags: {', '.join(monitor['tags'])}\n")
                f.write(f"   Description: {monitor['description']}\n")
                f.write("\n")

        # Ajouter des instructions
        f.write("=== INSTRUCTIONS DE CONFIGURATION ===\n\n")
        f.write("1. Ouvrez Uptime Kuma: http://localhost:3001\n")
        f.write("2. Créez votre compte administrateur\n")
        f.write("3. Pour chaque monitor ci-dessus:\n")
        f.write("   • Cliquez sur 'Add New Monitor'\n")
        f.write("   • Remplissez les champs selon les informations\n")
        f.write("   • Sauvegardez\n\n")
        f.write("4. Configurez les notifications (optionnel):\n")
        f.write("   • Settings → Notifications\n")
        f.write("   • Ajoutez Discord, Slack, Email, etc.\n\n")
        f.write("5. Créez une Status Page (optionnel):\n")
        f.write("   • Status Pages → Add New Status Page\n")
        f.write("   • Sélectionnez les monitors à afficher\n")

    log('SUCCESS', f'✓ Template créé: {templates_file}')
    return templates_file

def create_notification_examples():
    """Créer des exemples de configuration de notifications"""
    notifications_file = "./scripts/uptime-kuma-notifications-examples.json"

    examples = {
        "discord": {
            "name": "Discord Alerts",
            "type": "discord",
            "description": "Notifications Discord pour alertes critiques",
            "webhook_url": "https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN",
            "username": "Uptime Kuma",
            "content_template": "🚨 **Alert Laravel** 🚨\\n**Monitor:** {monitor.name}\\n**Status:** {monitor.status}\\n**URL:** {monitor.url}\\n**Time:** {monitor.localDateTime}"
        },
        "slack": {
            "name": "Slack Team Alerts",
            "type": "slack",
            "description": "Notifications Slack pour l'équipe",
            "webhook_url": "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK",
            "channel": "#monitoring",
            "username": "Uptime Kuma",
            "icon_emoji": ":warning:"
        },
        "email": {
            "name": "Email Alerts",
            "type": "smtp",
            "description": "Notifications email administrateur",
            "smtp_host": "localhost",
            "smtp_port": 1025,
            "smtp_secure": False,
            "smtp_username": "",
            "smtp_password": "",
            "from_email": "alerts@laravel.local",
            "to_email": "admin@laravel.local"
        },
        "webhook": {
            "name": "Custom Webhook",
            "type": "webhook",
            "description": "Webhook personnalisé pour intégrations",
            "url": "https://your-endpoint.com/webhook",
            "content_type": "application/json",
            "custom_headers": {
                "Authorization": "Bearer YOUR_TOKEN"
            }
        }
    }

    with open(notifications_file, 'w', encoding='utf-8') as f:
        json.dump(examples, f, indent=2, ensure_ascii=False)

    log('SUCCESS', f'✓ Exemples de notifications créés: {notifications_file}')
    return notifications_file

def show_manual_setup_guide():
    """Afficher le guide de configuration manuelle"""
    log('INFO', '📋 Guide de configuration manuelle')

    print(f"\n{Colors.CYAN}🔧 CONFIGURATION MANUELLE D'UPTIME KUMA{Colors.NC}")
    print(f"{Colors.CYAN}======================================={Colors.NC}")
    print()
    print(f"{Colors.YELLOW}1. 👤 Création du compte administrateur:{Colors.NC}")
    print(f"   • URL: {UPTIME_KUMA_URL}")
    print(f"   • Utilisateur: {ADMIN_USER}")
    print(f"   • Mot de passe: {ADMIN_PASS}")
    print(f"   • Email: {ADMIN_EMAIL}")
    print()
    print(f"{Colors.YELLOW}2. 📊 Ajout des monitors:{Colors.NC}")
    print("   • Utilisez le fichier template créé automatiquement")
    print("   • ./scripts/uptime-kuma-monitors-template.txt")
    print()
    print(f"{Colors.YELLOW}3. 🔔 Configuration des notifications:{Colors.NC}")
    print("   • Settings → Notifications")
    print("   • Utilisez les exemples dans:")
    print("   • ./scripts/uptime-kuma-notifications-examples.json")
    print()
    print(f"{Colors.YELLOW}4. 📱 Status Page (optionnel):{Colors.NC}")
    print("   • Status Pages → Add New Status Page")
    print("   • Sélectionnez les monitors critiques et importants")
    print("   • Partagez l'URL avec votre équipe")

def open_browser():
    """Ouvrir Uptime Kuma dans le navigateur"""
    log('INFO', '🌐 Ouverture d\'Uptime Kuma dans le navigateur...')

    try:
        webbrowser.open(UPTIME_KUMA_URL)
        log('SUCCESS', f'✓ Navigateur ouvert sur {UPTIME_KUMA_URL}')
    except Exception as e:
        log('ERROR', f'❌ Impossible d\'ouvrir le navigateur: {e}')
        log('INFO', f'🌐 Ouvrez manuellement: {UPTIME_KUMA_URL}')

def show_final_status(test_results):
    """Afficher le statut final et les recommandations"""
    print(f"\n{Colors.CYAN}📊 RÉSUMÉ DE LA CONFIGURATION{Colors.NC}")
    print(f"{Colors.CYAN}============================={Colors.NC}")

    # Statistiques
    total_services = len(test_results["accessible"]) + len(test_results["inaccessible"])
    total_ports = len(test_results["ports_open"]) + len(test_results["ports_closed"])

    print(f"\n{Colors.YELLOW}📈 Statistiques:{Colors.NC}")
    print(f"   • Services HTTP: {len(test_results['accessible'])}/{total_services} accessibles")
    print(f"   • Ports TCP: {len(test_results['ports_open'])}/{total_ports} ouverts")

    # Services accessibles
    if test_results["accessible"]:
        print(f"\n{Colors.GREEN}✅ Services accessibles:{Colors.NC}")
        for service in test_results["accessible"]:
            print(f"   • {service}")

    # Ports ouverts
    if test_results["ports_open"]:
        print(f"\n{Colors.GREEN}🔌 Ports ouverts:{Colors.NC}")
        for port in test_results["ports_open"]:
            print(f"   • {port}")

    # Problèmes détectés
    issues = test_results["inaccessible"] + test_results["ports_closed"]
    if issues:
        print(f"\n{Colors.RED}⚠️ Services à vérifier:{Colors.NC}")
        for issue in issues:
            print(f"   • {issue}")
        print(f"\n{Colors.BLUE}💡 Solutions:{Colors.NC}")
        print("   • Vérifiez que tous les containers sont démarrés: docker-compose ps")
        print("   • Redémarrez les services: make restart")
        print("   • Attendez l'initialisation complète (2-3 minutes)")

    # Instructions finales
    print(f"\n{Colors.BLUE}🎯 Prochaines étapes:{Colors.NC}")
    print(f"   1. Ouvrez Uptime Kuma: {UPTIME_KUMA_URL}")
    print(f"   2. Connectez-vous avec: {ADMIN_USER} / {ADMIN_PASS}")
    print("   3. Ajoutez les monitors depuis le template")
    print("   4. Configurez les notifications")
    print("   5. Testez les alertes")

    print(f"\n{Colors.PURPLE}📂 Fichiers créés:{Colors.NC}")
    print("   • ./scripts/uptime-kuma-monitors-template.txt")
    print("   • ./scripts/uptime-kuma-notifications-examples.json")

def main():
    """Fonction principale"""
    print(f"{Colors.PURPLE}🤖 CONFIGURATION AUTOMATIQUE COMPLÈTE D'UPTIME KUMA{Colors.NC}")
    print(f"{Colors.PURPLE}==================================================={Colors.NC}")
    print()

    # Vérifier l'accessibilité
    if not check_uptime_kuma_accessibility():
        log('ERROR', 'Impossible de continuer sans Uptime Kuma accessible')
        log('INFO', '💡 Démarrez l\'environnement: make up')
        sys.exit(1)

    # Tester les services
    test_results = test_services()

    # Créer les fichiers de templates
    create_templates_file()
    create_notification_examples()

    # Configuration manuelle (l'API automatique n'est pas disponible sans credentials)
    show_manual_setup_guide()

    # Ouvrir le navigateur
    open_browser()

    # Afficher le statut final
    show_final_status(test_results)

    print(f"\n{Colors.GREEN}✅ Configuration automatique terminée!{Colors.NC}")
    log('SUCCESS', '🎉 Uptime Kuma est prêt à être configuré!')

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n{Colors.YELLOW}⚠️ Configuration interrompue par l'utilisateur{Colors.NC}")
        sys.exit(130)
    except Exception as e:
        log('ERROR', f'❌ Erreur inattendue: {e}')
        sys.exit(1)