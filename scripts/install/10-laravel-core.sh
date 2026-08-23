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
# `die` — utilisé par le refus de nettoyage ci-dessous (story 2.2).
# `run_cmd` — la simulation de ce module (story 2.3) : voir plus bas.
source "$SCRIPT_DIR/../lib/runtime.sh"

# Initialiser le logging
init_logging "10-laravel-core"

# =============================================================================
# SIMULATION (--dry-run) — CE MODULE EST *DRY-RUN AWARE*
# =============================================================================
#
# Il est le SEUL module inscrit dans `DRY_RUN_AWARE_MODULES` (`install.sh`).
# Conséquence directe : sous `--dry-run`, l'orchestrateur ne l'annonce pas puis
# ne le saute pas — il le LANCE POUR DE VRAI. Ce sont les commandes ci-dessous
# qui décident, une par une, de s'exécuter ou de s'annoncer.
#
# ⛔ CE QUE CET ENGAGEMENT COÛTE, ET POURQUOI IL N'EST PRIS QUE POUR CE MODULE.
# Inscrire un module engage l'audit du module ENTIER, pas de ses seules lignes
# destructrices : ce qui n'est pas routé par `run_cmd` s'exécute réellement,
# sous un drapeau qui promet l'inverse. Les 1132 lignes de ce fichier ont donc
# été relues intégralement. Ce module est le seul dont le mode de défaillance
# est une PERTE DE DONNÉES IRRÉVERSIBLE (`rm -rf --` de `clean_target_directory`),
# ce qui justifie de payer cet audit ici avant partout ailleurs.
#
# ⚠️ LA SIMULATION S'ARRÊTE LÀ OÙ L'ÉTAT MANQUE, ET ELLE LE DIT.
# Une post-condition (« le skeleton est là », « le répertoire est vide », « la
# copie est identique ») décrit un travail que la simulation n'a pas fait :
# la vérifier ferait ÉCHOUER une simulation parfaitement saine. Chaque endroit
# où la séquence s'interrompt journalise ce qu'elle n'a pas joué, plutôt que de
# rendre 0 en silence.
#

#
# La simulation est-elle active ? Lit `INSTALL_DRY_RUN`, exporté UNE fois par
# `run_installation` — jamais `DRY_RUN`, qui est une globale de l'orchestrateur
# et n'existe pas dans ce sous-processus.
#
dry_run_active() {
    [ "${INSTALL_DRY_RUN:-false}" = true ]
}

#
# `run_cmd` pour une commande dont les ERREURS sont ATTENDUES et doivent rester
# silencieuses (`chown`/`chmod` sur des fichiers d'un autre propriétaire).
#
# ⚠️ POURQUOI CE DÉTOUR PLUTÔT QU'UN `2>/dev/null` SUR `run_cmd`.
# `log_info` écrit sur STDERR (`logging.sh:104`) : `run_cmd cmd 2>/dev/null`
# avalerait aussi la ligne `[DRY] …`, c'est-à-dire la SEULE trace que la
# simulation produit. Le silence est donc appliqué à l'exécution RÉELLE, jamais
# à l'annonce. Le code réel est rendu, comme `run_cmd` — l'appelant décide.
#
run_cmd_quiet() {
    if dry_run_active; then
        run_cmd "$@"
        return 0
    fi

    local status=0
    "$@" 2>/dev/null || status=$?

    return "$status"
}

#
# `run_cmd` dont la sortie est DUPLIQUÉE dans le journal, et dont le code rendu
# est CELUI DE LA COMMANDE.
#
# 🔴 EXISTE PARCE QUE `cmd 2>&1 | tee -a "$LOG_FILE"` REND LE CODE DE `tee`.
# Sept sites de ce module testaient `if ! cmd 2>&1 | tee …` : la condition ne
# pouvait donc JAMAIS être vraie, et sept branches d'échec étaient mortes —
# repli `laravel new`, échec de `composer install`, échec de la copie `cp -a`
# vers la cible, et échec de `key:generate` que l'appelant traite pourtant
# comme FATAL. Une clé d'application non générée passait pour un succès.
# C'est exactement le piège que le docblock de `run_cmd` venait de décrire, et
# qui vivait dans le fichier d'à côté.
#
# `${PIPESTATUS[0]}` — même idiome que `execute_module` dans l'orchestrateur.
#
run_cmd_logged() {
    # ⛔ PAS DE `tee` SOUS SIMULATION. `log_info` écrit DÉJÀ dans `$LOG_FILE` ;
    # le pipeline l'y ajoutait une SECONDE fois, avec ses échappements ANSI.
    # Le plan doit se relire, pas se dédoubler.
    if dry_run_active; then
        run_cmd "$@"
        return 0
    fi

    local status=0

    run_cmd "$@" 2>&1 | tee -a "$LOG_FILE"
    status=${PIPESTATUS[0]}

    return "$status"
}

#
# Journalise un succès… SEULEMENT s'il a eu lieu.
#
# ⛔ SOUS SIMULATION, « ✅ Clé d'application générée » EST UN MENSONGE.
# `main()` avait été soigneusement rendue honnête ; les fonctions qu'elle
# appelle, non. C'est le motif « phrase fausse à côté d'un code juste » que
# cette story existe pour combattre, reproduit dans le fichier qu'elle corrige.
#
log_applied() {
    if dry_run_active; then
        log_info "🔍 [DRY-RUN] NON joué — $1"
        return 0
    fi

    log_success "✅ $1"
}

#
# Même chose au niveau DEBUG, pour les traces internes.
#
log_applied_debug() {
    if dry_run_active; then
        log_debug "🔍 [DRY-RUN] NON joué — $1"
        return 0
    fi

    log_debug "$1"
}

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
            run_cmd_quiet mkdir -p "$target_dir" || true
        fi
        
        # Corriger automatiquement les permissions pour Docker
        log_debug "Correction des permissions Docker pour $target_dir"
        run_cmd_quiet chown -R www-data:www-data "$target_dir" || true
        run_cmd_quiet chmod -R 755 "$target_dir" || true
        
        # Vérifier que les permissions sont maintenant correctes
        if [ ! -w "$target_dir" ]; then
            # ⛔ EN SIMULATION, RIEN N'A ÉTÉ CHMODÉ : la cible est exactement
            # dans l'état où l'opérateur l'a laissée. Escalader jusqu'au
            # `chmod -R 777` reviendrait à modifier la cible pour satisfaire la
            # post-condition d'une correction qu'on vient de ne pas faire.
            if dry_run_active; then
                log_warn "🔍 [DRY-RUN] Cible non inscriptible en l'état: $target_dir — aucune correction appliquée."
            else
                log_error "Permissions encore incorrectes après correction"
                log_debug "Tentative de correction en mode root"
                # En dernier recours, donner les permissions complètes
                chmod -R 777 "$target_dir" 2>/dev/null || true

                if [ ! -w "$target_dir" ]; then
                    log_fatal "Impossible de corriger les permissions pour: $target_dir"
                fi
            fi
        fi
        
        log_applied_debug "Permissions Docker configurées avec succès"
    else
        # Validation classique pour les environnements non-Docker
        local parent_dir="$(dirname "$target_dir")"
        if [ ! -w "$parent_dir" ]; then
            log_fatal "Pas de permission d'écriture dans $parent_dir"
        fi
        
        # Créer le répertoire s'il n'existe pas
        run_cmd mkdir -p "$target_dir" || log_fatal "Impossible de créer: $target_dir"
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
    #
    # ⛔ POST-CONDITION D'UNE INSTALLATION QUI N'A PAS EU LIEU.
    # Sous simulation, `install_laravel_via_composer` n'a rien téléchargé ni
    # copié : exiger `artisan` et un `php artisan --version` qui répond ferait
    # échouer une simulation SAINE, et pire, le `chmod +x artisan` de la
    # validation toucherait un fichier versionné.
    if dry_run_active; then
        log_info "🔍 [DRY-RUN] Validation post-installation non jouée — rien n'a été installé."
    elif ! validate_laravel_installation "$target_dir"; then
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
        # Même règle que `patch_fresh_laravel_skeleton` : sous simulation, un
        # répertoire absent est un CONSTAT à rapporter, pas une mort à
        # provoquer — la simulation ne l'a pas créé, c'est tout ce que ça dit.
        if dry_run_active; then
            log_warn "🔍 [DRY-RUN] Répertoire absent: $laravel_dir — configuration d'environnement non jouée."
            return 0
        fi

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
# Nom de base de la racine d'état, telle qu'elle apparaît DANS la cible.
#
# L'orchestrateur peut la déplacer par `INSTALL_STATE_DIR` ; le module n'en voit
# que la variable d'environnement. Deux cas seulement nous intéressent ici :
# elle est sous la cible (il faut la préserver), ou elle est ailleurs (rien à
# faire). Comparer les chemins ABSOLUS, jamais les chaînes brutes : un
# `INSTALL_STATE_DIR` relatif ou avec un `//` ferait échouer un `case` textuel.
#
# 🔴 LA RACINE D'ÉTAT EST TYPÉE : un VRAI RÉPERTOIRE, et pas un lien.
# Même discipline qu'`ensure_idempotent`, qui refuse explicitement une
# sentinelle-répertoire (`runtime.sh:231`) : lecture et écriture doivent parler
# du même objet. Sans ce typage, mesuré à la revue 2 :
#   • un FICHIER nommé `.install-state` était exclu de la mesure de vacuité ET
#     de la suppression — répertoire réputé vide, fichier resté, et le
#     `composer create-project` suivant échouait sur un répertoire non vide ;
#   • un SYMLINK `.install-state` pointant vers un dossier interne faisait
#     supprimer le dossier RÉEL pendant que le journal annonçait « racine
#     d'état préservée ».
# Ce qui n'est pas un vrai répertoire n'est donc pas une racine d'état : c'est
# une entrée ordinaire, comptée et supprimée comme telle (pour un lien, seul le
# lien part — jamais sa cible).
#
install_state_basename_in() {
    local target_dir="$1"
    local state_dir="${INSTALL_STATE_DIR:-$target_dir/.install-state}"

    local absolute_target
    absolute_target="$(cd "$target_dir" 2>/dev/null && pwd)" || return 1

    # ⚠️ Le `|| return 1` d'une AFFECTATION porte le statut de la DERNIÈRE
    # substitution — ici `basename`, qui rend toujours 0. La garde était donc du
    # code mort (relevé revue 2). Le `cd` est évalué séparément, ce qui la rend
    # vivante.
    local state_parent
    state_parent="$(cd "$(dirname "$state_dir")" 2>/dev/null && pwd)" || return 1

    local state_name
    state_name="$(basename "$state_dir")"

    if [ "$state_parent" != "$absolute_target" ]; then
        return 1
    fi

    local candidate="$absolute_target/$state_name"

    if [ -L "$candidate" ]; then
        log_warn "Racine d'état ignorée : $candidate est un lien symbolique, pas un répertoire."
        return 1
    fi

    if [ ! -d "$candidate" ]; then
        if [ -e "$candidate" ]; then
            log_warn "Racine d'état ignorée : $candidate existe mais n'est pas un répertoire."
        fi
        return 1
    fi

    echo "$state_name"
    return 0
}

#
# Entrées d'un répertoire, racine d'état exclue — noms de base, un par ligne.
#
# 🔴 `[ -e ]` SEUL PERD LES LIENS SYMBOLIQUES CASSÉS (relevé revue 2) : `-e`
# suit le lien, donc il est faux sur un lien pendant. Une cible n'en contenant
# qu'un était jugée VIDE, tout le nettoyage était sauté, la fonction rendait 0
# en journalisant « nettoyé avec succès », et `composer create-project`
# échouait ensuite sur un répertoire non vide. `-e || -L` voit les deux.
#
# Cette énumération sert À LA FOIS la mesure de vacuité et la post-condition :
# une seule lecture, donc pas de divergence possible entre « ce qu'on a compté »
# et « ce qu'on vérifie avoir supprimé ».
#
list_target_entries() {
    local target_dir="$1"
    local state_basename="$2"

    local entry name
    for entry in "$target_dir"/* "$target_dir"/.*; do
        # `-e` pour ce qui existe, `-L` pour les liens pendants que `-e` rate.
        # Le `glob` non apparié se rend lui-même : les deux tests l'écartent.
        if [ ! -e "$entry" ] && [ ! -L "$entry" ]; then
            continue
        fi

        name="${entry##*/}"

        if [ "$name" = "." ] || [ "$name" = ".." ]; then
            continue
        fi

        if [ -n "$state_basename" ] && [ "$name" = "$state_basename" ]; then
            continue
        fi

        printf '%s\n' "$name"
    done
}

#
# Nettoyer le répertoire cible avant installation
#
# 🔴 CE CHEMIN ÉTAIT DESTRUCTEUR SANS CONDITION (story 2.2, boucle 1).
# Il n'est atteint que lorsque `is_laravel_installed` rend faux — c'est-à-dire
# exactement l'état d'une install crashée en plein `composer create-project` :
# un `vendor/` à moitié rempli, un `composer.json` déjà écrit, mais pas encore
# les quatre fichiers de `LARAVEL_CORE_FILES`. Le `find -delete` d'alors
# effaçait ce travail en silence, à chaque relance.
#
# 🔴 ET IL DÉTRUISAIT LA RACINE D'ÉTAT ELLE-MÊME (revue 1).
# PROUVÉ PAR EXÉCUTION : une cible portant
# `.install-state/{00-prerequisites-done,05-composer-setup-done,started-at}`
# ressortait avec **0** fichier d'état et un code retour **0**. Ce n'est pas un
# cas tordu, c'est le chemin NOMINAL d'un fork-streamer : après les modules 00
# et 05, la cible n'est JAMAIS « vraiment vide ».
#
# 🔴 TROISIÈME ITÉRATION DU MÊME DÉFAUT, ET C'EST ELLE QUI INSTRUIT (revue 2).
# Les deux premières parades employaient un MOTEUR DE MOTIFS là où un littéral
# était voulu :
#   1. `find -mindepth 1 -delete` nu — aucune exclusion ;
#   2. `-path … -prune -o` — `-delete` implique `-depth`, sous lequel `-prune`
#      est un no-op ;
#   3. `-not -path "$target/$etat"` — `-path` prend un GLOB, pas une chaîne.
#      Mesuré : une cible nommée `pro[1]jet` ressortait à `etat=0`,
#      `started-at` DÉTRUIT, code retour 0. Les crochets font une classe de
#      caractères ; le motif ne correspond plus à son propre chemin, donc rien
#      n'est exclu. C'est EXACTEMENT le mécanisme du défaut corrigé en sens
#      inverse dans `install-lockfile.sh` (un `grep` appliquant une regex à
#      `projet[1]_node`) — deux fois la même erreur dans la même story.
#
# La parade retenue n'a PLUS DE MOTEUR DE MOTIFS DU TOUT : on supprime les
# entrées énumérées, une par une, par comparaison littérale de noms de base.
# Aucun glob, aucune regex, donc aucun chemin ne peut s'y soustraire.
#
clean_target_directory() {
    local target_dir="$1"

    log_debug "Nettoyage du répertoire: $target_dir"

    # Nom à préserver, ou chaîne vide si la racine d'état vit ailleurs (ou
    # n'est pas un vrai répertoire).
    local state_basename=""
    state_basename="$(install_state_basename_in "$target_dir")" || state_basename=""

    if [ -n "$state_basename" ]; then
        log_debug "Racine d'état préservée: $target_dir/$state_basename"
    fi

    # Contenu de la cible, RACINE D'ÉTAT EXCLUE. C'est cette liste — et non
    # `ls -A` nu — qui décide si le répertoire est « vraiment vide » : sinon la
    # présence des sentinelles suffirait à déclencher le nettoyage qui les
    # efface, ce qui est précisément le défaut corrigé ici.
    local entries=()
    local name
    while IFS= read -r name; do
        [ -n "$name" ] && entries+=("$name")
    done < <(list_target_entries "$target_dir" "$state_basename")

    if [ ${#entries[@]} -gt 0 ]; then
        log_debug "Contenu actuel du répertoire (hors racine d'état): ${entries[*]}"

        # Marqueurs d'une installation PARTIELLE : leur présence prouve qu'un
        # travail a déjà eu lieu ici, et `is_laravel_installed` a pourtant rendu
        # faux. Effacer serait détruire une reprise possible.
        #
        # ⚖️ La liste va DÉLIBÉRÉMENT au-delà de `composer.json`/`vendor/`.
        # Effacer le `.env` d'un opérateur — clé d'application, identifiants de
        # base, secrets d'API — est du même ordre qu'effacer son `vendor/`, à
        # ceci près que `vendor/` se réinstalle et qu'un `.env` ne se retrouve
        # pas. `storage/` porte les uploads et les logs ; `database/` les
        # migrations écrites à la main.
        local candidates=(
            "composer.json"
            "composer.lock"
            ".env"
            "artisan"
            "vendor"
            "storage"
            "database"
            "app"
            "node_modules"
        )

        local partial_markers=()
        local candidate

        for candidate in "${candidates[@]}"; do
            # `-e || -L` ici aussi : un `.env` remplacé par un lien pendant
            # reste la trace d'un travail de l'opérateur.
            if [ -e "$target_dir/$candidate" ] || [ -L "$target_dir/$candidate" ]; then
                if [ -d "$target_dir/$candidate" ] && [ ! -L "$target_dir/$candidate" ]; then
                    partial_markers+=("$candidate/")
                else
                    partial_markers+=("$candidate")
                fi
            fi
        done

        if [ ${#partial_markers[@]} -gt 0 ]; then
            if [ "${INSTALL_FORCE:-false}" = "true" ]; then
                log_warn "🧨 INSTALL_FORCE : nettoyage autorisé malgré une installation partielle (${partial_markers[*]})"
            else
                # ⚠️ LE MESSAGE NOMME LES DEUX SORTIES, et pas seulement `--force`.
                # Ce module s'exécute aussi SEUL (`install.sh --only 10-laravel-core`
                # le lance en sous-processus, et un opérateur peut l'appeler
                # directement) : il n'a alors AUCUN drapeau `--force` à offrir.
                # La seule sortie y est la variable d'environnement, que la
                # rédaction précédente passait sous silence (relevé revue 2).
                die "Refus de nettoyer $target_dir : installation Laravel partielle détectée (${partial_markers[*]}). Aucun fichier n'a été supprimé. Sorties possibles : relancer l'installeur avec --force, exporter INSTALL_FORCE=true si vous lancez ce module seul, ou vider le répertoire à la main."
            fi
        fi

        # ⚠️ Le message ne promet la préservation QUE lorsqu'il y a une racine
        # d'état à préserver. La rédaction précédente l'annonçait toujours, y
        # compris quand `.install-state` s'était révélé n'être pas un
        # répertoire — une phrase fausse à côté d'un code juste, le motif que
        # cette story passe son temps à corriger.
        if [ -n "$state_basename" ]; then
            log_info "Nettoyage du répertoire $target_dir (racine d'état $state_basename préservée)..."
        else
            log_info "Nettoyage complet du répertoire $target_dir (aucune racine d'état à préserver)..."
        fi

        # ⛔ SUPPRESSION LITTÉRALE, ENTRÉE PAR ENTRÉE — AUCUN MOTEUR DE MOTIFS.
        # `entries` a été construite par comparaison de noms de base, la racine
        # d'état déjà écartée. Rien ici n'interprète `*`, `?` ni `[…]`, donc
        # aucun chemin de cible ne peut contourner l'exclusion — c'est la seule
        # propriété que les trois parades précédentes n'avaient pas.
        # `rm -rf --` : le `--` protège d'un nom commençant par `-`.
        #
        # ⛔ ET C'EST LA LIGNE QUI JUSTIFIE À ELLE SEULE QUE CE MODULE SOIT LE
        # PREMIER (ET LE SEUL) À SAVOIR SIMULER. Sous `--dry-run`, `run_cmd`
        # NOMME chaque entrée qui partirait — `[DRY] rm -rf -- <chemin>` — et
        # n'en efface aucune. Jusqu'ici la simulation annonçait « je simulerais
        # 10-laravel-core » sans jamais dire CE QU'ELLE EFFACERAIT.
        local doomed
        for doomed in "${entries[@]}"; do
            run_cmd_quiet rm -rf -- "${target_dir:?}/${doomed:?}" || true
        done

        # ⛔ EN SIMULATION, RIEN N'A ÉTÉ SUPPRIMÉ : la post-condition « le
        # répertoire est vide » est structurellement fausse et rendrait 1 sur
        # une simulation parfaitement saine — donc « Impossible de nettoyer le
        # répertoire cible », un échec inventé par la mesure elle-même.
        if dry_run_active; then
            log_info "🔍 [DRY-RUN] ${#entries[@]} entrée(s) auraient été supprimées — vérification de vacuité non jouée."
            return 0
        fi

        # Vérifier que le répertoire est vide — MÊME énumération que ci-dessus,
        # donc mêmes règles : racine d'état exclue, liens pendants vus.
        local remaining=()
        while IFS= read -r name; do
            [ -n "$name" ] && remaining+=("$name")
        done < <(list_target_entries "$target_dir" "$state_basename")

        if [ ${#remaining[@]} -gt 0 ]; then
            log_warn "Fichiers restants après nettoyage: ${remaining[*]}"
            return 1
        fi
    fi

    log_debug "Répertoire nettoyé avec succès"
    return 0
}

#
# Patch PRE-INSTALL du `composer.json` du skeleton, dans le répertoire courant.
#
# ⚠️ ENFERMÉE DANS UNE FONCTION POUR POUVOIR ÊTRE ROUTÉE PAR `run_cmd`.
# `run_cmd python3 << 'PYEOF'` aurait laissé le shell appelant traiter le
# document en-place — et surtout, la ligne annoncée aurait été un `[DRY]
# python3` nu, qui ne dit rien de ce qui serait écrit. Le nom de la fonction,
# lui, nomme la modification.
#
patch_skeleton_composer_json_preinstall() {
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
    run_cmd_quiet rm -rf "$temp_dir" || true
    
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

    # 🔴 CETTE BRANCHE DE REPLI ÉTAIT MORTE, ET ELLE REVIT (relevé revue 1).
    # `if ! cmd 2>&1 | tee -a "$LOG_FILE"` testait le code de `tee`, jamais
    # celui de `composer` : le repli `laravel new` ne pouvait pas se déclencher.
    # `run_cmd_logged` rend `${PIPESTATUS[0]}`. Conséquence assumée : un échec
    # réel de `composer create-project` déclenche désormais VRAIMENT le repli,
    # ce que le code annonçait depuis toujours.
    local use_fallback=false
    if ! run_cmd_logged eval "$laravel_cmd"; then
        log_warn "Échec avec composer create-project, tentative avec l'installeur Laravel..."
        use_fallback=true

        # Fallback: utiliser l'installeur Laravel global (installe les dépendances)
        log_info "Installation de l'installeur Laravel globalement..."
        if ! run_cmd_logged composer global require laravel/installer; then
            log_error "Impossible d'installer l'installeur Laravel globalement"
            run_cmd_quiet rm -rf "$temp_dir" || true
            return 1
        fi

        # ⚠️ LE CHEMIN DU BINAIRE N'EST PLUS FIGÉ. `/var/composer/vendor/bin`
        # est le `COMPOSER_HOME` de CE conteneur ; hors de lui, le repli
        # échouait sur un chemin inexistant après avoir installé l'installeur.
        local laravel_installer_bin="${LARAVEL_INSTALLER_BIN:-/var/composer/vendor/bin/laravel}"

        if [ ! -x "$laravel_installer_bin" ]; then
            laravel_installer_bin="$(command -v laravel 2>/dev/null || true)"
        fi

        if [ -z "$laravel_installer_bin" ] || [ ! -x "$laravel_installer_bin" ]; then
            log_error "Installeur Laravel introuvable après installation globale (essayé: ${LARAVEL_INSTALLER_BIN:-/var/composer/vendor/bin/laravel}, puis le PATH)"
            run_cmd_quiet rm -rf "$temp_dir" || true
            return 1
        fi

        local laravel_new_cmd="$laravel_installer_bin new \"$temp_dir\" --no-interaction --force"
        log_debug "Commande Laravel new: $laravel_new_cmd"

        if ! run_cmd_logged eval "$laravel_new_cmd"; then
            log_error "Échec de l'installation Laravel avec toutes les méthodes"
            run_cmd_quiet rm -rf "$temp_dir" || true
            return 1
        fi

        # ⛔ LA MAJEURE EST VÉRIFIÉE, PAS PROMISE. Le chemin principal épingle
        # « ^12.0 » dans son `composer create-project` ; `laravel new` n'épingle
        # RIEN et suit la dernière version publiée. Le repli pouvait donc
        # installer une majeure que rien dans ce dépôt n'a éprouvée, en silence.
        if ! dry_run_active \
           && ! grep -q '"laravel/framework"[[:space:]]*:[[:space:]]*"\^12' "$temp_dir/composer.json" 2>/dev/null; then
            log_error "Le repli « laravel new » a produit une majeure non conforme (^12.0 attendu) — refus."
            run_cmd_quiet rm -rf "$temp_dir" || true
            return 1
        fi
    fi

    # Vérifier que le skeleton est présent
    if [ ! -f "$temp_dir/composer.json" ]; then
        # ⛔ POINT D'ARRÊT DE LA SIMULATION, ET IL EST NATUREL PLUTÔT QU'AJOUTÉ.
        # Tout ce qui suit — patch du skeleton, `composer install`, copie vers
        # la cible, permissions finales — opère sur un `$temp_dir` que la
        # simulation n'a pas créé. Le premier `cd "$temp_dir"` tuerait le module
        # sous `set -e`, sur un échec que la simulation aurait inventé.
        if dry_run_active; then
            log_info "🔍 [DRY-RUN] Skeleton non téléchargé (simulation) — patch pre-install, composer install, copie vers $target_dir et permissions finales NON joués."
            return 0
        fi

        log_error "Skeleton Laravel invalide (composer.json manquant)"
        run_cmd_quiet rm -rf "$temp_dir" || true
        return 1
    fi

    # Étape 2 : Patcher composer.json AVANT le premier composer install.
    # (uniquement pour le path principal --no-install ; le fallback laravel new
    #  a déjà ses packages installés, patch_fresh_laravel_skeleton s'en chargera)
    if [ "$use_fallback" = false ]; then
        log_info "🔧 Patch pre-install du skeleton (suppression phpunit/pint/sail)..."
        cd "$temp_dir"
        # `if run_cmd …` et non `run_cmd …` suivi de `[ $? -eq 0 ]` : sous
        # `set -e`, la seconde forme tue le module avant d'atteindre le test —
        # la branche « patch échoué » n'aurait jamais pu s'exécuter.
        if run_cmd patch_skeleton_composer_json_preinstall; then
            log_applied "Pre-install patch appliqué (phpunit, pint, sail exclus)"
        else
            log_warn "⚠️ Patch pre-install échoué - ils seront supprimés après installation"
        fi

        # Étape 3 : Installer les dépendances avec le composer.json propre
        log_info "📦 Installation des dépendances Composer (skeleton patché)..."
        cd "$temp_dir"
        if ! run_cmd_logged composer install --no-interaction --prefer-dist; then
            log_error "Échec de composer install"
            run_cmd_quiet rm -rf "$temp_dir" || true
            return 1
        fi
    fi

    # Vérifier l'installation temporaire (fichiers critiques présents)
    if ! is_laravel_installed "$temp_dir"; then
        log_error "Installation temporaire invalide"
        run_cmd_quiet rm -rf "$temp_dir" || true
        return 1
    fi

    # Déplacer les fichiers vers le répertoire cible
    log_debug "Déplacement des fichiers vers $target_dir"

    # ⚠️ `cp -a .` DEPUIS `$temp_dir` : le `cd` vit dans un SOUS-SHELL, donc il
    # ne peut pas être routé par `run_cmd` (`run_cmd (…)` n'est pas un vecteur
    # de commande). C'est `cp -a` — la seule commande à effet du groupe — qui
    # est routée, avec sa source explicitée en `$temp_dir/.` puisqu'il n'y a
    # plus de `cd` pour la porter.
    # 🔴 LE CODE DE `cp -a` NE SUFFIT PAS À CONCLURE, ET S'EN CONTENTER
    # AVORTAIT DES INSTALLATIONS RÉUSSIES. `-a` implique `-p` : copier vers un
    # arbre appartenant à www-data en uid 1000 fait échouer la préservation du
    # PROPRIÉTAIRE alors que tous les octets sont arrivés. La branche d'échec,
    # rendue atteignable par le correctif `${PIPESTATUS[0]}`, effaçait alors
    # `temp_dir` et déclarait l'install perdue. C'est donc l'EFFET qui tranche ;
    # le code n'est plus qu'un signal à journaliser.
    local copy_status=0
    run_cmd_logged cp -a "$temp_dir/." "$target_dir/" || copy_status=$?

    if [ "$copy_status" -ne 0 ]; then
        log_warn "cp -a a rendu $copy_status (préservation des métadonnées ?) — vérification de l'effet sur $target_dir…"
    fi

    if ! dry_run_active && [ ! -f "$target_dir/artisan" ]; then
        log_error "Échec du déplacement des fichiers: artisan absent de $target_dir (cp -a code $copy_status)"
        run_cmd_quiet rm -rf "$temp_dir" || true
        return 1
    fi
    
    # Corriger les permissions après installation pour Docker
    if is_docker_environment; then
        log_debug "Correction finale des permissions après installation"
        run_cmd_quiet chown -R www-data:www-data "$target_dir" || true
        
        # Permissions pour le développement : directories 775, files 664
        run_cmd_quiet find "$target_dir" -type d -exec chmod 775 {} \; || true
        run_cmd_quiet find "$target_dir" -type f -exec chmod 664 {} \; || true
        
        # S'assurer qu'artisan est exécutable
        if [ -f "$target_dir/artisan" ]; then
            run_cmd_quiet chmod +x "$target_dir/artisan" || true
        fi
        
        log_debug "Permissions finales configurées pour le développement"
    fi
    
    # Nettoyer le répertoire temporaire
    run_cmd_quiet rm -rf "$temp_dir" || true
    
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
        run_cmd chmod +x "$target_dir/artisan" || return 1
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
        # 🔴 REPORT OUVERT (deferred-work.md) — `find_root_env` EST APPELÉE SANS
        # ARGUMENT alors que `common.sh:405` attend une RACINE DE PROJET (`$1`).
        # Elle teste donc « /.env », « /.env.local », « /.env.example », rend 1,
        # et la détection d'`APP_ENV` depuis le `.env` racine ne peut JAMAIS
        # aboutir : `target_env` reste « local » quoi qu'il y ait dans le .env.
        # ⚠️ Piste sérieuse sur l'origine : ce module définit plus bas un
        # `find_root_env_file()` LOCAL, à une lettre du nom exporté par
        # `common.sh`, et sans appelant. Corriger l'appel sans trancher lequel
        # des deux est le bon changerait l'environnement choisi d'une
        # installation réelle — hors périmètre de la story 2.3.
        if root_env_file=$(find_root_env 2>/dev/null); then
            local detected_env=$(grep "^APP_ENV=" "$root_env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^["'\'']//' | sed 's/["'\'']$//' | xargs)
            if [ -n "$detected_env" ]; then
                target_env="$detected_env"
            fi
        fi
    fi
    
    log_info "🎯 Environnement détecté: $target_env"
    
    # Localiser le fichier .env.{environnement} dans le projet racine
    #
    # ⚠️ RACINE INJECTABLE POUR ÊTRE TESTABLE, exactement comme
    # `INSTALL_STATE_DIR` côté orchestrateur. Écrite en dur, la garde de
    # sauvegarde ci-dessous n'était atteignable que si `/var/www/project/.env.local`
    # existait — c'est-à-dire dans le conteneur d'un poste déjà configuré, JAMAIS
    # sur un runner CI où les `.env` ne sont pas versionnés. Le test aurait donc
    # été vert en sautant silencieusement la branche qu'il prétend garder.
    local project_root="${INSTALL_PROJECT_ROOT:-/var/www/project}"
    local source_env_file="$project_root/.env.$target_env"
    local fallback_env_file="$project_root/.env"
    local target_env_file="$(pwd)/.env"
    
    # Vérifier que le fichier source existe
    if [ -f "$source_env_file" ]; then
        log_success "✅ Fichier source trouvé: $source_env_file"
        
        # Afficher des informations sur le fichier source
        log_debug "Taille du fichier source: $(wc -l < "$source_env_file" 2>/dev/null || echo 'inconnu') lignes"
        
        # Sauvegarder le .env Laravel existant avec timestamp
        if [ -f "$target_env_file" ]; then
            local backup_file=".env.laravel.backup.$(date +%Y%m%d-%H%M%S)"

            # ⛔ LA SAUVEGARDE EST UNE CONDITION DE L'ÉCRASEMENT, PAS UN CONFORT.
            # 🔴 Régression introduite par le routage de la story 2.3, relevée
            # en revue : un `cp` NU sous `set -e` arrêtait tout ; enveloppé en
            # `run_cmd … || log_warn`, il était devenu facultatif — et la copie
            # ci-dessous écrasait ensuite le `.env` de l'opérateur (clé
            # d'application, identifiants de base, secrets d'API) SANS FILET,
            # pour un avertissement dans un journal de /tmp. Le refus de
            # `clean_target_directory` protège ce même fichier deux fonctions
            # plus haut ; il n'y a aucune raison de l'abandonner ici.
            if ! run_cmd cp "$target_env_file" "$backup_file"; then
                log_fatal "Sauvegarde impossible de $target_env_file vers $backup_file — refus d'écraser le .env existant."
            fi

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

        # ⛔ EN SIMULATION, LA COPIE EST ANNONCÉE ET LA VÉRIFICATION SAUTÉE.
        # Le `diff -q` qui suit compare deux fichiers dont l'un n'a pas été
        # écrit : il conclurait « les fichiers ne sont pas identiques après
        # copie » et ferait rendre 1 à une simulation saine. Et surtout, tout
        # ce qui suit LIT `$target_env_file` — un `.env` que la simulation n'a
        # pas posé, donc des diagnostics de tokens sur un fichier absent.
        if dry_run_active; then
            run_cmd cp "$source_env_file" "$target_env_file"
            log_info "🔍 [DRY-RUN] .env non copié — vérification et diagnostic des variables non joués."
            return 0
        fi

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
        
        if run_cmd cp "$fallback_env_file" "$target_env_file"; then
            log_applied ".env racine copié comme fallback"
        else
            log_error "❌ Échec de la copie du .env racine"
            return 1
        fi

        # ⛔ SOUS SIMULATION, TOUT CE QUI SUIT LIT UN `.env` NON ÉCRIT.
        # La branche se clôturait par « ✅ Configuration .env.<env> intégrée
        # dans Laravel » après avoir diagnostiqué des tokens dans un fichier
        # absent — la même faute que la branche principale, laissée ici.
        if dry_run_active; then
            log_info "🔍 [DRY-RUN] .env racine NON copié — diagnostic des variables et verdict d'intégration non joués."
            return 0
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
# ⚠️ AUCUN APPELANT, et son nom est à UNE LETTRE de `find_root_env`
# (`common.sh:405`, exportée), que `copy_environment_configuration` appelle —
# sans argument. Report ouvert : voir le commentaire de cet appel.
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
# ⚠️ AUCUN APPELANT DANS CE MODULE AUJOURD'HUI (`configure_laravel_environment`
# passe par `copy_environment_configuration`). Ses commandes à effet sont tout
# de même routées : une fonction non routée qui retrouve un appelant plus tard
# rouvre le trou en silence, et personne ne relit une fonction morte.
#
adapt_environment_configuration() {
    local source_env="$1"
    
    log_debug "Adaptation de la configuration depuis $source_env"
    
    # Copier le fichier source
    run_cmd cp "$source_env" ".env" || return 1
    
    # Adapter les valeurs spécifiques à Laravel
    local adaptations=(
        "s/^APP_NAME=.*/APP_NAME=\"Laravel Application\"/"
        "s/^APP_ENV=.*/APP_ENV=local/"
        "s/^APP_DEBUG=.*/APP_DEBUG=true/"
        "s/^APP_URL=.*/APP_URL=http:\/\/localhost/"
    )
    
    for adaptation in "${adaptations[@]}"; do
        run_cmd_quiet sed -i "$adaptation" ".env" || true
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
            # ⚠️ `run_cmd echo "$var" >> ".env"` NE MARCHERAIT PAS : la
            # redirection est appliquée par le shell APPELANT, donc `.env`
            # serait créé/étendu même en simulation. L'écriture est enfermée
            # dans une fonction, et c'est LA FONCTION qui est routée.
            run_cmd append_line_to_env "$var" || true
            log_debug "Variable ajoutée: $var"
        fi
    done
    
    return 0
}

#
# Ajouter une ligne au `.env` du répertoire courant.
#
# Existe uniquement pour porter la REDIRECTION, que `run_cmd` ne peut pas
# envelopper (voir son docblock : vecteur de commande, pas redirection).
#
append_line_to_env() {
    echo "$1" >> ".env"
}

#
# Générer la clé d'application Laravel
#
generate_application_key() {
    log_info "Génération de la clé d'application Laravel..."

    # 🔴 L'ABSENCE DE `.env` N'EST PAS UN ÉCHEC DE GÉNÉRATION, ET LA TRAITER
    # COMME TEL TUAIT UN CHEMIN CONÇU POUR DÉGRADER PROPREMENT.
    # `copy_environment_configuration` est explicitement NON fatale (son échec
    # est journalisé puis l'installation continue). Sans `.env`, le `grep`
    # ci-dessous fuyait un « grep: .env: No such file » BRUT sur stderr — hors
    # format de log — puis `key:generate` échouait, et `configure_laravel_
    # environment` en faisait un `log_fatal` : toute l'installation mourait sur
    # une étape que le code déclarait facultative deux lignes plus haut.
    if [ ! -f ".env" ]; then
        if dry_run_active; then
            log_info "🔍 [DRY-RUN] Aucun .env sur le disque — la simulation ne l'a pas copié. L'installation réelle en aurait un ; la clé y serait générée ou conservée selon son contenu. Rien n'est prédit ici."
            return 0
        fi

        log_warn "⚠️ Aucun .env dans $(pwd) — clé d'application NON générée. L'application démarrera sans APP_KEY tant qu'un .env n'aura pas été posé."
        return 0
    fi

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
    if run_cmd_logged php artisan key:generate --force; then
        log_applied "Clé d'application générée"
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
            run_cmd_quiet mkdir -p "$dir" || true
        fi
        
        # Configurer les permissions (plus agressif pour bootstrap/cache)
        if [ "$dir" = "bootstrap/cache" ]; then
            # Bootstrap cache nécessite des permissions spéciales
            if is_docker_environment; then
                run_cmd_quiet chmod -R 777 "$dir" || true
                run_cmd_quiet chown -R www-data:www-data "$dir" || true
            else
                run_cmd_quiet chmod -R 775 "$dir" || true
            fi
            log_applied_debug "✓ Permissions spéciales configurées: $dir"
        else
            if run_cmd_quiet chmod -R 775 "$dir"; then
                log_applied_debug "✓ Permissions configurées: $dir"
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
    # ⚠️ `config:clear` SUPPRIME `bootstrap/cache/config.php` : c'est un effet,
    # pas une lecture, et il est routé comme tel.
    run_cmd_quiet php artisan config:clear || true
    
    # Vérifier si la table cache existe avant de la vider
    #
    # ⛔ EN SIMULATION, LA SONDE `tinker` N'EST PAS LANCÉE. Elle boote
    # l'application entière pour répondre à une question dont la réponse ne
    # servirait qu'à décider d'un `cache:clear` qui, lui, ne sera pas joué —
    # et ce boot écrit des logs et des caches dans la cible.
    # ⛔ ET ELLE N'ANNONCE PAS `cache:clear` NON PLUS (relevé revue 1).
    # En réel, la commande n'est lancée QUE si la sonde répond « exists ». Une
    # simulation qui annonce `[DRY] php artisan cache:clear` sans condition
    # décrit un plan que l'installation réelle ne suivrait pas — SUR-déclarer
    # est un mensonge de la même famille que sous-déclarer.
    if dry_run_active; then
        log_info "🔍 [DRY-RUN] Sonde « la table cache existe-t-elle ? » non jouée (elle boote l'application) — « php artisan cache:clear » sera joué OU sauté selon son résultat."
    elif php artisan tinker --execute="try { DB::table('cache')->limit(1)->get(); echo 'exists'; } catch(Exception \$e) { echo 'missing'; }" 2>/dev/null | grep -q "exists"; then
        run_cmd_quiet php artisan cache:clear || true
    else
        log_debug "Table cache non trouvée, skip cache:clear"
    fi
    
    run_cmd_quiet php artisan view:clear || true
    
    # ⛔ LA SUITE SE DÉCIDE SUR `APP_ENV`, LU DANS UN `.env` QUE LA SIMULATION
    # N'A PAS ÉCRIT. Annoncer `config:cache` (ou l'omettre) reviendrait à
    # prédire une branche que l'installation réelle ne suivrait pas forcément :
    # sur-déclarer et sous-déclarer sont deux mensonges de la même famille.
    if dry_run_active; then
        log_info "🔍 [DRY-RUN] Optimisation finale dépendante d'APP_ENV, lu dans un .env que la simulation n'a pas écrit — « php artisan config:cache » sera joué (production) ou sauté (local/development). Rien n'est prédit ici."
        return 0
    fi

    # Optimiser pour le développement
    if [ "$(get_current_environment)" = "local" ] || [ "$(get_current_environment)" = "development" ]; then
        log_debug "Optimisation pour l'environnement de développement"
        # En développement, on ne cache pas la configuration
        return 0
    fi
    
    # Optimiser pour la production
    log_debug "Optimisation pour l'environnement de production"
    run_cmd_quiet php artisan config:cache || true
    
    return 0
}

#
# Patch IDEMPOTENT du `composer.json` du répertoire courant.
#
# Enfermée dans une fonction pour la même raison que sa jumelle pre-install :
# `run_cmd` enveloppe un vecteur de commande, pas un document en-place, et un
# `[DRY] python3` nu ne dirait rien de ce qui serait réécrit.
#
patch_skeleton_composer_json_idempotent() {
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
}

#
# Patcher le skeleton Laravel par défaut après création
# (supprimer les conflits avec Pest v4, corriger phpunit.xml pour PostgreSQL)
#
patch_fresh_laravel_skeleton() {
    local laravel_dir="$1"

    log_info "🔧 Patch du skeleton Laravel par défaut..."

    # ⛔ SANS CE GARDE, LA SIMULATION MOURAIT ICI, SUR UN ÉCHEC QU'ELLE A CRÉÉ.
    # Sur une cible que la simulation n'a pas créée, `cd` échoue et `set -e`
    # tue le module — un rapport d'erreur qui ne décrit rien de l'installation
    # réelle. Le cas est signalé et la suite annoncée comme non jouée.
    if [ ! -d "$laravel_dir" ]; then
        if dry_run_active; then
            log_warn "🔍 [DRY-RUN] Répertoire absent: $laravel_dir — patch du skeleton non joué."
            return 0
        fi

        log_fatal "Répertoire Laravel non trouvé: $laravel_dir"
    fi

    cd "$laravel_dir"

    # --- 1. Patch composer.json (idempotent) ---
    # Pour le path principal (--no-install), ce patch a déjà été appliqué
    # avant composer install. Pour le fallback (laravel new), il est nécessaire ici.
    if [ -f "composer.json" ]; then
        # `if run_cmd …` : sous `set -e`, tester `$?` après coup ne peut pas
        # marcher — le script serait déjà mort.
        if run_cmd patch_skeleton_composer_json_idempotent; then
            log_applied "composer.json vérifié/patché"
        else
            log_warn "⚠️ Patch composer.json échoué"
        fi
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
        # ⛔ LE SUCCÈS N'EST PLUS JOURNALISÉ APRÈS UN ÉCHEC : la rédaction
        # précédente imprimait « ✅ Packages skeleton supprimés » juste après
        # avoir averti qu'ils ne l'étaient pas.
        if run_cmd_logged composer remove "${pkgs_to_remove[@]}" --dev --no-scripts --no-interaction; then
            log_applied "Packages skeleton supprimés"
        else
            log_warn "⚠️ Suppression des packages skeleton en échec — ils restent installés."
        fi
    else
        log_debug "✓ Aucun package skeleton à supprimer (pre-install patch appliqué)"
    fi

    # --- 3. Patcher phpunit.xml : SQLite → PostgreSQL ---
    if [ -f "phpunit.xml" ]; then
        # ⛔ MÊME RÈGLE : le succès n'est annoncé que si les TROIS `sed` ont
        # réussi. La rédaction précédente les faisait suivre d'un « ✅ patché »
        # inconditionnel, `|| true` compris.
        local sed_status=0

        # Remplacer sqlite par pgsql
        run_cmd sed -i 's|<env name="DB_CONNECTION" value="sqlite"/>|<env name="DB_CONNECTION" value="pgsql"/>|' phpunit.xml || sed_status=1
        # Remplacer :memory: par laravel_test
        run_cmd sed -i 's|<env name="DB_DATABASE" value=":memory:"/>|<env name="DB_DATABASE" value="laravel_test"/>|' phpunit.xml || sed_status=1
        # Supprimer la ligne DB_URL vide (spécifique SQLite)
        run_cmd sed -i '/<env name="DB_URL" value=""\/>/ d' phpunit.xml || sed_status=1

        if [ "$sed_status" -eq 0 ]; then
            log_applied "phpunit.xml patché (SQLite → PostgreSQL laravel_test)"
        else
            log_warn "⚠️ Patch de phpunit.xml en échec — la suite de tests pointerait encore SQLite."
        fi
    fi

    log_applied "Skeleton Laravel patché"
}

#
# Créer la route de healthcheck pour Docker (EXACTE DE L'ORIGINAL)
#
append_healthcheck_route() {
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
}

create_healthcheck_route() {
    log_info "🏥 Création de la route de healthcheck..."

    if [ ! -f "routes/web.php" ]; then
        # ⛔ CE N'EST PAS UN AVERTISSEMENT, C'EST UN ÉCHEC D'INSTALLATION.
        # 🔴 Relevé en revue : la rédaction précédente rendait 0 avec un
        # `log_warn`. Sans cette route, le HEALTHCHECK DOCKER du conteneur php
        # ne répond jamais — le service démarre et n'est jamais déclaré sain,
        # pour un avertissement dans un journal de /tmp que personne ne lit.
        # (La rédaction d'ORIGINE était pire encore : `grep` sur un fichier
        # absent rendait 2, la négation était vraie, et `cat >>` CRÉAIT un
        # `routes/web.php` ne contenant que la route de santé.)
        # ⚖️ ET LA SIMULATION NE PRÉDIT PAS UN ÉCHEC QU'ELLE A ELLE-MÊME CRÉÉ.
        # Sur une cible où Laravel n'est pas installé, `routes/web.php` est
        # absent PARCE QUE la simulation n'a rien copié — l'installation réelle,
        # elle, l'aurait posé. Annoncer « ÉCHOUERAIT ici » était une prédiction
        # fausse. Le cas reste signalé quand l'application EST là : c'est alors
        # un vrai diagnostic.
        if dry_run_active; then
            if [ -f "artisan" ]; then
                log_warn "🔍 [DRY-RUN] routes/web.php introuvable depuis $(pwd) ALORS QUE l'application est installée — l'installation réelle échouerait ici."
            else
                log_info "🔍 [DRY-RUN] routes/web.php absent parce que la simulation n'a PAS installé Laravel — l'installation réelle l'aurait créé. Rien n'est prédit ici."
            fi

            return 0
        fi

        log_fatal "routes/web.php introuvable depuis $(pwd) — la route /health, dont dépend le healthcheck Docker, ne peut pas être créée."
    fi

    if ! grep -q "/health" routes/web.php; then
        # ⚠️ L'ÉCRITURE EST UNE REDIRECTION (`>>`), QUE `run_cmd` NE PEUT PAS
        # ENVELOPPER : `run_cmd cat >> routes/web.php` ferait ouvrir le fichier
        # en ajout par le shell APPELANT, avant même que `run_cmd` n'ait décidé
        # quoi que ce soit. C'est donc la FONCTION qui porte la redirection, et
        # c'est elle qui est routée.
        # ⛔ ET LE SUCCÈS N'EST PAS JOURNALISÉ APRÈS UN ÉCHEC. La rédaction
        # précédente imprimait « ✅ Route /health créée » quoi qu'il arrive.
        if ! run_cmd append_healthcheck_route; then
            log_fatal "Écriture impossible dans routes/web.php — route /health absente, healthcheck Docker mort."
        fi

        log_applied "Route /health créée"
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
    #
    # ⛔ Sous simulation, la cible peut n'avoir jamais existé : `cd` échouerait
    # et `set -e` tuerait le module au moment de RAPPORTER, après une simulation
    # complète et saine.
    #
    # ⛔ ET LE VERDICT FINAL NE MENT PAS. « Laravel installé avec succès » à la
    # fin d'un `--dry-run` est exactement la phrase fausse à côté d'un code
    # juste que ce dépôt refuse : un opérateur la lirait comme une installation
    # faite.
    local laravel_version="(non relevée)"
    local php_version="(non relevée)"
    local duration

    if dry_run_active; then
        # ⛔ LA SONDE DE VERSION N'EST PAS UNE LECTURE INOFFENSIVE : elle boote
        # l'application (`php artisan --version`), ce qui écrit journaux et
        # caches DANS LA CIBLE. Un `--dry-run` qui laisse un `storage/logs/`
        # modifié fait sortir `git status --porcelain` non vide — c'est l'AC de
        # tête de cette story qui tombe.
        duration=$(calculate_duration $start_time)

        log_separator "SIMULATION TERMINÉE"
        log_success "🔍 [DRY-RUN] Simulation terminée en $duration — RIEN N'A ÉTÉ INSTALLÉ."
        log_info "📍 Répertoire cible (inchangé): $target_dir"
        log_info "📄 Fichier de log: $LOG_FILE"
        return 0
    fi

    if [ -d "$target_dir" ]; then
        cd "$target_dir"
        laravel_version=$(get_laravel_version)
        php_version=$(get_php_version)
    else
        log_warn "Répertoire cible absent: $target_dir — versions non relevées."
    fi
    
    duration=$(calculate_duration $start_time)
    
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