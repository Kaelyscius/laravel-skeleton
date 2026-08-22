#!/bin/bash

# =============================================================================
# ORCHESTRATEUR PRINCIPAL D'INSTALLATION LARAVEL
# =============================================================================
#
# Ce script orchestre l'installation complète de Laravel en exécutant
# séquentiellement tous les modules d'installation. Il gère les erreurs,
# le rollback et fournit un rapport détaillé de l'installation.
#
# Utilisation:
#   ./install.sh [options] [répertoire_cible]
#
# Options:
#   -h, --help          Afficher l'aide
#   -v, --verbose       Mode verbeux (DEBUG=true)
#   -q, --quiet         Mode silencieux
#   --skip-prereq       Ignorer la vérification des prérequis
#   --only MODULE       Exécuter seulement un module spécifique
#   --resume-from MODULE Reprendre depuis un module spécifique
#   --force             Ignorer les sentinelles et tout rejouer
#   --dry-run           Simulation sans exécution réelle
#
# Code de sortie:
#   0: Installation réussie
#   1: Erreur lors de l'installation
#
# ⚠️ L'en-tête annonçait aussi « 2: Erreur de paramètres ». Ce code n'a JAMAIS
# été émis : toutes les erreurs d'arguments passent par `log_fatal`, qui sort
# systématiquement 1. La ligne est retirée plutôt que corrigée en `exit 2` —
# personne ne lit ce contrat, et le changer casserait les appelants qui testent
# `!= 0`. Contrat réel et unique : 0 ou 1.
#
# =============================================================================

set -e

# Charger les dépendances
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/common.sh"
# Story 2.2 — `ensure_idempotent` avait zéro appelant de production (report W23).
# C'est ICI qu'elle en trouve un : les modules tournent en sous-processus
# (`execute_module`), donc l'`export -f` de runtime.sh ne les atteint pas —
# l'enveloppement doit se faire dans l'orchestrateur, pas dans les modules.
source "$SCRIPT_DIR/lib/runtime.sh"

# =============================================================================
# VARIABLES DE CONFIGURATION
# =============================================================================

# Modules d'installation dans l'ordre d'exécution
readonly INSTALL_MODULES=(
    "00-prerequisites:Vérification des prérequis"
    "05-composer-setup:Configuration et réparation Composer"
    "10-laravel-core:Installation du coeur Laravel"
    "20-database:Configuration de la base de données"
    "30-packages-prod:Installation des packages de production"
    "35-configure-spatie-packages:Configuration des packages Spatie"
    "40-packages-dev:Installation des packages de développement"
    "45-configure-pest:Configuration de Pest et plugin Drift"
    "50-quality-tools:Configuration des outils qualité"
    "60-nightwatch:Configuration de Nightwatch"
    "99-finalize:Finalisation et optimisation"
)

# Variables globales
SKIP_PREREQUISITES=false
ONLY_MODULE=""
RESUME_FROM=""
DRY_RUN=false
FORCE=false
TARGET_DIR=""
INSTALLATION_ID="$(date +%Y%m%d-%H%M%S)"

# Racine des sentinelles d'idempotence.
#
# ⚖️ Elle vit sous `$TARGET_DIR` — donc `src/.install-state/` en pratique — et
# NON à la racine du dépôt : celle-ci est montée `ro` sur `/var/www/project`
# dans les conteneurs php et node, et toute écriture y échouerait en EROFS.
# ⚠️ `test -w /var/www/project` rend pourtant VRAI sur ce montage : ne jamais
# garder l'écrivabilité avec `test -w`, c'est l'écriture réelle qui tranche
# (post-condition relue sur disque d'`ensure_idempotent`).
#
# Injectable par environnement pour être testable : la sonde Pest fixe son cwd
# sur l'arbre applicatif réel, elle ne peut donc pas laisser l'installeur semer
# des sentinelles dedans.
INSTALL_STATE_DIR="${INSTALL_STATE_DIR:-}"

