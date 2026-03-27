# 📦 Packages Laravel Recommandés

Documentation complète des packages Laravel utiles pour Laravel 12 + PHP 8.5.1

---

## 📊 Index par Catégorie

- [🔧 Développement (Must-Have)](#-développement-must-have)
- [🚀 Production (Must-Have)](#-production-must-have)
- [🌐 API Development (Must-Have)](#-api-development-must-have)
- [✨ Features Avancées (Nice-to-Have)](#-features-avancées-nice-to-have)
- [🧪 Outils de Test](#-outils-de-test)
- [🔒 Sécurité Supplémentaire](#-sécurité-supplémentaire)
- [📊 Monitoring & Performance](#-monitoring--performance)
- [🎨 Frontend & UI](#-frontend--ui)
- [📧 Email & Notifications](#-email--notifications)
- [🗄️ Base de Données](#️-base-de-données)
- [🌍 Internationalisation](#-internationalisation)

---

## 🔧 Développement (Must-Have)

### 1. **barryvdh/laravel-ide-helper** ⭐⭐⭐⭐⭐

**Statut**: ✅ DÉJÀ INSTALLÉ dans ton projet

**Description**: Génère des fichiers d'aide pour l'autocomplétion IDE (PhpStorm, VSCode)

**Pourquoi c'est essentiel**:
- Autocomplétion parfaite des facades Laravel
- Documentation inline des méthodes
- Évite les erreurs de typage
- Indispensable pour PhpStorm (ton setup)

**Installation**:
```bash
composer require --dev barryvdh/laravel-ide-helper
```

**Configuration**:
```bash
# Générer les helpers
php artisan ide-helper:generate
php artisan ide-helper:models
php artisan ide-helper:meta

# Ou via Makefile
make artisan cmd="ide-helper:generate"
```

**Usage avec ton setup**:
- ✅ Déjà dans composer.json scripts
- Compatible WSL + PhpStorm Windows
- Regénérer après ajout de modèles

**Compatibilité**: ✅ Laravel 12 ✅ PHP 8.5+

---

### 2. **spatie/laravel-ray** ⭐⭐⭐⭐

**Description**: Outil de debugging visuel (alternative à dump/dd)

**Pourquoi utile pour toi**:
- Debugging sans casser l'exécution
- Interface visuelle séparée
- Timeline de debug
- Inspecter requêtes, queries, mails

**Installation**:
```bash
composer require --dev spatie/laravel-ray
```

**Avantages vs dd()**:
```php
// Avant
dd($user); // Stoppe l'exécution

// Avec Ray
ray($user); // Continue l'exécution, affiche dans Ray
ray($user)->red(); // Coloré
ray()->showQueries(); // Affiche toutes les queries
```

**Note**: Nécessite l'app Ray Desktop (payante après 30j trial)

**Alternative gratuite**: Laravel Telescope (déjà installé ✅)

**Recommandation**: ⚠️ Optionnel - Telescope fait déjà le job gratuitement

**Compatibilité**: ✅ Laravel 12 ✅ PHP 8.5+

---

## 🚀 Production (Must-Have)

### 3. **spatie/laravel-backup** ⭐⭐⭐⭐⭐

**Description**: Backup automatique base de données + fichiers

**Pourquoi ESSENTIEL pour production**:
- Backup automatique DB + storage/
- Support S3, Google Drive, Dropbox
- Cleanup automatique vieux backups
- Notifications si échec

**Installation**:
```bash
composer require spatie/laravel-backup
php artisan vendor:publish --provider="Spatie\Backup\BackupServiceProvider"
```

**Configuration**:
```php
// config/backup.php
'destination' => [
    'disks' => ['s3'], // ou 'local'
],
'cleanup' => [
    'keep_all_backups_for_days' => 7,
    'keep_daily_backups_for_days' => 16,
],
```

**Usage**:
```bash
php artisan backup:run
php artisan backup:clean
php artisan backup:list

# Programmer via cron
php artisan backup:run --only-db --quiet
```

**Intégration recommandée**:
```bash
# Makefile
.PHONY: backup
backup: ## Backup complet DB + fichiers
	php artisan backup:run
```

**Recommandation**: 🔴 **CRITIQUE pour production**

**Compatibilité**: ✅ Laravel 12 ✅ PHP 8.5+

---

### 4. **sentry/sentry-laravel** ⭐⭐⭐⭐⭐

**Description**: Error tracking & monitoring (Sentry.io)

**Pourquoi ESSENTIEL**:
- Suivi erreurs production temps réel
- Stack traces détaillées
- Notifications erreurs
- Performance monitoring
- Free tier: 5000 events/mois

**Installation**:
```bash
composer require sentry/sentry-laravel
php artisan vendor:publish --provider="Sentry\Laravel\ServiceProvider"
```

**Configuration .env**:
```bash
SENTRY_LARAVEL_DSN=https://your-key@sentry.io/project-id
SENTRY_TRACES_SAMPLE_RATE=1.0
```

**Avantages**:
- Voir toutes les erreurs en prod
- Context utilisateur automatique
- Breadcrumbs (actions avant erreur)
- Intégration GitHub/Slack

**Alternative**: Laravel Flare (payant)

**Recommandation**: 🟢 **HAUTEMENT RECOMMANDÉ pour production**

**Compatibilité**: ✅ Laravel 12 ✅ PHP 8.5+

---

### 5. **spatie/laravel-responsecache** ⭐⭐⭐⭐

**Description**: Cache automatique des réponses HTTP

**Pourquoi utile**:
- Cache transparent des pages
- Boost performance jusqu'à 10x
- Invalide automatiquement
- Tags pour purge sélective

**Installation**:
```bash
composer require spatie/laravel-responsecache
php artisan vendor:publish --provider="Spatie\ResponseCache\ResponseCacheServiceProvider"
```

**Usage**:
```php
// Cache automatique
Route::get('/posts', PostController::class)->middleware('cacheResponse');

// Ou global dans Kernel
protected $middlewareGroups = [
    'web' => [
        \Spatie\ResponseCache\Middlewares\CacheResponse::class,
    ],
];
```

**Note**: Déjà Redis ✅ dans ton setup, parfait pour ce package

**Recommandation**: 🟢 **RECOMMANDÉ si site à fort trafic**

**Compatibilité**: ✅ Laravel 12 ✅ PHP 8.5+

---

## 🌐 API Development (Must-Have)

### 6. **spatie/laravel-query-builder** ⭐⭐⭐⭐⭐

**Description**: API filtering, sorting, includes automatiques

**Pourquoi ESSENTIEL pour API**:
- Filtering: `?filter[name]=John`
- Sorting: `?sort=-created_at`
- Includes: `?include=posts,comments`
- Standardisé (JSON:API style)

**Installation**:
```bash
composer require spatie/laravel-query-builder
```

**Exemple**:
```php
use Spatie\QueryBuilder\QueryBuilder;

// Controller
public function index()
{
    return QueryBuilder::for(User::class)
        ->allowedFilters(['name', 'email'])
        ->allowedSorts(['name', 'created_at'])
        ->allowedIncludes(['posts', 'comments'])
        ->get();
}

// URL: /users?filter[name]=John&sort=-created_at&include=posts
```

**Recommandation**: 🟢 **ESSENTIEL si tu fais une API REST**

**Compatibilité**: ✅ Laravel 12 ✅ PHP 8.5+

---

### 7. **darkaonline/l5-swagger** ⭐⭐⭐⭐

**Description**: Documentation API automatique (OpenAPI/Swagger)

**Pourquoi utile**:
- Docs API auto-générées
- Interface Swagger UI
- Annotations PHP → OpenAPI spec
- Testable directement

**Installation**:
```bash
composer require darkaonline/l5-swagger
php artisan vendor:publish --provider "L5Swagger\L5SwaggerServiceProvider"
```

**Usage**:
```php
/**
 * @OA\Get(
 *     path="/api/users",
 *     summary="List users",
 *     @OA\Response(response="200", description="Success")
 * )
 */
public function index() { }
```

**Accès**: `http://localhost/api/documentation`

**Alternative**: Scramble (plus moderne, Laravel-first)

**Recommandation**: 🟢 **RECOMMANDÉ pour API publique/équipe**

**Compatibilité**: ✅ Laravel 12 ✅ PHP 8.5+

---

## ✨ Features Avancées (Nice-to-Have)

### 8. **spatie/laravel-medialibrary** ⭐⭐⭐⭐⭐

**Description**: Gestion fichiers/images avec transformations

**Pourquoi utile**:
- Upload fichiers structuré
- Générer thumbnails auto
- Conversions images (WebP, resize)
- Support S3/cloud
- Responsive images

**Installation**:
```bash
composer require spatie/laravel-medialibrary
php artisan vendor:publish --provider="Spatie\MediaLibrary\MediaLibraryServiceProvider"
php artisan migrate
```

**Usage**:
```php
// Model
class Post extends Model implements HasMedia
{
    use InteractsWithMedia;

    public function registerMediaConversions()
    {
        $this->addMediaConversion('thumb')
            ->width(200)
            ->height(200);
    }
}

// Upload
$post->addMedia($request->file('image'))->toMediaCollection('images');

// Récupérer
$post->getFirstMediaUrl('images', 'thumb');
```

**Recommandation**: 🟢 **ESSENTIEL si upload images/fichiers**

**Compatibilité**: ✅ Laravel 12 ✅ PHP 8.5+

---

### 9. **spatie/laravel-settings** ⭐⭐⭐⭐

**Description**: Système de settings persistants

**Pourquoi utile**:
- Settings application DB
- Type-safe (DTO)
- Cache automatique
- Migrations settings

**Installation**:
```bash
composer require spatie/laravel-settings
php artisan vendor:publish --provider="Spatie\LaravelSettings\LaravelSettingsServiceProvider"
php artisan migrate
```

**Usage**:
```php
// Créer settings class
class GeneralSettings extends Settings
{
    public string $site_name;
    public bool $maintenance_mode;
}

// Utiliser
$settings = app(GeneralSettings::class);
echo $settings->site_name;

$settings->site_name = 'New Name';
$settings->save();
```

**Recommandation**: 🟡 **UTILE si beaucoup de settings configurables**

**Compatibilité**: ✅ Laravel 12 ✅ PHP 8.5+

---

### 10. **spatie/laravel-tags** ⭐⭐⭐⭐

**Description**: Système de tags pour modèles

**Pourquoi utile**:
- Tags sur n'importe quel modèle
- Recherche par tags
- Tags avec type/slug
- Multilingue

**Installation**:
```bash
composer require spatie/laravel-tags
php artisan vendor:publish --provider="Spatie\Tags\TagsServiceProvider"
php artisan migrate
```

**Usage**:
```php
$post->attachTag('Laravel');
$post->attachTags(['PHP', 'Tutorial']);

Post::withAnyTags(['Laravel', 'PHP'])->get();
```

**Recommandation**: 🟡 **UTILE si système de tags/catégories**

**Compatibilité**: ✅ Laravel 12 ✅ PHP 8.5+

---

## 🧪 Outils de Test

### 11. **pestphp/pest-plugin-drift** ⭐⭐⭐

**Description**: Détecte code non couvert par tests

**Pourquoi utile**:
- Trouve code sans tests
- Mutation testing
- Améliore couverture

**Installation**:
```bash
composer require pestphp/pest-plugin-drift --dev
```

**Usage**:
```bash
php artisan test --drift
```

**Note**: Pest déjà installé ✅ dans ton projet

**Recommandation**: 🟡 **NICE-TO-HAVE pour qualité maximale**

**Compatibilité**: ✅ Laravel 12 ✅ PHP 8.5+

---

### 12. **nunomaduro/larastan** ⭐⭐⭐⭐⭐

**Statut**: ✅ DÉJÀ INSTALLÉ (via composer.json)

**Description**: PHPStan + règles Laravel

**Ton niveau**: Level 8 (maximum)

**Recommandation**: ✅ **Déjà optimal dans ton setup**

---

## 🔒 Sécurité Supplémentaire

### 13. **pragmarx/google2fa-laravel** ⭐⭐⭐⭐

**Description**: Authentification 2FA (Google Authenticator)

**Installation**:
```bash
composer require pragmarx/google2fa-laravel
```

**Recommandation**: 🟢 **RECOMMANDÉ si données sensibles**

**Compatibilité**: ✅ Laravel 12 ✅ PHP 8.5+

---

### 14. **spatie/laravel-csp** ⭐⭐⭐⭐

**Description**: Content Security Policy headers

**Installation**:
```bash
composer require spatie/laravel-csp
```

**Recommandation**: 🟢 **RECOMMANDÉ pour sécurité XSS**

**Compatibilité**: ✅ Laravel 12 ✅ PHP 8.5+

---

## 📊 Monitoring & Performance

### 15. **spatie/laravel-health** ⭐⭐⭐⭐⭐

**Description**: Health checks application

**Installation**:
```bash
composer require spatie/laravel-health
```

**Checks**: DB, Cache, Queue, Disk space, etc.

**Recommandation**: 🟢 **RECOMMANDÉ pour production**

**Compatibilité**: ✅ Laravel 12 ✅ PHP 8.5+

---

### 16. **spatie/laravel-schedule-monitor** ⭐⭐⭐⭐

**Description**: Monitoring tâches cron

**Installation**:
```bash
composer require spatie/laravel-schedule-monitor
```

**Recommandation**: 🟢 **UTILE si beaucoup de cron jobs**

**Compatibilité**: ✅ Laravel 12 ✅ PHP 8.5+

---

## 🎨 Frontend & UI

### 17. **livewire/livewire** ⭐⭐⭐⭐⭐

**Description**: Framework frontend réactif (alternative à Vue/React)

**Installation**:
```bash
composer require livewire/livewire
```

**Recommandation**: 🟢 **EXCELLENT si pas de SPA complexe**

**Compatibilité**: ✅ Laravel 12 ✅ PHP 8.5+

---

### 18. **inertiajs/inertia-laravel** ⭐⭐⭐⭐⭐

**Description**: SPA sans API (Vue/React + Laravel)

**Installation**:
```bash
composer require inertiajs/inertia-laravel
```

**Recommandation**: 🟢 **PARFAIT pour SPA moderne**

**Compatibilité**: ✅ Laravel 12 ✅ PHP 8.5+

---

### 19. **filamentphp/filament** ⭐⭐⭐⭐⭐

**Description**: Admin panel moderne (TALL stack)

**Installation**:
```bash
composer require filament/filament
```

**Recommandation**: 🟢 **EXCELLENT pour backoffice**

**Compatibilité**: ✅ Laravel 12 ✅ PHP 8.5+

---

## 📧 Email & Notifications

### 20. **spatie/laravel-mail-preview** ⭐⭐⭐⭐

**Description**: Preview emails avant envoi

**Installation**:
```bash
composer require spatie/laravel-mail-preview --dev
```

**Note**: Mailpit est utilisé pour la capture email, ce package ajoute des assertions pratiques dans les tests

**Compatibilité**: ✅ Laravel 12 ✅ PHP 8.5+

---

## 🗄️ Base de Données

### 21. **spatie/laravel-sluggable** ⭐⭐⭐⭐

**Description**: Génération slugs automatique

**Installation**:
```bash
composer require spatie/laravel-sluggable
```

**Compatibilité**: ✅ Laravel 12 ✅ PHP 8.5+

---

### 22. **owen-it/laravel-auditing** ⭐⭐⭐⭐

**Description**: Audit trail (qui a modifié quoi/quand)

**Installation**:
```bash
composer require owen-it/laravel-auditing
```

**Note**: Spatie ActivityLog déjà installé ✅, fait similaire

**Compatibilité**: ✅ Laravel 12 ✅ PHP 8.5+

---

## 🌍 Internationalisation

### 23. **spatie/laravel-translatable** ⭐⭐⭐⭐

**Description**: Modèles multilingues

**Installation**:
```bash
composer require spatie/laravel-translatable
```

**Compatibilité**: ✅ Laravel 12 ✅ PHP 8.5+

---

## 📋 Résumé - Packages Recommandés pour Ton Projet

### 🔴 CRITIQUE (Installer AVANT production)

1. **spatie/laravel-backup** - Backups automatiques
2. **sentry/sentry-laravel** - Error tracking

### 🟢 HAUTEMENT RECOMMANDÉ

3. **spatie/laravel-query-builder** - Si API REST
4. **spatie/laravel-medialibrary** - Si upload fichiers
5. **spatie/laravel-health** - Health checks
6. **filamentphp/filament** - Si besoin backoffice
7. **livewire/livewire** ou **inertiajs/inertia** - Frontend moderne

### 🟡 UTILE SELON BESOINS

8. **spatie/laravel-responsecache** - Si fort trafic
9. **darkaonline/l5-swagger** - Si API documentée
10. **spatie/laravel-csp** - Sécurité XSS
11. **pragmarx/google2fa-laravel** - 2FA
12. **spatie/laravel-tags** - Système tags

### ⚪ OPTIONNEL

13. **spatie/laravel-ray** - Debug visuel (payant)
14. **spatie/laravel-settings** - Settings complexes
15. **pestphp/pest-plugin-drift** - Tests avancés

---

## 🚀 Installation Recommandée

### Étape 1: Production Critical
```bash
composer require spatie/laravel-backup sentry/sentry-laravel
php artisan vendor:publish --provider="Spatie\Backup\BackupServiceProvider"
php artisan vendor:publish --provider="Sentry\Laravel\ServiceProvider"
```

### Étape 2: Si API
```bash
composer require spatie/laravel-query-builder
```

### Étape 3: Si Upload Fichiers
```bash
composer require spatie/laravel-medialibrary
php artisan migrate
```

### Étape 4: Frontend (choisir un)
```bash
# Option 1: Livewire (plus simple)
composer require livewire/livewire

# Option 2: Inertia (SPA)
composer require inertiajs/inertia-laravel

# Option 3: Admin panel
composer require filament/filament
```

---

## 📊 Matrice de Décision

| Package | Installer si... | Priorité |
|---------|----------------|----------|
| laravel-backup | **Production** | 🔴 Critique |
| sentry-laravel | **Production** | 🔴 Critique |
| query-builder | API REST | 🟢 Haute |
| medialibrary | Upload fichiers | 🟢 Haute |
| filament | Besoin backoffice | 🟢 Haute |
| livewire/inertia | Frontend moderne | 🟢 Haute |
| laravel-health | Production | 🟢 Haute |
| responsecache | Fort trafic | 🟡 Moyenne |
| l5-swagger | API publique | 🟡 Moyenne |
| google2fa | Données sensibles | 🟡 Moyenne |
| laravel-ray | Debugging avancé | ⚪ Basse |

---

## ✅ Conclusion

Ton projet a déjà :
- ✅ IDE Helper
- ✅ Larastan (PHPStan)
- ✅ Activity Log
- ✅ Permissions (Spatie)

**À installer en priorité** :
1. **spatie/laravel-backup** (critique prod)
2. **sentry/sentry-laravel** (monitoring prod)
3. Puis selon tes besoins (API, uploads, etc.)

**Total packages Spatie recommandés** : 10-12 (excellente qualité, bien maintenus)
