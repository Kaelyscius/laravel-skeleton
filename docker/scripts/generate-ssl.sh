#!/bin/bash

# Script de génération de certificats SSL auto-signés pour Laravel - CORRIGÉ WINDOWS
# Usage: ./docker/scripts/generate-ssl.sh

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Configuration renforcée pour Windows
DOMAIN="laravel.local"
SSL_DIR="./docker/apache/conf/ssl"
DAYS=3650  # 10 ans pour éviter les renouvellements fréquents
KEY_SIZE=4096  # Clé plus forte pour réduire les alertes
COUNTRY="FR"
STATE="Ile-de-France"
CITY="Paris"
ORG="Laravel Development"
OU="Development Team"

echo -e "${CYAN}🔐 Génération de certificats SSL ULTRA-SÉCURISÉS pour Windows${NC}"
echo -e "${CYAN}================================================================${NC}"

# Détecter l'OS
detect_os() {
    if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ -n "$WINDIR" ]]; then
        echo "windows"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    else
        echo "unknown"
    fi
}

OS_TYPE=$(detect_os)
echo -e "${BLUE}🖥️ OS détecté: $OS_TYPE${NC}"

# Créer le répertoire SSL s'il n'existe pas
mkdir -p "$SSL_DIR"

# Vérifier si OpenSSL est installé
if ! command -v openssl &> /dev/null; then
    echo -e "${RED}❌ OpenSSL n'est pas installé${NC}"
    echo -e "${YELLOW}💡 Installation requise :${NC}"
    case $OS_TYPE in
        "windows")
            echo -e "  • Windows: Installez Git Bash (inclut OpenSSL) ou OpenSSL pour Windows"
            echo -e "  • Ou utilisez WSL: wsl --install"
            ;;
        "linux")
            echo -e "  • Ubuntu/Debian: sudo apt-get install openssl"
            echo -e "  • CentOS/RHEL: sudo yum install openssl"
            ;;
        "macos")
            echo -e "  • macOS: brew install openssl"
            ;;
    esac
    exit 1
fi

echo -e "${YELLOW}📋 Configuration du certificat RENFORCÉE :${NC}"
echo -e "  • Domaine: $DOMAIN"
echo -e "  • Répertoire: $SSL_DIR"
echo -e "  • Validité: $DAYS jours ($(($DAYS / 365)) ans)"
echo -e "  • Taille clé: $KEY_SIZE bits (ultra-sécurisé)"
echo -e "  • Extensions: v3 avec SAN pour compatibilité maximale"
echo ""

# Vérifier si les certificats existent déjà
if [ -f "$SSL_DIR/$DOMAIN.crt" ] && [ -f "$SSL_DIR/$DOMAIN.key" ]; then
    echo -e "${YELLOW}⚠️  Certificats existants trouvés${NC}"

    # Vérifier la validité du certificat existant
    if openssl x509 -in "$SSL_DIR/$DOMAIN.crt" -noout -checkend 86400 > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Certificat valide pour plus de 24h${NC}"

        # Pour Windows, proposer toujours la régénération pour corriger les problèmes
        if [ "$OS_TYPE" = "windows" ]; then
            echo -e "${CYAN}🪟 Windows détecté - Régénération recommandée pour optimiser la compatibilité${NC}"
            echo -e "${YELLOW}Régénération des certificats pour Windows...${NC}"
        else
            # Proposer de régénérer ou conserver
            if [ -t 0 ]; then
                echo -e "${CYAN}Voulez-vous régénérer les certificats ? (y/N)${NC}"
                read -r regenerate
                if [[ ! "$regenerate" =~ ^[Yy]$ ]]; then
                    echo -e "${BLUE}→ Conservation des certificats existants${NC}"
                    show_windows_install_instructions
                    exit 0
                fi
            else
                echo -e "${BLUE}→ Mode non-interactif : conservation des certificats valides${NC}"
                show_windows_install_instructions
                exit 0
            fi
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

echo -e "${YELLOW}🔑 Génération de la clé privée ultra-sécurisée ($KEY_SIZE bits)...${NC}"

