#!/bin/bash

# =============================================================================
# LOCKFILE D'INSTALLATION — src/.install-state/lock.yml
# =============================================================================
#
# Enregistre l'empreinte des dépendances PHP et les versions d'outils RÉELLEMENT
# utilisées par l'installation qui vient de se terminer.
#
# ⚠️ CE SCRIPT TOURNE SUR L'HÔTE, ET C'EST UNE CONTRAINTE MESURÉE, PAS UN GOÛT.
#
#   1. Le conteneur php n'a NI CLI docker NI socket docker : il ne peut pas
#      interroger le conteneur node. Un lockfile écrit depuis `install.sh`
#      (qui, lui, tourne dans php) ne pourrait donc pas rapporter la version de
#      node — ou la rapporterait fausse.
#   2. Les deux conteneurs n'ont pas le même node. Le conteneur node est épinglé
#      et c'est LUI qui produit `node_modules/` ; le conteneur php porte un node
#      installé par apt, non épinglé, qui n'installe jamais rien. Le lockfile
#      enregistre celui du conteneur NODE.
#   3. `npm-install` s'exécute APRÈS `install-laravel` dans toutes les chaînes du
#      Makefile. Un lockfile écrit en fin d'`install.sh` décrirait un
#      `node_modules/` qui n'existe pas encore.
#
# ⛔ AUCUNE VALEUR DE REPLI. Un conteneur absent, un `composer.lock` absent, un
# horodatage de début absent : le script MEURT en nommant ce qui manque. Un
# lockfile qui invente « inconnu » à la place d'une version est pire qu'absent —
# la story 2.4 le relira comme une mesure.
#
# Utilisation:
#   ./scripts/install-lockfile.sh
#   make install-lockfile
#
# Code de sortie:
#   0: lock.yml écrit
#   1: une valeur n'a pas pu être collectée (rien n'est écrit)
#
# =============================================================================

set -e

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/runtime.sh"

# =============================================================================
# CONFIGURATION — tout est injectable, pour que les tests n'aient pas besoin
# d'une stack docker réelle (le stub vit dans un PATH reconstruit).
# =============================================================================

REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
APP_DIR="${APP_DIR:-$REPO_ROOT/src}"
INSTALL_STATE_DIR="${INSTALL_STATE_DIR:-$APP_DIR/.install-state}"
COMPOSER_LOCK="${COMPOSER_LOCK:-$APP_DIR/composer.lock}"
# Pendant Node de `composer.lock` : sans lui, le lockfile argumente sur Node
# sans jamais empreinter ce que Node a installé.
NPM_LOCK="${NPM_LOCK:-$APP_DIR/package-lock.json}"
LOCKFILE="${LOCKFILE:-$INSTALL_STATE_DIR/lock.yml}"
STARTED_AT_MARKER="${STARTED_AT_MARKER:-$INSTALL_STATE_DIR/started-at}"

COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-laravel-app}"
PHP_CONTAINER_NAME="${PHP_CONTAINER_NAME:-${COMPOSE_PROJECT_NAME}_php}"
NODE_CONTAINER_NAME="${NODE_CONTAINER_NAME:-${COMPOSE_PROJECT_NAME}_node}"
DOCKER_BIN="${DOCKER_BIN:-docker}"

# =============================================================================
# COLLECTE
# =============================================================================

