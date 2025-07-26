#!/bin/bash

# =============================================================================
# UTILITAIRES LARAVEL POUR L'INSTALLATION
# =============================================================================
#
# Ce module fournit des utilitaires spécialisés pour Laravel : gestion des
# packages, migrations, configurations spécifiques, optimisations, etc.
#
# Utilisation:
#   source "$(dirname "$0")/lib/laravel.sh"
#
# =============================================================================

# Configuration Laravel par défaut
readonly LARAVEL_MIN_VERSION="11.0"
readonly LARAVEL_DEFAULT_VERSION="11.*"
readonly LARAVEL_TIMEZONE_DEFAULT="UTC"
readonly LARAVEL_LOCALE_DEFAULT="en"

# Répertoires Laravel critiques
readonly LARAVEL_STORAGE_DIRS=(
    "storage/app"
    "storage/framework"
    "storage/framework/cache"
    "storage/framework/sessions"
    "storage/framework/views"
    "storage/logs"
    "bootstrap/cache"
)

# =============================================================================
# FONCTIONS DE DÉTECTION ET VÉRIFICATION LARAVEL
# =============================================================================

#
# Vérifier si nous sommes dans un projet Laravel
#
is_laravel_project() {
    local target_dir="${1:-$(pwd)}"
    
    # Vérifier les fichiers essentiels de Laravel (compatible Laravel 11+)
    local required_files=(
        "$target_dir/artisan"
        "$target_dir/composer.json"
        "$target_dir/bootstrap/app.php"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            log_debug "Fichier Laravel manquant: $file"
            return 1
        fi
    done
    
    # Vérifier que composer.json contient laravel/framework
    if [ -f "$target_dir/composer.json" ]; then
        if grep -q "laravel/framework" "$target_dir/composer.json" 2>/dev/null; then
            return 0
        fi
    fi
    
    return 1
}

#
# Obtenir la version de Laravel installée
#
# Arguments:
#   $1: Répertoire Laravel (optionnel)
#
get_laravel_version() {
    local laravel_dir="${1:-$(pwd)}"
    
    if [ -f "$laravel_dir/artisan" ]; then
        # Méthode 1: Via artisan
        local version=$(cd "$laravel_dir" && php artisan --version 2>/dev/null | sed 's/Laravel Framework \([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/')
        if [ -n "$version" ] && [ "$version" != "Laravel Framework" ]; then
            echo "$version"
            return 0
        fi
    fi
    
    if [ -f "$laravel_dir/composer.json" ]; then
        # Méthode 2: Via composer.json
        local version=$(grep '"laravel/framework"' "$laravel_dir/composer.json" 2>/dev/null | sed 's/.*"\^\?\([0-9]\+\.[0-9]\+\).*/\1/' | head -1)
        if [ -n "$version" ]; then
            echo "$version"
            return 0
        fi
    fi
    
    # Méthode 3: Via composer.lock
    if [ -f "$laravel_dir/composer.lock" ]; then
        local version=$(grep -A3 '"name": "laravel/framework"' "$laravel_dir/composer.lock" 2>/dev/null | grep '"version"' | sed 's/.*"v\?\([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/' | head -1)
        if [ -n "$version" ]; then
            echo "$version"
            return 0
        fi
    fi
    
    echo "unknown"
}

#
# Vérifier si une version de Laravel est compatible
#
# Arguments:
#   $1: Version Laravel à vérifier
#   $2: Version minimale requise (défaut: LARAVEL_MIN_VERSION)
#
is_laravel_version_compatible() {
    local current_version="$1"
    local min_version="${2:-$LARAVEL_MIN_VERSION}"
    
    if [ "$current_version" = "unknown" ]; then
        log_warn "Version Laravel inconnue, impossible de vérifier la compatibilité"
        return 1
    fi
    
    # Utiliser la fonction version_compare du module common.sh
    if version_compare "$current_version" "$min_version"; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# FONCTIONS DE CONFIGURATION LARAVEL
# =============================================================================

#
# Configurer les variables d'environnement Laravel
#
# Arguments:
#   $1: Répertoire Laravel
#   $2: Environnement (local, production, etc.)
#
configure_laravel_environment() {
    local laravel_dir="$1"
    local environment="${2:-local}"
    
    log_debug "Configuration de l'environnement Laravel: $environment"
    
    if [ ! -f "$laravel_dir/.env" ]; then
        log_warn "Fichier .env non trouvé, utilisation de .env.example"
        if [ -f "$laravel_dir/.env.example" ]; then
            cp "$laravel_dir/.env.example" "$laravel_dir/.env"
        else
            log_error "Aucun fichier .env ou .env.example trouvé"
            return 1
        fi
    fi
    
    # Configuration selon l'environnement
    case "$environment" in
        "local"|"development")
            configure_laravel_development_env "$laravel_dir"
            ;;
        "staging")
            configure_laravel_staging_env "$laravel_dir"
            ;;
        "production")
            configure_laravel_production_env "$laravel_dir"
            ;;
        *)
            log_warn "Environnement inconnu: $environment, utilisation de la configuration par défaut"
            ;;
    esac
}

