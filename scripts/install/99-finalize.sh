#!/bin/bash

# =============================================================================
# MODULE DE FINALISATION ET NETTOYAGE
# =============================================================================
#
# Ce module effectue les tâches finales : optimisations, nettoyage,
# génération des caches, vérifications finales et rapport.
#
# =============================================================================

set -e

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/laravel.sh"

init_logging "99-finalize"

optimize_composer() {
    log_info "Optimisation de Composer..."
    
    local composer_commands=(
        "composer install --optimize-autoloader --no-dev"
        "composer dump-autoload --optimize"
    )
    
    local environment=$(get_current_environment)
    if [ "$environment" = "local" ] || [ "$environment" = "development" ]; then
        # En développement, garder les packages dev
        composer_commands[0]="composer install --optimize-autoloader"
    fi
    
    for cmd in "${composer_commands[@]}"; do
        log_debug "Exécution: $cmd"
        if eval "$cmd" 2>&1 | tee -a "$LOG_FILE"; then
            log_debug "✓ Commande réussie"
        else
            log_warn "⚠ Problème avec: $cmd"
        fi
    done
    
    log_success "✅ Composer optimisé"
}

generate_ide_helpers() {
    log_info "Génération des IDE helpers..."
    
    # Commandes IDE helper si le package est installé
    local ide_commands=(
        "php artisan ide-helper:generate"
        "php artisan ide-helper:models --nowrite"
        "php artisan ide-helper:meta"
    )
    
    if is_package_installed "barryvdh/laravel-ide-helper"; then
        for cmd in "${ide_commands[@]}"; do
            log_debug "Exécution: $cmd"
            if eval "$cmd" 2>&1 | tee -a "$LOG_FILE"; then
                log_debug "✓ Commande réussie: $cmd"
            else
                log_debug "Commande ignorée: $cmd"
            fi
        done
        log_success "✅ IDE helpers générés"
    else
        log_debug "Package IDE helper non installé, ignoré"
    fi
}

configure_composer_scripts() {
    log_info "📝 Configuration des scripts Composer..."
    local laravel_version=$(get_laravel_version | cut -d. -f1)

    if [ -f "composer.json" ]; then
        python3 << EOF
import json
import sys
import os

try:
    with open('composer.json', 'r') as f:
        composer_data = json.load(f)

    if 'scripts' not in composer_data:
        composer_data['scripts'] = {}

    # Vérifier quels packages sont installés
    pest_available = os.path.exists('vendor/pestphp/pest')
    enlightn_available = False  # Enlightn non supporté pour Laravel 12+

    # Scripts de base toujours disponibles
    custom_scripts = {
        "quality": [
            "@check:cs",
            "@analyse",
            "@insights"
        ],
        "quality:fix": [
            "@fix:cs",
            "@refactor"
        ],
        "check:cs": "vendor/bin/ecs",
        "fix:cs": "vendor/bin/ecs --fix",
        "analyse": "vendor/bin/phpstan analyse",
        "refactor": "vendor/bin/rector process --dry-run",
        "refactor:fix": "vendor/bin/rector process",
        "insights": "php artisan insights",
        "insights:fix": "php artisan insights --fix",
        "ide-helper": [
            "php artisan ide-helper:generate",
            "php artisan ide-helper:meta",
            "php artisan ide-helper:models --write"
        ],
        "test:coverage": "php artisan test --coverage-html coverage"
    }

    # Scripts adaptatifs selon les packages installés
    if pest_available:
        custom_scripts.update({
            "test:unit": "vendor/bin/pest --testsuite=Unit",
            "test:feature": "vendor/bin/pest --testsuite=Feature",
            "test:pest": "vendor/bin/pest"
        })
        # Ajouter Pest aux scripts de qualité
        custom_scripts["quality:full"] = [
            "@check:cs",
            "@analyse",
            "@insights",
            "@test:pest"
        ]
    else:
        # Utiliser PHPUnit par défaut
        custom_scripts.update({
            "test:unit": "php artisan test --testsuite=Unit",
            "test:feature": "php artisan test --testsuite=Feature",
            "test:phpunit": "vendor/bin/phpunit"
        })
        # Ajouter PHPUnit aux scripts de qualité
        custom_scripts["quality:full"] = [
            "@check:cs",
            "@analyse",
            "@insights",
            "@test:unit"
        ]

    # Pour Laravel 12+, ne pas inclure Enlightn
    laravel_version = $laravel_version
    if laravel_version >= 12:
        custom_scripts["security"] = "echo '⚠️ Enlightn non compatible avec Laravel 12+ - utilisez les autres outils de qualité'"
        custom_scripts["enlightn"] = "echo '⚠️ Enlightn sera disponible quand il supportera Laravel 12+'"
    else:
        # Pour les versions antérieures, inclure Enlightn si disponible
        custom_scripts["security"] = "php artisan enlightn --format=github || echo '⚠️ Enlightn non disponible'"
        custom_scripts["enlightn"] = "php artisan enlightn || echo '⚠️ Enlightn non disponible'"

    composer_data['scripts'].update(custom_scripts)

    with open('composer.json', 'w') as f:
        json.dump(composer_data, f, indent=2)

    print("Scripts ajoutés au composer.json")
except Exception as e:
    print(f"Erreur lors de la modification du composer.json: {e}")
    sys.exit(1)
EOF
        if [ $? -eq 0 ]; then
            log_success "✅ Scripts Composer configurés (adaptés pour Laravel $laravel_version)"
        else
            log_error "❌ Échec de la modification du composer.json"
        fi
    else
        log_error "composer.json non trouvé"
        return 1
    fi
}

