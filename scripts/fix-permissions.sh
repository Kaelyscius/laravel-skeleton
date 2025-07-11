#!/bin/bash

# =============================================================================
# CORRECTION DES PERMISSIONS - Scripts exécutables
# =============================================================================

set -e

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔧 Correction des permissions des scripts...${NC}"

# Répertoire du projet
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Scripts à rendre exécutables
SCRIPTS=(
    "scripts/setup/interactive-setup.sh"
    "scripts/setup/generate-configs.sh"
    "scripts/security/snyk-scan.sh"
    "scripts/setup-watchtower-simple.sh"
    "scripts/setup-git-hooks.sh"
    "scripts/create-gitkeep.sh"
    "scripts/test-watchtower.sh"
    "scripts/fix-permissions.sh"
    "docker/scripts/generate-ssl.sh"
    "docker/scripts/install-laravel.sh"
    "docker/scripts/configure-grumphp.sh"
    "docker/apache/scripts/docker-entrypoint.sh"
    "docker/php/scripts/docker-entrypoint.sh"
)

# Créer les répertoires s'ils n'existent pas
echo -e "${YELLOW}📁 Création des répertoires nécessaires...${NC}"
mkdir -p scripts/setup
mkdir -p scripts/security
mkdir -p config
mkdir -p docker/scripts
mkdir -p docker/apache/scripts
mkdir -p docker/php/scripts

# Corriger les permissions
echo -e "${YELLOW}⚙️ Correction des permissions...${NC}"
FIXED_COUNT=0
for script in "${SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        if [ ! -x "$script" ]; then
            chmod +x "$script"
            echo -e "  ${GREEN}✓ $script${NC}"
            FIXED_COUNT=$((FIXED_COUNT + 1))
        else
            echo -e "  ${BLUE}○ $script (déjà exécutable)${NC}"
        fi
    else
        echo -e "  ${YELLOW}⚠ $script (fichier non trouvé)${NC}"
    fi
done

echo ""
echo -e "${GREEN}✅ $FIXED_COUNT scripts rendus exécutables${NC}"

# Correction spéciale pour les scripts Docker
echo -e "${YELLOW}🐳 Correction des scripts Docker...${NC}"
find docker/ -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true
find scripts/ -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true

echo -e "${GREEN}✅ Toutes les permissions corrigées !${NC}"
echo ""
echo -e "${BLUE}💡 Vous pouvez maintenant lancer:${NC}"
echo -e "  ${GREEN}make setup-interactive${NC}"
echo -e "  ${GREEN}make generate-config ENV=local${NC}"