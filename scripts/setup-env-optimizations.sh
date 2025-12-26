#!/bin/bash

# =============================================================================
# Script de configuration des optimisations d'environnement
# =============================================================================

set -e

SHELL_RC="$HOME/.bashrc"
if [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
fi

echo "🚀 Configuration des optimisations pour WSL + Docker"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# =============================================================================
# 1. Docker BuildKit
# =============================================================================
echo ""
echo "📦 Configuration Docker BuildKit..."

if ! grep -q "DOCKER_BUILDKIT" "$SHELL_RC" 2>/dev/null; then
    cat >> "$SHELL_RC" << 'EOF'

# ============================================
# Docker BuildKit & Compose optimizations
# ============================================
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1
export BUILDKIT_PROGRESS=plain
EOF
    echo "✅ BuildKit activé dans $SHELL_RC"
else
    echo "✓ BuildKit déjà configuré"
fi

# =============================================================================
# 2. Composer Cache
# =============================================================================
echo ""
echo "🎵 Configuration Composer cache..."

if ! grep -q "COMPOSER_CACHE_DIR" "$SHELL_RC" 2>/dev/null; then
    cat >> "$SHELL_RC" << 'EOF'

# ============================================
# Composer optimizations
# ============================================
export COMPOSER_CACHE_DIR="$HOME/.cache/composer"
export COMPOSER_MEMORY_LIMIT=-1
EOF
    echo "✅ Composer cache configuré dans $SHELL_RC"
else
    echo "✓ Composer cache déjà configuré"
fi

# Créer le répertoire de cache
mkdir -p "$HOME/.cache/composer"
echo "✅ Répertoire cache créé: $HOME/.cache/composer"

# =============================================================================
# 3. NPM/Node optimizations
# =============================================================================
echo ""
echo "📦 Configuration NPM..."

if ! grep -q "NPM_CONFIG" "$SHELL_RC" 2>/dev/null; then
    cat >> "$SHELL_RC" << 'EOF'

# ============================================
# NPM optimizations
# ============================================
export NPM_CONFIG_CACHE="$HOME/.npm-cache"
export NPM_CONFIG_PREFER_OFFLINE=true
EOF
    echo "✅ NPM optimisations ajoutées dans $SHELL_RC"
else
    echo "✓ NPM déjà configuré"
fi

mkdir -p "$HOME/.npm-cache"

# =============================================================================
# 4. WSL optimizations
# =============================================================================
echo ""
echo "🐧 Configuration WSL..."

if ! grep -q "WSLENV" "$SHELL_RC" 2>/dev/null; then
    cat >> "$SHELL_RC" << 'EOF'

# ============================================
# WSL performance optimizations
# ============================================
# Forward Docker env vars to Windows
export WSLENV=DOCKER_BUILDKIT:COMPOSE_DOCKER_CLI_BUILD
EOF
    echo "✅ Variables WSL configurées"
else
    echo "✓ WSL déjà configuré"
fi

# =============================================================================
# 5. Vérification
# =============================================================================
echo ""
echo "🔍 Vérification de la configuration..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Source the RC file pour cette session
source "$SHELL_RC" 2>/dev/null || true

echo ""
echo "Variables configurées:"
echo "  DOCKER_BUILDKIT=${DOCKER_BUILDKIT:-non défini}"
echo "  COMPOSE_DOCKER_CLI_BUILD=${COMPOSE_DOCKER_CLI_BUILD:-non défini}"
echo "  COMPOSER_CACHE_DIR=${COMPOSER_CACHE_DIR:-non défini}"
echo "  NPM_CONFIG_CACHE=${NPM_CONFIG_CACHE:-non défini}"

# =============================================================================
# 6. Docker Desktop config (Windows)
# =============================================================================
echo ""
echo "⚙️  Configuration Docker Desktop recommandée (Windows):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Ouvrir Docker Desktop → Settings → Resources"
echo "   → WSL Integration: Activer pour votre distribution Debian"
echo ""
echo "2. Settings → Docker Engine, ajouter:"
cat << 'EOF'
{
  "builder": {
    "gc": {
      "enabled": true,
      "defaultKeepStorage": "20GB"
    }
  },
  "experimental": true,
  "features": {
    "buildkit": true
  }
}
EOF

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Configuration terminée !"
echo ""
echo "⚠️  IMPORTANT: Redémarrez votre terminal pour appliquer les changements"
echo ""
echo "Ou exécutez: source $SHELL_RC"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📚 Prochaines étapes:"
echo "  1. Redémarrer le terminal"
echo "  2. Lancer: make install-fast"
echo "  3. Consulter: PERFORMANCE-OPTIMIZATIONS.md"
echo ""
