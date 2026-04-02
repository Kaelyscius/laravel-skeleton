#!/bin/bash

# =============================================================================
# MODULE DE CONFIGURATION PEST + PLUGIN DRIFT
# =============================================================================
#
# Ce module configure Pest avec le plugin Drift pour la détection
# de code non couvert par les tests
#
# =============================================================================

set -e

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/laravel.sh"

init_logging "45-configure-pest"

main() {
    local laravel_dir="${1:-$(detect_working_directory)}"
    local start_time=$(date +%s)

    log_separator "CONFIGURATION PEST + DRIFT"
    log_info "🧪 Configuration de Pest dans: $laravel_dir"

    cd "$laravel_dir"

    if ! is_laravel_project "$laravel_dir"; then
        log_fatal "Pas un projet Laravel: $laravel_dir"
    fi

    # Vérifier si Pest est installé
    if ! is_package_installed "pestphp/pest"; then
        log_warn "⚠️ Pest n'est pas installé - configuration ignorée"
        return 0
    fi

    # Créer le fichier Pest.php s'il n'existe pas
    if [ ! -f "tests/Pest.php" ]; then
        log_info "📝 Création de tests/Pest.php..."
        create_pest_config
    else
        log_debug "✓ tests/Pest.php existe déjà"
        update_pest_config
    fi

    # Vérifier si pest-plugin-drift est installé
    if is_package_installed "pestphp/pest-plugin-drift"; then
        log_info "🎯 Configuration du plugin Drift..."
        configure_drift_plugin
    else
        log_debug "✓ Pest plugin Drift non installé - configuration ignorée"
    fi

    # Créer les répertoires de tests s'ils n'existent pas
    ensure_test_directories

    # Créer des tests d'exemple si aucun test n'existe
    if [ ! -f "tests/Feature/ExampleTest.php" ]; then
        log_info "📄 Création des tests d'exemple..."
        create_example_tests
    fi

    local duration=$(calculate_duration $start_time)
    log_success "✅ Configuration Pest terminée en $duration"
}

create_pest_config() {
    cat > tests/Pest.php << 'EOF'
<?php

use Illuminate\Foundation\Testing\RefreshDatabase;

/*
|--------------------------------------------------------------------------
| Test Case
|--------------------------------------------------------------------------
|
| The closure you provide to your test functions is always bound to a specific PHPUnit test
| case class. By default, that class is "PHPUnit\Framework\TestCase". Of course, you may
| need to change it using the "pest()" function to bind a different classes or traits.
|
*/

pest()->extend(Tests\TestCase::class)->in('Feature');

/*
|--------------------------------------------------------------------------
| Expectations
|--------------------------------------------------------------------------
|
| When you're writing tests, you often need to check that values meet certain conditions. The
| "expect()" function gives you access to a set of "expectations" methods that you can use
| to assert different things. Of course, you may extend the Expectation API at any time.
|
*/

expect()->extend('toBeOne', function () {
    return $this->toBe(1);
});

/*
|--------------------------------------------------------------------------
| Functions
|--------------------------------------------------------------------------
|
| While Pest is very powerful out-of-the-box, you may have some testing code specific to your
| project that you don't want to repeat in every file. Here you can also expose helpers as
| global functions to help you to reduce the number of lines of code in your test files.
|
*/

function something()
{
    // ..
}
EOF

    log_success "✅ Fichier tests/Pest.php créé"
}

update_pest_config() {
    # Vérifier si le fichier contient déjà la configuration RefreshDatabase
    if ! grep -q "RefreshDatabase" tests/Pest.php; then
        log_info "⚡ Ajout de RefreshDatabase à la configuration Pest..."

        # Backup du fichier
        cp tests/Pest.php tests/Pest.php.backup

        # Ajouter l'import RefreshDatabase si manquant
        if ! grep -q "use Illuminate\\Foundation\\Testing\\RefreshDatabase" tests/Pest.php; then
            sed -i '1a use Illuminate\\Foundation\\Testing\\RefreshDatabase;' tests/Pest.php
            log_success "✅ Import RefreshDatabase ajouté"
        fi
    fi
}

configure_drift_plugin() {
    log_info "Configuration du plugin Drift (v4)..."

    # Pest Plugin Drift v4 s'active automatiquement via Composer.
    # Il n'utilise PAS de fichier drift.json — la config JSON était une API d'une version antérieure.
    # Le plugin ajoute le flag --mutate à Pest pour le mutation testing.

    log_info "💡 Pour utiliser Drift (mutation testing): vendor/bin/pest --mutate"
    log_info "💡 Pour cibler un fichier spécifique:       vendor/bin/pest --mutate --path=app/Models"
    log_success "✅ Pest Plugin Drift v4 prêt (aucun fichier de configuration requis)"
}

ensure_test_directories() {
    local test_dirs=("tests/Feature" "tests/Unit")

    for dir in "${test_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            log_info "📁 Création du répertoire $dir..."
            mkdir -p "$dir"
        fi
    done
}

create_example_tests() {
    # Test Feature exemple
    cat > tests/Feature/ExampleTest.php << 'EOF'
<?php

use Illuminate\Foundation\Testing\RefreshDatabase;

uses(RefreshDatabase::class);

test('the application returns a successful response', function () {
    $response = $this->get('/');

    $response->assertStatus(200);
});

test('basic example with drift coverage', function () {
    expect(true)->toBeTrue();
});
EOF

    # Test Unit exemple
    if [ ! -f "tests/Unit/ExampleTest.php" ]; then
        cat > tests/Unit/ExampleTest.php << 'EOF'
<?php

test('that true is true', function () {
    expect(true)->toBeTrue();
});

test('basic math operations', function () {
    expect(1 + 1)->toBe(2);
    expect(5 * 2)->toBe(10);
});
EOF
    fi

    log_success "✅ Tests d'exemple créés"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
