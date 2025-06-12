#!/bin/bash

# Script de génération de certificats SSL auto-signés pour Laravel
# Usage: ./docker/scripts/generate-ssl.sh

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
DOMAIN="laravel.local"
SSL_DIR="./docker/apache/conf/ssl"
DAYS=365
KEY_SIZE=2048

echo -e "${CYAN}🔐 Génération de certificats SSL auto-signés${NC}"
echo -e "${CYAN}===========================================${NC}"

# Créer le répertoire SSL s'il n'existe pas
mkdir -p "$SSL_DIR"

# Vérifier si OpenSSL est installé
if ! command -v openssl &> /dev/null; then
    echo -e "${RED}❌ OpenSSL n'est pas installé${NC}"
    echo -e "${YELLOW}💡 Installation requise :${NC}"
    echo -e "  • Ubuntu/Debian: sudo apt-get install openssl"
    echo -e "  • CentOS/RHEL: sudo yum install openssl"
    echo -e "  • macOS: brew install openssl"
    exit 1
fi

echo -e "${YELLOW}📋 Configuration du certificat :${NC}"
echo -e "  • Domaine: $DOMAIN"
echo -e "  • Répertoire: $SSL_DIR"
echo -e "  • Validité: $DAYS jours"
echo -e "  • Taille clé: $KEY_SIZE bits"
echo ""

# Vérifier si les certificats existent déjà
if [ -f "$SSL_DIR/$DOMAIN.crt" ] && [ -f "$SSL_DIR/$DOMAIN.key" ]; then
    echo -e "${YELLOW}⚠️  Certificats existants trouvés${NC}"

    # Vérifier la validité du certificat existant
    if openssl x509 -in "$SSL_DIR/$DOMAIN.crt" -noout -checkend 86400 > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Certificat valide pour plus de 24h${NC}"

        # Proposer de régénérer ou conserver
        if [ -t 0 ]; then
            echo -e "${CYAN}Voulez-vous régénérer les certificats ? (y/N)${NC}"
            read -r regenerate
            if [[ ! "$regenerate" =~ ^[Yy]$ ]]; then
                echo -e "${BLUE}→ Conservation des certificats existants${NC}"
                exit 0
            fi
        else
            echo -e "${BLUE}→ Mode non-interactif : conservation des certificats valides${NC}"
            exit 0
        fi
    else
        echo -e "${RED}✗ Certificat expiré ou invalide${NC}"
        echo -e "${YELLOW}→ Régénération automatique...${NC}"
    fi

    # Sauvegarder les anciens certificats
    backup_dir="$SSL_DIR/backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    mv "$SSL_DIR/$DOMAIN.crt" "$backup_dir/" 2>/dev/null || true
    mv "$SSL_DIR/$DOMAIN.key" "$backup_dir/" 2>/dev/null || true
    echo -e "${YELLOW}→ Sauvegarde créée: $backup_dir${NC}"
fi

echo -e "${YELLOW}🔑 Génération de la clé privée...${NC}"

# Générer la clé privée
if ! openssl genrsa -out "$SSL_DIR/$DOMAIN.key" $KEY_SIZE 2>/dev/null; then
    echo -e "${RED}❌ Erreur lors de la génération de la clé privée${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Clé privée générée${NC}"

echo -e "${YELLOW}📜 Génération du certificat...${NC}"

# Créer un fichier de configuration temporaire pour le certificat
config_file=$(mktemp)
cat > "$config_file" << EOF
[req]
default_bits = $KEY_SIZE
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C=FR
ST=Ile-de-France
L=Paris
O=Laravel Development
OU=Development Team
CN=$DOMAIN

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $DOMAIN
DNS.2 = www.$DOMAIN
DNS.3 = localhost
DNS.4 = *.laravel.local
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

# Générer le certificat auto-signé
if ! openssl req -new -x509 -key "$SSL_DIR/$DOMAIN.key" -out "$SSL_DIR/$DOMAIN.crt" -days $DAYS -config "$config_file" -extensions v3_req 2>/dev/null; then
    echo -e "${RED}❌ Erreur lors de la génération du certificat${NC}"
    rm -f "$config_file"
    exit 1
fi

# Nettoyer le fichier de configuration temporaire
rm -f "$config_file"

echo -e "${GREEN}✓ Certificat généré${NC}"

# Définir les permissions appropriées
chmod 600 "$SSL_DIR/$DOMAIN.key"
chmod 644 "$SSL_DIR/$DOMAIN.crt"

echo -e "${YELLOW}🔍 Vérification du certificat...${NC}"

# Vérifier le certificat généré
if openssl x509 -in "$SSL_DIR/$DOMAIN.crt" -text -noout > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Certificat valide${NC}"

    # Afficher les informations du certificat
    echo -e "${BLUE}📋 Informations du certificat :${NC}"
    echo -e "${CYAN}→ Sujet:$(NC)"
    openssl x509 -in "$SSL_DIR/$DOMAIN.crt" -noout -subject | sed 's/subject=/  /'
    echo -e "${CYAN}→ Validité:$(NC)"
    echo -e "  De: $(openssl x509 -in "$SSL_DIR/$DOMAIN.crt" -noout -startdate | sed 's/notBefore=//')"
    echo -e "  À:  $(openssl x509 -in "$SSL_DIR/$DOMAIN.crt" -noout -enddate | sed 's/notAfter=//')"
    echo -e "${CYAN}→ Noms alternatifs:$(NC)"
    openssl x509 -in "$SSL_DIR/$DOMAIN.crt" -noout -text | grep -A 5 "Subject Alternative Name" | tail -4 | sed 's/^/  /'
else
    echo -e "${RED}❌ Certificat invalide${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ Certificats SSL générés avec succès !${NC}"

# Afficher les fichiers générés
echo -e "${BLUE}📁 Fichiers générés :${NC}"
echo -e "  • Certificat: $SSL_DIR/$DOMAIN.crt"
echo -e "  • Clé privée: $SSL_DIR/$DOMAIN.key"
echo ""

# Instructions d'installation dans le système
echo -e "${YELLOW}📱 Installation dans le système (optionnel)${NC}"
echo -e "${YELLOW}=========================================${NC}"
echo ""
echo -e "${BLUE}Pour éviter les avertissements de sécurité dans votre navigateur,${NC}"
echo -e "${BLUE}vous pouvez installer le certificat dans votre système :${NC}"
echo ""

# Instructions spécifiques par OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo -e "${CYAN}🐧 Linux (Ubuntu/Debian) :${NC}"
    echo -e "  sudo cp $SSL_DIR/$DOMAIN.crt /usr/local/share/ca-certificates/"
    echo -e "  sudo update-ca-certificates"
    echo ""
elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo -e "${CYAN}🍎 macOS :${NC}"
    echo -e "  sudo security add-trusted-cert -d -r trustRoot \\"
    echo -e "    -k /Library/Keychains/System.keychain $SSL_DIR/$DOMAIN.crt"
    echo ""
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
    echo -e "${CYAN}🪟 Windows :${NC}"
    echo -e "  1. Double-cliquez sur le fichier: $SSL_DIR/$DOMAIN.crt"
    echo -e "  2. Cliquez sur 'Installer le certificat...'"
    echo -e "  3. Choisissez 'Ordinateur local' et 'Suivant'"
    echo -e "  4. Sélectionnez 'Placer tous les certificats dans le magasin suivant'"
    echo -e "  5. Cliquez sur 'Parcourir' et choisissez 'Autorités de certification racines de confiance'"
    echo -e "  6. Terminez l'installation"
    echo ""
else
    echo -e "${CYAN}🖥️  Système non reconnu :${NC}"
    echo -e "  Consultez la documentation de votre OS pour installer"
    echo -e "  le certificat dans le magasin de certificats de confiance"
    echo ""
fi

# Instructions pour /etc/hosts
echo -e "${YELLOW}🌐 Configuration du fichier hosts${NC}"
echo -e "${YELLOW}================================${NC}"
echo ""
echo -e "${BLUE}Ajoutez cette ligne à votre fichier /etc/hosts :${NC}"
echo -e "${CYAN}127.0.0.1 $DOMAIN www.$DOMAIN${NC}"
echo ""

# Instructions par OS pour éditer hosts
if [[ "$OSTYPE" == "linux-gnu"* ]] || [[ "$OSTYPE" == "darwin"* ]]; then
    echo -e "${CYAN}Commande pour éditer :${NC}"
    echo -e "  sudo nano /etc/hosts"
    echo -e "  # ou"
    echo -e "  echo '127.0.0.1 $DOMAIN www.$DOMAIN' | sudo tee -a /etc/hosts"
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
    echo -e "${CYAN}Windows (en tant qu'administrateur) :${NC}"
    echo -e "  notepad C:\\Windows\\System32\\drivers\\etc\\hosts"
