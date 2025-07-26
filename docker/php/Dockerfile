# Stage 1: Base avec toutes les extensions
FROM php:8.4-fpm-alpine AS base

ARG UID=1000
ARG GID=1000

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

# Extensions PHP - séparées selon disponibilité dans PHP 8.4
# Extensions à compiler
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
        gd \
        pdo \
        pdo_mysql \
        mysqli \
        zip \
        intl \
        opcache \
        bcmath \
        xml \
        dom \
        xmlwriter \
        xmlreader \
        simplexml \
        mbstring \
        exif \
        pcntl \
        sockets

# Note: tokenizer, ctype, fileinfo, iconv sont incluses par défaut dans PHP 8.4
# Vérifier leur présence se fera au runtime

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
RUN mkdir -p /var/composer && \
    echo '{\n\
    "config": {\n\
        "process-timeout": 3600,\n\
        "preferred-install": "dist",\n\
        "sort-packages": true,\n\
        "optimize-autoloader": true,\n\
        "classmap-authoritative": true,\n\
        "apcu-autoloader": true,\n\
        "platform-check": false\n\
    },\n\
    "minimum-stability": "stable",\n\
    "prefer-stable": true\n\
}' > /var/composer/config.json

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
RUN mv "$PHP_INI_DIR/conf.d/xdebug.ini.disabled" "$PHP_INI_DIR/conf.d/xdebug.ini"

# Ajuster la limite mémoire pour le dev
RUN sed -i 's/memory_limit=2G/memory_limit=4G/' /usr/local/etc/php/conf.d/composer-optimizations.ini