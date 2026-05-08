#!/bin/bash

# =============================================================================
# MODULE D'INSTALLATION LARAVEL CORE
# =============================================================================
#
# Ce module s'occupe de l'installation et de la configuration de base de Laravel.
# Il gère la création du projet, la configuration de l'environnement,
# la génération de la clé d'application et les vérifications de base.
#
# Utilisation:
#   ./10-laravel-core.sh [répertoire_cible]
#
# Code de sortie:
#   0: Installation réussie
#   1: Échec de l'installation
#
# =============================================================================

set -e

# Charger les dépendances
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/common.sh"

# Initialiser le logging
init_logging "10-laravel-core"

# =============================================================================
# VARIABLES DE CONFIGURATION
# =============================================================================

# Version Laravel par défaut (version flexible pour auto-update vers dernière 12.x)
readonly DEFAULT_LARAVEL_VERSION="^12.0"

# Fichiers Laravel critiques pour la validation
readonly LARAVEL_CORE_FILES=(
    "artisan"
    "composer.json"
    "bootstrap/app.php"
    "config/app.php"
)

# Configuration par défaut pour Laravel
readonly DEFAULT_TIMEZONE="UTC"
readonly DEFAULT_LOCALE="en"

# =============================================================================
# FONCTIONS D'INSTALLATION LARAVEL
# =============================================================================

#
# Créer un nouveau projet Laravel
#
# Arguments:
#   $1: Répertoire cible pour l'installation
#   $2: Version Laravel (optionnel, défaut: DEFAULT_LARAVEL_VERSION)
#
create_laravel_project() {
    local target_dir="$1"
    local laravel_version="${2:-$DEFAULT_LARAVEL_VERSION}"
    
    log_step_start "CRÉATION PROJET LARAVEL" "Installation de Laravel $laravel_version dans $target_dir"
    
    local start_time=$(date +%s)
    
    # Validation des paramètres
    if [ -z "$target_dir" ]; then
        log_fatal "Répertoire cible requis"
    fi
    
    # Vérifier les permissions d'écriture (adapté pour Docker)
    if is_docker_environment; then
        log_debug "Environnement Docker détecté - validation et correction de permissions adaptée"
        
        # Dans Docker, créer et configurer les permissions appropriées
        if [ ! -d "$target_dir" ]; then
            log_debug "Création du répertoire cible: $target_dir"
            mkdir -p "$target_dir" 2>/dev/null || true
        fi
        
        # Corriger automatiquement les permissions pour Docker
        log_debug "Correction des permissions Docker pour $target_dir"
        chown -R www-data:www-data "$target_dir" 2>/dev/null || true
        chmod -R 755 "$target_dir" 2>/dev/null || true
        
        # Vérifier que les permissions sont maintenant correctes
        if [ ! -w "$target_dir" ]; then
            log_error "Permissions encore incorrectes après correction"
            log_debug "Tentative de correction en mode root"
            # En dernier recours, donner les permissions complètes
            chmod -R 777 "$target_dir" 2>/dev/null || true
            
            if [ ! -w "$target_dir" ]; then
                log_fatal "Impossible de corriger les permissions pour: $target_dir"
            fi
        fi
        
        log_debug "Permissions Docker configurées avec succès"
    else
        # Validation classique pour les environnements non-Docker
        local parent_dir="$(dirname "$target_dir")"
        if [ ! -w "$parent_dir" ]; then
            log_fatal "Pas de permission d'écriture dans $parent_dir"
        fi
        
        # Créer le répertoire s'il n'existe pas
        mkdir -p "$target_dir"
    fi
    
    # Vérifier si Laravel est déjà installé
    if is_laravel_installed "$target_dir"; then
        log_success "✅ Projet Laravel existant détecté dans $target_dir"
        local duration=$(calculate_duration $start_time)
        log_step_end "CRÉATION PROJET LARAVEL" "$duration"
        return 0
    fi
    
    # Nettoyer le répertoire si nécessaire
    if ! clean_target_directory "$target_dir"; then
        log_fatal "Impossible de nettoyer le répertoire cible"
    fi
    
    # Installer Laravel via Composer
    if ! install_laravel_via_composer "$target_dir" "$laravel_version"; then
        log_fatal "Échec de l'installation de Laravel"
    fi
    
    # Valider l'installation
    if ! validate_laravel_installation "$target_dir"; then
        log_fatal "Validation de l'installation Laravel échouée"
    fi
    
    local duration=$(calculate_duration $start_time)
    log_step_end "CRÉATION PROJET LARAVEL" "$duration"
}

