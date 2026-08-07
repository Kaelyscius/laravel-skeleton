# Stage 1: Base avec toutes les extensions
# php 8.5.8 / alpine 3.24.1 — épinglé par digest (le tag reste mutable).
FROM php:8.5-fpm-alpine@sha256:79def1d16ece3ab1a6656c46a23bfd80ad33887fbd33626e7bd743cef54ef9c6 AS base

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

# Dépendances système + Node.js pour compatibilité frontend
RUN apk add --no-cache \
    bash \
    git \
    curl \
    zip \
    unzip \
    shadow \
    supervisor \
    libpng-dev \
    libjpeg-turbo-dev \
    freetype-dev \
    libzip-dev \
    icu-dev \
    oniguruma-dev \
    libxml2-dev \
    postgresql-dev \
    linux-headers \
    nodejs \
    npm \
    $PHPIZE_DEPS

# Installer yq pour la lecture des configurations YAML
RUN curl -L "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq

# Extensions PHP pour PHP 8.5.1
# Extensions à compiler - compilées séparément pour compatibilité
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd

RUN docker-php-ext-install -j$(nproc) \
        pdo \
        pdo_pgsql \
        pgsql

RUN docker-php-ext-install -j$(nproc) \
        zip \
        intl

RUN docker-php-ext-install -j$(nproc) \
        bcmath \
        exif \
        pcntl \
        sockets

# Note: opcache est déjà compilé DANS PHP 8.5 (extension Zend intégrée)
# Il est configuré via /usr/local/etc/php/conf.d/opcache.ini

# Note: Les extensions XML (dom, xml, xmlwriter, xmlreader, simplexml) sont incluses par défaut dans PHP 8.5
# Note: tokenizer, ctype, fileinfo, iconv, mbstring sont également incluses par défaut dans PHP 8.5

# PECL: Redis, APCu, Xdebug, Imagick
RUN apk add --no-cache imagemagick-dev \
    && pecl install redis apcu xdebug imagick \
    && docker-php-ext-enable redis apcu xdebug imagick \
    && mv "$PHP_INI_DIR/conf.d/docker-php-ext-xdebug.ini" "$PHP_INI_DIR/conf.d/xdebug.ini.disabled"

# Ajuster UID et GID de www-data si besoin
RUN set -eux; \
    existing_gid=$(getent group www-data | cut -d: -f3); \
    if [ "$existing_gid" != "$GID" ]; then groupmod -g "$GID" www-data; fi; \
    existing_uid=$(getent passwd www-data | cut -d: -f3); \
    if [ "$existing_uid" != "$UID" ]; then usermod -u "$UID" www-data; fi

# Config PHP-FPM pour écouter sur 0.0.0.0:9000 et permissions socket
RUN sed -i 's|127.0.0.1:9000|9000|g' /usr/local/etc/php-fpm.d/www.conf \
    && echo "listen.mode = 0666" >> /usr/local/etc/php-fpm.d/www.conf

# Stage 2: Composer optimisé
FROM composer:2 AS composer-stage

# Stage 3: Dependencies builder (optionnel - pour pre-build des dépendances)
FROM base AS dependencies

# Copier Composer depuis le stage précédent
COPY --from=composer-stage /usr/bin/composer /usr/bin/composer

# Créer le répertoire de cache Composer avec les bonnes permissions
RUN mkdir -p /tmp/composer-cache /var/composer \
    && chown -R www-data:www-data /tmp/composer-cache /var/composer

# Variables d'environnement pour optimiser Composer
ENV COMPOSER_MEMORY_LIMIT=-1 \
    COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_NO_INTERACTION=1 \
    COMPOSER_HOME=/var/composer \
    COMPOSER_CACHE_DIR=/tmp/composer-cache

# Configurer Composer pour performances optimales
RUN composer config --global process-timeout 3600 \
    && composer config --global repos.packagist composer https://packagist.org

# Créer un fichier de config Composer global optimisé
# Note: minimum-stability et prefer-stable sont des paramètres par projet, pas globaux  
# Note: Suppression du config.json global car problématique - configuration via variables d'env

# Pre-télécharger les métadonnées des packages populaires Laravel (cache warming)
USER www-data
RUN composer create-project --no-install --no-scripts --no-dev \
    laravel/laravel /tmp/laravel-cache \
    2>/dev/null || true && \
    rm -rf /tmp/laravel-cache
USER root

# Stage 4: Production final
FROM base AS production

# Copier Composer et sa configuration
COPY --from=dependencies /usr/bin/composer /usr/bin/composer
COPY --from=dependencies /var/composer /var/composer
COPY --from=dependencies /tmp/composer-cache /tmp/composer-cache

# Variables d'environnement Composer optimisées + Docker
ENV COMPOSER_MEMORY_LIMIT=-1 \
    COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_NO_INTERACTION=1 \
    COMPOSER_HOME=/var/composer \
    COMPOSER_CACHE_DIR=/tmp/composer-cache \
    COMPOSER_PROCESS_TIMEOUT=3600 \
    COMPOSER_OPTIMIZE_AUTOLOADER=1 \
    DOCKER_CONTAINER=1 \
    CONTAINER_TYPE=php

