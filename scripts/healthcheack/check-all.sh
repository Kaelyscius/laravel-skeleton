#!/bin/bash

# Script de healthcheck global pour tous les services

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "🏥 Vérification de santé des services..."
echo "======================================="

# Fonction pour vérifier un service
check_service() {
    local service=$1
    local container_name=$2

    if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "$container_name.*healthy"; then
        echo -e "${GREEN}✓ $service${NC} : Healthy"
        return 0
    elif docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "$container_name.*unhealthy"; then
        echo -e "${RED}✗ $service${NC} : Unhealthy"
        return 1
    elif docker ps --format "table {{.Names}}" | grep -q "$container_name"; then
        echo -e "${YELLOW}⚠ $service${NC} : Running (no health check)"
        return 0
    else
        echo -e "${RED}✗ $service${NC} : Not running"
        return 1
    fi
}

# Vérifier tous les services
services=(
    "Apache:laravel-app_apache"
    "PHP-FPM:laravel-app_php"
    "MariaDB:laravel-app_mariadb"
    "Redis:laravel-app_redis"
    "Node.js:laravel-app_node"
    "MailHog:laravel-app_mailhog"
    "Adminer:laravel-app_adminer"
    "Dozzle:laravel-app_dozzle"
)

failed=0
for service_info in "${services[@]}"; do
    IFS=':' read -r service container <<< "$service_info"
    check_service "$service" "$container" || ((failed++))
done

echo "======================================="

# Vérifications supplémentaires
echo -e "\n📊 Vérifications supplémentaires :"

# Vérifier l'accès HTTPS
if curl -k -s -o /dev/null -w "%{http_code}" https://localhost | grep -q "200\|301\|302"; then
    echo -e "${GREEN}✓ HTTPS accessible${NC}"
else
    echo -e "${RED}✗ HTTPS non accessible${NC}"
    ((failed++))
fi

# Vérifier l'utilisation des ressources
echo -e "\n📈 Utilisation des ressources :"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# Résultat final
echo -e "\n======================================="
if [ $failed -eq 0 ]; then
    echo -e "${GREEN}✅ Tous les services sont opérationnels !${NC}"
    exit 0
else
    echo -e "${RED}❌ $failed service(s) en erreur${NC}"
    exit 1
fi