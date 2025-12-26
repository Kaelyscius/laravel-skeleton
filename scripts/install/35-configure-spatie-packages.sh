#!/bin/bash

# =============================================================================
# MODULE DE CONFIGURATION DES PACKAGES SPATIE
# =============================================================================
#
# Ce module configure les packages Spatie additionnels :
# - laravel-csp (Content Security Policy)
# - laravel-health (Health checks)
# - laravel-schedule-monitor (Monitoring cron)
#
# =============================================================================

set -e

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/laravel.sh"

init_logging "35-configure-spatie-packages"

main() {
    local laravel_dir="${1:-$(detect_working_directory)}"
    local start_time=$(date +%s)

    log_separator "CONFIGURATION PACKAGES SPATIE"
    log_info "🔧 Configuration des packages Spatie dans: $laravel_dir"

    cd "$laravel_dir"

    if ! is_laravel_project "$laravel_dir"; then
        log_fatal "Pas un projet Laravel: $laravel_dir"
    fi

    # Configuration de chaque package s'il est installé
    configure_laravel_csp
    configure_laravel_health
    configure_laravel_schedule_monitor

    local duration=$(calculate_duration $start_time)
    log_success "✅ Configuration des packages Spatie terminée en $duration"
}

configure_laravel_csp() {
    if ! is_package_installed "spatie/laravel-csp"; then
        log_debug "✓ spatie/laravel-csp non installé - ignoré"
        return 0
    fi

    log_info "🔒 Configuration de Laravel CSP..."

    # Publier la configuration
    if [ ! -f "config/csp.php" ]; then
        log_info "Publication de la configuration CSP..."
        php artisan vendor:publish --tag=csp-config 2>&1 | tee -a "$LOG_FILE" || {
            log_warn "⚠️ Impossible de publier la config CSP"
            return 1
        }
    fi

    # Ajouter le middleware dans app/Http/Kernel.php si nécessaire
    if [ -f "app/Http/Kernel.php" ]; then
        if ! grep -q "AddCspHeaders" app/Http/Kernel.php; then
            log_info "⚡ Configuration du middleware CSP..."
            log_info "💡 Ajoutez manuellement le middleware \\Spatie\\Csp\\AddCspHeaders::class dans app/Http/Kernel.php"
        fi
    fi

    log_success "✅ Laravel CSP configuré"
}

configure_laravel_health() {
    if ! is_package_installed "spatie/laravel-health"; then
        log_debug "✓ spatie/laravel-health non installé - ignoré"
        return 0
    fi

    log_info "🏥 Configuration de Laravel Health..."

    # Publier la configuration et les migrations
    if [ ! -f "config/health.php" ]; then
        log_info "Publication de la configuration Health..."
        php artisan vendor:publish --tag=health-config 2>&1 | tee -a "$LOG_FILE" || {
            log_warn "⚠️ Impossible de publier la config Health"
            return 1
        }
    fi

    # Publier les migrations
    log_info "Publication des migrations Health..."
    php artisan vendor:publish --tag=health-migrations 2>&1 | tee -a "$LOG_FILE" || log_debug "Migrations Health déjà publiées"

    # Créer un health check de base
    if [ ! -f "app/HealthChecks/DatabaseHealthCheck.php" ]; then
        log_info "📝 Création d'exemples de health checks..."
        mkdir -p app/HealthChecks

        cat > app/HealthChecks/DatabaseHealthCheck.php << 'EOF'
<?php

namespace App\HealthChecks;

use Illuminate\Support\Facades\DB;
use Spatie\Health\Checks\Check;
use Spatie\Health\Checks\Result;

class DatabaseHealthCheck extends Check
{
    public function run(): Result
    {
        try {
            DB::connection()->getPdo();

            return Result::make()->ok();
        } catch (\Exception $e) {
            return Result::make()
                ->failed('Database connection failed: ' . $e->getMessage());
        }
    }
}
EOF
        log_success "✅ Health check Database créé"
    fi

    log_info "💡 Route health check disponible sur: /health"
    log_success "✅ Laravel Health configuré"
}

configure_laravel_schedule_monitor() {
    if ! is_package_installed "spatie/laravel-schedule-monitor"; then
        log_debug "✓ spatie/laravel-schedule-monitor non installé - ignoré"
        return 0
    fi

    log_info "⏰ Configuration de Laravel Schedule Monitor..."

    # Publier la configuration et les migrations
    if [ ! -f "config/schedule-monitor.php" ]; then
        log_info "Publication de la configuration Schedule Monitor..."
        php artisan vendor:publish --tag=schedule-monitor-config 2>&1 | tee -a "$LOG_FILE" || {
            log_warn "⚠️ Impossible de publier la config Schedule Monitor"
            return 1
        }
    fi

    # Publier les migrations
    log_info "Publication des migrations Schedule Monitor..."
    php artisan vendor:publish --tag=schedule-monitor-migrations 2>&1 | tee -a "$LOG_FILE" || log_debug "Migrations Schedule Monitor déjà publiées"

    # Créer un exemple de scheduled task si app/Console/Kernel.php existe
    if [ -f "app/Console/Kernel.php" ]; then
        log_info "💡 Exemple de configuration dans app/Console/Kernel.php:"
        log_info "   \$schedule->command('inspire')->hourly()->monitorName('inspire-command');"
    fi

    log_info "💡 Pour synchroniser les moniteurs: php artisan schedule-monitor:sync"
    log_success "✅ Laravel Schedule Monitor configuré"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