# Configuration PHP optimisée pour Composer
RUN { \
        echo 'memory_limit=2G'; \
        echo 'max_execution_time=300'; \
        echo 'realpath_cache_size=4096K'; \
        echo 'realpath_cache_ttl=600'; \
        echo 'opcache.memory_consumption=256'; \
        echo 'opcache.max_accelerated_files=20000'; \
        echo 'opcache.validate_timestamps=0'; \
        echo 'opcache.revalidate_freq=0'; \
        echo 'opcache.fast_shutdown=1'; \
        echo 'opcache.enable_cli=1'; \
        echo 'opcache.jit=1255'; \
        echo 'opcache.jit_buffer_size=128M'; \
    } > /usr/local/etc/php/conf.d/composer-optimizations.ini

# Configuration PHP
COPY docker/php/conf/php.ini /usr/local/etc/php/php.ini
COPY docker/php/conf/xdebug.ini /usr/local/etc/php/conf.d/xdebug.ini.disabled

# Script d'aide pour Composer avec gestion mémoire
RUN mkdir -p /usr/local/bin && \
    echo '#!/bin/bash\n\
set -e\n\
# Nettoyer le cache si peu de mémoire\n\
if [ $(free -m | awk "NR==2{print \$4}") -lt 500 ]; then\n\
    echo "Mémoire faible détectée, nettoyage du cache..."\n\
    composer clear-cache\n\
fi\n\
# Options d optimisation pour install/update\n\
COMPOSER_OPTS=""\n\
if [ "$1" = "install" ] || [ "$1" = "update" ]; then\n\
    COMPOSER_OPTS="--optimize-autoloader --apcu-autoloader --classmap-authoritative"\n\
fi\n\
# Exécuter Composer avec les bonnes permissions\n\
if [ "$1" = "install" ] || [ "$1" = "update" ] || [ "$1" = "require" ]; then\n\
    # Utiliser www-data pour les commandes modifiant vendor/\n\
    exec su -s /bin/bash www-data -c "composer $* $COMPOSER_OPTS"\n\
else\n\
    exec composer "$@"\n\
fi' > /usr/local/bin/composer-safe && \
    chmod +x /usr/local/bin/composer-safe

# Alias pour utiliser composer-safe par défaut
RUN echo 'alias composer="composer-safe"' >> /etc/bash.bashrc

# Supervisor
COPY docker/supervisor/supervisord.conf /etc/supervisor/supervisord.conf
COPY docker/supervisor/conf.d/ /etc/supervisor/conf.d/

# Entrypoint + healthcheck
COPY docker/php/scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY docker/php/scripts/healthcheck.php /usr/local/bin/healthcheck.php
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Préparer répertoires et droits
RUN mkdir -p /var/www/html /var/log/supervisor /var/run \
    && chown -R www-data:www-data /var/www/html /var/log/supervisor /var/run /var/composer /tmp/composer-cache

WORKDIR /var/www/html

# Healthcheck optimisé
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
    CMD php /usr/local/bin/healthcheck.php || exit 1

EXPOSE 9000

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# Stage 5: Development (optionnel - avec Xdebug activé)
FROM production AS development

# Activer Xdebug pour le développement
# Remplacer l'ancienne config par la nouvelle config PHPStorm
RUN rm -f "$PHP_INI_DIR/conf.d/xdebug.ini" && \
    mv "$PHP_INI_DIR/conf.d/xdebug.ini.disabled" "$PHP_INI_DIR/conf.d/xdebug.ini"

# Ajuster la limite mémoire pour le dev
RUN sed -i 's/memory_limit=2G/memory_limit=4G/' /usr/local/etc/php/conf.d/composer-optimizations.ini

# Stage 6: Test navigateur — JAMAIS déployé
#
# Ce stage descend de `development`, donc ni `production` ni `development` ne
# portent Chromium. C'est la condition (2) du spike ADR-0011 : le coût du
# navigateur reste confiné à une image de test.
#
# Le service qui l'utilise est `php-test`, sous profil Compose `test` : il n'est
# démarré ni par `make up-prod`, ni par `make up-local`.
FROM development AS test

# Chromium natif Alpine, compilé contre musl.
# Les builds distribués par `playwright install` sont linux64/glibc et NE
# S'EXÉCUTENT PAS ici — ELF valide, interpréteur absent. Voir ADR-0013.
RUN apk add --no-cache chromium

# Chemin partagé, hors de /root : les tests tournent en uid 1000 alors que
# l'image est bâtie en root, et /root/.cache leur serait illisible.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

COPY docker/php/scripts/link-alpine-chromium.sh /usr/local/bin/link-alpine-chromium.sh
COPY docker/php/scripts/run-browser-tests.sh /usr/local/bin/run-browser-tests.sh
COPY docker/php/scripts/browser-verdict.php /usr/local/bin/browser-verdict.php
RUN chmod +x /usr/local/bin/link-alpine-chromium.sh /usr/local/bin/run-browser-tests.sh \
    && mkdir -p /opt/ms-playwright

# Le lien est posé au démarrage, pas au build : il dépend de la révision
# déclarée par le Playwright installé dans node_modules, qui est un bind mount.