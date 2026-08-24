#!/usr/bin/env bats
# =============================================================================
# GARDES DES PRIMITIVES DU E2E — jouables en une seconde (Story 2.4)
# =============================================================================
#
# 🔴 CE FICHIER EXISTE PARCE QUE `install.bats` NE SE REJOUE PAS.
# Le E2E coûte 20 à 40 minutes sur un runner nu et exige Docker : ses mutations
# ne peuvent pas être rejouées dans la boucle locale. Tout ce qui DÉCIDE d'un
# verdict — lecture du lockfile, calcul et jugement de la fenêtre, validation
# d'un horodatage, lecture d'un champ JSON, résolution de la CLI compose,
# contrôle des ports, étiquetage d'une panne d'infrastructure — vit donc dans
# `lib/e2e.bash` et est éprouvé ICI, où une mutation se rejoue en une seconde.
#
# ⚖️ LA FIXTURE DE LOCKFILE EST *PRODUITE*, PAS ÉCRITE À LA MAIN (revue 1).
# C'est la forme exacte du défaut de tête de la story 2.2 : une fixture qui
# décrit un état que la production ne connaît pas. `setup_file` lance donc le
# VRAI `scripts/install-lockfile.sh` contre des sondes stubées.
#
# `make test-bats` lance ce répertoire. `make test-bats-e2e` lance le E2E.
# =============================================================================

setup_file() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
    export REPO_ROOT

    FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/e2e-lockfile-fixture.XXXXXX")"
    export FIXTURE_DIR

    mkdir -p "$FIXTURE_DIR/app/.install-state" "$FIXTURE_DIR/bin"

    # Sondes stubées : le script interroge deux conteneurs, on lui répond.
    cat > "$FIXTURE_DIR/bin/docker" <<'STUB'
#!/usr/bin/env bash
# docker exec <conteneur> <commande...>
shift          # « exec »
shift          # nom du conteneur
case "$1" in
    php)  echo "8.5.0" ;;
    node) echo "v24.0.0" ;;
    *)    echo "commande stubée inattendue: $*" >&2; exit 1 ;;
esac
STUB
    chmod +x "$FIXTURE_DIR/bin/docker"

    printf '{"content-hash":"fixture"}\n' > "$FIXTURE_DIR/app/composer.lock"
    printf '{"lockfileVersion":3}\n' > "$FIXTURE_DIR/app/package-lock.json"
    printf '2026-08-23T10:00:00Z\n' > "$FIXTURE_DIR/app/.install-state/started-at"

    REPO_ROOT="$REPO_ROOT" \
    APP_DIR="$FIXTURE_DIR/app" \
    INSTALL_STATE_DIR="$FIXTURE_DIR/app/.install-state" \
    COMPOSER_LOCK="$FIXTURE_DIR/app/composer.lock" \
    NPM_LOCK="$FIXTURE_DIR/app/package-lock.json" \
    LOCKFILE="$FIXTURE_DIR/app/.install-state/lock.yml" \
    STARTED_AT_MARKER="$FIXTURE_DIR/app/.install-state/started-at" \
    DOCKER_BIN="$FIXTURE_DIR/bin/docker" \
    PHP_CONTAINER_NAME="fixture_php" \
    NODE_CONTAINER_NAME="fixture_node" \
        bash "$REPO_ROOT/scripts/install-lockfile.sh" > "$FIXTURE_DIR/lockfile.log" 2>&1

    GENERATED_LOCKFILE="$FIXTURE_DIR/app/.install-state/lock.yml"
    export GENERATED_LOCKFILE
}

teardown_file() {
    rm -rf -- "$FIXTURE_DIR"
}

setup() {
    load "../lib/e2e"

    E2E_REPORT_DIR="$BATS_TEST_TMPDIR/report"
    export E2E_REPORT_DIR
    mkdir -p "$E2E_REPORT_DIR"

    LOCKFILE="$BATS_TEST_TMPDIR/lock.yml"
    cp "$GENERATED_LOCKFILE" "$LOCKFILE"
    # `finished_at` est l'instant de génération ; on le fige pour que la fenêtre
    # attendue soit déterministe. `started_at` vient du marqueur ci-dessus.
    sed -i 's|^finished_at: .*|finished_at: "2026-08-23T10:07:30Z"|' "$LOCKFILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# La fixture elle-même
# ─────────────────────────────────────────────────────────────────────────────

@test "la fixture de lockfile est PRODUITE par scripts/install-lockfile.sh" {
    # ⛔ Anti-vacuité de tout le fichier : si le script n'avait rien écrit, tous
    # les tests suivants liraient une fixture écrite à la main — le défaut de
    # tête de la story 2.2, reconduit.
    [ -f "$GENERATED_LOCKFILE" ]
    grep -qF 'Généré par scripts/install-lockfile.sh' "$GENERATED_LOCKFILE"
    grep -qF 'php_version: "8.5.0"' "$GENERATED_LOCKFILE"
    grep -qF 'node_version: "24.0.0"' "$GENERATED_LOCKFILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# Lecture du lockfile
# ─────────────────────────────────────────────────────────────────────────────

@test "lit un champ scalaire du lockfile" {
    run e2e_lockfile_field "$LOCKFILE" started_at
    [ "$status" -eq 0 ]
    [ "$output" = "2026-08-23T10:00:00Z" ]
}

@test "REFUSE un champ absent plutôt que de rendre une chaîne vide" {
    run e2e_lockfile_field "$LOCKFILE" champ_inexistant
    [ "$status" -ne 0 ]
    [[ "$output" == *"absent"* ]]
}

@test "REFUSE un lockfile absent, et le DIT" {
    # 🔴 LE MESSAGE FAIT PARTIE DU GARDE, ET LA MUTATION L'A PROUVÉ. Sans
    # l'assertion sur « introuvable », retirer le contrôle d'existence laissait
    # le test VERT : la boucle de lecture échouait quand même, et le refus
    # tombait sur « champ absent » — un diagnostic FAUX sous un code de sortie
    # juste.
    run e2e_lockfile_field "$BATS_TEST_TMPDIR/nexiste-pas.yml" started_at
    [ "$status" -ne 0 ]
    [[ "$output" == *"introuvable"* ]]
}

@test "ne confond pas un champ avec un autre dont il est le préfixe" {
    # ⚠️ LE LEURRE EST PLACÉ AVANT, ET C'EST LA CONDITION DU TEST : posé après,
    # la première ligne rencontrée serait la bonne et l'assertion passerait même
    # avec une recherche par sous-chaîne.
    {
        printf 'php_version_extra: "9.9.9"\n'
        cat "$LOCKFILE"
    } > "$LOCKFILE.leurre"
    mv "$LOCKFILE.leurre" "$LOCKFILE"

    run e2e_lockfile_field "$LOCKFILE" php_version
    [ "$status" -eq 0 ]
    [ "$output" = "8.5.0" ]
}

@test "lit la DERNIÈRE ligne même sans saut final" {
    # Un lockfile tronqué à l'octet près par un disque plein perdait sa dernière
    # ligne : « champ absent » sur un champ pourtant écrit.
    printf 'schema: 1\nfinished_at: "2026-08-23T10:07:30Z"' > "$LOCKFILE"
    run e2e_lockfile_field "$LOCKFILE" finished_at
    [ "$status" -eq 0 ]
    [ "$output" = "2026-08-23T10:07:30Z" ]
}

@test "distingue un champ INDENTÉ d'un champ absent" {
    # Répondre « absent » sur un champ imbriqué envoie le lecteur chercher au
    # mauvais endroit : le champ est là, c'est la STRUCTURE qui a changé.
    printf 'racine:\n  started_at: "2026-08-23T10:00:00Z"\n' > "$LOCKFILE"
    run e2e_lockfile_field "$LOCKFILE" started_at
    [ "$status" -ne 0 ]
    [[ "$output" == *"INDENTÉ"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Horodatages
# ─────────────────────────────────────────────────────────────────────────────

@test "convertit un horodatage ISO UTC en époque" {
    run e2e_iso_to_epoch "1970-01-01T00:01:00Z"
    [ "$status" -eq 0 ]
    [ "$output" = "60" ]
}

@test "REFUSE un horodatage au mauvais format plutôt que de le laisser passer à date(1)" {
    # `date -d` accepte « yesterday », « now », « 5 » … Sans validation, un
    # marqueur corrompu deviendrait une fenêtre plausible et fausse sous exit 0.
    for mauvais in "hier" "2026-08-23 10:00:00" "2026-08-23T10:00:00" "now"; do
        run e2e_iso_to_epoch "$mauvais"
        [ "$status" -ne 0 ]
    done
}

@test "DIT que date(1) n'est pas GNU au lieu d'accuser l'horodatage" {
    # Le diagnostic est le garde : « inconvertible » enverrait chercher un
    # lockfile corrompu là où c'est l'outil qui ne sait pas lire.
    e2e_date_supports_iso_parsing() { return 1; }

    run e2e_iso_to_epoch "2026-08-23T10:00:00Z"
    [ "$status" -ne 0 ]
    [[ "$output" == *"coreutils GNU"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Fenêtre d'installation
# ─────────────────────────────────────────────────────────────────────────────

@test "calcule la fenêtre d'installation en secondes depuis le lockfile" {
    run e2e_install_window_seconds "$LOCKFILE"
    [ "$status" -eq 0 ]
    [ "$output" = "450" ]
}

@test "REFUSE une fenêtre négative au lieu de la ramener à zéro" {
    sed -i 's|^finished_at: .*|finished_at: "2026-08-23T09:00:00Z"|' "$LOCKFILE"
    run e2e_install_window_seconds "$LOCKFILE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"négative"* ]]
}

@test "REFUSE de calculer une fenêtre quand finished_at manque" {
    grep -v '^finished_at:' "$LOCKFILE" > "$LOCKFILE.tmp" && mv "$LOCKFILE.tmp" "$LOCKFILE"
    run e2e_install_window_seconds "$LOCKFILE"
    [ "$status" -ne 0 ]
}

@test "une fenêtre TROP COURTE est un échec, pas une bonne nouvelle" {
    # 🔴 Une installation entièrement court-circuitée par les sentinelles
    # d'idempotence (story 2.2) produit une fenêtre proche de zéro. Sans
    # plancher, le nightly la félicitait.
    run e2e_window_verdict 0 1 900
    [ "$status" -ne 0 ]
    [ "$output" = "trop-courte" ]
}

@test "une fenêtre au plafond est un échec" {
    run e2e_window_verdict 900 1 900
    [ "$status" -ne 0 ]
    [ "$output" = "trop-longue" ]
}

@test "une fenêtre plausible est acceptée" {
    run e2e_window_verdict 450 1 900
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Lecture JSON
# ─────────────────────────────────────────────────────────────────────────────

@test "lit un champ JSON par chemin pointé" {
    printf '%s' '{"status":"error","checks":{"database":{"status":"ok"}}}' > "$BATS_TEST_TMPDIR/h.json"

    run e2e_json_field "$BATS_TEST_TMPDIR/h.json" status
    [ "$status" -eq 0 ]
    [ "$output" = "error" ]

    run e2e_json_field "$BATS_TEST_TMPDIR/h.json" checks.database.status
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "le verdict GLOBAL ne peut pas être satisfait par une sonde imbriquée" {
    # 🔴 LE GARDE-FOU QUI NE GARDAIT RIEN (revue 1) : `grep -qF '\"status\":\"ok\"'`
    # matchait la sous-chaîne de `checks.database.status`. L'assertion du
    # verdict global était donc vraie tant qu'UNE sonde était verte.
    printf '%s' '{"status":"error","checks":{"database":{"status":"ok"}}}' > "$BATS_TEST_TMPDIR/h.json"

    run grep -qF '"status":"ok"' "$BATS_TEST_TMPDIR/h.json"
    [ "$status" -eq 0 ]   # le grep naïf passe…

    run e2e_json_field "$BATS_TEST_TMPDIR/h.json" status
    [ "$output" = "error" ]   # …alors que le verdict réel est « error »
}

@test "rend les scalaires NON textuels en JSON, pas en Python" {
    # 🔴 `print(True)` imprime « True » : aucune comparaison bats contre
    # « true » ne pouvait matcher, et un flottant sortait en notation Python
    # (revue 2). Les chaînes, elles, restent NUES — les entourer de guillemets
    # casserait toutes les comparaisons existantes.
    printf '%s' '{"vrai":true,"faux":false,"nb":1.5,"vide":null,"txt":"ok"}' > "$BATS_TEST_TMPDIR/s.json"

    run e2e_json_field "$BATS_TEST_TMPDIR/s.json" vrai
    [ "$output" = "true" ]

    run e2e_json_field "$BATS_TEST_TMPDIR/s.json" faux
    [ "$output" = "false" ]

    run e2e_json_field "$BATS_TEST_TMPDIR/s.json" nb
    [ "$output" = "1.5" ]

    run e2e_json_field "$BATS_TEST_TMPDIR/s.json" vide
    [ "$output" = "null" ]

    run e2e_json_field "$BATS_TEST_TMPDIR/s.json" txt
    [ "$output" = "ok" ]
}

@test "REFUSE un chemin JSON absent, et un document illisible" {
    printf '%s' '{"status":"ok"}' > "$BATS_TEST_TMPDIR/h.json"
    run e2e_json_field "$BATS_TEST_TMPDIR/h.json" checks.database.status
    [ "$status" -ne 0 ]

    printf '%s' 'pas du json' > "$BATS_TEST_TMPDIR/bad.json"
    run e2e_json_field "$BATS_TEST_TMPDIR/bad.json" status
    [ "$status" -ne 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# CLI compose et ports — les primitives qui décident si le nightly DÉMARRE
# ─────────────────────────────────────────────────────────────────────────────

@test "préfère docker-compose v1 quand il existe" {
    e2e_has_compose_v1() { return 0; }
    e2e_has_compose_v2() { return 0; }

    run e2e_resolve_compose
    [ "$status" -eq 0 ]
    [ "$output" = "docker-compose" ]
}

@test "retombe sur le greffon docker compose v2" {
    e2e_has_compose_v1() { return 1; }
    e2e_has_compose_v2() { return 0; }

    run e2e_resolve_compose
    [ "$status" -eq 0 ]
    [ "$output" = "docker compose" ]
}

@test "sans aucune CLI compose, échoue en INFRASTRUCTURE et laisse le marqueur" {
    e2e_has_compose_v1() { return 1; }
    e2e_has_compose_v2() { return 1; }

    run e2e_resolve_compose
    [ "$status" -ne 0 ]
    [ -f "$E2E_REPORT_DIR/INFRASTRUCTURE_FAILURE" ]
}

@test "un port occupé est refusé, et l'échec est étiqueté INFRASTRUCTURE" {
    e2e_port_is_busy() { [ "$1" = "8025" ]; }

    run e2e_assert_ports_free 80 443 8025
    [ "$status" -ne 0 ]
    [[ "$output" == *"8025"* ]]
    [ -f "$E2E_REPORT_DIR/INFRASTRUCTURE_FAILURE" ]
}

@test "des ports libres passent — anti-vacuité du test précédent" {
    e2e_port_is_busy() { return 1; }

    run e2e_assert_ports_free 80 443 8025
    [ "$status" -eq 0 ]
    [ ! -f "$E2E_REPORT_DIR/INFRASTRUCTURE_FAILURE" ]
}

@test "le VRAI corps de e2e_port_is_busy distingue un port lié d'un port fermé" {
    # 🔴 LES DEUX TESTS CI-DESSUS STUBENT LA FONCTION : le corps réel n'était
    # exécuté par RIEN. Vérifié en revue 2 — réintroduire exactement le défaut
    # de la passe 1 (fermeture du descripteur 3 dans le parent) donnait 31/31
    # ok. Le stubbing par couture avait déplacé la surface non testée d'un cran
    # au lieu de la supprimer.
    local port pid
    port="$(reserver_port)"
    pid="$(demarrer_serveur "$port" "$BATS_TEST_TMPDIR")"
    sleep 1

    # Le corps RÉEL, sur un port réellement lié.
    e2e_port_is_busy "$port"

    # ⛔ ET LE DESCRIPTEUR 3 DE BATS EST TOUJOURS VIVANT. C'est la régression de
    # la passe 1 : `exec 3<&-` s'exécutait dans le PARENT et fermait le fd que
    # Bats réserve à `>&3`. Cette écriture échoue si le défaut revient.
    echo "fd 3 toujours ouvert après la sonde de port" >&3

    arreter_serveur "$pid"

    # Anti-vacuité : une fois le serveur arrêté, le même port n'est plus occupé.
    local libre=0 attente=0
    while [ "$attente" -lt 50 ]; do
        if ! e2e_port_is_busy "$port"; then
            libre=1
            break
        fi
        sleep 0.1
        attente=$(( attente + 1 ))
    done
    [ "$libre" -eq 1 ]
}

@test "la liste des ports est DÉRIVÉE de compose, pas recopiée" {
    # 🔴 LE TEST PRÉCÉDENT RECOPIAIT LE LITTÉRAL DE LA FONCTION : il ne pouvait
    # rougir que si quelqu'un modifiait l'un sans l'autre — et il a laissé
    # passer DEUX erreurs (5432 omis, 8082 en trop). Celui-ci exerce la
    # DÉRIVATION sur un fichier compose fabriqué pour l'occasion : aucune liste
    # écrite à la main ne peut le satisfaire.
    command -v docker > /dev/null 2>&1 || skip "docker absent : la dérivation ne peut pas être exercée"

    mkdir -p "$BATS_TEST_TMPDIR/faux-projet"
    cat > "$BATS_TEST_TMPDIR/faux-projet/docker-compose.yml" <<'COMPOSE'
services:
  temoin:
    image: busybox
    ports:
      - "54321:1234"
  hors-profil:
    image: busybox
    profiles: ["dev-extra"]
    ports:
      - "54322:1234"
COMPOSE

    run e2e_published_ports "$BATS_TEST_TMPDIR/faux-projet"
    [ "$status" -eq 0 ]
    [[ "$output" == *"54321"* ]]

    # ⛔ ET LE PROFIL EST HONORÉ : `dev-extra` n'est jamais démarré par
    # `up-dev-full`. C'est l'erreur exacte qu'avait la liste écrite à la main.
    [[ "$output" != *"54322"* ]]
}

@test "les ports dérivés du VRAI dépôt contiennent 5432 et jamais 8082" {
    command -v docker > /dev/null 2>&1 || skip "docker absent"

    run e2e_published_ports "$REPO_ROOT"
    [ "$status" -eq 0 ]

    # 5432 est publié par docker-compose.dev.yml sur un service SANS profil :
    # il est donc TOUJOURS démarré, et il manquait à la liste écrite à la main.
    for port in 80 443 5432 1025 8025 8080 8081 9999; do
        [[ "$output" == *"$port"* ]]
    done

    # 8082 appartient à redis-commander (profil dev-extra) : jamais démarré.
    [[ "$output" != *"8082"* ]]
}

@test "REFUSE une liste VIDE, même quand compose répond parfaitement" {
    # 🔴 MUTATION VUE VERTE, D'OÙ CE TEST (revue 2). Le test voisin passe un
    # répertoire SANS compose : la fonction sort sur l'échec de `docker compose`
    # et n'atteint jamais la branche « liste vide ». Remplacer ce refus par un
    # repli silencieux (`ports="80"`) restait donc invisible — et un E2E parti
    # avec une liste de ports amputée aurait échoué sur « address already in
    # use » EN COURS d'installation, donc étiqueté INSTALLEUR.
    command -v docker > /dev/null 2>&1 || skip "docker absent"

    mkdir -p "$BATS_TEST_TMPDIR/sans-ports"
    cat > "$BATS_TEST_TMPDIR/sans-ports/docker-compose.yml" <<'COMPOSE'
services:
  muet:
    image: busybox
    command: ["true"]
COMPOSE

    run e2e_published_ports "$BATS_TEST_TMPDIR/sans-ports"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Aucun port publié"* ]]
}

@test "REFUSE de rendre une liste de ports quand compose ne répond pas" {
    # ⛔ Aucune valeur de repli : une liste incomplète ferait démarrer le E2E
    # sur des ports occupés, et l'échec serait imputé à l'installeur.
    mkdir -p "$BATS_TEST_TMPDIR/sans-compose"
    run e2e_published_ports "$BATS_TEST_TMPDIR/sans-compose"
    [ "$status" -ne 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Attente HTTP — trois verdicts du E2E en dépendent, et elle n'avait AUCUN test
# ─────────────────────────────────────────────────────────────────────────────
#
# 🔴 RELEVÉ EN REVUE 2 : la forcer à `return 0` laissait la suite VERTE et
# rendait INCONDITIONNELLE la garde anti-vacuité du E2E — celle qui vérifie que
# la pile revient à 200 après la coupure. Et l'en-tête de `lib/e2e.bash`
# réaffirmait, COMME CORRECTION DE LA PASSE 1, que tout ce qui décide d'un
# verdict y est couvert. Phrase fausse une seconde fois, pour une fonction que
# cette story a elle-même ajoutée.
#
# ⚖️ Serveur HTTP RÉEL (`python3 -m http.server`), pas de couture : c'est
# l'autre leçon de la revue 2, où le stubbing avait déplacé la surface non
# testée d'un cran.

# ─────────────────────────────────────────────────────────────────────────────
# Serveur HTTP jetable — utilitaires
# ─────────────────────────────────────────────────────────────────────────────
#
# 🔴 CES DEUX FONCTIONS SONT UN CORRECTIF, PAS UN CONFORT. La première rédaction
# lançait `(cd "$dir" && python3 -m http.server …) &` : `$!` est alors le pid du
# SOUS-SHELL, pas celui de python. `kill "$!"` laissait donc le serveur vivant,
# tenant le descripteur de sortie que Bats lit — et **bats restait suspendu
# indéfiniment**. Observé en rejouant les mutations : deux exécutions bloquées à
# cinq minutes d'intervalle, aucune sortie.
#
# Parade : `--directory` au lieu de `cd` (donc plus de sous-shell), `exec` pour
# que le pid survive au `sleep`, et TOUS les descripteurs détachés de ceux de
# Bats.

# Réserve un port libre en le liant puis en le relâchant.
reserver_port() {
    python3 -c '
import socket

s = socket.socket()
s.bind(("127.0.0.1", 0))
port = s.getsockname()[1]
s.close()
print(port)
'
}

# Démarre un serveur HTTP jetable, rend son PID RÉEL.
demarrer_serveur() {
    local port="$1" racine="$2" delai="${3:-0}"

    sh -c "sleep $delai; exec python3 -m http.server $port --bind 127.0.0.1 --directory '$racine'" \
        < /dev/null > /dev/null 2>&1 &

    printf '%s\n' "$!"
}

arreter_serveur() {
    local pid="$1"

    [ -n "$pid" ] || return 0
    kill "$pid" 2> /dev/null || true
    wait "$pid" 2> /dev/null || true
}

@test "rend le code attendu du premier coup quand le service répond" {
    local port pid
    port="$(reserver_port)"
    pid="$(demarrer_serveur "$port" "$BATS_TEST_TMPDIR")"
    sleep 1

    run e2e_wait_for_http "http://127.0.0.1:$port/" 200 5 1 "$BATS_TEST_TMPDIR/body" 5
    arreter_serveur "$pid"

    [ "$status" -eq 0 ]
    [ "$output" = "200" ]
}

@test "REJOUE réellement : un service qui démarre en retard finit par être vu" {
    # ⛔ C'EST LE GARDE DE LA BOUCLE. Sans reprise, Apache ou php-fpm encore en
    # chauffe donnaient un rouge instable, imputé à l'installeur. Une fonction
    # qui rendrait le premier code obtenu échouerait ici.
    local port pid
    port="$(reserver_port)"
    pid="$(demarrer_serveur "$port" "$BATS_TEST_TMPDIR" 3)"

    run e2e_wait_for_http "http://127.0.0.1:$port/" 200 12 1 "$BATS_TEST_TMPDIR/body" 5
    arreter_serveur "$pid"

    [ "$status" -eq 0 ]
    [ "$output" = "200" ]
}

@test "ABANDONNE en rendant le dernier code observé, jamais un succès de complaisance" {
    # Sur un port fermé, `curl` n'obtient rien : la fonction doit rendre « 000 »
    # et un statut non nul. Rendre 0 ici désarmerait les trois verdicts du E2E
    # qui s'appuient dessus.
    local port
    port="$(reserver_port)"

    run e2e_wait_for_http "http://127.0.0.1:$port/" 200 2 1 "$BATS_TEST_TMPDIR/body" 2
    [ "$status" -ne 0 ]
    [ "$output" = "000" ]
}

@test "ne confond pas « répond » et « répond ce qu'on attend »" {
    local port pid
    port="$(reserver_port)"
    pid="$(demarrer_serveur "$port" "$BATS_TEST_TMPDIR")"
    sleep 1

    # 404 : le service répond, mais pas le code attendu.
    run e2e_wait_for_http "http://127.0.0.1:$port/nexiste-pas" 200 2 1 "$BATS_TEST_TMPDIR/body" 5
    arreter_serveur "$pid"

    [ "$status" -ne 0 ]
    [ "$output" = "404" ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Étiquetage infrastructure
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# Les dernières lignes du journal — le diagnostic qui était JETÉ
# ─────────────────────────────────────────────────────────────────────────────

@test "les dernières lignes du journal APPARAISSENT réellement dans la sortie" {
    # 🔴 `tail … 2> /dev/null >&2` envoyait tout dans /dev/null : le test
    # d'installation rougissait sans rien montrer. Ici, `run` capture la sortie —
    # une redirection perdue rend un `output` VIDE, et le test rougit.
    seq 1 200 > "$BATS_TEST_TMPDIR/install.log"

    run e2e_print_log_tail "$BATS_TEST_TMPDIR/install.log" 80
    [ "$status" -eq 0 ]

    [ "$(printf '%s\n' "$output" | wc -l)" -eq 80 ]
    [[ "$output" == *"121"* ]]
    [[ "$output" == *"200"* ]]
    [[ "$output" != *"120"* ]]
}

@test "un journal VIDE ou ABSENT le DIT, et rend non nul" {
    : > "$BATS_TEST_TMPDIR/vide.log"

    run e2e_print_log_tail "$BATS_TEST_TMPDIR/vide.log" 80
    [ "$status" -ne 0 ]
    [ "$output" = "(journal absent)" ]

    run e2e_print_log_tail "$BATS_TEST_TMPDIR/inexistant.log" 80
    [ "$status" -ne 0 ]
    [ "$output" = "(journal absent)" ]
}

@test "le nombre de lignes demandé est HONORÉ, pas décoratif" {
    # ⛔ ANTI-VACUITÉ : sans ce test, `tail -n 80` codé en dur satisferait le
    # précédent alors que l'appelant demande un autre volume.
    seq 1 50 > "$BATS_TEST_TMPDIR/install.log"

    run e2e_print_log_tail "$BATS_TEST_TMPDIR/install.log" 5
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | wc -l)" -eq 5 ]
    [[ "$output" == *"46"* ]]
    [[ "$output" != *"45"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Capture du journal du conteneur — les trois chemins, sans Docker
#
# 🔴 CETTE FONCTION EXISTE PARCE QUE LE NIGHTLY NE POUVAIT PAS *MONTRER* SON
# ÉCHEC. Le conteneur php bouclait en redémarrage (le défaut même que la story
# corrige), `docker exec` échouait, et il ne restait qu'une bannière vide.
# La couture `DOCKER_BIN` permet d'éprouver ici, en une seconde, ce qui ne se
# manifeste qu'au bout de 20 à 40 minutes de E2E.
# ─────────────────────────────────────────────────────────────────────────────

# Fabrique un faux `docker` : `$1` = code de sortie de `exec` et son contenu,
# `$2` = code de sortie de `logs` et son contenu.
poser_docker_stub() {
    local exec_status="$1" exec_out="$2" logs_status="$3" logs_out="$4"

    DOCKER_BIN="$BATS_TEST_TMPDIR/docker"

    cat > "$DOCKER_BIN" <<STUB
#!/usr/bin/env bash
case "\$1" in
    exec)
        printf '%s' "$exec_out"
        [ -n "$exec_out" ] || printf 'exec indisponible\n' >&2
        exit $exec_status
        ;;
    logs)
        printf '%s' "$logs_out"
        exit $logs_status
        ;;
esac
echo "sous-commande docker inattendue: \$*" >&2
exit 127
STUB
    chmod +x "$DOCKER_BIN"
    export DOCKER_BIN
}

@test "capture le journal de RÉFÉRENCE et NOMME sa source" {
    poser_docker_stub 0 'Échec du module 20-database (code: 1)
' 0 'peu importe'

    run e2e_capture_container_log "e2e-install_php" "$BATS_TEST_TMPDIR/container.log"
    [ "$status" -eq 0 ]

    grep -qF "SOURCE DU JOURNAL : docker exec e2e-install_php" "$BATS_TEST_TMPDIR/container.log"
    grep -qF "/tmp/laravel-install-*.log" "$BATS_TEST_TMPDIR/container.log"
    grep -qF "Échec du module 20-database" "$BATS_TEST_TMPDIR/container.log"

    # ⛔ ANTI-SUBSTITUTION : tant que `docker exec` répond, `docker logs` n'est
    # PAS lu. Sa source ne doit donc apparaître nulle part.
    ! grep -qF "docker logs" "$BATS_TEST_TMPDIR/container.log"
}

@test "conteneur en REDÉMARRAGE : repli sur docker logs, source NOMMÉE" {
    # `docker exec` sur un conteneur qui redémarre échoue — c'est le cas mesuré
    # sur les deux nightlies rouges des 22 et 23/08.
    poser_docker_stub 1 '' 0 'Attente de postgres sur le port 5432...
PHP Fatal error: require(): Failed opening required vendor/autoload.php
'

    run e2e_capture_container_log "e2e-install_php" "$BATS_TEST_TMPDIR/container.log"
    [ "$status" -eq 0 ]

    grep -qF "SOURCE DU JOURNAL : docker logs e2e-install_php" "$BATS_TEST_TMPDIR/container.log"
    # ⛔ LA SOURCE EST DITE DIFFÉRENTE, EXPLICITEMENT : ce n'est pas le journal
    # d'`install.sh`, et un lecteur qui n'y trouve pas « Échec du module » doit
    # savoir pourquoi avant d'accuser l'installeur.
    grep -qF "PAS /tmp/laravel-install-*.log" "$BATS_TEST_TMPDIR/container.log"
    grep -qF "Failed opening required vendor/autoload.php" "$BATS_TEST_TMPDIR/container.log"
}

@test "un journal de référence VIDE déclenche le repli, pas un rapport vide" {
    # 🔴 `docker exec … cat /tmp/laravel-install-*.log` rend **0** quand le glob
    # ne matche rien (le `2>/dev/null` avale l'erreur de `cat`). Un test qui ne
    # regarderait que le code de sortie conclurait « journal capturé » sur un
    # fichier de zéro octet — un garde-fou vert sur une absence de preuve.
    poser_docker_stub 0 '' 0 'sortie du conteneur, faute de mieux'

    run e2e_capture_container_log "e2e-install_php" "$BATS_TEST_TMPDIR/container.log"
    [ "$status" -eq 0 ]

    grep -qF "SOURCE DU JOURNAL : docker logs" "$BATS_TEST_TMPDIR/container.log"
    grep -qF "sortie du conteneur, faute de mieux" "$BATS_TEST_TMPDIR/container.log"
}

@test "les DEUX sources en échec : statut non nul, et JAMAIS un fichier vide" {
    poser_docker_stub 1 '' 1 'Error: No such container: e2e-install_php'

    run e2e_capture_container_log "e2e-install_php" "$BATS_TEST_TMPDIR/container.log"
    [ "$status" -ne 0 ]

    [ -s "$BATS_TEST_TMPDIR/container.log" ]
    grep -qF "AUCUN journal du conteneur e2e-install_php" "$BATS_TEST_TMPDIR/container.log"
    grep -qF "No such container" "$BATS_TEST_TMPDIR/container.log"
}

@test "le repli ne RÉÉTIQUETTE pas : une panne d'infrastructure reste détectée" {
    # ⛔ CONTRAINTE ÉCRITE DE LA SPEC : changer de source ne doit pas transformer
    # une panne réseau en « échec de l'installeur ». La signature vit dans la
    # sortie du conteneur ; elle doit survivre au repli et rester trouvable par
    # l'étiquetage.
    poser_docker_stub 1 '' 0 'npm ERR! network Could not resolve host: registry.npmjs.org
'

    run e2e_capture_container_log "e2e-install_php" "$BATS_TEST_TMPDIR/container.log"
    [ "$status" -eq 0 ]

    run e2e_log_looks_like_infrastructure_failure "$BATS_TEST_TMPDIR/container.log"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Could not resolve host"* ]]
}

@test "la BANNIÈRE elle-même ne porte aucune signature d'infrastructure" {
    # 🔴 TÉMOIN : si le texte du repli contenait par mégarde l'une des treize
    # signatures, TOUT échec d'installeur capturé par ce chemin serait étiqueté
    # INFRASTRUCTURE — et le nightly cesserait d'accuser l'installeur, pour de
    # bon. On mesure la bannière SEULE, sur un contenu de conteneur neutre.
    poser_docker_stub 1 '' 0 'installation ordinaire, rien de special
'

    run e2e_capture_container_log "e2e-install_php" "$BATS_TEST_TMPDIR/container.log"
    [ "$status" -eq 0 ]

    run e2e_log_looks_like_infrastructure_failure "$BATS_TEST_TMPDIR/container.log"
    [ "$status" -ne 0 ]
}

@test "un échec d'infrastructure laisse un MARQUEUR relisible par le workflow" {
    run e2e_infra_fail "réseau du runner indisponible"
    [ "$status" -ne 0 ]
    [ -f "$E2E_REPORT_DIR/INFRASTRUCTURE_FAILURE" ]
    grep -qF "réseau du runner indisponible" "$E2E_REPORT_DIR/INFRASTRUCTURE_FAILURE"
}

@test "reconnaît une panne de résolveur dans un journal d'installation" {
    printf 'E: Temporary failure resolving deb.debian.org\n' > "$BATS_TEST_TMPDIR/install.log"
    run e2e_log_looks_like_infrastructure_failure "$BATS_TEST_TMPDIR/install.log"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Temporary failure resolving"* ]]
}

@test "lit TOUS les journaux, pas seulement le premier" {
    # 🔴 La première rédaction ne lisait qu'`install.log`. Or `composer` et `npm`
    # tournent DANS le conteneur : une panne DNS n'apparaît que dans
    # `install-container.log`, et l'échec était étiqueté INSTALLEUR.
    printf 'rien de special\n' > "$BATS_TEST_TMPDIR/a.log"
    printf 'curl: (6) Could not resolve host: registry.npmjs.org\n' > "$BATS_TEST_TMPDIR/b.log"
    run e2e_log_looks_like_infrastructure_failure "$BATS_TEST_TMPDIR/a.log" "$BATS_TEST_TMPDIR/b.log"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Could not resolve host"* ]]
}

@test "un port déjà pris pendant l'install est une panne d'INFRASTRUCTURE" {
    printf 'Error starting userland proxy: listen tcp4 0.0.0.0:8025: bind: address already in use\n' > "$BATS_TEST_TMPDIR/install.log"
    run e2e_log_looks_like_infrastructure_failure "$BATS_TEST_TMPDIR/install.log"
    [ "$status" -eq 0 ]
}

@test "n'étiquette PAS infrastructure un échec d'installeur ordinaire" {
    printf 'Échec du module 20-database (code: 1)\n' > "$BATS_TEST_TMPDIR/install.log"
    run e2e_log_looks_like_infrastructure_failure "$BATS_TEST_TMPDIR/install.log"
    [ "$status" -ne 0 ]
}

@test "ne déclenche PAS sur une ligne qui contient les mots sans la phrase" {
    {
        printf 'phase: dial-up legacy check\n'
        printf 'protocole: tcp/ip ok\n'
    } > "$BATS_TEST_TMPDIR/install.log"
    run e2e_log_looks_like_infrastructure_failure "$BATS_TEST_TMPDIR/install.log"
    [ "$status" -ne 0 ]
}
