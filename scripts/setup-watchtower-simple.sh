#!/bin/bash

# Script de configuration simple pour Watchtower
# Usage: ./scripts/setup-watchtower-simple.sh

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME:-"laravel-app"}
ENV_FILE="./.env"

echo -e "${CYAN}🔄 Configuration simple de Watchtower${NC}"
echo -e "${CYAN}====================================${NC}"

# Fonction pour vérifier si Watchtower est en cours d'exécution
check_watchtower_status() {
    echo -e "${YELLOW}Vérification du statut de Watchtower...${NC}"

    if docker ps --format "{{.Names}}" | grep -q "${COMPOSE_PROJECT_NAME}_watchtower"; then
        echo -e "${GREEN}✓ Watchtower est en cours d'exécution${NC}"

        # Afficher les derniers logs
        echo -e "${YELLOW}📋 Derniers logs de Watchtower:${NC}"
        docker logs "${COMPOSE_PROJECT_NAME}_watchtower" --tail 10 2>/dev/null || echo -e "${YELLOW}Aucun log disponible${NC}"
        return 0
    else
        echo -e "${RED}✗ Watchtower n'est pas en cours d'exécution${NC}"
        return 1
    fi
}

# Fonction pour configurer les notifications simples
configure_notifications() {
    echo -e "${BLUE}📱 Configuration des notifications${NC}"
    echo -e "${BLUE}==================================${NC}"

    # Vérifier si le fichier .env existe
    if [ ! -f "$ENV_FILE" ]; then
        echo -e "${RED}❌ Fichier .env non trouvé${NC}"
        return 1
    fi

    # Sauvegarder le .env
    cp "$ENV_FILE" "${ENV_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
    echo -e "${YELLOW}✓ Sauvegarde du .env créée${NC}"

    echo -e "\n${YELLOW}Choisissez votre type de notification:${NC}"
    echo -e "1) ${CYAN}Aucune notification${NC} (logs uniquement)"
    echo -e "2) ${CYAN}Email simple${NC} (SMTP)"
    echo -e "3) ${CYAN}Webhook générique${NC} (pour Discord/Slack)"
    echo -e "4) ${CYAN}Configuration manuelle${NC} (je configurerai plus tard)"
    echo ""

    if [ -t 0 ]; then
        read -p "Votre choix (1-4): " choice
    else
        choice="1"
        echo -e "${YELLOW}Mode non-interactif: choix par défaut (1 - Aucune notification)${NC}"
    fi

    # Afficher le choix sélectionné
    echo ""
    case $choice in
        1)
            echo -e "${CYAN}➤ Choix sélectionné: ${YELLOW}Aucune notification${NC}"
            configure_no_notifications
            ;;
        2)
            echo -e "${CYAN}➤ Choix sélectionné: ${YELLOW}Email simple${NC}"
            configure_email_notifications
            ;;
        3)
            echo -e "${CYAN}➤ Choix sélectionné: ${YELLOW}Webhook générique${NC}"
            configure_webhook_notifications
            ;;
        4)
            echo -e "${CYAN}➤ Choix sélectionné: ${YELLOW}Configuration manuelle${NC}"
            configure_manual_notifications
            ;;
        *)
            echo -e "${CYAN}➤ Choix invalide (${choice}), utilisation par défaut: ${YELLOW}Aucune notification${NC}"
            configure_no_notifications
            ;;
    esac
}

# Configuration sans notifications
configure_no_notifications() {
    echo -e "${YELLOW}Configuration sans notifications...${NC}"

    # Supprimer ou commenter la ligne de notification
    sed -i '/^WATCHTOWER_NOTIFICATION_URL=/d' "$ENV_FILE"
    echo "# WATCHTOWER_NOTIFICATION_URL=" >> "$ENV_FILE"

    echo -e "${GREEN}✓ Watchtower configuré sans notifications${NC}"
    echo -e "${BLUE}→ Les mises à jour seront visibles dans les logs uniquement${NC}"
    echo ""
    
    # Ajouter une petite pause pour que l'utilisateur puisse lire
    if [ -t 0 ]; then
        echo -e "${CYAN}Appuyez sur Entrée pour continuer...${NC}"
        read -r
    else
        echo -e "${YELLOW}Configuration en mode non-interactif - continuation automatique${NC}"
        sleep 2
    fi
}

