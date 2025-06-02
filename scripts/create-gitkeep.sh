#!/bin/bash

# Script pour créer les répertoires et fichiers .gitkeep nécessaires

# Créer les répertoires
mkdir -p docker/apache/logs
mkdir -p docker/apache/conf/ssl
mkdir -p docker/php/logs
mkdir -p docker/supervisor/logs
mkdir -p scripts/healthcheck
mkdir -p scripts/ci-cd
mkdir -p src

# Créer les fichiers .gitkeep
touch docker/apache/logs/.gitkeep
touch docker/apache/conf/ssl/.gitkeep
touch docker/php/logs/.gitkeep
touch docker/supervisor/logs/.gitkeep
touch scripts/healthcheck/.gitkeep
touch scripts/ci-cd/.gitkeep
touch src/.gitkeep

# Rendre les scripts exécutables
chmod +x docker/scripts/*.sh
chmod +x scripts/*.sh

echo "✓ Structure de répertoires créée avec succès"