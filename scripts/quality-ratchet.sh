#!/bin/bash

# =============================================================================
# RATCHET QUALITÉ — plafond monotone sur ECS et PHPStan
# =============================================================================
#
# Pourquoi ce script plutôt qu'une baseline PHPStan
# --------------------------------------------------
# Une baseline PHPStan convertit la dette en configuration : les erreurs
# disparaissent du rapport et plus personne ne les voit. Ce projet a déjà assez
# de garde-fous verts qui ne gardent rien.
#
# Le ratchet fait l'inverse : les erreurs restent VISIBLES dans les rapports,
# mais leur nombre ne peut plus augmenter. On n'exige de personne qu'il répare
# les 9 erreurs héritées du scaffolding vendor — on interdit la 10e.
#
# Usage
# -----
#   scripts/quality-ratchet.sh            vérifie (exit 1 si un compteur monte)
#   scripts/quality-ratchet.sh --update   fige les compteurs actuels
#
# Le compteur est lu au format JSON des outils, jamais par comptage de lignes :
# un parseur de texte est exactement le genre d'assertion qui cesse
# silencieusement de fonctionner quand un outil change son affichage.

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

MODE="${1:-check}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE="$PROJECT_ROOT/src/quality-baseline.json"

# Où exécuter les outils ? Trois contextes possibles, testés dans cet ordre.
# Le troisième (runner CI) manquait initialement : le script tentait un
# `docker compose exec` sur une machine sans conteneur, et l'étape CI aurait
# échoué pour une raison sans rapport avec la dette qu'elle mesure.
if [ -d /var/www/html/vendor ]; then
    # 1. On est DANS le conteneur php
    run() { (cd /var/www/html && "$@"); }
    CONTEXT="conteneur php"
elif [ -d "$PROJECT_ROOT/src/vendor" ] && command -v php >/dev/null 2>&1; then
    # 2. Dépendances installées ET binaire PHP présent (runner CI)
    #
    # Le test `command -v php` n'est pas redondant : `src/` est bind-monté dans
    # les conteneurs, donc `src/vendor` existe AUSSI sur le poste de dev, qui
    # lui n'a pas forcément PHP. Sans ce second test, le poste de dev tombait
    # dans cette branche et invoquait un binaire inexistant.
    run() { (cd "$PROJECT_ROOT/src" && "$@"); }
    CONTEXT="local ($PROJECT_ROOT/src)"
else
    # 3. Poste de dev : on délègue au conteneur
    COMPOSE_BIN="${COMPOSE_BIN:-docker compose}"
    run() { $COMPOSE_BIN exec -T -u 1000:1000 -w /var/www/html php "$@"; }
    CONTEXT="docker compose exec php"
fi

[ -f "$BASELINE" ] || { log ERROR "Baseline introuvable : $BASELINE"; exit 1; }

log INFO "Contexte d'exécution : $CONTEXT"

log INFO "Mesure ECS…"
ECS_JSON="$(run vendor/bin/ecs check --output-format=json --no-progress-bar 2>/dev/null || true)"

log INFO "Mesure PHPStan…"
PHPSTAN_JSON="$(run vendor/bin/phpstan analyse --error-format=json --no-progress 2>/dev/null || true)"

# Le parsing vit dans python3 : jq n'est pas garanti présent sur une machine
# de fork-streamer, python3 l'est sur toutes les distributions ciblées.
export ECS_JSON PHPSTAN_JSON BASELINE MODE
python3 <<'PY'
import json, os, sys, re

def parse(raw, label):
    raw = (raw or "").strip()
    i = raw.find("{")
    if i < 0:
        print(f"❌ Sortie {label} illisible — l'outil n'a produit aucun JSON.")
        print(f"   Reçu : {raw[:200]!r}")
        sys.exit(1)
    try:
        return json.loads(raw[i:])
    except json.JSONDecodeError as e:
        print(f"❌ JSON {label} invalide : {e}")
        sys.exit(1)

ecs = parse(os.environ["ECS_JSON"], "ECS")
ps  = parse(os.environ["PHPSTAN_JSON"], "PHPStan")

current = {
    "ecs":     {"errors": int(ecs["totals"]["errors"]), "diffs": int(ecs["totals"]["diffs"])},
    "phpstan": {"file_errors": int(ps["totals"]["file_errors"])},
}

path = os.environ["BASELINE"]
with open(path, encoding="utf-8") as f:
    baseline = json.load(f)

if os.environ["MODE"] == "--update":
    baseline.update(current)
    baseline["_updated"] = os.environ.get("TODAY", baseline.get("_updated", ""))
    with open(path, "w", encoding="utf-8") as f:
        json.dump(baseline, f, indent=4, ensure_ascii=False)
        f.write("\n")
    print("✅ Baseline figée sur les compteurs actuels :")
    for tool, counts in current.items():
        for k, v in counts.items():
            print(f"     {tool}.{k} = {v}")
    sys.exit(0)

rows, risen, fallen = [], [], []
for tool, counts in current.items():
    for key, now in counts.items():
        was = int(baseline.get(tool, {}).get(key, 0))
        if now > was:
            state, marker = "MONTE", "❌"
            risen.append(f"{tool}.{key} : {was} -> {now}")
        elif now < was:
            state, marker = "baisse", "🎉"
            fallen.append(f"{tool}.{key} : {was} -> {now}")
        else:
            state, marker = "stable", "  "
        rows.append(f"  {marker} {tool}.{key:<12} plafond {was:>3}  actuel {now:>3}  {state}")

print("\n".join(rows))

if risen:
    print("\n❌ RATCHET ROMPU — un compteur de dette a augmenté :")
    for r in risen:
        print(f"     {r}")
    print("\n   Le ratchet est monotone : la dette ne remonte pas.")
    print("   Corrigez les nouvelles violations, ou justifiez explicitement")
    print("   une hausse en mettant à jour src/quality-baseline.json dans le")
    print("   même commit — pour qu'elle soit visible en revue.")
    sys.exit(1)

if fallen:
    print("\n🎉 La dette a baissé :")
    for f_ in fallen:
        print(f"     {f_}")
    print("\n   Figez le nouveau plafond : make quality-ratchet-update")
    print("   (sinon la marge regagnée pourra être reperdue en silence)")
    sys.exit(1)

print("\n✅ Ratchet respecté — aucun compteur n'a augmenté.")
PY
