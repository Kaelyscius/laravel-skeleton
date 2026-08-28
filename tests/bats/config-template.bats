#!/usr/bin/env bats
# =============================================================================
# LES GABARITS RENDENT-ILS LA VALEUR RÉELLEMENT EFFECTIVE ? (story 2.5)
# =============================================================================
#
# 🔴 POURQUOI CE FICHIER EXISTE, ET POURQUOI IL NE PEUT PAS ÊTRE UN TEST PEST.
# La story tient dans une distinction que Pest ne peut pas observer :
# `memory_limit` doit valoir `256M` POUR PHP-FPM et rester haut POUR LA CLI,
# dans le même conteneur. `make test` s'exécute sous le SAPI `cli` et un seul.
# Un garde écrit là-bas ne pourrait que relire le fichier rendu — c'est-à-dire
# prouver qu'on a bien écrit ce qu'on a écrit.
#
# ⛔ LA PREUVE PORTE DONC SUR `ini_get`, PAS SUR LE FICHIER. Un vrai `php-fpm`
# est démarré et interrogé en FastCGI par `cgi-fcgi` — le véhicule des
# healthchecks FPM standards. Ce que ces tests lisent est ce que php-fpm
# servirait à une requête HTTP.
#
# ⚖️ VÉHICULE CHOISI, ET SES LIMITES, DITS PLUTÔT QUE SOUS-ENTENDUS :
#   • ce fichier EXIGE Docker. Sans démon il se saute — SAUF si `CI` est
#     défini, où il ÉCHOUE bruyamment : une étape verte qui n'a mesuré aucune
#     valeur effective serait exactement le garde-fou silencieux que toute
#     cette story combat ;
#   • côté PHP il ne construit PAS l'image du projet (les extensions se
#     compilent en minutes) : il part de l'image de BASE, LUE dans le
#     Dockerfile, et y rejoue le RENDU RÉEL — `rendre_gabarit` sourcée depuis
#     l'entrypoint versionné, sur les gabarits versionnés. Le CONCURRENT de
#     `conf.d` (`composer-optimizations.ini`) est lui aussi EXTRAIT du
#     Dockerfile et rejoué, sans quoi la précédence — la découverte centrale de
#     la story — ne serait mesurée nulle part : dans l'image de base nue,
#     `99-fork.ini` gagnerait tout aussi bien, faute d'adversaire ;
#   • conséquence assumée : la ligne `gettext` du Dockerfile php n'est pas
#     exercée ici ; elle est gardée par `src/tests/Unit/ConfigTemplateTest.php` ;
#   • côté Apache, l'image du projet EST construite (apk + quelques `sed`) : le
#     vhost dépend des modules que ce Dockerfile active, et `httpd -t` sur une
#     image sans `mod_ssl` mesurerait autre chose. Le répertoire des gabarits y
#     est monté **`:ro`**, comme dans `docker-compose.yml` — la contrainte qui
#     justifie toute la conception est REPRODUITE, pas supposée, et un test la
#     mesure ;
#   • ni les entrypoints ni les gabarits ne sont RECOPIÉS : le dépôt est monté
#     et les sujets sont lus dedans. Ils ne peuvent pas diverger du livré.
#
# ⚠️ L'ENVIRONNEMENT DE LA MESURE EST NOMMÉ, PAS SUPPOSÉ : l'entrypoint php est
# sourcé par le `/bin/sh` de `php:8.5-fpm-alpine`, c'est-à-dire **BusyBox ash**,
# en **root** ; le bloc apache par le `/bin/bash` de `httpd:2.4-alpine`, en root
# lui aussi. Les binaires qui décident sont nommés : `envsubst` (gettext),
# `cgi-fcgi` (fcgi), `php-fpm`, `httpd`.
# =============================================================================

