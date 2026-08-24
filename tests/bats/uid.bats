#!/usr/bin/env bats
# =============================================================================
# L'UID DEMANDÉ EST-IL RÉELLEMENT APPLIQUÉ DANS LES IMAGES ? (clôture 2.4)
# =============================================================================
#
# 🔴 POURQUOI CE FICHIER EXISTE, ET POURQUOI IL EST À PART.
# `docker/node/Dockerfile` acceptait un `ARG UID`, le documentait… et l'ignorait :
# `addgroup … || true && adduser … || true` échouent sur un utilisateur `node`
# qui existe DÉJÀ en uid 1000, et le `|| true` avalait l'échec. Conséquence
# mesurée en CI (run 32748093741) : `make npm-install` lance
# `docker exec -u 1001:1001`, l'uid 1001 n'avait aucune entrée `passwd`, `HOME`
# se résolvait en `/`, npm se rabattait sur `/.npm` et sortait en erreur 243.
#
# ⛔ UN GARDE TEXTUEL NE SUFFIT PAS ICI. Asserter que le Dockerfile CONTIENT
# « usermod » ne prouve pas que l'uid est appliqué — c'est précisément l'erreur
# que la version précédente commettait à l'envers (elle contenait « adduser » et
# n'appliquait rien). On EXÉCUTE donc le bloc d'ajustement, tel qu'il est écrit
# dans le Dockerfile, dans l'image de base réelle.
#
# ⚖️ VÉHICULE CHOISI, ET SES LIMITES, DITS PLUTÔT QUE SOUS-ENTENDUS :
#   • ce fichier EXIGE Docker — il ne peut donc pas vivre dans
#     `tests/bats/unit/`, dont l'en-tête promet « jouables en une seconde, sans
#     Docker ». Il a sa propre cible, `make test-bats-uid` ;
#   • il n'construit PAS l'image entière (une minute) : il rejoue le bloc
#     d'ajustement dans l'image de BASE, ce qui exerce exactement le code sous
#     test en quelques secondes ;
#   • le bloc est EXTRAIT du Dockerfile, jamais recopié : il ne peut pas
#     diverger de ce qui est réellement construit.
#
# L'installation complète, elle, est mesurée par `make test-bats-e2e`.
# =============================================================================

setup_file() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export REPO_ROOT

    if ! docker info > /dev/null 2>&1; then
        skip "Docker indisponible — ce fichier exige un démon Docker."
    fi
}

# Image de base d'un Dockerfile, LUE dedans (digest épinglé compris).
image_de_base() {
    awk '/^FROM /{print $2; exit}' "$REPO_ROOT/$1"
}

# Le bloc d'ajustement d'utilisateur, EXTRAIT du Dockerfile.
#
# On prend le `RUN set -eux; …` et ses continuations, on retire le `RUN ` de
# tête et les `\` de fin : ce qui reste est du shell exécutable tel quel.
bloc_ajustement() {
    awk '
        /^RUN set -eux;/ { dans = 1 }
        dans {
            ligne = $0
            sub(/^RUN /, "", ligne)
            sub(/[[:space:]]*\\$/, "", ligne)
            print ligne
            if ($0 !~ /\\$/) { exit }
        }
    ' "$REPO_ROOT/$1"
}

# Rejoue le bloc dans l'image de base, avec l'UID/GID demandés.
appliquer() {
    local dockerfile="$1" uid="$2" gid="$3"
    local base bloc
    base="$(image_de_base "$dockerfile")"
    bloc="$(bloc_ajustement "$dockerfile")"

    [ -n "$bloc" ] || { echo "bloc d'ajustement introuvable dans $dockerfile" >&2; return 1; }

    docker run --rm -u 0:0 -e UID="$uid" -e GID="$gid" --entrypoint sh "$base" -c "
        apk add --no-cache shadow > /dev/null 2>&1 || true
        ${bloc}
        echo \"RESULTAT=\$(getent passwd node | cut -d: -f3):\$(getent passwd node | cut -d: -f4):\$(getent passwd node | cut -d: -f6)\"
        echo \"HOME_PROPRIETAIRE=\$(stat -c %u /home/node)\"
    "
}

@test "le bloc d'ajustement est bien EXTRAIT du Dockerfile node, pas recopié" {
    # ⛔ Anti-vacuité de tout le fichier : si l'extraction rendait du vide, les
    # tests suivants exécuteraient un script vide et seraient verts pour rien.
    run bloc_ajustement docker/node/Dockerfile
    [ "$status" -eq 0 ]
    [[ "$output" == *"set -eux"* ]]
    [[ "$output" == *"node"* ]]
    [ "$(printf '%s\n' "$output" | wc -l)" -ge 4 ]
}

@test "un UID NON-1000 demandé est RÉELLEMENT appliqué, avec un HOME" {
    # 🔴 LE CAS DU RUNNER. Sans identité `passwd`, npm résout HOME=/ et meurt.
    run appliquer docker/node/Dockerfile 1001 1001
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESULTAT=1001:1001:/home/node"* ]]

    # ⛔ ET LE HOME LUI APPARTIENT. Sans ça, npm retrouve son identité mais pas
    # son cache : `/home/node/.npm` serait alors inécrivable pour lui.
    # ⚠️ On regarde le PROPRIÉTAIRE, jamais `test -w` : tout ceci s'exécute en
    # root, pour qui `-w` est toujours vrai. La première rédaction s'y est fait
    # prendre — la mutation « HOME chowné à root » restait VERTE.
    [[ "$output" == *"HOME_PROPRIETAIRE=1001"* ]]
}

@test "un second UID arbitraire l'est aussi — anti-coïncidence" {
    # Sans ce cas, un bloc qui figerait 1001 satisferait le test précédent.
    run appliquer docker/node/Dockerfile 1234 1234
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESULTAT=1234:1234:/home/node"* ]]
}

@test "UID=1000 laisse l'image STRICTEMENT inchangée" {
    # ⚖️ La moitié qui protège la machine de développement : sur un hôte en
    # uid 1000, rien ne doit bouger.
    run appliquer docker/node/Dockerfile 1000 1000
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESULTAT=1000:1000:/home/node"* ]]
    [[ "$output" == *"HOME_PROPRIETAIRE=1000"* ]]
}
