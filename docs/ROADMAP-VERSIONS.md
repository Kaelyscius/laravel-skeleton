# 🗓️ Roadmap des Versions Docker

Ce document planifie les mises à jour futures des images Docker base.

## 📊 État Actuel (Mars 2026)

| Component | Version Actuelle | LTS / Stable | EOL | Status |
|-----------|------------------|--------------|-----|--------|
| **PHP** | 8.5.3 (FPM Alpine) | Stable | Nov 2027 | ✅ Actuel |
| **Node.js** | 24 LTS (Alpine) | LTS actif | Avr 2028 | ✅ Actuel |
| **Apache** | 2.4 Alpine | Stable | — | ✅ Actuel |
| **MariaDB** | 11.8 LTS | LTS 2025 | Juin 2028 | ✅ Actuel |
| **Redis** | 7.4 Alpine | Stable | — | ✅ Actuel |

## 🎯 Calendrier des Mises à Jour Planifiées

### 📅 **2026 - PHP 8.6 (Évaluation)**

**Date de sortie prévue :** Novembre 2026

**Actions à effectuer :**
1. Vérifier la compatibilité Laravel 12/13
2. Tester les extensions PECL (redis, apcu, imagick, xdebug)
3. Évaluer les breaking changes
4. Décider de la migration après 2-3 mois post-release

**Status :** 🔍 À surveiller

---

### 📅 **2026 - MariaDB 11.8 → 12.x (Évaluation)**

**Condition :** Quand MariaDB 12.x atteint le statut LTS

**Status :** 🔍 MariaDB 12.2 rolling disponible — attendre LTS

---

### 📅 **2027 - Node.js 26 LTS**

**Date cible :** Octobre 2027 (quand Node.js 26 devient LTS)

**Status :** 🔮 Planifié

## 🛡️ Stratégie de Migration

### **Principe de Sécurité**
- ✅ Toujours utiliser les versions LTS en production
- ✅ Attendre 2-3 mois après release LTS pour migration
- ✅ Tester en environnement de dev d'abord
- ✅ Maintenir la compatibilité Laravel
- ✅ Toujours pinner les versions (jamais `latest` ni `alpine` sans version)

### **Processus de Mise à Jour**
1. **Phase de test** (1 mois avant migration)
2. **Backup complet** de l'environnement
3. **Migration graduelle** (dev → staging → prod)
4. **Tests complets** de régression
5. **Surveillance renforcée** post-migration

## 📈 Historique des Mises à Jour

| Date | Component | Ancienne Version | Nouvelle Version | Raison |
|------|-----------|------------------|------------------|---------|
| 2025-08-02 | Node.js | 20.x | 24 | Migration vers LTS actuel |
| 2025-11-xx | PHP | 8.4 | 8.5.1 | Nouvelle version stable |
| 2026-03-28 | MariaDB | `latest` (12.2 rolling) | 11.8 LTS | Stabilité + LTS actuel |
| 2026-03-28 | Redis | `alpine` (non pinnée) | 7.4-alpine | Version explicite |
| 2026-03-28 | MailHog | mailhog/mailhog | axllent/mailpit | MailHog abandonné 2023 |

## 🎯 Objectifs Long Terme

### **2026**
- ✅ PHP 8.5 en production
- ✅ Node.js 24 LTS actif
- ✅ MariaDB 11.8 LTS
- 🔍 Évaluation PHP 8.6 (novembre)
- 🔍 Surveillance MariaDB 12 LTS

### **2027**
- 🎯 Préparation migration Node.js 26 LTS
- 🎯 Évaluation PHP 8.6 (si stable et compatible)

### **2028**
- 🎯 Migration MariaDB avant EOL 11.8 (juin 2028)

## 💡 Versions et EOL de Référence

| Composant | Version | EOL |
|-----------|---------|-----|
| Node.js 24 LTS | LTS actif | Avr 2028 |
| Node.js 22 LTS | LTS actif | Avr 2027 |
| PHP 8.5 | Actif | Nov 2027 |
| PHP 8.4 | Actif | Nov 2026 |
| MariaDB 11.8 LTS | LTS actuel | Juin 2028 |
| MariaDB 11.4 LTS | Supporté | Mai 2029 |
| MariaDB 10.6 LTS | ⚠️ EOL proche | Juil 2026 |
