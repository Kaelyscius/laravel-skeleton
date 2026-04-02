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

WAIT_TIMEOUT=${WAIT_TIMEOUT:-60}  # Timeout max (en secondes) pour attendre MariaDB et Redis

echo -e "${YELLOW}🚀 Démarrage du container PHP...${NC}"

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

wait_for_service mariadb 3306
wait_for_service redis 6379

# Corriger les permissions pour le développement (compatibilité PHPStorm/IDE)
# www-data dans le container = UID 1000 = même que l'utilisateur hôte
if [ -d "/var/www/html" ]; then
    echo -e "${YELLOW}Correction des permissions pour le développement...${NC}"

    # Corriger le propriétaire si nécessaire (www-data = UID 1000)
    find /var/www/html -not -user www-data -not -path "*/vendor/*" -not -path "*/node_modules/*" -exec chown www-data:www-data {} + 2>/dev/null || true

    # S'assurer que les répertoires critiques ont les bonnes permissions
    if [ -d "/var/www/html/storage" ]; then
        chmod -R 775 /var/www/html/storage 2>/dev/null || true
        chown -R www-data:www-data /var/www/html/storage 2>/dev/null || true
    fi

    if [ -d "/var/www/html/bootstrap/cache" ]; then
        chmod -R 775 /var/www/html/bootstrap/cache 2>/dev/null || true
        chown -R www-data:www-data /var/www/html/bootstrap/cache 2>/dev/null || true
    fi

    # Fichiers spécifiques
    [ -f "/var/www/html/.env" ] && chmod 664 /var/www/html/.env 2>/dev/null || true
    [ -f "/var/www/html/artisan" ] && chmod 775 /var/www/html/artisan 2>/dev/null || true

    echo -e "${GREEN}✓ Permissions corrigées${NC}"
fi

# Vérifier si Laravel est installé
if [ -f "/var/www/html/artisan" ]; then
   echo -e "${YELLOW}Configuration de Laravel...${NC}"

   if [ "$APP_ENV" = "production" ]; then
       echo -e "${YELLOW}Optimisation pour la production...${NC}"
       php artisan config:cache
       php artisan route:cache
       php artisan view:cache
       php artisan event:cache

       if [ -f "/var/www/html/config/opcache-preload.php" ]; then
           echo "opcache.preload=/var/www/html/config/opcache-preload.php" >> /usr/local/etc/php/conf.d/opcache.ini
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

   if [ ! -L "/var/www/html/public/storage" ]; then
       echo -e "${YELLOW}Création du lien de storage...${NC}"
       php artisan storage:link
   fi

   if [ -d "/var/www/html/vendor/laravel/horizon" ] && [ ! -d "/var/www/html/public/vendor/horizon" ]; then
       echo -e "${YELLOW}Publication des assets Horizon...${NC}"
       php artisan horizon:publish
   fi

   echo -e "${GREEN}✓ Laravel configuré${NC}"
else
   echo -e "${YELLOW}Laravel n'est pas encore installé${NC}"
fi

mkdir -p /var/log/supervisor
chown -R www-data:www-data /var/log/supervisor

echo -e "${GREEN}✓ Container PHP prêt${NC}"

# Exécuter la commande principale, ou lancer php-fpm en mode foreground par défaut
if [ $# -eq 0 ]; then
  exec php-fpm -F
else
  exec "$@"
fi