# Grain de sentinelle = identifiant de module (`00-prerequisites`, …), déjà
# stable, unique, validé, et déjà l'identité publique de `--only`/`--resume-from`.
# ⛔ Jamais les libellés de `log_step_start` : accentués, non uniques, et donc
# incapables de faire un nom de fichier fiable.
sentinel_path_for_module() {
    echo "$INSTALL_STATE_DIR/${1}-done"
}

# Résout la racine d'état. Appelée par `parse_arguments` ET au début de
# `run_installation`, pour qu'un appelant qui n'aurait pas parsé d'arguments
# (fixture, test) obtienne le même défaut.
init_install_state_dir() {
    if [ -z "${INSTALL_STATE_DIR:-}" ]; then
        INSTALL_STATE_DIR="$TARGET_DIR/.install-state"
    fi
}

# =============================================================================
# FONCTIONS D'AIDE
# =============================================================================

show_help() {
    cat << EOF
ORCHESTRATEUR D'INSTALLATION LARAVEL

Ce script installe et configure un projet Laravel complet avec tous
les outils de développement et de qualité.

UTILISATION:
    $(basename "$0") [options] [répertoire_cible]

OPTIONS:
    -h, --help          Afficher cette aide
    -v, --verbose       Mode verbeux avec logs détaillés
    -q, --quiet         Mode silencieux (erreurs uniquement)
    --skip-prereq       Ignorer la vérification des prérequis
    --only MODULE       Exécuter seulement un module spécifique
    --resume-from MODULE Reprendre l'installation depuis un module
    --force             Ignorer les sentinelles et rejouer tous les modules
    --dry-run           Simulation sans exécution réelle
    --list-modules      Lister les modules disponibles

MODULES DISPONIBLES:
$(for module in "${INSTALL_MODULES[@]}"; do
    local name="${module%%:*}"
    local desc="${module##*:}"
    printf "    %-20s %s\n" "$name" "$desc"
done)

EXEMPLES:
    $(basename "$0")                          # Installation complète
    $(basename "$0") /var/www/html/app        # Installation dans un répertoire spécifique
    $(basename "$0") --only 10-laravel-core   # Installer seulement Laravel
    $(basename "$0") --resume-from 30-packages-prod # Reprendre à partir des packages
    $(basename "$0") --dry-run                # Simulation
    $(basename "$0") --verbose                # Mode verbeux

ENVIRONNEMENT:
    DEBUG=true          Active le mode debug
    LOG_LEVEL=INFO      Niveau de log (DEBUG|INFO|WARN|ERROR)
    QUIET=true          Mode silencieux
    INSTALL_STATE_DIR   Racine des sentinelles (défaut: <cible>/.install-state)

FICHIERS:
    Le fichier de log est créé dans /tmp/laravel-install-YYYYMMDD-HHMMSS.log
    Les sentinelles d'idempotence vivent dans <cible>/.install-state/

IDEMPOTENCE:
    Chaque module franchi pose une sentinelle <module>-done. Une install
    interrompue reprend d'elle-même au module qui a échoué : inutile de taper
    --resume-from. Un module en échec ne pose PAS sa sentinelle, il est donc
    rejoué au passage suivant. --force ignore et réécrit toutes les sentinelles.

CODES DE SORTIE:
    0    Installation réussie
    1    Erreur lors de l'installation

EOF
}

list_modules() {
    log_separator "MODULES D'INSTALLATION DISPONIBLES"
    
    for module in "${INSTALL_MODULES[@]}"; do
        local name="${module%%:*}"
        local desc="${module##*:}"
        local module_file="$SCRIPT_DIR/install/$name.sh"
        
        if [ -f "$module_file" ]; then
            local status="✅ Disponible"
        else
            local status="❌ Manquant"
        fi
        
        printf "%-20s %-50s %s\n" "$name" "$desc" "$status"
    done
}

