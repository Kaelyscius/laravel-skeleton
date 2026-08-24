#!/bin/sh
# -----------------------------------------------------------------------------
# `date -u -d <ISO 8601> +%s` de GNU, sur une machine qui n'a que BusyBox.
# -----------------------------------------------------------------------------
#
# 🔴 L'ENVIRONNEMENT DE MESURE, ENCORE — ET IL AURAIT DÉCIDÉ DU VERDICT.
# `nightly-freshness` calcule un âge en jours par `date -u -d "$last" +%s`. Sur
# le runner (`ubuntu-latest`), c'est GNU coreutils, qui lit l'ISO 8601 de l'API
# GitHub. Dans `laravel-app_php`, où `make test` exécute la sonde, `/bin/date`
# est **BusyBox** — mesuré le 2026-08-24 : `date -u -d "2026-08-20T03:17:00Z"
# +%s` y rend « invalid date », code 1.
#
# Sans ce shim, la sonde mourrait sur le binaire de la machine au lieu de
# mesurer la LOGIQUE du workflow, et elle rendrait un verdict différent selon
# qu'on la lance dans le conteneur ou sur le runner. On épingle donc le binaire,
# pas seulement l'interpréteur.
#
# ⚖️ PHP, ET NON python3 (revue 3). La première rédaction appelait `python3` :
# il existe bien dans l'image, mais il n'est déclaré dans AUCUN `apk add` du
# Dockerfile — c'est une dépendance TRANSITIVE, qui peut disparaître à la
# prochaine reconstruction sans que personne ne l'ait décidé. `php`, lui, est
# garanti partout où cette sonde tourne : c'est le lanceur de tests lui-même.
#
# ⛔ ET IL REFUSE CE QU'IL N'ÉMULE PAS. La rédaction précédente ignorait son 4e
# argument : `date -u -d "$x" +%Y` aurait rendu un horodatage epoch en silence.
# Seul `+%s` est émulé ; tout autre format sort en 64, en le disant.
# -----------------------------------------------------------------------------

if [ "$1" = "-u" ] && [ "$2" = "-d" ]; then
    if [ "$#" -ne 4 ] || [ "$4" != "+%s" ]; then
        echo "gnu-date-shim : seul « date -u -d <iso> +%s » est émulé (reçu : $*)." >&2
        exit 64
    fi

    if ! command -v php > /dev/null 2>&1; then
        echo "gnu-date-shim : « php » introuvable — le shim ne peut pas convertir l'horodatage." >&2
        exit 65
    fi

    SHIM_ISO="$3"
    export SHIM_ISO

    php -r '$t = strtotime((string) getenv("SHIM_ISO")); if ($t === false) { fwrite(STDERR, "gnu-date-shim : horodatage illisible : " . getenv("SHIM_ISO") . PHP_EOL); exit(66); } echo $t, PHP_EOL;'
    exit $?
fi

exec "${REAL_DATE:?REAL_DATE doit nommer le date RÉEL de la machine}" "$@"
