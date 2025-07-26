#!/bin/bash

# =============================================================================
# SCRIPT DE CORRECTION DES PERMISSIONS DOCKER-LARAVEL
# =============================================================================
#
# Ce script corrige les permissions des fichiers Laravel pour permettre
# une édition depuis l'hôte (PhpStorm) et un fonctionnement correct dans Docker.
#
# Usage: ./scripts/fix-permissions.sh [target_directory]
#
# =============================================================================

set -e

# Configuration
DEFAULT_TARGET="/var/www/html/myLaravelSkeleton/src"
TARGET_DIR="${1:-$DEFAULT_TARGET}"
USER_ID="${USER_ID:-1000}"
GROUP_ID="${GROUP_ID:-1000}"

echo "🔧 Correction des permissions Laravel pour Docker + PhpStorm"
echo "📁 Répertoire cible: $TARGET_DIR"
echo "👤 UID:GID: $USER_ID:$GROUP_ID"
echo ""

if [ ! -d "$TARGET_DIR" ]; then
    echo "❌ Répertoire non trouvé: $TARGET_DIR"
    exit 1
fi

cd "$TARGET_DIR"

# Vérifier que c'est un projet Laravel
if [ ! -f "artisan" ] || [ ! -f "composer.json" ]; then
    echo "❌ Pas un projet Laravel valide dans: $TARGET_DIR"
    exit 1
fi

echo "🔄 Application des permissions de base..."

# 1. Définir la propriété correcte
echo "  → Propriété des fichiers (chown $USER_ID:$GROUP_ID)"
chown -R "$USER_ID:$GROUP_ID" . 2>/dev/null || {
    echo "  ⚠️ Impossible de changer la propriété, tentative sans chown"
}

# 2. Permissions pour les répertoires (775 = rwxrwxr-x)
echo "  → Permissions des répertoires (775)"
find . -type d -exec chmod 775 {} \; 2>/dev/null || true

# 3. Permissions pour les fichiers (664 = rw-rw-r--)
echo "  → Permissions des fichiers (664)"
find . -type f -exec chmod 664 {} \; 2>/dev/null || true

# 4. Permissions spéciales pour les exécutables
echo "  → Permissions des exécutables"
chmod +x artisan 2>/dev/null || true

if [ -d "vendor/bin" ]; then
    find vendor/bin -type f -exec chmod +x {} \; 2>/dev/null || true
fi

# 5. Permissions Laravel critiques
echo "🚀 Permissions spéciales Laravel..."

# Storage: Laravel doit pouvoir écrire (777)
if [ -d "storage" ]; then
    echo "  → Storage (777)"
    chmod -R 777 storage 2>/dev/null || {
        echo "  ⚠️ Problème avec storage, tentative alternative"
        find storage -type d -exec chmod 775 {} \; 2>/dev/null || true
        find storage -type f -exec chmod 664 {} \; 2>/dev/null || true
    }
fi

# Bootstrap cache: Laravel doit pouvoir écrire (777)
if [ -d "bootstrap/cache" ]; then
    echo "  → Bootstrap cache (777)"
    chmod -R 777 bootstrap/cache 2>/dev/null || {
        echo "  ⚠️ Problème avec bootstrap/cache, permissions alternatives"
        find bootstrap/cache -type d -exec chmod 775 {} \; 2>/dev/null || true
        find bootstrap/cache -type f -exec chmod 664 {} \; 2>/dev/null || true
    }
fi

# Config cache (si existant)
if [ -d "bootstrap/cache" ]; then
    echo "  → Cache de configuration"
    touch bootstrap/cache/.gitkeep 2>/dev/null || true
    chmod 664 bootstrap/cache/.gitkeep 2>/dev/null || true
fi

# 6. Permissions pour les répertoires de développement
echo "📝 Permissions de développement..."

# Logs
if [ -d "storage/logs" ]; then
    echo "  → Logs"
    chmod -R 775 storage/logs 2>/dev/null || true
fi

# Sessions
if [ -d "storage/framework/sessions" ]; then
    echo "  → Sessions"
    chmod -R 775 storage/framework/sessions 2>/dev/null || true
fi

# Cache framework
if [ -d "storage/framework/cache" ]; then
    echo "  → Cache framework"
    chmod -R 775 storage/framework/cache 2>/dev/null || true
fi

# Views compilées
if [ -d "storage/framework/views" ]; then
    echo "  → Vues compilées"
    chmod -R 775 storage/framework/views 2>/dev/null || true
fi

# 7. Répertoires de développement qui doivent être accessibles
echo "🛠️ Répertoires de développement..."

for dev_dir in "app" "config" "database" "resources" "routes" "tests"; do
    if [ -d "$dev_dir" ]; then
        echo "  → $dev_dir"
        find "$dev_dir" -type d -exec chmod 775 {} \; 2>/dev/null || true
        find "$dev_dir" -type f -exec chmod 664 {} \; 2>/dev/null || true
    fi
done

# 8. Vérifications finales
echo ""
echo "🔍 Vérifications finales..."

# Vérifier que artisan est exécutable
if [ -x "artisan" ]; then
    echo "  ✅ artisan exécutable"
else
    echo "  ❌ artisan non exécutable"
    chmod +x artisan 2>/dev/null || echo "  ⚠️ Impossible de corriger artisan"
fi

# Vérifier que storage est accessible en écriture
if [ -w "storage" ]; then
    echo "  ✅ storage accessible en écriture"
else
    echo "  ❌ storage non accessible en écriture"
fi

# Vérifier que bootstrap/cache est accessible
if [ -w "bootstrap/cache" ]; then
    echo "  ✅ bootstrap/cache accessible en écriture"
else
    echo "  ❌ bootstrap/cache non accessible en écriture"
fi

# Test de création/suppression de fichier
TEST_FILE="storage/logs/permission-test-$$.tmp"
if touch "$TEST_FILE" 2>/dev/null && rm "$TEST_FILE" 2>/dev/null; then
    echo "  ✅ Test écriture/suppression réussi"
else
    echo "  ⚠️ Test écriture/suppression échoué"
fi

echo ""
echo "🎉 Correction des permissions terminée !"
echo ""
echo "💡 Utilisation depuis PhpStorm:"
echo "   - Les fichiers doivent être modifiables"
echo "   - La suppression/création doit fonctionner"
echo "   - Laravel doit pouvoir écrire ses caches"
echo ""
echo "🔄 Si des problèmes persistent:"
echo "   1. Redémarrer PhpStorm"
echo "   2. Invalider les caches: File > Invalidate Caches and Restart"
echo "   3. Relancer ce script: ./scripts/fix-permissions.sh"
echo "   4. Vérifier les mappings Docker: ./src:/var/www/html"