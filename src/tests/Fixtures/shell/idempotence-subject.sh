#!/bin/bash

# =============================================================================
# SUJET DE RÉFÉRENCE DE L'IDEMPOTENCE (scripts/install.sh — Story 2.2)
# =============================================================================
#
# Ce fichier est VERSIONNÉ, et c'est le point : un scénario construit à la volée
# dans un test ne garde que lui-même. Ici, ce qui est éprouvé est un scénario
# relisible, lançable à la main :
#
#   bash src/tests/Fixtures/shell/idempotence-subject.sh ; echo $?
#
# Il joue QUATRE passes de l'orchestrateur réel sur une racine d'état jetable :
#
#   passe 1 — un module échoue en cours de route  → l'install s'arrête
#   passe 2 — relance SANS aucun argument         → seuls les modules NON
#                                                    franchis sont rejoués
#   passe 3 — relance encore                      → plus rien à faire, sortie 0
#   passe 4 — relance avec --force                → TOUT est rejoué
#
# ⚠️ CE QUI EST RÉELLEMENT SOUS TEST, C'EST L'ORCHESTRATEUR, PAS UN JOUET.
# `scripts/install.sh` est SOURCÉ (sa garde `BASH_SOURCE[0] = $0` l'empêche de
# s'auto-exécuter) et seule la SONDE est remplacée : `execute_module` devient un
# compteur. La boucle, le fail-fast, `ensure_idempotent` et le calcul du chemin
# de sentinelle sont ceux qui partent en production.
#
# Sortie : des lignes CLEF=valeur, lisibles à l'œil comme par une assertion.
#
# =============================================================================

set -e

FIXTURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT=""

# Deux dispositions d'exécution, comme trap-subject.sh : depuis l'hôte
# (4 niveaux au-dessus de ce fichier) et depuis le conteneur php, où la racine
# du dépôt est montée sur /var/www/project.
for candidate in "$FIXTURE_DIR/../../../.." "/var/www/project"; do
    if [ -f "$candidate/scripts/install.sh" ]; then
        REPO_ROOT="$(cd "$candidate" && pwd)"
        break
    fi
done

if [ -z "$REPO_ROOT" ]; then
    echo "idempotence-subject : scripts/install.sh introuvable depuis $FIXTURE_DIR" >&2
    exit 2
fi

BAC="$(mktemp -d)"
trap 'rm -rf "$BAC"' EXIT

# Racine d'état INJECTÉE : sans cela, l'installeur sèmerait ses sentinelles dans
# l'arbre applicatif réel — celui sur lequel la sonde Pest fixe son cwd.
export INSTALL_STATE_DIR="$BAC/etat"
export LOG_FILE="$BAC/install.log"

JOURNAL="$BAC/journal"
: > "$JOURNAL"

# `source` : l'orchestrateur ne s'auto-exécute pas, on récupère ses fonctions.
source "$REPO_ROOT/scripts/install.sh"

TARGET_DIR="$BAC/cible"
mkdir -p "$TARGET_DIR"

# Module que la passe 1 fait échouer. Choisi au milieu de la liste pour que
# la reprise ait quelque chose à sauter ET quelque chose à rejouer.
MODULE_QUI_ECHOUE="30-packages-prod"

#
# LA SONDE — remplace l'exécution réelle des modules, rien d'autre.
#
execute_module() {
    local module_name="$1"

    echo "$module_name" >> "$JOURNAL"

    if [ "$module_name" = "$MODULE_QUI_ECHOUE" ]; then
        return 7
    fi

    return 0
}

#
# Joue une passe et rapporte ce qui a RÉELLEMENT tourné.
#
passe() {
    local etiquette="$1"
    shift

    : > "$JOURNAL"

    local status=0
    # La sortie de l'installeur est volumineuse et sans intérêt ici : ce qui est
    # mesuré est le JOURNAL des modules joués, pas la prose.
    run_installation > /dev/null 2>&1 || status=$?

    echo "${etiquette}_STATUS=$status"
    echo "${etiquette}_JOUES=[$(tr '\n' ',' < "$JOURNAL")]"
    echo "${etiquette}_SENTINELLES=$(find "$INSTALL_STATE_DIR" -maxdepth 1 -name '*-done' -type f 2>/dev/null | wc -l | tr -d ' ')"
}

# --- Passe 1 : le module 30 échoue ------------------------------------------
passe "PASSE1"

# --- Passe 2 : relance nue, sans --resume-from ------------------------------
MODULE_QUI_ECHOUE=""
passe "PASSE2"

# --- Passe 3 : tout est franchi, plus rien à jouer --------------------------
passe "PASSE3"

# --- Passe 4 : --force, tout est rejoué -------------------------------------
FORCE=true
passe "PASSE4"

echo "TOTAL_MODULES=${#INSTALL_MODULES[@]}"
