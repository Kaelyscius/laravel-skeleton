# 🎯 Prompts d'amélioration - Laravel Skeleton

Ce répertoire contient des prompts prêts à l'emploi pour améliorer et étendre le skeleton Laravel. Chaque prompt est une instruction complète pour Claude Code avec tous les détails nécessaires.

## 📂 Structure des prompts

```
prompts/
├── restoration/       # Restauration et réparation
├── enhancements/      # Améliorations fonctionnelles
├── security/          # Renforcement de la sécurité
├── documentation/     # Documentation
├── deployment/        # Déploiement et CI/CD
├── testing/           # Tests et QA
├── monitoring/        # Monitoring et observabilité
└── performance/       # Optimisations de performance
```

## 🚀 Comment utiliser ces prompts

### Méthode 1: Copier-coller dans Claude Code

1. Ouvrir le fichier prompt souhaité
2. Copier tout le contenu
3. Le coller dans Claude Code
4. Claude suivra les instructions pas à pas

### Méthode 2: Référencer dans une conversation

```
@claude Suis les instructions du prompt: prompts/restoration/01-restore-laravel-application.md
```

### Méthode 3: Utiliser avec l'API Claude

```python
with open('prompts/restoration/01-restore-laravel-application.md') as f:
    prompt = f.read()

response = claude.messages.create(
    model="claude-sonnet-4-5",
    messages=[{"role": "user", "content": prompt}]
)
```

## 📋 Prompts disponibles

### 🔴 CRITIQUE - À faire en priorité

#### Restoration (restauration/)

- **01-restore-laravel-application.md** ⭐⭐⭐⭐⭐
  - Restaurer l'application Laravel 12 complète dans `/src`
  - Installer tous les packages documentés
  - Configurer PHPStan, ECS, Rector, Pest
  - Créer des exemples d'implémentation
  - **Durée**: 2-3 heures
  - **Priorité**: CRITIQUE

### 🟠 HAUTE PRIORITÉ - Important pour un skeleton complet

#### Enhancements (enhancements/)

- **01-add-api-documentation.md** ⭐⭐⭐⭐⭐
  - Implémenter L5-Swagger/OpenAPI
  - Documenter automatiquement l'API
  - Interface Swagger UI interactive
  - **Durée**: 1-2 heures
  - **Priorité**: Haute

#### Security (security/)

- **01-implement-2fa-with-fortify.md** ⭐⭐⭐⭐⭐
  - Authentification à deux facteurs (2FA)
  - Support Google Authenticator/Authy
  - Recovery codes et API endpoints
  - **Durée**: 2-3 heures
  - **Priorité**: Haute

#### Monitoring (monitoring/)

- **01-add-sentry-error-tracking.md** ⭐⭐⭐⭐⭐
  - Tracking d'erreurs professionnel
  - Performance monitoring
  - Breadcrumbs et contexte
  - **Durée**: 1-2 heures
  - **Priorité**: Haute

### 🟡 MOYENNE PRIORITÉ - Améliorations importantes

#### Testing (testing/)

- **01-add-dusk-e2e-testing.md** ⭐⭐⭐⭐
  - Tests End-to-End avec navigateur
  - Selenium Chrome intégré
  - Page Objects et VNC debugging
  - **Durée**: 2-3 heures
  - **Priorité**: Moyenne

### 🟢 BASSE PRIORITÉ - Nice to have

#### Performance (performance/)

- **À venir**: Optimisation des requêtes DB
- **À venir**: Cache strategies avancées
- **À venir**: CDN integration

#### Deployment (deployment/)

- **À venir**: Workflow de déploiement CI/CD
- **À venir**: Zero-downtime deployment
- **À venir**: Kubernetes manifests

#### Documentation (documentation/)

- **À venir**: README en anglais
- **À venir**: Architecture Decision Records (ADR)
- **À venir**: CONTRIBUTING.md

## 🎯 Roadmap d'implémentation recommandée

### Phase 1: Foundation (Semaine 1) 🔴

**Objectif**: Rendre le skeleton fonctionnel

1. ✅ `restoration/01-restore-laravel-application.md`
   - Restaurer Laravel 12 dans `/src`
   - Installer tous les packages
   - **BLOQUANT**: Sans ceci, rien ne fonctionne

### Phase 2: Core Features (Semaines 2-3) 🟠

**Objectif**: Ajouter les fonctionnalités essentielles

2. ✅ `enhancements/01-add-api-documentation.md`
   - Documentation API Swagger/OpenAPI
   - Essential pour une API moderne

3. ✅ `monitoring/01-add-sentry-error-tracking.md`
   - Error tracking production
   - Critical pour maintenir l'application

