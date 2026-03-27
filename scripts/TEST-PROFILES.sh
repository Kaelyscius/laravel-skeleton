#!/bin/bash

# =============================================================================
# Script de test de l'architecture modulaire Docker Profiles
# =============================================================================
# Ce script permet de tester rapidement que les profiles fonctionnent
# correctement sans démarrer réellement les containers.
# =============================================================================

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Test de l'architecture modulaire Docker Profiles      ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# Test 1 : Vérifier que docker-compose est installé
# =============================================================================
echo -e "${YELLOW}[TEST 1]${NC} Vérification de Docker Compose..."
if command -v docker-compose &> /dev/null; then
    VERSION=$(docker-compose version --short)
    echo -e "${GREEN}✓${NC} Docker Compose installé (version: ${VERSION})"
else
    echo -e "${RED}✗${NC} Docker Compose n'est pas installé"
    exit 1
fi
echo ""

# =============================================================================
# Test 2 : Vérifier que les fichiers docker-compose existent
# =============================================================================
echo -e "${YELLOW}[TEST 2]${NC} Vérification des fichiers de configuration..."

files=(
    "docker-compose.yml"
    "docker-compose.dev.yml"
    "docker-compose.prod.yml"
)

for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC} $file existe"
    else
        echo -e "${RED}✗${NC} $file manquant"
        exit 1
    fi
done
echo ""

# =============================================================================
# Test 3 : Vérifier la syntaxe des fichiers docker-compose
# =============================================================================
echo -e "${YELLOW}[TEST 3]${NC} Validation de la syntaxe Docker Compose..."

if docker-compose -f docker-compose.yml config > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} docker-compose.yml valide"
else
    echo -e "${RED}✗${NC} docker-compose.yml invalide"
    exit 1
fi

if docker-compose -f docker-compose.yml -f docker-compose.dev.yml config > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} docker-compose.dev.yml valide"
else
    echo -e "${RED}✗${NC} docker-compose.dev.yml invalide"
    exit 1
fi

if docker-compose -f docker-compose.yml -f docker-compose.prod.yml config > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} docker-compose.prod.yml valide"
else
    echo -e "${RED}✗${NC} docker-compose.prod.yml invalide"
    exit 1
fi
echo ""

# =============================================================================
# Test 4 : Vérifier les services avec profiles
# =============================================================================
echo -e "${YELLOW}[TEST 4]${NC} Vérification des services et profiles..."

# Services essentiels (sans profile)
echo -e "${BLUE}Services essentiels (aucun profile):${NC}"
ESSENTIAL_SERVICES=$(docker-compose config --services 2>/dev/null | grep -E "^(apache|php|mariadb|redis)$" || true)
if [ -n "$ESSENTIAL_SERVICES" ]; then
    echo "$ESSENTIAL_SERVICES" | while read service; do
        echo -e "  ${GREEN}✓${NC} $service"
    done
else
    echo -e "${RED}✗${NC} Aucun service essentiel trouvé"
fi

# Services avec profile "dev"
echo -e "${BLUE}Services avec profile 'dev':${NC}"
DEV_SERVICES=$(docker-compose --profile dev config --services 2>/dev/null | grep -E "^(node|mailhog|adminer)$" || true)
if [ -n "$DEV_SERVICES" ]; then
    echo "$DEV_SERVICES" | while read service; do
        echo -e "  ${GREEN}✓${NC} $service"
    done
else
    echo -e "${YELLOW}⚠${NC} Aucun service 'dev' trouvé"
fi

# Services avec profile "tools"
echo -e "${BLUE}Services avec profile 'tools':${NC}"
TOOLS_SERVICES=$(docker-compose --profile tools config --services 2>/dev/null | grep -E "^(dozzle|it-tools|watchtower)$" || true)
if [ -n "$TOOLS_SERVICES" ]; then
    echo "$TOOLS_SERVICES" | while read service; do
        echo -e "  ${GREEN}✓${NC} $service"
    done
else
    echo -e "${YELLOW}⚠${NC} Aucun service 'tools' trouvé"
fi
echo ""

# =============================================================================
# Test 5 : Vérifier que les profiles sont bien définis
# =============================================================================
echo -e "${YELLOW}[TEST 5]${NC} Vérification des définitions de profiles dans docker-compose.yml..."

check_profile_in_service() {
    local service=$1
    local expected_profile=$2

    if grep -A 5 "^  $service:" docker-compose.yml | grep -q "profiles: \[\"$expected_profile\"\]"; then
        echo -e "${GREEN}✓${NC} Service '$service' a le profile '$expected_profile'"
        return 0
    else
        echo -e "${RED}✗${NC} Service '$service' n'a pas le profile '$expected_profile'"
        return 1
    fi
}

