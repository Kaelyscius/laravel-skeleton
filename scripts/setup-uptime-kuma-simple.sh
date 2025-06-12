#!/bin/bash

# Script de configuration simple pour Uptime Kuma
# Usage: ./scripts/setup-uptime-kuma-simple.sh

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

UPTIME_KUMA_URL="http://localhost:3001"
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME:-"laravel-app"}

echo -e "${CYAN}🔍 Configuration simple d'Uptime Kuma${NC}"
echo -e "${CYAN}====================================${NC}"

# Vérifier si Uptime Kuma est accessible
check_uptime_kuma() {
    echo -e "${YELLOW}Vérification d'Uptime Kuma...${NC}"

    max_attempts=30
    attempt=1

    while [ $attempt -le $max_attempts ]; do
        if curl -s -f "$UPTIME_KUMA_URL" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Uptime Kuma est accessible${NC}"
            return 0
        fi

        echo -e "${YELLOW}⏳ Tentative $attempt/$max_attempts - Uptime Kuma non accessible...${NC}"
        sleep 2
        ((attempt++))
    done

    echo -e "${RED}❌ Uptime Kuma n'est pas accessible après $max_attempts tentatives${NC}"
    echo -e "${YELLOW}💡 Vérifiez que le service est démarré: make up${NC}"
    return 1
}

# Ouvrir Uptime Kuma dans le navigateur
open_uptime_kuma() {
    echo -e "${BLUE}🌐 Ouverture d'Uptime Kuma...${NC}"

    if command -v open >/dev/null 2>&1; then
        # macOS
        open "$UPTIME_KUMA_URL"
    elif command -v xdg-open >/dev/null 2>&1; then
        # Linux
        xdg-open "$UPTIME_KUMA_URL"
    elif command -v start >/dev/null 2>&1; then
        # Windows
        start "$UPTIME_KUMA_URL"
    else
        echo -e "${YELLOW}→ Ouvrez manuellement: $UPTIME_KUMA_URL${NC}"
    fi
}

# Afficher les instructions de configuration manuelle
show_manual_instructions() {
    echo -e "${BLUE}📋 Instructions de configuration manuelle${NC}"
    echo -e "${BLUE}=======================================${NC}"
    echo ""
    echo -e "${YELLOW}1. 👤 Création du compte administrateur :${NC}"
    echo -e "   • Utilisateur: admin"
    echo -e "   • Mot de passe: (choisissez un mot de passe sécurisé)"
    echo ""
    echo -e "${YELLOW}2. 🏠 Monitors essentiels à créer :${NC}"
    echo ""
    echo -e "${CYAN}   📱 Application Laravel${NC}"
    echo -e "   • Type: HTTP(s)"
    echo -e "   • Nom: Laravel Application"
    echo -e "   • URL: https://laravel.local"
    echo -e "   • Mot-clé (optionnel): Laravel"
    echo -e "   • Intervalle: 60 secondes"
    echo -e "   • Tags: critical, laravel, web"
    echo ""
    echo -e "${CYAN}   🗄️  Base de données MariaDB${NC}"
    echo -e "   • Type: Port"
    echo -e "   • Nom: MariaDB Database"
    echo -e "   • Hostname: localhost"
    echo -e "   • Port: 3306"
    echo -e "   • Intervalle: 120 secondes"
    echo -e "   • Tags: critical, database"
    echo ""
    echo -e "${CYAN}   🔄 Cache Redis${NC}"
    echo -e "   • Type: Port"
    echo -e "   • Nom: Redis Cache"
    echo -e "   • Hostname: localhost"
    echo -e "   • Port: 6379"
    echo -e "   • Intervalle: 120 secondes"
    echo -e "   • Tags: important, cache"
    echo ""
    echo -e "${CYAN}   🐳 Container Apache${NC}"
    echo -e "   • Type: Docker Container"
    echo -e "   • Nom: Apache Web Server"
    echo -e "   • Container: ${COMPOSE_PROJECT_NAME}_apache"
    echo -e "   • Intervalle: 180 secondes"
    echo -e "   • Tags: infrastructure"
    echo ""
    echo -e "${CYAN}   🌐 Services de développement${NC}"
    echo -e "   • MailHog: http://localhost:8025"
    echo -e "   • Adminer: http://localhost:8080"
    echo -e "   • IT-Tools: http://localhost:8081"
    echo -e "   • Dozzle: http://localhost:9999"
    echo -e "   • Type: HTTP, Intervalle: 300 secondes, Tags: tools"
    echo ""
    echo -e "${YELLOW}3. 🔔 Configuration des notifications (optionnel) :${NC}"
    echo -e "   • Allez dans Settings → Notifications"
    echo -e "   • Configurez Discord, Slack, Email selon vos besoins"
    echo -e "   • Testez les notifications"
    echo ""
    echo -e "${YELLOW}4. 📊 Status Page (optionnel) :${NC}"
    echo -e "   • Créez une Status Page publique"
    echo -e "   • Sélectionnez les monitors à afficher"
    echo -e "   • Partagez l'URL avec votre équipe"
    echo ""
}