#
# Configurer l'environnement Laravel
#
# Arguments:
#   $1: Répertoire Laravel
#
configure_laravel_environment() {
    local laravel_dir="$1"
    
    log_step_start "CONFIGURATION ENVIRONNEMENT" "Configuration de l'environnement Laravel"
    
    local start_time=$(date +%s)
    
    if [ ! -d "$laravel_dir" ]; then
        log_fatal "Répertoire Laravel non trouvé: $laravel_dir"
    fi
    
    cd "$laravel_dir"
    
    # Copier la configuration environnement depuis le projet parent
    if ! copy_environment_configuration; then
        log_error "Échec de la copie de configuration environnement"
        # Non fatal, on continue avec la configuration par défaut
    fi
    
    # Générer la clé d'application Laravel
    if ! generate_application_key; then
        log_fatal "Échec de la génération de la clé d'application"
    fi
    
    # Configurer les permissions des répertoires Laravel
    if ! setup_laravel_permissions; then
        log_warn "Problème avec la configuration des permissions"
    fi
    
    # Optimiser la configuration Laravel de base
    if ! optimize_laravel_configuration; then
        log_warn "Problème avec l'optimisation de la configuration"
    fi
    
    local duration=$(calculate_duration $start_time)
    log_step_end "CONFIGURATION ENVIRONNEMENT" "$duration"
}

# =============================================================================
# FONCTIONS D'INSTALLATION DÉTAILLÉES
# =============================================================================

#
# Vérifier si Laravel est déjà installé dans un répertoire
#
is_laravel_installed() {
    local target_dir="$1"
    
    # Vérifier les fichiers critiques
    for file in "${LARAVEL_CORE_FILES[@]}"; do
        if [ ! -f "$target_dir/$file" ]; then
            log_debug "Fichier Laravel manquant: $file"
            return 1
        fi
    done
    
    # Vérifier que composer.json contient laravel/framework
    if [ -f "$target_dir/composer.json" ]; then
        if grep -q "laravel/framework" "$target_dir/composer.json" 2>/dev/null; then
            log_debug "Laravel framework détecté dans composer.json"
            return 0
        fi
    fi
    
    return 1
}

#
# Nettoyer le répertoire cible avant installation
#
clean_target_directory() {
    local target_dir="$1"
    
    log_debug "Nettoyage du répertoire: $target_dir"
    
    # Afficher le contenu actuel pour diagnostic
    if [ "$(ls -A "$target_dir" 2>/dev/null | wc -l)" -gt 0 ]; then
        log_debug "Contenu actuel du répertoire:"
        ls -la "$target_dir" 2>/dev/null | head -10 || true
        
        log_info "Nettoyage complet du répertoire $target_dir..."
        
        # Supprimer tout le contenu, y compris les fichiers cachés
        find "$target_dir" -mindepth 1 -delete 2>/dev/null || {
            log_debug "Fallback: suppression avec rm -rf"
            rm -rf "$target_dir"/{*,.*} 2>/dev/null || true
        }
        
        # Vérifier que le répertoire est maintenant vide
        local remaining_files=$(ls -A "$target_dir" 2>/dev/null | wc -l)
        if [ "$remaining_files" -gt 0 ]; then
            log_warn "Fichiers restants après nettoyage: $remaining_files"
            return 1
        fi
    fi
    
    log_debug "Répertoire nettoyé avec succès"
    return 0
}

