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
#   --dry-run           Simulation: aucun effet de bord hors journal
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
# C'est ICI qu'elle en trouve un.
#
# 🔴 LA RAISON ÉCRITE ICI JUSQU'AU 2026-08-22 ÉTAIT FAUSSE, ET MESURÉE TELLE.
# Elle disait : « les modules tournent en sous-processus, donc l'`export -f` de
# runtime.sh ne les atteint pas ». Sondé — `bash -c 'declare -F
# ensure_idempotent'` lancé depuis un shell qui a sourcé cette lib rend **oui** :
# bash exporte les fonctions à ses enfants via `BASH_FUNC_x%%`. La prémisse
# était donc l'inverse de la réalité, et `run_cmd` (story 2.3) en dépend
# entièrement : c'est précisément parce que l'export TRAVERSE qu'un module
# lancé en sous-processus peut router ses commandes par `run_cmd`.
#
# ⚖️ LA VRAIE RAISON DE L'ENVELOPPEMENT AU NIVEAU ORCHESTRATEUR EST LE GRAIN.
# La sentinelle a pour identité le module (`10-laravel-core-done`), et « ce
# module a-t-il été franchi ? » est une question que seul l'orchestrateur peut
# poser : lui seul connaît la liste, l'ordre, `--only`, `--resume-from` et
# `--force`. Un module qui s'auto-enveloppe déciderait de son propre saut sans
# rien savoir de la séquence.
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

# =============================================================================
# MODULES QUI SAVENT SIMULER
# =============================================================================
#
# Sous `--dry-run`, un module inscrit ici est RÉELLEMENT LANCÉ : c'est lui qui
# route ses commandes à effet par `run_cmd`, et sa simulation descend donc au
# grain de la COMMANDE (« [DRY] rm -rf … ») au lieu de s'arrêter au grain du
# module (« je simulerais 10-laravel-core »). Un module absent de cette liste
# garde l'annonce-et-saut, qui reste la garantie forte de zéro effet.
#
# ⛔ INSCRIRE UN MODULE ICI ENGAGE L'AUDIT DU MODULE ENTIER, pas de ses seules
# lignes destructrices. Un module inscrit sans audit fait exécuter POUR DE VRAI,
# sous un drapeau qui promet l'inverse, ce que personne n'a regardé — strictement
# pire que le dry-run aveugle qu'il remplace. La liste reste donc explicite et
# courte : c'est elle qui rend l'engagement visible et refusable en revue.
#
# 📋 `20-database` et `99-finalize` sont AUDITÉS MAIS NON CONVERTIS (report
# ouvert dans `_bmad-output/implementation-artifacts/deferred-work.md`, trigger
# Story 2.4). Tant qu'ils n'y sont pas, leur simulation ne dit rien des
# migrations ni des caches qu'ils joueraient.
readonly DRY_RUN_AWARE_MODULES=(
    "10-laravel-core"
)

#
# Le module sait-il simuler ? Comparaison LITTÉRALE de noms, aucun motif.
#
module_is_dry_run_aware() {
    local candidate="$1"
    local aware

    for aware in "${DRY_RUN_AWARE_MODULES[@]}"; do
        if [ "$aware" = "$candidate" ]; then
            return 0
        fi
    done

    return 1
}

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
    --dry-run           Simulation: rien n'est installé, aucune sentinelle
                        écrite. Les modules de DRY_RUN_AWARE_MODULES sont
                        LANCÉS et annoncent chaque commande à effet en
                        « [DRY] … » ; les autres sont annoncés puis sautés.
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

SIMULATION (--dry-run):
    Aucune sentinelle n'est écrite ni effacée, aucun horodatage posé, aucun
    répertoire créé ni re-chmodé, aucune version sondée (php artisan --version
    booterait l'application). Le rapport final porte le verdict DRY-RUN, jamais
    EXECUTED. Seul le journal /tmp/laravel-install-*.log est écrit: c'est le
    canal d'observation de la simulation.
    Les modules déclarés dry-run aware (voir DRY_RUN_AWARE_MODULES) tournent
    réellement et routent leurs commandes à effet par run_cmd; les autres sont
    annoncés puis sautés, et leur contenu n'est PAS décrit.

    ⚠️ LE PLAN EST RÉPARTI SUR LES DEUX FLUX. Les lignes émises par
    l'orchestrateur partent sur stderr; celles émises par un module *aware*
    sortent sur stdout, parce que execute_module le lance en "2>&1 | tee".
    La seule capture COMPLÈTE prend donc les deux:
        ./install.sh --dry-run > plan.txt 2>&1        # le plan ENTIER
        ./install.sh --dry-run 2>&1 | tee plan.txt    # idem, à l'écran aussi
        ./install.sh --dry-run > plan.txt             # INCOMPLET
        ./install.sh --dry-run 2> plan.txt            # INCOMPLET

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

            # ⛔ EN SIMULATION, LA CIBLE N'EST NI CRÉÉE NI RE-CHMODÉE.
            # Ce bloc s'exécutait AVANT toute branche `--dry-run` : un
            # `install.sh --dry-run` posait un `mkdir -p`, un `chown -R` et
            # jusqu'à un `chmod -R 777` sur la cible — trois effets de bord sous
            # le drapeau qui promet de n'en avoir aucun. La simulation DIAGNOSTIQUE
            # désormais, en nommant le chemin, et ne corrige rien.
            #
            # ⚠️ `run_cmd` N'EST PAS UTILISÉE ICI, ET C'EST DÉLIBÉRÉ.
            # `validate_arguments` tourne depuis `parse_arguments`, donc AVANT
            # `run_installation` — seul site où `INSTALL_DRY_RUN` est dérivé.
            # Un `run_cmd` posé ici lirait la variable ENCORE ABSENTE et
            # exécuterait pour de vrai. Le drapeau lu est donc la globale du
            # processus, `DRY_RUN`, qui est la seule vraie à cet instant.
            if [ "$DRY_RUN" = true ]; then
                if [ ! -d "$TARGET_DIR" ]; then
                    log_warn "🔍 [DRY-RUN] Répertoire cible absent: $TARGET_DIR — non créé."
                fi

                log_info "[DRY] mkdir -p $TARGET_DIR"
                log_info "[DRY] chown -R www-data:www-data $TARGET_DIR"
                log_info "[DRY] chmod -R 755 $TARGET_DIR"

                if [ ! -w "$TARGET_DIR" ]; then
                    log_warn "🔍 [DRY-RUN] Cible non inscriptible en l'état: $TARGET_DIR — l'installation réelle tenterait de corriger les permissions ; rien n'a été modifié."
                fi

                return 0
            fi

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
        # ⛔ AUCUN `chmod +x` SOUS SIMULATION — LE FICHIER EST VERSIONNÉ.
        # Ce `chmod` s'exécutait avant toute branche `--dry-run` : une
        # simulation modifiait le mode d'un fichier suivi par git, donc
        # `git status --porcelain` ne sortait plus vide. Et le mode d'un module
        # est une VRAIE condition d'installation : la simulation existe pour la
        # découvrir avant l'install réelle, pas pour la réparer en douce.
        if [ "$DRY_RUN" = true ]; then
            log_error "🔍 [DRY-RUN] Module non exécutable: $module_file (aucun chmod +x appliqué — corrigez le mode avant l'installation réelle)"
            return 1
        fi

        log_debug "Module non exécutable, correction..."
        chmod +x "$module_file"
    fi

    log_step_start "$module_name" "$module_desc"
    local start_time=$(date +%s)

    # ---------------------------------------------------------------
    # Mode dry-run : annonce-et-saut, SAUF pour un module qui sait simuler
    # ---------------------------------------------------------------
    # Un module non *aware* est annoncé puis SAUTÉ : il ne tourne jamais, ce
    # qui reste la garantie forte de zéro effet. Un module inscrit dans
    # `DRY_RUN_AWARE_MODULES` est au contraire LANCÉ POUR DE VRAI : il lit
    # `INSTALL_DRY_RUN` (exporté par `run_installation`) et route ses commandes
    # à effet par `run_cmd`. C'est ce qui fait descendre la simulation du grain
    # « module » au grain « commande ».
    #
    # ⛔ Le `sleep 1` qui « simulait un temps d'exécution » est retiré : il ne
    # simulait rien — 11 secondes d'attente pour une mesure fausse.
    if [ "$DRY_RUN" = true ] && ! module_is_dry_run_aware "$module_name"; then
        log_info "🔍 [DRY-RUN] Simulation du module $module_name"
        log_info "📂 Répertoire cible: $TARGET_DIR"
        log_info "📜 Script: $module_file"
        log_info "⏭️ [DRY-RUN] Module NON lancé (pas dans DRY_RUN_AWARE_MODULES)"
        local duration=$(calculate_duration $start_time)
        log_step_end "$module_name" "$duration"
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        log_info "🔍 [DRY-RUN] Module $module_name est DRY-RUN AWARE — lancé pour de vrai, ses commandes à effet sortent en [DRY]"
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

    # ⚖️ TROIS CHOSES DIFFÉRENTES SOUS SIMULATION, DONC TROIS COMPTEURS.
    # `executed_modules` répondait pour les trois, et le rapport final en
    # déduisait « 11 module(s) joué(s) » — alors qu'aucun n'avait rien joué.
    #   • `simulated_modules` : module *aware*, RÉELLEMENT lancé, effets routés ;
    #   • `announced_modules` : module non *aware*, annoncé puis SAUTÉ ;
    #   • `skipped_modules`   : déjà franchi (sentinelle), commun aux deux modes.
    local simulated_modules=()
    local announced_modules=()
    # 🔴 QUATRIÈME POPULATION, OUBLIÉE PAR LE DÉCOUPAGE : un module écarté par
    # `--skip-prereq` n'entrait dans AUCUN compteur, et le rapport cessait donc
    # de rendre compte de toute la liste — un module disparaissait sans trace.
    local bypassed_modules=()

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

    # ⛔ MÊME SITE, MÊME RAISON, ET C'EST LE SEUL POUR `INSTALL_DRY_RUN` AUSSI.
    # `DRY_RUN` est une globale de l'orchestrateur, jamais exportée : sondé le
    # 2026-08-22, un enfant voit `<absent>`. Un module *aware* tourne en
    # SOUS-PROCESSUS, et c'est `INSTALL_DRY_RUN` — dérivé ici, une fois, sur le
    # chemin d'exécution — qui lui dit de router ses commandes par `run_cmd`.
    # Le dériver ailleurs (dans la branche `--dry-run` de `parse_arguments`,
    # par exemple) recréerait exactement les DEUX sources de vérité qu'on vient
    # de supprimer pour `INSTALL_FORCE`.
    export INSTALL_DRY_RUN="$DRY_RUN"

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
            bypassed_modules+=("$module_name")
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

        # ⚖️ SOUS `--dry-run --force`, LA SUPPRESSION EST ANNONCÉE, PAS FAITE.
        # Le plan omettait ces `rm -f` : il décrivait donc une exécution qui
        # n'était pas celle qu'`install.sh --force` aurait menée. `run_cmd` lit
        # `INSTALL_DRY_RUN`, déjà exporté au-dessus — même primitive, même
        # frontière. Le `[ -f ]` évite d'annoncer la suppression d'un fichier
        # qui n'existe pas (`rm -f` y est déjà un no-op).
        if [ "$FORCE" = true ] && [ -f "$sentinel" ]; then
            run_cmd rm -f "$sentinel" || true
        fi

        # Relevé AVANT l'appel : `ensure_idempotent` rend 0 aussi bien pour
        # « déjà franchi » que pour « joué avec succès ». Sans ce relevé, le
        # rapport final compterait comme exécuté un module jamais lancé.
        local already_done=false
        if [ -f "$sentinel" ] && [ "$FORCE" != true ]; then
            already_done=true
        fi

        # ⛔ EN SIMULATION, AUCUNE SENTINELLE N'EST NI ÉCRITE NI EFFACÉE.
        # Envelopper `execute_module` dans `ensure_idempotent` ferait ÉCRIRE la
        # sentinelle d'un module qui n'a rien accompli, et l'install réelle
        # suivante le sauterait. Une simulation qui laisse un effet de bord
        # n'est pas une simulation — c'est la promesse même du drapeau (Epic 2 :
        # « --dry-run sans aucun effet de bord, ni fichier, ni conteneur »).
        #
        # ⚖️ L'INVARIANT NE RECULE PAS QUAND LE MODULE EST *AWARE*, ET C'EST LÀ
        # QU'IL COMPTE LE PLUS. Depuis la story 2.3, `execute_module` LANCE
        # réellement les modules de `DRY_RUN_AWARE_MODULES` — la phrase d'avant
        # (« rend 0 sans rien faire ») n'est donc plus vraie et a été retirée
        # plutôt que laissée à côté d'un code qui la contredit. Un module *aware*
        # qui va jusqu'au bout de sa simulation n'a rien INSTALLÉ : lui poser sa
        # sentinelle ferait sauter, à l'install réelle, le seul module dont
        # l'échec est une perte de données.
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
                    # ⚖️ TOUS LES MODULES FRANCHIS, PAS SEULEMENT LES SIMULÉS.
                    # Le découpage en trois compteurs avait laissé ce site
                    # derrière : un seul module étant *aware*, un échec au 11ᵉ
                    # annonçait « aucun module réussi avant l'échec » alors que
                    # dix avaient été franchis.
                    show_error_report "$module_name" \
                        "${simulated_modules[@]}" "${announced_modules[@]}"

                    return "$dry_status"
                fi

                # ⛔ NE JAMAIS REVERSER DANS `executed_modules` : c'est ce
                # tableau que `show_success_report` traduit en « Modules
                # installés » et en « VERDICT: EXECUTED ». Un module simulé
                # n'a rien installé, et un module annoncé-puis-sauté n'a même
                # pas tourné — les confondre était la moitié du mensonge.
                if module_is_dry_run_aware "$module_name"; then
                    simulated_modules+=("$module_name")
                else
                    announced_modules+=("$module_name")
                fi
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

    local duration=$(calculate_duration $start_time)

    # ⛔ UNE SIMULATION NE REND PAS LE RAPPORT D'UNE INSTALLATION.
    # `show_success_report` imprimait « 🎉 Installation Laravel terminée »,
    # « 🆕 VERDICT: EXECUTED — 11 module(s) joué(s) », listait les onze modules
    # sous « Modules installés », puis entrait dans `cd "$TARGET_DIR"` +
    # `get_laravel_version` — c'est-à-dire `php artisan --version`, qui BOOTE
    # l'application et écrit dans `storage/logs/` du conteneur. Un rapport
    # mensonger ET un effet de bord, dans la fonction de clôture d'un drapeau
    # qui promet ni l'un ni l'autre.
    if [ "$DRY_RUN" = true ]; then
        show_simulation_report "$duration"
        return 0
    fi

    # Rapport de succès
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
        log_info "   • Modules qui savent simuler: ${DRY_RUN_AWARE_MODULES[*]}"
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

#
# Rapport de clôture d'une SIMULATION.
#
# ⚠️ LIT SES TROIS TABLEAUX PAR PORTÉE DYNAMIQUE, et c'est écrit plutôt que
# subi : `simulated_modules`, `announced_modules` et `skipped_modules` sont des
# `local` de `run_installation`, donc visibles ici (bash n'a pas de portée
# lexicale). Les passer en arguments demanderait un protocole de délimiteur
# pour trois tableaux — plus de code, et une occasion de plus de mentir sur qui
# est dans quel groupe.
#
# ⛔ AUCUN `cd`, AUCUN SONDAGE DE VERSION : `get_laravel_version` lance
# `php artisan --version`, ce qui boote l'application dans la cible.
#
# ⚖️ QUATRE COMPTEURS, PARCE QU'IL Y A QUATRE POPULATIONS. Leur somme doit
# couvrir toute la liste des modules considérés : un module qui n'entrerait dans
# aucun disparaîtrait du rapport sans que rien ne le signale.
#
# Le verdict est une ligne STABLE et DISTINCTE de celles de l'install réelle
# (`VERDICT: EXECUTED` / `VERDICT: NO-OP`), pour que la story 2.4 puisse la lire
# sans compter des lignes de log.
#
show_simulation_report() {
    local duration="$1"

    log_separator "SIMULATION TERMINÉE — AUCUNE INSTALLATION EFFECTUÉE"

    log_success "🔍 VERDICT: DRY-RUN — rien n'a été installé, aucune sentinelle écrite"
    log_info "📍 Répertoire cible (inchangé): $TARGET_DIR"
    log_info "🗂️ Racine d'état (inchangée): $INSTALL_STATE_DIR"
    log_info "🔢 Modules réellement simulés: ${#simulated_modules[@]}"
    log_info "🔢 Modules annoncés sans exécution: ${#announced_modules[@]}"
    log_info "🔢 Modules déjà franchis (sentinelle): ${#skipped_modules[@]}"
    log_info "🔢 Modules écartés par une option (--skip-prereq): ${#bypassed_modules[@]}"

    if [ ${#simulated_modules[@]} -gt 0 ]; then
        log_info "🔬 Simulés au grain de la commande (voir les lignes [DRY]):"
        local module
        for module in "${simulated_modules[@]}"; do
            log_info "   🔬 $module"
        done
    fi

    if [ ${#announced_modules[@]} -gt 0 ]; then
        log_info "📣 Annoncés puis sautés (hors DRY_RUN_AWARE_MODULES — leur"
        log_info "   contenu n'est PAS décrit par cette simulation):"
        local module
        for module in "${announced_modules[@]}"; do
            log_info "   📣 $module"
        done
    fi

    if [ ${#skipped_modules[@]} -gt 0 ]; then
        log_info "⏭️ Déjà franchis, ils seraient sautés:"
        local module
        for module in "${skipped_modules[@]}"; do
            log_info "   ⏭️ $module"
        done
    fi

    if [ ${#bypassed_modules[@]} -gt 0 ]; then
        log_info "🚫 Écartés par une option de ligne de commande:"
        local module
        for module in "${bypassed_modules[@]}"; do
            log_info "   🚫 $module"
        done
    fi

    log_info "⏱️ Durée de la simulation: $duration"
    log_info "📄 Plan complet: $LOG_FILE"
    log_info ""
    log_info "⚠️ Le plan est réparti sur STDOUT et STDERR (l'orchestrateur"
    log_info "   journalise sur stderr, les modules *aware* sur stdout via tee)."
    log_info "   Capture complète: « > plan.txt 2>&1 » ou « 2>&1 | tee plan.txt »."
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
        # ⛔ « ✅ Installation terminée avec succès » est FAUX sous simulation,
        # et cette ligne-ci est la DERNIÈRE que l'opérateur lit. Elle avait
        # survécu au correctif de `show_success_report`, un cran plus haut.
        if [ "$DRY_RUN" = true ]; then
            log_success "🔍 Simulation terminée — aucune installation effectuée"
        else
            log_success "✅ Installation terminée avec succès"
        fi

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