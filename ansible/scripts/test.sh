#!/bin/bash
# Script de test après déploiement
# Usage: ./test.sh [environment] [host]

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(dirname "$SCRIPT_DIR")"

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction pour afficher les messages
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Fonction pour tester une URL
test_url() {
    local url="$1"
    local description="$2"
    local expected_status="${3:-200}"
    
    info "Test de $description: $url"
    
    if curl -s -o /dev/null -w "%{http_code}" "$url" | grep -q "$expected_status"; then
        log "✅ $description: $url (HTTP $expected_status)"
        return 0
    else
        error "❌ $description inaccessible: $url"
        return 1
    fi
}

# Fonction pour tester un service
test_service() {
    local host="$1"
    local service="$2"
    local description="$3"
    
    info "Test du service $service sur $host"
    
    if ansible "$host" -i "$ANSIBLE_DIR/inventories/$environment/hosts.yml" \
       -m service -a "name=$service state=started" >/dev/null 2>&1; then
        log "✅ $description: $service actif"
        return 0
    else
        error "❌ $description: $service inactif"
        return 1
    fi
}

# Fonction pour tester les conteneurs Docker
test_docker_containers() {
    local host="$1"
    local project_name="$2"
    
    info "Test des conteneurs Docker sur $host"
    
    local containers=("apache" "php" "mariadb" "redis")
    local failed_containers=()
    
    for container in "${containers[@]}"; do
        local container_name="${project_name}_${container}"
        
        if ansible "$host" -i "$ANSIBLE_DIR/inventories/$environment/hosts.yml" \
           -m shell -a "docker ps --filter 'name=$container_name' --filter 'status=running' --quiet" \
           | grep -q "SUCCESS"; then
            log "✅ Conteneur $container_name: running"
        else
            error "❌ Conteneur $container_name: stopped"
            failed_containers+=("$container_name")
        fi
    done
    
    if [[ ${#failed_containers[@]} -eq 0 ]]; then
        return 0
    else
        error "Conteneurs défaillants: ${failed_containers[*]}"
        return 1
    fi
}

# Fonction pour tester les ports
test_ports() {
    local host="$1"
    local ports=("80" "443" "22")
    
    info "Test des ports sur $host"
    
    for port in "${ports[@]}"; do
        if nmap -p "$port" "$host" 2>/dev/null | grep -q "open"; then
            log "✅ Port $port: ouvert"
        else
            warning "⚠️  Port $port: fermé ou filtré"
        fi
    done
}

# Fonction pour tester les logs
test_logs() {
    local host="$1"
    local project_name="$2"
    
    info "Test des logs sur $host"
    
    # Vérifier les logs Apache
    if ansible "$host" -i "$ANSIBLE_DIR/inventories/$environment/hosts.yml" \
       -m shell -a "docker logs ${project_name}_apache --tail=10" >/dev/null 2>&1; then
        log "✅ Logs Apache: accessibles"
    else
        error "❌ Logs Apache: inaccessibles"
    fi
    
    # Vérifier les logs PHP
    if ansible "$host" -i "$ANSIBLE_DIR/inventories/$environment/hosts.yml" \
       -m shell -a "docker logs ${project_name}_php --tail=10" >/dev/null 2>&1; then
        log "✅ Logs PHP: accessibles"
    else
        error "❌ Logs PHP: inaccessibles"
    fi
}

# Fonction pour tester la base de données
test_database() {
    local host="$1"
    local project_name="$2"
    
    info "Test de la base de données sur $host"
    
    if ansible "$host" -i "$ANSIBLE_DIR/inventories/$environment/hosts.yml" \
       -m shell -a "docker exec ${project_name}_mariadb mysql -u root -p\$(cat /var/www/laravel-app/.env | grep DB_ROOT_PASSWORD | cut -d'=' -f2) -e 'SHOW DATABASES;'" >/dev/null 2>&1; then
        log "✅ Base de données: accessible"
        return 0
    else
        error "❌ Base de données: inaccessible"
        return 1
    fi
}

# Fonction pour tester Redis
test_redis() {
    local host="$1"
    local project_name="$2"
    
    info "Test de Redis sur $host"
    
    if ansible "$host" -i "$ANSIBLE_DIR/inventories/$environment/hosts.yml" \
       -m shell -a "docker exec ${project_name}_redis redis-cli ping" >/dev/null 2>&1; then
        log "✅ Redis: accessible"
        return 0
    else
        error "❌ Redis: inaccessible"
        return 1
    fi
}

# Fonction pour tester les performances
test_performance() {
    local host="$1"
    
    info "Test des performances sur $host"
    
    # Test du temps de réponse
    local response_time=$(curl -o /dev/null -s -w "%{time_total}" "http://$host" || echo "0")
    
    if (( $(echo "$response_time < 2" | bc -l) )); then
        log "✅ Temps de réponse: ${response_time}s"
    else
        warning "⚠️  Temps de réponse lent: ${response_time}s"
    fi
    
    # Test de la charge système
    local load=$(ansible "$host" -i "$ANSIBLE_DIR/inventories/$environment/hosts.yml" \
                -m shell -a "uptime | awk -F'load average:' '{print \$2}' | awk '{print \$1}' | sed 's/,//'" 2>/dev/null | grep -o '[0-9.]*' | head -1)
    
    if [[ -n "$load" ]]; then
        if (( $(echo "$load < 2" | bc -l) )); then
            log "✅ Charge système: $load"
        else
            warning "⚠️  Charge système élevée: $load"
        fi
    fi
}

# Fonction pour tester la sécurité
test_security() {
    local host="$1"
    
    info "Test de sécurité sur $host"
    
    # Test UFW
    if ansible "$host" -i "$ANSIBLE_DIR/inventories/$environment/hosts.yml" \
       -m shell -a "ufw status" 2>/dev/null | grep -q "active"; then
        log "✅ Firewall UFW: actif"
    else
        warning "⚠️  Firewall UFW: inactif"
    fi
    
    # Test Fail2ban
    if ansible "$host" -i "$ANSIBLE_DIR/inventories/$environment/hosts.yml" \
       -m shell -a "systemctl is-active fail2ban" 2>/dev/null | grep -q "active"; then
        log "✅ Fail2ban: actif"
    else
        warning "⚠️  Fail2ban: inactif"
    fi
}

# Fonction pour tester les outils de monitoring
test_monitoring() {
    local host="$1"
    
    info "Test des outils de monitoring sur $host"
    
    # Test Dozzle
    test_url "http://$host:9999" "Dozzle (logs Docker)"
    
    # Test Adminer (si activé)
    if ansible "$host" -i "$ANSIBLE_DIR/inventories/$environment/hosts.yml" \
       -m shell -a "docker ps --filter 'name=adminer' --quiet" 2>/dev/null | grep -q "SUCCESS"; then
        test_url "http://$host:8080" "Adminer (base de données)"
    fi
    
    # Test Mailhog (si activé)
    if ansible "$host" -i "$ANSIBLE_DIR/inventories/$environment/hosts.yml" \
       -m shell -a "docker ps --filter 'name=mailhog' --quiet" 2>/dev/null | grep -q "SUCCESS"; then
        test_url "http://$host:8025" "Mailhog (capture emails)"
    fi
}

# Fonction pour générer un rapport
generate_report() {
    local host="$1"
    local project_name="$2"
    local report_file="/tmp/ansible_test_report_$(date +%Y%m%d_%H%M%S).txt"
    
    info "Génération du rapport: $report_file"
    
    cat > "$report_file" << EOF
# Rapport de test Ansible Laravel
Date: $(date)
Environnement: $environment
Hôte: $host
Projet: $project_name

## Résumé des tests

### Services système
$(ansible "$host" -i "$ANSIBLE_DIR/inventories/$environment/hosts.yml" -m shell -a "systemctl is-active docker nginx ssh" 2>/dev/null | grep -E "(SUCCESS|FAILED)")

### Conteneurs Docker
$(ansible "$host" -i "$ANSIBLE_DIR/inventories/$environment/hosts.yml" -m shell -a "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep $project_name" 2>/dev/null)

### Utilisation des ressources
$(ansible "$host" -i "$ANSIBLE_DIR/inventories/$environment/hosts.yml" -m shell -a "df -h | head -2; free -h | head -2; uptime" 2>/dev/null)

### Ports ouverts
$(nmap -p 22,80,443,3306,6379,8025,8080,9999 "$host" 2>/dev/null | grep -E "(open|closed|filtered)")

EOF
    
    log "📄 Rapport généré: $report_file"
}

# Fonction principale
main() {
    local environment="${1:-production}"
    local specific_host="${2:-}"
    
    log "🧪 Tests post-déploiement Ansible Laravel"
    log "Environnement: $environment"
    
    # Vérifier que l'inventaire existe
    if [[ ! -f "$ANSIBLE_DIR/inventories/$environment/hosts.yml" ]]; then
        error "Inventaire non trouvé: $ANSIBLE_DIR/inventories/$environment/hosts.yml"
        exit 1
    fi
    
    # Obtenir la liste des hôtes
    local hosts
    if [[ -n "$specific_host" ]]; then
        hosts=("$specific_host")
    else
        hosts=($(ansible-inventory -i "$ANSIBLE_DIR/inventories/$environment/hosts.yml" --list 2>/dev/null | jq -r '.web_servers.hosts[]' 2>/dev/null || echo "localhost"))
    fi
    
    local total_tests=0
    local failed_tests=0
    
    for host in "${hosts[@]}"; do
        log "🔍 Test de l'hôte: $host"
        
        # Obtenir les variables de l'hôte
        local project_name=$(ansible-inventory -i "$ANSIBLE_DIR/inventories/$environment/hosts.yml" --host "$host" 2>/dev/null | jq -r '.project_name' 2>/dev/null || echo "laravel-app")
        local host_ip=$(ansible-inventory -i "$ANSIBLE_DIR/inventories/$environment/hosts.yml" --host "$host" 2>/dev/null | jq -r '.ansible_host' 2>/dev/null || echo "$host")
        
        # Tests de connectivité
        ((total_tests++))
        if ansible "$host" -i "$ANSIBLE_DIR/inventories/$environment/hosts.yml" -m ping >/dev/null 2>&1; then
            log "✅ Connectivité Ansible: $host"
        else
            error "❌ Connectivité Ansible: $host"
            ((failed_tests++))
            continue
        fi
        
        # Tests des services
        ((total_tests++))
        test_service "$host" "docker" "Docker" || ((failed_tests++))
        
        # Tests des conteneurs
        ((total_tests++))
        test_docker_containers "$host" "$project_name" || ((failed_tests++))
        
        # Tests des URLs
        ((total_tests++))
        test_url "http://$host_ip" "Application Laravel" || ((failed_tests++))
        
        # Tests des ports
        ((total_tests++))
        test_ports "$host_ip" || ((failed_tests++))
        
        # Tests de la base de données
        ((total_tests++))
        test_database "$host" "$project_name" || ((failed_tests++))
        
        # Tests de Redis
        ((total_tests++))
        test_redis "$host" "$project_name" || ((failed_tests++))
        
        # Tests des logs
        ((total_tests++))
        test_logs "$host" "$project_name" || ((failed_tests++))
        
        # Tests de performance
        ((total_tests++))
        test_performance "$host_ip" || ((failed_tests++))
        
        # Tests de sécurité
        ((total_tests++))
        test_security "$host" || ((failed_tests++))
        
        # Tests de monitoring
        ((total_tests++))
        test_monitoring "$host_ip" || ((failed_tests++))
        
        # Générer un rapport
        generate_report "$host" "$project_name"
    done
    
    # Résumé final
    echo ""
    log "📊 Résumé des tests"
    log "Total des tests: $total_tests"
    log "Tests réussis: $((total_tests - failed_tests))"
    log "Tests échoués: $failed_tests"
    
    if [[ $failed_tests -eq 0 ]]; then
        log "🎉 Tous les tests sont passés avec succès !"
        exit 0
    else
        error "❌ $failed_tests test(s) ont échoué"
        exit 1
    fi
}

# Exécuter le script principal
main "$@"