fi

echo ""

# Proposition d'installation automatique
echo -e "\n${YELLOW}🤖 Installation automatique sur le système ?${NC}"
echo -e "${YELLOW}Voulez-vous installer automatiquement le certificat sur votre système ? (y/N)${NC}"

# En mode non-interactif (CI/Docker), on peut passer cette étape
if [ -t 0 ]; then
    read -r auto_install
else
    auto_install="n"
fi

if [[ "$auto_install" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}🔧 Installation automatique du certificat...${NC}"

    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo -e "${YELLOW}→ Linux détecté - installation du certificat...${NC}"
        if command -v sudo >/dev/null 2>&1; then
            if sudo cp "$SSL_DIR/$DOMAIN.crt" /usr/local/share/ca-certificates/ 2>/dev/null; then
                sudo update-ca-certificates >/dev/null 2>&1
                echo -e "${GREEN}✓ Certificat installé avec succès sur Linux${NC}"
            else
                echo -e "${RED}✗ Échec de l'installation (permissions ?)${NC}"
                echo -e "${YELLOW}→ Essayez manuellement: sudo cp $SSL_DIR/$DOMAIN.crt /usr/local/share/ca-certificates/${NC}"
            fi
        else
            echo -e "${RED}✗ sudo non disponible${NC}"
        fi

    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo -e "${YELLOW}→ macOS détecté - installation du certificat...${NC}"
        if security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain "$SSL_DIR/$DOMAIN.crt" 2>/dev/null; then
            echo -e "${GREEN}✓ Certificat installé avec succès sur macOS${NC}"
        else
            echo -e "${YELLOW}⚠ Installation manuelle peut être requise${NC}"
            echo -e "${YELLOW}→ Essayez: security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain $SSL_DIR/$DOMAIN.crt${NC}"
        fi

    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        echo -e "${YELLOW}→ Windows détecté${NC}"
        echo -e "${BLUE}Installation manuelle requise:${NC}"
        echo -e "${BLUE}1. Double-cliquez sur: $SSL_DIR/$DOMAIN.crt${NC}"
        echo -e "${BLUE}2. Installez dans 'Autorités de certification racines de confiance'${NC}"

    else
        echo -e "${YELLOW}→ OS non reconnu - installation manuelle requise${NC}"
        echo -e "${BLUE}Emplacement du certificat: $SSL_DIR/$DOMAIN.crt${NC}"
    fi
else
    echo -e "${BLUE}→ Installation manuelle - suivez les instructions ci-dessus${NC}"
fi

echo -e "\n${GREEN}🎉 Configuration SSL terminée !${NC}"

# Test de connectivité
echo -e "\n${YELLOW}🧪 Test de connectivité${NC}"
echo -e "${YELLOW}=====================${NC}"

# Vérifier si Apache est en cours d'exécution
if docker ps --format "{{.Names}}" | grep -q "apache" 2>/dev/null; then
    echo -e "${GREEN}✓ Container Apache détecté${NC}"
    echo -e "${BLUE}→ Testez votre configuration: https://$DOMAIN${NC}"
else
    echo -e "${YELLOW}⚠ Container Apache non détecté${NC}"
    echo -e "${BLUE}→ Démarrez votre environnement avec: make up${NC}"
    echo -e "${BLUE}→ Puis testez: https://$DOMAIN${NC}"
fi

echo ""
echo -e "${CYAN}🔗 URLs de test :${NC}"
echo -e "  • HTTPS: https://$DOMAIN"
echo -e "  • HTTP (redirection): http://$DOMAIN"
echo -e "  • Avec www: https://www.$DOMAIN"
echo ""

# Afficher les commandes utiles
echo -e "${BLUE}🛠️ Commandes utiles :${NC}"
echo -e "  • Vérifier le certificat:"
echo -e "    openssl x509 -in $SSL_DIR/$DOMAIN.crt -text -noout"
echo -e "  • Tester la connexion SSL:"
echo -e "    openssl s_client -connect $DOMAIN:443 -servername $DOMAIN"
echo -e "  • Voir l'expiration:"
echo -e "    openssl x509 -in $SSL_DIR/$DOMAIN.crt -noout -enddate"
echo ""

echo -e "${GREEN}✅ Script terminé avec succès !${NC}"