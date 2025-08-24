# GitHub Actions Configuration

Ce dossier contient les workflows GitHub Actions pour l'intégration continue et la validation du projet Laravel.

## 🚀 Workflows Disponibles

### 1. **CI/CD Pipeline** (`workflows/ci.yml`)
**Déclenchement :** Push/PR sur main/develop  
**Durée :** ~15 minutes  
**Objectif :** Tests complets et contrôle qualité  

- ✅ Tests Pest avec coverage 80%
- ✅ PHPStan niveau 8 (analyse statique stricte)
- ✅ ECS (style de code PSR-12)
- ✅ PHP Insights (métriques qualité)
- ✅ Rector (suggestions refactoring)

### 2. **Security Audit** (`workflows/security.yml`)
**Déclenchement :** Push/PR + Quotidien 02:00 UTC  
**Durée :** ~10 minutes  
**Objectif :** Audit sécurité complet  

- 🛡️ Composer audit (vulnérabilités PHP)
- 🛡️ NPM audit (vulnérabilités Node.js)
- 🛡️ Snyk scan (base données complète)
- 🔍 Analyse statique sécurité
- 📊 Monitoring continu (main branch)

### 3. **Docker Build** (`workflows/docker.yml`)
**Déclenchement :** Changements Docker  
**Durée :** ~20 minutes  
**Objectif :** Validation containers  

- 🔍 Validation docker-compose
- 🧹 Lint Dockerfiles (hadolint)
- 🔨 Build multi-service (php/apache/node)
- 🧪 Tests d'intégration
- 🛡️ Scan sécurité (Trivy)

## ⚙️ Configuration Requise

### Secrets GitHub (optionnels)
```bash
SNYK_TOKEN          # Scan sécurité avancé
CODECOV_TOKEN       # Upload coverage
DOCKER_USERNAME     # Push images Docker Hub
DOCKER_PASSWORD     # Push images Docker Hub
```

### Variables d'environnement
```yaml
PHP_VERSION: 8.4    # Compatible Laravel 12
NODE_VERSION: 22    # LTS actuel
```

## 🎯 Utilisation

### Validation locale
Avant de pusher, testez localement :
```bash
# Mêmes tests que CI
make quality-all
make test

# Validation Docker
make build
docker-compose config
```

### Debugging
En cas d'échec, consultez :
1. **Logs GitHub Actions** dans l'onglet Actions
2. **Artifacts** générés (coverage, reports)
3. **Documentation complète** : `/docs/GITHUB-WORKFLOWS.md`

## 🔧 Modifications

### Ajout de nouveaux checks
1. Modifier le workflow approprié
2. Tester localement avec `act` (optionnel)
3. Valider YAML : `yamllint .github/workflows/`

### Désactivation temporaire
Commenter la section `on:` du workflow concerné.

---

📚 **Documentation complète :** Voir `/docs/GITHUB-WORKFLOWS.md` pour tous les détails techniques, configuration et troubleshooting.