# Configuration email simple
configure_email_notifications() {
    echo -e "${YELLOW}Configuration des notifications email...${NC}"
    echo ""

    if [ -t 0 ]; then
        echo -e "${CYAN}Informations SMTP requises:${NC}"
        read -p "Serveur SMTP (ex: smtp.gmail.com): " smtp_host
        read -p "Port SMTP (ex: 587): " smtp_port
        read -p "Utilisateur SMTP: " smtp_user
        read -s -p "Mot de passe SMTP: " smtp_password
        echo ""
        read -p "Email expéditeur: " from_email
        read -p "Email destinataire: " to_email

        # Construire l'URL SMTP
        notification_url="smtp://${smtp_user}:${smtp_password}@${smtp_host}:${smtp_port}/?from=${from_email}&to=${to_email}"
    else
        echo -e "${YELLOW}Mode non-interactif: utilisation de MailHog local${NC}"
        notification_url="smtp://localhost:1025/?from=watchtower@laravel.local&to=admin@laravel.local"
    fi

    # Mettre à jour le .env
    sed -i '/^WATCHTOWER_NOTIFICATION_URL=/d' "$ENV_FILE"
    echo "WATCHTOWER_NOTIFICATION_URL=$notification_url" >> "$ENV_FILE"

    echo -e "${GREEN}✓ Notifications email configurées${NC}"
}

# Configuration webhook (Discord/Slack)
configure_webhook_notifications() {
    echo -e "${YELLOW}Configuration des notifications webhook...${NC}"
    echo ""

    if [ -t 0 ]; then
        echo -e "${CYAN}Types de webhook supportés:${NC}"
        echo -e "• Discord: discord://token@channel"
        echo -e "• Slack: slack://webhook_url"
        echo -e "• Générique: generic://webhook_url"
        echo ""

        read -p "URL du webhook complet: " webhook_url
    else
        echo -e "${YELLOW}Mode non-interactif: webhook générique configuré${NC}"
        webhook_url="generic://your-webhook-url"
    fi

    # Mettre à jour le .env
    sed -i '/^WATCHTOWER_NOTIFICATION_URL=/d' "$ENV_FILE"
    echo "WATCHTOWER_NOTIFICATION_URL=$webhook_url" >> "$ENV_FILE"

    echo -e "${GREEN}✓ Notifications webhook configurées${NC}"
}

# Configuration manuelle
configure_manual_notifications() {
    echo -e "${YELLOW}Configuration manuelle...${NC}"

    # Ajouter un commentaire avec les exemples
    sed -i '/^WATCHTOWER_NOTIFICATION_URL=/d' "$ENV_FILE"
    cat >> "$ENV_FILE" << 'EOF'

# Configuration Watchtower - Notifications
# Décommentez et configurez selon vos besoins:
#
# Discord:
# WATCHTOWER_NOTIFICATION_URL=discord://token@channel_id
#
# Slack:
# WATCHTOWER_NOTIFICATION_URL=slack://hook_url
#
# Email:
# WATCHTOWER_NOTIFICATION_URL=smtp://user:pass@host:port/?from=from@example.com&to=to@example.com
#
# Teams:
# WATCHTOWER_NOTIFICATION_URL=teams://token@tenant/altId/groupOwner?host=outlook.office.com
#
WATCHTOWER_NOTIFICATION_URL=
EOF

    echo -e "${GREEN}✓ Configuration manuelle préparée${NC}"
    echo -e "${BLUE}→ Éditez le fichier .env pour configurer vos notifications${NC}"
}

# Fonction pour configurer les exclusions de containers
configure_container_exclusions() {
    echo -e "${BLUE}🐳 Configuration des exclusions de containers${NC}"
    echo -e "${BLUE}=============================================${NC}"

    echo -e "${YELLOW}Containers avec images personnalisées (exclus par défaut):${NC}"
    echo -e "  • ${COMPOSE_PROJECT_NAME}_php (image custom Laravel)"
    echo -e "  • ${COMPOSE_PROJECT_NAME}_apache (configuration SSL custom)"
    echo -e "  • ${COMPOSE_PROJECT_NAME}_node (outils de build custom)"
    echo ""

    echo -e "${YELLOW}Containers avec images standard (mis à jour automatiquement):${NC}"
    echo -e "  • ${COMPOSE_PROJECT_NAME}_mariadb"
    echo -e "  • ${COMPOSE_PROJECT_NAME}_redis"
    echo -e "  • ${COMPOSE_PROJECT_NAME}_mailhog"
    echo -e "  • ${COMPOSE_PROJECT_NAME}_adminer"
    echo -e "  • ${COMPOSE_PROJECT_NAME}_it-tools"
    echo -e "  • ${COMPOSE_PROJECT_NAME}_dozzle"
    echo ""

    echo -e "${GREEN}✓ Configuration par défaut appropriée pour un environnement Laravel${NC}"
    echo -e "${BLUE}→ Les containers avec images custom sont protégés des mises à jour automatiques${NC}"
}

