#!/bin/bash

# =============================================================================
# MODULE DE CONFIGURATION DES OUTILS QUALITÉ
# =============================================================================
#
# Ce module configure les outils de qualité de code : PHPStan, ECS, Rector
# avec les configurations optimisées pour Laravel 12 et PHP 8.4
#
# =============================================================================

set -e

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/laravel.sh"

init_logging "50-quality-tools"

# NOTE: Les packages d'outils qualité sont maintenant lus depuis config/installer.yml
# via get_packages_from_config() (CONFORMÉMENT AU PROMPT)

create_ecs_config() {
    log_info "Création de la configuration ECS..."
    
    cat > ecs.php << 'EOF'
<?php

declare(strict_types=1);

use Symplify\EasyCodingStandard\Config\ECSConfig;
use Symplify\EasyCodingStandard\ValueObject\Set\SetList;

return function (ECSConfig $ecsConfig): void {
    $ecsConfig->paths([
        __DIR__ . '/app',
        __DIR__ . '/config',
        __DIR__ . '/database',
        __DIR__ . '/routes',
        __DIR__ . '/tests',
    ]);

    $ecsConfig->sets([
        SetList::SPACES,
        SetList::ARRAY,
        SetList::DOCBLOCK,
        SetList::NAMESPACES,
        SetList::COMMENTS,
        SetList::PSR_12,
    ]);

    $ecsConfig->skip([
        __DIR__ . '/bootstrap',
        __DIR__ . '/storage',
        __DIR__ . '/vendor',
        __DIR__ . '/node_modules',
    ]);
};
EOF

    log_success "✅ Configuration ECS créée"
}

create_phpstan_config() {
    log_info "Création de la configuration PHPStan..."
    
    cat > phpstan.neon << 'EOF'
includes:
    - vendor/larastan/larastan/extension.neon

parameters:
    level: 8
    paths:
        - app/
        - config/
        - database/
        - routes/
        - tests/

    excludePaths:
        - bootstrap/
        - storage/
        - vendor/
        - node_modules/

    treatPhpDocTypesAsCertain: false
    reportUnmatchedIgnoredErrors: false
    checkUninitializedProperties: true
    checkBenevolentUnionTypes: true
    checkExplicitMixedMissingReturn: true
    checkFunctionNameCase: true
    checkInternalClassCaseSensitivity: true
    checkTooWideReturnTypesInProtectedAndPublicMethods: true
    checkMissingCallableSignature: true
    checkPhpDocMethodSignatures: true
EOF

    log_success "✅ Configuration PHPStan créée"
}

create_rector_config() {
    log_info "Création de la configuration Rector..."
    
    # Détecter les versions pour adapter la configuration
    local laravel_version=$(get_laravel_version | cut -d. -f1)
    local php_version=$(get_php_version | cut -d. -f1-2)
    
    log_debug "Configuration Rector pour Laravel $laravel_version, PHP $php_version"
    
    # Adapter selon la version Laravel
    local rector_laravel_set="LaravelSetList::LARAVEL_110"  # Laravel 11 par défaut
    
    if [ "$laravel_version" -ge 12 ] && is_package_installed "driftingly/rector-laravel"; then
        rector_laravel_set="RectorLaravel\\Set\\LaravelSetList::LARAVEL_120"
        log_debug "Utilisation du set Laravel 12 via driftingly/rector-laravel"
    elif [ "$laravel_version" -ge 12 ]; then
        rector_laravel_set="LaravelSetList::LARAVEL_110"  # Fallback
        log_debug "Laravel 12 détecté mais driftingly/rector-laravel non installé - utilisation du set 11.0"
    fi
    
    cat > rector.php << EOF
<?php

declare(strict_types=1);

use Rector\Config\RectorConfig;
use Rector\Set\ValueObject\LevelSetList;
use Rector\Set\ValueObject\SetList;
use Rector\Laravel\Set\LaravelSetList;
use Rector\TypeDeclaration\Rector\ClassMethod\AddVoidReturnTypeWhereNoReturnRector;
use Rector\TypeDeclaration\Rector\ClassMethod\AddReturnTypeDeclarationRector;

return static function (RectorConfig \$rectorConfig): void {
    \$rectorConfig->paths([
        __DIR__ . '/app',
        __DIR__ . '/config',
        __DIR__ . '/database',
        __DIR__ . '/routes',
        __DIR__ . '/tests',
    ]);

    // Règles spécifiquement utiles pour PHPStan niveau 8+
    \$rectorConfig->rules([
        AddVoidReturnTypeWhereNoReturnRector::class,
        AddReturnTypeDeclarationRector::class,
    ]);

    // Sets optimisés pour PHPStan
    \$rectorConfig->sets([
        LevelSetList::UP_TO_PHP_84,
        $rector_laravel_set,
        LaravelSetList::LARAVEL_CODE_QUALITY,
        SetList::CODE_QUALITY,
        SetList::TYPE_DECLARATION,
        SetList::DEAD_CODE,
    ]);

    \$rectorConfig->skip([
        __DIR__ . '/bootstrap',
        __DIR__ . '/storage',
        __DIR__ . '/vendor',
        __DIR__ . '/node_modules',
        __DIR__ . '/database/migrations',
    ]);

    \$rectorConfig->importNames();
    \$rectorConfig->parallel();
    
    // Lien avec PHPStan config si elle existe
    if (file_exists(__DIR__ . '/phpstan.neon')) {
        \$rectorConfig->phpstanConfig(__DIR__ . '/phpstan.neon');
    }
};
EOF

    log_success "✅ Configuration Rector créée (adaptée Laravel $laravel_version)"
}

