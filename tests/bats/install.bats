#!/usr/bin/env bats
# =============================================================================
# INSTALLATION DE BOUT EN BOUT — LA PREMIÈRE VRAIE (Story 2.4)
# =============================================================================
#
# 🔴 CE QUE CE FICHIER CORRIGE. Les stories 2.1, 2.2 et 2.3 ont TOUTES été
# mergées avec la même réserve écrite : « aucune install complète n'a jamais été
# jouée ». Le module 10 est éprouvé au grain fonction, l'orchestrateur est sourcé
# avec `execute_module` remplacé par un compteur. Trois chemins que la 2.3 a
# rendus fatals ou vivants — `routes/web.php` absent, échec de sauvegarde du
# `.env`, repli `laravel new` ressuscité — n'ont tourné que contre des stubs.
#
# ─────────────────────────────────────────────────────────────────────────────
# CE QU'IL FAIT, DANS L'ORDRE
#
#   1. préflight : outils présents, ports libres, CLI compose résolue ;
#   2. `git clone` du dépôt dans un répertoire temporaire — un CLONE, donc
#      exactement ce que git suit, sans `vendor/`, sans `node_modules/`, sans
#      `.env` (tous ignorés) ;
#   3. `cp .env.example .env` — ce que fait un fork-streamer ;
#   4. `make install-dev-full` ;
#   5. verdicts : code de sortie, lockfile, fenêtre encadrée (plancher ET
#      plafond), `/health` à 200 avec les trois sondes, `/health` qui SAIT
#      rougir avec le conteneur postgres RÉELLEMENT arrêté, et rejeu de
#      l'installeur pour éprouver l'idempotence de la story 2.2.
#
# ⛔ DOCKER-IN-DOCKER EST EXCLU (arbitré dans la spec) : le job tourne SUR le
# runner, qui fournit déjà Docker et compose.
#
# ─────────────────────────────────────────────────────────────────────────────
# ⚠️ POUR LE JOUER EN LOCAL
#
#   make down            # les ports publiés doivent être libres
#   make test-bats-e2e
#
# La pile du test emploie son propre `COMPOSE_PROJECT_NAME` (`E2E_PROJECT`),
# donc elle ne partage aucun conteneur avec la pile de développement — mais
# elle partage les PORTS de l'hôte, d'où le refus explicite au préflight.
# =============================================================================

