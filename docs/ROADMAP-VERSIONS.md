# 🗓️ Roadmap des Versions Docker

Ce document planifie les mises à jour futures des images Docker base.

## 📊 État Actuel (Août 2025)

| Component | Version Actuelle | Status | Prochaine Action |
|-----------|------------------|--------|------------------|
| **Node.js** | 22.17.1 LTS | ✅ **Optimal** | Mise à jour vers 24 LTS en oct 2025 |
| **PHP** | 8.4 | ✅ **Stable** | Surveiller PHP 8.5 (nov 2025) |
| **Apache** | 2.4 | ✅ **Stable** | Aucune action requise |

## 🎯 Calendrier des Mises à Jour Planifiées

### 📅 **Octobre 2025 - Node.js 24 LTS**

**Date cible :** Octobre 2025 (quand Node.js 24 devient LTS)

**Actions à effectuer :**
1. Mettre à jour `docker/node/Dockerfile` :
   ```dockerfile
   FROM node:24-alpine
   ```

2. Mettre à jour le script de surveillance :
   ```bash
   # Dans scripts/update-custom-images.sh
   "node:24-alpine"
   ```

3. Tester la compatibilité :
   ```bash
   make rebuild-all-images
   make npm-install
   make npm-build
   ```

**Avantages Node.js 24 LTS :**
- Support à long terme jusqu'en 2028
- Performances améliorées
- Nouvelles features ECMAScript
- Corrections de sécurité

### 📅 **Novembre 2025 - PHP 8.5 (Évaluation)**

**Date de sortie :** 20 novembre 2025

**Actions d'évaluation :**
1. Vérifier la compatibilité Laravel 12/13
2. Tester les extensions PHP requises
3. Évaluer les breaking changes
4. Décider de la migration (probablement 2026)

**Status :** 🔍 **Évaluation requise**

## 🛡️ Stratégie de Migration

### **Principe de Sécurité**
- ✅ Toujours utiliser les versions LTS en production
- ✅ Attendre 2-3 mois après release LTS pour migration
- ✅ Tester en environnement de dev d'abord
- ✅ Maintenir la compatibilité Laravel

### **Processus de Mise à Jour**
1. **Phase de test** (1 mois avant migration)
2. **Backup complet** de l'environnement
3. **Migration graduelle** (dev → staging → prod)
4. **Tests complets** de régression
5. **Surveillance renforcée** post-migration

## 🔔 Alertes et Rappels

### **Alertes à Configurer**

```bash
# Rappel automatique pour octobre 2025
echo "0 0 15 10 2025 echo 'RAPPEL: Node.js 24 LTS est disponible ! Planifier la migration.' | mail -s 'Node.js 24 LTS' admin@domain.com" | crontab -
```

### **Vérifications Mensuelles**

```bash
# Commande à exécuter chaque mois
make check-image-updates
```

## 📈 Historique des Mises à Jour

| Date | Component | Ancienne Version | Nouvelle Version | Raison |
|------|-----------|------------------|------------------|---------|
| 2025-08-02 | Node.js | 20.x | 22.17.1 LTS | Migration vers LTS actuel |

## 🎯 Objectifs Long Terme

### **2025**
- ✅ Node.js 22 LTS stabilisé
- 🔄 Migration Node.js 24 LTS (octobre)
- 🔍 Évaluation PHP 8.5 (novembre)

### **2026**
- 🎯 PHP 8.5 potentiel (si stable et compatible)
- 🎯 Maintien Node.js 24 LTS
- 🎯 Surveillance nouvelles versions Apache

### **2027**
- 🎯 Préparation migration Node.js 26 LTS
- 🎯 Évaluation PHP 8.6

## 💡 Notes Importantes

- **Node.js 20** : End of Life avril 2026
- **Node.js 22** : End of Life avril 2027
- **Node.js 24** : End of Life avril 2028
- **PHP 8.4** : Support actif jusqu'en novembre 2026

## 🚀 Actions Immédiates

- [x] Node.js 22 LTS installé et fonctionnel
- [x] Script de surveillance mis à jour
- [x] Documentation créée
- [ ] Rappel calendrier pour octobre 2025
- [ ] Formation équipe sur nouvelles features Node.js 22