# Fonction pour configurer la planification
configure_schedule() {
    echo -e "${BLUE}⏰ Configuration de la planification${NC}"
    echo -e "${BLUE}===================================${NC}"

    echo -e "${YELLOW}Planification actuelle:${NC}"
    echo -e "  • Vérification: Tous les jours à 3h du matin"
    echo -e "  • Nettoyage: Automatique (anciennes images supprimées)"
    echo -e "  • Mode: Label-based (seuls les containers autorisés)"
    echo ""

    if [ -t 0 ]; then
        echo -e "${CYAN}Voulez-vous modifier la planification ? (y/N)${NC}"
        read -r modify_schedule

        if [[ "$modify_schedule" =~ ^[Yy]$ ]]; then
            configure_custom_schedule
        else
            echo -e "${GREEN}✓ Planification par défaut conservée${NC}"
        fi
    else
        echo -e "${GREEN}✓ Planification par défaut (3h du matin)${NC}"
    fi
}

# Configuration d'une planification personnalisée
configure_custom_schedule() {
    echo -e "${YELLOW}Configuration d'une planification personnalisée...${NC}"
    echo ""
    echo -e "${CYAN}Exemples de planification (format cron):${NC}"
    echo -e "  • Toutes les heures: 0 * * * * *"
    echo -e "  • Tous les jours à 2h: 0 0 2 * * *"
    echo -e "  • Tous les dimanche à 1h: 0 0 1 * * 0"
    echo -e "  • Toutes les 6h: 0 0 */6 * * *"
    echo ""

    read -p "Nouvelle planification (format cron): " custom_schedule

    # Mettre à jour le docker-compose.yml (nécessiterait un script plus complexe)
    echo -e "${YELLOW}⚠️  Pour modifier la planification, éditez manuellement:${NC}"
    echo -e "${CYAN}    docker-compose.yml → services.watchtower.environment.WATCHTOWER_SCHEDULE${NC}"
    echo -e "${CYAN}    Nouvelle valeur: $custom_schedule${NC}"
    echo ""
    echo -e "${BLUE}→ Puis redémarrez: make restart${NC}"
}

# Fonction pour tester Watchtower
test_watchtower() {
    echo -e "${BLUE}🧪 Test de Watchtower${NC}"
    echo -e "${BLUE}===================${NC}"

    if ! docker ps --format "{{.Names}}" | grep -q "${COMPOSE_PROJECT_NAME}_watchtower"; then
        echo -e "${RED}❌ Watchtower n'est pas en cours d'exécution${NC}"
        return 1
    fi

    echo -e "${YELLOW}Déclenchement d'une vérification manuelle...${NC}"

    # Déclencher une vérification immédiate
    docker exec "${COMPOSE_PROJECT_NAME}_watchtower" /watchtower --run-once --cleanup 2>/dev/null || {
        echo -e "${YELLOW}⚠️  Impossible de déclencher une vérification manuelle${NC}"
        echo -e "${BLUE}→ Cela peut être normal selon la configuration${NC}"
    }

    echo -e "${YELLOW}Affichage des logs récents...${NC}"
    docker logs "${COMPOSE_PROJECT_NAME}_watchtower" --tail 20

    echo -e "${GREEN}✓ Test terminé${NC}"
}

# Fonction pour afficher le statut des containers surveillés
show_monitored_containers() {
    echo -e "${BLUE}📊 Statut des containers surveillés${NC}"
    echo -e "${BLUE}==================================${NC}"

    echo -e "\n${YELLOW}🔄 Containers avec mise à jour automatique:${NC}"
    auto_update_containers=(
        "${COMPOSE_PROJECT_NAME}_mariadb"
        "${COMPOSE_PROJECT_NAME}_redis"
        "${COMPOSE_PROJECT_NAME}_mailhog"
        "${COMPOSE_PROJECT_NAME}_adminer"
        "${COMPOSE_PROJECT_NAME}_it-tools"
        "${COMPOSE_PROJECT_NAME}_dozzle"
        "${COMPOSE_PROJECT_NAME}_watchtower"
    )

    for container in "${auto_update_containers[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "^$container$"; then
            image=$(docker inspect "$container" --format="{{.Config.Image}}" 2>/dev/null)
            echo -e "  ${GREEN}✓ $container${NC} ($image)"
        else
            echo -e "  ${RED}✗ $container${NC} (non démarré)"
        fi
    done

    echo -e "\n${YELLOW}🛡️  Containers exclus (images custom):${NC}"
    excluded_containers=(
        "${COMPOSE_PROJECT_NAME}_php"
        "${COMPOSE_PROJECT_NAME}_apache"
        "${COMPOSE_PROJECT_NAME}_node"
    )

    for container in "${excluded_containers[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "^$container$"; then
            echo -e "  ${BLUE}⚠ $container${NC} (exclu - image custom)"
        else
            echo -e "  ${RED}✗ $container${NC} (non démarré)"
        fi
    done
}

