#!/bin/bash

# =============================================================================
# GARDE-FOU — aucun fichier source ou documentaire ne doit être exclu du dépôt
# =============================================================================
#
# Ce que ce script attrape
# ------------------------
# Un fichier présent sur le disque du développeur, ignoré par .gitignore, donc
# ABSENT après un `git clone`. C'est le mode de défaillance le plus vicieux de
# ce projet : tout est vert en local, et le dépôt est cassé pour tout le monde
# d'autre. Aucune erreur, aucun signal.
#
# Trois occurrences constatées, toutes causées par des patterns filtrant le NOM
# des fichiers plutôt qu'un chemin ou une extension :
#   `*token*`  -> src/resources/css/tokens.css      (livrable de la Story 1.8)
#   `*secret*` -> docs/adr/ADR-0006-...             (ADR référencé 4 fois)
#   `*backup*` -> docs/adr/ADR-0003-...,
#                 docs/architecture/8-architecture-backup-...,
#                 scripts/ops/backup-local.sh,
#                 scripts/ops/backup-offsite.sh     (toute la stratégie ADR-0003)
#
# Les deux premières ont été trouvées par accident. Celle-ci est le mécanisme
# qui les aurait trouvées à la première exécution.
#
# Pourquoi un script et pas un test Pest
# --------------------------------------
# Le conteneur php ne monte que `src/`. Le répertoire `.git` du dépôt lui est
# invisible, donc aucun test Pest ne peut interroger l'index git.

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m'
log() {
    case $1 in
        INFO)    echo -e "${BLUE}ℹ️  ${*:2}${NC}" ;;
        WARN)    echo -e "${YELLOW}⚠️  ${*:2}${NC}" ;;
        SUCCESS) echo -e "${GREEN}✅ ${*:2}${NC}" ;;
        ERROR)   echo -e "${RED}❌ ${*:2}${NC}" ;;
    esac
}

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Répertoires dont TOUT le contenu doit se retrouver dans un clone.
GUARDED=(
    ".github"
    "docs"
    "scripts"
    "src/app"
    "src/config"
    "src/database"
    "src/resources"
    "src/routes"
    "src/tests"
)

# Exceptions légitimes — chemins réellement destinés à rester hors du dépôt.
# Toute entrée ajoutée ici doit être justifiée : c'est le seul endroit où l'on
# peut affaiblir ce garde-fou, et il doit rester lisible en revue.
ALLOWED_REGEX='^(src/resources/css/app-compiled\.css|docs/.*\.local\.md)$'

log INFO "Recherche de fichiers ignorés dans les répertoires protégés…"

# --others --ignored : fichiers présents sur disque, non suivis, ET ignorés.
# C'est exactement la population dangereuse : ni suivie, ni signalée.
mapfile -t OFFENDERS < <(
    git ls-files --others --ignored --exclude-standard -- "${GUARDED[@]}" 2>/dev/null \
    | grep -vE "$ALLOWED_REGEX" || true
)

if [ ${#OFFENDERS[@]} -eq 0 ]; then
    log SUCCESS "Aucun fichier source ou documentaire n'est exclu du dépôt"
    exit 0
fi

log ERROR "${#OFFENDERS[@]} fichier(s) présent(s) en local mais ABSENT(S) d'un clone :"
echo ""
for f in "${OFFENDERS[@]}"; do
    rule="$(git check-ignore -v -- "$f" 2>/dev/null | awk '{print $1}')"
    printf "    %s\n        exclu par : %s\n" "$f" "${rule:-inconnu}"
done
echo ""
log INFO "Deux issues possibles :"
log INFO "  1. Le fichier DOIT être versionné -> ancrez le pattern .gitignore"
log INFO "     (par chemin ou extension), ne l'exemptez pas au cas par cas."
log INFO "  2. Le fichier doit rester local -> ajoutez-le à ALLOWED_REGEX ici,"
log INFO "     avec une justification visible en revue."
exit 1
