#!/usr/bin/env bash
# =============================================================================
# PRIMITIVES DU TEST E2E D'INSTALLATION (Story 2.4)
# =============================================================================
#
# Ce fichier ne contient QUE des fonctions pures ou quasi-pures, et c'est
# délibéré : `tests/bats/install.bats` ne peut être joué qu'en 20 à 40 minutes
# sur un runner nu, donc rien de ce qui décide d'un verdict ne doit vivre
# uniquement là-bas. Ce qui est ici est éprouvé par `tests/bats/unit/`, qui
# tourne en une seconde et dont les mutations se rejouent dans la boucle locale.
#
# ⛔ « TOUT CE QUI DÉCIDE D'UN VERDICT EST ICI *ET* COUVERT » — cette phrase
# était FAUSSE au premier jet (revue 1) : la résolution de la CLI compose et le
# contrôle des ports, qui décident si le nightly démarre et à qui l'échec est
# imputé, n'avaient aucun test. Ils en ont désormais, par des COUTURES
# (`e2e_has_compose_v1`, `e2e_port_is_busy`) que le test remplace — plutôt que
# par un environnement qu'il faudrait fabriquer.
#
# ⚠️ RÈGLE DU DÉPÔT, APPLIQUÉE ICI AUSSI : jamais un moteur de motif là où un
# littéral est voulu. La story 2.3 a corrigé DEUX fois le même défaut (`-prune`
# sous `-depth`, puis un glob `-not -path` qu'un `[` dans le chemin cassait) et
# la 2.2 une troisième (`grep` en regex sur un nom de conteneur).
#
# ⛔ AUCUNE VALEUR DE REPLI. Une fenêtre d'installation qu'on ne sait pas lire
# n'est pas « zéro seconde » : c'est un refus. Même discipline que
# `scripts/install-lockfile.sh`, qui écrit ce lockfile.
# =============================================================================

# -----------------------------------------------------------------------------
# Échec ÉTIQUETÉ INFRASTRUCTURE.
#
# 🔴 POURQUOI CETTE DISTINCTION EXISTE : un nightly bloquant qui rougit pour le
# réseau du runner est désarmé en trois semaines. L'échec d'infrastructure est
# donc écrit dans un MARQUEUR que le workflow relit pour étiqueter le job, en
# plus d'être dit dans la sortie.
# -----------------------------------------------------------------------------
e2e_infra_fail() {
    local message="$1"

    mkdir -p "$E2E_REPORT_DIR"
    printf '%s\n' "$message" >> "$E2E_REPORT_DIR/INFRASTRUCTURE_FAILURE"

    echo "INFRASTRUCTURE_FAILURE: $message" >&2

    return 1
}

