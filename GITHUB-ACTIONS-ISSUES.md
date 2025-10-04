# 🔴 Problèmes GitHub Actions Identifiés

## Analyse des 3 workflows

### ❌ PROBLÈMES CRITIQUES

#### 1. **ci.yml** - Laravel CI/CD Pipeline

**Ligne 98** : Installation Composer sans dev dependencies puis scripts composer qui nécessitent dev
```yaml
composer install --no-interaction --prefer-dist --optimize-autoloader --no-progress --no-scripts
```
❌ Problème : `--no-scripts` empêche l'exécution des scripts post-install

**Lignes 186-198** : Scripts composer qui n'existent PAS dans composer.json actuel
```yaml
- composer run check:cs      # ❌ N'existe pas
- composer run analyse        # ❌ N'existe pas  
- composer run refactor       # ❌ N'existe pas
- composer run insights       # ❌ N'existe pas
- composer run test:coverage  # ❌ N'existe pas
```

**Fichier src/composer.json actuel** ne contient PAS ces scripts !

**Ligne 247** : Fichier .env.example n'existe probablement pas dans src/
```bash
cp src/.env.example src/.env
```

#### 2. **docker.yml** - Docker Build & Validation

**Ligne 54** : Commande docker-compose obsolète
```bash
docker-compose config  # ❌ Utiliser docker compose (sans tiret)
```

**Lignes 208-223** : Test des images qui n'existent pas encore localement
```bash
image_name="${{ env.REGISTRY }}/${{ env.NAMESPACE }}-${{ matrix.service }}:${{ github.sha }}"
docker run --rm "$image_name" php --version
```
❌ L'image n'a pas été construite avec ce tag

**Ligne 247** : Fichier src/.env.example manquant
```bash
cp src/.env.example src/.env || echo "No .env.example found"
```

**Ligne 264** : docker-compose obsolète
```bash
docker-compose up -d --build  # ❌ Utiliser docker compose
```

#### 3. **security.yml** - Security Audit

**Ligne 50** : Installation sans scripts
```yaml
composer install --no-interaction --no-scripts --no-dev --prefer-dist
```
❌ Puis utilise des outils qui nécessitent dev dependencies

**Lignes 225-230** : PHPStan nécessite dev dependencies
```bash
vendor/bin/phpstan analyse  # ❌ Pas installé si --no-dev
```

**Ligne 258** : Vérifie un fichier qui n'existe pas dans Laravel 11+
```bash
grep -r "VerifyCsrfToken" app/Http/Kernel.php
```
❌ Laravel 12 n'a plus de Kernel.php

---

## 🔧 CORRECTIONS NÉCESSAIRES

### 1. Créer src/.env.example

```bash
cd src/
cp .env .env.example  # Si .env existe
# OU créer manuellement
```

### 2. Ajouter les scripts manquants dans src/composer.json

```json
{
  "scripts": {
    "check:cs": "vendor/bin/ecs",
    "fix:cs": "vendor/bin/ecs --fix",
    "analyse": "vendor/bin/phpstan analyse",
    "refactor": "vendor/bin/rector process --dry-run",
    "refactor:fix": "vendor/bin/rector process",
    "insights": "php artisan insights",
    "insights:fix": "php artisan insights --fix",
    "test": "php artisan test",
    "test:coverage": "php artisan test --coverage-html coverage --coverage-clover coverage.xml",
    "test:unit": "vendor/bin/pest --testsuite=Unit",
    "test:feature": "vendor/bin/pest --testsuite=Feature"
  }
}
```

### 3. Corriger docker-compose (ci.yml ligne 54, 66, 264, etc.)

**Avant :**
```yaml
docker-compose config
docker-compose up -d
```

**Après :**
```yaml
docker compose config
docker compose up -d
```

### 4. Corriger l'installation Composer (ci.yml ligne 98)

**Avant :**
```yaml
composer install --no-interaction --prefer-dist --optimize-autoloader --no-progress --no-scripts
```

**Après :**
```yaml
composer install --no-interaction --prefer-dist --optimize-autoloader --no-progress
```

### 5. Corriger le test Docker (docker.yml lignes 198-224)

**Problème** : L'image n'est pas buildée avec le tag testé

**Solution** : Utiliser le tag local ou récupérer l'image buildée

### 6. Corriger security.yml (ligne 50)

**Avant :**
```yaml
composer install --no-interaction --no-scripts --no-dev --prefer-dist
```

**Après :**
```yaml
composer install --no-interaction --prefer-dist  # Inclure dev pour PHPStan
```

---

## 📋 FICHIERS À CRÉER/MODIFIER

### Priorité 1 (CRITIQUE)
1. ✅ `src/composer.json` - Ajouter scripts manquants
2. ✅ `src/.env.example` - Créer fichier exemple
3. ✅ `.github/workflows/ci.yml` - Corriger scripts composer
4. ✅ `.github/workflows/docker.yml` - docker-compose → docker compose
5. ✅ `.github/workflows/security.yml` - Inclure dev dependencies

### Priorité 2 (IMPORTANT)
6. `.github/workflows/ci.yml` - Retirer --no-scripts
7. `.github/workflows/docker.yml` - Corriger tags images
8. `.github/workflows/security.yml` - Adapter pour Laravel 12

---

## 🎯 SOLUTION RAPIDE

**Option 1 : Corriger maintenant**
1. Ajouter scripts dans composer.json
2. Créer .env.example
3. Corriger docker-compose → docker compose
4. Retirer --no-dev de security.yml

**Option 2 : Désactiver temporairement**
Ajouter en haut de chaque workflow :
```yaml
on:
  workflow_dispatch:  # Seulement manuel
# Commenter push/pull_request
```

---

## ✅ VÉRIFICATIONS POST-FIX

```bash
# 1. Vérifier que les scripts existent
cd src/
composer run check:cs --help
composer run analyse --help
composer run test --help

# 2. Vérifier .env.example
ls -la src/.env.example

# 3. Tester docker compose localement
docker compose config
docker compose version

# 4. Push et vérifier GitHub Actions
git add .
git commit -m "fix: GitHub Actions workflows"
git push
```

---

**Fichiers identifiés comme problématiques :**
- ❌ `src/composer.json` - Scripts manquants
- ❌ `src/.env.example` - Fichier manquant
- ❌ `.github/workflows/ci.yml` - Multiples problèmes
- ❌ `.github/workflows/docker.yml` - docker-compose obsolète
- ❌ `.github/workflows/security.yml` - Dev dependencies manquantes

**Estimation temps de correction : 15-30 minutes**
