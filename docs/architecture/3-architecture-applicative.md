# 3. Architecture applicative

## 3.1 Arborescence cible `src/app/`

```
src/app/
├── Core/                          # Cœur transversal, toujours actif
│   ├── Concerns/                  # Traits réutilisables
│   │   └── BelongsToStreamer.php
│   ├── Models/
│   │   └── Streamer.php
│   ├── Scopes/
│   │   └── BelongsToStreamerScope.php
│   ├── Http/
│   │   └── Middleware/
│   │       └── SetCurrentStreamer.php
│   ├── Providers/
│   │   └── CoreServiceProvider.php
│   └── Support/
│       └── CurrentStreamer.php    # Container singleton fail-loud
│
├── Modules/                       # Modules métier activables
│   ├── Public/                    # Homepage, About, layout, SEO, sitemap
│   │   ├── Http/{Controllers,Requests,Resources}
│   │   ├── Models/
│   │   ├── Providers/PublicServiceProvider.php
│   │   ├── Routes/web.php
│   │   ├── Views/                 # ou resources/views/modules/public/
│   │   ├── database/migrations/   # Migrations module-scoped
│   │   └── tests/
│   ├── Live/                      # Twitch embed + chat + offline + status
│   ├── Reviews/                   # CRUD articles + commentaires + YT VOD
│   ├── PressKit/                  # Press page + contact + bio FR+EN
│   └── Admin/                     # Filament panels + Sanctum + Permissions
│
└── Providers/
    └── AppServiceProvider.php     # Bootstrap conditionnel des modules
```

> **Note** : Les `Views/` et `database/migrations/` sont versionnés dans le module lui-même (pas `database/migrations/` racine — décision LOCKED). Les service providers chargent dynamiquement leurs vues/migrations via `loadMigrationsFrom()` et `loadViewsFrom()`.

## 3.2 Activation conditionnelle des modules

**Fichier de configuration** : `src/config/modules.php`

```php
return [
    'public'    => env('MODULE_PUBLIC_ENABLED', true),
    'live'      => env('MODULE_LIVE_ENABLED', true),
    'reviews'   => env('MODULE_REVIEWS_ENABLED', true),
    'press_kit' => env('MODULE_PRESS_KIT_ENABLED', true),
    'admin'     => env('MODULE_ADMIN_ENABLED', true),
];
```

**Bootstrap conditionnel** dans `AppServiceProvider::register()` :

```php
collect(config('modules'))
    ->filter()
    ->each(fn ($_, $module) => $this->app->register(
        "App\\Modules\\".Str::studly($module)."\\Providers\\".Str::studly($module)."ServiceProvider"
    ));
```

**Conséquence** : un forker désactive `MODULE_REVIEWS_ENABLED=false` au déploiement et plus aucune route, migration, vue, ou table Reviews n'est touchée. **Pas de panel admin pour ça.**

## 3.3 Conventions interdites (refus explicites — cf. roundtable §Architecture)

| ❌ Anti-pattern | Pourquoi refusé |
|---|---|
| Repositories systématiques | Eloquent EST le repository |
| Façades custom par module | Bloat sans bénéfice |
| Event bus inter-modules J1 | YAGNI — appels directs suffisent, événements quand le besoin émerge |
| CQRS / Command Bus | Over-engineering pour solo dev |
| Hexagonal / Ports & Adapters | Over-engineering pour solo dev |
| DTOs systématiques | Form Requests + Resources Eloquent suffisent |
| `app/Domain/`, `app/UseCases/`, `app/Application/` | DDD prématuré |
| Discovery automatique Filament resources | Explicite > magique pour OSS forkers |
| Mix migrations modules dans `database/migrations/` racine | Coupure module brisée |
| `nwidart/laravel-modules` | Magic inutile — PSR-4 natif suffit |

## 3.4 Tenancy multi-streamer

**v1 (mono-streamer) — Pattern C — cf. ADR-0002**

Composants :
1. Colonne `streamer_id` (nullable=false, indexée) sur **toutes les tables métier dès jour 1**
2. Trait `BelongsToStreamer` à inclure dans tout modèle métier
3. Scope global `BelongsToStreamerScope` appliqué automatiquement via le trait
4. Middleware `SetCurrentStreamer` qui résout le streamer courant et bind dans le container
5. Singleton `App\Core\Support\CurrentStreamer` accessible via `app(CurrentStreamer::class)` — **fail-loud** si pas bindé

Pseudocode du scope :
```php
public function apply(Builder $builder, Model $model): void
{
    $streamerId = app(CurrentStreamer::class)->id();
    $builder->where($model->getTable().'.streamer_id', $streamerId);
}
```

**Pseudocode du middleware** :
```php
public function handle(Request $request, Closure $next)
{
    $streamer = Streamer::query()->firstOrFail(); // v1 mono → un seul row
    app()->instance(CurrentStreamer::class, new CurrentStreamer($streamer));
    return $next($request);
}
```

**Garde-fous** :
- `Streamer::query()->count() === 1` assert dans une commande `artisan tenancy:assert` (CI bloquant)
- Test Pest : tout modèle métier DOIT inclure `BelongsToStreamer` trait (test feature scanne `app/Modules/*/Models/`)

**v2+ (multi-streamer) — Pattern D — RLS Postgres**

Migration additive :
```sql
ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;
CREATE POLICY streamer_isolation ON reviews
    USING (streamer_id = current_setting('app.current_streamer_id')::bigint);
```

Middleware enrichi (panel admin uniquement) :
```php
DB::transaction(function () use ($next, $request, $streamerId) {
    DB::statement("SET LOCAL app.current_streamer_id = ?", [$streamerId]);
    return $next($request);
});
```

**Activation Filament tenancy native** simultanée.
Effort estimé : ~3-4j additive, **non breaking**.

## 3.5 Feature flags — Laravel Pennant J1

**Coût scaffolding** : 1h (publish config + table `features`).

**Usage v1 (solo dev toggles)** :
```php
if (Feature::active('og-dynamic-pre-render')) {
    GenerateOgImage::dispatch($review);
}
```

**Migration vers SaaS v3 (gating per-streamer)** :
```php
if (Feature::for($streamer)->active('clips-module')) { ... }
```

→ Changement API trivial, **pas de re-architecture**.

## 3.6 Isolation environnements

| Outil | Dev | Staging | Prod |
|---|---|---|---|
| Telescope, Debugbar, Mailpit, Adminer, Xdebug | ✅ | ❌ | ❌ |
| Sentry, Pulse, Spatie Health | ✅ | ✅ | ✅ (DSN distincts) |
| Niveau log | `debug` | `info` | `warning` |
| HTTPS forcé | ❌ | ✅ | ✅ |
| Profiles Docker actifs | `dev` + `tools` + `dev-extra` | `dev` minimal | aucun |
| Cookie consent banner | ✅ (mock) | ✅ | ✅ |

---
