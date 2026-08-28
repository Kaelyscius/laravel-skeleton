#!/bin/bash
set -e

# Couleurs pour les logs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}🚀 Démarrage du container Apache...${NC}"

# Attendre que PHP-FPM soit prêt
echo -e "${YELLOW}Attente de PHP-FPM...${NC}"
while ! nc -z php 9000; do
    sleep 1
done
echo -e "${GREEN}✓ PHP-FPM est prêt${NC}"

# Vérifier les certificats SSL dans le bon chemin (montage docker-compose)
SSL_CERT="/etc/apache2/ssl/laravel.local.crt"
SSL_KEY="/etc/apache2/ssl/laravel.local.key"

if [ ! -f "$SSL_CERT" ] || [ ! -f "$SSL_KEY" ]; then
    echo -e "${RED}❌ Certificats SSL manquants !${NC}"
    echo -e "${YELLOW}Cherchés dans :${NC}"
    echo -e "  - $SSL_CERT"
    echo -e "  - $SSL_KEY"
    echo -e "\n${YELLOW}Contenu de /etc/apache2/ssl/ :${NC}"
    ls -la /etc/apache2/ssl/ 2>/dev/null || echo "  (répertoire inexistant)"
    echo -e "\n${YELLOW}Veuillez exécuter : make setup-ssl${NC}"
    echo -e "${YELLOW}Et vérifiez votre docker-compose.yml pour le montage du volume SSL${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Certificats SSL trouvés${NC}"

# =============================================================================
# GABARIT DE VHOST — RENDU VERS UNE CIBLE INSCRIPTIBLE, PUIS PROMU (story 2.5)
# =============================================================================
#
# 🔴 CE QUE LA VERSION PRÉCÉDENTE FAISAIT, ET POURQUOI ÇA NE POUVAIT PAS ÊTRE
# RÉGLABLE. Elle attendait `/etc/apache2/sites-enabled/laravel.conf` et
# l'incluait tel quel. Ce répertoire est bind-monté `:ro`
# (`docker-compose.yml:15`) : mesuré le 2026-08-28, y écrire échoue en
# `Read-only file system` MÊME EN ROOT. Rendre le vhost sur place était donc
# impossible — et, sans le `:ro`, cela aurait réécrit un fichier VERSIONNÉ à
# chaque démarrage, le défaut exact que cette story supprime côté PHP.
#
# ⚖️ LE PIVOT EST L'`Include`, PAS LA CIBLE. L'entrypoint écrivait DÉJÀ dans
# `httpd.conf`, qui vit dans la couche image et n'est monté nulle part. Le vhost
# devient un `.template` (hors du glob `*.conf`, donc jamais deux `VirtualHost`
# concurrents) et l'`Include` désigne le répertoire RENDU.
#
# ⛔ ET LE `httpd -t` PORTE SUR LE CANDIDAT, PAS SUR LA CIBLE. Un gabarit fautif
# promu puis testé aurait déjà détruit la configuration précédente : le
# conteneur repartirait en boucle sans plus rien de valide à servir. On teste
# donc le candidat dans une configuration principale TEMPORAIRE, et on ne
# promeut qu'après.
# =============================================================================
HTTPD_CONF="${HTTPD_CONF:-/usr/local/apache2/conf/httpd.conf}"
VHOST_TEMPLATE="${VHOST_TEMPLATE:-/etc/apache2/sites-enabled/laravel.conf.template}"
VHOST_RENDERED_DIR="${VHOST_RENDERED_DIR:-/usr/local/apache2/conf/sites-rendered}"
ENVSUBST_BIN="${ENVSUBST_BIN:-envsubst}"

# ⛔ DÉFAUTS POSÉS ICI, PAS DANS LE GABARIT : `envsubst` ne connaît pas
# `${VAR:-defaut}` et le rendrait littéralement. Une variable VIDE — ce que
# Compose injecte quand le `.env` racine ne la déclare pas — est traitée comme
# absente, sinon `ServerName` serait rendu SANS valeur.
APACHE_SERVER_NAME="${APACHE_SERVER_NAME:-laravel.local}"
APACHE_SERVER_ALIAS="${APACHE_SERVER_ALIAS:-www.laravel.local}"
APACHE_DOCUMENT_ROOT="${APACHE_DOCUMENT_ROOT:-/var/www/html/public}"
export APACHE_SERVER_NAME APACHE_SERVER_ALIAS APACHE_DOCUMENT_ROOT

# Liste d'autorisation, au format « shell-format » attendu par `envsubst`.
# Sans elle, TOUTE variable de l'environnement présente dans le gabarit serait
# substituée — y compris ce que Compose exporte sans le destiner à un vhost.
VHOST_VARS='${APACHE_SERVER_NAME} ${APACHE_SERVER_ALIAS} ${APACHE_DOCUMENT_ROOT}'

# ⛔ UNE VALEUR MULTILIGNE EST UNE INJECTION DE DIRECTIVES.
# Une variable d'environnement peut porter un saut de ligne ; `envsubst` le
# recopie tel quel, et tout ce qui suit devient une directive Apache de plus.
# La liste d'autorisation contrôle QUELLES variables entrent, jamais ce
# qu'elles portent. `httpd -t` accepterait volontiers un vhost bien formé.
valider_valeur_vhost() {
    local nom="$1"
    local valeur="$2"

    case "$valeur" in
        *"
"*)
            echo -e "${RED}❌ $nom porte un SAUT DE LIGNE.${NC}"
            echo -e "${RED}   Tout ce qui suit deviendrait une directive Apache de plus : arrêt.${NC}"
            exit 1
            ;;
    esac
}

valider_valeur_vhost APACHE_SERVER_NAME "$APACHE_SERVER_NAME"
valider_valeur_vhost APACHE_SERVER_ALIAS "$APACHE_SERVER_ALIAS"
valider_valeur_vhost APACHE_DOCUMENT_ROOT "$APACHE_DOCUMENT_ROOT"

# Les deux lignes `Include` manipulées, écrites UNE fois et réutilisées.
#
# ⛔ ELLES SONT TRAITÉES EN LITTÉRAL, JAMAIS EN MOTIF. `VHOST_RENDERED_DIR` est
# surchargeable ; un chemin portant `|`, `.` ou `[` casserait une adresse `sed`
# ou la ferait matcher trop large. Ce dépôt s'est fait mordre deux fois par un
# moteur de motif là où un littéral était voulu (story 2.2), et le jumeau
# `grep -qF` de ce même bloc était déjà correct — l'incohérence était le défaut.
INCLUDE_ANCIEN="Include /etc/apache2/sites-enabled/*.conf"
INCLUDE_RENDU="IncludeOptional $VHOST_RENDERED_DIR/*.conf"

rendre_vhost() {
    local cible="$VHOST_RENDERED_DIR/laravel.conf"
    local candidat="$VHOST_RENDERED_DIR/laravel.conf.candidat"
    local conf_test

    if [ ! -f "$VHOST_TEMPLATE" ]; then
        echo -e "${RED}❌ Gabarit de vhost manquant : $VHOST_TEMPLATE${NC}"
        echo -e "${YELLOW}Contenu de $(dirname "$VHOST_TEMPLATE") :${NC}"
        ls -la "$(dirname "$VHOST_TEMPLATE")" 2>/dev/null || echo "  (répertoire vide ou inexistant)"
        exit 1
    fi

    if ! command -v "$ENVSUBST_BIN" > /dev/null 2>&1; then
        echo -e "${RED}❌ « $ENVSUBST_BIN » est introuvable (paquet « gettext »).${NC}"
        echo -e "${RED}   « $VHOST_TEMPLATE » ne peut pas être rendu vers « $cible » : arrêt.${NC}"
        exit 1
    fi

    mkdir -p "$VHOST_RENDERED_DIR"

    # ⚠️ `.candidat` n'est PAS un `.conf` : le glob de l'`Include` ne peut pas
    # l'attraper, même laissé derrière par un échec.
    "$ENVSUBST_BIN" "$VHOST_VARS" < "$VHOST_TEMPLATE" > "$candidat"

    # ⛔ JAMAIS DE DIRECTIVE VIDE. `ServerName` sans valeur est une erreur de
    # syntaxe qu'`httpd -t` attraperait ; `ServerAlias` sans valeur aussi. On
    # nomme le défaut ici plutôt que de laisser lire un diagnostic d'Apache.
    if grep -Eq '^[[:space:]]*(ServerName|ServerAlias|DocumentRoot)[[:space:]]*$' "$candidat"; then
        rm -f "$candidat"
        echo -e "${RED}❌ Directive sans valeur dans le rendu de « $VHOST_TEMPLATE ».${NC}"
        echo -e "${RED}   « $cible » est laissée INTACTE et le conteneur s'arrête.${NC}"
        exit 1
    fi

    # ⛔ AUCUN `${…}` NE SURVIT AU RENDU — pendant RUNTIME du garde statique de
    # liste d'autorisation, muet à l'exécution : une variable ajoutée au gabarit
    # et oubliée dans la liste serait servie littéralement.
    if grep -Eq '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "$candidat"; then
        rm -f "$candidat"
        echo -e "${RED}❌ Une variable n'a PAS été substituée dans le rendu de « $VHOST_TEMPLATE ».${NC}"
        echo -e "${RED}   Elle manque probablement à la liste d'autorisation d'envsubst.${NC}"
        echo -e "${RED}   « $cible » est laissée INTACTE et le conteneur s'arrête.${NC}"
        exit 1
    fi

    # ⚖️ LE TEST PORTE SUR LE CANDIDAT, ET `httpd.conf` N'A PAS ENCORE BOUGÉ.
    #
    # 🔴 L'ORDRE PRÉCÉDENT ÉTAIT FAUX, ET SON COMMENTAIRE MENTAIT À MOITIÉ. Il
    # modifiait `httpd.conf` (retrait de l'ancien `Include`, ajout du nouveau)
    # AVANT le `httpd -t`, et ne le défaisait pas en cas d'échec : « la cible
    # précédente n'est pas touchée » était vrai du VHOST et faux de la
    # CONFIGURATION PRINCIPALE. Un gabarit fautif laissait donc `httpd.conf`
    # modifié derrière lui. Ici, `httpd.conf` n'est écrit qu'APRÈS le succès —
    # il n'y a plus rien à défaire.
    #
    # La configuration temporaire reprend `httpd.conf` MOINS les deux formes
    # d'`Include` (littéralement, `grep -vF`), PLUS le candidat : ce qui est
    # validé est bien le fichier qu'on s'apprête à promouvoir, dans le contexte
    # réel du serveur.
    conf_test="$(mktemp)"
    grep -vF "$INCLUDE_ANCIEN" "$HTTPD_CONF" | grep -vF "$INCLUDE_RENDU" > "$conf_test" || true
    echo "Include $candidat" >> "$conf_test"

    echo -e "${YELLOW}Test de la configuration Apache (candidat)...${NC}"
    if ! httpd -t -f "$conf_test"; then
        rm -f "$conf_test" "$candidat"
        echo -e "${RED}❌ Le rendu de « $VHOST_TEMPLATE » est REFUSÉ par httpd -t.${NC}"
        echo -e "${RED}   « $cible » est laissée INTACTE, « $HTTPD_CONF » n'a pas été modifié,${NC}"
        echo -e "${RED}   et le conteneur s'arrête.${NC}"
        exit 1
    fi
    rm -f "$conf_test"

    # L'`Include` de la cible promue, posé UNE fois — APRÈS validation.
    #
    # ⚠️ `IncludeOptional`, PAS `Include` : un `Include` à joker SANS
    # correspondance est FATAL en Apache 2.4, et le répertoire rendu est vide au
    # tout premier démarrage.
    # ⛔ L'ancien `Include` du répertoire monté est retiré s'il traîne (image
    # reconstruite sur un conteneur déjà démarré) : il ne peut plus matcher — le
    # vhost y est devenu un `.template` — donc il ferait échouer le démarrage.
    if grep -qF "$INCLUDE_ANCIEN" "$HTTPD_CONF"; then
        grep -vF "$INCLUDE_ANCIEN" "$HTTPD_CONF" > "$conf_test.menage" || true
        cat "$conf_test.menage" > "$HTTPD_CONF"
        rm -f "$conf_test.menage"
    fi

    # ⚖️ IDEMPOTENT : au deuxième démarrage la ligne est déjà là, et elle ne
    # s'ajoute pas une seconde fois. Mesuré par `config-template.bats`, qui joue
    # le bloc deux fois et compte les occurrences.
    if ! grep -qF "$INCLUDE_RENDU" "$HTTPD_CONF"; then
        echo "$INCLUDE_RENDU" >> "$HTTPD_CONF"
    fi

    # ⚖️ REJOUABLE : à environnement égal, `mv` repose le même contenu, et le
    # gabarit n'est jamais touché (il est monté en lecture seule).
    mv "$candidat" "$cible"
    echo -e "${GREEN}✓ $(basename "$VHOST_TEMPLATE") → $cible${NC}"
}

# Créer les répertoires de logs si nécessaire.
# ⚠️ AVANT le rendu, pas après : `httpd -t` du candidat lit un vhost qui déclare
# `ErrorLog`/`CustomLog` dans ce répertoire.
mkdir -p /usr/local/apache2/logs

rendre_vhost

# Tester la configuration Apache
echo -e "${YELLOW}Test de la configuration Apache...${NC}"
if httpd -t; then
    echo -e "${GREEN}✓ Configuration Apache valide${NC}"
else
    echo -e "${RED}❌ Erreur dans la configuration Apache${NC}"
    echo -e "${YELLOW}Détails de l'erreur :${NC}"
    httpd -t
    exit 1
fi

echo -e "${GREEN}✅ Container Apache prêt - Laravel accessible sur https://laravel.local${NC}"

# Lancer Apache
exec httpd-foreground