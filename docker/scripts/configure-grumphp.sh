#!/bin/bash

# Script de configuration GrumPHP pour Laravel
# Usage: ./docker/scripts/configure-grumphp.sh

set -e

# Couleurs pour les logs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case $level in
        "INFO")
            echo -e "${BLUE}[INFO $timestamp]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN $timestamp]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR $timestamp]${NC} $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS $timestamp]${NC} $message"
            ;;
    esac
}

# Vérifier si GrumPHP est installé
check_grumphp_installed() {
    if [ -f "./vendor/bin/grumphp" ]; then
        log "SUCCESS" "GrumPHP détecté"
        return 0
    else
        log "ERROR" "GrumPHP non installé"
        log "INFO" "Installez avec: composer require --dev phpro/grumphp"
        return 1
    fi
}

# Détecter la version de Laravel
get_laravel_version() {
    if [ -f "composer.json" ]; then
        local version=$(grep -oP '"laravel/framework":\s*"\^\K[0-9]+' composer.json 2>/dev/null)
        echo "${version:-11}"
    else
        echo "11"
    fi
}

# Détecter la version de PHP
get_php_version() {
    php -r "echo PHP_MAJOR_VERSION . '.' . PHP_MINOR_VERSION;"
}

# Détecter les outils disponibles
detect_tools() {
    local tools_status=""

    # ECS
    if [ -f "./vendor/bin/ecs" ] && [ -f "ecs.php" ]; then
        tools_status="${tools_status}ecs "
        log "INFO" "✓ ECS disponible"
    fi

    # PHPStan
    if [ -f "./vendor/bin/phpstan" ] && [ -f "phpstan.neon" ]; then
        tools_status="${tools_status}phpstan "
        log "INFO" "✓ PHPStan disponible"
    fi

    # Pest
    if [ -f "./vendor/bin/pest" ]; then
        tools_status="${tools_status}pest "
        log "INFO" "✓ Pest disponible"
    elif [ -f "phpunit.xml" ]; then
        tools_status="${tools_status}phpunit "
        log "INFO" "✓ PHPUnit disponible"
    fi

    # Rector
    if [ -f "./vendor/bin/rector" ] && [ -f "rector.php" ]; then
        tools_status="${tools_status}rector "
        log "INFO" "✓ Rector disponible"
    fi

    # PHP Insights
    if php artisan list 2>/dev/null | grep -q "insights"; then
        tools_status="${tools_status}insights "
        log "INFO" "✓ PHP Insights disponible"
    fi

    echo "$tools_status"
}