#
# Configuration pour l'environnement de développement
#
configure_laravel_development_env() {
    local laravel_dir="$1"
    local env_file="$laravel_dir/.env"
    
    log_debug "Configuration pour l'environnement de développement"
    
    # Variables de développement
    local dev_vars=(
        "APP_ENV=local"
        "APP_DEBUG=true"
        "LOG_LEVEL=debug"
        "LOG_CHANNEL=stack"
    )
    
    for var in "${dev_vars[@]}"; do
        local key="${var%%=*}"
        local value="${var#*=}"
        
        if grep -q "^$key=" "$env_file"; then
            sed -i "s/^$key=.*/$var/" "$env_file"
        else
            echo "$var" >> "$env_file"
        fi
        log_debug "Variable configurée: $var"
    done
}

#
# Configuration pour l'environnement de staging
#
configure_laravel_staging_env() {
    local laravel_dir="$1"
    local env_file="$laravel_dir/.env"
    
    log_debug "Configuration pour l'environnement de staging"
    
    local staging_vars=(
        "APP_ENV=staging"
        "APP_DEBUG=false"
        "LOG_LEVEL=info"
        "LOG_CHANNEL=daily"
    )
    
    for var in "${staging_vars[@]}"; do
        local key="${var%%=*}"
        local value="${var#*=}"
        
        if grep -q "^$key=" "$env_file"; then
            sed -i "s/^$key=.*/$var/" "$env_file"
        else
            echo "$var" >> "$env_file"
        fi
        log_debug "Variable configurée: $var"
    done
}

#
# Configuration pour l'environnement de production
#
configure_laravel_production_env() {
    local laravel_dir="$1"
    local env_file="$laravel_dir/.env"
    
    log_debug "Configuration pour l'environnement de production"
    
    local prod_vars=(
        "APP_ENV=production"
        "APP_DEBUG=false"
        "LOG_LEVEL=error"
        "LOG_CHANNEL=daily"
    )
    
    for var in "${prod_vars[@]}"; do
        local key="${var%%=*}"
        local value="${var#*=}"
        
        if grep -q "^$key=" "$env_file"; then
            sed -i "s/^$key=.*/$var/" "$env_file"
        else
            echo "$var" >> "$env_file"
        fi
        log_debug "Variable configurée: $var"
    done
}

# =============================================================================
# FONCTIONS DE GESTION DES PACKAGES
# =============================================================================

#
# Vérifier si un package est installé (FONCTION AMÉLIORÉE DE L'ORIGINAL)
#
# Arguments:
#   $1: Nom du package
#
is_package_installed() {
    local package=$1
    # Nettoyer le nom du package (enlever les contraintes de version)
    local clean_package=$(echo $package | cut -d':' -f1)

    # Vérifier dans composer.json
    if [ -f "composer.json" ] && grep -q "\"$clean_package\"" composer.json; then
        log_debug "Package $clean_package trouvé dans composer.json"

        # Vérifier dans vendor/
        local vendor_path="vendor/$(echo $clean_package | tr '/' '/')"
        if [ -d "$vendor_path" ]; then
            log_debug "Package $clean_package trouvé dans vendor/"
            return 0
        fi

        # Vérifier avec composer show (plus fiable)
        if composer show "$clean_package" >/dev/null 2>&1; then
            log_debug "Package $clean_package confirmé par composer show"
            return 0
        fi
    fi

    return 1
}

