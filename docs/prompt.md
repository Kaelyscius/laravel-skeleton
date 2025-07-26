# 🔧 PROMPT POUR REFACTORISER install-laravel.sh

## CONTEXTE DU PROJET

Je travaille sur un template Laravel industrialisé avec Docker. Le script `docker/scripts/install-laravel.sh` fait actuellement **2300+ lignes** et doit être refactorisé en modules.

### ARCHITECTURE ACTUELLE
- **Projet** : Template Laravel 12 + PHP 8.4 + Docker
- **But** : Base réutilisable pour créer rapidement des projets Laravel
- **Configuration centralisée** : `config/installer.yml` (voir fichiers joints)
- **Générateur** : `scripts/setup/generate-configs.sh`

### PROBLÈMES DU SCRIPT ACTUEL
- **2300+ lignes** - ingérable
- Mélange de responsabilités (Laravel, packages, DB, qualité, Nightwatch)
- Variables hardcodées partout
- Debugging impossible
- Maintenance cauchemardesque

## OBJECTIF DE REFACTORING

### STRUCTURE CIBLE
```bash
scripts/
├── install/
│   ├── 00-prerequisites.sh      # Vérifications système
│   ├── 10-laravel-core.sh       # Installation Laravel de base
│   ├── 20-database.sh           # Configuration et migrations DB
│   ├── 30-packages-prod.sh      # Packages de production
│   ├── 40-packages-dev.sh       # Packages de développement
│   ├── 50-quality-tools.sh      # Configuration outils qualité
│   ├── 60-nightwatch.sh         # Configuration Nightwatch
│   └── 99-finalize.sh           # Finalisation et nettoyage
├── lib/
│   ├── common.sh                # Fonctions communes
│   ├── docker.sh                # Utilitaires Docker
│   ├── laravel.sh               # Utilitaires Laravel
│   └── logging.sh               # Système de logs
└── install.sh                   # Orchestrateur principal
```

### FONCTIONS À EXTRAIRE DU SCRIPT ACTUEL

#### Scripts modulaires :
1. **00-prerequisites.sh** : `check_prerequisites()`, `detect_working_directory()`, `wait_for_database()`
2. **10-laravel-core.sh** : `create_laravel_project()`, `copy_root_env_to_laravel()`, `generate_app_key()`
3. **20-database.sh** : `run_base_migrations()`, `run_final_migrations()`, `prevent_migration_conflicts()`
4. **30-packages-prod.sh** : Installation packages production depuis `config/installer.yml`
5. **40-packages-dev.sh** : Installation packages développement + configuration
6. **50-quality-tools.sh** : `create_quality_tools_config()`, configuration ECS/PHPStan/Rector
7. **60-nightwatch.sh** : Configuration et démarrage Nightwatch
8. **99-finalize.sh** : `optimize_composer()`, génération IDE helpers, caches

#### Bibliothèques communes :
- **common.sh** : `log()`, `check_container()`, `is_package_installed()`
- **docker.sh** : Fonctions Docker/Compose
- **laravel.sh** : `get_laravel_version()`, `artisan()`, `composer()`
- **logging.sh** : Système de logs structuré

### PRINCIPES DE REFACTORING

1. **Modularité** : Chaque script = une responsabilité
2. **Configuration centralisée** : Lire depuis `config/installer.yml`
3. **Gestion d'erreurs** : Exit codes cohérents, rollback possible
4. **Logging uniforme** : Toutes les fonctions utilisent le même système
5. **Tests unitaires** : Chaque module testable indépendamment
6. **Idempotence** : Relancer sans casser l'existant

### COMPATIBILITÉ REQUISE

- **Conserver** : Toutes les fonctionnalités actuelles
- **Variables** : Lire depuis `config/installer.yml` via `yq`
- **Logs** : Format compatible avec le système actuel
- **Docker** : Compatible avec l'architecture Docker existante
- **Makefile** : `make install-laravel` doit continuer à fonctionner

### MIGRATION PROGRESSIVE

1. **Étape 1** : Créer les modules sans casser l'existant
2. **Étape 2** : Tester chaque module indépendamment
3. **Étape 3** : Remplacer l'ancien script par l'orchestrateur
4. **Étape 4** : Supprimer l'ancien script une fois validé

## INSTRUCTIONS POUR LE REFACTORING

### COMMENCER PAR :
1. **Analyser** le script actuel `docker/scripts/install-laravel.sh`
2. **Identifier** les fonctions principales et leurs dépendances
3. **Créer** la structure modulaire proposée
4. **Extraire** les fonctions en respectant les responsabilités

### RÈGLES IMPORTANTES :
- **Pas de duplication** de code entre modules
- **Gestion d'erreurs** robuste dans chaque module
- **Configuration** lue depuis `config/installer.yml`
- **Tests** de chaque module avant intégration
- **Documentation** de chaque fonction

### FORMAT DE LIVRAISON :
1. Un module à la fois (pour éviter les messages trop longs)
2. Tests de validation pour chaque module
3. Script de migration de l'ancien vers le nouveau
4. Documentation des changements

## QUESTION AVANT DE COMMENCER

Quel module veux-tu que je commence par créer en premier ?
- `lib/common.sh` (fonctions communes)
- `00-prerequisites.sh` (vérifications)
- `10-laravel-core.sh` (cœur Laravel)
- L'orchestrateur `install.sh`

---

*Utilise ce prompt si tu dois relancer une discussion pour le refactoring du script install-laravel.sh*