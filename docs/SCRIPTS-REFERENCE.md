# 📚 Scripts Reference - Documentation Complète

**Total**: 34 scripts shell organisés en 6 catégories

---

## 📂 Structure des Scripts

```
scripts/
├── *.sh                 # Scripts racine (13 fichiers)
├── install/            # Installation modulaire (11 scripts)
├── lib/                # Bibliothèques partagées (5 scripts)
├── ops/                # Exploitation — sauvegardes (2 scripts)
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

**Modules lancés** (dans l'ordre): les **11** entrées du tableau
`INSTALL_MODULES` — `00`, `05`, `10`, `20`, `30`, `35`, `40`, `45`, `50`, `60`,
`99`. ⚠️ La numérotation ne comporte ni `01`, ni `06`, ni `07` : plusieurs
documents de planification en supposent, à tort.

**Idempotence** (Story 2.2): chaque module franchi pose une sentinelle
`<cible>/.install-state/<module>-done`. Une install interrompue **reprend
d'elle-même** au module qui a échoué — inutile de taper `--resume-from`. Un
module en échec ne pose PAS sa sentinelle : il sera rejoué. `--force` ignore et
réécrit toutes les sentinelles. La racine d'état est surchargeable par
`INSTALL_STATE_DIR`.

⚠️ Elle vit sous la **cible** (donc `src/.install-state/`) et non à la racine du
dépôt : celle-ci est montée `ro` dans les conteneurs php et node. `test -w` y rend
pourtant VRAI — seule l'écriture réelle tranche.

**Utilisation**:
```bash
make install-laravel  # Appelle ce script
./scripts/install.sh --force        # tout rejouer
./scripts/install.sh --list-modules # voir les 11 identifiants
```

---

### 1bis. 🔒 **install-lockfile.sh** - ESSENTIEL
**Chemin**: `scripts/install-lockfile.sh`
**Utilisé par**: `make install-lockfile`, appelé par `install-dev`, `install-dev-full`,
`install-dev-fast` **après** `npm-install`
**Description**: Écrit `src/.install-state/lock.yml` — empreinte sha256 de
`src/composer.lock`, version PHP du conteneur php, version Node du conteneur
**node**, `started_at` / `finished_at`.

**Pourquoi un script HÔTE et non une étape d'`install.sh`** (contraintes mesurées):
- le conteneur php n'a **ni CLI docker ni socket** : il ne peut pas interroger le
  conteneur node ;
- les deux conteneurs n'ont pas le même node — c'est celui du conteneur **node**
  qui produit `node_modules/` ;
- `npm-install` tourne **après** `install-laravel` : un lockfile écrit en fin
  d'`install.sh` décrirait un `node_modules/` inexistant.

⛔ **Aucune valeur de repli.** Conteneur absent, `composer.lock` absent,
horodatage de début absent : le script meurt en nommant ce qui manque, et
**rien** n'est écrit.

⛔ **Non appelé par `install-prod` / `install-prod-fast`** : ces chaînes ne jouent
pas `npm-install`, le conteneur node n'y tourne donc pas.

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
**Description**: Diagnostics complets PHP 8.5 + Laravel 12

**Fonctionnalité**:
- Vérifie PHP 8.5 extensions
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
- Skip images standard (PostgreSQL, Redis)
- Avec ou sans cache

**Utilisation**:
```bash
./scripts/update-custom-images.sh
```

---

## 🔴 Scripts « potentiellement obsolètes » — SECTION SUPPRIMÉE

> 🔴 **Cette section décrivait cinq scripts qui n'existent pas**, en détaillant
> leur taille, leur usage et une recommandation pour chacun :
> `backup-before-cleanup.sh`, `setup-auto-update.sh`,
> `test-installation-complete.sh`, `test-watchtower.sh`, `validate-all-fixes.sh`
> — plus `create-gitkeep.sh` un peu plus haut. **Six fiches complètes pour zéro
> fichier sur disque**, avec des octets au B près.
>
> Ils avaient probablement été supprimés il y a longtemps ; la documentation,
> elle, ne l'a jamais su. C'est la forme documentaire du motif dominant du
> dépôt : *l'affirmation précède son référent*, et plus la fiche est détaillée,
> plus elle inspire confiance. Relevé à la **revue 2** de la Story 2.2.
>
> ⚠️ Un test compte désormais les scripts **sur disque** et exige que chacun
> soit nommé dans ce fichier — mais il ne peut pas, seul, empêcher d'y décrire
> un fichier absent. Ce qui protège de cela est l'inventaire complet ci-dessous,
> exhaustif et daté.

---

## 📚 Scripts Bibliothèque (lib/) - NE PAS TOUCHER

### 18-22. Bibliothèques partagées
**Chemin**: `scripts/lib/*.sh`

| Script | Rôle |
|--------|------|
| `common.sh` | Fonctions communes (colors, logging) |
| `logging.sh` | Système de logs — affichage sur **stderr**, fichier sur `$LOG_FILE` |
| `docker.sh` | Utilitaires Docker |
| `laravel.sh` | Helpers Laravel |
| `runtime.sh` | Primitives d'exécution : `die`, `retry`, `require_cmd`, `ensure_idempotent`, `arm_err_trap` (Story 2.1) |

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
| 00 | `00-prerequisites.sh` | Vérifications pré-install |
| 05 | `05-composer-setup.sh` | Config Composer |
| 10 | `10-laravel-core.sh` | Laravel de base |
| 20 | `20-database.sh` | Base de données |
| 30 | `30-packages-prod.sh` | Packages production |
| 35 | `35-configure-spatie-packages.sh` | Config packages Spatie |
| 40 | `40-packages-dev.sh` | Packages développement |
| 45 | `45-configure-pest.sh` | Config Pest |
| 50 | `50-quality-tools.sh` | PHPStan, ECS, Rector |
| 60 | `60-nightwatch.sh` | Laravel Nightwatch |
| 99 | `99-finalize.sh` | Finalisation |

> ⚠️ Ce tableau annonçait **9** modules pour **11** sur disque (`35` et `45`
> manquaient) et amputait chaque nom de son préfixe d'ordre — alors que ce
> préfixe EST l'identifiant public du module : c'est ce que prennent `--only`,
> `--resume-from`, et c'est le grain des sentinelles d'idempotence
> (`.install-state/<module>-done`). Corrigé le 2026-08-22 (Story 2.2).

**Utilisation**: Appelés automatiquement par `scripts/install.sh`

**Recommandation**: ✅ **GARDER TOUS** - Architecture modulaire

---

## 📊 Résumé - Actions Recommandées

### ✅ INVENTAIRE COMPLET — 34 scripts, tous présents sur disque

> 🔴 **Ce bloc était faux, et il l'était deux fois.** Corrigé à la **revue 2** de
> la Story 2.2, après une première correction incomplète à la revue 1.
>
> - Le total annonçait **27** pour des sous-totaux à **28** — arithmétique
>   corrigée à la revue 1, avec un encadré qui augmentait la confiance accordée
>   au bloc.
> - Mais l'**inventaire** restait faux : il prescrivait d'archiver ou de
>   supprimer **six scripts qui n'existent pas** (`backup-before-cleanup.sh`,
>   `validate-all-fixes.sh`, `test-installation-complete.sh`,
>   `setup-auto-update.sh`, `test-watchtower.sh`, `create-gitkeep.sh`), et il
>   **omettait trois scripts bien présents** — dont `assert-tracked-files.sh` et
>   `quality-ratchet.sh`, les deux que le bloc gelé de cette story inscrit en
>   `Never: toucher` parce qu'ils sont bloquants en CI.
>
> Une arithmétique juste sur un inventaire faux est pire qu'un compteur faux :
> elle se relit comme vérifiée. La liste ci-dessous est désormais **comptée sur
> disque par un test** (`InstallSentinelsTest`), qui exige que **chaque** script
> présent soit nommé ici.

#### Scripts racine (13)
- ✅ `install.sh` — Orchestrateur d'installation, idempotent depuis la Story 2.2
- ✅ `install-lockfile.sh` — Lockfile d'installation (script **hôte**)
- ✅ `assert-tracked-files.sh` — ⛔ **Bloquant en CI** : refuse qu'un fichier source soit gitignoré
- ✅ `quality-ratchet.sh` — ⛔ **Bloquant en CI** : compteurs de dette monotones (0/0/0)
- ✅ `fix-permissions.sh` — Permissions WSL/PhpStorm
- ✅ `diagnostic-tools.sh` — Diagnostics PHP/Laravel
- ✅ `check-package-compatibility.sh` — Compatibilité des paquets
- ✅ `configure-test-database.sh` — Base de tests
- ✅ `setup-env-optimizations.sh` — Optimisations d'environnement
- ✅ `setup-watchtower-simple.sh` — Watchtower
- ✅ `setup-git-hooks.sh` — Hooks git
- ✅ `update-custom-images.sh` — Mise à jour des images Docker maison
- ✅ `TEST-PROFILES.sh` — Vérification des profiles Docker Compose

#### Modules install/ (11)
- ✅ Tous les scripts `install/*.sh` — voir le tableau des modules plus haut

#### Bibliothèques lib/ (5)
- ✅ Tous les scripts `lib/*.sh` — voir le tableau des bibliothèques plus haut

#### Exploitation ops/ (2)
- ✅ `ops/backup-local.sh` — Sauvegarde locale (ADR-0003)
- ✅ `ops/backup-offsite.sh` — Sauvegarde hors site (ADR-0003)

#### Sécurité (1)
- ✅ `security/snyk-scan.sh` — Scan de vulnérabilités

#### Configuration setup/ (2)
- ✅ `setup/interactive-setup.sh` — Installation interactive
- ✅ `setup/generate-configs.sh` — Génération des configurations

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