# Générer la clé privée avec une taille renforcée
if ! openssl genrsa -out "$SSL_DIR/$DOMAIN.key" $KEY_SIZE 2>/dev/null; then
    echo -e "${RED}❌ Erreur lors de la génération de la clé privée${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Clé privée ultra-sécurisée générée${NC}"

echo -e "${YELLOW}📜 Génération du certificat avec extensions complètes...${NC}"

# Créer un fichier de configuration OpenSSL ultra-complet pour Windows
config_file=$(mktemp)
cat > "$config_file" << EOF
[req]
default_bits = $KEY_SIZE
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C=$COUNTRY
ST=$STATE
L=$CITY
O=$ORG
OU=$OU
CN=$DOMAIN

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names
authorityKeyIdentifier = keyid,issuer
subjectKeyIdentifier = hash

[alt_names]
DNS.1 = $DOMAIN
DNS.2 = www.$DOMAIN
DNS.3 = localhost
DNS.4 = *.laravel.local
DNS.5 = laravel.test
DNS.6 = www.laravel.test
IP.1 = 127.0.0.1
IP.2 = ::1
IP.3 = 192.168.1.1
IP.4 = 10.0.0.1
EOF

# Générer le certificat auto-signé avec extensions v3 complètes
if ! openssl req -new -x509 -key "$SSL_DIR/$DOMAIN.key" -out "$SSL_DIR/$DOMAIN.crt" -days $DAYS -config "$config_file" -extensions v3_req 2>/dev/null; then
    echo -e "${RED}❌ Erreur lors de la génération du certificat${NC}"
    rm -f "$config_file"
    exit 1
fi

# Nettoyer le fichier de configuration temporaire
rm -f "$config_file"

echo -e "${GREEN}✓ Certificat ultra-sécurisé généré${NC}"

# Définir les permissions appropriées
chmod 600 "$SSL_DIR/$DOMAIN.key"
chmod 644 "$SSL_DIR/$DOMAIN.crt"

echo -e "${YELLOW}🔍 Vérification du certificat...${NC}"

# Vérifier le certificat généré
if openssl x509 -in "$SSL_DIR/$DOMAIN.crt" -text -noout > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Certificat ultra-sécurisé valide${NC}"

    # Afficher les informations du certificat
    echo -e "${BLUE}📋 Informations du certificat :${NC}"
    echo -e "${CYAN}→ Sujet:${NC}"
    openssl x509 -in "$SSL_DIR/$DOMAIN.crt" -noout -subject | sed 's/subject=/  /'
    echo -e "${CYAN}→ Validité:${NC}"
    echo -e "  De: $(openssl x509 -in "$SSL_DIR/$DOMAIN.crt" -noout -startdate | sed 's/notBefore=//')"
    echo -e "  À:  $(openssl x509 -in "$SSL_DIR/$DOMAIN.crt" -noout -enddate | sed 's/notAfter=//')"
    echo -e "${CYAN}→ Taille de clé:${NC} $KEY_SIZE bits"
    echo -e "${CYAN}→ Algorithme:${NC} SHA256 avec RSA"
    echo -e "${CYAN}→ Noms alternatifs:${NC}"
    openssl x509 -in "$SSL_DIR/$DOMAIN.crt" -noout -text | grep -A 10 "Subject Alternative Name" | tail -5 | sed 's/^/  /'
else
    echo -e "${RED}❌ Certificat invalide${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ Certificats SSL ultra-sécurisés générés avec succès !${NC}"

# Afficher les fichiers générés
echo -e "${BLUE}📁 Fichiers générés :${NC}"
echo -e "  • Certificat: $SSL_DIR/$DOMAIN.crt ($KEY_SIZE bits, valide $(($DAYS / 365)) ans)"
echo -e "  • Clé privée: $SSL_DIR/$DOMAIN.key (sécurisée)"
echo ""

