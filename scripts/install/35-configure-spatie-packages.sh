#!/bin/bash

# =============================================================================
# MODULE DE CONFIGURATION DES PACKAGES SPATIE + LARAVEL PULSE
# =============================================================================
#
# Ce module configure les packages additionnels :
# - laravel-csp (Content Security Policy)
# - laravel-health (Health checks)
# - laravel-schedule-monitor (Monitoring cron)
# - laravel/pulse (Monitoring temps réel)
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
    configure_laravel_pulse

    local duration=$(calculate_duration $start_time)
    log_success "✅ Configuration des packages terminée en $duration"
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

    # Laravel 12 : enregistrement du middleware dans bootstrap/app.php (plus de Kernel.php)
    if [ -f "bootstrap/app.php" ]; then
        if ! grep -q "AddCspHeaders" bootstrap/app.php; then
            log_info "⚡ Enregistrement du middleware CSP dans bootstrap/app.php..."
            sed -i "s/->withMiddleware(function (Middleware \$middleware) {/->withMiddleware(function (Middleware \$middleware) {\n        \$middleware->append(\\\\Spatie\\\\Csp\\\\AddCspHeaders::class);/" bootstrap/app.php
            log_success "✅ Middleware CSP enregistré dans bootstrap/app.php"
        else
            log_debug "✓ Middleware CSP déjà enregistré"
        fi
    else
        log_warn "⚠️ bootstrap/app.php non trouvé - enregistrez manuellement \\\\Spatie\\\\Csp\\\\AddCspHeaders::class"
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

    log_info "💡 Exemple dans routes/console.php (Laravel 12) :"
    log_info "   Schedule::command('inspire')->hourly()->monitorName('inspire-command');"
    log_info "💡 Pour synchroniser les moniteurs: php artisan schedule-monitor:sync"
    log_success "✅ Laravel Schedule Monitor configuré"
}

configure_laravel_pulse() {
    if ! is_package_installed "laravel/pulse"; then
        log_debug "✓ laravel/pulse non installé - ignoré"
        return 0
    fi

    log_info "📊 Configuration de Laravel Pulse..."

    # Publier la configuration et les migrations
    log_info "Publication des assets Pulse..."
    php artisan vendor:publish --provider="Laravel\\Pulse\\PulseServiceProvider" 2>&1 | tee -a "$LOG_FILE" \
        || log_debug "Assets Pulse déjà publiés"

    # Exécuter les migrations Pulse
    log_info "Migration des tables Pulse..."
    php artisan migrate --force 2>&1 | tee -a "$LOG_FILE" || log_warn "⚠️ Migrations Pulse non exécutées"

    log_info "💡 Dashboard Pulse disponible sur: /pulse (restreint aux admins en prod)"
    log_info "💡 Configurez les enregistreurs dans config/pulse.php"
    log_success "✅ Laravel Pulse configuré"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