#
# Vérifier la compatibilité d'un package (FONCTION DE L'ORIGINAL)
#
# Arguments:
#   $1: Nom du package
#   $2: Version Laravel
#   $3: Version PHP
#
check_package_compatibility() {
    local package=$1
    local laravel_version=$2
    local php_version=$3

    # Vérifications spécifiques pour Laravel 12+
    if [ "$laravel_version" -ge 12 ]; then
        case $package in
            "enlightn/enlightn")
                log_debug "Enlightn non compatible avec Laravel 12+ - ignoré"
                return 1
                ;;
            "pestphp/pest")
                # Compatible avec PHPUnit 11.5+
                return 0
                ;;
            "pestphp/pest-plugin-laravel")
                return 0
                ;;
        esac
    fi

    # Vérifications pour Laravel 11 et antérieur
    if [ "$laravel_version" -le 11 ]; then
        case $package in
            "enlightn/enlightn")
                # Compatible avec Laravel 10 et 11
                return 0
                ;;
        esac
    fi

    return 0  # Compatible par défaut
}

#
# Installer un package avec gestion spéciale Pest et compatibilité (EXACTE DE L'ORIGINAL)
#
# Arguments:
#   $1: Nom du package
#   $2: Type (require|require-dev, défaut: require)
#
install_package() {
    local package=$1
    local type=${2:-"require"}
    local max_attempts=3
    local attempt=1
    local laravel_version=$(get_laravel_version | cut -d. -f1)
    local php_version=$(get_php_version | cut -d. -f1-2)

    # Nettoyer le nom du package pour la vérification
    local clean_package=$(echo $package | cut -d':' -f1)

    log_info "📦 Installation de $clean_package (type: $type)"

    # Vérifier si le package est déjà installé
    if is_package_installed "$clean_package"; then
        log_success "$clean_package déjà installé"
        return 0
    fi

    # Gestion spéciale pour Pest
    if [[ "$package" == *"pest"* ]]; then
        log_info "Installation spéciale pour Pest avec dernière version compatible..."

        # Nettoyer le cache avant l'installation de Pest
        composer clear-cache 2>/dev/null || true

        # Installer avec des options spéciales pour Pest
        local composer_cmd="COMPOSER_MEMORY_LIMIT=-1 composer require --dev \"$package\" --no-interaction --with-all-dependencies"

        log_debug "Commande Pest: $composer_cmd"

        if eval $composer_cmd 2>&1 | tee -a "$LOG_FILE"; then
            log_success "$package installé avec succès"
            composer dump-autoload --no-interaction 2>/dev/null || true
            return 0
        else
            log_error "Impossible d'installer $package - conflit de versions détecté"
            echo "$package" >> .incompatible_packages.txt
            return 2
        fi
    fi

    # Vérifier la compatibilité avant l'installation (pour les autres packages)
    if ! check_package_compatibility "$clean_package" "$laravel_version" "$php_version"; then
        log_warn "Package $clean_package non compatible avec Laravel $laravel_version et PHP $php_version"
        log_info "Ajout à la liste d'attente pour future compatibilité"
        echo "$clean_package" >> .incompatible_packages.txt
        return 2  # Code spécial pour incompatibilité
    fi

    while [ $attempt -le $max_attempts ]; do
        log_debug "Installation de $clean_package (tentative $attempt/$max_attempts)..."

        # Nettoyer le cache avant l'installation
        log_debug "Nettoyage du cache Composer..."
        composer clear-cache 2>/dev/null || true

        # Construire la commande Composer avec gestion des contraintes
        local composer_cmd
        if [ "$type" = "require-dev" ]; then
            composer_cmd="COMPOSER_MEMORY_LIMIT=-1 composer require --dev \"$package\" --no-interaction --with-all-dependencies"
        else
            composer_cmd="COMPOSER_MEMORY_LIMIT=-1 composer require \"$package\" --no-interaction --with-all-dependencies"
        fi

        log_debug "Commande: $composer_cmd"

        # Exécuter la commande avec capture des erreurs
        if eval $composer_cmd 2>&1 | tee -a "$LOG_FILE"; then
            # Vérifier que le package est maintenant vraiment installé
            if is_package_installed "$clean_package"; then
                log_success "$clean_package installé avec succès"

                # Régénérer l'autoloader après installation
                composer dump-autoload --no-interaction 2>/dev/null || true

                return 0
            else
                log_warn "$clean_package semble installé mais non détecté"
            fi
        else
            local exit_code=$?
            log_error "Échec de l'installation de $clean_package (code: $exit_code)"

            # Vérifier si c'est un problème de compatibilité
            if grep -q "conflicts with\|does not satisfy" "$LOG_FILE"; then
                log_warn "Conflit de dépendances détecté pour $clean_package"
                echo "$clean_package" >> .incompatible_packages.txt
                return 2
            fi
        fi

        if [ $attempt -lt $max_attempts ]; then
            log_warn "Nouvelle tentative dans 5 secondes..."
            sleep 5
            attempt=$((attempt + 1))
        else
            log_error "Impossible d'installer $clean_package après $max_attempts tentatives"

            if [ "${DEBUG:-false}" = "true" ]; then
                log_debug "Diagnostic de l'échec:"
                composer diagnose 2>&1 | tail -20 | tee -a "$LOG_FILE" || true
            fi

            return 1
        fi
    done
}