# Fonction pour afficher les instructions Windows
show_windows_install_instructions() {
    if [ "$OS_TYPE" = "windows" ]; then
        echo -e "${PURPLE}🪟 INSTRUCTIONS SPÉCIALES POUR WINDOWS${NC}"
        echo -e "${PURPLE}====================================${NC}"
        echo ""
        echo -e "${YELLOW}📱 Installation automatique du certificat :${NC}"
        echo ""
        echo -e "${CYAN}🔧 Méthode 1: Script PowerShell automatique${NC}"
        echo -e "1. Ouvrez PowerShell en tant qu'Administrateur"
        echo -e "2. Exécutez cette commande :"
        echo -e "   ${GREEN}Import-Certificate -FilePath \"$(pwd)/$SSL_DIR/$DOMAIN.crt\" -CertStoreLocation Cert:\\LocalMachine\\Root${NC}"
        echo ""
        echo -e "${CYAN}🖱️ Méthode 2: Interface graphique${NC}"
        echo -e "1. Double-cliquez sur: ${GREEN}$SSL_DIR/$DOMAIN.crt${NC}"
        echo -e "2. Cliquez sur 'Installer le certificat...'"
        echo -e "3. Choisissez 'Ordinateur local' puis 'Suivant'"
        echo -e "4. Sélectionnez 'Placer tous les certificats dans le magasin suivant'"
        echo -e "5. Cliquez sur 'Parcourir' et choisissez ${GREEN}'Autorités de certification racines de confiance'${NC}"
        echo -e "6. Cliquez sur 'Suivant' puis 'Terminer'"
        echo -e "7. Confirmez l'installation avec 'Oui'"
        echo ""
        echo -e "${YELLOW}⚠️ Important pour les antivirus :${NC}"
        echo -e "  • ${GREEN}Windows Defender${NC} : Peut bloquer temporairement - ajouter une exception"
        echo -e "  • ${GREEN}Avast/AVG${NC} : Aller dans Paramètres → Exceptions → Ajouter l'URL https://laravel.local"
        echo -e "  • ${GREEN}Kaspersky${NC} : Protection Web → Gérer les exclusions → Ajouter laravel.local"
        echo -e "  • ${GREEN}Norton${NC} : Paramètres → Antivirus → Exclusions → Sites web → Ajouter laravel.local"
        echo ""
        echo -e "${CYAN}🔄 Après installation :${NC}"
        echo -e "1. Redémarrez votre navigateur complètement"
        echo -e "2. Videz le cache DNS: ${GREEN}ipconfig /flushdns${NC}"
        echo -e "3. Testez l'accès: ${GREEN}https://laravel.local${NC}"
        echo ""
    fi
}

# Instructions d'installation dans le système
echo -e "${YELLOW}📱 Installation dans le système (pour éliminer les avertissements)${NC}"
echo -e "${YELLOW}================================================================${NC}"
echo ""

# Instructions spécifiques par OS
case $OS_TYPE in
    "windows")
        show_windows_install_instructions
        ;;
    "linux")
        echo -e "${CYAN}🐧 Linux (Ubuntu/Debian) :${NC}"
        echo -e "  sudo cp $SSL_DIR/$DOMAIN.crt /usr/local/share/ca-certificates/"
        echo -e "  sudo update-ca-certificates"
        echo ""
        ;;
    "macos")
        echo -e "${CYAN}🍎 macOS :${NC}"
        echo -e "  sudo security add-trusted-cert -d -r trustRoot \\"
        echo -e "    -k /Library/Keychains/System.keychain $SSL_DIR/$DOMAIN.crt"
        echo ""
        ;;
    *)
        echo -e "${CYAN}🖥️  Système non reconnu :${NC}"
        echo -e "  Consultez la documentation de votre OS pour installer"
        echo -e "  le certificat dans le magasin de certificats de confiance"
        echo ""
        ;;
esac

# Instructions pour /etc/hosts
echo -e "${YELLOW}🌐 Configuration du fichier hosts${NC}"
echo -e "${YELLOW}================================${NC}"
echo ""
echo -e "${BLUE}Ajoutez cette ligne à votre fichier hosts :${NC}"
echo -e "${CYAN}127.0.0.1 $DOMAIN www.$DOMAIN${NC}"
echo ""