#
# Installer Laravel via Composer
#
install_laravel_via_composer() {
    local target_dir="$1"
    local laravel_version="$2"
    
    log_info "Installation de Laravel $laravel_version..."
    
    # Utiliser un répertoire temporaire pour éviter les conflits
    local temp_dir="/tmp/laravel-install-$$"
    rm -rf "$temp_dir" 2>/dev/null || true
    
    log_debug "Installation via répertoire temporaire: $temp_dir"
    
    # Configurer Composer pour l'installation (VARIABLES CRITIQUES DE L'ORIGINAL)
    export COMPOSER_MEMORY_LIMIT=-1
    export COMPOSER_PROCESS_TIMEOUT=0
    export COMPOSER_ALLOW_SUPERUSER=1
    
    # Étape 1 : Télécharger le skeleton SANS installer les dépendances.
    # --no-install permet de patcher composer.json avant le premier install,
    # évitant ainsi de télécharger puis supprimer phpunit/pint/sail.
    local laravel_cmd="composer create-project --prefer-dist laravel/laravel \"$temp_dir\" \"^12.0\" --no-interaction --no-install"
    log_debug "Commande Composer create-project (--no-install): $laravel_cmd"

    local use_fallback=false
    if ! eval "$laravel_cmd" 2>&1 | tee -a "$LOG_FILE"; then
        log_warn "Échec avec composer create-project, tentative avec l'installeur Laravel..."
        use_fallback=true

        # Fallback: utiliser l'installeur Laravel global (installe les dépendances)
        log_info "Installation de l'installeur Laravel globalement..."
        if ! composer global require laravel/installer 2>&1 | tee -a "$LOG_FILE"; then
            log_error "Impossible d'installer l'installeur Laravel globalement"
            rm -rf "$temp_dir" 2>/dev/null || true
            return 1
        fi

        local laravel_new_cmd="/var/composer/vendor/bin/laravel new \"$temp_dir\" --no-interaction --force"
        log_debug "Commande Laravel new: $laravel_new_cmd"

        if ! eval "$laravel_new_cmd" 2>&1 | tee -a "$LOG_FILE"; then
            log_error "Échec de l'installation Laravel avec toutes les méthodes"
            rm -rf "$temp_dir" 2>/dev/null || true
            return 1
        fi
    fi

    # Vérifier que le skeleton est présent
    if [ ! -f "$temp_dir/composer.json" ]; then
        log_error "Skeleton Laravel invalide (composer.json manquant)"
        rm -rf "$temp_dir" 2>/dev/null || true
        return 1
    fi

    # Étape 2 : Patcher composer.json AVANT le premier composer install.
    # (uniquement pour le path principal --no-install ; le fallback laravel new
    #  a déjà ses packages installés, patch_fresh_laravel_skeleton s'en chargera)
    if [ "$use_fallback" = false ]; then
        log_info "🔧 Patch pre-install du skeleton (suppression phpunit/pint/sail)..."
        cd "$temp_dir"
        python3 << 'PYEOF'
import json, sys

with open('composer.json', 'r') as f:
    data = json.load(f)

# Contrainte PHP alignée sur le container Docker
data.setdefault('require', {})['php'] = '^8.5'

# Supprimer les packages du skeleton par défaut non désirés
dev_remove = {'phpunit/phpunit', 'laravel/pint', 'laravel/sail'}
data['require-dev'] = {
    k: v for k, v in data.get('require-dev', {}).items()
    if k not in dev_remove
}

# Ajouter phpstan/extension-installer dans allow-plugins (requis par larastan)
data.setdefault('config', {}).setdefault('allow-plugins', {})
data['config']['allow-plugins']['phpstan/extension-installer'] = True

# Supprimer la création du fichier SQLite dans post-create-project-cmd
cmds = data.get('scripts', {}).get('post-create-project-cmd', [])
data['scripts']['post-create-project-cmd'] = [
    c for c in cmds
    if 'database.sqlite' not in c
]

with open('composer.json', 'w') as f:
    json.dump(data, f, indent=2)

print("composer.json patché: PHP ^8.5, phpunit/pint/sail exclus avant install")
PYEOF
        if [ $? -eq 0 ]; then
            log_success "✅ Pre-install patch appliqué (phpunit, pint, sail exclus)"
        else
            log_warn "⚠️ Patch pre-install échoué - ils seront supprimés après installation"
        fi

        # Étape 3 : Installer les dépendances avec le composer.json propre
        log_info "📦 Installation des dépendances Composer (skeleton patché)..."
        cd "$temp_dir"
        if ! composer install --no-interaction --prefer-dist 2>&1 | tee -a "$LOG_FILE"; then
            log_error "Échec de composer install"
            rm -rf "$temp_dir" 2>/dev/null || true
            return 1
        fi
    fi

    # Vérifier l'installation temporaire (fichiers critiques présents)
    if ! is_laravel_installed "$temp_dir"; then
        log_error "Installation temporaire invalide"
        rm -rf "$temp_dir" 2>/dev/null || true
        return 1
    fi

    # Déplacer les fichiers vers le répertoire cible
    log_debug "Déplacement des fichiers vers $target_dir"
    
    if ! (cd "$temp_dir" && cp -a . "$target_dir/") 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Échec du déplacement des fichiers"
        rm -rf "$temp_dir" 2>/dev/null || true
        return 1
    fi
    
    # Corriger les permissions après installation pour Docker
    if is_docker_environment; then
        log_debug "Correction finale des permissions après installation"
        chown -R www-data:www-data "$target_dir" 2>/dev/null || true
        
        # Permissions pour le développement : directories 775, files 664
        find "$target_dir" -type d -exec chmod 775 {} \; 2>/dev/null || true
        find "$target_dir" -type f -exec chmod 664 {} \; 2>/dev/null || true
        
        # S'assurer qu'artisan est exécutable
        if [ -f "$target_dir/artisan" ]; then
            chmod +x "$target_dir/artisan" 2>/dev/null || true
        fi
        
        log_debug "Permissions finales configurées pour le développement"
    fi
    
    # Nettoyer le répertoire temporaire
    rm -rf "$temp_dir" 2>/dev/null || true
    
    log_success "Laravel installé avec succès"
    return 0
}