# Afficher les exemples de configuration avancée
show_advanced_tips() {
    echo -e "${BLUE}💡 Conseils avancés${NC}"
    echo -e "${BLUE}==================${NC}"
    echo ""
    echo -e "${YELLOW}🎯 Stratégie de monitoring recommandée :${NC}"
    echo ""
    echo -e "${GREEN}Monitors critiques${NC} (alerte immédiate) :"
    echo -e "  • Application Laravel"
    echo -e "  • Base de données"
    echo -e "  • Cache Redis"
    echo ""
    echo -e "${YELLOW}Monitors importants${NC} (alerte après 2-3 échecs) :"
    echo -e "  • Horizon Dashboard"
    echo -e "  • Telescope"
    echo -e "  • Services de développement"
    echo ""
    echo -e "${BLUE}Monitors informatifs${NC} (alerte après 5+ échecs) :"
    echo -e "  • Outils de développement"
    echo -e "  • Métriques non-critiques"
    echo ""
    echo -e "${YELLOW}📱 Notifications recommandées :${NC}"
    echo -e "  • Critique: Discord/Slack + Email"
    echo -e "  • Important: Discord/Slack"
    echo -e "  • Informatif: Email uniquement"
    echo ""
    echo -e "${YELLOW}📈 Intervalles recommandés :${NC}"
    echo -e "  • Application web: 60s"
    echo -e "  • Base de données: 120s"
    echo -e "  • Services internes: 300s"
    echo -e "  • Outils de développement: 600s"
    echo ""
}

# Créer un fichier de configuration de base
create_config_template() {
    local config_file="./scripts/uptime-kuma-monitors.txt"

    echo -e "${YELLOW}📝 Création d'un template de configuration...${NC}"

    mkdir -p ./scripts

    cat > "$config_file" << EOF
# Template de monitors Uptime Kuma pour environnement Laravel
# Copiez-collez ces informations dans l'interface Uptime Kuma

=== MONITORS CRITIQUES ===

1. Laravel Application
   Type: HTTP(s)
   URL: https://laravel.local
   Méthode: GET
   Intervalle: 60s
   Timeout: 10s
   Retry: 3
   Tags: critical,laravel,web

2. MariaDB Database
   Type: Port
   Hostname: localhost
   Port: 3306
   Intervalle: 120s
   Tags: critical,database

3. Redis Cache
   Type: Port
   Hostname: localhost
   Port: 6379
   Intervalle: 120s
   Tags: critical,cache

=== MONITORS IMPORTANTS ===

4. Laravel Horizon
   Type: HTTP(s)
   URL: https://laravel.local/horizon
   Intervalle: 180s
   Tags: important,laravel,queues

5. Laravel Telescope
   Type: HTTP(s)
   URL: https://laravel.local/telescope
   Intervalle: 300s
   Tags: important,laravel,debug

=== SERVICES DE DÉVELOPPEMENT ===

6. MailHog
   Type: HTTP
   URL: http://localhost:8025
   Intervalle: 300s
   Tags: tools,dev

7. Adminer
   Type: HTTP
   URL: http://localhost:8080
   Intervalle: 300s
   Tags: tools,database

8. IT-Tools
   Type: HTTP
   URL: http://localhost:8081
   Intervalle: 300s
   Tags: tools,dev

9. Dozzle (Logs)
   Type: HTTP
   URL: http://localhost:9999
   Intervalle: 300s
   Tags: tools,monitoring

=== CONTAINERS DOCKER ===

10. Apache Container
    Type: Docker Container
    Container: ${COMPOSE_PROJECT_NAME}_apache
    Intervalle: 180s
    Tags: infrastructure,docker

11. PHP Container
    Type: Docker Container
    Container: ${COMPOSE_PROJECT_NAME}_php
    Intervalle: 180s
    Tags: infrastructure,docker

=== NOTIFICATIONS RECOMMANDÉES ===

- Discord: Pour les alertes critiques et importantes
- Email: Pour toutes les alertes
- Slack: Alternative à Discord pour les équipes

=== GROUPES ET TAGS ===

Tags recommandés:
- critical: Services essentiels (alerte immédiate)
- important: Services importants (alerte après 2-3 échecs)
- tools: Outils de développement
- infrastructure: Containers et services système
- laravel: Services spécifiques à Laravel

EOF

    echo -e "${GREEN}✓ Template créé: $config_file${NC}"
    echo -e "${YELLOW}→ Ce fichier contient tous les détails pour configurer vos monitors${NC}"
}

