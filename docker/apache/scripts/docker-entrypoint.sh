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

# Vérifier la configuration des sites
SITES_CONFIG="/etc/apache2/sites-enabled/laravel.conf"
if [ -f "$SITES_CONFIG" ]; then
    echo -e "${YELLOW}Configuration Laravel détectée${NC}"
    # Inclure les sites enabled dans la configuration principale si pas déjà fait
    if ! grep -q "Include /etc/apache2/sites-enabled/\*.conf" /usr/local/apache2/conf/httpd.conf; then
        echo "Include /etc/apache2/sites-enabled/*.conf" >> /usr/local/apache2/conf/httpd.conf
        echo -e "${GREEN}✓ Configuration Laravel incluse${NC}"
    fi
else
    echo -e "${RED}❌ Configuration Laravel manquante : $SITES_CONFIG${NC}"
    echo -e "${YELLOW}Contenu de /etc/apache2/sites-enabled/ :${NC}"
    ls -la /etc/apache2/sites-enabled/ 2>/dev/null || echo "  (répertoire vide ou inexistant)"
    exit 1
fi

# Créer les répertoires de logs si nécessaire
mkdir -p /usr/local/apache2/logs

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