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