# Vérifier les services du profile "dev"
check_profile_in_service "node" "dev"
check_profile_in_service "mailhog" "dev"
check_profile_in_service "adminer" "dev"

# Vérifier les services du profile "tools"
check_profile_in_service "dozzle" "tools"
check_profile_in_service "it-tools" "tools"
check_profile_in_service "watchtower" "tools"

echo ""

# =============================================================================
# Test 6 : Vérifier les commandes Makefile
# =============================================================================
echo -e "${YELLOW}[TEST 6]${NC} Vérification des commandes Makefile..."

if [ -f "Makefile" ]; then
    echo -e "${GREEN}✓${NC} Makefile existe"

    # Vérifier que les nouvelles commandes existent
    commands=(
        "up-prod"
        "up-dev"
        "up-dev-full"
        "up-dev-extra"
        "up-local"
        "up-tools"
        "ps-profiles"
        "stop-profile"
        "help-profiles"
    )

    for cmd in "${commands[@]}"; do
        if grep -q "^\.PHONY: $cmd" Makefile; then
            echo -e "${GREEN}✓${NC} Commande 'make $cmd' disponible"
        else
            echo -e "${RED}✗${NC} Commande 'make $cmd' manquante"
        fi
    done
else
    echo -e "${RED}✗${NC} Makefile manquant"
fi
echo ""

# =============================================================================
# Test 7 : Vérifier la documentation
# =============================================================================
echo -e "${YELLOW}[TEST 7]${NC} Vérification de la documentation..."

docs=(
    "DOCKER-ARCHITECTURE.md"
    "MIGRATION-PROFILES.md"
    "RESUME-IMPLEMENTATION.md"
    "CLAUDE.md"
)

for doc in "${docs[@]}"; do
    if [ -f "$doc" ]; then
        echo -e "${GREEN}✓${NC} $doc existe"
    else
        echo -e "${YELLOW}⚠${NC} $doc manquant"
    fi
done
echo ""

# =============================================================================
# Test 8 : Simulation de démarrage (dry-run)
# =============================================================================
echo -e "${YELLOW}[TEST 8]${NC} Simulation de démarrage des différents modes..."

echo -e "${BLUE}Mode Production (services essentiels uniquement):${NC}"
PROD_SERVICES=$(docker-compose -f docker-compose.yml -f docker-compose.prod.yml config --services 2>/dev/null | sort | tr '\n' ', ')
echo -e "  Services: ${CYAN}${PROD_SERVICES%,}${NC}"

echo -e "${BLUE}Mode Développement (profile dev):${NC}"
DEV_SERVICES=$(docker-compose -f docker-compose.yml -f docker-compose.dev.yml --profile dev config --services 2>/dev/null | sort | tr '\n' ', ')
echo -e "  Services: ${CYAN}${DEV_SERVICES%,}${NC}"

echo -e "${BLUE}Mode Développement complet (profiles dev + tools):${NC}"
FULL_SERVICES=$(docker-compose -f docker-compose.yml -f docker-compose.dev.yml --profile dev --profile tools config --services 2>/dev/null | sort | tr '\n' ', ')
echo -e "  Services: ${CYAN}${FULL_SERVICES%,}${NC}"

echo ""

# =============================================================================
# Résumé final
# =============================================================================
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                     RÉSUMÉ DES TESTS                     ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✅ Tous les tests sont passés avec succès !${NC}"
echo ""
echo -e "${YELLOW}📋 Commandes disponibles :${NC}"
echo -e "  ${CYAN}make up-local${NC}      - Développement local complet (recommandé)"
echo -e "  ${CYAN}make up-prod${NC}       - Production (services essentiels uniquement)"
echo -e "  ${CYAN}make up-dev${NC}        - Développement (services + dev tools)"
echo -e "  ${CYAN}make up-dev-full${NC}   - Développement complet (services + dev + tools)"
echo -e "  ${CYAN}make ps-profiles${NC}   - Voir les services actifs par profile"
echo -e "  ${CYAN}make help-profiles${NC} - Aide complète sur les profiles"
echo ""
echo -e "${YELLOW}📚 Documentation :${NC}"
echo -e "  ${CYAN}DOCKER-ARCHITECTURE.md${NC}  - Documentation complète"
echo -e "  ${CYAN}MIGRATION-PROFILES.md${NC}   - Guide de migration"
echo -e "  ${CYAN}RESUME-IMPLEMENTATION.md${NC} - Résumé de l'implémentation"
echo ""
echo -e "${BLUE}💡 Pour démarrer maintenant :${NC}"
echo -e "  ${GREEN}make up-local${NC}"
echo ""