# =============================================================================
# FONCTIONS DE GESTION DES PARAMÈTRES
# =============================================================================

parse_arguments() {
    # ⚠️ `INSTALL_FORCE` N'EST PAS REMIS À PLAT ICI, ET C'EST DÉLIBÉRÉ.
    # La revue demandait une remise à `false` en tête de cette fonction. La
    # PROPRIÉTÉ voulue — une valeur héritée de l'environnement n'autorise aucune
    # destruction — est tenue, mais au SEUL endroit qui la rend indéformable :
    # `run_installation`, qui redérive `INSTALL_FORCE` depuis `FORCE` juste
    # avant de lancer le premier module. Mesuré le 2026-08-22 : avec la remise à
    # plat ici EN PLUS, la retirer laissait la suite verte — un second garde
    # qu'aucune mutation ne peut faire rougir, c'est-à-dire la définition même
    # du garde-fou décoratif que cette story existe pour refuser.
    # Voir la dérivation unique dans `run_installation`.
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                export DEBUG=true
                export LOG_LEVEL=DEBUG
                shift
                ;;
            -q|--quiet)
                export QUIET=true
                export LOG_LEVEL=ERROR
                shift
                ;;
            --skip-prereq)
                SKIP_PREREQUISITES=true
                shift
                ;;
            --only)
                ONLY_MODULE="$2"
                if [ -z "$ONLY_MODULE" ]; then
                    log_fatal "Module requis pour --only"
                fi
                shift 2
                ;;
            --resume-from)
                RESUME_FROM="$2"
                if [ -z "$RESUME_FROM" ]; then
                    log_fatal "Module requis pour --resume-from"
                fi
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                export DEBUG=true
                shift
                ;;
            --list-modules)
                list_modules
                exit 0
                ;;
            -*)
                log_fatal "Option inconnue: $1"
                ;;
            *)
                if [ -z "$TARGET_DIR" ]; then
                    TARGET_DIR="$1"
                else
                    log_fatal "Trop d'arguments positionnels"
                fi
                shift
                ;;
        esac
    done
    
    # Définir le répertoire cible par défaut
    if [ -z "$TARGET_DIR" ]; then
        TARGET_DIR=$(detect_working_directory)
    fi

    # La racine d'état dépend de la cible : elle ne peut être résolue qu'ici.
    init_install_state_dir

    # Valider les paramètres
    validate_arguments
}

validate_arguments() {
    # Valider le module pour --only
    if [ -n "$ONLY_MODULE" ]; then
        local valid=false
        for module in "${INSTALL_MODULES[@]}"; do
            local name="${module%%:*}"
            if [ "$name" = "$ONLY_MODULE" ]; then
                valid=true
                break
            fi
        done
        
        if [ "$valid" = false ]; then
            log_fatal "Module invalide pour --only: $ONLY_MODULE"
        fi
    fi
    
    # Valider le module pour --resume-from
    if [ -n "$RESUME_FROM" ]; then
        local valid=false
        for module in "${INSTALL_MODULES[@]}"; do
            local name="${module%%:*}"
            if [ "$name" = "$RESUME_FROM" ]; then
                valid=true
                break
            fi
        done
        
        if [ "$valid" = false ]; then
            log_fatal "Module invalide pour --resume-from: $RESUME_FROM"
        fi
    fi
    
    # Valider et configurer le répertoire cible
    if [ -n "$TARGET_DIR" ]; then
        # Dans un environnement Docker, les permissions sont gérées différemment
        if is_docker_environment; then
            log_debug "Environnement Docker détecté - configuration proactive des permissions"
            
            # Créer le répertoire s'il n'existe pas
            if [ ! -d "$TARGET_DIR" ]; then
                log_debug "Création du répertoire cible: $TARGET_DIR"
                mkdir -p "$TARGET_DIR" 2>/dev/null || true
            fi
            
            # Corriger les permissions de manière proactive
            log_debug "Correction proactive des permissions Docker pour $TARGET_DIR"
            chown -R www-data:www-data "$TARGET_DIR" 2>/dev/null || true
            chmod -R 755 "$TARGET_DIR" 2>/dev/null || true
            
            # Vérifier que les permissions sont maintenant correctes
            if [ ! -w "$TARGET_DIR" ]; then
                log_warn "Permissions encore incorrectes, tentative de correction forcée"
                chmod -R 777 "$TARGET_DIR" 2>/dev/null || true
                
                if [ ! -w "$TARGET_DIR" ]; then
                    log_fatal "Impossible de corriger les permissions pour: $TARGET_DIR"
                fi
            fi
            
            log_debug "Permissions Docker configurées avec succès pour $TARGET_DIR"
        else
            # Validation classique pour les environnements non-Docker
            local parent_dir="$(dirname "$TARGET_DIR")"
            if [ ! -d "$parent_dir" ]; then
                log_fatal "Répertoire parent inexistant: $parent_dir"
            fi
            
            if [ ! -w "$parent_dir" ]; then
                log_fatal "Pas de permission d'écriture dans: $parent_dir"
            fi
        fi
    fi
}

