#!/bin/bash
set -e

# Couleurs pour les logs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Fonction pour détecter le répertoire de travail correct
detect_working_directory() {
    # Si on est dans un container Docker avec /var/www/html (monté depuis ./src)
    if [ -d "/var/www/html" ] && [ -w "/var/www/html" ]; then
        echo "/var/www/html"
        return
    fi

    # Sinon, utiliser le répertoire courant
    echo "$(pwd)"
}

# Fonction pour réparer la configuration Composer
fix_composer_config() {
    echo -e "${YELLOW}Vérification de la configuration Composer...${NC}"

    # Vérifier si le fichier config existe et est valide
    if [ -f "/var/composer/config.json" ]; then
        if ! python3 -m json.tool /var/composer/config.json >/dev/null 2>&1; then
            echo -e "${RED}Configuration Composer corrompue, réparation...${NC}"
            rm -f /var/composer/config.json
        fi
    fi

    # Créer le répertoire si nécessaire
    mkdir -p /var/composer

    # Initialiser une configuration propre
    composer config --global --no-interaction repos.packagist composer https://packagist.org 2>/dev/null || {
        echo -e "${YELLOW}Recréation de la configuration Composer...${NC}"
        echo '{"config":{},"repositories":{"packagist.org":{"type":"composer","url":"https://packagist.org"}}}' > /var/composer/config.json
    }
}

# Fonction pour créer un nouveau projet Laravel
create_laravel_project() {
    local target_dir="$1"

    echo -e "${YELLOW}Création d'un nouveau projet Laravel dans $target_dir${NC}"

    # Vérifier les permissions d'écriture
    if [ ! -w "$target_dir" ]; then
        echo -e "${RED}Erreur : Pas de permission d'écriture dans $target_dir${NC}"
        echo -e "${YELLOW}Essayez avec sudo ou vérifiez les permissions${NC}"
        exit 1
    fi

    # Vérifier si le dossier est vide (ignorer les fichiers cachés comme .gitkeep)
    if [ "$(find "$target_dir" -mindepth 1 -maxdepth 1 ! -name '.*' | wc -l)" -gt 0 ]; then
        echo -e "${RED}Erreur : Le dossier $target_dir n'est pas vide${NC}"
        echo -e "${YELLOW}Contenu trouvé :${NC}"
        ls -la "$target_dir"
        echo -e "${YELLOW}Veuillez vider le dossier ou supprimer son contenu avant l'installation${NC}"
        exit 1
    fi

    # Aller dans le dossier cible et installer Laravel directement dedans
    cd "$target_dir"

    # Créer le projet Laravel dans le répertoire courant (.)
    if ! COMPOSER_MEMORY_LIMIT=-1 composer create-project laravel/laravel . --no-interaction; then
        echo -e "${RED}Échec de la création du projet Laravel${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Projet Laravel créé avec succès dans : $target_dir${NC}"
}

# Fonction pour installer un package avec gestion d'erreur
install_package() {
    local package=$1
    local max_attempts=3
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        echo -e "${YELLOW}Installation de $package (tentative $attempt/$max_attempts)...${NC}"

        # Nettoyer le cache avant l'installation
        composer clear-cache 2>/dev/null || true

        # Essayer d'installer le package
        if COMPOSER_MEMORY_LIMIT=-1 composer require "$package" --no-interaction --no-scripts --no-progress 2>&1; then
            echo -e "${GREEN}✓ $package installé avec succès${NC}"

            # Exécuter les scripts post-installation séparément
            composer run-script post-autoload-dump --no-interaction 2>&1 || true

            return 0
        else
            echo -e "${RED}✗ Échec de l'installation de $package${NC}"

            if [ $attempt -lt $max_attempts ]; then
                echo -e "${YELLOW}Nouvelle tentative dans 5 secondes...${NC}"
                sleep 5
                attempt=$((attempt + 1))
            else
                echo -e "${RED}Impossible d'installer $package après $max_attempts tentatives${NC}"
                return 1
            fi
        fi
    done
}