# Afficher le statut des services
show_services_status() {
    echo -e "${BLUE}📊 Statut des services à monitorer${NC}"
    echo -e "${BLUE}==================================${NC}"

    # Vérifier les services web
    services_web=(
        "Laravel:https://laravel.local"
        "MailHog:http://localhost:8025"
        "Adminer:http://localhost:8080"
        "IT-Tools:http://localhost:8081"
        "Dozzle:http://localhost:9999"
    )

    echo -e "\n${YELLOW}🌐 Services Web:${NC}"
    for service_info in "${services_web[@]}"; do
        IFS=':' read -r name url <<< "$service_info"
        if curl -s -f "$url" > /dev/null 2>&1; then
            echo -e "  ${GREEN}✓ $name${NC} ($url)"
        else
            echo -e "  ${RED}✗ $name${NC} ($url) - Non accessible"
        fi
    done

    # Vérifier les ports
    echo -e "\n${YELLOW}🔌 Ports:${NC}"
    ports=("3306:MariaDB" "6379:Redis" "80:Apache HTTP" "443:Apache HTTPS")
    for port_info in "${ports[@]}"; do
        IFS=':' read -r port name <<< "$port_info"
        if nc -z localhost "$port" 2>/dev/null; then
            echo -e "  ${GREEN}✓ $name${NC} (port $port)"
        else
            echo -e "  ${RED}✗ $name${NC} (port $port) - Non accessible"
        fi
    done

    # Vérifier les containers Docker
    echo -e "\n${YELLOW}🐳 Containers Docker:${NC}"
    containers=("${COMPOSE_PROJECT_NAME}_apache" "${COMPOSE_PROJECT_NAME}_php" "${COMPOSE_PROJECT_NAME}_mariadb" "${COMPOSE_PROJECT_NAME}_redis")
    for container in "${containers[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "^$container$"; then
            status=$(docker inspect "$container" --format="{{.State.Health.Status}}" 2>/dev/null || echo "running")
            if [ "$status" = "healthy" ]; then
                echo -e "  ${GREEN}✓ $container${NC} (healthy)"
            elif [ "$status" = "running" ] || [ "$status" = "" ]; then
                echo -e "  ${YELLOW}⚠ $container${NC} (running, no health check)"
            else
                echo -e "  ${RED}✗ $container${NC} ($status)"
            fi
        else
            echo -e "  ${RED}✗ $container${NC} (not running)"
        fi
    done
}

# Fonction principale
main() {
    echo -e "${CYAN}🚀 Configuration simple d'Uptime Kuma pour Laravel${NC}"
    echo ""

    # Vérifier Uptime Kuma
    if ! check_uptime_kuma; then
        echo -e "${RED}Impossible de continuer sans Uptime Kuma accessible${NC}"
        echo -e "${YELLOW}💡 Démarrez d'abord l'environnement: make up${NC}"
        exit 1
    fi

    # Afficher le statut des services
    show_services_status

    # Créer le template de configuration
    create_config_template

    echo ""
    echo -e "${GREEN}🎯 Prochaines étapes:${NC}"
    echo -e "1. ${YELLOW}Ouvrir Uptime Kuma dans votre navigateur${NC}"
    echo -e "2. ${YELLOW}Créer votre compte administrateur${NC}"
    echo -e "3. ${YELLOW}Utiliser le template créé pour configurer vos monitors${NC}"
    echo ""

    # Proposer d'ouvrir automatiquement
    if [ -t 0 ]; then
        echo -e "${CYAN}Voulez-vous ouvrir Uptime Kuma maintenant ? (y/N)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            open_uptime_kuma
        fi
    else
        echo -e "${YELLOW}→ URL: $UPTIME_KUMA_URL${NC}"
    fi

    echo ""
    show_manual_instructions
    echo ""
    show_advanced_tips

    echo ""
    echo -e "${GREEN}✅ Configuration simple terminée !${NC}"
    echo -e "${YELLOW}💡 Pour une configuration automatique avancée, utilisez: make setup-monitoring-auto${NC}"
}

# Exécuter la fonction principale
main "$@"