#
# Valider l'installation Laravel
#
validate_laravel_installation() {
    local target_dir="$1"
    
    log_debug "Validation de l'installation Laravel"
    
    # Vérifier les fichiers critiques
    for file in "${LARAVEL_CORE_FILES[@]}"; do
        if [ ! -f "$target_dir/$file" ]; then
            log_error "Fichier Laravel manquant: $file"
            return 1
        fi
    done
    
    # Vérifier que artisan est exécutable
    if [ ! -x "$target_dir/artisan" ]; then
        log_debug "Artisan non exécutable, correction..."
        chmod +x "$target_dir/artisan"
    fi
    
    # Tester artisan
    cd "$target_dir"
    if ! php artisan --version &>/dev/null; then
        log_error "Artisan ne fonctionne pas correctement"
        return 1
    fi
    
    # Vérifier composer.json
    if ! php -r "json_decode(file_get_contents('composer.json')); if(json_last_error() !== JSON_ERROR_NONE) exit(1);" 2>/dev/null; then
        log_error "composer.json invalide"
        return 1
    fi
    
    log_success "Installation Laravel validée"
    return 0
}

# =============================================================================
# FONCTIONS DE CONFIGURATION
# =============================================================================

#
# Copier la configuration environnement depuis le projet parent (FONCTION COMPLÈTE)
#
copy_environment_configuration() {
    log_info "📋 Copie de la configuration .env selon l'environnement..."
    
    # Diagnostic du répertoire courant
    log_debug "Répertoire de travail actuel: $(pwd)"
    
    # Détecter l'environnement cible depuis les variables d'environnement Docker
    local target_env="${APP_ENV:-local}"
    
    # Si APP_ENV pas défini, essayer de le détecter depuis le .env racine
    if [ "$target_env" = "local" ]; then
        local root_env_file
        if root_env_file=$(find_root_env 2>/dev/null); then
            local detected_env=$(grep "^APP_ENV=" "$root_env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^["'\'']//' | sed 's/["'\'']$//' | xargs)
            if [ -n "$detected_env" ]; then
                target_env="$detected_env"
            fi
        fi
    fi
    
    log_info "🎯 Environnement détecté: $target_env"
    
    # Localiser le fichier .env.{environnement} dans le projet racine
    local source_env_file="/var/www/project/.env.$target_env"
    local fallback_env_file="/var/www/project/.env"
    local target_env_file="$(pwd)/.env"
    
    # Vérifier que le fichier source existe
    if [ -f "$source_env_file" ]; then
        log_success "✅ Fichier source trouvé: $source_env_file"
        
        # Afficher des informations sur le fichier source
        log_debug "Taille du fichier source: $(wc -l < "$source_env_file" 2>/dev/null || echo 'inconnu') lignes"
        
        # Sauvegarder le .env Laravel existant avec timestamp
        if [ -f "$target_env_file" ]; then
            local backup_file=".env.laravel.backup.$(date +%Y%m%d-%H%M%S)"
            cp "$target_env_file" "$backup_file"
            log_debug "Sauvegarde de .env Laravel vers $backup_file"
            
            # Comparer avec le fichier source pour voir s'il y a des différences
            if diff -q "$source_env_file" "$target_env_file" >/dev/null 2>&1; then
                log_info "✅ Le .env Laravel est déjà identique au .env.$target_env"
                return 0
            else
                log_debug "Différences détectées entre .env.$target_env et Laravel"
            fi
        fi
        
        # Copier avec vérification
        log_debug "Copie de '$source_env_file' vers '$target_env_file'"
        if cp "$source_env_file" "$target_env_file"; then
            log_success "✅ .env.$target_env copié avec succès vers Laravel"
            log_info "📁 Source: $source_env_file"
            log_info "📁 Destination: $target_env_file"
            
            # Vérifier que la copie est identique
            if diff -q "$source_env_file" "$target_env_file" >/dev/null 2>&1; then
                log_success "✅ Copie vérifiée - fichiers identiques"
            else
                log_warn "⚠️ Les fichiers ne sont pas identiques après copie"
                if [ "$DEBUG" = "true" ]; then
                    log_debug "Différences détectées:"
                    diff "$source_env_file" "$target_env_file" | head -10 || true
                fi
                return 1
            fi
        else
            log_error "❌ Échec de la copie du .env.$target_env"
            log_debug "Vérifiez les permissions du répertoire $(pwd)"
            return 1
        fi
        
    elif [ -f "$fallback_env_file" ]; then
        log_warn "⚠️ .env.$target_env non trouvé - utilisation du .env racine"
        log_info "📁 Fallback: $fallback_env_file"
        
        if cp "$fallback_env_file" "$target_env_file"; then
            log_success "✅ .env racine copié comme fallback"
        else
            log_error "❌ Échec de la copie du .env racine"
            return 1
        fi
        
    else
        log_error "❌ Aucun fichier .env trouvé"
        log_info "Fichiers recherchés :"
        log_info "  • Principal: $source_env_file"
        log_info "  • Fallback: $fallback_env_file"
        log_info "💡 Lancez d'abord: make setup-interactive"
        return 1
    fi
    
    # Diagnostic des variables importantes
    log_debug "Vérification des variables importantes dans le .env copié:"
    
    local important_vars=("APP_NAME" "APP_ENV" "DB_HOST" "COMPOSE_PROJECT_NAME" "NIGHTWATCH_TOKEN" "REDIS_HOST")
    for var in "${important_vars[@]}"; do
        local value=$(grep "^$var=" "$target_env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^["'\'']//' | sed 's/["'\'']$//' | xargs)
        if [ -n "$value" ]; then
            if [[ "$var" == *"TOKEN"* ]] || [[ "$var" == *"PASSWORD"* ]]; then
                log_debug "  $var: ${value:0:10}... (masqué)"
            else
                log_debug "  $var: $value"
            fi
        else
            log_debug "  $var: (non défini)"
        fi
    done
    
    # Vérification spéciale pour Nightwatch
    local final_token=$(grep "^NIGHTWATCH_TOKEN=" "$target_env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^["'\'']//' | sed 's/["'\'']$//' | xargs)
    if [ -n "$final_token" ] && [ "$final_token" != "" ] && [ "$final_token" != "\${NIGHTWATCH_TOKEN}" ]; then
        log_success "✅ Token Nightwatch configuré: ${final_token:0:10}..."
    else
        log_warn "⚠️ Token Nightwatch non configuré ou vide"
        log_debug "Valeur NIGHTWATCH_TOKEN: '$final_token'"
        log_info "Le service fonctionnera mais Nightwatch ne sera pas actif"
    fi
    
    # Vérification de l'environnement
    local final_env=$(grep "^APP_ENV=" "$target_env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^["'\'']//' | sed 's/["'\'']$//' | xargs)
    if [ "$final_env" = "$target_env" ]; then
        log_success "✅ Environnement correctement configuré: $final_env"
    else
        log_warn "⚠️ Incohérence d'environnement détectée"
        log_debug "Attendu: $target_env, Trouvé: $final_env"
    fi
    
    log_success "✅ Configuration .env.$target_env intégrée dans Laravel"
    return 0
}

