#!/bin/bash

echo "🔗 Installation des hooks Git custom..."

if [ ! -d ".git" ]; then
    echo "❌ Pas un dépôt Git"
    exit 1
fi

# Créer le hook pre-commit
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash

echo "🔍 Vérifications de qualité avant commit..."

# Aller à la racine du projet
cd "$(git rev-parse --show-toplevel)"

# Vérifier que Docker est en cours
if ! docker ps >/dev/null 2>&1; then
    echo "❌ Docker n'est pas en cours d'exécution"
    exit 1
fi

# Lancer les vérifications de qualité
echo "→ Vérification du style de code..."
if ! make ecs; then
    echo "❌ Erreurs de style détectées"
    echo "💡 Corrigez avec: make ecs-fix"
    exit 1
fi

echo "→ Analyse statique..."
if ! make phpstan; then
    echo "❌ Erreurs PHPStan détectées"
    echo "💡 Consultez les erreurs ci-dessus"
    exit 1
fi

echo "→ Tests unitaires..."
if ! make test-unit; then
    echo "❌ Tests unitaires échoués"
    exit 1
fi

echo "✅ Toutes les vérifications sont passées !"
echo "🚀 Commit autorisé"
EOF

chmod +x .git/hooks/pre-commit
echo "✅ Hook pre-commit installé"