# =============================================================================
# FONCTIONS D'EXÉCUTION DES MODULES
# =============================================================================

execute_module() {
    local module_name="$1"
    local module_desc="${2:-Installation du module $module_name}"
    local module_file="$SCRIPT_DIR/install/$module_name.sh"
    
    # Vérifier que le module existe
    if [ ! -f "$module_file" ]; then
        log_error "Module non trouvé: $module_file"
        return 1
    fi
    
    # Vérifier que le module est exécutable
    if [ ! -x "$module_file" ]; then
        log_debug "Module non exécutable, correction..."
        chmod +x "$module_file"
    fi
    
    log_step_start "$module_name" "$module_desc"
    local start_time=$(date +%s)
    
    # Mode dry-run
    if [ "$DRY_RUN" = true ]; then
        log_info "🔍 [DRY-RUN] Simulation du module $module_name"
        log_info "📂 Répertoire cible: $TARGET_DIR"
        log_info "📜 Script: $module_file"
        sleep 1  # Simuler un temps d'exécution
        local duration=$(calculate_duration $start_time)
        log_step_end "$module_name" "$duration"
        return 0
    fi
    
    # Exécution réelle du module
    local exit_code=0
    
    # Exécuter le module et capturer le vrai code de retour
    "$module_file" "$TARGET_DIR" 2>&1 | tee -a "$LOG_FILE"
    exit_code=${PIPESTATUS[0]}  # Capturer le code de retour du script, pas de tee
    
    if [ $exit_code -ne 0 ]; then
        log_error "Échec du module $module_name (code: $exit_code)"
        log_error "🔍 Consultez le fichier de log: $LOG_FILE"
        return $exit_code
    fi
    
    local duration=$(calculate_duration $start_time)
    log_step_end "$module_name" "$duration"
    
    return 0
}

run_installation() {
    local start_time=$(date +%s)
    local executed_modules=()
    local skipped_modules=()
    local resume_found=false

    init_install_state_dir

    # ⛔ SEUL ENDROIT OÙ `INSTALL_FORCE` EST DÉRIVÉ, ET IL EST SUR LE CHEMIN
    # D'EXÉCUTION. Le module 10 le lit pour savoir si un nettoyage DESTRUCTEUR
    # de la cible est autorisé, et les modules tournent en SOUS-PROCESSUS
    # (`execute_module`) : sans export, le drapeau ne les atteint pas et le
    # message « relancez avec --force » devient un cul-de-sac.
    #
    # 🔴 IL ÉTAIT POSÉ DANS LA BRANCHE `--force` DE `parse_arguments`, ce qui
    # faisait DEUX sources de vérité pour un seul fait. Mesuré : un appelant
    # qui pose `FORCE=true` sans passer par `parse_arguments` — la fixture
    # versionnée le fait, et `install-laravel-prod` enchaîne cinq processus —
    # laissait le fils voir `<absent>` alors que l'installeur se croyait en
    # mode forcé. Dériver ici, à partir de `FORCE`, rend le désaccord
    # impossible plutôt qu'improbable.
    export INSTALL_FORCE="$FORCE"

    log_separator "DÉBUT DE L'INSTALLATION"
    log_info "🚀 Installation Laravel - ID: $INSTALLATION_ID"
    log_info "📍 Répertoire cible: $TARGET_DIR"
    log_info "🗂️ Racine d'état: $INSTALL_STATE_DIR"
    log_info "📄 Fichier de log: $LOG_FILE"

    if [ "$FORCE" = true ]; then
        log_warn "🧨 --force : les sentinelles existantes sont ignorées et réécrites"
    fi

    if [ "$DRY_RUN" = true ]; then
        log_info "🔍 MODE SIMULATION (DRY-RUN)"
    fi

    record_installation_start

    # Afficher la configuration
    show_installation_config
    
    # Exécuter les modules
    for module_entry in "${INSTALL_MODULES[@]}"; do
        local module_name="${module_entry%%:*}"
        local module_desc="${module_entry##*:}"
        
        # Gestion du mode --only
        if [ -n "$ONLY_MODULE" ]; then
            if [ "$module_name" != "$ONLY_MODULE" ]; then
                continue
            fi
        fi
        
        # Gestion du mode --resume-from
        if [ -n "$RESUME_FROM" ]; then
            if [ "$resume_found" = false ]; then
                if [ "$module_name" = "$RESUME_FROM" ]; then
                    resume_found=true
                else
                    log_debug "Module ignoré (resume-from): $module_name"
                    continue
                fi
            fi
        fi
        
        # Skip des prérequis si demandé
        if [ "$SKIP_PREREQUISITES" = true ] && [ "$module_name" = "00-prerequisites" ]; then
            log_warn "⚠️ Vérification des prérequis ignorée (--skip-prereq)"
            continue
        fi
        
        # ---------------------------------------------------------------
        # Idempotence au grain MODULE
        # ---------------------------------------------------------------
        # `--force` retire la sentinelle AVANT l'appel plutôt que de
        # court-circuiter `ensure_idempotent` : la primitive reste le seul
        # endroit qui décide « joué / pas joué », et la sentinelle est réécrite
        # (donc relue sur disque) au lieu d'être laissée telle quelle.
        local sentinel
        sentinel="$(sentinel_path_for_module "$module_name")"

        if [ "$FORCE" = true ] && [ "$DRY_RUN" != true ]; then
            rm -f "$sentinel" 2>/dev/null || true
        fi

        # Relevé AVANT l'appel : `ensure_idempotent` rend 0 aussi bien pour
        # « déjà franchi » que pour « joué avec succès ». Sans ce relevé, le
        # rapport final compterait comme exécuté un module jamais lancé.
        local already_done=false
        if [ -f "$sentinel" ] && [ "$FORCE" != true ]; then
            already_done=true
        fi

        # ⛔ EN SIMULATION, AUCUNE SENTINELLE N'EST NI ÉCRITE NI EFFACÉE.
        # `execute_module` rend 0 sans rien faire sous `--dry-run` :
        # l'envelopper dans `ensure_idempotent` ferait ÉCRIRE la sentinelle
        # d'un module qui n'a jamais tourné, et l'install réelle suivante le
        # sauterait. Une simulation qui laisse un effet de bord n'est pas une
        # simulation — c'est la promesse même du drapeau (Epic 2 : « --dry-run
        # sans aucun effet de bord, ni fichier, ni conteneur »).
        if [ "$DRY_RUN" = true ]; then
            if [ "$already_done" = true ]; then
                log_info "🔍 [DRY-RUN] $module_name serait SAUTÉ (sentinelle présente)"
                skipped_modules+=("$module_name")
            else
                # 🔴 LE STATUT EST DE NOUVEAU BRANCHÉ (correctif revue 1).
                # La première rédaction appelait `execute_module` nu et
                # comptait le module comme joué quoi qu'il arrive : un module
                # ABSENT du disque rendait 1, `set -e` ne s'applique pas dans
                # une condition… mais ici il n'y avait aucune condition, donc
                # la simulation mourait sans rapport d'erreur, ou pire passait.
                # Or `--dry-run` sert précisément à découvrir qu'un module
                # manque AVANT de lancer l'installation réelle.
                local dry_status=0
                execute_module "$module_name" "$module_desc" || dry_status=$?

                if [ "$dry_status" -ne 0 ]; then
                    log_error "Échec du module $module_name (simulation)"
                    show_error_report "$module_name" "${executed_modules[@]}"

                    return "$dry_status"
                fi

                executed_modules+=("$module_name")
            fi

            if [ -n "$ONLY_MODULE" ]; then
                break
            fi

            continue
        fi

        if ensure_idempotent "$sentinel" execute_module "$module_name" "$module_desc"; then
            if [ "$already_done" = true ]; then
                skipped_modules+=("$module_name")
                log_info "⏭️ Module $module_name déjà franchi — sentinelle présente, non rejoué"
            else
                executed_modules+=("$module_name")
                log_debug "Module $module_name exécuté avec succès"
            fi
        else
            local exit_code=$?
            log_error "Échec du module $module_name"

            # Afficher le rapport d'erreur
            show_error_report "$module_name" "${executed_modules[@]}"

            return $exit_code
        fi

        # En mode --only, s'arrêter après le module
        if [ -n "$ONLY_MODULE" ]; then
            break
        fi
    done

    # Rapport de succès
    local duration=$(calculate_duration $start_time)
    show_success_report "$duration" "${executed_modules[@]}"

    if [ ${#skipped_modules[@]} -gt 0 ]; then
        log_info "⏭️ Modules déjà franchis (non rejoués): ${#skipped_modules[@]}"
        for module in "${skipped_modules[@]}"; do
            log_info "   ⏭️ $module"
        done
    fi

    return 0
}

#
# Horodater le début de l'installation, une seule fois.
#
# Écrit uniquement si absent : une install reprise après crash garde donc son
# heure de départ d'origine, et la fenêtre enregistrée couvre l'installation
# ENTIÈRE, reprises comprises. C'est ce que `scripts/install-lockfile.sh` relit
# pour `started_at`, et ce que la story 2.4 devra pouvoir mesurer contre la
# promesse « install < 15 min ».
#
record_installation_start() {
    local marker="$INSTALL_STATE_DIR/started-at"

    # ⛔ Même règle qu'au-dessus : une simulation n'écrit RIEN.
    if [ "$DRY_RUN" = true ]; then
        log_debug "[DRY-RUN] horodatage de début non écrit ($marker)"
        return 0
    fi

    # 🔴 SEUL UN REJEU COMPLET REPART LA FENÊTRE (relevé revue 2).
    # La rédaction précédente réécrivait dès `FORCE=true`, sans égard à
    # `ONLY_MODULE`. Prouvé par exécution : `install.sh --only 30-packages-prod
    # --force` republiait un `started_at` postérieur à l'install complète — donc
    # une fenêtre décrivant la reprise d'UN module, pas l'installation. C'est
    # exactement le mode de défaillance que M13 avait fait garder, revenu par
    # une autre porte : la story 2.4 lira ce champ contre « install < 15 min ».
    # `--force --only X` rejoue X ; il ne recommence pas l'installation.
    local full_replay=false
    if [ "$FORCE" = true ] && [ -z "$ONLY_MODULE" ]; then
        full_replay=true
    fi

    if [ -f "$marker" ] && [ "$full_replay" != true ]; then
        return 0
    fi

    mkdir -p "$INSTALL_STATE_DIR" > /dev/null 2>&1 || true
    date -u '+%Y-%m-%dT%H:%M:%SZ' > "$marker" 2>/dev/null || {
        # Non fatal, et c'est délibéré : l'horodatage est de la MÉTROLOGIE, pas
        # une garde d'installation. Ce qui doit mourir bruyamment sur une racine
        # inécrivable, c'est la sentinelle du premier module — et
        # `ensure_idempotent` s'en charge, en nommant le chemin.
        log_warn "Horodatage de début impossible à écrire ($marker)"
        return 0
    }

    return 0
}

# =============================================================================
# FONCTIONS DE RAPPORT
# =============================================================================

show_installation_config() {
    log_separator "CONFIGURATION DE L'INSTALLATION"
    
    log_info "📋 Paramètres:"
    log_info "   • Répertoire cible: $TARGET_DIR"
    log_info "   • Racine d'état: $INSTALL_STATE_DIR"
    log_info "   • Rejeu forcé (--force): $FORCE"
    log_info "   • Mode debug: ${DEBUG:-false}"
    log_info "   • Mode silencieux: ${QUIET:-false}"
    log_info "   • Skip prérequis: $SKIP_PREREQUISITES"

    if [ -n "$ONLY_MODULE" ]; then
        log_info "   • Module unique: $ONLY_MODULE"
    fi
    
    if [ -n "$RESUME_FROM" ]; then
        log_info "   • Reprendre depuis: $RESUME_FROM"
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_info "   • Mode simulation: activé"
    fi
    
    log_info "🏗️ Modules à exécuter:"
    for module_entry in "${INSTALL_MODULES[@]}"; do
        local module_name="${module_entry%%:*}"
        local module_desc="${module_entry##*:}"
        local status="✅"
        
        # Vérifier les conditions d'exécution
        if [ -n "$ONLY_MODULE" ] && [ "$module_name" != "$ONLY_MODULE" ]; then
            status="⏸️ Ignoré (--only)"
        elif [ "$FORCE" != true ] && [ -f "$(sentinel_path_for_module "$module_name")" ]; then
            status="⏭️ Déjà franchi (sentinelle)"
        elif [ "$SKIP_PREREQUISITES" = true ] && [ "$module_name" = "00-prerequisites" ]; then
            status="⏸️ Ignoré (--skip-prereq)"
        elif [ -n "$RESUME_FROM" ]; then
            # Logique de resume
            local found=false
            for check_module in "${INSTALL_MODULES[@]}"; do
                local check_name="${check_module%%:*}"
                if [ "$check_name" = "$RESUME_FROM" ]; then
                    found=true
                elif [ "$check_name" = "$module_name" ] && [ "$found" = false ]; then
                    status="⏸️ Ignoré (--resume-from)"
                fi
            done
        fi
        
        log_info "   $status $module_name: $module_desc"
    done
}

show_success_report() {
    local duration="$1"
    shift
    local executed_modules=("$@")
    
    log_separator "INSTALLATION TERMINÉE AVEC SUCCÈS"
    
    log_success "🎉 Installation Laravel terminée en $duration"
    log_info "📍 Répertoire: $TARGET_DIR"
    log_info "🔢 Modules exécutés: ${#executed_modules[@]}"

    # ⚖️ UNE INSTALL RÉELLE ET UNE INSTALL ENTIÈREMENT SAUTÉE RENDENT TOUTES
    # DEUX 0 — et c'est voulu (rejouer une install complète est un succès).
    # Mais elles ne se ressemblent pas, et la story 2.4 doit pouvoir les
    # distinguer sans compter des lignes de log : un smoke nightly qui mesure
    # « install < 15 min » sur une install où RIEN n'a tourné ne mesure rien.
    # Ce verdict est donc énoncé, en une ligne stable.
    if [ ${#executed_modules[@]} -eq 0 ]; then
        log_success "🟰 VERDICT: NO-OP — aucun module joué, tout était déjà franchi"
    else
        log_success "🆕 VERDICT: EXECUTED — ${#executed_modules[@]} module(s) joué(s) lors de ce passage"
    fi
    
    if [ ${#executed_modules[@]} -gt 0 ]; then
        log_info "📋 Modules installés:"
        for module in "${executed_modules[@]}"; do
            log_info "   ✅ $module"
        done
    fi
    
    # Informations finales
    if [ -d "$TARGET_DIR" ] && [ -f "$TARGET_DIR/artisan" ]; then
        cd "$TARGET_DIR"
        local laravel_version=$(get_laravel_version)
        local php_version=$(get_php_version)
        
        log_info "🔧 Versions installées:"
        log_info "   • Laravel: $laravel_version"
        log_info "   • PHP: $php_version"
    fi
    
    log_info "📄 Log complet: $LOG_FILE"
    
    # Prochaines étapes
    log_separator "PROCHAINES ÉTAPES"
    log_info "🚀 Pour commencer le développement:"
    log_info "   cd $TARGET_DIR"
    log_info "   php artisan serve"
    log_info ""
    log_info "🔧 Commandes utiles:"
    log_info "   make artisan cmd=\"migrate\"    # Migrations base de données"
    log_info "   make npm-dev                   # Développement frontend"
    log_info "   make test                      # Lancer les tests"
    log_info "   make quality-all               # Audit qualité complet"
}

show_error_report() {
    local failed_module="$1"
    shift
    local executed_modules=("$@")
    
    log_separator "ÉCHEC DE L'INSTALLATION"
    
    log_error "💥 Installation échouée au module: $failed_module"
    
    if [ ${#executed_modules[@]} -gt 0 ]; then
        log_info "✅ Modules réussis avant l'échec:"
        for module in "${executed_modules[@]}"; do
            log_info "   ✅ $module"
        done
    fi
    
    log_info "🔧 Pour reprendre l'installation:"
    log_info "   $(basename "$0")   # la reprise est automatique: $failed_module n'a pas posé sa sentinelle"
    # ⚠️ NE PAS PROMETTRE QUE --resume-from FORCE UN POINT DE REPRISE.
    # L'état PRIME désormais : `--resume-from X` ne fait que sauter ce qui
    # précède X ; un module situé APRÈS X et portant déjà sa sentinelle reste
    # sauté. Le seul drapeau qui force un rejeu est `--force`. La rédaction
    # précédente disait l'inverse, et un opérateur l'aurait crue.
    log_info "   (--resume-from $failed_module ignore ce qui PRÉCÈDE; il ne rejoue pas un module déjà franchi)"
    log_info "   (--force rejoue tout, sentinelles ignorées et réécrites)"

    log_info "🔍 Pour déboguer le problème:"
    log_info "   $(basename "$0") --only $failed_module --verbose"
    
    log_info "📄 Log complet: $LOG_FILE"
    
    # Afficher les dernières erreurs
    log_error_summary
}

# =============================================================================
# FONCTION PRINCIPALE
# =============================================================================

main() {
    # Capturer les signaux pour un nettoyage propre
    trap 'log_fatal "Installation interrompue par l'\''utilisateur"' INT TERM
    
    # Parser les arguments
    parse_arguments "$@"
    
    # Initialiser le logging avec l'ID d'installation
    export LOG_FILE="/tmp/laravel-install-$INSTALLATION_ID.log"
    init_logging "install-orchestrator"
    
    log_info "🔧 Orchestrateur d'installation Laravel démarré"
    
    # Vérifier l'environnement
    if ! is_docker_environment; then
        log_warn "⚠️ Environnement non-Docker détecté"
    fi
    
    # Lancer l'installation
    if run_installation; then
        log_success "✅ Installation terminée avec succès"
        return 0
    else
        log_fatal "❌ Installation échouée"
    fi
}

# =============================================================================
# EXÉCUTION
# =============================================================================

# Exécuter seulement si le script est appelé directement
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi