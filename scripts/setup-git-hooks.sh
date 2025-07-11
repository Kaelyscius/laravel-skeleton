#!/bin/bash

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}🔗 Installation des hooks Git avec options d'urgence...${NC}"

if [ ! -d ".git" ]; then
    echo -e "${RED}❌ Pas un dépôt Git${NC}"
    exit 1
fi

# Sauvegarder les hooks existants
if [ -f ".git/hooks/pre-commit" ]; then
    backup_file=".git/hooks/pre-commit.backup-$(date +%Y%m%d-%H%M%S)"
    cp ".git/hooks/pre-commit" "$backup_file"
    echo -e "${YELLOW}📋 Hook existant sauvegardé : $backup_file${NC}"
fi

# Créer le hook pre-commit avec support bypass d'urgence
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash

# 🚨 BYPASS D'URGENCE
if [ "$SKIP_HOOKS" = "true" ] || [ "$EMERGENCY_COMMIT" = "true" ]; then
    echo "🚨 BYPASS D'URGENCE ACTIVÉ - Hook ignoré"
    echo "⚠️  N'oubliez pas de corriger les problèmes plus tard !"
    exit 0
fi

echo "🔍 Vérifications de qualité avant commit..."

# Aller à la racine du projet
cd "$(git rev-parse --show-toplevel)"

# Vérifier que Docker est en cours
if ! docker ps >/dev/null 2>&1; then
    echo "❌ Docker n'est pas en cours d'exécution"
    echo ""
    echo "🚨 OPTIONS DE BYPASS D'URGENCE :"
    echo "   git commit --no-verify -m \"votre message\""
    echo "   SKIP_HOOKS=true git commit -m \"votre message\""
    echo "   EMERGENCY_COMMIT=true git commit -m \"hotfix urgent\""
    exit 1
fi

# Détection automatique du contexte (merge/rebase)
if [ -f ".git/MERGE_HEAD" ] || [ -f ".git/REBASE_HEAD" ]; then
    echo "🔀 Merge/Rebase détecté - vérifications allégées"
    LIGHT_CHECK=true
else
    LIGHT_CHECK=false
fi

# Fonction pour afficher les options de bypass en cas d'erreur
show_bypass_options() {
    echo ""
    echo "🚨 OPTIONS DE BYPASS D'URGENCE :"
    echo "   git commit --no-verify -m \"votre message\""
    echo "   SKIP_HOOKS=true git commit -m \"votre message\""
    echo "   EMERGENCY_COMMIT=true git commit -m \"hotfix urgent\""
}

# Vérifications selon le contexte
if [ "$LIGHT_CHECK" = "true" ]; then
    echo "→ Vérifications rapides pour merge/rebase..."

    # Seulement vérifier la syntaxe PHP
    echo "→ Vérification syntaxe PHP..."
    if ! make shell cmd="find . -name '*.php' -exec php -l {} \;" 2>/dev/null; then
        echo "❌ Erreurs de syntaxe PHP détectées"
        show_bypass_options
        exit 1
    fi
else
    echo "→ Vérifications complètes..."

    # Vérification du style de code
    echo "→ Vérification du style de code..."
    if ! make ecs; then
        echo "❌ Erreurs de style détectées"
        echo "💡 Corrigez avec: make ecs-fix"
        show_bypass_options
        exit 1
    fi

    # Analyse statique
    echo "→ Analyse statique..."
    if ! make phpstan; then
        echo "❌ Erreurs PHPStan détectées"
        echo "💡 Consultez les erreurs ci-dessus"
        show_bypass_options
        exit 1
    fi

    # Tests unitaires
    echo "→ Tests unitaires..."
    if ! make test-unit; then
        echo "❌ Tests unitaires échoués"
        show_bypass_options
        exit 1
    fi
fi

echo "✅ Toutes les vérifications sont passées !"
echo "🚀 Commit autorisé"
EOF

chmod +x .git/hooks/pre-commit

# Configuration des alias Git pour faciliter les urgences
echo -e "${YELLOW}📝 Configuration des alias Git pour les urgences...${NC}"

git config alias.emergency-commit "commit --no-verify"
git config alias.hotfix "!f() { git commit --no-verify -m \"hotfix: \$1\"; }; f"
git config alias.quick-commit "!f() { SKIP_HOOKS=true git commit -m \"\$1\"; }; f"

echo -e "${GREEN}✅ Hook pre-commit installé avec options d'urgence${NC}"
echo ""
echo -e "${CYAN}🚨 OPTIONS DE BYPASS DISPONIBLES :${NC}"
echo ""
echo -e "${YELLOW}1. Option --no-verify (recommandée) :${NC}"
echo -e "   ${BLUE}git commit --no-verify -m \"hotfix urgent\"${NC}"
echo -e "   ${BLUE}git commit -n -m \"hotfix urgent\"${NC} (version courte)"
echo ""
echo -e "${YELLOW}2. Variables d'environnement :${NC}"
echo -e "   ${BLUE}SKIP_HOOKS=true git commit -m \"hotfix urgent\"${NC}"
echo -e "   ${BLUE}EMERGENCY_COMMIT=true git commit -m \"hotfix urgent\"${NC}"
echo ""
echo -e "${YELLOW}3. Alias Git configurés :${NC}"
echo -e "   ${BLUE}git emergency-commit -m \"hotfix urgent\"${NC}"
echo -e "   ${BLUE}git hotfix \"correction urgente\"${NC}"
echo -e "   ${BLUE}git quick-commit \"fix rapide\"${NC}"
echo ""
echo -e "${YELLOW}💡 Recommandation pour les urgences :${NC}"
echo -e "   ${CYAN}git commit --no-verify -m \"hotfix: description du problème urgent\"${NC}"
echo ""
echo -e "${RED}⚠️  Workflow post-urgence recommandé :${NC}"
echo -e "   ${BLUE}make quality-fix${NC}      # Corrections automatiques"
echo -e "   ${BLUE}make quality-all${NC}      # Vérifications complètes"
echo -e "   ${BLUE}git add .${NC}"
echo -e "   ${BLUE}git commit -m \"fix: corrections qualité post-hotfix\"${NC}"