# Instructions par OS pour éditer hosts
case $OS_TYPE in
    "linux"|"macos")
        echo -e "${CYAN}Commande pour éditer :${NC}"
        echo -e "  sudo nano /etc/hosts"
        echo -e "  # ou"
        echo -e "  echo '127.0.0.1 $DOMAIN www.$DOMAIN' | sudo tee -a /etc/hosts"
        ;;
    "windows")
        echo -e "${CYAN}Windows (en tant qu'administrateur) :${NC}"
        echo -e "  notepad C:\\Windows\\System32\\drivers\\etc\\hosts"
        echo -e "  # ou via PowerShell Admin :"
        echo -e "  Add-Content C:\\Windows\\System32\\drivers\\etc\\hosts '127.0.0.1 $DOMAIN www.$DOMAIN'"
        ;;
esac

echo ""

# Installation automatique si Windows
if [ "$OS_TYPE" = "windows" ]; then
    echo -e "${YELLOW}🤖 Installation automatique Windows ?${NC}"
    echo -e "${YELLOW}Voulez-vous installer automatiquement le certificat dans Windows ? (y/N)${NC}"

    if [ -t 0 ]; then
        read -r auto_install_windows
    else
        auto_install_windows="n"
    fi

    if [[ "$auto_install_windows" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}🔧 Tentative d'installation automatique Windows...${NC}"

        # Convertir le chemin Windows
        windows_cert_path=$(cygpath -w "$(pwd)/$SSL_DIR/$DOMAIN.crt" 2>/dev/null || echo "$(pwd)/$SSL_DIR/$DOMAIN.crt")

        # Essayer PowerShell si disponible
        if command -v powershell.exe >/dev/null 2>&1; then
            echo -e "${YELLOW}→ Utilisation de PowerShell pour l'installation...${NC}"
            if powershell.exe -Command "Import-Certificate -FilePath '$windows_cert_path' -CertStoreLocation Cert:\\LocalMachine\\Root" 2>/dev/null; then
                echo -e "${GREEN}✅ Certificat installé automatiquement dans Windows !${NC}"
                echo -e "${BLUE}→ Redémarrez votre navigateur et testez https://$DOMAIN${NC}"
            else
                echo -e "${YELLOW}⚠️ Installation automatique échouée - permissions admin requises${NC}"
                echo -e "${BLUE}→ Suivez les instructions manuelles ci-dessus${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️ PowerShell non disponible pour l'installation automatique${NC}"
            echo -e "${BLUE}→ Suivez les instructions manuelles ci-dessus${NC}"
        fi
    fi
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

# Instructions spéciales pour Windows
if [ "$OS_TYPE" = "windows" ]; then
    echo -e "${PURPLE}🪟 RÉSOLUTION DES PROBLÈMES WINDOWS${NC}"
    echo -e "${PURPLE}===================================${NC}"
    echo ""
    echo -e "${YELLOW}Si votre antivirus bloque encore le site :${NC}"
    echo -e "1. ${GREEN}Ajoutez une exception${NC} pour https://laravel.local"
    echo -e "2. ${GREEN}Désactivez temporairement${NC} la protection web"
    echo -e "3. ${GREEN}Redémarrez le navigateur${NC} après installation du certificat"
    echo -e "4. ${GREEN}Videz le cache DNS${NC}: ipconfig /flushdns"
    echo -e "5. ${GREEN}Testez en navigation privée${NC} pour éviter le cache"
    echo ""
    echo -e "${CYAN}🔍 Vérification de l'installation :${NC}"
    echo -e "1. Ouvrez certmgr.msc (Gestionnaire de certificats)"
    echo -e "2. Allez dans 'Autorités de certification racines de confiance' → 'Certificats'"
    echo -e "3. Cherchez '$DOMAIN' dans la liste"
    echo -e "4. Si présent → Installation réussie ✅"
    echo ""
fi

echo -e "${GREEN}✅ Script terminé avec succès !${NC}"
echo -e "${CYAN}🎯 Pour une expérience optimale sur Windows :${NC}"
echo -e "  1. Installez le certificat dans le magasin de confiance"
echo -e "  2. Ajoutez une exception antivirus si nécessaire"
echo -e "  3. Redémarrez votre navigateur"
echo -e "  4. Testez avec https://laravel.local"