#
# Exécute une commande dans un conteneur et rend sa sortie, ou MEURT en nommant
# le conteneur.
#
# `docker exec` échoue aussi bien parce que le conteneur est arrêté que parce
# qu'il n'existe pas : les deux méritent le même refus explicite, et aucun des
# deux ne mérite une version inventée.
#
container_output() {
    local container="$1"
    shift

    local output=""
    local status=0

    output="$("$DOCKER_BIN" exec "$container" "$@" 2>&1)" || status=$?

    if [ "$status" -ne 0 ]; then
        # 🔴 CE COMMENTAIRE DISAIT UNE CHOSE FAUSSE (corrigé, revue 1).
        # Il affirmait que « `die` est appelé en dehors de toute substitution ».
        # C'est l'inverse : `container_output` n'est JAMAIS appelée autrement
        # qu'en substitution — `x="$(container_output …)"` — donc `die` n'y tue
        # que le sous-shell, exactement le piège documenté dans l'en-tête de
        # `die` (runtime.sh).
        #
        # CE QUI SAUVE LE CAS, ET C'EST FRAGILE, DONC ÉCRIT :
        #   1. l'idiome en DEUX lignes chez l'appelant — `local x` puis
        #      `x="$(…)"` — car une affectation simple propage le code de
        #      retour de la substitution, là où `local x="$(…)"` le MASQUE
        #      (le code retourné devient celui de `local`, toujours 0) ;
        #   2. `set -e`, qui transforme ce code non nul en arrêt du script.
        # Écrire `local x="$(container_output …)"` rendrait donc la bannière
        # fatale comme VALEUR et poursuivrait l'exécution. Une mutation garde
        # ce point ; il n'est pas laissé à la vigilance du prochain lecteur.
        log_error "docker exec a échoué (code $status) : $output"
        die "Conteneur « $container » injoignable — impossible de relever « $* ». Démarrez la stack (make up-dev) puis relancez. Aucune valeur de repli n'est écrite."
    fi

    if [ -z "$output" ]; then
        die "Conteneur « $container » : « $* » n'a rien rendu. Aucune valeur de repli n'est écrite."
    fi

    echo "$output"
}

#
# Empreinte sha256 d'un fichier, ou mort bruyante.
#
# 🔴 LE STATUT DE `sha256sum` ÉTAIT MASQUÉ PAR `cut` (corrigé, revue 1).
# `sha256sum X | cut -d' ' -f1` rend le code de `cut`, soit 0 quoi qu'il
# arrive : un fichier illisible (droits, disque) donnait une empreinte VIDE et
# le lockfile portait `composer_lock_sha256: ""`. `set -o pipefail` réglerait
# le motif d'un coup, mais il est explicitement « Ask First » dans le bloc
# gelé — on capture donc le statut avant tout tube, ce qui est de toute façon
# plus lisible que d'en dépendre.
#
file_sha256() {
    local label="$1"
    local path="$2"

    if [ ! -f "$path" ]; then
        die "$label introuvable ($path) — l'installation n'a pas abouti, rien à verrouiller. Aucune valeur de repli n'est écrite."
    fi

    local line=""
    local status=0
    line="$(sha256sum "$path")" || status=$?

    if [ "$status" -ne 0 ]; then
        die "$label illisible ($path) — sha256sum a rendu $status. Aucune valeur de repli n'est écrite."
    fi

    local digest="${line%% *}"

    # Le format est VALIDÉ, pas supposé : 64 caractères hexadécimaux. Un
    # `sha256sum` qui aurait imprimé un avertissement, ou une implémentation
    # BusyBox au format différent, produirait sinon une empreinte plausible et
    # fausse — précisément ce qu'un lockfile ne doit jamais contenir.
    if [[ ! "$digest" =~ ^[0-9a-f]{64}$ ]]; then
        die "$label : empreinte sha256 inattendue (« $digest ») pour $path. Aucune valeur de repli n'est écrite."
    fi

    echo "$digest"
}