# -----------------------------------------------------------------------------
# Signatures d'un échec d'INFRASTRUCTURE dans un journal d'installation.
#
# ⚖️ C'est une HEURISTIQUE, et elle est nommée comme telle plutôt que présentée
# comme une preuve. Elle sert à ne pas accuser l'installeur d'une panne de
# registre ou de résolveur ; elle ne sert jamais à faire passer un échec pour
# bénin — le job reste ROUGE dans les deux cas, seule l'étiquette change.
#
# `grep -F` — comparaison LITTÉRALE. ⚠️ ET LA PHRASE HONNÊTE EST CELLE-CI :
# aucune des signatures ci-dessous ne porte de métacaractère, donc AUCUN TEST NE
# PEUT AUJOURD'HUI DISTINGUER `-F` DU MODE REGEX. Le drapeau est une précaution
# pour les signatures FUTURES et pour le journal lui-même, qui contient des
# chemins arbitraires. Il n'est pas gardé, et le prétendre serait exactement le
# défaut que ce dépôt traque.
#
# 🔴 LE TROU MESURÉ (run 32761876936, clôture 2.4). Un run lancé avec
# `mutate_module=20-database` a rougi AVANT d'atteindre la mutation : un `504`
# d'`api.github.com` pendant `composer install`, au module 10. Aucune des treize
# signatures d'alors ne connaissait de 5xx de registre, donc l'échec a été
# étiqueté **INSTALLEUR** — la mutation n'a pas tiré, et le rapport accusait le
# code. Les signatures de panne amont sont ajoutées ci-dessous.
#
# ⛔ ET LES CODES NUS `504` / `502` / `503` ONT ÉTÉ REFUSÉS, MESURE À L'APPUI.
# `grep -F 504` matche `Get:5 http://deb.debian.org … libxml2 amd64 [504 kB]` —
# une ligne d'`apt` parfaitement ordinaire, présente dans presque tout journal
# d'installation. Un vrai défaut d'installeur serait alors étiqueté
# INFRASTRUCTURE, et `nightly-freshness` le TOLÉRERAIT : le garde-fou
# anti-désarmement se désarmerait par sa propre heuristique. Les signatures
# retenues portent donc le code **avec son contexte HTTP**. Le témoin
# « une taille de paquet apt n'est pas une panne amont » garde ce choix.
#
# 🔴 ET LA MÊME INVERSION EST REVENUE PAR LA PORTE DE DERRIÈRE — RETIRÉE DEPUIS.
# La première rédaction de cette liste ajoutait aussi `could not be downloaded`
# et `Failed to download`, SANS contexte HTTP, trois lignes sous le commentaire
# qui refusait les codes nus pour cette raison exacte. Mesuré en revue :
#   • `Failed to download acme/nope from dist: … (HTTP/2 404)` → INFRASTRUCTURE.
#     Un paquet inexistant est un défaut de DÉPENDANCE, et il était absous.
#   • `Failed to download acme/pkg from dist, trying the source instead` — le
#     repli ORDINAIRE et bénin de composer — accompagné d'un vrai
#     `Échec du module` → INFRASTRUCTURE aussi.
# Les deux sont supprimées. Ce qui reste porte un **5xx**, et un 5xx n'est jamais
# imputable à l'installeur : c'est la passerelle d'en face qui a cédé. Les deux
# témoins « un 404 de dist reste INSTALLEUR » et « le repli dist→source reste
# INSTALLEUR » gardent ce retrait.
#
# ⚠️ CE QUE CETTE HEURISTIQUE NE SAIT TOUJOURS PAS FAIRE, et il faut le dire :
# `grep -F` compare une ligne à UN littéral, donc elle ne peut pas exiger
# « `from dist:` ET un 5xx sur la même ligne ». Elle ne distingue pas non plus un
# 5xx d'un registre d'un 5xx rendu par NOTRE apache. Ce second cas reste
# théorique — l'E2E n'interroge que `/health`, dont le code attendu est vérifié
# par `e2e_wait_for_http`, qui échoue en NOMMANT le code observé.
# -----------------------------------------------------------------------------
e2e_infrastructure_signatures() {
    cat <<'SIGNATURES'
Temporary failure resolving
Could not resolve host
Could not resolve hostname
TLS handshake timeout
toomanyrequests
429 Too Many Requests
i/o timeout
dial tcp
connection reset by peer
Cannot connect to the Docker daemon
no space left on device
address already in use
port is already allocated
502 Bad Gateway
503 Service Unavailable
504 Gateway Time-out
504 Gateway Timeout
HTTP/1.1 502
HTTP/1.1 503
HTTP/1.1 504
HTTP/2 502
HTTP/2 503
HTTP/2 504
SIGNATURES
}

# -----------------------------------------------------------------------------
# Rend 0 si l'UN des journaux passés porte une signature d'infrastructure.
#
# 🔴 IL EN FAUT PLUSIEURS, ET LA PREMIÈRE RÉDACTION N'EN LISAIT QU'UN : le
# workflow grepait `install.log` ET `install-container.log`, mais l'étiquetage
# ne regardait que le premier. Une panne DNS visible uniquement dans le journal
# du conteneur — le cas le plus fréquent, puisque `composer` et `npm` tournent
# là — était donc étiquetée INSTALLEUR.
# -----------------------------------------------------------------------------
e2e_log_looks_like_infrastructure_failure() {
    local logfile signature

    for logfile in "$@"; do
        [ -f "$logfile" ] || continue

        while IFS= read -r signature; do
            [ -n "$signature" ] || continue
            if grep -qF -- "$signature" "$logfile"; then
                echo "$signature"

                return 0
            fi
        done < <(e2e_infrastructure_signatures)
    done

    return 1
}

# -----------------------------------------------------------------------------
# Capture le journal d'installation ÉCRIT DANS LE CONTENEUR, et NOMME sa source.
#
# 🔴 CE QUI ÉTAIT CASSÉ. `install.bats` capturait ce journal par un seul
# `docker exec … cat /tmp/laravel-install-*.log`. Or le défaut que la story 2.4
# a fini par mesurer fait précisément BOUCLER le conteneur php
# (`set -e` + `restart: unless-stopped`) : `docker exec` sur un conteneur en
# redémarrage échoue, il ne restait qu'une bannière « INDISPONIBLE », et le grep
# « Échec du module » lisait un fichier sans contenu. Le nightly rougissait sans
# pouvoir MONTRER pourquoi.
#
# ⛔ REPLI, JAMAIS SUBSTITUTION — et c'est une contrainte écrite, pas un goût.
# Remplacer sèchement `docker exec` par `docker logs` change la SOURCE : on lit
# la sortie standard du conteneur au lieu de `/tmp/laravel-install-*.log`. Les
# lignes « Échec du module <nom> (code: N) » qu'`execute_module` écrit dans le
# journal n'y figurent pas forcément, et les signatures d'infrastructure
# (`e2e_infrastructure_signatures`) cesseraient de matcher au même endroit :
# une panne réseau serait alors réétiquetée INSTALLEUR. `docker logs` n'est donc
# atteint QUE lorsque `docker exec` a échoué ou n'a rien rendu, et le rapport
# DIT laquelle des deux sources il porte.
#
# ⛔ ET LE FICHIER N'EST JAMAIS VIDE. Même quand les deux sources échouent, une
# bannière explicite est écrite avec les deux codes de sortie et les deux
# messages d'erreur : un fichier vide est un diagnostic perdu, pas une absence
# de problème. Le code de retour, lui, reste non nul — l'appelant décide.
#
# `DOCKER_BIN` est la couture : elle existe pour que `tests/bats/unit/` puisse
# éprouver les trois chemins en une seconde, sans Docker.
# -----------------------------------------------------------------------------
e2e_capture_container_log() {
    local conteneur="$1" sortie="$2"
    local docker_bin="${DOCKER_BIN:-docker}"

    local bac
    bac="$(mktemp -d "${TMPDIR:-/tmp}/e2e-capture.XXXXXX")" || return 1

    local statut_exec=0 statut_logs=0

    "$docker_bin" exec "$conteneur" \
        sh -c 'cat /tmp/laravel-install-*.log 2>/dev/null' \
        > "$bac/exec.out" 2> "$bac/exec.err" || statut_exec=$?

    if [ "$statut_exec" -eq 0 ] && [ -s "$bac/exec.out" ]; then
        {
            echo "── SOURCE DU JOURNAL : docker exec $conteneur → /tmp/laravel-install-*.log ──"
            cat "$bac/exec.out"
        } > "$sortie"

        rm -rf -- "$bac"

        return 0
    fi

    "$docker_bin" logs --tail 500 "$conteneur" > "$bac/logs.out" 2>&1 || statut_logs=$?

    if [ "$statut_logs" -eq 0 ] && [ -s "$bac/logs.out" ]; then
        {
            echo "⚠️ Journal de référence indisponible : « docker exec $conteneur » a rendu $statut_exec, ou un journal vide."
            cat "$bac/exec.err"
            echo "── SOURCE DU JOURNAL : docker logs $conteneur (SORTIE DU CONTENEUR, PAS /tmp/laravel-install-*.log) ──"
            echo "   Repli : le conteneur était probablement en redémarrage. Les lignes « Échec du module »"
            echo "   n'y figurent que si l'installeur a écrit sur la sortie standard du conteneur."
            cat "$bac/logs.out"
        } > "$sortie"

        rm -rf -- "$bac"

        return 0
    fi

    {
        echo "⚠️ AUCUN journal du conteneur $conteneur n'a pu être capturé."
        echo "   « docker exec » a rendu $statut_exec ; le repli « docker logs » a rendu $statut_logs."
        echo "   (conteneur absent, arrêté ou en redémarrage — l'installation s'est probablement arrêtée avant de le démarrer)"
        echo "── Erreur de « docker exec » ──"
        cat "$bac/exec.err"
        echo "── Erreur de « docker logs » ──"
        cat "$bac/logs.out"
    } > "$sortie"

    rm -rf -- "$bac"

    return 1
}

# -----------------------------------------------------------------------------
# Imprime les N dernières lignes d'un journal — SUR STDOUT, et l'appelant redirige.
#
# 🔴 CETTE FONCTION EXISTE PARCE QUE LE DIAGNOSTIC ÉTAIT JETÉ. `install.bats`
# écrivait `tail -n 80 "$journal" 2> /dev/null >&2` : le shell applique les
# redirections DE GAUCHE À DROITE, donc fd2 pointait déjà sur /dev/null quand
# `>&2` l'a dupliqué dans fd1. La sortie de `tail` partait intégralement dans
# /dev/null. Reproduit le 2026-08-24 sur l'hôte (bash 5.2, WSL2). Le test
# rougissait en ne MONTRANT rien, sur le seul chemin où quelqu'un a besoin de
# lire le journal.
#
# ⚖️ ELLE ÉCRIT SUR STDOUT, ET C'EST LE POINT. Une fonction qui redirige
# elle-même vers `>&2` ne peut plus être éprouvée : `run` de Bats capture la
# sortie standard. En rendant la redirection à l'appelant, la présence des
# lignes devient MESURABLE plutôt qu'affirmée.
#
# ⛔ UN JOURNAL VIDE N'EST PAS UN JOURNAL ABSENT DE DIAGNOSTIC : on le DIT, et
# on rend non nul, plutôt que de laisser une sortie vide qui ressemble à un
# succès silencieux.
# -----------------------------------------------------------------------------
e2e_print_log_tail() {
    local fichier="$1" lignes="${2:-80}"

    if [ -s "$fichier" ]; then
        tail -n "$lignes" "$fichier"

        return 0
    fi

    echo "(journal absent)"

    return 1
}

# -----------------------------------------------------------------------------
# Lit un champ scalaire du lockfile d'installation.
#
# Le lockfile est écrit par `scripts/install-lockfile.sh` au format
# `champ: "valeur"`, une paire par ligne, sans imbrication. On ne convoque donc
# pas un analyseur YAML : on lit le PRÉFIXE LITTÉRAL de la ligne.
#
# ⚠️ `|| [ -n "$line" ]` : sans lui, `read` PERD la dernière ligne quand le
# fichier ne se termine pas par un saut. Un lockfile tronqué à l'octet près par
# un disque plein aurait rendu « champ absent » sur un champ pourtant écrit.
#
# ⛔ UN CHAMP INDENTÉ EST UN REFUS EXPLICITE, PAS UNE ABSENCE. Le format est
# plat ; une indentation signifie que quelqu'un a imbriqué la structure, et
# répondre « champ absent » enverrait le lecteur chercher au mauvais endroit.
# -----------------------------------------------------------------------------
e2e_lockfile_field() {
    local lockfile="$1" field="$2"

    if [ ! -f "$lockfile" ]; then
        echo "Lockfile introuvable: $lockfile" >&2

        return 1
    fi

    local line value found=1 indented=1
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            "$field: "*)
                value="${line#"$field": }"
                found=0
                break
                ;;
            [[:space:]]*"$field: "*)
                indented=0
                ;;
        esac
    done < "$lockfile"

    if [ "$found" -ne 0 ]; then
        if [ "$indented" -eq 0 ]; then
            echo "Champ « $field » présent mais INDENTÉ dans $lockfile — le format attendu est plat (« champ: valeur » en colonne 1)." >&2
        else
            echo "Champ « $field » absent de $lockfile" >&2
        fi

        return 1
    fi

    # Retire les guillemets encadrants, s'il y en a.
    value="${value#\"}"
    value="${value%\"}"

    if [ -z "$value" ]; then
        echo "Champ « $field » vide dans $lockfile" >&2

        return 1
    fi

    printf '%s\n' "$value"
}

# -----------------------------------------------------------------------------
# `date` sait-il convertir une date arbitraire (`-d`) ?
#
# 🔴 GNU SEULEMENT, ET C'ÉTAIT SILENCIEUX. `date -d` n'existe pas sur BSD/macOS
# (qui veut `-j -f`). La première rédaction rendait alors « horodatage
# inconvertible » : un diagnostic FAUX — l'horodatage est parfait, c'est l'outil
# qui ne sait pas le lire — sous un code de sortie juste.
# -----------------------------------------------------------------------------
e2e_date_supports_iso_parsing() {
    [ "$(date -u -d '1970-01-01T00:01:00Z' +%s 2> /dev/null)" = "60" ]
}

# -----------------------------------------------------------------------------
# Convertit un horodatage ISO-8601 UTC (`AAAA-MM-JJTHH:MM:SSZ`) en époque.
#
# ⛔ LE FORMAT EST VALIDÉ AVANT D'ÊTRE CONVERTI, comme
# `installation_started_at` le fait côté écriture. `date -d` accepte des
# chaînes très permissives : sans ce contrôle, un marqueur corrompu deviendrait
# une fenêtre d'installation plausible et fausse, sous un exit 0.
# -----------------------------------------------------------------------------
e2e_iso_to_epoch() {
    local iso="$1"

    if [[ ! "$iso" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
        echo "Horodatage invalide (« $iso ») — attendu AAAA-MM-JJTHH:MM:SSZ" >&2

        return 1
    fi

    if ! e2e_date_supports_iso_parsing; then
        echo "date(1) n'accepte pas « -d » : ce test exige les coreutils GNU (BSD/macOS demande « date -j -f »). L'horodatage « $iso » est valide, c'est l'OUTIL qui ne sait pas le lire." >&2

        return 1
    fi

    local epoch
    if ! epoch="$(date -u -d "$iso" +%s 2> /dev/null)"; then
        echo "Horodatage inconvertible (« $iso »)" >&2

        return 1
    fi

    printf '%s\n' "$epoch"
}

# -----------------------------------------------------------------------------
# Fenêtre d'installation, EN SECONDES, lue dans le lockfile.
#
# ⚖️ LA MESURE VIENT DU LOCKFILE, PAS D'UN CHRONOMÈTRE PARALLÈLE. La story 2.2 a
# construit `started_at`/`finished_at` exactement pour cet usage ; deux mesures
# divergentes vaudraient moins qu'une. Corollaire assumé : la fenêtre commence
# au premier passage d'`install.sh` et exclut donc la CONSTRUCTION des images,
# qui n'est pas de l'installation applicative.
#
# Une fenêtre négative est un REFUS, pas un zéro : elle signale une horloge qui
# a reculé ou un lockfile bricolé.
# -----------------------------------------------------------------------------
e2e_install_window_seconds() {
    local lockfile="$1"

    local started finished start_epoch end_epoch
    started="$(e2e_lockfile_field "$lockfile" started_at)" || return 1
    finished="$(e2e_lockfile_field "$lockfile" finished_at)" || return 1
    start_epoch="$(e2e_iso_to_epoch "$started")" || return 1
    end_epoch="$(e2e_iso_to_epoch "$finished")" || return 1

    local window=$(( end_epoch - start_epoch ))

    if [ "$window" -lt 0 ]; then
        echo "Fenêtre négative ($window s) : $started → $finished" >&2

        return 1
    fi

    printf '%s\n' "$window"
}

# -----------------------------------------------------------------------------
# Verdict sur une fenêtre : `ok`, `trop-courte` ou `trop-longue`.
#
# 🔴 « TROP COURTE » EST UN VERDICT, PAS UNE BONNE NOUVELLE (relevé revue 1).
# La première rédaction n'assertait que le plafond : une fenêtre de ZÉRO seconde
# — c'est-à-dire une installation entièrement COURT-CIRCUITÉE par les
# sentinelles d'idempotence de la story 2.2 — passait pour une installation
# rapide. Le nightly aurait félicité une install qui n'a rien fait.
# -----------------------------------------------------------------------------
e2e_window_verdict() {
    local window="$1" min="$2" max="$3"

    if [ "$window" -lt "$min" ]; then
        echo "trop-courte"

        return 1
    fi

    if [ "$window" -ge "$max" ]; then
        echo "trop-longue"

        return 1
    fi

    echo "ok"
}

# -----------------------------------------------------------------------------
# Lit un champ d'un document JSON par chemin pointé.
#
# 🔴 POURQUOI PAS `grep` : au premier jet, le verdict global était asserté par
# `grep -qF '"status":"ok"'` — une sous-chaîne que le champ IMBRIQUÉ
# `checks.database.status` satisfait à lui seul. L'assertion du verdict global
# ne pouvait donc pas rougir seule : elle était vraie tant qu'UNE sonde était
# verte. C'est la forme exacte du garde-fou qui ne garde rien.
#
# ⚖️ `python3` plutôt que `jq` : présent sur les runners GitHub ET dans la
# boucle locale (mesuré : `jq` ne l'est pas ici), et il ANALYSE le document au
# lieu d'y chercher un motif.
# -----------------------------------------------------------------------------
e2e_json_field() {
    local file="$1" path="$2"

    if [ ! -f "$file" ]; then
        echo "Document JSON introuvable: $file" >&2

        return 1
    fi

    python3 - "$file" "$path" <<'PYTHON'
import json
import sys

path = sys.argv[2]

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        node = json.load(handle)
except Exception as error:                       # noqa: BLE001
    print(f"JSON illisible ({sys.argv[1]}) : {error}", file=sys.stderr)
    raise SystemExit(1)

for segment in path.split("."):
    if not isinstance(node, dict) or segment not in node:
        print(f"Chemin « {path} » absent du document", file=sys.stderr)
        raise SystemExit(1)
    node = node[segment]

if isinstance(node, (dict, list)):
    print(f"Chemin « {path} » ne désigne pas un scalaire", file=sys.stderr)
    raise SystemExit(1)

# ⛔ RENDU **JSON**, PAS `repr` PYTHON (revue 2). `print(True)` imprime
# « True », que nulle comparaison bats contre `true` ne peut satisfaire ; un
# flottant sortait en notation Python. Les chaînes, elles, sont rendues NUES —
# `json.dumps` les entourerait de guillemets et casserait toutes les
# comparaisons existantes.
print(node if isinstance(node, str) else json.dumps(node))
PYTHON
}

# -----------------------------------------------------------------------------
# Coutures de détection de la CLI compose — remplaçables par un test.
# -----------------------------------------------------------------------------
e2e_has_compose_v1() {
    command -v docker-compose > /dev/null 2>&1
}

e2e_has_compose_v2() {
    docker compose version > /dev/null 2>&1
}

# -----------------------------------------------------------------------------
# Résout la CLI compose disponible, ou échoue en INFRASTRUCTURE.
#
# 🔴 Le Makefile pose `DOCKER_COMPOSE = docker-compose` (v1). Les images de
# runner GitHub récentes ne fournissent plus toujours ce binaire, seulement le
# greffon `docker compose` (v2). Une variable de LIGNE DE COMMANDE `make` prime
# sur une affectation du Makefile et se propage aux sous-`make` : c'est donc la
# porte prévue, et elle laisse la commande de l'opérateur inchangée quand
# `docker-compose` existe.
# -----------------------------------------------------------------------------
e2e_resolve_compose() {
    if e2e_has_compose_v1; then
        printf '%s\n' "docker-compose"

        return 0
    fi

    if e2e_has_compose_v2; then
        printf '%s\n' "docker compose"

        return 0
    fi

    e2e_infra_fail "Aucune CLI compose utilisable (ni « docker-compose », ni « docker compose »)."
}

# -----------------------------------------------------------------------------
# Un port de l'hôte est-il déjà pris ?
#
# ⛔ TOUT SE PASSE DANS UN SOUS-SHELL, ET C'EST UN CORRECTIF (revue 1). La
# première rédaction faisait `(exec 3<>/dev/tcp/…)` puis `exec 3<&-` DANS LE
# PARENT : elle fermait le descripteur 3, celui que Bats réserve à `>&3`, donc
# toute sortie de progression ultérieure disparaissait ou cassait.
# -----------------------------------------------------------------------------
e2e_port_is_busy() {
    local port="$1"

    (: < "/dev/tcp/127.0.0.1/$port") 2> /dev/null
}

# -----------------------------------------------------------------------------
# Refuse de démarrer si un port de la pile est déjà pris.
#
# Sur un runner c'est du zèle ; en local c'est la différence entre un test et
# une pile de développement écrasée. L'échec est étiqueté INFRASTRUCTURE parce
# qu'il ne dit rien de l'installeur.
# -----------------------------------------------------------------------------
e2e_assert_ports_free() {
    local port busy=""

    for port in "$@"; do
        if e2e_port_is_busy "$port"; then
            busy="$busy $port"
        fi
    done

    if [ -n "$busy" ]; then
        e2e_infra_fail "Ports déjà occupés sur l'hôte :$busy — arrêtez la pile locale (make down) avant de jouer ce test."

        return 1
    fi

    return 0
}

# -----------------------------------------------------------------------------
# Ports publiés par `make install-dev-full`, DÉRIVÉS DE COMPOSE.
#
# 🔴 DEUX RÉDACTIONS, DEUX LISTES FAUSSES — d'où la dérivation (revue 2).
#   • la 1ʳᵉ n'en vérifiait que deux (80, 443) : un Mailpit déjà lancé faisait
#     échouer `up-dev-full` EN COURS d'installation, donc étiqueté INSTALLEUR ;
#   • la 2ᵉ, écrite à la main, **omettait 5432** (publié par
#     `docker-compose.dev.yml` sur un service SANS profil, donc toujours
#     démarré) et **incluait 8082**, qui appartient à `redis-commander` en
#     profil `dev-extra` — jamais démarré par `up-dev-full`. Et son test
#     recopiait le littéral de la fonction : il ne pouvait rougir que si
#     quelqu'un modifiait l'un sans l'autre.
#
# ⚖️ MÊME CORRECTIF QUE `COMPOSITE_INSTALL_TARGETS` EN 2.3 : la liste est
# DÉRIVÉE du graphe qui fait autorité, pas énumérée à côté de lui. Les profils
# passés ici sont EXACTEMENT ceux de `make up-dev-full` (Makefile) : `dev` et
# `tools`, jamais `dev-extra`.
#
# ⛔ AUCUNE VALEUR DE REPLI : si compose ne rend pas la liste, on REFUSE. Une
# liste incomplète ferait démarrer le E2E sur des ports occupés, et l'échec
# serait imputé à l'installeur.
# ⚠️ `--env-file /dev/null` : la dérivation ne doit dépendre d'AUCUN `.env`
# (il n'y en a pas sur un runner). Mesuré : compose avertit sur les variables
# non posées et rend quand même la configuration — les ports sont des
# littéraux du fichier.
# -----------------------------------------------------------------------------
e2e_published_ports() {
    local root="${1:-${E2E_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." 2> /dev/null && pwd)}}"

    local files=(-f docker-compose.yml)
    [ -f "$root/docker-compose.dev.yml" ] && files+=(-f docker-compose.dev.yml)

    local config
    if ! config="$(cd "$root" && docker compose --env-file /dev/null "${files[@]}" \
        --profile dev --profile tools config --format json 2> /dev/null)"; then
        echo "docker compose config a échoué dans $root — impossible de dériver les ports publiés." >&2

        return 1
    fi

    local ports
    ports="$(printf '%s' "$config" | python3 -c '
import json, sys

document = json.load(sys.stdin)
published = {
    entry["published"]
    for service in document.get("services", {}).values()
    for entry in service.get("ports", [])
    if entry.get("published")
}
for port in sorted(published, key=int):
    print(port)
')" || {
        echo "Configuration compose illisible dans $root." >&2

        return 1
    }

    if [ -z "$ports" ]; then
        echo "Aucun port publié dérivé dans $root — refus plutôt que passage à l'aveugle." >&2

        return 1
    fi

    printf '%s\n' "$ports"
}

# -----------------------------------------------------------------------------
# Attend qu'une URL réponde le code attendu, ou rend le dernier code obtenu.
#
# 🔴 UN SEUL `curl` EST UN TEST INSTABLE (relevé revue 1) : Apache ou php-fpm
# peuvent encore chauffer quand `make` rend la main, et le rouge aurait été
# imputé à l'installeur. La reprise ne masque rien — elle attend un état, et
# elle finit par rendre le code réellement observé.
# -----------------------------------------------------------------------------
e2e_wait_for_http() {
    local url="$1" expected="$2" attempts="$3" delay="$4" outfile="$5" max_time="$6"
    local code="000" attempt=1

    while [ "$attempt" -le "$attempts" ]; do
        # 🔴 PAS DE `|| echo "000"` DANS LA SUBSTITUTION (trouvé par le test
        # « ABANDONNE en rendant le dernier code observé », revue 2) : sur une
        # connexion refusée, `curl -w` imprime DÉJÀ « 000 » puis sort non nul,
        # donc le repli s'ajoutait à la sortie et `$code` valait « 000\n000 ».
        # Toute comparaison ultérieure échouait pour la mauvaise raison.
        code="$(curl -skS --max-time "$max_time" -o "$outfile" -w '%{http_code}' "$url" 2> /dev/null)" || true
        [ -n "$code" ] || code="000"

        if [ "$code" = "$expected" ]; then
            printf '%s\n' "$code"

            return 0
        fi

        attempt=$(( attempt + 1 ))
        [ "$attempt" -le "$attempts" ] && sleep "$delay"
    done

    printf '%s\n' "$code"

    return 1
}
