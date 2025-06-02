FROM httpd:2.4-alpine

# Arguments pour l'utilisateur
ARG UID=1000
ARG GID=1000

# Installation des dépendances
RUN apk add --no-cache \
    openssl \
    curl \
    bash \
    shadow \
    netcat-openbsd

# Création de l'utilisateur (mais Apache reste root pour les ports)
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
    CMD curl -k -f https://localhost/health || curl -f http://localhost/ || exit 1

# Apache doit rester root pour binder les ports < 1024
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]