setup_file() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export REPO_ROOT

    if ! docker info > /dev/null 2>&1; then
        # ⛔ EN CI, UN SAUT EST UN MENSONGE VERT.
        if [ -n "${CI:-}" ]; then
            echo "Docker est indisponible alors que CI est défini." >&2
            echo "Ce fichier est le SEUL à mesurer une valeur de configuration effective :" >&2
            echo "le sauter rendrait l'étape verte sans avoir rien mesuré." >&2
            return 1
        fi
        skip "Docker indisponible — ce fichier exige un démon Docker."
    fi

    # Image de base du Dockerfile php, LUE dedans (digest épinglé compris).
    IMAGE_PHP="$(awk '/^FROM /{print $2; exit}' "$REPO_ROOT/docker/php/Dockerfile")"
    export IMAGE_PHP

    SONDE_DIR="$(mktemp -d)"
    case "$SONDE_DIR" in
        /tmp/*) ;;
        *) echo "bac hors /tmp : $SONDE_DIR" >&2; return 1 ;;
    esac
    export SONDE_DIR

    ecrire_sonde_php
    ecrire_bloc_apache
    ecrire_bloc_concurrent
    ecrire_stubs
    ecrire_gabarits_fautifs

    # ⚠️ TAG UNIQUE : un tag fixe ferait se disputer le même nom à deux
    # exécutions concurrentes (poste + CI, ou deux shells) — l'une reconstruit
    # pendant que l'autre mesure.
    IMAGE_APACHE="laravel-skeleton-apache-sonde:$$"
    export IMAGE_APACHE
    docker build -q -f "$REPO_ROOT/docker/apache/Dockerfile" -t "$IMAGE_APACHE" "$REPO_ROOT" > /dev/null
}

teardown_file() {
    case "${SONDE_DIR:-}" in
        /tmp/*) rm -rf -- "$SONDE_DIR" ;;
    esac

    if [ -n "${IMAGE_APACHE:-}" ]; then
        docker image rm -f "$IMAGE_APACHE" > /dev/null 2>&1 || true
    fi
}

# -----------------------------------------------------------------------------
# Le CONCURRENT de `conf.d`, EXTRAIT du Dockerfile — jamais recopié.
#
# C'est le `RUN { echo 'memory_limit=2G'; … } > …/composer-optimizations.ini`.
# On retire le `RUN ` de tête ; les continuations `\` restent, et ce qui subsiste
# est du shell exécutable tel quel.
# -----------------------------------------------------------------------------
ecrire_bloc_concurrent() {
    awk '
        /^RUN \{ \\$/ { dans = 1 }
        dans {
            ligne = $0
            sub(/^RUN /, "", ligne)
            print ligne
            if ($0 ~ /composer-optimizations\.ini$/) { exit }
        }
    ' "$REPO_ROOT/docker/php/Dockerfile" > "$SONDE_DIR/concurrent.sh"
}

# Bloc apache, EXTRAIT de l'entrypoint versionné — jamais recopié.
# De la première affectation (`HTTPD_CONF=`) jusqu'à l'APPEL `rendre_vhost`
# inclus : chemins, défauts, validation des valeurs, liste d'autorisation,
# fonction ET son appel.
ecrire_bloc_apache() {
    awk '
        /^HTTPD_CONF=/ { dans = 1 }
        dans { print }
        dans && /^rendre_vhost$/ { exit }
    ' "$REPO_ROOT/docker/apache/scripts/docker-entrypoint.sh" > "$SONDE_DIR/bloc-apache.sh"
}

# Stubs de binaires — épinglage, pas confort.
ecrire_stubs() {
    # `envsubst` qui VIDE la valeur des trois directives du vhost : la seule
    # façon d'atteindre la branche « directive sans valeur », que les défauts
    # rendent autrement inatteignable.
    printf '%s\n' \
        '#!/bin/sh' \
        'exec sed -E "s/^([[:space:]]*)(ServerName|ServerAlias|DocumentRoot) .*/\1\2/"' \
        > "$SONDE_DIR/envsubst-vide"
    chmod +x "$SONDE_DIR/envsubst-vide"
}

# Gabarits fautifs, posés dans des répertoires qui seront montés `:ro`.
ecrire_gabarits_fautifs() {
    mkdir -p "$SONDE_DIR/vhost-casse" "$SONDE_DIR/php-casse"

    cp "$REPO_ROOT/docker/apache/conf/sites-enabled/laravel.conf.template" \
       "$SONDE_DIR/vhost-casse/laravel.conf.template"
    # Une directive qui n'existe pas : refusée par `httpd -t`, et invisible à
    # toute relecture de gabarit.
    printf '%s\n' 'CetteDirectiveNExistePas oui' >> "$SONDE_DIR/vhost-casse/laravel.conf.template"

    cp "$REPO_ROOT/docker/php/conf/php-fpm-fork.conf.template" "$SONDE_DIR/php-casse/"
    # Un fragment de pool que `php-fpm -t` refuse (« unknown entry »).
    printf '%s\n' '[www]' 'directive_inexistante = 1' \
        > "$SONDE_DIR/php-casse/php-fpm-fork.conf.template"

    # Un `conf.d` portant une variable ABSENTE de la liste d'autorisation :
    # `envsubst` la laisse littérale, et PHP lirait la limite comme 0.
    mkdir -p "$SONDE_DIR/php-non-autorisee"
    cp "$REPO_ROOT/docker/php/conf/php-fpm-fork.conf.template" "$SONDE_DIR/php-non-autorisee/"
    printf '%s\n' 'memory_limit = ${VARIABLE_NON_AUTORISEE}' \
        > "$SONDE_DIR/php-non-autorisee/php-fork.ini.template"
}

# -----------------------------------------------------------------------------
# Sonde PHP : rend les deux gabarits, puis MESURE les deux SAPI.
# -----------------------------------------------------------------------------
ecrire_sonde_php() {
    cat > "$SONDE_DIR/php.sh" <<'SONDE'
#!/bin/sh
set -e

apk add --no-cache gettext fcgi > /dev/null 2>&1

# Le CONCURRENT de conf.d, si la sonde le demande — extrait du Dockerfile.
if [ "${AVEC_CONCURRENT:-}" = "oui" ]; then
    sh /sonde/concurrent.sh
    echo "CONCURRENT=$(grep '^memory_limit=' /usr/local/etc/php/conf.d/composer-optimizations.ini)"
fi

# Les gabarits sont posés là où le Dockerfile les COPIE.
mkdir -p /usr/local/etc/php/templates
cp /repo/docker/php/conf/php-fork.ini.template /usr/local/etc/php/templates/
cp /repo/docker/php/conf/php-fpm-fork.conf.template /usr/local/etc/php/templates/

# ⛔ LE SUJET EST LU DANS LE DÉPÔT, PAS RECOPIÉ ICI.
LARAVEL_ENTRYPOINT_SOURCE_ONLY=true
export LARAVEL_ENTRYPOINT_SOURCE_ONLY
. /repo/docker/php/scripts/docker-entrypoint.sh

# ----------------------------------------------------------------------------
# 🔴 LES APPELS SONT EXTRAITS DE L'ENTRYPOINT, PAS RECOPIÉS ICI.
#
# La première rédaction de cette sonde écrivait elle-même
# `rendre_gabarit … "$PHP_CONF_D/zz-fork.ini"`. Conséquence MESURÉE le
# 2026-08-28 : renommer la cible en `99-fork.ini` DANS L'ENTRYPOINT laissait
# les 19 tests VERTS — la sonde continuait de rendre `zz-fork.ini`, donc de
# mesurer un nom qui n'était plus celui de la production. Le test de
# précédence, raison d'être de ce fichier, était vert sur le défaut exact
# qu'il existe pour attraper. On joue donc les LIGNES D'APPEL du sujet.
# ----------------------------------------------------------------------------
APPELS="$(grep -E '^rendre_gabarit ' /repo/docker/php/scripts/docker-entrypoint.sh)"

# Anti-vacuité : sans appel extrait, tout ce qui suit mesurerait une image nue.
NB_APPELS="$(printf '%s\n' "$APPELS" | grep -c '^rendre_gabarit ')"
echo "APPELS_EXTRAITS=$NB_APPELS"

# Les noms de cible, LUS dans ces mêmes lignes.
NOM_INI="$(printf '%s\n' "$APPELS" | sed -n 's|.*\$PHP_CONF_D/\([^"]*\)".*|\1|p' | head -1)"
NOM_POOL="$(printf '%s\n' "$APPELS" | sed -n 's|.*\$PHP_FPM_D/\([^"]*\)".*|\1|p' | head -1)"
echo "CIBLE_INI=$NOM_INI"
echo "CIBLE_POOL=$NOM_POOL"

CIBLE_INI="$PHP_CONF_D/$NOM_INI"
CIBLE_POOL="$PHP_FPM_D/$NOM_POOL"

jouer_rendus() {
    eval "$APPELS"
}

AVANT_INI="$(cksum < "$PHP_TEMPLATE_DIR/php-fork.ini.template")"
AVANT_POOL="$(cksum < "$PHP_TEMPLATE_DIR/php-fpm-fork.conf.template")"

jouer_rendus > /dev/null 2>&1

UN_INI="$(cksum < "$CIBLE_INI")"
UN_POOL="$(cksum < "$CIBLE_POOL")"

# ⚖️ SECOND RENDU, À CHAUD : c'est le deuxième démarrage d'un conteneur qui
# `restart: unless-stopped`, donc le cas nominal, pas un cas limite.
jouer_rendus > /dev/null 2>&1

if [ "$UN_INI" = "$(cksum < "$CIBLE_INI")" ] \
   && [ "$UN_POOL" = "$(cksum < "$CIBLE_POOL")" ]; then
    echo "REJOUABLE=identique"
else
    echo "REJOUABLE=divergent"
fi

if [ "$AVANT_INI" = "$(cksum < "$PHP_TEMPLATE_DIR/php-fork.ini.template")" ] \
   && [ "$AVANT_POOL" = "$(cksum < "$PHP_TEMPLATE_DIR/php-fpm-fork.conf.template")" ]; then
    echo "GABARITS=intacts"
else
    echo "GABARITS=reecrits"
fi

# ⛔ AUCUNE DIRECTIVE VIDE, ET AUCUN MARQUEUR NON SUBSTITUÉ, dans le rendu.
if grep -Eq '^[[:space:]]*[A-Za-z_][^=]*=[[:space:]]*$' \
        "$CIBLE_INI" "$CIBLE_POOL"; then
    echo "DIRECTIVE_VIDE=oui"
else
    echo "DIRECTIVE_VIDE=non"
fi

if grep -Eq '[$][{][A-Za-z_][A-Za-z0-9_]*[}]' \
        "$CIBLE_INI" "$CIBLE_POOL"; then
    echo "MARQUEUR_RESIDUEL=oui"
else
    echo "MARQUEUR_RESIDUEL=non"
fi

# La CLI, mesurée par PHP lui-même.
echo "CLI_MEMORY=$(php -r 'echo ini_get("memory_limit");')"

# FPM, mesuré PAR UNE REQUÊTE. C'est la seule mesure qui distingue cette story
# d'un fichier bien écrit au mauvais endroit.
printf '%s\n' '<?php echo "FPM_MEMORY=".ini_get("memory_limit")."\n"."FPM_TIME=".ini_get("max_execution_time")."\n";' > /tmp/mesure.php
chmod 644 /tmp/mesure.php

php-fpm -D
essai=0
while [ "$essai" -lt 20 ]; do
    if SCRIPT_NAME=/mesure.php SCRIPT_FILENAME=/tmp/mesure.php REQUEST_METHOD=GET \
        cgi-fcgi -bind -connect 127.0.0.1:9000 2> /dev/null | grep -q 'FPM_MEMORY='; then
        break
    fi
    essai=$((essai + 1))
    sleep 1
done

SCRIPT_NAME=/mesure.php SCRIPT_FILENAME=/tmp/mesure.php REQUEST_METHOD=GET \
    cgi-fcgi -bind -connect 127.0.0.1:9000
echo
SONDE
}

# Lance la sonde php dans l'image de BASE, avec l'environnement demandé.
mesurer_php() {
    docker run --rm -u 0:0 "$@" \
        -v "$REPO_ROOT:/repo:ro" -v "$SONDE_DIR:/sonde:ro" \
        --entrypoint sh "$IMAGE_PHP" /sonde/php.sh
}

# Refus d'un rendu php : gabarit fautif monté `:ro`, cible précédente établie
# au premier passage. `$1` désigne la variable de répertoire du rendu visé
# (`PHP_FPM_D` ou `PHP_CONF_D`) ; `$2` le répertoire de gabarits fautifs.
php_rendu_refuse() {
    local variable="$1"
    local gabarits="$2"

    docker run --rm -u 0:0 -e VARIABLE_VISEE="$variable" \
        -v "$REPO_ROOT:/repo:ro" \
        -v "$SONDE_DIR/$gabarits:/gabarits-casse:ro" \
        --entrypoint sh "$IMAGE_PHP" -c '
            set -e
            apk add --no-cache gettext > /dev/null 2>&1
            mkdir -p /usr/local/etc/php/templates
            cp /repo/docker/php/conf/*.template /usr/local/etc/php/templates/

            LARAVEL_ENTRYPOINT_SOURCE_ONLY=true
            export LARAVEL_ENTRYPOINT_SOURCE_ONLY
            . /repo/docker/php/scripts/docker-entrypoint.sh

            # 🔴 L APPEL EST EXTRAIT DE L ENTRYPOINT, VALIDATEUR COMPRIS.
            # La première rédaction écrivait `rendre_gabarit … valider_pool_fpm`
            # elle-même : retirer le validateur DANS L ENTRYPOINT laissait ce
            # test VERT (mesuré le 2026-08-28), puisque la sonde continuait de
            # le passer. Le garde était vert sur sa propre suppression.
            APPEL_POOL="$(grep -E "^rendre_gabarit .*$VARIABLE_VISEE" /repo/docker/php/scripts/docker-entrypoint.sh)"
            echo "APPEL_POOL=[$APPEL_POOL]"

            NOM="$(printf "%s\n" "$APPEL_POOL" | sed -n "s|.*[\$]$VARIABLE_VISEE/\([^\"]*\)\".*|\1|p" | head -1)"
            eval "REPERTOIRE=\$$VARIABLE_VISEE"
            CIBLE="$REPERTOIRE/$NOM"

            # 1er passage : les gabarits VERSIONNÉS, pour quil existe une cible.
            eval "$APPEL_POOL" > /dev/null 2>&1
            echo "PASSE1=$(cksum < "$CIBLE")"

            # 2e passage : MÊME ligne dappel, gabarits FAUTIFS montés `:ro`.
            PHP_TEMPLATE_DIR=/gabarits-casse
            statut=0
            ( eval "$APPEL_POOL" ) > /tmp/passe2.log 2>&1 || statut=$?

            echo "STATUT=$statut"
            echo "PASSE2=$(cksum < "$CIBLE")"
            echo "=== SORTIE ==="
            grep -v "^\[" /tmp/passe2.log || true
            echo "=== FIN ==="
        '
}

# Lance le bloc apache dans l'image DU PROJET.
#
# `$1` : « VERSIONNE » (gabarit du dépôt) ou « CASSE » (gabarit fautif). Les
# DEUX vivent sur un montage `:ro`, comme en production.
apache_rendu() {
    local variante="$1"; shift

    docker run --rm -u 0:0 -e VARIANTE="$variante" "$@" \
        -v "$REPO_ROOT:/repo:ro" -v "$SONDE_DIR:/sonde:ro" \
        -v "$REPO_ROOT/docker/apache/conf/sites-enabled:/etc/apache2/sites-enabled:ro" \
        -v "$SONDE_DIR/vhost-casse:/etc/apache2/sites-casse:ro" \
        --entrypoint bash "$IMAGE_APACHE" -c '
            set -e
            mkdir -p /etc/apache2/ssl /var/www/html/public
            openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=laravel.local" \
                -keyout /etc/apache2/ssl/laravel.local.key \
                -out /etc/apache2/ssl/laravel.local.crt > /dev/null 2>&1

            # ⛔ LA CONTRAINTE QUI JUSTIFIE TOUTE LA CONCEPTION EST REPRODUITE,
            # PAS SUPPOSÉE : le répertoire des gabarits est monté `:ro`, comme
            # dans docker-compose.yml. On le MESURE avant de mesurer le reste.
            if echo x > /etc/apache2/sites-enabled/temoin-ecriture 2>/dev/null; then
                echo "MONTAGE_RO=non"
                rm -f /etc/apache2/sites-enabled/temoin-ecriture
            else
                echo "MONTAGE_RO=oui"
            fi

            CIBLE=/usr/local/apache2/conf/sites-rendered/laravel.conf

            # 1er passage : TOUJOURS le gabarit versionné, à son chemin par
            # défaut, pour quil existe une cible PRÉCÉDENTE.
            ( . /sonde/bloc-apache.sh ) > /tmp/passe1.log 2>&1
            echo "PASSE1=$(cksum < "$CIBLE")"
            echo "INCLUDE1=$(grep -cF "IncludeOptional /usr/local/apache2/conf/sites-rendered/*.conf" /usr/local/apache2/conf/httpd.conf)"

            if [ "$VARIANTE" = "CASSE" ]; then
                export VHOST_TEMPLATE=/etc/apache2/sites-casse/laravel.conf.template
            fi

            # ⚖️ LE BINAIRE FAUTIF N ARRIVE QU AU SECOND PASSAGE. Le premier doit
            # réussir, sinon il n existerait aucune cible précédente dont on
            # puisse dire si elle survit — et le test mesurerait un refus sur
            # rien.
            if [ -n "${ENVSUBST_PASSE2:-}" ]; then
                export ENVSUBST_BIN="$ENVSUBST_PASSE2"
            fi

            # ⚖️ ON SÈME LANCIENNE LIGNE `Include` POUR RENDRE OBSERVABLE CE QUE
            # LENTRYPOINT FAIT DE `httpd.conf`. Sans elle, un rendu en échec ne
            # laisse aucune trace mesurable dans la configuration principale, et
            # linversion « modifier puis tester » resterait invisible.
            if [ "${SEMER_ANCIEN_INCLUDE:-}" = "oui" ]; then
                echo "Include /etc/apache2/sites-enabled/*.conf" >> /usr/local/apache2/conf/httpd.conf
            fi

            echo "HTTPD1=$(cksum < /usr/local/apache2/conf/httpd.conf)"

            statut=0
            ( . /sonde/bloc-apache.sh ) > /tmp/passe2.log 2>&1 || statut=$?
            echo "STATUT=$statut"
            echo "PASSE2=$(cksum < "$CIBLE")"
            echo "HTTPD2=$(cksum < /usr/local/apache2/conf/httpd.conf)"
            echo "INCLUDE2=$(grep -cF "IncludeOptional /usr/local/apache2/conf/sites-rendered/*.conf" /usr/local/apache2/conf/httpd.conf)"
            echo "=== SORTIE ==="
            cat /tmp/passe2.log
            echo "=== RENDU ==="
            cat "$CIBLE"
            echo "=== FIN ==="
        '
}

# =============================================================================
# ANTI-VACUITÉ — sans elle, tout ce fichier pourrait mesurer du vide
# =============================================================================

@test "le bloc apache est bien EXTRAIT de l’entrypoint, pas recopié" {
    run cat "$SONDE_DIR/bloc-apache.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"rendre_vhost() {"* ]]
    [[ "$output" == *"VHOST_VARS="* ]]
    [[ "$output" == *"httpd -t -f"* ]]
    # L'APPEL, pas seulement la définition : sans lui, rien ne s'exécuterait.
    [ "$(printf '%s\n' "$output" | grep -c '^rendre_vhost$')" -eq 1 ]
}

@test "le CONCURRENT de conf.d est bien EXTRAIT du Dockerfile, pas recopié" {
    # ⛔ Sans lui, les tests de précédence mesureraient une image sans
    # adversaire — et `99-fork.ini` y gagnerait tout aussi bien.
    run cat "$SONDE_DIR/concurrent.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"memory_limit=2G"* ]]
    [[ "$output" == *"composer-optimizations.ini"* ]]
}

# =============================================================================
# PHP — LA VALEUR EFFECTIVE, PAR SAPI
# =============================================================================

@test "les APPELS de rendu sont EXTRAITS de l’entrypoint, pas recopiés" {
    # 🔴 ANTI-VACUITÉ DE TOUT LE VOLET PHP, ET ELLE A UNE HISTOIRE. La première
    # rédaction de la sonde écrivait elle-même le nom de la cible : renommer
    # celle-ci en `99-fork.ini` dans l entrypoint laissait les 19 tests VERTS,
    # y compris le test de précédence — mesuré le 2026-08-28. La sonde joue
    # désormais les lignes du sujet, et ce test refuse qu elle n en trouve
    # aucune.
    run mesurer_php -e PHP_CLI_MEMORY_LIMIT_DEFAUT=4G
    [ "$status" -eq 0 ]
    [[ "$output" == *"APPELS_EXTRAITS=2"* ]]
    [[ "$output" == *"CIBLE_INI=zz-fork.ini"* ]]
    [[ "$output" == *"CIBLE_POOL=zz-fork.conf"* ]]
}

@test "étage DEVELOPMENT : php-fpm borné à 256M, CLI à 4G" {
    # 🔴 LE CŒUR DE LA STORY. Avant elle, `php.ini:5` annonçait 256M et la
    # valeur effective valait 4G — POUR LES DEUX SAPI. Ici les deux nombres
    # DIFFÈRENT, et c'est ce qui prouve que le fragment de pool agit.
    run mesurer_php -e PHP_CLI_MEMORY_LIMIT_DEFAUT=4G
    [ "$status" -eq 0 ]
    [[ "$output" == *"FPM_MEMORY=256M"* ]]
    [[ "$output" == *"CLI_MEMORY=4G"* ]]
    [[ "$output" == *"DIRECTIVE_VIDE=non"* ]]
    [[ "$output" == *"MARQUEUR_RESIDUEL=non"* ]]
}

@test "étage PRODUCTION : la CLI reste à 2G, elle n’hérite pas du réglage de dev" {
    # 🔴 LE DÉFAUT QUE LA REVUE A TROUVÉ. `docker-compose.prod.yml` plafonne le
    # conteneur à 1 Go ; une CLI à 4G y ferait tuer les processus par le kernel,
    # sans erreur PHP lisible. Le défaut est DÉRIVÉ DE L'ÉTAGE.
    run mesurer_php -e PHP_CLI_MEMORY_LIMIT_DEFAUT=2G
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLI_MEMORY=2G"* ]]
    [[ "$output" == *"FPM_MEMORY=256M"* ]]
}

@test "sans défaut d’étage, le repli est le SÛR (2G), pas celui de dev" {
    run mesurer_php
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLI_MEMORY=2G"* ]]
}

@test "PHP_MEMORY_LIMIT=512M déplace FPM, et LAISSE la CLI où elle est" {
    run mesurer_php -e PHP_CLI_MEMORY_LIMIT_DEFAUT=4G -e PHP_MEMORY_LIMIT=512M
    [ "$status" -eq 0 ]
    [[ "$output" == *"FPM_MEMORY=512M"* ]]
    # ⛔ L'ASSERTION QUI COMPTE VRAIMENT : une story qui aurait posé une valeur
    # unique satisferait la ligne du dessus et casserait celle-ci.
    [[ "$output" == *"CLI_MEMORY=4G"* ]]
}

@test "une variable VIDE retombe sur le défaut, sans rendre de directive nue" {
    # C'est le cas nominal, pas un cas limite : `docker-compose.yml` injecte
    # `PHP_MEMORY_LIMIT=` quand le `.env` racine ne la déclare pas.
    run mesurer_php -e PHP_CLI_MEMORY_LIMIT_DEFAUT=4G \
        -e PHP_MEMORY_LIMIT= -e PHP_CLI_MEMORY_LIMIT= -e PHP_MAX_EXECUTION_TIME=
    [ "$status" -eq 0 ]
    [[ "$output" == *"FPM_MEMORY=256M"* ]]
    [[ "$output" == *"CLI_MEMORY=4G"* ]]
    [[ "$output" == *"FPM_TIME=300"* ]]
    [[ "$output" == *"DIRECTIVE_VIDE=non"* ]]
}

@test "PHP_CLI_MEMORY_LIMIT déplace la CLI, et LAISSE php-fpm où il est" {
    # Anti-coïncidence : sans ce cas, un rendu qui figerait la CLI satisferait
    # les tests précédents.
    run mesurer_php -e PHP_CLI_MEMORY_LIMIT=1G -e PHP_MAX_EXECUTION_TIME=45
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLI_MEMORY=1G"* ]]
    [[ "$output" == *"FPM_MEMORY=256M"* ]]
    [[ "$output" == *"FPM_TIME=45"* ]]
}

@test "le rendu est REJOUABLE et n’écrit JAMAIS dans le gabarit" {
    run mesurer_php -e PHP_MEMORY_LIMIT=512M
    [ "$status" -eq 0 ]
    [[ "$output" == *"REJOUABLE=identique"* ]]
    [[ "$output" == *"GABARITS=intacts"* ]]
}

# =============================================================================
# PHP — LA PRÉCÉDENCE, MESURÉE CONTRE UN CONCURRENT RÉEL
# =============================================================================

@test "AVEC le concurrent de conf.d, l’override CLI l’emporte — c’est le tri qui décide" {
    # 🔴 LE TEST QUE LA REVUE A EXIGÉ, ET IL EST LE SEUL DE SON ESPÈCE.
    # `composer-optimizations.ini` (memory_limit=2G) est rejoué dans l'image.
    # `zz-fork.ini` est scanné APRÈS lui et gagne : 512M.
    # Avec `99-fork.ini`, PHP lirait `9` avant les lettres, le fichier serait
    # parsé AVANT le concurrent, et la CLI vaudrait 2G.
    #
    # ⚠️ ET C'EST L'OVERRIDE QUI RÉVÈLE LE DÉFAUT, PAS LE DÉFAUT LUI-MÊME :
    # aux valeurs par défaut les deux fichiers posent la MÊME valeur, et le
    # perdant est indiscernable du gagnant.
    run mesurer_php -e AVEC_CONCURRENT=oui -e PHP_CLI_MEMORY_LIMIT=512M
    [ "$status" -eq 0 ]
    [[ "$output" == *"CONCURRENT=memory_limit=2G"* ]]
    [[ "$output" == *"CLI_MEMORY=512M"* ]]
}

@test "AVEC le concurrent, php-fpm reste borné — le pool l’emporte sur les deux" {
    # `php_admin_value` est la seule directive qui gagne contre `php.ini` ET
    # contre `conf.d`. Sans elle, FPM prendrait ici 2G comme la CLI.
    run mesurer_php -e AVEC_CONCURRENT=oui -e PHP_CLI_MEMORY_LIMIT=512M
    [ "$status" -eq 0 ]
    [[ "$output" == *"FPM_MEMORY=256M"* ]]
}

# =============================================================================
# PHP — LE FRAGMENT DE POOL EST ÉPROUVÉ AVANT D'ÊTRE PROMU
# =============================================================================

@test "un fragment de pool INVALIDE est refusé, et la cible précédente SURVIT" {
    # ⛔ SYMÉTRIE AVEC LE VHOST. Sans `php-fpm -t`, un fragment invalide écrasait
    # le précédent VALIDE : php-fpm refusait de démarrer et
    # `restart: unless-stopped` bouclait, sans plus rien de sain où revenir.
    run php_rendu_refuse PHP_FPM_D php-casse
    [ "$status" -eq 0 ]

    # Anti-vacuité : l appel a bien été extrait, ET il porte le validateur.
    [[ "$output" == *"APPEL_POOL=[rendre_gabarit "* ]]
    [[ "$output" == *"valider_pool_fpm"* ]]

    [[ "$output" == *"STATUT=1"* ]]
    [[ "$output" == *"REFUSÉ par"* ]]

    passe1="$(printf '%s\n' "$output" | sed -n 's/^PASSE1=//p')"
    passe2="$(printf '%s\n' "$output" | sed -n 's/^PASSE2=//p')"
    [ -n "$passe1" ]
    [ "$passe1" = "$passe2" ]
}

@test "une variable OUBLIÉE dans la liste d’autorisation fait REFUSER le rendu" {
    # ⛔ PENDANT RUNTIME DU GARDE STATIQUE. `ConfigTemplateTest` compare la liste
    # d'autorisation aux gabarits ; il ne dit RIEN à l'exécution. Sans ce refus,
    # `envsubst` recopierait le marqueur littéralement et PHP lirait la limite
    # comme **0** — un conteneur sain qui échoue sur chaque requête.
    run php_rendu_refuse PHP_CONF_D php-non-autorisee
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUT=1"* ]]
    [[ "$output" == *"n'a PAS été substituée"* ]]

    passe1="$(printf '%s\n' "$output" | sed -n 's/^PASSE1=//p')"
    passe2="$(printf '%s\n' "$output" | sed -n 's/^PASSE2=//p')"
    [ -n "$passe1" ]
    [ "$passe1" = "$passe2" ]
}

# =============================================================================
# PHP — LE FORMAT DES VALEURS, PAS SEULEMENT LEUR NON-VACUITÉ
# =============================================================================

@test "une limite mémoire ABSURDE fait refuser le démarrage, en la nommant" {
    # 🔴 `memory_limit = abc` N'EST PAS UNE ERREUR POUR PHP : il lit **0**.
    # Le conteneur démarrerait et échouerait sur chaque requête — le garde
    # « aucune directive vide » ne voit rien, la directive a une valeur.
    run mesurer_php -e PHP_MEMORY_LIMIT=abc
    [ "$status" -ne 0 ]
    [[ "$output" == *"PHP_MEMORY_LIMIT"* ]]
    [[ "$output" == *"abc"* ]]
}

@test "une limite mémoire SANS UNITÉ est refusée elle aussi" {
    # ⚠️ `512` n'est pas `512M` : PHP lit 512 OCTETS. C'est le cas le plus
    # facile à écrire de bonne foi dans un `.env`.
    run mesurer_php -e PHP_MEMORY_LIMIT=512
    [ "$status" -ne 0 ]
    [[ "$output" == *"PHP_MEMORY_LIMIT"* ]]
}

@test "une durée d’exécution NON NUMÉRIQUE est refusée" {
    run mesurer_php -e PHP_MAX_EXECUTION_TIME=trois-cents
    [ "$status" -ne 0 ]
    [[ "$output" == *"PHP_MAX_EXECUTION_TIME"* ]]
}

@test "une valeur MULTILIGNE est refusée — c’est une injection de directives" {
    # ⛔ `envsubst` recopie le saut de ligne, et tout ce qui suit devient une
    # DIRECTIVE de plus. La liste d'autorisation contrôle quelles variables
    # entrent, jamais ce qu'elles portent.
    run mesurer_php -e "$(printf 'PHP_MEMORY_LIMIT=256M\nmax_execution_time=1')"
    [ "$status" -ne 0 ]
    [[ "$output" == *"SAUT DE LIGNE"* ]]
}

@test "TÉMOIN : une limite mémoire BIEN FORMÉE passe — anti-vacuité des refus" {
    # Sans ce cas, une validation qui refuserait TOUT satisferait les quatre
    # tests ci-dessus.
    run mesurer_php -e PHP_MEMORY_LIMIT=-1 -e PHP_MAX_EXECUTION_TIME=0
    [ "$status" -eq 0 ]
    [[ "$output" == *"FPM_MEMORY=-1"* ]]
}

# =============================================================================
# APACHE — LE VHOST, TESTÉ AVANT D'ÊTRE PROMU
# =============================================================================

@test "le répertoire des gabarits apache est bien monté en LECTURE SEULE" {
    # ⛔ C'EST LA PRÉMISSE DE TOUTE LA CONCEPTION. Si ce montage devenait
    # inscriptible, rendre le vhost sur place redeviendrait possible — et
    # réécrirait un fichier VERSIONNÉ à chaque démarrage.
    run apache_rendu "VERSIONNE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"MONTAGE_RO=oui"* ]]
}

@test "le vhost est rendu, promu, et les dollars littéraux survivent" {
    run apache_rendu "VERSIONNE" -e APACHE_SERVER_NAME=fork.example -e APACHE_SERVER_ALIAS=www.fork.example
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUT=0"* ]]
    [[ "$output" == *"ServerName fork.example"* ]]
    [[ "$output" == *"Redirect permanent / https://fork.example/"* ]]

    # ⛔ CE QUE LA LISTE D'AUTORISATION PROTÈGE : `envsubst` ne touche à RIEN
    # d'autre. Le `$` de `<FilesMatch \.php$>` et le `%{…}` de mod_rewrite sont
    # rendus tels quels.
    [[ "$output" == *'<FilesMatch \.php$>'* ]]
    [[ "$output" == *'RewriteCond %{REQUEST_FILENAME} !-f'* ]]

    # Et aucune variable n'est restée littérale — anti-vacuité du rendu.
    [[ "$output" != *'${APACHE_'* ]]
}

@test "la ligne IncludeOptional NE S’ACCUMULE PAS d’un démarrage à l’autre" {
    # ⚖️ La sonde joue le bloc DEUX fois : c'est le deuxième démarrage d'un
    # conteneur `restart: unless-stopped`. Une ligne ajoutée à chaque passage
    # ferait grossir `httpd.conf` sans fin.
    run apache_rendu "VERSIONNE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"INCLUDE1=1"* ]]
    [[ "$output" == *"INCLUDE2=1"* ]]
}

@test "un gabarit de vhost INVALIDE est refusé, et la cible précédente SURVIT" {
    run apache_rendu "CASSE" -e SEMER_ANCIEN_INCLUDE=oui
    [ "$status" -eq 0 ]   # le conteneur, lui, va au bout de la sonde

    # 🔴 LE REFUS EST MESURÉ, PAS LU : `httpd -t` tourne sur le CANDIDAT.
    [[ "$output" == *"STATUT=1"* ]]
    [[ "$output" == *"REFUSÉ par httpd -t"* ]]
    [[ "$output" == *"laravel.conf.template"* ]]

    # ⛔ L'INVARIANT QUI COMPTE : la cible promue au premier passage est INCHANGÉE.
    passe1="$(printf '%s\n' "$output" | sed -n 's/^PASSE1=//p')"
    passe2="$(printf '%s\n' "$output" | sed -n 's/^PASSE2=//p')"
    [ -n "$passe1" ]
    [ "$passe1" = "$passe2" ]

    # 🔴 ET `httpd.conf` NON PLUS N'A PAS BOUGÉ — c'est la moitié que le
    # commentaire d'origine passait sous silence. L'entrypoint modifiait la
    # configuration PRINCIPALE avant le `httpd -t`, et ne la défaisait pas :
    # « la cible précédente n'est pas touchée » était vrai du vhost et faux de
    # `httpd.conf`. La sonde sème l'ancienne ligne `Include` exprès, pour que
    # ce retrait prématuré soit MESURABLE.
    httpd1="$(printf '%s\n' "$output" | sed -n 's/^HTTPD1=//p')"
    httpd2="$(printf '%s\n' "$output" | sed -n 's/^HTTPD2=//p')"
    [ -n "$httpd1" ]
    [ "$httpd1" = "$httpd2" ]
}

@test "sur SUCCÈS, l’ancienne ligne Include est bien retirée — anti-vacuité" {
    # Sans ce cas, un entrypoint qui ne toucherait JAMAIS `httpd.conf`
    # satisferait le test ci-dessus, et laisserait un `Include` à joker sans
    # correspondance — fatal en Apache 2.4.
    run apache_rendu "VERSIONNE" -e SEMER_ANCIEN_INCLUDE=oui
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUT=0"* ]]

    httpd1="$(printf '%s\n' "$output" | sed -n 's/^HTTPD1=//p')"
    httpd2="$(printf '%s\n' "$output" | sed -n 's/^HTTPD2=//p')"
    [ -n "$httpd1" ]
    [ "$httpd1" != "$httpd2" ]
}

@test "une directive de vhost SANS VALEUR est refusée, et la cible SURVIT" {
    # ⛔ BRANCHE AUTREMENT INATTEIGNABLE : les défauts garantissent une valeur.
    # Le stub `envsubst` vide les trois directives — c'est la seule façon
    # d'atteindre ce refus, et sans lui il n'était éprouvé par rien.
    run apache_rendu "VERSIONNE" -e ENVSUBST_PASSE2=/sonde/envsubst-vide
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUT=1"* ]]
    [[ "$output" == *"Directive sans valeur"* ]]

    passe1="$(printf '%s\n' "$output" | sed -n 's/^PASSE1=//p')"
    passe2="$(printf '%s\n' "$output" | sed -n 's/^PASSE2=//p')"
    [ -n "$passe1" ]
    [ "$passe1" = "$passe2" ]
}

@test "un envsubst introuvable fait REFUSER le démarrage d’apache, en le nommant" {
    run apache_rendu "VERSIONNE" -e ENVSUBST_PASSE2=envsubst-absent-pour-la-sonde
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUT=1"* ]]
    [[ "$output" == *"envsubst-absent-pour-la-sonde"* ]]
    [[ "$output" == *"gettext"* ]]
}

@test "un vhost valide N’est PAS refusé — anti-vacuité des tests de refus" {
    run apache_rendu "VERSIONNE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUT=0"* ]]
    [[ "$output" != *"REFUSÉ par httpd -t"* ]]
    [[ "$output" != *"Directive sans valeur"* ]]
}