#
# Alias pour compatibilité avec les anciens scripts
#
install_composer_package() {
    local package_name="$1"
    local version="${2:-}"
    local install_type="${3:-require}"
    
    # Convertir au format attendu par install_package
    local package_spec="$package_name"
    if [ -n "$version" ]; then
        package_spec="$package_name:$version"
    fi
    
    install_package "$package_spec" "$install_type"
}

#
# Publier les assets d'un package Laravel
#
# Arguments:
#   $1: Nom du provider ou tag
#   $2: Force la publication (true/false, défaut: false)
#
publish_package_assets() {
    local provider_or_tag="$1"
    local force="${2:-false}"
    
    if [ -z "$provider_or_tag" ]; then
        log_error "Provider ou tag requis"
        return 1
    fi
    
    local publish_cmd="php artisan vendor:publish --provider=\"$provider_or_tag\""
    
    if [ "$force" = "true" ]; then
        publish_cmd="$publish_cmd --force"
    fi
    
    log_debug "Publication des assets: $provider_or_tag"
    
    if eval "$publish_cmd" 2>&1 | tee -a "$LOG_FILE"; then
        log_debug "Assets publiés pour: $provider_or_tag"
        return 0
    else
        log_warn "Échec de la publication des assets pour: $provider_or_tag"
        return 1
    fi
}

# =============================================================================
# FONCTIONS DE GESTION DES MIGRATIONS
# =============================================================================

#
# Exécuter les migrations Laravel
#
# Arguments:
#   $1: Options supplémentaires (optionnel)
#
run_laravel_migrations() {
    local options="${1:-}"
    
    log_info "Exécution des migrations Laravel..."
    
    # Vérifier que nous sommes dans un projet Laravel
    if ! is_laravel_project; then
        log_error "Pas dans un projet Laravel"
        return 1
    fi
    
    # Attendre que la base de données soit disponible
    if ! wait_for_database 30; then
        log_error "Base de données non disponible pour les migrations"
        return 1
    fi
    
    local migrate_cmd="php artisan migrate --force"
    if [ -n "$options" ]; then
        migrate_cmd="$migrate_cmd $options"
    fi
    
    log_debug "Commande de migration: $migrate_cmd"
    
    if eval "$migrate_cmd" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Migrations exécutées avec succès"
        return 0
    else
        log_error "Échec des migrations"
        return 1
    fi
}

#
# Marquer une migration comme exécutée sans la lancer
#
# Arguments:
#   $1: Nom du fichier de migration
#
mark_migration_as_executed() {
    local migration_file="$1"
    
    if [ -z "$migration_file" ]; then
        log_error "Nom de fichier de migration requis"
        return 1
    fi
    
    log_debug "Marquage de la migration comme exécutée: $migration_file"
    
    # Extraire le nom de la migration (sans l'extension)
    local migration_name=$(basename "$migration_file" .php)
    
    # Utiliser tinker pour insérer la migration dans la table migrations
    local tinker_cmd="php artisan tinker --execute=\"
        try {
            if (!Schema::hasTable('migrations')) {
                echo 'TABLE_MIGRATIONS_NOT_EXISTS';
                exit;
            }
            \\\$exists = DB::table('migrations')->where('migration', '$migration_name')->exists();
            if (!\\\$exists) {
                DB::table('migrations')->insert([
                    'migration' => '$migration_name',
                    'batch' => DB::table('migrations')->max('batch') + 1
                ]);
                echo 'MIGRATION_MARKED';
            } else {
                echo 'MIGRATION_ALREADY_EXISTS';
            }
        } catch (Exception \\\$e) {
            echo 'ERROR_MARKING_MIGRATION';
        }
    \""
    
    local result=$(eval "$tinker_cmd" 2>/dev/null | tail -1)
    
    case "$result" in
        "MIGRATION_MARKED")
            log_debug "Migration marquée comme exécutée: $migration_name"
            return 0
            ;;
        "MIGRATION_ALREADY_EXISTS")
            log_debug "Migration déjà marquée: $migration_name"
            return 0
            ;;
        "TABLE_MIGRATIONS_NOT_EXISTS")
            log_warn "Table migrations n'existe pas encore"
            return 1
            ;;
        *)
            log_error "Erreur lors du marquage de la migration: $migration_name"
            return 1
            ;;
    esac
}