setup_file() {
    load "lib/e2e"

    E2E_ROOT="${E2E_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"
    E2E_WORKDIR="${E2E_WORKDIR:-$(mktemp -d "${TMPDIR:-/tmp}/e2e-install.XXXXXX")}"
    E2E_REPORT_DIR="${E2E_REPORT_DIR:-$E2E_WORKDIR/report}"
    E2E_PROJECT="${E2E_PROJECT:-e2e-install}"
    E2E_BASE_URL="${E2E_BASE_URL:-https://localhost}"
    E2E_WINDOW_MIN_SECONDS="${E2E_WINDOW_MIN_SECONDS:-1}"
    E2E_WINDOW_LIMIT_SECONDS="${E2E_WINDOW_LIMIT_SECONDS:-900}"
    E2E_HEALTH_MAX_TIME="${E2E_HEALTH_MAX_TIME:-60}"
    # Délai de passerelle d'Apache, mesuré sur cette pile : 60 s (il a rendu un
    # 504 à 60,0 s avant le portillon). La borne assertée est 45 s : elle prouve
    # « corps 503, pas timeout de passerelle » tout en absorbant la queue de
    # distribution de la résolution de nom — mesurée sur 11 échantillons,
    # conteneur postgres arrêté : **4,05 · 3,19 · 3,21 s** (php-fpm redémarré).
    # Le plancher est le résolveur — ~3,1 s par tentative, que PHP ne peut pas
    # borner ; le portillon borne le NOMBRE de tentatives, pas leur coût.
    E2E_GATEWAY_LIMIT_SECONDS="${E2E_GATEWAY_LIMIT_SECONDS:-45}"
    E2E_CLONE="$E2E_WORKDIR/clone"
    E2E_STATE="$E2E_WORKDIR/state"

    export E2E_ROOT E2E_WORKDIR E2E_REPORT_DIR E2E_PROJECT E2E_BASE_URL \
        E2E_WINDOW_MIN_SECONDS E2E_WINDOW_LIMIT_SECONDS E2E_HEALTH_MAX_TIME \
        E2E_GATEWAY_LIMIT_SECONDS E2E_CLONE E2E_STATE

    mkdir -p "$E2E_REPORT_DIR"

    # ── 1. Préflight ────────────────────────────────────────────────────────
    # `python3` en fait partie : `e2e_json_field` s'en sert pour ANALYSER la
    # réponse de `/health` au lieu d'y chercher une sous-chaîne.
    local tool
    for tool in git make docker curl python3; do
        command -v "$tool" > /dev/null 2>&1 \
            || e2e_infra_fail "Outil requis absent du runner : $tool" \
            || return 1
    done

    docker info > /dev/null 2>&1 \
        || e2e_infra_fail "Démon Docker injoignable." \
        || return 1

    local ports
    mapfile -t ports < <(e2e_published_ports)
    e2e_assert_ports_free "${ports[@]}" || return 1

    local compose
    compose="$(e2e_resolve_compose)" || return 1
    printf '%s\n' "$compose" > "$E2E_WORKDIR/compose-cli"

    # ── 2. Clone neuf ───────────────────────────────────────────────────────
    # `git clone` d'un dépôt local ne copie que ce que git SUIT : c'est le point
    # du test. Un `cp -a` du répertoire de travail embarquerait `vendor/`,
    # `node_modules/` et le `.env` de l'opérateur, et prouverait qu'une
    # installation déjà faite est déjà faite.
    git clone --quiet --no-hardlinks "$E2E_ROOT" "$E2E_CLONE" \
        > "$E2E_REPORT_DIR/clone.log" 2>&1 \
        || e2e_infra_fail "Clone impossible depuis $E2E_ROOT (voir clone.log)." \
        || return 1

    # ── 3. Configuration minimale, celle du README ──────────────────────────
    cp "$E2E_CLONE/.env.example" "$E2E_CLONE/.env"
    printf '\nCOMPOSE_PROJECT_NAME=%s\n' "$E2E_PROJECT" >> "$E2E_CLONE/.env"

    # ── 3 bis. MUTATION DÉLIBÉRÉE (optionnelle) ─────────────────────────────
    # 🔴 SANS CE LEVIER, PERSONNE NE SAIT SI LE NIGHTLY PEUT ROUGIR. L'AC exige
    # une mutation EXÉCUTÉE et un rouge OBSERVÉ, pas déduit. Reproductible d'un
    # clic (`workflow_dispatch`, entrée `mutate_module`) ou en local par
    # `E2E_MUTATE_MODULE=20-database make test-bats-e2e`.
    #
    # ⛔ LISTE BLANCHE, PAS CONCATÉNATION. La valeur vient d'une entrée de
    # workflow et finissait dans un CHEMIN (`scripts/install/$X.sh`) : un `../`
    # sortait du répertoire des modules. Elle est confrontée à la liste RÉELLE
    # lue dans `scripts/install.sh` — la même source que le garde `RESUME_FROM`
    # du Makefile, pour qu'un module ajouté ou renommé n'ait qu'un référent.
    #
    # ⚠️ ET CE N'EST PAS LE CONTRÔLE QUI BLOQUE RÉELLEMENT UNE TRAVERSÉE, LA
    # PHRASE HONNÊTE EST CELLE-CI (revue 2) : cette liste blanche ne vit que
    # dans le chemin de 20-40 minutes, jamais joué en revue. Ce qui arrête un
    # `../` avant qu'il n'atteigne quoi que ce soit, c'est le contrôle de
    # jeu de caractères du workflow (`nightly.yml`, step « Valider les entrées »,
    # `*[!a-z0-9-]*`), qui tourne en quelques secondes et refuse le point. La
    # liste blanche ici est la SECONDE barrière, et la meilleure erreur —
    # elle nomme les modules valides — pas la première.
    if [ -n "${E2E_MUTATE_MODULE:-}" ]; then
        local known
        known="$(sed -n '/^readonly INSTALL_MODULES=(/,/^)/p' "$E2E_CLONE/scripts/install.sh" \
            | sed -n 's/^[[:space:]]*"\([^":]*\):.*/\1/p')"

        local match=1 candidate
        while IFS= read -r candidate; do
            [ "$candidate" = "$E2E_MUTATE_MODULE" ] && match=0
        done <<< "$known"

        if [ "$match" -ne 0 ]; then
            e2e_infra_fail "E2E_MUTATE_MODULE=« $E2E_MUTATE_MODULE » n'est pas un module connu. Modules valides : $(echo "$known" | tr '\n' ' ')"

            return 1
        fi

        local module_file="$E2E_CLONE/scripts/install/${E2E_MUTATE_MODULE}.sh"

        {
            head -n 1 "$module_file"
            printf 'echo "MUTATION E2E: échec délibéré de %s" >&2\n' "$E2E_MUTATE_MODULE"
            printf 'exit 42\n'
            tail -n +2 "$module_file"
        } > "$module_file.mutated"
        mv "$module_file.mutated" "$module_file"
        chmod +x "$module_file"

        echo "⚠️ MUTATION ACTIVE sur $E2E_MUTATE_MODULE — ce run DOIT être rouge." >&3
    fi

    # ── 4. L'installation, pour de vrai ─────────────────────────────────────
    # ⛔ AUCUN `| tee` ICI. Sans `pipefail` — et le dépôt a délibérément choisi
    # de ne PAS l'armer (report W20, story 2.3) — le statut d'un pipeline est
    # celui de `tee`, donc un échec d'installation passerait pour un succès.
    # C'est exactement le mécanisme qui avait tué la branche de repli
    # `laravel new`. Redirection simple, statut lu directement.
    local install_status=0
    COMPOSE_PROJECT_NAME="$E2E_PROJECT" \
    make -C "$E2E_CLONE" DOCKER_COMPOSE="$compose" install-dev-full \
        > "$E2E_REPORT_DIR/install.log" 2>&1 || install_status=$?

    printf '%s\n' "$install_status" > "$E2E_STATE.install_status"

    # Le journal du conteneur, en plus de celui de `make` : `install.sh` y
    # écrit son détail (`/tmp/laravel-install-*.log`).
    # ⛔ LE STATUT N'EST PLUS AVALÉ (revue 1) : un `|| true` laissait un journal
    # VIDE et le grep « module fautif » ne rapportait rien SANS DIRE POURQUOI.
    # 🔁 LA CAPTURE VIT DÉSORMAIS DANS `lib/e2e.bash` (clôture 2.4), avec un
    # REPLI sur `docker logs` quand `docker exec` échoue — le cas exact d'un
    # conteneur php en boucle de redémarrage, qui est précisément la panne que
    # cette story corrige. La source retenue est NOMMÉE dans le rapport, et le
    # fichier n'est jamais vide. Éprouvée par `tests/bats/unit/e2e-lib.bats`.
    if ! e2e_capture_container_log "${E2E_PROJECT}_php" "$E2E_REPORT_DIR/install-container.log"; then
        echo "⚠️ Aucun journal du conteneur ${E2E_PROJECT}_php n'a pu être capturé — la bannière écrite dans install-container.log dit pourquoi." >&3
    fi

    # Étiquetage : un échec dont l'UN des journaux porte une signature de panne
    # d'infrastructure n'accuse pas l'installeur.
    if [ "$install_status" -ne 0 ]; then
        local signature
        if signature="$(e2e_log_looks_like_infrastructure_failure \
            "$E2E_REPORT_DIR/install.log" "$E2E_REPORT_DIR/install-container.log")"; then
            e2e_infra_fail "Installation interrompue sur une signature d'infrastructure : « $signature »." || true
        fi
    fi
}

teardown_file() {
    load "lib/e2e"

    if [ "${E2E_KEEP:-false}" = "true" ]; then
        echo "E2E_KEEP=true — pile et répertoire conservés : $E2E_WORKDIR" >&3

        return 0
    fi

    local compose
    compose="$(cat "$E2E_WORKDIR/compose-cli" 2> /dev/null || echo "docker compose")"

    if [ -d "$E2E_CLONE" ]; then
        (
            cd "$E2E_CLONE" || exit 0
            COMPOSE_PROJECT_NAME="$E2E_PROJECT" $compose \
                -f docker-compose.yml -f docker-compose.dev.yml \
                --profile dev --profile tools --profile dev-extra down -v \
                > /dev/null 2>&1 || true
        )
    fi

    # ⛔ Le clone porte des fichiers créés par des conteneurs tournant en root :
    # `rm -rf` sans élévation peut échouer.
    # ⚠️ `sudo -n` (revue 1) : un `sudo` interactif après 20-40 minutes de run
    # BLOQUE indéfiniment sur une machine sans sudo sans mot de passe. Un échec
    # de nettoyage ne doit ni bloquer, ni rougir.
    rm -rf -- "$E2E_CLONE" 2> /dev/null \
        || sudo -n rm -rf -- "$E2E_CLONE" 2> /dev/null \
        || echo "⚠️ Nettoyage partiel : $E2E_CLONE subsiste (droits root, sudo non disponible)." >&3
}

setup() {
    load "lib/e2e"
}

# -----------------------------------------------------------------------------
# ⛔ CASCADE : quand l'installation a échoué, un seul test rougit et NOMME la
# cause. Sans cela, lockfile / fenêtre / `/health` rougissaient tous pour des
# raisons DÉRIVÉES, et le rapport comptait cinq échecs pour un seul défaut.
# -----------------------------------------------------------------------------
skip_unless_installed() {
    local status_recorded
    status_recorded="$(cat "$E2E_STATE.install_status" 2> /dev/null || echo "absent")"

    if [ "$status_recorded" != "0" ]; then
        skip "installation en échec (code « $status_recorded ») — voir le premier test, qui nomme la cause"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────

@test "l'installation complète aboutit sur un clone neuf" {
    local status_recorded
    status_recorded="$(cat "$E2E_STATE.install_status" 2> /dev/null || echo "absent")"

    if [ "$status_recorded" != "0" ]; then
        echo "── 80 dernières lignes du journal d'installation ──" >&2

        # 🔴 L'ORDRE DES REDIRECTIONS JETAIT LE DIAGNOSTIC. La rédaction
        # précédente était `tail … 2> /dev/null >&2` : le shell applique de
        # GAUCHE À DROITE, donc fd2 pointait DÉJÀ sur /dev/null quand `>&2` l'a
        # dupliqué dans fd1. La sortie de `tail` partait intégralement dans
        # /dev/null — reproduit le 2026-08-24 sur l'hôte (bash 5.2, WSL2).
        # ⚖️ LA LECTURE VIT DÉSORMAIS DANS `lib/e2e.bash`, où `tests/bats/unit/`
        # peut MESURER que les lignes sortent bien — un ordre de redirections
        # « qui a l'air juste » est exactement ce qui a produit le défaut.
        e2e_print_log_tail "$E2E_REPORT_DIR/install.log" 80 >&2 || true

        if [ -f "$E2E_REPORT_DIR/INFRASTRUCTURE_FAILURE" ]; then
            echo "⚠️ Échec étiqueté INFRASTRUCTURE :" >&2
            cat "$E2E_REPORT_DIR/INFRASTRUCTURE_FAILURE" >&2
        else
            echo "❌ Échec attribué à l'INSTALLEUR." >&2
            # Le module fautif est NOMMÉ : `execute_module` (scripts/install.sh)
            # imprime « Échec du module <nom> (code: N) ».
            grep -F "Échec du module" "$E2E_REPORT_DIR/install.log" >&2 || true
            grep -F "Échec du module" "$E2E_REPORT_DIR/install-container.log" >&2 || true
        fi
    fi

    [ "$status_recorded" = "0" ]
}

@test "le lockfile d'installation existe et porte ses deux horodatages" {
    skip_unless_installed
    local lockfile="$E2E_CLONE/src/.install-state/lock.yml"

    [ -f "$lockfile" ]

    run e2e_lockfile_field "$lockfile" started_at
    [ "$status" -eq 0 ]

    run e2e_lockfile_field "$lockfile" finished_at
    [ "$status" -eq 0 ]
}

@test "la fenêtre d'installation est ENCADRÉE : ni nulle, ni au-delà de 15 minutes" {
    skip_unless_installed
    # ⚖️ UNE SEULE MESURE, ET C'EST CELLE DU LOCKFILE (contrainte de la spec).
    # ⛔ LE PLANCHER COMPTE AUTANT QUE LE PLAFOND : une installation entièrement
    # court-circuitée par les sentinelles d'idempotence produit une fenêtre
    # proche de zéro, que le seul plafond aurait félicitée.
    local lockfile="$E2E_CLONE/src/.install-state/lock.yml"

    run e2e_install_window_seconds "$lockfile"
    [ "$status" -eq 0 ]

    local window="$output"
    echo "Fenêtre d'installation mesurée : ${window} s (plancher ${E2E_WINDOW_MIN_SECONDS} s, plafond ${E2E_WINDOW_LIMIT_SECONDS} s)" >&3
    printf 'install_window_seconds=%s\n' "$window" >> "$E2E_REPORT_DIR/metrics.txt"

    run e2e_window_verdict "$window" "$E2E_WINDOW_MIN_SECONDS" "$E2E_WINDOW_LIMIT_SECONDS"
    [ "$output" = "ok" ]
    [ "$status" -eq 0 ]
}

@test "/health répond 200 et les trois sondes sont à ok" {
    skip_unless_installed
    # ⛔ LE CODE HTTP NE SUFFIT PAS, ET C'EST TOUT LE SUJET DE LA STORY. Avant
    # le 2026-08-23, `/health` rendait un JSON LITTÉRAL : il disait `ok` la base
    # à terre. On lit donc les TROIS sondes — et le verdict GLOBAL est lu par
    # ANALYSE JSON, pas par `grep` : `grep '"status":"ok"'` est satisfait par la
    # sous-chaîne d'une sonde imbriquée, donc il ne peut pas rougir seul.
    local body_file="$E2E_REPORT_DIR/health.json"
    local code

    run e2e_wait_for_http "$E2E_BASE_URL/health" 200 10 3 "$body_file" "$E2E_HEALTH_MAX_TIME"
    code="$output"
    echo "code=$code corps=$(cat "$body_file" 2> /dev/null)" >&3
    [ "$status" -eq 0 ]

    run e2e_json_field "$body_file" status
    [ "$output" = "ok" ]

    local sonde
    for sonde in database cache queue; do
        run e2e_json_field "$body_file" "checks.${sonde}.status"
        [ "$status" -eq 0 ]
        [ "$output" = "ok" ]
    done
}

@test "/health SAIT rougir : conteneur postgres RÉELLEMENT arrêté, corps 503 et réponse BORNÉE" {
    skip_unless_installed
    # 🔴 CE TEST EST LA LIGNE « SONDE LENTE » DE LA MATRICE GELÉE, ET LA PREMIÈRE
    # RÉDACTION L'AVAIT CONTOURNÉE : elle réécrivait `DB_HOST` pour obtenir un
    # `ECONNREFUSED` instantané — le chemin RAPIDE — parce que le chemin réel
    # ne tenait pas dans le délai de passerelle. Le seul test capable d'observer
    # le vrai mode de panne était celui écrit pour l'éviter.
    #
    # Un conteneur ARRÊTÉ retire son alias réseau : chaque tentative coûte alors
    # le délai du résolveur (3,13 s mesuré). Avant le portillon de
    # `BackendEndpoint`, le framework en enchaînait ~10 par sonde : 58,6 s de
    # réponse contre 60 s de passerelle, donc un 504 SANS CORPS sur un runner
    # plus lent. Avec le portillon, mesure finale du 2026-08-23 sur cette pile
    # (php-fpm redémarré, opcache frais), conteneur postgres réellement arrêté :
    # **4,05 · 3,19 · 3,21 s**. La borne assertée (45 s) laisse plus de dix fois
    # la marge observée tout en restant sous les 60 s de la passerelle — et elle
    # couvre aussi le cas où le portillon ne s'applique pas (pilote sans couple
    # hôte/port), où la tempête de reconnexions revient.
    #
    # Deux assertions, et il en faut deux : le CORPS `503` (pas un 504), et le
    # TEMPS sous la limite de passerelle.
    local body_file="$E2E_REPORT_DIR/health-degraded.json"
    local timing_file="$E2E_REPORT_DIR/health-degraded.time"

    docker stop "${E2E_PROJECT}_postgres" > /dev/null

    local code
    code="$(curl -skS --max-time "$E2E_HEALTH_MAX_TIME" \
        -o "$body_file" -w '%{http_code} %{time_total}' "$E2E_BASE_URL/health" 2> /dev/null || echo "000 0")"

    printf '%s\n' "$code" > "$timing_file"

    # Remontée AVANT toute assertion : un test qui échoue ne doit pas laisser la
    # pile dégradée pour les suivants.
    docker start "${E2E_PROJECT}_postgres" > /dev/null

    local http_code="${code%% *}"
    local elapsed="${code##* }"

    echo "postgres arrêté → code=$http_code total=${elapsed}s corps=$(cat "$body_file" 2> /dev/null)" >&3
    printf 'health_degraded_seconds=%s\n' "$elapsed" >> "$E2E_REPORT_DIR/metrics.txt"

    [ "$http_code" = "503" ]

    run e2e_json_field "$body_file" status
    [ "$output" = "error" ]

    run e2e_json_field "$body_file" checks.database.status
    [ "$output" = "error" ]

    # ⛔ LA BORNE TEMPORELLE — la lettre de la matrice gelée. `awk` parce que le
    # shell ne compare pas les décimaux.
    awk -v t="$elapsed" -v limite="$E2E_GATEWAY_LIMIT_SECONDS" \
        'BEGIN { exit (t < limite) ? 0 : 1 }'

    # ⛔ ANTI-VACUITÉ : la pile revient saine, donc `200` de nouveau. Sans cela,
    # un `/health` cassé en dur (503 constant) passerait ce test.
    run e2e_wait_for_http "$E2E_BASE_URL/health" 200 20 3 "$E2E_REPORT_DIR/health-back.json" "$E2E_HEALTH_MAX_TIME"
    [ "$status" -eq 0 ]
}

@test "rejouer l'installeur est SANS EFFET — l'idempotence de la story 2.2, éprouvée pour de vrai" {
    skip_unless_installed
    # 🔴 LA STORY 2.2 A LIVRÉ `ensure_idempotent` ET SES SENTINELLES, ET RIEN NE
    # LES AVAIT JAMAIS REJOUÉES SUR UNE VRAIE INSTALLATION (relevé revue 1).
    # Le E2E n'installait qu'une fois : le sujet même de la story précédente
    # n'était pas couvert par le seul test capable de le couvrir.
    local compose second_status=0
    compose="$(cat "$E2E_WORKDIR/compose-cli")"

    COMPOSE_PROJECT_NAME="$E2E_PROJECT" \
    make -C "$E2E_CLONE" DOCKER_COMPOSE="$compose" install-laravel \
        > "$E2E_REPORT_DIR/install-second-pass.log" 2>&1 || second_status=$?

    if [ "$second_status" -ne 0 ]; then
        echo "── 60 dernières lignes du second passage ──" >&2
        tail -n 60 "$E2E_REPORT_DIR/install-second-pass.log" >&2
    fi

    [ "$second_status" -eq 0 ]

    # Les sentinelles ont fait leur travail : les modules sont ANNONCÉS SAUTÉS.
    grep -qF "déjà" "$E2E_REPORT_DIR/install-second-pass.log"

    # Et l'application est toujours saine après le rejeu.
    run e2e_wait_for_http "$E2E_BASE_URL/health" 200 10 3 "$E2E_REPORT_DIR/health-after-replay.json" "$E2E_HEALTH_MAX_TIME"
    [ "$status" -eq 0 ]
}