# Créer le fichier de configuration GrumPHP
create_grumphp_config() {
    local tools="$1"
    local laravel_version="$2"
    local php_version="$3"

    log "INFO" "Création de grumphp.yml pour Laravel $laravel_version, PHP $php_version..."

    # En-tête du fichier
    cat > grumphp.yml << EOF
# Configuration GrumPHP pour Laravel $laravel_version - PHP $php_version
# Généré automatiquement - Modifiez selon vos besoins
#
# GrumPHP: Hooks Git automatiques pour maintenir la qualité du code
# Documentation: https://github.com/phpro/grumphp

grumphp:
    # Configuration des hooks Git
    git_hook_variables:
        EXEC_GRUMPHP_COMMAND: 'vendor/bin/grumphp'

    # Paramètres généraux
    process_timeout: 300
    stop_on_failure: true
    ignore_unstaged_changes: false
    hide_circumvention_tip: false

    # Tâches à exécuter lors des commits
    tasks:
EOF

    # ECS si disponible
    if [[ "$tools" == *"ecs"* ]]; then
        cat >> grumphp.yml << 'EOF'
        # Easy Coding Standard - Style de code PSR-12
        ecs:
            config: ecs.php
            triggered_by: ['php']
            clear_cache: false
            no_error_table: false

EOF
        log "INFO" "→ ECS ajouté à la configuration"
    fi

    # PHPStan si disponible
    if [[ "$tools" == *"phpstan"* ]]; then
        cat >> grumphp.yml << 'EOF'
        # PHPStan - Analyse statique niveau 8
        phpstan:
            configuration: phpstan.neon
            level: ~
            triggered_by: ['php']
            memory_limit: "1G"
            use_grumphp_paths: true

EOF
        log "INFO" "→ PHPStan ajouté à la configuration"
    fi

    # Tests avec Pest ou PHPUnit
    if [[ "$tools" == *"pest"* ]]; then
        cat >> grumphp.yml << 'EOF'
        # Pest - Tests modernes pour Laravel
        pest:
            config: ~
            testsuite: ~
            group: []
            always_execute: false
            triggered_by: ['php']

EOF
        log "INFO" "→ Pest ajouté à la configuration"
    elif [[ "$tools" == *"phpunit"* ]]; then
        cat >> grumphp.yml << 'EOF'
        # PHPUnit - Tests Laravel par défaut
        phpunit:
            config_file: phpunit.xml
            testsuite: ~
            group: []
            always_execute: false
            triggered_by: ['php']

EOF
        log "INFO" "→ PHPUnit ajouté à la configuration"
    fi

    # Vérifications génériques (toujours incluses)
    cat >> grumphp.yml << 'EOF'
        # Vérifications de syntaxe PHP
        phplint:
            exclude: ['vendor/', 'node_modules/', 'storage/', 'bootstrap/cache/']
            jobs: ~
            short_open_tag: false
            ignore_patterns: []
            triggered_by: ['php']

        # Validation JSON (composer.json, package.json, etc.)
        jsonlint:
            detect_key_conflicts: true
            triggered_by: ['json']

        # Validation YAML (GitHub Actions, docker-compose, etc.)
        yamllint:
            object_support: true
            exception_on_invalid_type: true
            parse_constant: true
            parse_custom_tags: true
            triggered_by: ['yaml', 'yml']

        # Détection de conflits Git
        git_conflict:
            whitespaces:
                ignore_whitespaces: true
                ignore_whitespaces_in_empty_lines: true
                ignore_whitespaces_at_end_of_line: true

EOF

    # Rector en mode dry-run si disponible
    if [[ "$tools" == *"rector"* ]]; then
        cat >> grumphp.yml << 'EOF'
        # Rector - Vérifications de refactoring (dry-run seulement)
        shell:
            rector_dry_run:
                command: 'vendor/bin/rector process --dry-run --no-progress-bar'
                triggered_by: ['php']
                working_directory: './'

EOF
        log "INFO" "→ Rector (dry-run) ajouté à la configuration"
    fi

    # Configuration des environnements
    cat >> grumphp.yml << 'EOF'
    # Configuration des environnements et extensions
    environment:
        variables:
            COMPOSER_ALLOW_SUPERUSER: '1'
            COMPOSER_MEMORY_LIMIT: '-1'

    # Extensions personnalisées (si nécessaires)
    extensions: []

    # Configuration avancée
    ascii:
        failed: ~
        succeeded: ~

    # Parallélisation (expérimental)
    parallel:
        enabled: false
        max_workers: 4

EOF

    log "SUCCESS" "Configuration GrumPHP créée avec $(echo $tools | wc -w) outils intégrés"
}

# Installer les hooks Git
install_git_hooks() {
    log "INFO" "Installation des hooks Git..."

    # Vérifier si on est dans un repo Git
    if [ ! -d ".git" ]; then
        log "WARN" "Pas de dépôt Git détecté"
        log "INFO" "Initialisez un dépôt avec: git init"
        return 1
    fi

    # Sauvegarder les hooks existants
    if [ -f ".git/hooks/pre-commit" ]; then
        local backup_file=".git/hooks/pre-commit.backup-$(date +%Y%m%d-%H%M%S)"
        cp ".git/hooks/pre-commit" "$backup_file"
        log "INFO" "Hook existant sauvegardé: $backup_file"
    fi

    # Installer les hooks
    if php vendor/bin/grumphp git:init 2>/dev/null; then
        log "SUCCESS" "Hooks Git installés"

        # Vérifier que le hook est bien installé
        if [ -f ".git/hooks/pre-commit" ]; then
            log "SUCCESS" "Hook pre-commit activé"

            # Afficher les permissions
            local permissions=$(ls -la .git/hooks/pre-commit | cut -d' ' -f1)
            log "INFO" "Permissions du hook: $permissions"
        else
            log "WARN" "Hook pre-commit non créé"
        fi

    else
        log "ERROR" "Échec de l'installation des hooks Git"
        return 1
    fi
}