4. ✅ `security/01-implement-2fa-with-fortify.md`
   - 2FA pour sécurité renforcée
   - Important pour applications sensibles

### Phase 3: Testing & Quality (Semaine 4) 🟡

**Objectif**: Renforcer la qualité

5. ✅ `testing/01-add-dusk-e2e-testing.md`
   - Tests E2E automatisés
   - Confiance dans les releases

6. ✅ **À venir**: Tests de performance
7. ✅ **À venir**: Security audit complet

### Phase 4: Production Readiness (Mois 2) 🟢

**Objectif**: Préparer pour la production

8. ✅ **À venir**: Deployment workflows
9. ✅ **À venir**: Backup automation
10. ✅ **À venir**: Performance optimization

### Phase 5: Developer Experience (Mois 3) 🔵

**Objectif**: Améliorer l'expérience développeur

11. ✅ **À venir**: Documentation complète
12. ✅ **À venir**: Video tutorials
13. ✅ **À venir**: Multi-language support

## 📊 Matrice de décision

Utilisez cette matrice pour prioriser les prompts selon vos besoins:

| Prompt | Use Case | Priorité | Durée | Complexité |
|--------|----------|----------|-------|------------|
| Restore Laravel | Tous | 🔴 CRITIQUE | 2-3h | Moyenne |
| API Documentation | API-first | 🟠 Haute | 1-2h | Faible |
| 2FA Security | Enterprise/SaaS | 🟠 Haute | 2-3h | Moyenne |
| Sentry Monitoring | Production | 🟠 Haute | 1-2h | Faible |
| Dusk E2E | Critical UX | 🟡 Moyenne | 2-3h | Moyenne |

## 🎓 Conseils d'utilisation

### Pour les débutants

1. **Commencez par le prompt de restauration** - C'est le prérequis
2. **Suivez l'ordre recommandé** - Les phases build sur les précédentes
3. **Testez après chaque prompt** - Validez que tout fonctionne
4. **Lisez les checklists** - Ne sautez pas d'étapes

### Pour les expérimentés

1. **Adaptez les prompts** - Personnalisez selon vos besoins
2. **Combinez les prompts** - Exécutez plusieurs en parallèle si possible
3. **Ajoutez vos prompts** - Contribuez de nouveaux prompts
4. **Partagez les améliorations** - Pull requests bienvenues

### Best Practices

1. ✅ **Toujours commiter** après un prompt complété
2. ✅ **Tester avant de continuer** au prompt suivant
3. ✅ **Lire la documentation générée** pour comprendre
4. ✅ **Adapter au contexte** si nécessaire
5. ✅ **Suivre les checklists** pour ne rien oublier

## 🤝 Contribution

### Ajouter un nouveau prompt

1. Choisir la catégorie appropriée
2. Nommer: `NN-description-courte.md` (NN = numéro)
3. Suivre le template standard:

```markdown
# Prompt: [Titre descriptif]

## Contexte
[Situation actuelle et problème]

## Objectif
[Ce que le prompt va accomplir]

## Instructions pour Claude Code
[Étapes détaillées]

## Checklist de vérification
[Liste de vérification]

## Références
[Liens utiles]
```

### Template de prompt

Un template vierge est disponible dans `prompts/TEMPLATE.md`

## 📚 Ressources supplémentaires

### Documentation externe

- Laravel 12 Docs: https://laravel.com/docs/12.x
- Pest Framework: https://pestphp.com
- Docker Compose: https://docs.docker.com/compose/
- GitHub Actions: https://docs.github.com/actions

### Communauté

- Issues GitHub: Reportez les problèmes
- Discussions: Proposez des améliorations
- Pull Requests: Contribuez des prompts

## 🔄 Mises à jour

Ce répertoire est maintenu et mis à jour régulièrement avec:
- ✅ Nouveaux prompts basés sur les besoins
- ✅ Améliorations des prompts existants
- ✅ Corrections de bugs dans les instructions
- ✅ Nouveaux use cases et exemples

## ❓ FAQ

**Q: Puis-je modifier les prompts?**
A: Oui! Adaptez-les à vos besoins spécifiques.

**Q: Les prompts fonctionnent-ils avec d'autres AI?**
A: Ils sont optimisés pour Claude mais peuvent être adaptés.

**Q: Combien de temps pour tout implémenter?**
A: Phase 1-3 (essentiels): ~2 semaines. Complet: 1-2 mois.

**Q: Puis-je sauter des prompts?**
A: Oui, sauf le prompt de restauration qui est obligatoire.

**Q: Les prompts sont-ils testés?**
A: Oui, chaque prompt a été testé sur le skeleton.

---

**Dernière mise à jour**: 2026-01-10
**Version**: 1.0.0
**Maintenu par**: L'équipe Laravel Skeleton
