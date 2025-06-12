#!/bin/bash

# Script de test pour Watchtower
# Usage: ./scripts/test-watchtower.sh

COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME:-"laravel-app"}

echo "🔄 Test de Watchtower"
echo "===================="

echo "📊 Statut:"
if docker ps --format "{{.Names}}" | grep -q "${COMPOSE_PROJECT_NAME}_watchtower"; then
    echo "  ✓ Watchtower en cours d'exécution"
else
    echo "  ✗ Watchtower non démarré"
    exit 1
fi

echo ""
echo "📋 Derniers logs:"
docker logs "${COMPOSE_PROJECT_NAME}_watchtower" --tail 15

echo ""
echo "🧪 Déclenchement d'une vérification manuelle:"
docker exec "${COMPOSE_PROJECT_NAME}_watchtower" /watchtower --run-once --cleanup 2>/dev/null || {
    echo "⚠️  Vérification manuelle non disponible"
}

echo ""
echo "✅ Test terminé"
