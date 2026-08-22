#!/bin/bash

# =============================================================================
# SUJET DE RÉFÉRENCE DU `trap ERR` (scripts/lib/runtime.sh)
# =============================================================================
#
# Ce fichier est VERSIONNÉ, et c'est le point : un jouet construit à la volée
# dans un test ne garde que lui-même. Ici, ce qui est éprouvé est un script
# relisible, lançable à la main :
#
#   bash src/tests/Fixtures/shell/trap-subject.sh ; echo $?
#   → bannière « ERREUR FATALE: Commande en échec — <ce fichier>:<ligne> », exit 1
#
# Exercé par src/tests/Unit/ShellRuntimeLibTest.php, qui dérive le numéro de
# ligne attendu du marqueur ci-dessous plutôt que de l'écrire en dur : déplacer
# la commande en échec ne doit pas rendre le test vert par accident.
#
# ⚠️ Ce fichier est le SEUL du dépôt à armer le trap. Aucun script
# d'installation ne l'arme (voir arm_err_trap dans runtime.sh).
#
# =============================================================================

set -e

# Racine du dépôt, résolue pour les deux dispositions d'exécution : depuis
# l'hôte (4 niveaux au-dessus de ce fichier) et depuis le conteneur php, où
# `src/` est monté sur /var/www/html et la racine du dépôt sur /var/www/project.
FIXTURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_LIB=""

for candidate in "$FIXTURE_DIR/../../../.." "/var/www/project"; do
    if [ -f "$candidate/scripts/lib/runtime.sh" ]; then
        RUNTIME_LIB="$(cd "$candidate" && pwd)/scripts/lib"
        break
    fi
done

if [ -z "$RUNTIME_LIB" ]; then
    echo "trap-subject : scripts/lib/runtime.sh introuvable depuis $FIXTURE_DIR" >&2
    exit 2
fi

source "$RUNTIME_LIB/logging.sh"
source "$RUNTIME_LIB/runtime.sh"

arm_err_trap

echo "TRAP-SUBJECT-AVANT"

false # TRAP-SUBJECT-FAILING-LINE

# Ne doit JAMAIS s'exécuter : la ligne ci-dessus est fatale.
echo "TRAP-SUBJECT-APRES"