#
# Chercher le fichier .env racine du projet
#
find_root_env_file() {
    local search_paths=(
        "/var/www/project/.env"
        "../../.env"
        "../.env"
        ".env"
    )
    
    for env_path in "${search_paths[@]}"; do
        if [ -f "$env_path" ]; then
            # Vérifier que c'est un fichier .env de projet Docker
            if grep -q "COMPOSE_PROJECT_NAME\|DB_HOST.*postgres\|DB_CONNECTION.*pgsql" "$env_path" 2>/dev/null; then
                echo "$env_path"
                return 0
            fi
        fi
    done
    
    return 1
}

#
# Adapter la configuration environnement pour Laravel
#
adapt_environment_configuration() {
    local source_env="$1"
    
    log_debug "Adaptation de la configuration depuis $source_env"
    
    # Copier le fichier source
    cp "$source_env" ".env"
    
    # Adapter les valeurs spécifiques à Laravel
    local adaptations=(
        "s/^APP_NAME=.*/APP_NAME=\"Laravel Application\"/"
        "s/^APP_ENV=.*/APP_ENV=local/"
        "s/^APP_DEBUG=.*/APP_DEBUG=true/"
        "s/^APP_URL=.*/APP_URL=http:\/\/localhost/"
    )
    
    for adaptation in "${adaptations[@]}"; do
        sed -i "$adaptation" ".env" 2>/dev/null || true
    done
    
    # Ajouter des valeurs manquantes si nécessaire
    local required_vars=(
        "APP_NAME=\"Laravel Application\""
        "APP_ENV=local"
        "APP_DEBUG=true"
        "APP_URL=http://localhost"
    )
    
    for var in "${required_vars[@]}"; do
        local var_name="${var%%=*}"
        if ! grep -q "^$var_name=" ".env"; then
            echo "$var" >> ".env"
            log_debug "Variable ajoutée: $var"
        fi
    done
    
    return 0
}

