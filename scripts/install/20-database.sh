#!/bin/bash

# =============================================================================
# MODULE DE CONFIGURATION DE LA BASE DE DONNÉES
# =============================================================================
#
# Ce module s'occupe de la configuration de la base de données Laravel :
# attente de la disponibilité, migrations de base, gestion des conflits,
# et création des tables système.
#
# Utilisation:
#   ./20-database.sh [répertoire_laravel]
#
# Code de sortie:
#   0: Configuration réussie
#   1: Échec de la configuration
#
# =============================================================================

set -e

# Charger les dépendances
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/laravel.sh"
source "$SCRIPT_DIR/../lib/docker.sh"

# Initialiser le logging
init_logging "20-database"

# =============================================================================
# VARIABLES DE CONFIGURATION
# =============================================================================

# Tables système Laravel à créer si nécessaire
readonly LARAVEL_SYSTEM_TABLES=(
    "sessions:session:table"
    "cache:cache:table"
    "jobs:queue:table"
    "failed_jobs:queue:failed-table"
)

# Timeout pour l'attente de la base de données
readonly DB_WAIT_TIMEOUT=60

# =============================================================================
# FONCTIONS DE GESTION DE LA BASE DE DONNÉES
# =============================================================================

#
# Attendre et vérifier la disponibilité de la base de données
#
setup_database_connection() {
    log_step_start "CONNEXION BASE DE DONNÉES" "Vérification et attente de la disponibilité"
    
    local start_time=$(date +%s)
    
    # Lire les paramètres de connexion depuis .env
    local db_host=$(grep "^DB_HOST=" .env 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "localhost")
    local db_port=$(grep "^DB_PORT=" .env 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "3306")
    local db_database=$(grep "^DB_DATABASE=" .env 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "laravel")
    local db_username=$(grep "^DB_USERNAME=" .env 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "root")
    
    log_info "🔗 Paramètres de connexion:"
    log_info "   • Host: $db_host:$db_port"
    log_info "   • Database: $db_database"
    log_info "   • Username: $db_username"
    
    # Attendre que la base de données soit disponible
    if ! wait_for_database $DB_WAIT_TIMEOUT; then
        log_fatal "Base de données non disponible après $DB_WAIT_TIMEOUT secondes"
    fi
    
    # Tester la connexion Laravel
    if test_laravel_database_connection; then
        log_success "✅ Connexion Laravel à la base de données vérifiée"
    else
        log_fatal "Connexion Laravel à la base de données échouée"
    fi
    
    local duration=$(calculate_duration $start_time)
    log_step_end "CONNEXION BASE DE DONNÉES" "$duration"
}

#
# Tester la connexion à la base de données via Laravel
#
test_laravel_database_connection() {
    log_debug "Test de la connexion Laravel à la base de données..."
    
    # Utiliser artisan tinker pour tester la connexion
    local test_result=$(php artisan tinker --execute="
        try {
            DB::connection()->getPdo();
            echo 'CONNECTION_OK';
        } catch (Exception \$e) {
            echo 'CONNECTION_FAILED';
        }
    " 2>/dev/null | tail -1)
    
    case "$test_result" in
        "CONNECTION_OK")
            log_debug "Connexion Laravel OK"
            return 0
            ;;
        "CONNECTION_FAILED")
            log_error "Connexion Laravel échouée"
            return 1
            ;;
        *)
            log_error "Test de connexion indéterminé: $test_result"
            return 1
            ;;
    esac
}

# =============================================================================
# FONCTIONS DE GESTION DES MIGRATIONS
# =============================================================================

#
# Exécuter les migrations de base Laravel
#
run_base_migrations() {
    log_step_start "MIGRATIONS DE BASE" "Exécution des migrations Laravel de base"
    
    local start_time=$(date +%s)
    
    # Créer la table migrations si nécessaire
    if ! table_exists "migrations"; then
        log_info "Création de la table migrations..."
        if ! php artisan migrate:install --no-interaction 2>&1 | tee -a "$LOG_FILE"; then
            log_fatal "Impossible de créer la table migrations"
        fi
        log_success "Table migrations créée"
    else
        log_debug "Table migrations déjà existante"
    fi
    
    # Exécuter les migrations de base Laravel uniquement
    log_info "Exécution des migrations Laravel de base..."
    
    local migrate_result
    if php artisan migrate --path=database/migrations --force --no-interaction 2>&1 | tee -a "$LOG_FILE"; then
        migrate_result="success"
        log_success "Migrations de base Laravel exécutées"
    else
        migrate_result="partial"
        log_warn "Certaines migrations de base ont échoué - continuons"
    fi
    
    # Afficher le statut des migrations
    show_migration_status
    
    local duration=$(calculate_duration $start_time)
    log_step_end "MIGRATIONS DE BASE" "$duration"
    
    [ "$migrate_result" = "success" ]
}

#
# Créer les tables système Laravel
#
create_system_tables() {
    log_step_start "TABLES SYSTÈME" "Création des tables système Laravel"
    
    local start_time=$(date +%s)
    local created_count=0
    
    for table_info in "${LARAVEL_SYSTEM_TABLES[@]}"; do
        local table_name="${table_info%%:*}"
        local artisan_command="${table_info#*:}"
        
        if ! table_exists "$table_name"; then
            log_info "Création de la table $table_name..."
            
            if php artisan $artisan_command --force --no-interaction 2>&1 | tee -a "$LOG_FILE"; then
                log_success "✅ Table $table_name créée"
                created_count=$((created_count + 1))
            else
                log_warn "⚠️ Échec de la création de la table $table_name"
            fi
        else
            log_debug "✓ Table $table_name déjà existante"
        fi
    done
    
    if [ $created_count -gt 0 ]; then
        log_info "$created_count table(s) système créée(s)"
    else
        log_info "Toutes les tables système existent déjà"
    fi
    
    local duration=$(calculate_duration $start_time)
    log_step_end "TABLES SYSTÈME" "$duration"
}

#
# Prévenir les conflits de migration (FONCTION COMPLÈTE DE L'ORIGINAL)
#
prevent_migration_conflicts() {
    log_info "🛡️ Prévention des conflits de migrations..."
    
    local start_time=$(date +%s)
    local conflicts_resolved=0
    
    # Tables à vérifier avec leurs migrations correspondantes (LOGIQUE ORIGINALE)
    local conflicts=(
        "telescope_entries:2018_08_08_100000_create_telescope_entries_table"
        "telescope_entries_tags:2018_08_08_100001_create_telescope_entries_tags_table"
        "telescope_monitoring:2018_08_08_100002_create_telescope_monitoring_table"
        "personal_access_tokens:2019_12_14_000001_create_personal_access_tokens_table"
        "password_resets:2014_10_12_100000_create_password_resets_table"
        "failed_jobs:2019_08_19_000000_create_failed_jobs_table"
        "cache:2024_01_01_000000_create_cache_table"
    )
    
    log_info "Vérification des conflits de migration..."
    
    for conflict in "${conflicts[@]}"; do
        local table_name=$(echo $conflict | cut -d':' -f1)
        local migration_pattern=$(echo $conflict | cut -d':' -f2)
        
        if table_exists "$table_name"; then
            log_warn "Table $table_name existe déjà - prévention du conflit"
            
            # Marquer toutes les migrations correspondantes comme exécutées
            if [[ "$migration_pattern" == *"*"* ]]; then
                # Gérer les patterns avec wildcard pour Sanctum
                local pattern_prefix=$(echo $migration_pattern | sed 's/\*.*$//')
                for migration_file in database/migrations/${pattern_prefix}*.php; do
                    if [ -f "$migration_file" ]; then
                        if mark_migration_as_executed "$migration_file"; then
                            log_success "✅ Migration marquée: $(basename $migration_file)"
                            conflicts_resolved=$((conflicts_resolved + 1))
                        fi
                    fi
                done
            else
                # Migration exacte
                local migration_file="database/migrations/${migration_pattern}.php"
                if [ -f "$migration_file" ]; then
                    if mark_migration_as_executed "$migration_file"; then
                        log_success "✅ Migration marquée: ${migration_pattern}.php"
                        conflicts_resolved=$((conflicts_resolved + 1))
                    fi
                else
                    # Essayer de trouver la migration avec un pattern plus flexible
                    local found_migration=$(find database/migrations -name "*${migration_pattern#*_}*.php" | head -1)
                    if [ -n "$found_migration" ] && [ -f "$found_migration" ]; then
                        if mark_migration_as_executed "$found_migration"; then
                            log_success "✅ Migration trouvée et marquée: $(basename $found_migration)"
                            conflicts_resolved=$((conflicts_resolved + 1))
                        fi
                    else
                        log_debug "Migration non trouvée: $migration_pattern"
                    fi
                fi
            fi
        else
            log_debug "Table $table_name n'existe pas - migration autorisée"
        fi
    done
    
    if [ $conflicts_resolved -gt 0 ]; then
        log_success "$conflicts_resolved conflit(s) de migration résolu(s)"
    else
        log_info "Aucun conflit de migration détecté"
    fi
    
    local duration=$(calculate_duration $start_time)
    log_debug "Prévention des conflits terminée en $duration"
}

#
# Exécuter les migrations finales (packages)
#
run_final_migrations() {
    log_step_start "MIGRATIONS FINALES" "Exécution des migrations de packages"
    
    local start_time=$(date +%s)
    
    # Prévenir les conflits avant migration
    prevent_migration_conflicts
    
    # Exécuter toutes les migrations restantes
    log_info "Exécution des migrations de packages..."
    
    local migrate_result="success"
    if php artisan migrate --force --no-interaction 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Migrations de packages exécutées avec succès"
    else
        log_warn "Certaines migrations de packages ont échoué"
        migrate_result="partial"
        
        # Tentative de résolution des conflits restants
        log_info "Résolution des conflits restants..."
        prevent_migration_conflicts
        
        # Nouvelle tentative
        php artisan migrate --force --no-interaction 2>/dev/null || {
            log_warn "Migrations partiellement réussies"
        }
    fi
    
    # Afficher le statut final des migrations
    show_migration_status
    
    local duration=$(calculate_duration $start_time)
    log_step_end "MIGRATIONS FINALES" "$duration"
    
    [ "$migrate_result" = "success" ]
}

#
# Exécuter les seeders si disponibles
#
run_database_seeders() {
    log_step_start "SEEDERS" "Exécution des seeders de base de données"
    
    local start_time=$(date +%s)
    
    # Vérifier si des seeders existent
    if [ ! -f "database/seeders/DatabaseSeeder.php" ]; then
        log_info "Aucun seeder trouvé, étape ignorée"
        local duration=$(calculate_duration $start_time)
        log_step_end "SEEDERS" "$duration"
        return 0
    fi
    
    # Vérifier si le seeder a du contenu
    if ! grep -q "run()" database/seeders/DatabaseSeeder.php; then
        log_info "Seeder vide, étape ignorée"
        local duration=$(calculate_duration $start_time)
        log_step_end "SEEDERS" "$duration"
        return 0
    fi
    
    # Exécuter les seeders en mode développement uniquement
    local environment=$(get_current_environment)
    if [ "$environment" = "local" ] || [ "$environment" = "development" ]; then
        log_info "Exécution des seeders (environnement: $environment)..."
        
        if php artisan db:seed --force --no-interaction 2>&1 | tee -a "$LOG_FILE"; then
            log_success "Seeders exécutés avec succès"
        else
            log_warn "Échec des seeders (normal pour une nouvelle installation)"
        fi
    else
        log_info "Seeders ignorés en environnement: $environment"
    fi
    
    local duration=$(calculate_duration $start_time)
    log_step_end "SEEDERS" "$duration"
}

# =============================================================================
# FONCTIONS UTILITAIRES
# =============================================================================

#
# Afficher le statut des migrations
#
show_migration_status() {
    log_debug "Statut des migrations:"
    
    # Compter les migrations en attente
    local pending_count=$(php artisan migrate:status --no-interaction 2>/dev/null | grep -c "Pending" || echo "0")
    local ran_count=$(php artisan migrate:status --no-interaction 2>/dev/null | grep -c "Ran" || echo "0")
    
    log_info "📊 Migrations: $ran_count exécutées, $pending_count en attente"
    
    if [ "$pending_count" -gt 0 ]; then
        log_debug "Migrations en attente détectées"
        return 1
    fi
    
    return 0
}

#
# Nettoyer et optimiser la base de données
#
optimize_database() {
    log_step_start "OPTIMISATION DB" "Optimisation de la base de données"
    
    local start_time=$(date +%s)
    
    # Analyser les tables pour optimiser les performances
    log_info "Analyse et optimisation des tables..."
    
    # Commandes d'optimisation Laravel
    local optimize_commands=(
        "php artisan optimize:clear"
        "php artisan config:cache"
    )
    
    for cmd in "${optimize_commands[@]}"; do
        log_debug "Exécution: $cmd"
        if eval "$cmd" 2>/dev/null; then
            log_debug "✓ Commande réussie: $cmd"
        else
            log_debug "⚠ Commande échouée: $cmd"
        fi
    done
    
    local duration=$(calculate_duration $start_time)
    log_step_end "OPTIMISATION DB" "$duration"
}

# =============================================================================
# FONCTION PRINCIPALE
# =============================================================================

main() {
    local laravel_dir="${1:-$(detect_working_directory)}"
    local start_time=$(date +%s)
    
    log_separator "CONFIGURATION BASE DE DONNÉES"
    log_info "🗄️ Configuration de la base de données Laravel dans: $laravel_dir"
    
    # Aller dans le répertoire Laravel
    if [ ! -d "$laravel_dir" ]; then
        log_fatal "Répertoire Laravel non trouvé: $laravel_dir"
    fi
    
    cd "$laravel_dir"
    
    # Vérifier que nous sommes bien dans un projet Laravel
    if ! is_laravel_project "$laravel_dir"; then
        log_fatal "Répertoire non valide - pas un projet Laravel: $laravel_dir"
    fi
    
    # Configuration étape par étape
    local has_errors=false
    
    # 1. Configuration de la connexion
    if ! setup_database_connection; then
        has_errors=true
    fi
    
    # 2. Migrations de base
    if ! run_base_migrations; then
        log_warn "Problème avec les migrations de base, continuons..."
    fi
    
    # 3. Tables système
    if ! create_system_tables; then
        log_warn "Problème avec les tables système, continuons..."
    fi
    
    # 4. Migrations finales
    if ! run_final_migrations; then
        log_warn "Problème avec les migrations finales, continuons..."
    fi
    
    # 5. Seeders
    run_database_seeders || true  # Non bloquant
    
    # 6. Optimisation
    optimize_database || true  # Non bloquant
    
    # Résultat final
    local duration=$(calculate_duration $start_time)
    
    if [ "$has_errors" = true ]; then
        log_error "❌ Configuration base de données terminée avec des erreurs en $duration"
        return 1
    else
        log_separator "CONFIGURATION TERMINÉE"
        log_success "✅ Base de données configurée avec succès en $duration"
        
        # Afficher les informations finales
        show_migration_status || true
        
        log_info "🎯 Prochaines étapes:"
        log_info "   • Installation des packages de production"
        log_info "   • Configuration des outils de développement"
        
        return 0
    fi
}

# =============================================================================
# EXÉCUTION
# =============================================================================

# Exécuter seulement si le script est appelé directement
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi