#!/bin/sh
set -e

# Garantit que les fichiers créés dans le container sont group-writable (664/775)
# Indispensable pour l'édition depuis Windows/PhpStorm via WSL2
umask 002

# Couleurs pour les logs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

WAIT_TIMEOUT=${WAIT_TIMEOUT:-60}  # Timeout max (en secondes) pour attendre PostgreSQL et Redis

# ⚖️ DEUX CHEMINS EN VARIABLES, ET C'EST CE QUI REND CE SCRIPT ÉPROUVABLE.
# Leurs valeurs par défaut sont EXACTEMENT celles qui étaient écrites en dur :
# rien ne change en production. Mais un `APP_ROOT` codé en dur rendait ce
# fichier intestable — une sonde aurait dû, pour l'exécuter, `chown` l'arbre
# applicatif RÉEL et écrire dans `/var/log/supervisor`. Le défaut corrigé ici
# (une sonde qui décidait « installé » sur un fichier versionné) a vécu
# précisément parce qu'aucun test ne pouvait lancer ce script.
APP_ROOT="${APP_ROOT:-/var/www/html}"
SUPERVISOR_LOG_DIR="${SUPERVISOR_LOG_DIR:-/var/log/supervisor}"

# ⛔ LA SONDE DE BOOTABILITÉ EST BORNÉE, COMME L'ATTENTE DES SERVICES.
# `wait_for_service` honore `WAIT_TIMEOUT` depuis toujours ; `php artisan
# --version`, lui, n'avait AUCUNE borne. Un provider qui bloque au boot (socket
# ouvert vers un service injoignable, `sleep` dans un `register()`) figeait
# l'entrypoint indéfiniment : pas de sortie, pas d'état décidé, un conteneur ni
# sain ni mort — le pire des trois. Un dépassement est désormais un ÉTAT, et il
# est nommé.
BOOT_PROBE_TIMEOUT=${BOOT_PROBE_TIMEOUT:-15}

# Témoin de passage par la branche « bootable », RÉÉCRIT À CHAQUE DÉMARRAGE.
# 🔴 IL EXISTE PARCE QUE LA POST-CONDITION PRÉCÉDENTE MENTAIT. `make
# post-install-restart-php` attendait l'apparition de `public/storage` — or
# `./src` est bind-monté (`docker-compose.yml`) et ce lien SURVIT au conteneur :
# à la deuxième exécution, le tout premier sondage réussissait et la cible
# annonçait « entrypoint rejoué » sans avoir rien mesuré. Le témoin ci-dessous
# vit dans le conteneur, il est réécrit à chaque démarrage, et son contenu est
# UNIQUE : « il a changé » ne peut vouloir dire qu'une chose.
BOOTABLE_MARKER="${BOOTABLE_MARKER:-/tmp/laravel-entrypoint-bootable}"

# =============================================================================
# DÉFINITIONS — TOUT CE QUI EST *SOURÇABLE* VIT AVANT LA GARDE CI-DESSOUS
# =============================================================================
#
# 🔴 CET ENTRYPOINT EST DEVENU UN SUJET DE TEST (story 2.4, clôture). Le défaut
# qu'il portait — une sonde `[ -f artisan ]` qui décidait « Laravel est
# installé » sur un fichier VERSIONNÉ — n'était atteignable par AUCUN test :
# le script est monolithique et sa première ligne utile attend PostgreSQL.
# Les fonctions sont donc définies d'abord, et `LARAVEL_ENTRYPOINT_SOURCE_ONLY`
# permet à une sonde de les charger SANS exécuter le corps impératif.
# =============================================================================

# Fonction pour attendre un service TCP avec timeout
wait_for_service() {
  local host=$1
  local port=$2
  local start_time=$(date +%s)

  echo -e "${YELLOW}Attente de $host sur le port $port...${NC}"

  if ! command -v nc >/dev/null 2>&1; then
    echo -e "${RED}nc (netcat) n'est pas installé. Impossible d'attendre le service.${NC}"
    exit 1
  fi

  while ! nc -z "$host" "$port"; do
    sleep 1
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    if [ "$elapsed" -ge "$WAIT_TIMEOUT" ]; then
      echo -e "${RED}Timeout dépassé (${WAIT_TIMEOUT}s) en attendant $host:$port${NC}"
      exit 1
    fi
  done

  echo -e "${GREEN}✓ $host est prêt${NC}"
}

# -----------------------------------------------------------------------------
# TROIS ÉTATS, PAS UN BOOLÉEN — et un quatrième qui est un REFUS.
#
# 🔴 LE DÉFAUT MESURÉ (2026-08-24, conteneur `laravel-app_php`) : la sonde
# `[ -f artisan ]` répondait « installé » sur un CLONE NEUF, parce que
# `src/artisan` est versionné alors que `src/vendor` ne l'est pas
# (`src/.gitignore:55`). `artisan:10` fait `require __DIR__.'/vendor/autoload.php'`
# sans condition : toute commande sortait en **255**, `set -e` tuait
# l'entrypoint, `restart: unless-stopped` bouclait, et `make install-dev-full`
# ne pouvait pas aboutir. C'est ce que le nightly a rougi deux fois
# (runs 32654512271 et 32688766596), étiqueté INSTALLEUR — à raison.
#
# ⛔ ET LA CORRECTION N'EST PAS D'INVERSER LA SONDE VERS
# `[ -f vendor/autoload.php ]`. Un `vendor/` PARTIEL (install interrompue,
# déploiement à moitié copié) satisfait ce test : la branche production
# s'exécuterait et `config:cache`/`route:cache` FIGERAIENT des caches
# construits depuis un état cassé — précisément ce que la décision D7
# ci-dessous a été écrite pour empêcher. On ne devine donc pas la bootabilité,
# **on la mesure** : `php artisan --version` répond, ou il ne répond pas.
#
# ⚖️ CINQ ÉTATS, ET LE COMPTE EST TENU PAR UN TEST. Les quatre écrits du même
# commit avaient déjà commencé à diverger — « trois états plus un refus » ici,
# « quatre » dans le nom d'un test, cinq branches dans le `case`. Un garde
# (`PhpEntrypointStateTest`) DÉRIVE désormais la liste de cette fonction et
# vérifie que le `case` en aval traite exactement ces états-là : le compte ne
# peut plus dériver en silence.
#
# États rendus sur STDOUT :
#   absent                — pas d'`artisan` : rien n'a jamais été installé ici
#   sans-vendor           — `artisan` présent, `vendor/autoload.php` absent (clone neuf)
#   non-bootable          — `autoload.php` présent mais l'application ne boote PAS
#   non-bootable-timeout  — la sonde de boot n'a jamais rendu la main (bornée)
#   bootable              — l'application répond
#
# `PHP_BIN` existe pour la sonde de test, qui n'a ni Laravel ni vendor à lui
# offrir : il n'est jamais posé en production.
# -----------------------------------------------------------------------------
detect_laravel_state() {
  local app_root="${1:-/var/www/html}"
  local statut=0

  if [ ! -f "$app_root/artisan" ]; then
    echo "absent"
    return 0
  fi

  if [ ! -f "$app_root/vendor/autoload.php" ]; then
    echo "sans-vendor"
    return 0
  fi

  # ⛔ BORNÉE, ET LE CODE DE DÉPASSEMENT DÉPEND DE L'IMPLÉMENTATION.
  # 🔴 MESURÉ LE 2026-08-24, LES DEUX : GNU coreutils rend **124** ; le
  # `timeout` de **BusyBox** — celui de cette image, `php:8.5-fpm-alpine` —
  # rend **143** (128 + SIGTERM). Écrire `-eq 124` seul rendait donc cet état
  # INATTEIGNABLE EN PRODUCTION : un garde qui ne se déclenche jamais là où il
  # compte. C'est le motif de la story 2.3 (GNU vs BusyBox), et c'est la sonde
  # tournant enfin sous le bon interpréteur qui l'a fait rougir.
  # ⚠️ Honnêteté du diagnostic : 143 est aussi ce que rend un php tué par un
  # SIGTERM venu d'ailleurs. Les deux cas se rapportent pareil — « n'a pas
  # rendu la main » — parce que la réparation est la même.
  (cd "$app_root" && timeout "$BOOT_PROBE_TIMEOUT" "${PHP_BIN:-php}" artisan --version) > /dev/null 2>&1 || statut=$?

  if [ "$statut" -eq 124 ] || [ "$statut" -eq 143 ]; then
    echo "non-bootable-timeout"
    return 0
  fi

  if [ "$statut" -ne 0 ]; then
    echo "non-bootable"
    return 0
  fi

  echo "bootable"
}

# -----------------------------------------------------------------------------
# GABARITS DE CONFIGURATION — LE GABARIT EST VERSIONNÉ, LA CIBLE NE L'EST PAS.
#
# 🔴 CE QUI ÉTAIT FAUX AVANT (mesuré le 2026-08-28, conteneur `laravel-app_php`).
# `docker/php/conf/php.ini:5` annonce `memory_limit = 256M` ; la valeur
# EFFECTIVE valait **4G**, parce que `composer-optimizations.ini` est lu après
# `php.ini` et qu'un `sed` du stage `development` la pousse à 4G. La
# configurabilité annoncée était donc déjà fausse dans le fichier qu'un
# fork-streamer irait éditer — et pour la corriger il devait modifier un fichier
# du DÉPÔT, bind-monté en écriture. Cette story déplace la décision dans
# l'environnement, sans qu'aucun fichier versionné ne soit réécrit.
#
# ⚖️ LES CIBLES SONT CHOISIES SUR MESURE, PAS PAR HABITUDE :
#   • `conf.d/zz-fork.ini`      — `zz-` gagne le tri alphabétique de `conf.d` ;
#                                 `99-` PERDRAIT (ASCII : `9` < les lettres) ;
#   • `php-fpm.d/zz-fork.conf`  — `php_admin_value` l'emporte sur `php.ini` ET
#                                 sur `conf.d`, et seulement pour FPM ;
#   • aucune des deux n'est bind-montée — gardé par `ConfigTemplateTest`.
#
# ⛔ `envsubst` NE CONNAÎT PAS `${VAR:-defaut}` : il rendrait la chaîne telle
# quelle. Les défauts sont donc posés ICI, avant l'appel. Une variable VIDE
# (`PHP_MEMORY_LIMIT=` — ce que Compose injecte quand le `.env` racine ne la
# déclare pas) est traitée comme absente, sinon la cible recevrait `= ` nu.
#
# ⛔ ET LA SUBSTITUTION EST SUR LISTE D'AUTORISATION. Sans le premier argument,
# `envsubst` remplace TOUTE variable de l'environnement présente dans le
# gabarit — un `$HOME`, un `$PATH`, un secret exporté par Compose passeraient
# dans un fichier de configuration.
# -----------------------------------------------------------------------------
PHP_TEMPLATE_DIR="${PHP_TEMPLATE_DIR:-/usr/local/etc/php/templates}"
PHP_CONF_D="${PHP_CONF_D:-/usr/local/etc/php/conf.d}"
PHP_FPM_D="${PHP_FPM_D:-/usr/local/etc/php-fpm.d}"
PHP_FPM_CONF="${PHP_FPM_CONF:-/usr/local/etc/php-fpm.conf}"

# ⛔ LES BINAIRES SONT NOMMÉS, PAS SUPPOSÉS — même motif que `PHP_BIN` ci-dessus.
# Sans ces variables, ni le refus « envsubst manquant » ni la validation du pool
# ne seraient éprouvables sans démonter le `PATH` de la sonde — donc, en
# pratique, jamais.
ENVSUBST_BIN="${ENVSUBST_BIN:-envsubst}"
PHP_FPM_BIN="${PHP_FPM_BIN:-php-fpm}"

PHP_MEMORY_LIMIT="${PHP_MEMORY_LIMIT:-256M}"

# ⚖️ LE DÉFAUT CLI EST DÉRIVÉ DE L'ÉTAGE DE BUILD, ET C'EST UNE DÉCISION DE SÛRETÉ.
#
# 🔴 UN DÉFAUT UNIQUE À `4G` ÉTAIT FAUX EN PRODUCTION, ET DANGEREUSEMENT.
# `docker-compose.prod.yml:49` plafonne le conteneur php à `memory: 1G`
# (`deploy.resources.limits`) et n'injecte PAS `PHP_CLI_MEMORY_LIMIT`. Avant
# cette story, la CLI de production valait `2G` — la valeur écrite par
# `Dockerfile:183` dans `composer-optimizations.ini`, que seul l'étage
# `development` pousse à `4G` (`:258`). Un défaut unique à `4G` DOUBLAIT donc la
# limite en production, sous un cgroup de 1 Go : le kernel tue le processus
# avant que PHP n'atteigne sa limite, donc SANS erreur PHP lisible — un OOM
# anonyme au lieu d'un « Allowed memory size exhausted » qui nomme le coupable.
#
# ⚠️ ET LA CLI N'EST PAS QUE `composer` : les workers **Horizon** tournent sous
# ce même SAPI dans ce même conteneur (`docker/supervisor/conf.d/horizon.conf`
# lance `php artisan horizon`, qui engendre N processus enfants). Une limite par
# processus multipliée par N enfants sous un cgroup de 1 Go est exactement la
# façon dont on transforme un échec net en OOM système.
#
# `PHP_CLI_MEMORY_LIMIT_DEFAUT` est posée PAR ÉTAGE dans le Dockerfile
# (`production` → 2G, `development` → 4G) et gardée par `ConfigTemplateTest`,
# qui refuse que les deux étages la confondent. Le repli `2G` ci-dessous est le
# choix SÛR : si l'étage n'a rien posé, on ne suppose pas la machine de
# développement.
PHP_CLI_MEMORY_LIMIT="${PHP_CLI_MEMORY_LIMIT:-${PHP_CLI_MEMORY_LIMIT_DEFAUT:-2G}}"
PHP_MAX_EXECUTION_TIME="${PHP_MAX_EXECUTION_TIME:-300}"
export PHP_MEMORY_LIMIT PHP_CLI_MEMORY_LIMIT PHP_MAX_EXECUTION_TIME

# Liste d'autorisation, au format « shell-format » attendu par `envsubst`.
PHP_TEMPLATE_VARS='${PHP_MEMORY_LIMIT} ${PHP_CLI_MEMORY_LIMIT} ${PHP_MAX_EXECUTION_TIME}'

# -----------------------------------------------------------------------------
# LE FORMAT EST VALIDÉ, PAS SEULEMENT LA NON-VACUITÉ.
#
# 🔴 `memory_limit = abc` ET `memory_limit = 512` (sans unité) SONT ACCEPTÉS PAR
# PHP, qui les lit comme **0** octet. Ce ne sont donc pas des erreurs de
# démarrage : ce sont des conteneurs sains qui échouent sur chaque requête. Le
# garde « aucune directive vide » ne les voit pas — la directive a une valeur,
# elle est juste absurde.
#
# ⛔ ET LE SAUT DE LIGNE EST UNE INJECTION. Une variable d'environnement peut en
# contenir un ; `envsubst` le recopierait tel quel, et tout ce qui suit
# deviendrait une DIRECTIVE de plus dans le fichier rendu. La liste
# d'autorisation contrôle QUELLES variables entrent, pas ce qu'elles portent.
# -----------------------------------------------------------------------------
valider_valeur() {
  local nom="$1"
  local valeur="$2"
  local motif="$3"
  local attendu="$4"

  case "$valeur" in
    *"
"*)
      echo -e "${RED}❌ $nom porte un SAUT DE LIGNE.${NC}"
      echo -e "${RED}   Tout ce qui suit deviendrait une directive de plus dans le fichier rendu : arrêt.${NC}"
      exit 1
      ;;
  esac

  if ! printf '%s' "$valeur" | grep -Eq "$motif"; then
    echo -e "${RED}❌ $nom = « $valeur » n'est pas $attendu.${NC}"
    echo -e "${RED}   PHP lirait cette valeur comme 0 : le conteneur s'arrête plutôt que de servir cela.${NC}"
    exit 1
  fi
}

# ⚠️ L'UNITÉ EST OBLIGATOIRE, ET C'EST PLUS STRICT QUE PHP — DÉLIBÉRÉMENT.
# `memory_limit = 512` est accepté par PHP, qui le lit comme **512 OCTETS**.
# C'est la faute la plus facile à écrire de bonne foi dans un `.env`, et son
# symptôme (chaque requête échoue) ne ressemble en rien à sa cause. On refuse
# donc le nombre nu : « -1 » pour illimité, sinon une unité explicite.
valider_valeur PHP_MEMORY_LIMIT "$PHP_MEMORY_LIMIT" \
  '^(-1|[0-9]+[KMGkmg])$' 'une limite mémoire PHP (« -1 », ou un nombre SUIVI DE K, M ou G — « 512 » seul vaut 512 octets)'
valider_valeur PHP_CLI_MEMORY_LIMIT "$PHP_CLI_MEMORY_LIMIT" \
  '^(-1|[0-9]+[KMGkmg])$' 'une limite mémoire PHP (« -1 », ou un nombre SUIVI DE K, M ou G — « 512 » seul vaut 512 octets)'
valider_valeur PHP_MAX_EXECUTION_TIME "$PHP_MAX_EXECUTION_TIME" \
  '^[0-9]+$' 'un nombre entier de secondes'

# -----------------------------------------------------------------------------
# LE FRAGMENT DE POOL EST ÉPROUVÉ AVANT D'ÊTRE PROMU — comme le vhost.
#
# 🔴 L'ASYMÉTRIE ÉTAIT UN DÉFAUT, ET SON COÛT EST LE MÊME DES DEUX CÔTÉS. Le
# vhost passait par `httpd -t` ; le pool était promu à l'aveugle. Un fragment
# invalide écrasait alors le précédent VALIDE, php-fpm refusait de démarrer, et
# `restart: unless-stopped` bouclait — sans plus aucune configuration saine à
# laquelle revenir.
#
# ⚖️ LE TEST PORTE SUR LE CANDIDAT, dans une copie de l'arborescence de pools :
# `php-fpm -t` valide un ENSEMBLE de fichiers, pas un fichier isolé.
# ⛔ Aucun `sed` sur un chemin interpolé ici : l'`include=` est retiré par
# `grep -v` littéral puis réécrit. Un moteur de motif appliqué à un chemin qu'on
# ne contrôle pas a déjà mordu ce dépôt (story 2.2).
# -----------------------------------------------------------------------------
valider_pool_fpm() {
  local candidat="$1"
  local bac
  local statut=0

  if ! command -v "$PHP_FPM_BIN" > /dev/null 2>&1; then
    echo -e "${RED}❌ « $PHP_FPM_BIN » est introuvable : le fragment de pool ne peut pas être éprouvé.${NC}"
    return 1
  fi

  bac="$(mktemp -d)"

  # ⚠️ LES POOLS VONT DANS UN SOUS-RÉPERTOIRE, ET CE N'EST PAS COSMÉTIQUE.
  # Poser la configuration principale À CÔTÉ des fragments la fait ramasser par
  # son propre `include=…/*.conf` : FPM refuse alors « Unable to include … from
  # … » et rend **78** — pour TOUT candidat, valide comme invalide. Mesuré le
  # 2026-08-28 : le garde aurait été rouge en permanence, donc jamais activé.
  mkdir -p "$bac/pools"

  # Les pools DÉJÀ en place, puis le candidat à la place du sien.
  cp "$PHP_FPM_D"/*.conf "$bac/pools/" 2> /dev/null || true
  cp "$candidat" "$bac/pools/zz-fork.conf"

  if [ -f "$PHP_FPM_CONF" ]; then
    grep -v '^include=' "$PHP_FPM_CONF" > "$bac/php-fpm.conf" || true
  fi
  echo "include=$bac/pools/*.conf" >> "$bac/php-fpm.conf"

  "$PHP_FPM_BIN" -t -y "$bac/php-fpm.conf" || statut=$?

  rm -rf "$bac"

  return "$statut"
}

rendre_gabarit() {
  local gabarit="$1"
  local cible="$2"
  # Validateur OPTIONNEL, appliqué au CANDIDAT. Le pool FPM en a un
  # (`php-fpm -t`) ; le fichier `conf.d` n'en a pas — PHP n'expose aucun
  # vérificateur d'ini, et inventer une validation approximative vaudrait moins
  # que de dire qu'il n'y en a pas.
  local validateur="${3:-}"
  local temporaire

  if [ "$gabarit" = "$cible" ]; then
    echo -e "${RED}❌ Gabarit et cible confondus (« $cible ») : le rendu écraserait sa propre source.${NC}"
    exit 1
  fi

  if [ ! -f "$gabarit" ]; then
    echo -e "${RED}❌ Gabarit de configuration absent : « $gabarit ».${NC}"
    echo -e "${RED}   L'image ne porte pas ce fichier — php-fpm ne démarre pas sur une configuration devinée.${NC}"
    exit 1
  fi

  if ! command -v "$ENVSUBST_BIN" > /dev/null 2>&1; then
    echo -e "${RED}❌ « $ENVSUBST_BIN » est introuvable (paquet « gettext »).${NC}"
    echo -e "${RED}   « $gabarit » ne peut pas être rendu vers « $cible » : arrêt.${NC}"
    exit 1
  fi

  mkdir -p "$(dirname "$cible")"

  # ⚖️ ON REND À CÔTÉ, PUIS ON PROMEUT. Écrire directement dans la cible
  # laisserait, sur un rendu fautif, une configuration à moitié écrite que
  # php-fpm lirait au démarrage suivant.
  temporaire="${cible}.rendu"
  "$ENVSUBST_BIN" "$PHP_TEMPLATE_VARS" < "$gabarit" > "$temporaire"

  # ⛔ JAMAIS DE DIRECTIVE VIDE. `memory_limit =` (sans valeur) n'est pas une
  # erreur pour PHP : il l'interprète comme une chaîne vide, donc `0` — soit un
  # refus d'allouer quoi que ce soit. Un défaut mal posé produirait donc un
  # conteneur qui démarre et qui échoue sur chaque requête.
  if grep -Eq '^[[:space:]]*[A-Za-z_][^=]*=[[:space:]]*$' "$temporaire"; then
    rm -f "$temporaire"
    echo -e "${RED}❌ Directive sans valeur dans le rendu de « $gabarit ».${NC}"
    echo -e "${RED}   « $cible » est laissée INTACTE et le conteneur s'arrête.${NC}"
    exit 1
  fi

  # ⛔ AUCUN `${…}` NE SURVIT AU RENDU. C'est le pendant RUNTIME du garde
  # statique de liste d'autorisation, qui ne dit rien à l'exécution : une
  # variable ajoutée au gabarit et OUBLIÉE dans la liste serait recopiée
  # littéralement, et PHP lirait « ${PHP_MEMORY_LIMIT} » comme 0.
  if grep -Eq '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "$temporaire"; then
    rm -f "$temporaire"
    echo -e "${RED}❌ Une variable n'a PAS été substituée dans le rendu de « $gabarit ».${NC}"
    echo -e "${RED}   Elle manque probablement à la liste d'autorisation d'envsubst.${NC}"
    echo -e "${RED}   « $cible » est laissée INTACTE et le conteneur s'arrête.${NC}"
    exit 1
  fi

  # Validation par l'outil du sujet, quand il en existe un.
  if [ -n "$validateur" ]; then
    if ! "$validateur" "$temporaire"; then
      rm -f "$temporaire"
      echo -e "${RED}❌ Le rendu de « $gabarit » est REFUSÉ par « $validateur ».${NC}"
      echo -e "${RED}   « $cible » est laissée INTACTE et le conteneur s'arrête.${NC}"
      exit 1
    fi
  fi

  mv "$temporaire" "$cible"
  echo -e "${GREEN}✓ $(basename "$gabarit") → $cible${NC}"
}

# ⛔ PORTE DE SONDE, JAMAIS DE PRODUCTION. La variable n'est posée que par
# `src/tests/Unit/PhpEntrypointStateTest.php`, qui `source` ce fichier pour
# éprouver `detect_laravel_state` sur un arbre de bac à sable. En exécution
# réelle elle est absente, et cette ligne ne fait rien.
if [ "${LARAVEL_ENTRYPOINT_SOURCE_ONLY:-}" = "true" ]; then
  return 0 2> /dev/null || exit 0
fi

echo -e "${YELLOW}🚀 Démarrage du container PHP...${NC}"

wait_for_service postgres 5432
wait_for_service redis 6379

# ⚖️ RENDU AVANT LA SONDE DE BOOTABILITÉ, ET C'EST DÉLIBÉRÉ : `detect_laravel_state`
# lance `php artisan --version` un peu plus bas, donc sous la configuration
# effectivement rendue. Une sonde qui mesurerait l'ancienne configuration
# n'éprouverait pas ce que php-fpm servira.
echo -e "${YELLOW}Rendu des gabarits de configuration...${NC}"
rendre_gabarit "$PHP_TEMPLATE_DIR/php-fork.ini.template" "$PHP_CONF_D/zz-fork.ini"
rendre_gabarit "$PHP_TEMPLATE_DIR/php-fpm-fork.conf.template" "$PHP_FPM_D/zz-fork.conf" valider_pool_fpm

# ─────────────────────────────────────────────────────────────────────────────
# PERMISSIONS : ON N'AJUSTE QUE CE QUE LE CONTENEUR DOIT ÉCRIRE.
#
# 🔴 CE BLOC CONFISQUAIT L'ARBRE ENTIER, ET C'EST CE QUI A ROUGI LE PREMIER
# NIGHTLY RÉELLEMENT ABOUTI (run 32742873104). Il faisait :
#
#     find "$APP_ROOT" -not -user www-data … -exec chown www-data:www-data {} +
#
# c'est-à-dire : « tout ce qui n'appartient pas à www-data devient www-data ».
# `www-data` valait alors UID **1000** en dur. Sur la machine de développement
# documentée (WSL2/PhpStorm) l'hôte est AUSSI 1000 : le geste était un no-op, et
# le défaut invisible. Sur un runner GitHub, l'hôte est **1001** — l'entrypoint
# retirait donc à l'hôte la propriété de son propre arbre.
# `scripts/install-lockfile.sh` s'exécute SUR L'HÔTE (aucun `docker exec`) : son
# `mktemp` dans `src/.install-state/`, désormais possédé par 1000, était refusé,
# et l'installation mourait à sa dernière étape après avoir réussi les onze
# modules (run 32742873104).
#
# 🔁 ET LE RETIRER SEUL N'A PAS SUFFI — c'était l'autre moitié du même piège.
# Sans lui, l'hôte gardait l'arbre… et c'est l'INSTALLEUR, qui tourne en
# `docker exec -u`, qui ne pouvait plus écrire : run 32745286801, mort dès
# l'étape 1/5. Deux pansements contradictoires pour un seul conflit.
# ✅ La cause est traitée ailleurs, et à la racine : `HOST_UID`/`HOST_GID`
# (Makefile) alignent l'uid du conteneur sur celui de l'hôte, donc `www-data`
# **EST** l'hôte. Il n'y a plus qu'un propriétaire possible, et le `chown`
# restreint ci-dessous devient juste et inoffensif.
#
# ⚖️ CE QUI DOIT ÊTRE ÉCRIVABLE PAR LE CONTENEUR EST CONNU ET COURT : `storage/`
# et `bootstrap/cache/`. Le reste — le code, la configuration, `.install-state/`
# — appartient à l'hôte et DOIT lui rester. On ajuste donc ces deux
# répertoires-là, nommément, et rien d'autre.
#
# ⚠️ LE CONFORT WSL2/PhpStorm EST PRÉSERVÉ : quand l'hôte EST uid 1000, il l'est
# déjà pour tout l'arbre — le `find` ne faisait rien pour lui. Ce qu'il
# corrigeait réellement, ce sont les fichiers écrits en root PAR L'ENTRYPOINT,
# et ceux-là vivent précisément dans `storage/` et `bootstrap/cache/`.
# ─────────────────────────────────────────────────────────────────────────────
if [ -d "$APP_ROOT" ]; then
    echo -e "${YELLOW}Ajustement des permissions d'écriture du conteneur...${NC}"

    # S'assurer que les répertoires critiques ont les bonnes permissions
    if [ -d "$APP_ROOT/storage" ]; then
        chmod -R 775 "$APP_ROOT/storage" 2>/dev/null || true
        chown -R www-data:www-data "$APP_ROOT/storage" 2>/dev/null || true
    fi

    if [ -d "$APP_ROOT/bootstrap/cache" ]; then
        chmod -R 775 "$APP_ROOT/bootstrap/cache" 2>/dev/null || true
        chown -R www-data:www-data "$APP_ROOT/bootstrap/cache" 2>/dev/null || true
    fi

    # Fichiers spécifiques
    [ -f "$APP_ROOT/.env" ] && chmod 664 "$APP_ROOT/.env" 2>/dev/null || true
    [ -f "$APP_ROOT/artisan" ] && chmod 775 "$APP_ROOT/artisan" 2>/dev/null || true

    echo -e "${GREEN}✓ Permissions corrigées${NC}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# TROIS ÉTATS. La branche « bootable » est la SEULE à jouer une commande artisan.
# ─────────────────────────────────────────────────────────────────────────────
ETAT_LARAVEL="$(detect_laravel_state "$APP_ROOT")"
echo -e "${YELLOW}État de l'application détecté : ${ETAT_LARAVEL}${NC}"

case "$ETAT_LARAVEL" in
 absent)
   echo -e "${YELLOW}Laravel n'est pas encore installé (aucun « artisan ») — php-fpm démarre nu.${NC}"
   ;;

 sans-vendor)
   # ⛔ CLONE NEUF. `artisan` est versionné, `vendor/` ne l'est pas : l'arbre est
   # LÀ, les dépendances non. Jouer la moindre commande artisan ici sort en 255
   # et, sous `set -e` + `restart: unless-stopped`, boucle le conteneur — donc
   # `make install-laravel`, qui a besoin de ce conteneur pour peupler
   # `vendor/`, ne peut jamais démarrer. Poule et œuf : le correctif ne pouvait
   # être QUE dans cet entrypoint.
   if [ "$APP_ENV" = "local" ] || [ "$APP_ENV" = "testing" ]; then
       echo -e "${YELLOW}Dépendances non installées (« vendor/autoload.php » absent).${NC}"
       echo -e "${YELLOW}→ Aucune commande artisan n'est jouée ; php-fpm démarre pour que${NC}"
       echo -e "${YELLOW}  « make install-laravel » puisse s'exécuter DANS ce conteneur.${NC}"
       echo -e "${YELLOW}  Les caches seront purgés/reconstruits au prochain démarrage,${NC}"
       echo -e "${YELLOW}  une fois « vendor/ » en place.${NC}"
   else
       # ⛔ ET LE CHEMIN NON-DEV RESTE FATAL. `proxies:check` est le contrôle de
       # déploiement sorti du bloc production le 2026-08-20 précisément pour
       # qu'un hôte `staging`/`preprod`/`demo` — ou un APP_ENV VIDE, ce que
       # rend le repli `make up` sans `-f` — ne démarre pas sans lui. Sans
       # `vendor/`, il ne PEUT pas s'exécuter : démarrer quand même rouvrirait
       # ce trou en silence. On refuse, et on nomme la variable.
       echo -e "${RED}❌ Dépendances absentes (« vendor/autoload.php ») et APP_ENV=« ${APP_ENV:-<vide>} ».${NC}"
       echo -e "${YELLOW}   APP_ENV n'est ni « local » ni « testing » : « php artisan proxies:check »${NC}"
       echo -e "${YELLOW}   ne peut pas s'exécuter, et démarrer sans lui est refusé.${NC}"
       echo -e "${YELLOW}   → Posez APP_ENV=local (docker-compose.dev.yml le fait) pour une machine${NC}"
       echo -e "${YELLOW}     de développement, ou installez les dépendances avant de démarrer.${NC}"
       exit 1
   fi
   ;;

 non-bootable|non-bootable-timeout)
   # ⛔ `vendor/autoload.php` EXISTE ET L'APPLICATION NE BOOTE PAS. C'est le cas
   # qu'une sonde `[ -f vendor/autoload.php ]` aurait déclaré sain — et la
   # branche production aurait alors figé `config:cache`/`route:cache` DEPUIS
   # UN ÉTAT CASSÉ (décision D7 ci-dessous). Aucun cache n'est construit depuis
   # cet état, jamais, quel que soit l'environnement.
   if [ "$ETAT_LARAVEL" = "non-bootable-timeout" ]; then
       echo -e "${RED}❌ La sonde de démarrage n'a JAMAIS rendu la main (tuée après ${BOOT_PROBE_TIMEOUT}s).${NC}"
       echo -e "${YELLOW}   Ce n'est pas « l'application a échoué » mais « l'application ne répond pas » :${NC}"
       echo -e "${YELLOW}   un service injoignable attendu au boot, ou une boucle dans un provider.${NC}"
   else
       echo -e "${RED}❌ « vendor/autoload.php » est présent mais l'application ne boote pas.${NC}"
       echo -e "${YELLOW}   Dépendances incomplètes (install interrompue, copie partielle).${NC}"
   fi
   echo -e "${YELLOW}   Diagnostic : « php artisan --version » dans $APP_ROOT.${NC}"

   # ⛔ ET EN DEV, ON NE TUE PAS LE CONTENEUR — MÊME RAISONNEMENT QUE POUR
   # « sans-vendor », QUI LUI AVAIT ÉTÉ APPLIQUÉ ET PAS ICI (relevé en revue).
   # Un `composer install` interrompu laisse EXACTEMENT cet état : autoloader
   # présent, dépendances incomplètes. Le tuer boucle le conteneur sous
   # `restart: unless-stopped`, et la seule réparation documentée — `make
   # install-laravel`, `make composer cmd="install"` — s'exécute DANS ce
   # conteneur. On refuserait de démarrer l'unique endroit d'où l'on peut
   # réparer : c'est la poule et l'œuf que cette story a corrigée un cran plus
   # haut, reconduite ici.
   # ⚠️ La fatalité HORS dev ne bouge pas : `proxies:check` ne peut pas
   # s'exécuter sur une application qui ne boote pas, et démarrer sans lui est
   # refusé.
   if [ "$APP_ENV" = "local" ] || [ "$APP_ENV" = "testing" ]; then
       echo -e "${YELLOW}→ APP_ENV=« $APP_ENV » : php-fpm démarre quand même, SANS jouer${NC}"
       echo -e "${YELLOW}  la moindre commande artisan, pour que la réparation ait un hôte.${NC}"
   else
       exit 1
   fi
   ;;

 bootable)
   echo -e "${YELLOW}Configuration de Laravel...${NC}"

   # ⛔ Le `cd` était IMPLICITE : `WORKDIR` du Dockerfile vaut `/var/www/html`,
   # donc `php artisan …` marchait par coïncidence de répertoire courant. Avec
   # `APP_ROOT` variable, l'implicite devient un défaut latent — on le rend
   # explicite plutôt que de le laisser dépendre du lanceur.
   cd "$APP_ROOT"

   # ─────────────────────────────────────────────────────────────────────────
   # ⛔ LE CONTRÔLE DES PROXYS EST HORS DU `if production` (finding de revue, 2026-08-20)
   #
   # Il y était, et c'était un trou : un hôte `staging`, `preprod` ou `demo` —
   # tout ce qui n'est pas LITTÉRALEMENT « production » — démarrait sans contrôle,
   # avec le `TRUSTED_PROXIES=*` hérité d'un vieux `.env`, c'est-à-dire dans l'état
   # exact que ce contrôle a été écrit pour refuser. Il est bon marché (il lit la
   # configuration) : on le passe partout sauf en local/testing, où un opérateur
   # bricole et n'a pas à être arrêté.
   # ─────────────────────────────────────────────────────────────────────────
   if [ "$APP_ENV" != "local" ] && [ "$APP_ENV" != "testing" ]; then
       php artisan proxies:check || exit 1
   fi

   if [ "$APP_ENV" = "production" ]; then
       echo -e "${YELLOW}Optimisation pour la production...${NC}"

       # ─────────────────────────────────────────────────────────────────────
       # ⚠️ ON PURGE AVANT DE RECONSTRUIRE (décision D7, revue du 2026-08-20)
       #
       # Les caches de routes et de configuration sont construits À PARTIR DE
       # L'ENVIRONNEMENT COURANT. Un cache hérité d'un démarrage précédent — image
       # dont le build a exécuté `route:cache`, volume persistant, redéploiement
       # partiel — survit sinon au changement d'un `MODULE_*_ENABLED`.
       #
       # Conséquence mesurée en revue : des routes cachées MODULE ACTIVÉ laissent
       # `/admin` résoluble après bascule à `MODULE_ADMIN_ENABLED=false`. Plus
       # aucun panel n'est enregistré, `PanelRegistry::getDefault()` lève
       # `NoDefaultPanelSetException`, et le visiteur reçoit **500** — alors que
       # l'AC2 de la Story 1.10a exige 404. Aucun test ne peut atteindre cet état :
       # `Tests\Support\ModuleBoot` boote toujours une application jetable NON
       # cachée. Le garde-fou ne pouvait donc être qu'ici.
       # ─────────────────────────────────────────────────────────────────────
       php artisan optimize:clear

       # ⛔ `proxies:check` a déjà tourné ci-dessus, AVANT `config:cache` — l'ordre
       # compte : le refus de `TRUSTED_PROXIES` ne vit plus dans le chargement de
       # `config/` (décision D8, où une exception rendait l'application non
       # bootable, commandes de réparation comprises), et il ne doit pas s'exécuter
       # sur une configuration déjà mise en cache.

       php artisan config:cache
       php artisan route:cache
       php artisan view:cache
       php artisan event:cache

       if [ -f "$APP_ROOT/config/opcache-preload.php" ]; then
           echo "opcache.preload=$APP_ROOT/config/opcache-preload.php" >> /usr/local/etc/php/conf.d/opcache.ini
           echo "opcache.preload_user=www-data" >> /usr/local/etc/php/conf.d/opcache.ini
       fi
   else
       echo -e "${YELLOW}Configuration pour le développement...${NC}"
       php artisan config:clear
       php artisan route:clear
       php artisan view:clear
       php artisan event:clear

       if [ "$XDEBUG_ENABLE" = "true" ] && [ -f "/usr/local/etc/php/conf.d/xdebug.ini.disabled" ]; then
           echo -e "${YELLOW}Activation de Xdebug...${NC}"
           mv /usr/local/etc/php/conf.d/xdebug.ini.disabled /usr/local/etc/php/conf.d/xdebug.ini
       fi
   fi

   # ⛔ ON TESTE L'EXISTENCE, PAS SEULEMENT LE TYPE DE LIEN. `[ ! -L … ]` est
   # VRAI pour un vrai répertoire : `storage:link` échouait alors (« The
   # "public/storage" directory already exists »), `set -e` tuait l'entrypoint,
   # et `restart: unless-stopped` bouclait — sur un dossier que quelqu'un a
   # peut-être rempli. On ne l'efface pas, on le DIT.
   # ⛔ TROIS CAS, ET LE TROISIÈME EST UN LIEN CASSÉ (relevé en 2ᵉ revue).
   # `-e` suit le lien : sur un symlink pointant dans le vide il est FAUX
   # tandis que `-L` est VRAI. Un test `! -e` seul reprenait donc la branche de
   # création, `storage:link` échouait sur un chemin déjà occupé, `set -e`
   # tuait l'entrypoint et `restart: unless-stopped` bouclait — le mode de
   # panne exact que ce bloc vient de corriger pour le répertoire réel.
   if [ ! -e "$APP_ROOT/public/storage" ] && [ ! -L "$APP_ROOT/public/storage" ]; then
       echo -e "${YELLOW}Création du lien de storage...${NC}"
       php artisan storage:link
   elif [ -L "$APP_ROOT/public/storage" ] && [ ! -e "$APP_ROOT/public/storage" ]; then
       echo -e "${YELLOW}⚠️ « public/storage » est un lien symbolique CASSÉ (cible absente).${NC}"
       echo -e "${YELLOW}   « storage:link » n'est pas joué : il échouerait et tuerait ce conteneur.${NC}"
       echo -e "${YELLOW}   Supprimez ce lien, puis redémarrez.${NC}"
   elif [ ! -L "$APP_ROOT/public/storage" ]; then
       echo -e "${YELLOW}⚠️ « public/storage » existe et n'est PAS un lien symbolique.${NC}"
       echo -e "${YELLOW}   « storage:link » n'est pas joué : il échouerait et tuerait ce conteneur.${NC}"
       echo -e "${YELLOW}   Déplacez ou supprimez ce chemin, puis redémarrez.${NC}"
   fi

   if [ -d "$APP_ROOT/vendor/laravel/horizon" ] && [ ! -d "$APP_ROOT/public/vendor/horizon" ]; then
       echo -e "${YELLOW}Publication des assets Horizon...${NC}"
       php artisan horizon:publish
   fi

   echo -e "${GREEN}✓ Laravel configuré${NC}"
   ;;

 *)
   # Un état inconnu est un REFUS, jamais un « on continue ». Il ne peut venir
   # que d'une modification de `detect_laravel_state` non répercutée ici.
   echo -e "${RED}❌ État d'application inconnu: « $ETAT_LARAVEL » — refus de démarrer.${NC}"
   exit 1
   ;;
esac

mkdir -p "$SUPERVISOR_LOG_DIR"

# ⚠️ `|| true` ASSUMÉ, ET DIT. Ce `chown` était fatal ; il ne l'est plus, pour
# une raison d'ENVIRONNEMENT DE MESURE. En production l'entrypoint tourne en
# root et le geste réussit ; sous sonde, il tourne comme l'utilisateur des tests
# — celui de l'hôte dans le conteneur (= www-data, cf. `HOST_UID`), mais un
# utilisateur QUELCONQUE sur un runner nu, hors du groupe `www-data`.
# Laisser `set -e` tuer la sonde là aurait rendu ce script vert en local et
# rouge en CI : le défaut exact relevé sur `main` au run 32627114533.
# ⚖️ Et le compromis est petit : des permissions de RÉPERTOIRE DE LOGS ne
# justifient pas de refuser de démarrer. Ce qui doit tuer le conteneur — la
# porte `proxies:check`, un `vendor/` cassé — le tue toujours.
chown -R www-data:www-data "$SUPERVISOR_LOG_DIR" 2>/dev/null || true

# ─────────────────────────────────────────────────────────────────────────────
# ⛔ LE TÉMOIN EST POSÉ ICI — DERNIÈRE LIGNE AVANT `exec`, PAS FIN DE BRANCHE.
#
# 🔴 IL ÉTAIT ÉCRIT À LA FIN DE LA BRANCHE « bootable », ET C'ÉTAIT TROP TÔT
# (relevé en 2ᵉ revue). Entre cette branche et `exec` vivent encore
# `mkdir -p "$SUPERVISOR_LOG_DIR"` — FATAL sous `set -e` — et le `exec`
# lui-même. Un échec là laissait `make post-install-restart-php` VERT sur un
# conteneur qui meurt aussitôt : la cible aurait attesté d'un démarrage qui
# n'a jamais servi.
#
# ⚖️ Ce que le témoin dit maintenant, exactement : « l'application était
# bootable ET l'entrypoint est allé jusqu'à passer la main ». Rien de plus,
# et c'est ce que la cible attend.
# ⚠️ Il n'est posé QUE dans l'état `bootable`. Les autres états démarrent
# php-fpm (en dev) ou refusent : dans les deux cas il n'y a rien à attester.
# Contenu UNIQUE : un horodatage seul se répéterait si deux démarrages
# tombaient dans la même seconde.
# ─────────────────────────────────────────────────────────────────────────────
if [ "$ETAT_LARAVEL" = "bootable" ]; then
  printf '%s %s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      "$(cat /proc/sys/kernel/random/uuid 2> /dev/null || echo "$$")" \
      > "$BOOTABLE_MARKER" 2> /dev/null || true
fi

echo -e "${GREEN}✓ Container PHP prêt${NC}"

# Exécuter la commande principale, ou lancer php-fpm en mode foreground par défaut
if [ $# -eq 0 ]; then
  exec php-fpm -F
else
  exec "$@"
fi