#
# Générer la clé d'application Laravel
#
generate_application_key() {
    log_info "Génération de la clé d'application Laravel..."
    
    # Vérifier si une clé existe déjà
    if grep -q "^APP_KEY=.*" ".env" && [ "$(grep "^APP_KEY=" ".env" | cut -d= -f2)" != "" ]; then
        log_debug "Clé d'application existante détectée"
        local existing_key=$(grep "^APP_KEY=" ".env" | cut -d= -f2)
        if [ ${#existing_key} -gt 10 ]; then
            log_success "Clé d'application existante conservée"
            return 0
        fi
    fi
    
    # Générer une nouvelle clé
    if php artisan key:generate --force 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Clé d'application générée"
        return 0
    else
        log_error "Échec de la génération de la clé d'application"
        return 1
    fi
}

#
# Configurer les permissions des répertoires Laravel
#
setup_laravel_permissions() {
    log_debug "Configuration des permissions Laravel..."
    
    local directories=(
        "storage"
        "storage/app"
        "storage/framework"
        "storage/framework/cache"
        "storage/framework/sessions"
        "storage/framework/views"
        "storage/logs"
        "bootstrap/cache"
    )
    
    for dir in "${directories[@]}"; do
        # Créer le répertoire s'il n'existe pas
        if [ ! -d "$dir" ]; then
            log_debug "Répertoire manquant, création: $dir"
            mkdir -p "$dir" 2>/dev/null || true
        fi
        
        # Configurer les permissions (plus agressif pour bootstrap/cache)
        if [ "$dir" = "bootstrap/cache" ]; then
            # Bootstrap cache nécessite des permissions spéciales
            if is_docker_environment; then
                chmod -R 777 "$dir" 2>/dev/null || true
                chown -R www-data:www-data "$dir" 2>/dev/null || true
            else
                chmod -R 775 "$dir" 2>/dev/null || true
            fi
            log_debug "✓ Permissions spéciales configurées: $dir"
        else
            if chmod -R 775 "$dir" 2>/dev/null; then
                log_debug "✓ Permissions configurées: $dir"
            else
                log_warn "Impossible de configurer les permissions: $dir"
            fi
        fi
    done
    
    return 0
}

#
# Optimiser la configuration Laravel de base
#
optimize_laravel_configuration() {
    log_debug "Optimisation de la configuration Laravel..."
    
    # Nettoyer les caches existants (seulement si les tables existent)
    php artisan config:clear 2>/dev/null || true
    
    # Vérifier si la table cache existe avant de la vider
    if php artisan tinker --execute="try { DB::table('cache')->limit(1)->get(); echo 'exists'; } catch(Exception \$e) { echo 'missing'; }" 2>/dev/null | grep -q "exists"; then
        php artisan cache:clear 2>/dev/null || true
    else
        log_debug "Table cache non trouvée, skip cache:clear"
    fi
    
    php artisan view:clear 2>/dev/null || true
    
    # Optimiser pour le développement
    if [ "$(get_current_environment)" = "local" ] || [ "$(get_current_environment)" = "development" ]; then
        log_debug "Optimisation pour l'environnement de développement"
        # En développement, on ne cache pas la configuration
        return 0
    fi
    
    # Optimiser pour la production
    log_debug "Optimisation pour l'environnement de production"
    php artisan config:cache 2>/dev/null || true
    
    return 0
}

#
# Patcher le skeleton Laravel par défaut après création
# (supprimer les conflits avec Pest v4, corriger phpunit.xml pour PostgreSQL)
#
patch_fresh_laravel_skeleton() {
    local laravel_dir="$1"

    log_info "🔧 Patch du skeleton Laravel par défaut..."

    cd "$laravel_dir"

    # --- 1. Patch composer.json (idempotent) ---
    # Pour le path principal (--no-install), ce patch a déjà été appliqué
    # avant composer install. Pour le fallback (laravel new), il est nécessaire ici.
    if [ -f "composer.json" ]; then
        python3 << 'PYEOF'
import json, sys

with open('composer.json', 'r') as f:
    data = json.load(f)

changed = False

# Contrainte PHP alignée sur le container Docker
if data.get('require', {}).get('php') != '^8.5':
    data.setdefault('require', {})['php'] = '^8.5'
    changed = True

# Supprimer les packages du skeleton non désirés (idempotent)
dev_remove = {'phpunit/phpunit', 'laravel/pint', 'laravel/sail'}
before = set(data.get('require-dev', {}).keys())
data['require-dev'] = {
    k: v for k, v in data.get('require-dev', {}).items()
    if k not in dev_remove
}
if before != set(data.get('require-dev', {}).keys()):
    changed = True

# Ajouter phpstan/extension-installer dans allow-plugins
plugins = data.setdefault('config', {}).setdefault('allow-plugins', {})
if not plugins.get('phpstan/extension-installer'):
    plugins['phpstan/extension-installer'] = True
    changed = True

# Supprimer la création du fichier SQLite
cmds = data.get('scripts', {}).get('post-create-project-cmd', [])
filtered = [c for c in cmds if 'database.sqlite' not in c]
if filtered != cmds:
    data['scripts']['post-create-project-cmd'] = filtered
    changed = True

with open('composer.json', 'w') as f:
    json.dump(data, f, indent=2)

if changed:
    print("composer.json patché (fallback path: phpunit/pint/sail retirés)")
else:
    print("composer.json déjà patché (pre-install patch détecté, aucun changement)")
PYEOF
        [ $? -eq 0 ] && log_success "✅ composer.json vérifié/patché" \
                      || log_warn "⚠️ Patch composer.json échoué"
    fi

    # --- 2. Supprimer les packages skeleton si encore présents dans vendor/ ---
    # Cas du fallback (laravel new) : les packages ont été installés.
    # --no-scripts évite les erreurs prePackageUninstall de ComposerScripts.
    local skeleton_pkgs=("phpunit/phpunit" "laravel/pint" "laravel/sail")
    local pkgs_to_remove=()
    for pkg in "${skeleton_pkgs[@]}"; do
        if [ -d "vendor/${pkg}" ]; then
            pkgs_to_remove+=("$pkg")
        fi
    done

    if [ ${#pkgs_to_remove[@]} -gt 0 ]; then
        log_info "🧹 Suppression des packages skeleton encore présents: ${pkgs_to_remove[*]}"
        composer remove "${pkgs_to_remove[@]}" --dev --no-scripts --no-interaction \
            2>&1 | tee -a "$LOG_FILE" || true
        log_success "✅ Packages skeleton supprimés"
    else
        log_debug "✓ Aucun package skeleton à supprimer (pre-install patch appliqué)"
    fi

    # --- 3. Patcher phpunit.xml : SQLite → PostgreSQL ---
    if [ -f "phpunit.xml" ]; then
        # Remplacer sqlite par pgsql
        sed -i 's|<env name="DB_CONNECTION" value="sqlite"/>|<env name="DB_CONNECTION" value="pgsql"/>|' phpunit.xml
        # Remplacer :memory: par laravel_test
        sed -i 's|<env name="DB_DATABASE" value=":memory:"/>|<env name="DB_DATABASE" value="laravel_test"/>|' phpunit.xml
        # Supprimer la ligne DB_URL vide (spécifique SQLite)
        sed -i '/<env name="DB_URL" value=""\/>/ d' phpunit.xml
        log_success "✅ phpunit.xml patché (SQLite → PostgreSQL laravel_test)"
    fi

    log_success "✅ Skeleton Laravel patché"
}

#
# Créer la route de healthcheck pour Docker (EXACTE DE L'ORIGINAL)
#
create_healthcheck_route() {
    log_info "🏥 Création de la route de healthcheck..."
    
    if ! grep -q "/health" routes/web.php; then
        cat >> routes/web.php << 'EOF'

// Route de healthcheck pour Docker
Route::get('/health', function () {
    return response()->json([
        'status' => 'ok',
        'timestamp' => now()->toISOString(),
        'service' => 'laravel',
        'app' => config('app.name', 'Laravel')
    ]);
});
EOF
        log_success "✅ Route /health créée"
    else
        log_info "Route /health déjà existante"
    fi
}

# =============================================================================
# FONCTION PRINCIPALE
# =============================================================================

main() {
    local target_dir="${1:-$(detect_working_directory)}"
    local start_time=$(date +%s)
    
    log_separator "INSTALLATION LARAVEL CORE"
    log_info "🚀 Début de l'installation Laravel dans: $target_dir"
    
    # Créer le projet Laravel
    create_laravel_project "$target_dir"

    # Patcher le skeleton par défaut (PHP ^8.5, supprimer phpunit/pint/sail, PostgreSQL pour les tests)
    patch_fresh_laravel_skeleton "$target_dir"

    # Configurer l'environnement
    configure_laravel_environment "$target_dir"
    
    # Créer la route de healthcheck
    create_healthcheck_route
    
    # Afficher les informations finales
    cd "$target_dir"
    local laravel_version=$(get_laravel_version)
    local php_version=$(get_php_version)
    
    local duration=$(calculate_duration $start_time)
    
    log_separator "INSTALLATION TERMINÉE"
    log_success "✅ Laravel $laravel_version installé avec succès en $duration"
    log_info "📍 Répertoire: $target_dir"
    log_info "🐘 PHP: $php_version"
    log_info "🔑 Clé d'application: configurée"
    log_info "📄 Fichier de log: $LOG_FILE"
}

# =============================================================================
# EXÉCUTION
# =============================================================================

# Exécuter seulement si le script est appelé directement
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi