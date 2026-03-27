# 🎨 Comparaison des Frameworks Frontend pour Laravel (2026)

**Date**: 2026-01-11
**Basé sur**: Recherche exhaustive de l'écosystème Laravel 2026
**Pour**: Skeleton Laravel polyvalent - Construction rapide d'interfaces web

---

## 📊 Vue d'ensemble

Ce guide compare les solutions modernes pour construire rapidement des interfaces web avec Laravel. L'objectif est de vous aider à choisir la meilleure stack selon votre projet et vos compétences.

### TL;DR - Recommandations rapides

| Use Case | Solution recommandée |
|----------|---------------------|
| **Admin Panel / Dashboard** | **Filament PHP** ⭐⭐⭐⭐⭐ |
| **Site public / Marketing** | **Blade + Alpine.js** ⭐⭐⭐⭐⭐ |
| **SaaS Application** | **Livewire + Filament** ou **Inertia + React** ⭐⭐⭐⭐⭐ |
| **MVP Rapide** | **Breeze + Livewire + DaisyUI** ⭐⭐⭐⭐⭐ |
| **App hautement interactive** | **Inertia.js + Vue/React** ⭐⭐⭐⭐⭐ |

---

## 1. Laravel Livewire 🔥

### Qu'est-ce que c'est ?

Framework full-stack pour Laravel qui permet de construire des interfaces dynamiques et réactives en restant en PHP, sans écrire de JavaScript. Livewire rend le développement d'UIs interactives aussi simple que l'écriture de composants PHP classiques.

**Version actuelle**: Livewire 3.x (janvier 2026)

### Architecture

```
User Action (click) → Server (Livewire component) → Response → DOM Update
```

- Chaque interaction envoie une requête au serveur
- Le serveur met à jour l'état et renvoie le HTML modifié
- Alpine.js (inclus) gère les mises à jour DOM côté client

### ✅ Points forts

1. **Zéro JavaScript requis** - Développement 100% en PHP
2. **Courbe d'apprentissage minimale** pour développeurs Laravel
3. **SEO-friendly** - Rendu côté serveur par défaut
4. **Excellente pour les formulaires** - Validation temps réel native
5. **Sécurité intégrée** - Checksums empêchent manipulation client
6. **Réutilisabilité** - Components réutilisables à travers l'app
7. **Support officiel Laravel** - Maintenu par l'équipe Laravel
8. **Écosystème TALL** - S'intègre parfaitement avec Tailwind, Alpine, Laravel

### ❌ Points faibles

1. **Performance à surveiller** - Risque de requêtes excessives si mal utilisé
2. **Requiert optimisation** - Débouncing, lazy loading nécessaires
3. **Connexion serveur obligatoire** - Pas de mode hors ligne
4. **Peut flouter frontend/backend** - Facilite les mauvaises pratiques
5. **Latence perceptible** - Chaque interaction = round-trip serveur

### 🎯 Cas d'usage idéaux

- Développeurs backend voulant éviter JavaScript
- Applications forms-heavy avec validation temps réel
- Admin panels avec interactivité modérée
- Prototypage rapide et MVPs
- Applications nécessitant SEO fort

### 📚 Courbe d'apprentissage

**Facile à Moyen** (⭐⭐⭐⭐)
- Démarrage: 1-2 heures
- Maîtrise des bases: 1-2 jours
- Optimisation production: 1-2 semaines

### ⚡ Performance

**Moyenne** - Comparable à Inertia.js si bien optimisé

**Optimisations requises**:
```php
// ❌ Mauvais - Update à chaque frappe
wire:model="search"

// ✅ Bon - Debounced
wire:model.debounce.500ms="search"

// ✅ Meilleur - Lazy (on blur)
wire:model.lazy="search"
```

### 👥 Communauté

**Très large** - 20K+ stars GitHub, écosystème TALL massif

### 💰 Coût

**Gratuit** et open-source

---

## 2. Filament PHP 🚀

### Qu'est-ce que c'est ?

**Framework d'accélération Laravel** et constructeur d'admin panel basé sur la stack TALL. Ce n'est PAS qu'un simple admin panel - c'est un framework UI complet avec 25+ composants de formulaire, table builders, et système de panels pour développement rapide.

**Version actuelle**: Filament v4 (janvier 2026) - 2-3× plus rapide que v3

### Architecture

```
Filament Resources → Livewire Components → Alpine.js → Tailwind CSS v4
```

Construit AU-DESSUS de Livewire avec optimisations et patterns de production intégrés.

### ✅ Points forts

1. **100% gratuit et open-source** - Pas de frais de licence (contrairement à Nova)
2. **Setup ultra-rapide** - Admin panels en minutes
3. **UI moderne et polie** - Look professionnel SaaS par défaut
4. **25+ composants formulaire** prêts à l'emploi
5. **Hautement customisable** - Peut construire dashboards, CRMs, SaaS complets
6. **Documentation excellente** - Guides clairs et complets
7. **Écosystème de plugins** - Library croissante d'extensions
8. **Performance v4** - 2-3× plus rapide avec partial re-rendering
9. **Multi-panel** - Plusieurs zones admin dans une app
10. **Agnostique data source** - Fonctionne avec Eloquent, APIs, arrays

### ❌ Points faibles

1. **Courbe d'apprentissage** - Plus complexe que Livewire seul
2. **Moins flexible que du custom** - Doit suivre les patterns Filament
3. **Structure opinionée** - Conventions strictes à respecter
4. **Relativement jeune** - Moins mature que Nova/Backpack
5. **Peut être overkill** pour CRUD ultra-simples

### 🎯 Cas d'usage idéaux

- **Admin panels et dashboards** (use case principal)
- **Zones admin SaaS** - Gestion subs, billing, users
- **E-commerce** - Produits, commandes, inventaire
- **CRM** - Gestion clients et relations
- **Outils internes** - RH, inventory management
- **Multi-tenant** - Support natif
- **Prototypage rapide** - Admin fonctionnel en heures

### 📚 Courbe d'apprentissage

**Moyenne** (⭐⭐⭐)
- Démarrage: 2-4 heures
- Maîtrise: 1-2 semaines
- Expertise: 1-2 mois

Requiert comprendre:
- Livewire (fondation)
- Patterns Filament (Resources, Actions, Forms, Tables)
- Customisation avancée

### ⚡ Performance

**Moyenne-Basse** - v4 apporte 2-3× amélioration

- Optimisations Livewire intégrées
- Lazy loading natif pour datasets larges
- Partial component re-rendering (v4)
- Pagination et caching intelligents

### 👥 Communauté

**Large et en croissance rapide**
- Un des packages Laravel à plus forte croissance
- Discord actif avec 15K+ membres
- Écosystème de plugins riche
- Updates régulières de l'équipe core

### 💰 Coût

**Gratuit** et open-source

**Comparaison coûts admin panels**:
- **Filament**: $0
- **Laravel Nova**: $99-$299/projet
- **Backpack**: $49-$449/projet

---

## 3. Laravel Jetstream ✈️

### Qu'est-ce que c'est ?

Starter kit Laravel complet avec auth avancée (2FA, teams, session management, API tokens). Propose choix entre stacks Livewire ou Inertia.js (Vue).

**Version actuelle**: Jetstream v5.x

### ✅ Points forts

- **Produit officiel Laravel** - Support long-terme garanti
- **Features-rich** - 2FA, teams, API tokens inclus
- **Production-ready** - Patterns officiels Laravel
- **Choix de stack** - Livewire ou Inertia + Vue
- **Tailwind CSS** intégré

### ❌ Points faibles

- **Complexe pour débutants** - Beaucoup de concepts
- **Heavy** - Beaucoup de code à comprendre/supprimer
- **Features superflues** - Teams management pas toujours nécessaire
- **Moins flexible** - Utilise Fortify en sous-couche

### 🎯 Cas d'usage idéaux

- SaaS avec gestion d'équipes
- Apps nécessitant API tokens + Sanctum
- Projets avec 2FA obligatoire
- Équipes voulant patterns Laravel officiels

### 📚 Courbe d'apprentissage

**Moyenne à Difficile** (⭐⭐)
- Laravel recommande Breeze en premier pour apprendre

### 💰 Coût

**Gratuit** et open-source

---

## 4. Laravel Breeze 🍃

### Qu'est-ce que c'est ?

Implémentation minimale et simple des fonctionnalités d'authentification Laravel. Alternative ultra-légère à Jetstream. Publie tout le code dans votre app pour contrôle total.

**Stacks disponibles**: Blade, Livewire, Inertia + Vue, Inertia + React

### ✅ Points forts

- **Ultra-léger** - Dépendances et code minimaux
- **Setup rapide** - Auth en 5 minutes
- **Contrôle total** - Code publié et modifiable
- **Multiple stacks** - Blade, Livewire, Inertia (Vue/React)
- **Beginner-friendly** - Simple à comprendre
- **Pas de magie** - Controllers directs, facile debug
- **Recommandation officielle** pour débuter

### ❌ Points faibles

- **Features basiques** - Juste auth, pas de teams/2FA/API
- **Travail manuel** - Features avancées à développer soi-même
- **Pas un admin panel** - Juste scaffolding auth

### 🎯 Cas d'usage idéaux

- Apprentissage Laravel
- Petits projets sans auth complexe
- Builds custom nécessitant contrôle total
- Base pour construire son propre admin

### 📚 Courbe d'apprentissage

**Facile** (⭐⭐⭐⭐⭐)
- Parfait pour débutants Laravel

### 💰 Coût

**Gratuit** et open-source

---

## 5. Inertia.js (Vue/React) ⚡

### Qu'est-ce que c'est ?

Approche moderne pour construire SPAs server-driven. Colle entre Laravel et frameworks JavaScript modernes, permettant de construire SPAs sans API. UI updates côté client.

### Architecture

```
Laravel Routes → Inertia → React/Vue Components → Client-side Rendering
```

### ✅ Points forts

- **Expérience SPA moderne** - Interactions fluides côté client
- **Pas d'API requise** - Integration directe routes Laravel
- **Écosystèmes JS riches** - Accès à React/Vue libraries
- **TypeScript** - Type safety end-to-end possible
- **Rendering client-side** - Interactions plus rapides après chargement initial
- **Offline-capable** - Plus de logique client possible
- **Support officiel Laravel**

### ❌ Points faibles

- **JavaScript requis** - Doit connaître Vue ou React
- **Setup complexe** - Build process, bundler, etc.
- **SEO challenges** - SSR nécessaire pour SEO optimal
- **Dev plus lent** initialement pour backend devs
- **Deux écosystèmes** - Laravel + framework JS à gérer

### 🎯 Cas d'usage idéaux

- Full-stack devs à l'aise avec React/Vue
- Applications SPA hautement interactives
- Équipes avec expertise frontend
- UIs complexes (dashboards temps réel)
- Projets TypeScript
- Grandes entreprises standardisées sur React/Vue

### 📚 Courbe d'apprentissage

**Moyenne à Difficile** (⭐⭐)
- Requiert Laravel ET React/Vue
- Build tooling, state management, Inertia concepts

### ⚡ Performance

**Basse à Moyenne**
- Client-side rendering = interactions rapides
- Initial load inclut JS bundle
- Meilleure performance perçue pour UIs très interactives

### 💰 Coût

**Gratuit** et open-source

---

## 6. Blade + Alpine.js 🏔️

### Qu'est-ce que c'est ?

Templating engine Laravel par défaut (Blade) + Alpine.js pour interactivité légère côté client. Alpine.js est un framework JS minimal (15KB) avec réactivité via attributs HTML.

### ✅ Points forts

- **Footprint minimal** - Alpine.js = 15KB
- **Apprentissage facile** - Attributs HTML familiers
- **Pas de build process** - Drop-in dans les pages
- **Contrôle total** - Accès direct DOM
- **Parfait pour "sprinkles"** - Dropdowns, modals, tabs
- **SEO-friendly** - Server-rendered par défaut
- **Chargement rapide**

### ❌ Points faibles

- **AJAX manuel** - fetch/axios à la main
- **Plus de boilerplate** que Livewire
- **Limité pour interactions complexes**
- **Mix PHP/JavaScript** - Context switching

### 🎯 Cas d'usage idéaux

- Apps server-rendered traditionnelles
- Interactivité simple (dropdowns, modals)
- Sites marketing
- Apps existantes Blade à moderniser
- Devs préférant approche traditionnelle

### 📚 Courbe d'apprentissage

**Facile** (⭐⭐⭐⭐⭐)

### ⚡ Performance

**Très Basse** - JS minimal, HTML server-rendered

### 💰 Coût

**Gratuit** et open-source

---

## 7. Bibliothèques de Composants UI

### Tailwind UI (Payant)

**Prix**: $299-$599 one-time

**Points forts**:
- 500+ composants professionnels
- Créé par équipe Tailwind CSS
- Versions React, Vue, HTML
- Copy-paste ready

**Points faibles**:
- Coûteux
- Juste des composants, pas de framework

### DaisyUI (Gratuit) ⭐

**Prix**: $0

**Points forts**:
- 63+ composants CSS purs
- 35+ thèmes built-in
- Classes sémantiques (`btn`, `card`, `modal`)
- **Mary UI** - Composants Blade pour Livewire 3 basés sur DaisyUI
- Intégration Laravel parfaite
- Zero JavaScript pour styling

**Points faibles**:
- CSS seulement, Alpine/Livewire pour comportements
- Moins de composants que Tailwind UI

### Recommandation

**DaisyUI + Mary UI** pour Laravel skeleton:
```bash
npm install -D daisyui@latest
composer require robsontenorio/mary
```

Pourquoi:
- ✅ Gratuit
- ✅ Composants Blade Livewire prêts (Mary UI)
- ✅ Gain de temps énorme
- ✅ Look professionnel par défaut
- ✅ 35+ thèmes pour customisation rapide

---

## 8. Autres solutions notables

### Laravel Nova (Admin Panel - Payant)

**Prix**: $99-$299/projet

**Points forts**:
- Officiel Laravel
- Enterprise-ready
- Vue.js moderne
- Support garanti

**Points faibles**:
- Coûteux
- Moins flexible que Filament

**Quand choisir**: Budget disponible + besoin support officiel

### Laravel Backpack (Admin Panel - Payant)

**Prix**: $49-$449/projet

**Points forts**:
- 10+ ans de maturité
- Très flexible
- Large library widgets

**Points faibles**:
- Complexe
- Payant

**Quand choisir**: Customisations profondes nécessaires

### Laravel Orchid (Admin Panel - Gratuit)

Alternative gratuite à Filament avec approche platform.

**Quand choisir**: Alternative gratuite voulue mais communauté plus petite

---

## 📊 Matrice de décision complète

### Admin Panels / Dashboards

| Solution | Note | Coût | Rapidité | Flexibilité |
|----------|------|------|----------|-------------|
| **Filament** | ⭐⭐⭐⭐⭐ | $0 | ⚡⚡⚡⚡⚡ | ⭐⭐⭐⭐ |
| Nova | ⭐⭐⭐⭐ | $99+ | ⚡⚡⚡⭐ | ⭐⭐⭐ |
| Backpack | ⭐⭐⭐⭐ | $49+ | ⚡⚡⚡ | ⭐⭐⭐⭐⭐ |
| Livewire custom | ⭐⭐⭐ | $0 | ⚡⚡ | ⭐⭐⭐⭐⭐ |

**Gagnant**: **Filament PHP** - Gratuit, rapide, moderne

### Sites Publics / Marketing

| Solution | Note | SEO | Performance | Simplicité |
|----------|------|-----|-------------|------------|
| **Blade + Alpine** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Livewire | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| Inertia | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ |

**Gagnant**: **Blade + Alpine.js** - SEO parfait, rapide, simple

### Applications SaaS

| Solution | Note | Interactivité | Type Safety | Écosystème |
|----------|------|---------------|-------------|------------|
| **Inertia + React** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Livewire + Filament** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| Jetstream | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |

**Gagnant**: **Inertia + React** (frontend team) OU **Livewire + Filament** (backend team)

### MVPs / Prototypage Rapide

| Solution | Note | Vitesse Setup | Coût | Look Pro |
|----------|------|---------------|------|----------|
| **Filament** | ⭐⭐⭐⭐⭐ | ⚡⚡⚡⚡⚡ | $0 | ⭐⭐⭐⭐⭐ |
| **Breeze + Livewire + DaisyUI** | ⭐⭐⭐⭐⭐ | ⚡⚡⚡⚡⭐ | $0 | ⭐⭐⭐⭐ |
| Jetstream | ⭐⭐⭐ | ⚡⚡⭐ | $0 | ⭐⭐⭐⭐ |

**Gagnant**: **Filament** (admin) + **Breeze + Livewire + DaisyUI** (frontend)

### Applications Hautement Interactives

| Solution | Note | Réactivité | Offline | Performance |
|----------|------|------------|---------|-------------|
| **Inertia + Vue/React** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Livewire + Alpine | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐ |
| Blade + Alpine | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ |

**Gagnant**: **Inertia.js + Vue/React**

---

## 🎯 Recommandation pour votre Skeleton Laravel

### Stack Recommandée: **TALL + Filament + Breeze + DaisyUI**

```
✅ Laravel 12 (déjà installé)
✅ Breeze avec Livewire (auth scaffolding)
✅ Livewire 3 (composants réactifs)
✅ Alpine.js (interactivité client-side)
✅ Tailwind CSS v4 (styling utility)
✅ DaisyUI + Mary UI (composants gratuits)
✅ Filament v4 (admin panel builder)
```

### Pourquoi cette stack ?

#### 1. **Flexibilité maximale**
- Peut fork pour admin panels (Filament)
- Peut fork pour sites publics (Blade + Alpine)
- Peut fork pour SaaS (Livewire + Filament)

#### 2. **100% Gratuit**
- Aucun coût de licence
- Pas de lock-in commercial

#### 3. **Développement rapide**
- Admin panels en minutes (Filament)
- Auth prête en 5 min (Breeze)
- Composants UI gratuits (DaisyUI/Mary)

#### 4. **Moderne et Maintenu**
- Stack TALL = standard Laravel 2026
- Toutes les technos activement maintenues
- Support communauté massif

#### 5. **Courbe apprentissage raisonnable**
- Principalement PHP (Livewire)
- JavaScript minimal (Alpine.js)
- Excellente documentation partout

#### 6. **Production-ready**
- Patterns optimisés intégrés
- Filament v4 haute performance
- Scaling éprouvé

### Installation

```bash
cd src

# 1. Breeze avec Livewire
composer require laravel/breeze --dev
php artisan breeze:install livewire
npm install && npm run build

# 2. Filament v4
composer require filament/filament:"^4.0"
php artisan filament:install --panels

# 3. DaisyUI
npm install -D daisyui@latest

# Configure tailwind.config.js:
# plugins: [require('daisyui')]

# 4. Mary UI (optionnel - composants Blade Livewire)
composer require robsontenorio/mary
```

### Structure projet recommandée

```
src/
├── app/
│   ├── Filament/          # Admin panel Filament
│   │   ├── Resources/
│   │   └── Pages/
│   ├── Livewire/          # Composants Livewire publics
│   │   ├── Auth/          # Auth components (Breeze)
│   │   ├── Dashboard/
│   │   └── Public/
│   └── Http/
│       └── Controllers/   # Controllers traditionnels si besoin
├── resources/
│   └── views/
│       ├── livewire/      # Vues Livewire
│       ├── components/    # Blade components
│       └── layouts/       # Layouts (Breeze)
```

---

## 🔄 Stratégie Alternative: Deux Branches

Pour maximum flexibilité, créer **deux branches principales**:

### Option A: Branch `main-livewire` (Backend-focused)
```
- Breeze Livewire
- Livewire 3
- Filament v4
- DaisyUI + Mary UI
```

**Pour**: Équipes backend, développement rapide, PHP-only

### Option B: Branch `main-inertia` (Frontend-focused)
```
- Breeze Inertia + React
- TypeScript
- Filament v4 (admin toujours utile)
- shadcn/ui ou Radix
```

**Pour**: Équipes frontend, apps interactives, TypeScript lovers

### Quand forker

```bash
# Backend team project
git checkout main-livewire
git checkout -b project-name

# Frontend team project
git checkout main-inertia
git checkout -b project-name
```

---

## 📈 Tendances 2026

### Ce qui monte

1. **Filament PHP** - Croissance explosive, remplace Nova pour beaucoup
2. **Livewire 3** - Adoption massive dans écosystème Laravel
3. **DaisyUI** - Devient standard pour composants Tailwind gratuits
4. **Mary UI** - Composants Blade Livewire populaires
5. **Inertia.js** - De plus en plus adopté pour SPAs

### Ce qui descend

1. **Laravel Nova** - Filament gratuit grignote parts de marché
2. **Vue Options API** - Composition API standard maintenant
3. **Bootstrap** - Tailwind domine largement
4. **jQuery** - Quasi-disparu sauf legacy

### Stack "TALL" devient le standard

**TALL Stack = Laravel standard 2026**:
- **T**ailwind CSS
- **A**lpine.js
- **L**aravel
- **L**ivewire

---

## 🎓 Courbes d'apprentissage comparées

**Temps pour créer une app CRUD fonctionnelle avec auth:**

| Stack | Débutant | Intermédiaire | Expert |
|-------|----------|---------------|--------|
| Breeze + Blade | 4-6h | 2-3h | 1h |
| Breeze + Livewire | 6-8h | 3-4h | 1-2h |
| Filament | 8-12h | 4-6h | 1-2h |
| Jetstream | 12-16h | 6-8h | 2-3h |
| Inertia + Vue | 16-20h | 8-12h | 3-4h |

**Temps pour maîtriser la stack:**

| Stack | Compétence fonctionnelle | Expertise |
|-------|-------------------------|-----------|
| Blade + Alpine | 1-2 jours | 1-2 semaines |
| Livewire | 3-5 jours | 2-4 semaines |
| Filament | 1-2 semaines | 1-2 mois |
| Inertia + React | 2-4 semaines | 2-3 mois |

---

## 💰 Analyse coûts (projet 5 ans)

### Stack gratuite (TALL + Filament)
- **Licences**: $0
- **Maintenance**: Basse (Laravel ecosystem)
- **Hosting**: Standard Laravel ($20-50/mois)
- **Total 5 ans**: ~$1,200-3,000 (hosting uniquement)

### Stack avec Nova
- **Licence Nova**: $299/projet
- **Mises à jour**: Gratuites à vie
- **Hosting**: Standard ($20-50/mois)
- **Total 5 ans**: ~$1,500-3,300

### Stack Inertia + React + Vercel
- **Licences**: $0
- **Hosting Laravel**: $20-50/mois
- **Vercel/Netlify**: $0-20/mois
- **Total 5 ans**: ~$1,200-4,200

**Conclusion**: Stack TALL gratuite = économies significatives sans compromis qualité

---

## ✅ Checklist de décision

Utilisez cette checklist pour choisir:

### Votre équipe

- [ ] Équipe backend pure → **Livewire + Filament**
- [ ] Équipe frontend forte → **Inertia + React/Vue**
- [ ] Équipe mixte → **Livewire** (plus accessible)
- [ ] Solo dev → **Livewire + Filament** (moins de contexte switching)

### Votre projet

- [ ] Admin panel principal → **Filament**
- [ ] Site public → **Blade + Alpine** ou **Livewire**
- [ ] SaaS → **Livewire + Filament** ou **Inertia + React**
- [ ] MVP rapide → **Filament + Breeze + DaisyUI**
- [ ] App mobile + web → **Laravel API** + **React Native/Flutter**

### Vos priorités

- [ ] Vitesse développement → **Filament**
- [ ] SEO critique → **Blade + Alpine** ou **Livewire**
- [ ] Interactivité riche → **Inertia + React**
- [ ] Budget serré → **Stack TALL gratuite**
- [ ] Type safety → **Inertia + TypeScript**

### Vos compétences

- [ ] Maîtrise PHP, peu JavaScript → **Livewire**
- [ ] Maîtrise React/Vue → **Inertia**
- [ ] Débutant Laravel → **Breeze + Blade**
- [ ] Full-stack expérimenté → **Choix libre**

---

## 🚀 Plan d'implémentation pour le Skeleton

### Phase 1: Installation de base (Maintenant)

```bash
# Déjà fait
✅ Laravel 12
✅ Tailwind CSS

# À ajouter
make install-frontend-stack
```

### Phase 2: Ajout Breeze + Livewire (15 min)

```bash
cd src
composer require laravel/breeze --dev
php artisan breeze:install livewire
npm install && npm run build
```

### Phase 3: Ajout Filament (10 min)

```bash
composer require filament/filament:"^4.0"
php artisan filament:install --panels
php artisan make:filament-user
```

### Phase 4: Ajout DaisyUI + Mary (10 min)

```bash
npm install -D daisyui@latest
composer require robsontenorio/mary

# Configurer tailwind.config.js
# Publier Mary UI
php artisan mary:install
```

### Phase 5: Documentation et exemples (2h)

- [ ] Créer exemples Livewire components
- [ ] Créer exemple Filament Resource
- [ ] Documenter patterns recommandés
- [ ] Créer templates réutilisables

---

## 📚 Ressources et liens

### Documentation officielle

- **Livewire**: https://livewire.laravel.com
- **Filament**: https://filamentphp.com
- **Alpine.js**: https://alpinejs.dev
- **Inertia.js**: https://inertiajs.com
- **Breeze**: https://laravel.com/docs/starter-kits#breeze
- **DaisyUI**: https://daisyui.com
- **Mary UI**: https://mary-ui.com

### Tutoriels recommandés

- **TALL Stack**: https://tallstack.dev
- **Laracasts Livewire**: https://laracasts.com/series/livewire-uncovered
- **Filament Daily**: https://www.youtube.com/@FilamentDaily

### Communautés

- **Filament Discord**: https://discord.gg/filamentphp
- **Laravel Discord**: https://discord.gg/laravel
- **TALL Stack**: https://github.com/livewire/livewire/discussions

---

**Dernière mise à jour**: 2026-01-11
**Maintenu par**: L'équipe Laravel Skeleton
**Feedback**: Créez une issue GitHub avec vos retours