#
# Horodatage de début, posé par `scripts/install.sh` au premier passage.
#
installation_started_at() {
    if [ ! -f "$STARTED_AT_MARKER" ]; then
        die "Horodatage de début introuvable ($STARTED_AT_MARKER) — lancez d'abord l'installeur (make install-laravel). Aucune valeur de repli n'est écrite."
    fi

    local value
    value="$(head -n 1 "$STARTED_AT_MARKER" | tr -d '[:space:]')"

    if [ -z "$value" ]; then
        die "Horodatage de début vide ($STARTED_AT_MARKER)."
    fi

    # ⚖️ VALIDÉ PAR SYMÉTRIE (revue 2) : `started_at` était le SEUL champ du
    # lockfile écrit sans contrôle de format, alors que les versions et les
    # empreintes en ont un. Ce fichier est relu comme une MESURE par la story
    # 2.4 ; un marqueur corrompu à la main y deviendrait une fenêtre
    # d'installation, sous un exit 0.
    if [[ ! "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
        die "Horodatage de début invalide (« $value » dans $STARTED_AT_MARKER) — attendu AAAA-MM-JJTHH:MM:SSZ. Aucune valeur de repli n'est écrite."
    fi

    echo "$value"
}

# =============================================================================
# ÉCRITURE
# =============================================================================

#
# Valide une version relevée dans un conteneur, ou meurt.
#
# 🔴 `container_output` FUSIONNE stderr DANS LA VALEUR (`2>&1`), et c'est
# délibéré — c'est ce qui permet de citer le message de docker dans le refus.
# Conséquence non vue au premier jet : un avertissement du conteneur
# (« Warning: ... », une bannière de shell, un `npm notice`) devient une
# VERSION, écrite telle quelle dans le lockfile, sur une commande qui a pourtant
# rendu 0. Le format est donc validé AVANT écriture : ce fichier est relu comme
# une mesure par la story 2.4, pas comme un journal.
#
validated_version() {
    local label="$1"
    local raw="$2"

    # Le `v` de `node -v` est retiré par l'appelant ; on tolère les
    # pré-versions (`8.5.0-dev`, `24.19.0-rc.1`), jamais une phrase.
    if [[ ! "$raw" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]]; then
        die "$label : version inattendue (« $raw ») — attendu X.Y.Z. Le conteneur a probablement émis un avertissement sur la même sortie. Aucune valeur de repli n'est écrite."
    fi

    echo "$raw"
}

main() {
    log_separator "LOCKFILE D'INSTALLATION"

    require_cmd "$DOCKER_BIN" sha256sum

    local started_at
    started_at="$(installation_started_at)"

    local composer_sha
    composer_sha="$(file_sha256 "composer.lock" "$COMPOSER_LOCK")"

    # ⚖️ `package-lock.json` EST EMPREINTÉ LUI AUSSI (correctif revue 1).
    # Ce script argumente tout entier sur Node — quel conteneur l'a produit,
    # quelle version, pourquoi c'est celle-là — et n'empreintait pourtant que
    # les dépendances PHP. Le pendant Node de `composer.lock` manquait, ce qui
    # rendait le lockfile incapable de dire si `node_modules/` correspond à ce
    # que le dépôt déclare.
    local npm_sha
    npm_sha="$(file_sha256 "package-lock.json" "$NPM_LOCK")"

    # PHP_VERSION plutôt que le texte de `php -v` : on veut « 8.5.0 », pas une
    # bannière de trois lignes à re-parser à chaque montée de version.
    #
    # ⚠️ L'IDIOME EN DEUX LIGNES EST PORTEUR (voir `container_output`) :
    # `local x` puis `x="$(…)"`. Écrit `local x="$(…)"`, le code de retour de la
    # substitution serait masqué par `local` et un `die` interne deviendrait une
    # VALEUR. Ne pas condenser ces paires de lignes.
    local php_version
    php_version="$(container_output "$PHP_CONTAINER_NAME" php -r 'echo PHP_VERSION;')"
    php_version="$(validated_version "PHP ($PHP_CONTAINER_NAME)" "$php_version")"

    # ⚖️ Le conteneur NODE, jamais le conteneur php : c'est celui-ci qui a
    # produit `node_modules/`. Les deux ne portent pas la même version.
    local node_version
    node_version="$(container_output "$NODE_CONTAINER_NAME" node -v)"
    node_version="$(validated_version "Node ($NODE_CONTAINER_NAME)" "${node_version#v}")"

    local finished_at
    finished_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

    # ⚠️ L'en-tête de ce script promet qu'il « MEURT en nommant ce qui manque ».
    # Ce `mkdir` échouait sous `set -e` nu : mort silencieuse, sans `die`, sans
    # nommer le chemin — la prose promettait plus que le code (relevé revue 2).
    mkdir -p "$(dirname "$LOCKFILE")" 2>/dev/null \
        || die "Racine d'état impossible à créer ($(dirname "$LOCKFILE")) — vérifiez les droits. Aucune valeur de repli n'est écrite."


    # ⛔ ÉCRITURE ATOMIQUE : temporaire dans le MÊME répertoire, puis `mv`.
    # Le contrôle `[ -f "$LOCKFILE" ]` qui tenait lieu de post-condition est
    # VRAI sur un fichier tronqué — un disque plein ou un `cat` interrompu
    # laissait un lock.yml à moitié écrit que le script déclarait « écrit ».
    # Même répertoire : `mv` n'est atomique que sur le même système de
    # fichiers. Le temporaire est retiré par le `trap` si quoi que ce soit
    # échoue en chemin.
    local tmp_lockfile
    tmp_lockfile="$(mktemp "$(dirname "$LOCKFILE")/.lock.yml.XXXXXX")" || die "Temporaire impossible à créer près de $LOCKFILE."
    trap 'rm -f "$tmp_lockfile"' EXIT

    cat > "$tmp_lockfile" << EOF
# Généré par scripts/install-lockfile.sh — NE PAS ÉDITER À LA MAIN.
# Ce fichier est ignoré par git (src/.gitignore: /.install-state) : il décrit
# UNE installation, sur UNE machine, pas l'intention du dépôt.
schema: 1
started_at: "$started_at"
finished_at: "$finished_at"
composer_lock_sha256: "$composer_sha"
package_lock_sha256: "$npm_sha"
php_version: "$php_version"
php_source_container: "$PHP_CONTAINER_NAME"
node_version: "$node_version"
node_source_container: "$NODE_CONTAINER_NAME"
EOF

    # Post-condition RELUE sur le temporaire — même discipline qu'
    # `ensure_idempotent` : la dernière ligne attendue est présente, donc
    # l'écriture est allée à son terme.
    #
    # 🔴 CETTE VÉRIFICATION EMPLOYAIT `grep` EN MODE REGEX SUR UN NOM DE
    # CONTENEUR. Mesuré : avec `COMPOSE_PROJECT_NAME` portant un métacaractère
    # — `projet[1]` suffit — le motif ne correspondait plus à sa propre sortie
    # et le script refusait un fichier PARFAITEMENT écrit, en annonçant une
    # « écriture partielle » qui n'avait pas eu lieu. Un diagnostic faux coûte
    # plus cher qu'aucun diagnostic. Comparaison LITTÉRALE de la dernière
    # ligne : aucun langage de motif n'a affaire ici.
    local expected_tail="node_source_container: \"$NODE_CONTAINER_NAME\""
    local actual_tail
    actual_tail="$(tail -n 1 "$tmp_lockfile")"

    if [ "$actual_tail" != "$expected_tail" ]; then
        die "Lockfile écrit partiellement ($tmp_lockfile) — dernière ligne « $actual_tail », attendue « $expected_tail ». Rien n'est publié."
    fi

    # ⚖️ PERMISSIONS TRANCHÉES ET ÉCRITES (revue 2). `mktemp` crée en 0600 et
    # `mv` conserve le mode : le lockfile était donc publié en 0600, illisible
    # par tout autre utilisateur — or il vit dans `src/`, relu depuis les
    # conteneurs php et node, sous des uid qui ne sont pas nécessairement celui
    # qui a lancé `make`. Décision : 0644. Ce fichier ne porte AUCUN secret —
    # deux empreintes publiques, deux numéros de version, deux horodatages — et
    # sa raison d'être est d'être relu. Un 0600 par accident de `mktemp` n'est
    # pas une décision de sécurité, c'est un effet de bord.
    chmod 0644 "$tmp_lockfile" || die "Permissions impossibles à poser sur $tmp_lockfile."

    mv "$tmp_lockfile" "$LOCKFILE" || die "Publication impossible du lockfile ($LOCKFILE)."
    trap - EXIT

    log_success "✅ Lockfile écrit: $LOCKFILE"
    log_info "   • composer.lock sha256: $composer_sha"
    log_info "   • package-lock.json sha256: $npm_sha"
    log_info "   • PHP ($PHP_CONTAINER_NAME): $php_version"
    log_info "   • Node ($NODE_CONTAINER_NAME): $node_version"
    log_info "   • Fenêtre: $started_at → $finished_at"

    return 0
}

# =============================================================================
# EXÉCUTION
# =============================================================================

# Sourçable : les tests remplacent les sondes plutôt que le code sous test.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