# Fonction pour optimiser Composer
optimize_composer() {
    echo -e "${YELLOW}Optimisation de Composer...${NC}"

    # Réparer la configuration d'abord
    fix_composer_config

    # Désactiver les plugins non essentiels (avec vérification)
    composer config --global allow-plugins.php-http/discovery false 2>/dev/null || true

    # Optimiser l'autoloader
    composer dump-autoload --optimize --no-interaction 2>/dev/null || true
}

# Installation principale
main() {
    echo -e "${YELLOW}🚀 Installation optimisée de Laravel et ses dépendances${NC}"

    # Détecter le répertoire de travail (normalement /var/www/html dans le container)
    WORKING_DIR=$(detect_working_directory)
    echo -e "${YELLOW}Répertoire de travail détecté : $WORKING_DIR${NC}"

    # Vérifier la mémoire disponible
    if command -v free &> /dev/null; then
        echo -e "${YELLOW}Mémoire disponible :${NC}"
        free -h | grep -E "^Mem|^Swap"
    fi

    # Optimiser Composer
    optimize_composer

    # Vérifier si on a déjà un projet Laravel
    if [ ! -f "$WORKING_DIR/composer.json" ]; then
        echo -e "${YELLOW}Aucun projet Laravel détecté dans $WORKING_DIR${NC}"
        echo -e "${YELLOW}Création d'un nouveau projet Laravel...${NC}"
        create_laravel_project "$WORKING_DIR"
    else
        echo -e "${GREEN}Projet Laravel existant détecté dans $WORKING_DIR${NC}"

        # Vérifier si c'est bien un projet Laravel
        if grep -q "laravel/framework" "$WORKING_DIR/composer.json"; then
            echo -e "${GREEN}✓ Projet Laravel valide trouvé${NC}"
        else
            echo -e "${YELLOW}⚠️  Le composer.json existe mais ne semble pas être un projet Laravel${NC}"
        fi
    fi

    # Se déplacer dans le répertoire de travail pour les installations
    cd "$WORKING_DIR"

    # Liste des packages à installer
    packages=(
        "laravel/horizon"
        "laravel/telescope"
        "laravel/sanctum"
        # Ajoutez d'autres packages ici si nécessaire
    )

    # Installer chaque package séparément
    for package in "${packages[@]}"; do
        if ! install_package "$package"; then
            echo -e "${RED}⚠️  Échec de l'installation de $package${NC}"
            # Continuer avec les autres packages
        fi

        # Pause entre les installations pour libérer de la mémoire
        sleep 2
    done

    # Installation finale et optimisation
    echo -e "${YELLOW}Finalisation de l'installation...${NC}"
    COMPOSER_MEMORY_LIMIT=-1 composer install --no-interaction --optimize-autoloader

    # Publier les assets si nécessaire
    if [ -f "artisan" ]; then
        echo -e "${YELLOW}Publication des assets...${NC}"
        php artisan vendor:publish --tag=horizon-config --force 2>/dev/null || true
        php artisan vendor:publish --tag=horizon-assets --force 2>/dev/null || true
    fi

    # Afficher l'emplacement des fichiers créés
    echo -e "${GREEN}✓ Installation terminée avec succès !${NC}"
    echo -e "${YELLOW}Fichiers Laravel installés dans : $WORKING_DIR${NC}"
    echo -e "${YELLOW}Structure créée :${NC}"
    ls -la "$WORKING_DIR" | head -10

    # Vérifier la présence du package.json
    if [ -f "$WORKING_DIR/package.json" ]; then
        echo -e "${GREEN}✓ package.json trouvé pour npm${NC}"
    else
        echo -e "${RED}⚠️  package.json non trouvé${NC}"
    fi
}

# Exécuter l'installation
main