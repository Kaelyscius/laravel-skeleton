# 🗓️ Roadmap des Versions Docker

Ce document planifie les mises à jour futures des images Docker base.

## 📊 État Actuel (Mars 2026)

| Component | Version Actuelle | LTS / Stable | EOL | Status |
|-----------|------------------|--------------|-----|--------|
| **PHP** | 8.5.3 (FPM Alpine) | Stable | Nov 2027 | ✅ Actuel |
| **Node.js** | 24 LTS (Alpine) | LTS actif | Avr 2028 | ✅ Actuel |
| **Apache** | 2.4 Alpine | Stable | — | ✅ Actuel |
| **PostgreSQL** | 17 (Alpine) | Stable | Nov 2029 | ✅ Actuel |
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

### 📅 **2027 - PostgreSQL 17 → 18 (Évaluation)**

**Date de sortie prévue :** Septembre 2027

**Actions à effectuer :**
1. Vérifier compat Laravel pgsql driver
2. Tester migrations + RLS policies (acté en v2+ multi-tenant SaaS)
3. Évaluer breaking changes (rare en Postgres)
4. Décider migration après 6+ mois post-release

**Status :** 🔮 Planifié

---

### 📅 **2026 - Node.js 26 LTS**

**Date cible :** fin 2026 / début 2027.

Node.js 26 devient LTS le **2026-10-28** (et non octobre 2027 — erreur corrigée le
2026-07-27 après vérification du calendrier officiel `nodejs/Release`). Node 24
quitte l'Active LTS le **2026-10-20** : les deux dates se croisent, c'est la
fenêtre de migration naturelle. En appliquant le principe « attendre 2-3 mois
après la release LTS » ci-dessous, la bascule se fait donc vers janvier 2027.

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
| 2026-05-08 | DB Engine | MariaDB 11.8 LTS | PostgreSQL 17 (Alpine) | Switch SaaS-ready : RLS native + JSONB + full-text FR. ADR-0001 |
| 2026-03-28 | Redis | `alpine` (non pinnée) | 7.4-alpine | Version explicite |
| 2026-03-28 | MailHog | mailhog/mailhog | axllent/mailpit | MailHog abandonné 2023 |

## 🎯 Objectifs Long Terme

### **2026**
- ✅ PHP 8.5 en production
- ✅ Node.js 24 LTS actif
- ✅ PostgreSQL 17
- 🔍 Évaluation PHP 8.6 (novembre)
- 🔍 Surveillance PostgreSQL 18

### **2027**
- 🎯 Préparation migration Node.js 26 LTS
- 🎯 Évaluation PHP 8.6 (si stable et compatible)

### **2028**
- 🎯 Évaluation PostgreSQL 18 (si stable et compatible)

## 💡 Versions et EOL de Référence

| Composant | Version | EOL |
|-----------|---------|-----|
| Node.js 24 LTS | Active LTS jusqu'au 20 oct. 2026, puis maintenance | Avr 2028 |
| Node.js 22 LTS | Maintenance (depuis oct. 2025) | Avr 2027 |
| PHP 8.5 | Actif | Nov 2027 |
| PHP 8.4 | Actif | Nov 2026 |
| PostgreSQL 17 | Stable actuel | Nov 2029 |
| PostgreSQL 16 | Stable supporté | Nov 2028 |
| PostgreSQL 15 | Stable supporté | Nov 2027 |
