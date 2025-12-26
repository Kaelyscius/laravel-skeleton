# 📚 Scripts Reference - Documentation Complète

**Total**: 31 scripts shell organisés en 6 catégories

---

## 📂 Structure des Scripts

```
scripts/
├── *.sh                 # Scripts racine (15 fichiers)
├── ci-cd/              # CI/CD (vide actuellement)
├── healthcheck/        # Health checks (vide actuellement)
├── install/            # Installation modulaire (9 scripts)
├── lib/                # Bibliothèques partagées (4 scripts)
├── security/           # Sécurité (1 script)
└── setup/              # Configuration (2 scripts)
```

---

## 🟢 Scripts Utilisés Activement

### 1. 📦 **install.sh** (19K) - ESSENTIEL
**Chemin**: `scripts/install.sh`
**Utilisé par**: `make install-laravel`
**Description**: Orchestrateur principal de l'installation Laravel

**Fonctionnalité**:
- Lance les modules d'installation dans l'ordre
- Gère les logs et erreurs
- Créé par la refactorisation pour remplacer l'ancien monolithe

**Modules lancés** (dans l'ordre):
1. `00-prerequisites.sh` - Vérifications système
2. `05-composer-setup.sh` - Configuration Composer
3. `10-laravel-core.sh` - Installation Laravel
4. `20-database.sh` - Base de données
5. `30-packages-prod.sh` - Packages production
6. `40-packages-dev.sh` - Packages développement
7. `50-quality-tools.sh` - Outils qualité (PHPStan, ECS, Rector)
8. `60-nightwatch.sh` - Laravel Nightwatch
9. `99-finalize.sh` - Finalisation

**Utilisation**:
```bash
make install-laravel  # Appelle ce script
```

---

### 2. 🔧 **fix-permissions.sh** (5.6K) - UTILISÉ
**Chemin**: `scripts/fix-permissions.sh`
**Utilisé par**: `make fix-permissions`
**Description**: Corrige les permissions pour WSL + PhpStorm

**Fonctionnalité**:
- Fix permissions src/, storage/, bootstrap/cache/
- Compatible WSL2 + Windows PhpStorm
- Corrige propriétaire et droits

**Utilisation**:
```bash
make fix-permissions
```

---

### 3. ⚡ **setup-env-optimizations.sh** (5.6K) - UTILISÉ
**Chemin**: `scripts/setup-env-optimizations.sh`
**Utilisé par**: Manuel (documentation)
**Description**: Configure les optimisations d'environnement

**Fonctionnalité**:
- Active Docker BuildKit
- Configure cache Composer
- Configure cache NPM
- Variables WSL

**Utilisation**:
```bash
./scripts/setup-env-optimizations.sh
source ~/.bashrc
```

---

### 4. 🔄 **setup-watchtower-simple.sh** (15K) - UTILISÉ
**Chemin**: `scripts/setup-watchtower-simple.sh`
**Utilisé par**: Setup Docker Watchtower
**Description**: Configure Watchtower pour auto-updates

**Fonctionnalité**:
- Configure Watchtower (mises à jour auto containers)
- Exclut images custom (PHP, Apache, Node)
- Schedule updates

**Utilisation**: Appelé automatiquement lors de la config Docker

---

### 5. 📊 **diagnostic-tools.sh** (14K) - UTILISÉ
**Chemin**: `scripts/diagnostic-tools.sh`
**Utilisé par**: `make diagnostic`
**Description**: Diagnostics complets PHP 8.4 + Laravel 12

**Fonctionnalité**:
- Vérifie PHP 8.4 extensions
- Test Laravel 12 compatibility
- Check packages incompatibles
- Génère rapport détaillé

**Utilisation**:
```bash
make diagnostic
make quick-check        # Version rapide
make check-extensions   # Extensions seulement
```

---

### 6. 🔒 **snyk-scan.sh** (dans security/)
**Chemin**: `scripts/security/snyk-scan.sh`
**Utilisé par**: `make security-scan`
**Description**: Scan sécurité avec Snyk

**Utilisation**:
```bash
make security-scan
```

---

### 7. ⚙️ **interactive-setup.sh** (dans setup/)
**Chemin**: `scripts/setup/interactive-setup.sh`
**Utilisé par**: `make setup-interactive`, `make setup-dev`, `make setup-prod`
**Description**: Configuration interactive de l'environnement

**Fonctionnalité**:
- Setup dev/staging/prod
- Configure .env
- Génère configurations

**Utilisation**:
```bash
make setup-interactive  # Mode interactif
make setup-dev          # Dev automatique
make setup-prod         # Prod automatique
```

---

## 🟡 Scripts Utilitaires (Utiles mais optionnels)

### 8. 🔍 **check-package-compatibility.sh** (6.6K)
**Description**: Vérifie compatibilité packages Laravel 12

**Fonctionnalité**:
- Check si packages supportent Laravel 12
- Identifie packages incompatibles
- Suggère alternatives

**Utilisation**:
```bash
make check-compatibility
```

---

### 9. 🗄️ **configure-test-database.sh** (7.6K)
**Description**: Configure base de données de test

**Fonctionnalité**:
- Créé DB SQLite pour tests
- Configure .env.testing
- Setup migrations test

**Utilisation**: Appelé automatiquement lors des tests

---

### 10. 📝 **create-gitkeep.sh** (694B)
**Description**: Créé fichiers .gitkeep dans dossiers vides

**Utilisation**:
```bash
./scripts/create-gitkeep.sh
```

---

### 11. 🔧 **setup-git-hooks.sh** (4.9K)
**Description**: Configure hooks Git (pre-commit, pre-push)

**Fonctionnalité**:
- Pre-commit: PHPStan, ECS
- Pre-push: Tests
- Quality gates automatiques

**Utilisation**:
```bash
./scripts/setup-git-hooks.sh
```

---

### 12. 🐳 **update-custom-images.sh** (7.1K)
**Description**: Met à jour images Docker custom

**Fonctionnalité**:
- Rebuild PHP, Apache, Node
- Skip images standard (MariaDB, Redis)
- Avec ou sans cache

**Utilisation**:
```bash
./scripts/update-custom-images.sh
```

---

## 🔴 Scripts Potentiellement Obsolètes (À vérifier)

### 13. 💾 **backup-before-cleanup.sh** (5.3K)
**Description**: Backup avant nettoyage

**Statut**: ⚠️ Peut-être obsolète (cleanup déjà fait)

**Utilisation**:
```bash
./scripts/backup-before-cleanup.sh
```

**Recommandation**: Probablement **PEUT ÊTRE SUPPRIMÉ** si cleanup terminé

---

### 14. 🔄 **setup-auto-update.sh** (2.7K)
**Description**: Setup auto-updates (ancien système)

**Statut**: ⚠️ Remplacé par setup-watchtower-simple.sh

**Recommandation**: **À SUPPRIMER** (doublon avec Watchtower)

---

### 15. 🧪 **test-installation-complete.sh** (5.8K)
**Description**: Test installation complète

**Statut**: ⚠️ Utilité limitée

**Utilisation**:
```bash
./scripts/test-installation-complete.sh
```

**Recommandation**: Garder pour debug, ou intégrer dans `make diagnostic`

---

### 16. 🧪 **test-watchtower.sh** (778B)
**Description**: Test Watchtower

**Statut**: ⚠️ Script de test unitaire

**Recommandation**: **PEUT ÊTRE SUPPRIMÉ** (tests déjà validés)

---

### 17. ✅ **validate-all-fixes.sh** (8.2K)
**Description**: Valide tous les fix appliqués

**Statut**: ⚠️ Historique des corrections

**Recommandation**: **À ARCHIVER** (fixes déjà appliqués)

---

## 📚 Scripts Bibliothèque (lib/) - NE PAS TOUCHER

### 18-21. Bibliothèques partagées
**Chemin**: `scripts/lib/*.sh`

| Script | Rôle |
|--------|------|
| `common.sh` | Fonctions communes (colors, logging) |
| `logging.sh` | Système de logs |
| `docker.sh` | Utilitaires Docker |
| `laravel.sh` | Helpers Laravel |

**Utilisation**: Sourcés par autres scripts
```bash
source "$(dirname "$0")/lib/common.sh"
```

**Recommandation**: ✅ **GARDER** - Utilisés partout

---

## 🟢 Scripts Modules d'Installation (install/) - ESSENTIELS

### 22-30. Modules d'installation
**Chemin**: `scripts/install/*.sh`

| Ordre | Script | Fonction |
|-------|--------|----------|
| 00 | `prerequisites.sh` | Vérifications pré-install |
| 05 | `composer-setup.sh` | Config Composer |
| 10 | `laravel-core.sh` | Laravel de base |
| 20 | `database.sh` | Base de données |
| 30 | `packages-prod.sh` | Packages production |
| 40 | `packages-dev.sh` | Packages développement |
| 50 | `quality-tools.sh` | PHPStan, ECS, Rector |
| 60 | `nightwatch.sh` | Laravel Nightwatch |
| 99 | `finalize.sh` | Finalisation |

**Utilisation**: Appelés automatiquement par `scripts/install.sh`

**Recommandation**: ✅ **GARDER TOUS** - Architecture modulaire

---

## 📊 Résumé - Actions Recommandées

### ✅ À GARDER (Scripts essentiels) - 24 scripts

#### Scripts racine (7)
- ✅ `install.sh` - Orchestrateur
- ✅ `fix-permissions.sh` - Permissions WSL
- ✅ `setup-env-optimizations.sh` - Optimisations
- ✅ `setup-watchtower-simple.sh` - Watchtower
- ✅ `diagnostic-tools.sh` - Diagnostics
- ✅ `check-package-compatibility.sh` - Compatibilité
- ✅ `configure-test-database.sh` - Tests DB

#### Modules install/ (9)
- ✅ Tous les scripts `install/*.sh`

#### Bibliothèques lib/ (4)
- ✅ Tous les scripts `lib/*.sh`

#### Setup & Security (3)
- ✅ `setup/interactive-setup.sh`
- ✅ `setup/generate-configs.sh`
- ✅ `security/snyk-scan.sh`

#### Utilitaires optionnels (1)
- ✅ `setup-git-hooks.sh` - Git hooks

---

### ⚠️ À ARCHIVER (Scripts historiques) - 3 scripts

Créer dossier `scripts/archive/` et déplacer :

```bash
mkdir -p scripts/archive
mv scripts/backup-before-cleanup.sh scripts/archive/
mv scripts/validate-all-fixes.sh scripts/archive/
mv scripts/test-installation-complete.sh scripts/archive/
```

**Raison**: Fixes déjà appliqués, utiles pour historique seulement

---

### 🗑️ À SUPPRIMER (Doublons/obsolètes) - 2 scripts

```bash
rm scripts/setup-auto-update.sh      # Remplacé par setup-watchtower-simple.sh
rm scripts/test-watchtower.sh        # Test unitaire obsolète
```

---

### 📝 Optionnels à garder (2 scripts)

- `create-gitkeep.sh` - Utile pour structure projet
- `update-custom-images.sh` - Utile pour updates Docker

---

## 📖 Guide d'Utilisation Rapide

### Installation
```bash
make install-laravel    # Utilise scripts/install.sh
```

### Diagnostics
```bash
make diagnostic         # Utilise scripts/diagnostic-tools.sh
make check-compatibility  # Utilise scripts/check-package-compatibility.sh
```

### Configuration
```bash
make setup-interactive  # Utilise scripts/setup/interactive-setup.sh
make fix-permissions    # Utilise scripts/fix-permissions.sh
```

### Optimisations
```bash
./scripts/setup-env-optimizations.sh
source ~/.bashrc
```

### Sécurité
```bash
make security-scan      # Utilise scripts/security/snyk-scan.sh
```

---

## 🔗 Références Croisées

- **Makefile** utilise: `install.sh`, `fix-permissions.sh`, `diagnostic-tools.sh`
- **GitHub Actions** utilise: Modules `install/*.sh`
- **Docker** utilise: `lib/docker.sh`, `setup-watchtower-simple.sh`

---

## ✅ Conclusion

**Scripts essentiels à garder**: 26
**Scripts à archiver**: 3
**Scripts à supprimer**: 2

Tous les scripts essentiels au fonctionnement sont bien organisés et utilisés. Le nettoyage recommandé améliore la clarté sans impacter les fonctionnalités.
