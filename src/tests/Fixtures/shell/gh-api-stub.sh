#!/bin/sh
# -----------------------------------------------------------------------------
# Stub de la CLI `gh`, pour EXÉCUTER le corps du job `nightly-freshness`.
# -----------------------------------------------------------------------------
#
# ⚖️ POURQUOI UN FICHIER VERSIONNÉ PLUTÔT QU'UN HEREDOC DANS LE TEST.
# Même arbitrage que `trap-subject.sh` : un sujet de sonde doit être relisible
# et lançable à la main. Un stub enfoui dans une chaîne PHP échappée trois fois
# ne se débogue pas, et personne ne peut vérifier ce qu'il répond réellement.
#
# ⛔ CE STUB NE DÉCIDE RIEN. Il rend, pour chaque appel d'API, la valeur que le
# test lui a mise dans l'environnement. Toute la logique — « un rouge amont est
# toléré si un vert existe dans la fenêtre » — reste dans `ci.yml`, qui est le
# sujet mesuré.
#
# 🔴 ET IL REFUSE CE QU'IL NE CONNAÎT PAS (revue 3). La rédaction précédente
# avait un `case` SANS branche par défaut : toute URL non prévue tombait dans le
# vide et le stub rendait 0 EN SILENCE. Un changement d'endpoint dans `ci.yml`
# n'aurait donc rien signalé — la sonde aurait mesuré un `gh` muet et conclu
# vert. Un stub qui ne sait pas répondre doit faire ÉCHOUER la sonde, jamais la
# laisser croire qu'elle a mesuré.
#
# Entrées (variables d'environnement) — la valeur `__API_DOWN__` simule, pour
# chaque endpoint, une API en échec (sortie 1) :
#   FIX_STATE          — `.state` du workflow (`active`, `disabled_inactivity`…).
#   FIX_DEFAULT_BRANCH — `.default_branch` du dépôt.
#   FIX_LAST           — `created_at` du dernier run ; VIDE = aucun run.
#   FIX_VERDICT        — `conclusion` du dernier run.
#   FIX_RUNID          — `id` du dernier run.
#   FIX_ARTIFACTS      — noms d'artefacts du dernier run, un par ligne.
#   FIX_GREEN          — `created_at` du dernier run VERT ; VIDE = aucun.
# -----------------------------------------------------------------------------

[ "$1" = "api" ] || exit 0

url="$2"

en_panne() {
    echo "gh: erreur API simulée sur $url" >&2
    exit 1
}

case "$url" in
    *"/actions/runs/"*"/artifacts"*)
        [ "${FIX_ARTIFACTS:-}" = "__API_DOWN__" ] && en_panne
        printf '%s\n' "${FIX_ARTIFACTS:-}"
        ;;

    *"/actions/workflows/nightly.yml/runs?status=success"*)
        [ "${FIX_GREEN:-}" = "__API_DOWN__" ] && en_panne
        printf '%s\n' "${FIX_GREEN:-}"
        ;;

    *"/actions/workflows/nightly.yml/runs?"*)
        [ "${FIX_LAST:-}" = "__API_DOWN__" ] && en_panne
        # `--jq '.workflow_runs[0] // empty | … | @tsv'` ne rend RIEN quand il
        # n'y a aucun run : on modélise ce silence, pas une ligne vide.
        if [ -n "${FIX_LAST:-}" ]; then
            printf '%s\t%s\t%s\n' "${FIX_LAST}" "${FIX_VERDICT:-}" "${FIX_RUNID:-}"
        fi
        ;;

    *"/actions/workflows/nightly.yml")
        [ "${FIX_STATE:-active}" = "__API_DOWN__" ] && en_panne
        printf '%s\n' "${FIX_STATE:-active}"
        ;;

    repos/*)
        # ⚠️ `*` MATCHE AUSSI LES `/` DANS UN `case` DE SHELL : `repos/*/*`
        # aurait avalé la quasi-totalité des URLs sous `repos/`, y compris
        # celles que ce stub ne connaît pas — la branche par défaut aurait été
        # rendue à la place d'un refus. On compte donc les segments :
        # `repos/<owner>/<repo>` en a exactement deux.
        if [ "$(printf '%s' "$url" | tr -cd '/' | wc -c)" -ne 2 ]; then
            echo "gh-api-stub : URL non stubée « $url » — la sonde mesurerait un gh muet." >&2
            exit 97
        fi

        [ "${FIX_DEFAULT_BRANCH:-main}" = "__API_DOWN__" ] && en_panne
        printf '%s\n' "${FIX_DEFAULT_BRANCH:-main}"
        ;;

    *)
        echo "gh-api-stub : URL non stubée « $url » — la sonde mesurerait un gh muet." >&2
        exit 97
        ;;
esac

exit 0