create_insights_config() {
    log_info "Création de la configuration PHP Insights..."
    
    mkdir -p config
    
    cat > config/insights.php << 'EOF'
<?php

declare(strict_types=1);

return [
    'preset' => 'laravel',
    'ide' => 'phpstorm',

    'exclude' => [
        'bootstrap',
        'storage',
        'vendor',
        'node_modules',
        'public/build',
        'public/hot',
    ],

    'add' => [
        // Ajoutez des métriques personnalisées ici
    ],

    'remove' => [
        // Désactiver certaines vérifications si nécessaire
        \NunoMaduro\PhpInsights\Domain\Insights\ForbiddenTraits::class,
        \SlevomatCodingStandard\Sniffs\TypeHints\DisallowMixedTypeHintSniff::class,
        \SlevomatCodingStandard\Sniffs\Classes\ForbiddenPublicPropertySniff::class,
    ],

    'config' => [
        \PHP_CodeSniffer\Standards\Generic\Sniffs\Files\LineLengthSniff::class => [
            'lineLimit' => 120,
            'absoluteLineLimit' => 160,
        ],
        \SlevomatCodingStandard\Sniffs\Functions\FunctionLengthSniff::class => [
            'maxLinesLength' => 50,
        ],
        \SlevomatCodingStandard\Sniffs\Classes\ClassLengthSniff::class => [
            'maxLinesLength' => 250,
        ],
    ],

    'requirements' => [
        'min-quality' => 80,
        'min-complexity' => 85,
        'min-architecture' => 80,
        'min-style' => 90,
        'disable-security-check' => false,
    ],

    'threads' => null,
];
EOF

    log_success "✅ Configuration PHP Insights créée"
}

main() {
    local laravel_dir="${1:-$(detect_working_directory)}"
    local start_time=$(date +%s)
    
    log_separator "CONFIGURATION OUTILS QUALITÉ"
    log_info "⚙️ Configuration des outils qualité dans: $laravel_dir"
    
    cd "$laravel_dir"
    
    if ! is_laravel_project "$laravel_dir"; then
        log_fatal "Pas un projet Laravel: $laravel_dir"
    fi
    
    # Lire les packages qualité depuis config/installer.yml (CONFORMÉMENT AU PROMPT)
    log_info "📋 Lecture des packages d'outils qualité depuis config/installer.yml..."
    
    # Liste des packages qualité attendus
    local quality_tools=("nunomaduro/larastan" "symplify/easy-coding-standard" "rector/rector" "nunomaduro/phpinsights")
    
    # Obtenir la liste de tous les packages de développement depuis le YAML
    local all_dev_packages
    if ! all_dev_packages=$(get_packages_from_config "development"); then
        log_error "Impossible de lire les packages de développement depuis la configuration"
        return 1
    fi
    
    # Installer les packages qualité trouvés dans la configuration
    for quality_tool in "${quality_tools[@]}"; do
        # Vérifier si ce package est dans la configuration
        if echo "$all_dev_packages" | grep -q "^$quality_tool$"; then
            # Obtenir la version depuis la configuration
            local version=$(get_package_version "$quality_tool" "development")
            
            if ! is_package_installed "$quality_tool"; then
                log_info "Installation de $quality_tool:$version..."
                if install_composer_package "$quality_tool" "$version" "require-dev"; then
                    log_success "✅ $quality_tool installé"
                else
                    if is_package_required "$quality_tool" "development"; then
                        log_error "❌ Échec installation package qualité requis: $quality_tool"
                    else
                        log_warn "❌ Échec installation package qualité optionnel: $quality_tool"
                    fi
                fi
            else
                log_debug "✓ $quality_tool déjà installé"
            fi
        else
            log_debug "Package qualité $quality_tool non trouvé dans la configuration YAML"
        fi
    done
    
    # Créer les configurations
    create_ecs_config
    create_phpstan_config
    create_rector_config
    create_insights_config
    
    local duration=$(calculate_duration $start_time)
    log_success "✅ Outils qualité configurés en $duration"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi