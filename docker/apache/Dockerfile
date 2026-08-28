# httpd 2.4.68 / alpine 3.24.1 — épinglé par digest (le tag reste mutable).
FROM httpd:2.4-alpine@sha256:1b766f17b84026429b7cb243317b142921b24432336e798bc881c43f45ed9567

# Arguments pour l'utilisateur
ARG UID=1000
ARG GID=1000

# Correctifs de sécurité de la distribution, appliqués à CHAQUE build.
#
# Pourquoi c'est nécessaire malgré une image de base épinglée : une image de
# base est figée à sa date de publication. Entre deux publications, Alpine
# corrige des CVE dans son dépôt, et l'image continue d'embarquer les paquets
# vulnérables. Constaté le 2026-07-27 via Snyk puis la base de sécurité Alpine :
#
#   libexpat  2.7.5-r0 installé  ->  2.8.2-r0 disponible   (15 CVE de retard,
#             dont CVE-2026-50219 Use-After-Free, CVSS 5.9)
#   libcurl   8.14.1-r2 installé ->  8.21.0-r0 disponible  (~30 CVE de retard)
#
# Arbitrage assumé : `apk upgrade` rend le build légèrement moins reproductible,
# puisque les paquets évoluent entre deux exécutions. C'est le bon compromis
# pour des correctifs de sécurité — la reproductibilité de la BASE reste
# assurée par l'épinglage de l'image, et l'alternative (rester sur des paquets
# vulnérables jusqu'à la prochaine publication amont) est pire.
RUN apk upgrade --no-cache

# Installation des dépendances
# ⚠️ `gettext` FOURNIT `envsubst`, ET IL N'EST PAS DÉCORATIF (story 2.5).
# L'entrypoint REFUSE de démarrer sans lui : le vhost est un gabarit versionné,
# rendu au démarrage vers une cible inscriptible. Retirer ce paquet fait rougir
# `src/tests/Unit/ConfigTemplateTest.php` et `tests/bats/config-template.bats`.
RUN apk add --no-cache \
    openssl \
    curl \
    bash \
    shadow \
    gettext \
    netcat-openbsd

# Création de l'utilisateur (mais Apache reste root pour les ports)
#
# ⚠️ CES DEUX APPELS SONT INERTES, ET C'EST ÉCRIT PLUTÔT QUE SUBI (mesuré le
# 2026-08-24). `www-data` existe DÉJÀ dans `httpd:2.4-alpine`, en uid **82** :
# `addgroup`/`adduser` échouent donc — « already exists » — et le `|| true`
# avale l'échec. L'`ARG UID` est accepté, et ignoré. C'est le défaut exact que
# `docker/node/Dockerfile` portait et qui a bloqué le nightly (run 32748093741).
#
# ⛔ POURQUOI IL N'EST PAS CORRIGÉ ICI, ET PAS PAR PARESSE. Cette image n'est
# pas dans le même cas que node :
#   • `httpd.conf` porte `User www-data` / `Group www-data` — changer cet uid
#     change l'utilisateur des WORKERS, pas seulement une identité de shell ;
#   • `usermod` ne re-chowne que le HOME : `/usr/local/apache2`, le seul autre
#     chemin possédé par `www-data(82)` (mesuré), resterait à 82 ;
#   • et une vraie requête HTTP avec un apache non-1000 n'est pas éprouvable
#     sans monter la pile complète — l'entrypoint attend `php:9000` SANS
#     timeout et exige les certificats.
# Rien ne le rend bloquant : les workers lisent l'arbre par les bits de
# permission (775/664), et l'ont toujours fait. Le corriger reste un geste à
# part, avec sa propre vérification. Report ouvert.
RUN addgroup -g ${GID} www-data 2>/dev/null || true \
    && adduser -D -u ${UID} -G www-data www-data 2>/dev/null || true

# Activer les modules Apache nécessaires (vérification d'existence)
RUN sed -i \
    -e 's/^#\(LoadModule .*mod_rewrite.so\)/\1/' \
    -e 's/^#\(LoadModule .*mod_ssl.so\)/\1/' \
    -e 's/^#\(LoadModule .*mod_headers.so\)/\1/' \
    -e 's/^#\(LoadModule .*mod_deflate.so\)/\1/' \
    -e 's/^#\(LoadModule .*mod_expires.so\)/\1/' \
    -e 's/^#\(LoadModule .*mod_status.so\)/\1/' \
    -e 's/^#\(LoadModule .*mod_proxy.so\)/\1/' \
    -e 's/^#\(LoadModule .*mod_proxy_fcgi.so\)/\1/' \
    /usr/local/apache2/conf/httpd.conf

# Ajouter les modules qui ne sont pas dans httpd.conf par défaut
RUN echo "" >> /usr/local/apache2/conf/httpd.conf \
    && echo "# Modules supplémentaires" >> /usr/local/apache2/conf/httpd.conf \
    && echo "LoadModule socache_shmcb_module modules/mod_socache_shmcb.so" >> /usr/local/apache2/conf/httpd.conf

# Vérifier si HTTP/2 est disponible et l'activer
RUN if [ -f /usr/local/apache2/modules/mod_http2.so ]; then \
        echo "LoadModule http2_module modules/mod_http2.so" >> /usr/local/apache2/conf/httpd.conf; \
    fi

# Configuration de base SSL
RUN echo "" >> /usr/local/apache2/conf/httpd.conf \
    && echo "# Configuration SSL" >> /usr/local/apache2/conf/httpd.conf \
    && echo "Listen 443 ssl" >> /usr/local/apache2/conf/httpd.conf \
    && echo "SSLRandomSeed startup builtin" >> /usr/local/apache2/conf/httpd.conf \
    && echo "SSLRandomSeed connect builtin" >> /usr/local/apache2/conf/httpd.conf

# Configuration du serveur
RUN echo "" >> /usr/local/apache2/conf/httpd.conf \
    && echo "# Configuration serveur" >> /usr/local/apache2/conf/httpd.conf \
    && echo "ServerName laravel.local" >> /usr/local/apache2/conf/httpd.conf \
    && echo "ServerTokens Prod" >> /usr/local/apache2/conf/httpd.conf \
    && echo "ServerSignature Off" >> /usr/local/apache2/conf/httpd.conf

# Créer les répertoires nécessaires avec les bonnes permissions
RUN mkdir -p /usr/local/apache2/logs \
    && mkdir -p /var/www/html \
    && mkdir -p /etc/apache2/ssl \
    && mkdir -p /etc/apache2/sites-enabled

# Script de démarrage
COPY docker/apache/scripts/docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Permissions pour les répertoires de travail
RUN chown -R www-data:www-data /var/www/html \
    && chown -R www-data:www-data /usr/local/apache2/logs \
    && chmod 755 /etc/apache2/ssl \
    && chmod 755 /etc/apache2/sites-enabled

# Exposition des ports
EXPOSE 80 443

# Healthcheck amélioré
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -k -f https://localhost/up || curl -f http://localhost/up || exit 1

# Apache doit rester root pour binder les ports < 1024
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]