# =============================================================================
# FONCTIONS D'OPTIMISATION LARAVEL
# =============================================================================

#
# Optimiser Laravel pour l'environnement de développement
#
optimize_laravel_for_development() {
    local laravel_dir="${1:-$(pwd)}"
    
    log_info "Optimisation Laravel pour le développement..."
    
    cd "$laravel_dir"
    
    # Nettoyer tous les caches
    local clear_commands=(
        "php artisan config:clear"
        "php artisan cache:clear"
        "php artisan view:clear"
        "php artisan route:clear"
    )
    
    for cmd in "${clear_commands[@]}"; do
        log_debug "Exécution: $cmd"
        eval "$cmd" 2>/dev/null || true
    done
    
    log_success "Optimisation développement terminée"
}

#
# Optimiser Laravel pour la production
#
optimize_laravel_for_production() {
    local laravel_dir="${1:-$(pwd)}"
    
    log_info "Optimisation Laravel pour la production..."
    
    cd "$laravel_dir"
    
    # Optimisations de production
    local optimize_commands=(
        "php artisan config:cache"
        "php artisan route:cache"
        "php artisan view:cache"
        "composer install --no-dev --optimize-autoloader"
        "php artisan optimize"
    )
    
    for cmd in "${optimize_commands[@]}"; do
        log_debug "Exécution: $cmd"
        if ! eval "$cmd" 2>&1 | tee -a "$LOG_FILE"; then
            log_warn "Échec de la commande d'optimisation: $cmd"
        fi
    done
    
    log_success "Optimisation production terminée"
}

#
# Configurer les permissions des répertoires Laravel
#
setup_laravel_permissions() {
    local laravel_dir="${1:-$(pwd)}"
    
    log_debug "Configuration des permissions Laravel dans: $laravel_dir"
    
    cd "$laravel_dir"
    
    # Créer les répertoires manquants
    for dir in "${LARAVEL_STORAGE_DIRS[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            log_debug "Répertoire créé: $dir"
        fi
    done
    
    # Configurer les permissions (775 pour les répertoires, 664 pour les fichiers)
    for dir in "${LARAVEL_STORAGE_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            # Permissions des répertoires
            find "$dir" -type d -exec chmod 775 {} \; 2>/dev/null || true
            # Permissions des fichiers
            find "$dir" -type f -exec chmod 664 {} \; 2>/dev/null || true
            log_debug "Permissions configurées: $dir"
        fi
    done
    
    # S'assurer qu'artisan est exécutable
    if [ -f "artisan" ]; then
        chmod +x artisan
        log_debug "Artisan rendu exécutable"
    fi
    
    log_debug "Permissions Laravel configurées"
}

# =============================================================================
# FONCTIONS DE DIAGNOSTIC LARAVEL
# =============================================================================

#
# Afficher des informations détaillées sur l'installation Laravel
#
show_laravel_info() {
    local laravel_dir="${1:-$(pwd)}"
    
    log_separator "INFORMATIONS LARAVEL"
    
    cd "$laravel_dir"
    
    # Version Laravel
    local laravel_version=$(get_laravel_version)
    log_info "🚀 Laravel: $laravel_version"
    
    # Version PHP
    local php_version=$(get_php_version)
    log_info "🐘 PHP: $php_version"
    
    # Environnement
    local env_app=$(grep "^APP_ENV=" .env 2>/dev/null | cut -d= -f2 || echo "unknown")
    local env_debug=$(grep "^APP_DEBUG=" .env 2>/dev/null | cut -d= -f2 || echo "unknown")
    log_info "🌍 Environnement: $env_app (debug: $env_debug)"
    
    # Base de données
    local db_connection=$(grep "^DB_CONNECTION=" .env 2>/dev/null | cut -d= -f2 || echo "unknown")
    local db_host=$(grep "^DB_HOST=" .env 2>/dev/null | cut -d= -f2 || echo "unknown")
    log_info "🗄️ Database: $db_connection @ $db_host"
    
    # Cache et sessions
    local cache_driver=$(grep "^CACHE_DRIVER=" .env 2>/dev/null | cut -d= -f2 || echo "file")
    local session_driver=$(grep "^SESSION_DRIVER=" .env 2>/dev/null | cut -d= -f2 || echo "file")
    log_info "💾 Cache: $cache_driver | Sessions: $session_driver"
    
    # Packages installés (principaux)
    if [ -f "composer.json" ]; then
        log_info "📦 Packages principaux:"
        grep -E '"(laravel|spatie|barryvdh|nunomaduro)' composer.json | head -5 | while read -r line; do
            local package=$(echo "$line" | sed 's/.*"\([^"]*\)".*/\1/')
            log_info "   • $package"
        done
    fi
}

