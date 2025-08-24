#!/bin/bash

# Script pour configurer la mise à jour automatique des images custom
# Alternative à Watchtower pour surveiller nos images construites localement

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🔧 Configuration de la mise à jour automatique des images custom"

# Créer le répertoire de logs
mkdir -p "$PROJECT_ROOT/logs"

# Créer la tâche cron
cat > /tmp/docker-update-cron << EOF
# Mise à jour automatique des images Docker custom
# Vérifie les mises à jour tous les dimanche à 2h du matin
0 2 * * 0 cd "$PROJECT_ROOT" && "$SCRIPT_DIR/update-custom-images.sh" >/dev/null 2>&1

# Vérification quotidienne avec notification (optionnel)
# 0 8 * * * cd "$PROJECT_ROOT" && "$SCRIPT_DIR/update-custom-images.sh" --check-only
EOF

echo "📅 Ajout de la tâche cron..."

# Installer la tâche cron
if command -v crontab >/dev/null 2>&1; then
    # Sauvegarder le crontab existant
    crontab -l 2>/dev/null > /tmp/current-cron || touch /tmp/current-cron
    
    # Supprimer les anciennes tâches de mise à jour Docker
    grep -v "update-custom-images.sh" /tmp/current-cron > /tmp/new-cron || touch /tmp/new-cron
    
    # Ajouter la nouvelle tâche
    cat /tmp/docker-update-cron >> /tmp/new-cron
    
    # Installer le nouveau crontab
    crontab /tmp/new-cron
    
    echo "✅ Tâche cron installée - vérification des mises à jour chaque dimanche à 2h"
    
    # Nettoyer
    rm -f /tmp/current-cron /tmp/new-cron /tmp/docker-update-cron
else
    echo "⚠️  Crontab non disponible. Vous pouvez exécuter manuellement:"
    echo "   $SCRIPT_DIR/update-custom-images.sh"
fi

echo ""
echo "📋 Commandes disponibles:"
echo "  • Vérification manuelle:     $SCRIPT_DIR/update-custom-images.sh"
echo "  • Logs de mise à jour:       tail -f $PROJECT_ROOT/logs/image-updates.log" 
echo "  • Status des conteneurs:     docker compose ps"

# Ajouter au Makefile
if ! grep -q "update-images" "$PROJECT_ROOT/Makefile" 2>/dev/null; then
    echo "" >> "$PROJECT_ROOT/Makefile"
    echo "# Mise à jour des images custom" >> "$PROJECT_ROOT/Makefile"
    echo "update-images:" >> "$PROJECT_ROOT/Makefile"
    echo "	@\$(SCRIPT_DIR)/update-custom-images.sh" >> "$PROJECT_ROOT/Makefile"
    echo "" >> "$PROJECT_ROOT/Makefile"
    echo "check-image-updates:" >> "$PROJECT_ROOT/Makefile"
    echo "	@\$(SCRIPT_DIR)/update-custom-images.sh --check-only" >> "$PROJECT_ROOT/Makefile"
    
    echo "✅ Commandes ajoutées au Makefile:"
    echo "  • make update-images"
    echo "  • make check-image-updates"
fi

echo ""
echo "🎉 Configuration terminée ! Les images custom seront maintenant surveillées."