configure_test_database() {
    log_info "🗄️ Configuration de la base de données de test..."
    
    # Appeler le script de configuration de la base de données de test
    local test_db_script="$SCRIPT_DIR/../configure-test-database.sh"
    
    if [ -f "$test_db_script" ]; then
        log_debug "Exécution du script de configuration DB test"
        if bash "$test_db_script" 2>&1 | tee -a "$LOG_FILE"; then
            log_success "✅ Base de données de test configurée"
        else
            log_warn "⚠️ Problème lors de la configuration de la DB test (non-bloquant)"
        fi
    else
        log_warn "Script de configuration DB test non trouvé: $test_db_script"
    fi
}

setup_development_permissions() {
    log_info "🔧 Configuration des permissions pour le développement..."
    
    # Permissions pour l'édition depuis l'hôte (PhpStorm, VSCode, etc.)
    log_debug "Application des permissions de développement"
    
    # Directories: 775 (rwxrwxr-x) - group writable
    find . -type d -exec chmod 775 {} \; 2>/dev/null || true
    
    # Files: 664 (rw-rw-r--) - group writable
    find . -type f -exec chmod 664 {} \; 2>/dev/null || true
    
    # Executables spéciaux
    chmod +x artisan 2>/dev/null || true
    if [ -d "vendor/bin" ]; then
        find vendor/bin -type f -exec chmod +x {} \; 2>/dev/null || true
    fi
    
    # Laravel critical directories - full access
    for critical_dir in "storage" "bootstrap/cache"; do
        if [ -d "$critical_dir" ]; then
            chmod -R 777 "$critical_dir" 2>/dev/null || {
                log_debug "Fallback permissions pour $critical_dir"
                find "$critical_dir" -type d -exec chmod 775 {} \; 2>/dev/null || true
                find "$critical_dir" -type f -exec chmod 664 {} \; 2>/dev/null || true
            }
        fi
    done
    
    log_success "✅ Permissions de développement configurées"
}

final_optimizations() {
    log_info "Optimisations finales Laravel..."
    
    local environment=$(get_current_environment)
    
    if [ "$environment" = "production" ]; then
        optimize_laravel_for_production
    else
        optimize_laravel_for_development
    fi
    
    # Permissions finales Laravel
    setup_laravel_permissions
    
    # Permissions spéciales pour le développement
    if [ "$environment" != "production" ]; then
        setup_development_permissions
    fi
    
    log_success "✅ Optimisations terminées"
}

run_final_checks() {
    log_info "Vérifications finales..."
    
    local issues=0
    
    # Vérifier Laravel
    if check_laravel_health; then
        log_debug "✓ Laravel en bonne santé"
    else
        log_warn "⚠ Problèmes détectés dans Laravel"
        issues=$((issues + 1))
    fi
    
    # Vérifier les fichiers critiques
    local critical_files=("artisan" ".env" "composer.json")
    for file in "${critical_files[@]}"; do
        if [ -f "$file" ]; then
            log_debug "✓ $file présent"
        else
            log_error "✗ $file manquant"
            issues=$((issues + 1))
        fi
    done
    
    if [ $issues -eq 0 ]; then
        log_success "✅ Toutes les vérifications passées"
        return 0
    else
        log_warn "⚠ $issues problème(s) détecté(s)"
        return 1
    fi
}

show_final_report() {
    log_separator "RAPPORT FINAL D'INSTALLATION"
    
    # Informations Laravel
    show_laravel_info
    
    # Recommandations
    log_separator "RECOMMANDATIONS"
    log_info "🚀 Pour démarrer le développement:"
    log_info "   php artisan serve"
    log_info ""
    log_info "🔧 Commandes utiles:"
    log_info "   php artisan migrate          # Migrations"
    log_info "   php artisan queue:work       # Traitement des tâches"
    log_info "   npm run dev                  # Build frontend"
    log_info ""
    log_info "📊 Outils qualité:"
    log_info "   vendor/bin/phpstan analyse   # Analyse statique"
    log_info "   vendor/bin/ecs check         # Style de code"
    log_info "   vendor/bin/rector --dry-run  # Refactoring"
    
    log_separator "INSTALLATION TERMINÉE"
    log_success "🎉 Laravel installé et configuré avec succès !"
}

main() {
    local laravel_dir="${1:-$(detect_working_directory)}"
    local start_time=$(date +%s)
    
    log_separator "FINALISATION ET NETTOYAGE"
    log_info "🏁 Finalisation de l'installation dans: $laravel_dir"
    
    cd "$laravel_dir"
    
    if ! is_laravel_project "$laravel_dir"; then
        log_fatal "Pas un projet Laravel: $laravel_dir"
    fi
    
    # Étapes de finalisation
    optimize_composer
    generate_ide_helpers
    configure_composer_scripts
    final_optimizations
    
    # Configuration base de données de test (remplacer SQLite)
    configure_test_database
    
    # Vérifications finales
    local checks_passed=true
    if ! run_final_checks; then
        checks_passed=false
    fi
    
    # Rapport final
    show_final_report
    
    local duration=$(calculate_duration $start_time)
    
    if [ "$checks_passed" = true ]; then
        log_success "✅ Finalisation terminée avec succès en $duration"
        return 0
    else
        log_warn "⚠ Finalisation terminée avec des avertissements en $duration"
        return 0  # Non bloquant
    fi
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi