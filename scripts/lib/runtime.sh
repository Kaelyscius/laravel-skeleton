#!/bin/bash

# =============================================================================
# PRIMITIVES D'EXÉCUTION PARTAGÉES
# =============================================================================
#
# Cinq primitives que les scripts d'installation réimplémentaient à la main,
# chacune dans sa variante : `die`, `retry`, `require_cmd`, `ensure_idempotent`,
# `run_cmd`. Plus `arm_err_trap`, opt-in (voir plus bas pourquoi il n'est armé
# nulle part).
#
# Utilisation:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/../lib/logging.sh"
#   source "$SCRIPT_DIR/../lib/runtime.sh"
#
# =============================================================================

# =============================================================================
# GARDE D'INCLUSION
# =============================================================================
#
# Mesuré le 2026-08-20 : re-sourcer `logging.sh` sous `set -e` TUE l'appelant —
# `readonly GREEN` (logging.sh:20) échoue au second passage et errexit fait le
# reste. Aucune lib de ce dépôt n'a de garde ; celle-ci en a une pour ne pas
# reproduire le défaut.
#
# ⚠️ CE QUI EST RÉELLEMENT GARDÉ, C'EST LE BLOC `if` — pas le `readonly`.
# Mesuré le 2026-08-22, contre l'affirmation qui tenait ici jusque-là : retirer
# le SEUL mot-clé `readonly` laisse la suite à 26 verts, parce que le `return 0`
# court-circuite avant toute ré-affectation. Retirer le bloc `if`, lui, fait
# rougir « survit à un double source ».
# Le `readonly` reste, et ce qu'il garantit est plus étroit : un appelant ne
# peut pas remettre `RUNTIME_SH_LOADED` à vide pour forcer un second `source`.
# C'est une ceinture, pas la bretelle — et cette distinction est écrite parce
# qu'un commentaire qui promet un rouge inexistant EST un garde-fou silencieux.
if [ -n "${RUNTIME_SH_LOADED:-}" ]; then
    return 0 2>/dev/null || exit 0
fi
readonly RUNTIME_SH_LOADED=1

readonly RUNTIME_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# `die` délègue à `log_fatal`. Si l'appelant a respecté l'idiome du dépôt
# (logging.sh en premier), il est déjà là ; sinon on le charge — une seule fois,
# donc jamais le double-source décrit ci-dessus.
if ! declare -F log_fatal > /dev/null 2>&1; then
    source "$RUNTIME_LIB_DIR/logging.sh"
fi

# =============================================================================
# die — erreur fatale
# =============================================================================
#
# Arguments:
#   $1: Message
#   $2: Code de sortie (défaut: 1)
#
# ⚠️ `die` est fatal AU PROCESSUS : il délègue à `log_fatal`, qui appelle
# `exit`. Dans une substitution de commande — `x=$(require_cmd foo)` — il ne tue
# que le sous-shell, sa bannière devient la VALEUR de `x`, et l'appelant
# poursuit en croyant tout normal. Ne jamais appeler `die` ni `require_cmd` en
# substitution.
#
die() {
    local message="${1:-Erreur fatale sans message}"
    local exit_code="${2:-1}"

    log_fatal "$message" "$exit_code"
}

# =============================================================================
# require_cmd — exiger un ou plusieurs binaires
# =============================================================================
#
# Arguments:
#   $@: Noms des binaires requis
#
# Vérifie TOUS les binaires avant de mourir, et les nomme TOUS : un binaire
# manquant n'en masque donc pas un second, ce qui évite la réinstallation en
# aller-retour.
#
require_cmd() {
    if [ $# -eq 0 ]; then
        die "require_cmd : appelé sans argument — aucun binaire à vérifier."
    fi

    local missing=()
    local blank=0
    local binary

    # UNE SEULE passe, aucune sortie anticipée : le docblock promet que TOUS
    # les binaires sont vérifiés avant la mort, et un `die` posé DANS la boucle
    # tenait cette promesse pour les absents mais pas pour les noms vides — le
    # premier argument vide masquait tout ce qui suivait.
    for binary in "$@"; do
        if [ -z "$binary" ]; then
            blank=$((blank + 1))
            continue
        fi

        if ! command -v "$binary" > /dev/null 2>&1; then
            missing+=("$binary")
        fi
    done

    if [ "$blank" -ne 0 ] || [ ${#missing[@]} -ne 0 ]; then
        local report="require_cmd :"

        if [ "$blank" -ne 0 ]; then
            report="$report $blank nom(s) de binaire vide(s) ;"
        fi

        if [ ${#missing[@]} -ne 0 ]; then
            report="$report binaire(s) requis introuvable(s) dans le PATH : ${missing[*]}"
        fi

        die "$report"
    fi

    return 0
}

# =============================================================================
# retry — réessayer avec backoff exponentiel
# =============================================================================
#
# Arguments:
#   $1: Nombre d'essais (entier >= 1)
#   $@: Commande à exécuter
#
# Variables:
#   RETRY_BASE_DELAY: délai de base en secondes (défaut: 1). L'attente avant le
#                     n-ième réessai vaut RETRY_BASE_DELAY × 2^(n-1) et est
#                     JOURNALISÉE avant d'être subie — c'est ce qui permet de
#                     vérifier le doublement sans mesurer une horloge. À 0,
#                     aucun `sleep` n'est exécuté.
#
# Rend 0 au premier succès, sinon le code de la dernière tentative. Ne meurt
# JAMAIS de lui-même : c'est à l'appelant de décider si un échec est fatal.
#
retry() {
    local attempts="${1:-}"
    shift || true

    # Validation AVANT toute boucle. Mesuré sur une dérivation précédente :
    # `retry abc f` bouclait à l'infini (le compteur n'était jamais atteint) et
    # `retry 3` sans commande rendait 0 — un faux succès.
    #
    # 🔴 LE NOMBRE DE CHIFFRES EST BORNÉ, et ce n'est pas de la coquetterie.
    # `^[0-9]+$` accepte « 99999999999999999999 » ; le test `-lt` qui suit sort
    # alors de la plage 64 bits, `[` rend « integer expression expected », la
    # garde ne se déclenche PAS et la boucle tourne sans fin — mesuré le
    # 2026-08-22, tué par timeout à 5 s (code 143). La matrice gelée dit
    # « jamais de boucle » : un entier hors plage doit donc mourir comme un
    # non-entier.
    if [[ ! "$attempts" =~ ^[0-9]{1,6}$ ]] || [ "$attempts" -lt 1 ]; then
        die "retry : nombre d'essais invalide (« ${attempts} ») — entier de 1 à 999999 attendu."
    fi

    if [ $# -eq 0 ]; then
        die "retry : aucune commande à exécuter (usage : retry <n> <commande…>)."
    fi

    local base_delay="${RETRY_BASE_DELAY:-1}"

    # Bornée pour la même raison : un délai hors plage 64 bits ferait échouer
    # l'arithmétique du backoff au lieu d'être refusé à l'entrée.
    if [[ ! "$base_delay" =~ ^[0-9]{1,6}$ ]]; then
        die "retry : RETRY_BASE_DELAY invalide (« ${base_delay} ») — entier de 0 à 999999 attendu."
    fi

    local attempt=1
    local status=0
    local delay=0

    while true; do
        status=0
        "$@" || status=$?

        if [ "$status" -eq 0 ]; then
            return 0
        fi

        if [ "$attempt" -ge "$attempts" ]; then
            log_warn "retry : « $* » a échoué après $attempts essai(s) (code $status)."
            return "$status"
        fi

        delay=$((base_delay * (2 ** (attempt - 1))))
        log_warn "retry : essai $attempt/$attempts en échec (code $status) — nouvelle tentative dans ${delay}s."

        if [ "$delay" -gt 0 ]; then
            sleep "$delay"
        fi

        attempt=$((attempt + 1))
    done
}

# =============================================================================
# ensure_idempotent — n'exécuter qu'une fois, prouvé par une sentinelle
# =============================================================================
#
# Arguments:
#   $1: Chemin de la sentinelle
#   $@: Commande à exécuter si la sentinelle est absente
#
# Rend 0 UNIQUEMENT si l'étape est réellement franchie : soit la sentinelle
# était déjà là, soit la commande a réussi ET la sentinelle a été écrite. Une
# dérivation précédente rendait 0 en journalisant « sentinelle posée » sur un
# chemin impossible, sentinelle absente — l'étape aurait été considérée faite
# une fois pour toutes sans que rien ne l'ait jamais été.
#
ensure_idempotent() {
    local sentinel="${1:-}"
    shift || true

    if [ -z "$sentinel" ]; then
        die "ensure_idempotent : chemin de sentinelle vide."
    fi

    if [ $# -eq 0 ]; then
        die "ensure_idempotent : aucune commande (usage : ensure_idempotent <sentinelle> <commande…>)."
    fi

    # `-f` et non `-e` : la post-condition d'écriture, plus bas, exige un
    # FICHIER RÉGULIER. Lire avec `-e` acceptait donc un répertoire (ou un lien
    # cassé, ou un socket) comme preuve que l'étape était faite — une étape
    # jamais jouée, réputée franchie à jamais, sans qu'aucune écriture n'ait
    # pu avoir lieu. Lecture et écriture doivent parler du MÊME objet.
    if [ -f "$sentinel" ]; then
        log_debug "ensure_idempotent : sentinelle présente ($sentinel) — « $* » non exécutée."
        return 0
    fi

    local status=0
    "$@" || status=$?

    if [ "$status" -ne 0 ]; then
        log_error "ensure_idempotent : « $* » a échoué (code $status) — sentinelle NON posée."
        return "$status"
    fi

    mkdir -p "$(dirname "$sentinel")" > /dev/null 2>&1 || true
    : > "$sentinel" 2> /dev/null || true

    # Post-condition vérifiée sur le disque, pas déduite du code de retour d'un
    # `touch` : c'est elle qui interdit le « sentinelle posée » mensonger.
    if [ ! -f "$sentinel" ]; then
        log_error "ensure_idempotent : sentinelle impossible à écrire ($sentinel) — l'étape sera rejouée."
        return 1
    fi

    log_debug "ensure_idempotent : sentinelle posée ($sentinel)."
    return 0
}

# =============================================================================
# run_cmd — exécuter, ou seulement ANNONCER sous simulation
# =============================================================================
#
# Arguments:
#   $@: Commande à exécuter (vecteur : binaire ou fonction, puis arguments)
#
# Variables:
#   INSTALL_DRY_RUN: `true` ⇒ la commande est JOURNALISÉE (`[DRY] …`) et n'est
#                    PAS exécutée ; toute autre valeur (ou l'absence) ⇒
#                    exécution réelle.
#
# Rend 0 en simulation, sinon le code RÉEL de la commande enveloppée. Ne meurt
# JAMAIS d'elle-même — même contrat que `retry` : c'est à l'appelant de décider
# si un échec est fatal. Un `run_cmd` qui mourrait tout seul rendrait la
# simulation plus fatale que l'exécution réelle qu'elle décrit.
#
# ⚠️ ELLE LIT `INSTALL_DRY_RUN`, PAS `DRY_RUN`. `DRY_RUN` est une globale de
# l'orchestrateur, jamais exportée (sondé le 2026-08-22 : un enfant voit
# `<absent>`). Le préfixe `INSTALL_` marque la même frontière qu'`INSTALL_FORCE` :
# dérivée UNE fois, sur le chemin d'exécution, lue par les sous-processus.
#
# 🔴 LE PLAN EST RÉPARTI SUR LES DEUX FLUX, ET LA PHRASE D'AVANT DISAIT LE
# CONTRAIRE. Elle affirmait « la trace part sur STDERR ; `> plan.txt` rend un
# fichier vide ». MESURÉ, deux fois : `install.sh --dry-run --only
# 10-laravel-core` émet la MAJORITÉ de ses lignes `[DRY]` sur **STDOUT**.
#
# Pourquoi : `log_info` écrit bien sur stderr (`logging.sh:104`), mais
# l'orchestrateur lance les modules en `"$module_file" … 2>&1 | tee -a
# "$LOG_FILE"` (`install.sh`, `execute_module`) — ce `2>&1` replie le stderr du
# MODULE dans le stdout de l'orchestrateur. Les lignes émises par le module
# sortent donc sur stdout, celles émises par l'orchestrateur sur stderr.
#
# ⚖️ LA SEULE CAPTURE COMPLÈTE EST DONC CELLE QUI PREND LES DEUX :
#   ./scripts/install.sh --dry-run > plan.txt 2>&1     # ✅ le plan ENTIER
#   ./scripts/install.sh --dry-run 2>&1 | tee plan.txt # ✅ idem, à l'écran aussi
#   ./scripts/install.sh --dry-run > plan.txt          # ⛔ INCOMPLET
#   ./scripts/install.sh --dry-run 2> plan.txt         # ⛔ INCOMPLET
# Le plan est aussi écrit dans `/tmp/laravel-install-<id>.log`, qui reste le
# canal d'observation nommé par le spec. Cette répartition est PINNÉE par une
# sonde qui capture les deux flux séparément et compte — un test qui lit
# `2>&1` ne peut pas les distinguer, et c'est ce qui a laissé la phrase fausse
# vivre cinq endroits durant.
#
# ⚠️ LES FRONTIÈRES D'ARGUMENTS SONT PRÉSERVÉES PAR `printf %q`.
# `log_info "[DRY] $*"` aplatissait tout en une chaîne : un chemin contenant une
# espace devenait indistinguable de deux arguments — sur la SEULE trace que la
# simulation produit, et précisément pour la classe de chemins piégés qui a
# coûté trois correctifs à la story 2.2.
#
# ⚠️ `run_cmd` PREND UN VECTEUR DE COMMANDE, PAS UN PIPELINE NI UNE REDIRECTION.
#   • `run_cmd a | b` n'enveloppe QUE `a` : `b` tourne toujours, et en
#     simulation il lit la sortie de `log_info` au lieu de celle de `a`.
#   • `run_cmd cmd > fichier` fait CRÉER `fichier` par le shell appelant AVANT
#     que `run_cmd` n'ait rien décidé — l'effet de bord survit à la simulation.
# Dans ces deux cas, enfermer le tout dans une fonction et router LA FONCTION.
# Même piège que la substitution de commande qui neutralise `die`.
#
run_cmd() {
    # ⛔ LE PREMIER ARGUMENT VIDE EST REFUSÉ AUTANT QUE L'ABSENCE D'ARGUMENT.
    # `run_cmd ""` franchissait la garde `$# -eq 0` : en réel il sortait 127
    # (« command not found » sur la chaîne vide), et en simulation il produisait
    # une ligne `[DRY]` qui ne nommait RIEN — une simulation qui annonce le
    # vide. Même refus que `require_cmd` pour ses noms de binaires vides.
    if [ $# -eq 0 ] || [ -z "$1" ]; then
        die "run_cmd : aucune commande à exécuter (usage : run_cmd <commande…>)."
    fi

    if [ "${INSTALL_DRY_RUN:-false}" = true ]; then
        local rendu
        rendu="$(printf '%q ' "$@")"
        log_info "[DRY] ${rendu% }"
        return 0
    fi

    # Le code est capturé puis rendu explicitement : `"$@"` nu sous `set -e`
    # tuerait l'appelant, et le contrat promet un code rendu, pas une mort.
    local status=0
    "$@" || status=$?

    return "$status"
}

# =============================================================================
# arm_err_trap — trap ERR, OPT-IN
# =============================================================================
#
# ⛔ AUCUN script d'installation ne l'arme, et c'est délibéré.
#
# Mesuré le 2026-08-20 : sous `set -E`, le trap se déclenche bien dans
# `local x=$(cmd)`, mais DANS LE SOUS-SHELL de substitution — la bannière fatale
# devient la valeur de `x` et le script continue, exit 0. `00-prerequisites.sh`
# porte ~17 affectations de cette forme. Un trap armé globalement prétendrait
# donc attraper ce qu'il n'attrape pas.
#
# Ce qu'`arm_err_trap` garantit, et rien de plus : une COMMANDE NUE qui échoue
# meurt en nommant son fichier et son numéro de ligne. Sujet de référence :
# `src/tests/Fixtures/shell/trap-subject.sh`.
#
# 🔴 DEUXIÈME LIMITE, ÉCRITE PARCE QU'ELLE ÉTAIT TUE (report W20) : IL N'Y A
# PAS DE `pipefail` ICI, DONC UN PIPELINE QUI ÉCHOUE À GAUCHE NE DÉCLENCHE RIEN.
# `faux | tee -a "$LOG_FILE"` rend le code de `tee` — 0 — le trap ne se
# déclenche pas, et le script continue. Le docblock promettait « une commande
# nue » sans jamais dire que le pipeline en était exclu : un lecteur pouvait
# croire le contraire.
#
# ⚖️ ET `pipefail` N'EST DÉLIBÉRÉMENT PAS POSÉ (Ask First du spec 2.3).
# Neuf pipelines `| tee -a "$LOG_FILE"` de l'installeur dépendent de son
# absence — ils capturent le code de gauche à la main par `${PIPESTATUS[0]}`
# quand il les intéresse. L'armer ici changerait le comportement de tout script
# qui appelle `arm_err_trap`, pour un bénéfice que rien ne mesure aujourd'hui.
# Le comportement RÉEL est donc pinné par un test (`ShellRuntimeLibTest`) plutôt
# que promis par une phrase : une prose qui décrit un `pipefail` inexistant est
# exactement le garde-fou silencieux que ce dépôt refuse.
#
arm_err_trap() {
    # `set -E` : sans lui, le trap ERR n'est hérité par aucune fonction.
    set -E
    # Fichier et ligne sont capturés DANS LA CHAÎNE du trap, donc évalués au
    # moment où il se déclenche. Les lire dans le corps du gestionnaire
    # donnerait la ligne du gestionnaire — un numéro juste-en-apparence.
    trap '_runtime_on_err "$?" "${BASH_SOURCE[0]}" "$LINENO"' ERR
}

#
# Gestionnaire du trap ERR. Interne : ne pas appeler directement.
#
_runtime_on_err() {
    local status="${1:-1}"
    local source_file="${2:-?}"
    local line="${3:-?}"

    # Désarmer avant de mourir : `die` journalise, et une erreur dans le
    # gestionnaire ne doit pas le rappeler en boucle.
    trap - ERR

    die "Commande en échec — ${source_file}:${line} (code ${status})" "$status"
}

# =============================================================================
# EXPORT DES FONCTIONS
# =============================================================================

export -f die require_cmd retry ensure_idempotent run_cmd arm_err_trap _runtime_on_err