#
# Vérifier l'état de santé de Laravel
#
check_laravel_health() {
    local laravel_dir="${1:-$(pwd)}"
    
    log_info "Vérification de l'état de Laravel..."
    cd "$laravel_dir"
    
    local issues=0
    
    # Vérifier artisan
    if php artisan --version &>/dev/null; then
        log_debug "✓ Artisan fonctionne"
    else
        log_error "✗ Artisan ne fonctionne pas"
        issues=$((issues + 1))
    fi
    
    # Vérifier les permissions
    for dir in "${LARAVEL_STORAGE_DIRS[@]}"; do
        if [ -w "$dir" ]; then
            log_debug "✓ $dir: écriture OK"
        else
            log_warn "✗ $dir: pas de permissions d'écriture"
            issues=$((issues + 1))
        fi
    done
    
    # Vérifier la base de données
    if wait_for_database 5; then
        log_debug "✓ Base de données accessible"
    else
        log_warn "✗ Base de données non accessible"
        issues=$((issues + 1))
    fi
    
    # Vérifier la clé d'application
    local app_key=$(grep "^APP_KEY=" .env 2>/dev/null | cut -d= -f2)
    if [ -n "$app_key" ] && [ "$app_key" != "" ]; then
        log_debug "✓ Clé d'application configurée"
    else
        log_warn "✗ Clé d'application manquante"
        issues=$((issues + 1))
    fi
    
    if [ $issues -eq 0 ]; then
        log_success "Laravel en bonne santé !"
        return 0
    else
        log_warn "Laravel a $issues problème(s)"
        return 1
    fi
}

#
# Wrapper pour artisan avec logging unifié (DEMANDÉ DANS LE PROMPT)
#
# Arguments:
#   $@: Commande artisan et ses arguments
#
artisan() {
    local cmd="$*"
    log_debug "Exécution artisan: $cmd"
    
    if php artisan "$@" 2>&1 | tee -a "$LOG_FILE"; then
        log_debug "✓ Artisan réussi: $cmd"
        return 0
    else
        log_error "✗ Artisan échoué: $cmd"
        return 1
    fi
}

#
# Wrapper pour composer avec logging unifié (DEMANDÉ DANS LE PROMPT)
#
# Arguments:
#   $@: Commande composer et ses arguments
#
composer() {
    local cmd="$*"
    log_debug "Exécution composer: $cmd"
    
    # Configurer les variables d'environnement Composer
    export COMPOSER_MEMORY_LIMIT=-1
    export COMPOSER_PROCESS_TIMEOUT=0
    export COMPOSER_ALLOW_SUPERUSER=1
    export COMPOSER_NO_INTERACTION=1
    
    if command composer "$@" 2>&1 | tee -a "$LOG_FILE"; then
        log_debug "✓ Composer réussi: $cmd"
        return 0
    else
        log_error "✗ Composer échoué: $cmd"
        return 1
    fi
}

# =============================================================================
# EXPORT DES FONCTIONS
# =============================================================================

# Rendre les fonctions disponibles pour les scripts qui sourcent ce fichier
export -f is_laravel_project get_laravel_version is_laravel_version_compatible
export -f configure_laravel_environment configure_laravel_development_env configure_laravel_staging_env configure_laravel_production_env
export -f is_package_installed check_package_compatibility install_package install_composer_package publish_package_assets
export -f run_laravel_migrations mark_migration_as_executed
export -f optimize_laravel_for_development optimize_laravel_for_production setup_laravel_permissions
export -f show_laravel_info check_laravel_health
export -f artisan composer

# Variables exportées
export LARAVEL_MIN_VERSION LARAVEL_DEFAULT_VERSION LARAVEL_TIMEZONE_DEFAULT LARAVEL_LOCALE_DEFAULT