# Fonction pour créer un script de test
create_test_script() {
    local test_script="./scripts/test-watchtower.sh"

    echo -e "${YELLOW}📝 Création d'un script de test...${NC}"

    mkdir -p ./scripts

    cat > "$test_script" << EOF
#!/bin/bash

# Script de test pour Watchtower
# Usage: ./scripts/test-watchtower.sh

COMPOSE_PROJECT_NAME=\${COMPOSE_PROJECT_NAME:-"laravel-app"}

echo "🔄 Test de Watchtower"
echo "===================="

echo "📊 Statut:"
if docker ps --format "{{.Names}}" | grep -q "\${COMPOSE_PROJECT_NAME}_watchtower"; then
    echo "  ✓ Watchtower en cours d'exécution"
else
    echo "  ✗ Watchtower non démarré"
    exit 1
fi

echo ""
echo "📋 Derniers logs:"
docker logs "\${COMPOSE_PROJECT_NAME}_watchtower" --tail 15

echo ""
echo "🧪 Déclenchement d'une vérification manuelle:"
docker exec "\${COMPOSE_PROJECT_NAME}_watchtower" /watchtower --run-once --cleanup 2>/dev/null || {
    echo "⚠️  Vérification manuelle non disponible"
}

echo ""
echo "✅ Test terminé"
EOF

    chmod +x "$test_script"
    echo -e "${GREEN}✓ Script de test créé: $test_script${NC}"
}

# Fonction principale
main() {
    echo -e "${CYAN}🚀 Configuration simple de Watchtower pour Laravel${NC}"
    echo ""

    # Vérifier le statut actuel
    check_watchtower_status
    echo ""

    # Configurer les notifications
    configure_notifications
    echo ""

    # Configurer les exclusions
    configure_container_exclusions
    echo ""

    # Configurer la planification
    configure_schedule
    echo ""

    # Afficher le statut des containers
    show_monitored_containers
    echo ""

    # Créer un script de test
    create_test_script
    echo ""

    # Tester Watchtower
    if [ -t 0 ]; then
        echo -e "${CYAN}Voulez-vous tester Watchtower maintenant ? (y/N)${NC}"
        read -r test_now
        if [[ "$test_now" =~ ^[Yy]$ ]]; then
            echo ""
            test_watchtower
        fi
    fi

    echo ""
    echo -e "${GREEN}✅ Configuration de Watchtower terminée !${NC}"
    echo ""
    echo -e "${YELLOW}📋 Résumé de la configuration:${NC}"
    echo -e "  • Planification: Tous les jours à 3h du matin"
    echo -e "  • Nettoyage: Automatique"
    echo -e "  • Containers exclus: Images custom (PHP, Apache, Node)"
    echo -e "  • Containers surveillés: Images standard (MariaDB, Redis, etc.)"

    if grep -q "^WATCHTOWER_NOTIFICATION_URL=" "$ENV_FILE"; then
        echo -e "  • Notifications: Configurées"
    else
        echo -e "  • Notifications: Désactivées"
    fi

    echo ""
    echo -e "${BLUE}🛠️  Commandes utiles:${NC}"
    echo -e "  • ${CYAN}make watchtower-logs${NC}        - Voir les logs"
    echo -e "  • ${CYAN}make watchtower-status${NC}      - Vérifier le statut"
    echo -e "  • ${CYAN}make watchtower-update-now${NC}  - Forcer une mise à jour"
    echo -e "  • ${CYAN}./scripts/test-watchtower.sh${NC} - Tester la configuration"
    echo ""
    echo -e "${YELLOW}💡 Redémarrez l'environnement pour appliquer les changements:${NC}"
    echo -e "    ${CYAN}make restart${NC}"
}

# Exécuter la fonction principale
main "$@"