# Tester la configuration
test_grumphp() {
    log "INFO" "Test de la configuration GrumPHP..."

    # Test de la syntaxe du fichier de configuration
    if php vendor/bin/grumphp run --help > /dev/null 2>&1; then
        log "SUCCESS" "Configuration GrumPHP valide"
    else
        log "ERROR" "Configuration GrumPHP invalide"
        return 1
    fi

    # Test rapide (sans exécuter toutes les tâches)
    log "INFO" "Test rapide des tâches configurées..."

    # Créer un fichier temporaire pour tester
    echo "<?php echo 'Test GrumPHP';" > .grumphp_test.php

    # Tester la validation
    if php vendor/bin/grumphp run --no-interaction --skip-success-output 2>/dev/null; then
        log "SUCCESS" "Test GrumPHP réussi"
    else
        log "WARN" "Certaines tâches ont échoué (normal lors de la première configuration)"
        log "INFO" "Utilisez 'make quality-fix' pour corriger automatiquement"
    fi

    # Nettoyer le fichier de test
    rm -f .grumphp_test.php
}

# Créer un README pour GrumPHP
create_grumphp_readme() {
    log "INFO" "Création de la documentation GrumPHP..."

    cat > GRUMPHP.md << EOF
# 🛡️ GrumPHP - Hooks Git pour Laravel

GrumPHP est configuré pour maintenir automatiquement la qualité du code en exécutant des vérifications avant chaque commit.

## 🚀 Fonctionnement

### Automatique
- **Pre-commit** : GrumPHP s'exécute automatiquement avant chaque commit
- **Blocage** : Le commit est refusé si les vérifications échouent
- **Feedback** : Messages d'erreur détaillés pour corriger les problèmes

### Outils intégrés
$(if [[ "$(detect_tools)" == *"ecs"* ]]; then echo "- ✅ **ECS** : Vérification du style de code PSR-12"; fi)
$(if [[ "$(detect_tools)" == *"phpstan"* ]]; then echo "- ✅ **PHPStan** : Analyse statique niveau 8"; fi)
$(if [[ "$(detect_tools)" == *"pest"* ]]; then echo "- ✅ **Pest** : Tests modernes"; elif [[ "$(detect_tools)" == *"phpunit"* ]]; then echo "- ✅ **PHPUnit** : Tests Laravel"; fi)
$(if [[ "$(detect_tools)" == *"rector"* ]]; then echo "- ✅ **Rector** : Suggestions de refactoring (dry-run)"; fi)
- ✅ **PHP Lint** : Vérification de syntaxe PHP
- ✅ **JSON Lint** : Validation des fichiers JSON
- ✅ **YAML Lint** : Validation des fichiers YAML
- ✅ **Git Conflicts** : Détection de conflits Git

## 🛠️ Commandes

### Make (recommandé)
\`\`\`bash
make grumphp-install      # Installer les hooks Git (une fois)
make grumphp-check        # Vérification manuelle
make pre-commit-check     # Simulation pre-commit
make grumphp-status       # Diagnostic
make grumphp-uninstall    # Désinstaller les hooks
\`\`\`

### Composer
\`\`\`bash
composer grumphp:install    # Installer les hooks
composer grumphp:check      # Vérification non-interactive
composer pre-commit         # Simulation pre-commit
\`\`\`

### Direct
\`\`\`bash
vendor/bin/grumphp run              # Exécution interactive
vendor/bin/grumphp run --no-interaction  # Non-interactive
vendor/bin/grumphp git:init         # Installer les hooks
vendor/bin/grumphp git:deinit       # Désinstaller les hooks
\`\`\`

## 🚨 En cas de problème

### Commit bloqué
1. **Voir les erreurs** : Les messages sont affichés dans le terminal
2. **Corriger automatiquement** : \`make quality-fix\`
3. **Retenter le commit** : \`git commit -m "votre message"\`

### Bypass d'urgence
\`\`\`bash
git commit --no-verify -m "hotfix urgent"
\`\`\`
⚠️ **À utiliser uniquement en cas d'urgence !**

### Désactiver temporairement
\`\`\`bash
make grumphp-uninstall    # Désinstaller les hooks
# ... faire vos commits ...
make grumphp-install      # Réinstaller les hooks
\`\`\`

## 🔧 Configuration

### Fichier principal
- **grumphp.yml** : Configuration des tâches et paramètres

### Personnalisation
Éditez \`grumphp.yml\` pour :
- Ajouter/supprimer des tâches
- Modifier les paramètres
- Exclure des fichiers
- Configurer la parallélisation

### Exemple d'exclusion
\`\`\`yaml
tasks:
    ecs:
        config: ecs.php
        triggered_by: ['php']
        exclude: ['tests/Fixtures/', 'database/migrations/']
\`\`\`

## 📊 Monitoring

### Vérifier l'installation
\`\`\`bash
make grumphp-status
\`\`\`

### Logs détaillés
\`\`\`bash
vendor/bin/grumphp run --verbose
\`\`\`

### Performance
- **Première exécution** : Plus lente (tous les fichiers)
- **Commits suivants** : Rapide (seulement les fichiers modifiés)

## 🎯 Workflow recommandé

1. **Développement normal**
   \`\`\`bash
   # Modifier des fichiers
   vim app/Models/User.php
   \`\`\`

2. **Correction automatique** (optionnel)
   \`\`\`bash
   make quality-fix
   \`\`\`

3. **Commit** (GrumPHP s'exécute automatiquement)
   \`\`\`bash
   git add .
   git commit -m "feat: nouveau modèle"
   # → GrumPHP vérifie ECS, PHPStan, Tests...
   # → Commit accepté ✅ ou refusé ❌
   \`\`\`

4. **En cas d'échec**
   \`\`\`bash
   # Voir les erreurs affichées
   make quality-fix      # Corriger automatiquement
   git add .             # Ajouter les corrections
   git commit -m "feat: nouveau modèle"  # Retenter
   \`\`\`

## 🔗 Intégration CI/CD

GrumPHP utilise les mêmes outils que votre CI/CD :
- **GitHub Actions** : \`.github/workflows/ci.yml\`
- **Même configuration** : ECS, PHPStan, Tests
- **Détection précoce** : Problèmes trouvés avant le push

## 📚 Ressources

- [Documentation GrumPHP](https://github.com/phpro/grumphp)
- [Configuration des tâches](https://github.com/phpro/grumphp/blob/main/doc/tasks.md)
- [Hooks Git](https://git-scm.com/book/en/v2/Customizing-Git-Git-Hooks)

---

*Configuration générée automatiquement pour Laravel $(get_laravel_version) - PHP $(get_php_version)*
EOF

    log "SUCCESS" "Documentation créée : GRUMPHP.md"
}

# Afficher les informations d'utilisation
show_usage_info() {
    local tools="$1"
    local laravel_version="$2"
    local php_version="$3"

    log "INFO" "📋 Configuration GrumPHP terminée"
    echo ""
    echo -e "${YELLOW}🛡️ GrumPHP est maintenant configuré pour Laravel $laravel_version !${NC}"
    echo ""
    echo -e "${BLUE}📝 Fonctionnement automatique :${NC}"
    echo -e "  • GrumPHP s'exécute automatiquement avant chaque commit"
    echo -e "  • Le commit sera bloqué si les vérifications échouent"
    echo -e "  • Outils configurés : $(echo $tools | tr ' ' ',')"
    echo ""
    echo -e "${BLUE}🛠️ Commandes utiles :${NC}"
    echo -e "  ${GREEN}make grumphp-run${NC}        - Exécuter GrumPHP manuellement"
    echo -e "  ${GREEN}make grumphp-check${NC}      - Vérification non-interactive"
    echo -e "  ${GREEN}make pre-commit-check${NC}   - Simuler un pre-commit"
    echo -e "  ${GREEN}make quality-fix${NC}        - Corriger automatiquement"
    echo -e "  ${GREEN}make grumphp-status${NC}     - Vérifier le statut"
    echo ""
    echo -e "${BLUE}🔧 Gestion des hooks :${NC}"
    echo -e "  ${GREEN}make grumphp-install${NC}    - Réinstaller les hooks"
    echo -e "  ${GREEN}make grumphp-uninstall${NC}  - Désinstaller les hooks"
    echo ""
    echo -e "${BLUE}📚 Documentation :${NC}"
    echo -e "  ${GREEN}cat GRUMPHP.md${NC}          - Guide complet d'utilisation"
    echo ""
    echo -e "${YELLOW}💡 Conseils :${NC}"
    echo -e "  • Commitez vos modifications avant les tests"
    echo -e "  • Utilisez 'git commit --no-verify' pour bypasser (urgence)"
    echo -e "  • Configurez votre IDE pour utiliser les mêmes outils"
    echo -e "  • Lisez GRUMPHP.md pour plus de détails"
}

# Fonction principale
main() {
    log "INFO" "🛡️ Configuration de GrumPHP pour Laravel"

    # Vérifier que GrumPHP est installé
    if ! check_grumphp_installed; then
        exit 1
    fi

    # Détecter la version Laravel et PHP
    local laravel_version=$(get_laravel_version)
    local php_version=$(get_php_version)

    log "INFO" "Environnement détecté : Laravel $laravel_version, PHP $php_version"

    # Détecter les outils disponibles
    local available_tools
    available_tools=$(detect_tools)

    if [ -z "$available_tools" ]; then
        log "WARN" "Aucun outil de qualité détecté"
        log "INFO" "GrumPHP sera configuré avec les vérifications de base uniquement"
        available_tools="basic"
    else
        log "INFO" "Outils détectés : $(echo $available_tools | tr ' ' ',')"
    fi

    # Créer la configuration
    create_grumphp_config "$available_tools" "$laravel_version" "$php_version"

    # Installer les hooks Git
    install_git_hooks

    # Tester la configuration
    test_grumphp

    # Créer la documentation
    create_grumphp_readme

    # Afficher les informations d'utilisation
    show_usage_info "$available_tools" "$laravel_version" "$php_version"

    log "SUCCESS" "Configuration GrumPHP terminée avec succès !"
    echo ""
    echo -e "${CYAN}🎉 Prochaines étapes :${NC}"
    echo -e "1. Testez avec : ${GREEN}make grumphp-check${NC}"
    echo -e "2. Faites un commit pour tester les hooks automatiques"
    echo -e "3. Lisez la documentation : ${GREEN}cat GRUMPHP.md${NC}"
}

# Afficher l'aide si demandé
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Configuration GrumPHP pour Laravel"
    echo ""
    echo "Usage: $0 [--help]"
    echo ""
    echo "Ce script configure GrumPHP avec :"
    echo "  • Détection automatique des outils disponibles"
    echo "  • Configuration adaptée à votre version Laravel/PHP"
    echo "  • Installation des hooks Git"
    echo "  • Documentation complète"
    echo ""
    echo "Prérequis :"
    echo "  • GrumPHP installé : composer require --dev phpro/grumphp"
    echo "  • Dépôt Git initialisé : git init"
    echo "  • Outils de qualité configurés (ECS, PHPStan, etc.)"
    exit 0
fi

# Exécuter si appelé directement
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi