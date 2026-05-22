# ADR-0009 — Modularité `app/Modules/*` PSR-4 hand-rolled

> **Statut** : ✅ Accepted — 2026-05-08
> **Décideurs** : Winston (architect), Amelia (dev), Alex (PO), Victor (innovation strategist)
> **Source débat** : `docs/roundtable-decisions.md` §3.1, mini-round Modularité (2026-05-08)

---

## Contexte

Le skeleton doit servir un site mono-streamer (Alex) **et** rester duplicable par fork pour d'autres streamers, avec une possibilité crédible de SaaS v3. Trois questions structurantes :

1. **Comment isoler les modules métier** (Live, Reviews, Admin, PressKit, Public) pour permettre l'activation/désactivation au déploiement ?
2. **Faut-il une bibliothèque de modularisation tierce** (ex. `nwidart/laravel-modules`) ou rester en convention Laravel pure ?
3. **Quelles abstractions architecturales** (DDD, hexagonal, repositories, DTOs, CQRS) ?

Amelia avait initialement (R1) défendu une approche anti-modules pure (*"Laravel a déjà des modules, ça s'appelle des controllers + services"*). Elle a inversé sa position au mini-round Modularité 2026-05-08 sur un argument de Victor : **en SaaS, la frontière de facturation = la frontière de code**. Si on ne dessine pas les modules tôt, on ne pourra jamais facturer "Clips" en module premium plus tard sans refactor majeur.

Mais sur les abstractions (DDD/repository/etc.), consensus immédiat : **YAGNI brutal**, on reste idiomatique Laravel.

---

## Décision

### Structure adoptée

```
app/
├── Core/                          # toujours actif (Streamer, tenancy, traits, base policies)
│   ├── Models/
│   ├── Providers/CoreServiceProvider.php
│   └── ...
└── Modules/
    ├── Live/                      # Twitch embed, chat, status
    │   ├── Http/
    │   ├── Models/
    │   ├── Livewire/
    │   ├── Providers/LiveServiceProvider.php
    │   └── routes.php
    ├── Reviews/                   # CRUD articles + commentaires + YouTube VOD
    ├── Admin/                     # Filament panels + Sanctum + Spatie Permission
    ├── PressKit/                  # Page presse + contact + bio FR+EN
    └── Public/                    # Homepage, About, layout, SEO, sitemap
```

### Règles d'or

1. **PSR-4 natif Laravel 12** — namespaces déclarés dans `composer.json` :
   ```json
   "autoload": {
     "psr-4": {
       "App\\Core\\": "app/Core/",
       "App\\Modules\\Live\\": "app/Modules/Live/",
       "App\\Modules\\Reviews\\": "app/Modules/Reviews/",
       "App\\Modules\\Admin\\": "app/Modules/Admin/",
       "App\\Modules\\PressKit\\": "app/Modules/PressKit/",
       "App\\Modules\\Public\\": "app/Modules/Public/"
     }
   }
   ```
2. **Service providers conditionnels** chargés via `config/modules.php` et `AppServiceProvider::register()` :
   ```php
   foreach (config('modules.enabled') as $module) {
       $this->app->register("App\\Modules\\{$module}\\Providers\\{$module}ServiceProvider");
   }
   ```
3. **Activation via ENV** : `MODULE_LIVE_ENABLED=true`, `MODULE_REVIEWS_ENABLED=true`, etc.
4. **Migrations par module** : chaque module a son dossier `Modules/X/Database/migrations/` enregistré via `loadMigrationsFrom()` dans son provider. **Pas de mix dans `database/migrations/` racine.**
5. **Routes par module** : `Modules/X/routes.php` chargé via le provider.
6. **Tests par module** : `tests/Feature/Modules/X/`, `tests/Unit/Modules/X/`.

### Rejets explicites

- ❌ **`nwidart/laravel-modules`** — magic inutile, autoload custom non-PSR-4 standard, divergence avec convention Laravel.
- ❌ **Repositories systématiques** — Eloquent EST le repository. Pas de `UserRepository` qui wrappe `User::find()`.
- ❌ **Façades custom par module** — `app(LiveTwitchService::class)` ou injection constructeur suffit.
- ❌ **Event bus inter-modules J1** — couplage direct par appel de service, on extraira un bus si le besoin réel apparaît en v2+.
- ❌ **CQRS / Command Bus** — sur-équipement pour un site éditorial + blog.
- ❌ **Hexagonal / Ports & Adapters** — sur-équipement, Laravel n'a pas ce niveau de cérémonial.
- ❌ **DTOs systématiques** — Eloquent + Form Request + Resource suffisent. Un DTO seulement si on a un cas concret de transfert vers un service externe complexe.
- ❌ **`app/Domain/`, `app/UseCases/`, `app/Application/`** — pas de DDD vocabulaire dans un site Laravel.
- ❌ **Discovery automatique Filament resources** — chaque module enregistre ses resources explicitement dans son provider.

---

## Conséquences

### Positives

- **Frontière de facturation v3 = frontière de code** — module Clips premium pourra être un package Composer séparé (modèle GitLab CE/EE) sans refactor (cf. [ADR-0001](ADR-0001-modularity-plausible-style.md)).
- **Mental model simple Laravel** — un dev Laravel 12 comprend la structure en 5 minutes. Pas de DSL custom, pas de manifest YAML de module.
- **Tests isolés par module** — `pest --filter=Reviews` cible un module entier.
- **Désactivation propre** — un module désactivé via ENV ne charge ni ses routes, ni ses migrations, ni ses Filament resources.
- **YAGNI respecté** — pas de couches d'abstraction prématurées (repositories, DTOs, hexagonal). Coût scaffolding minimum.
- **Refactor v2+ ouvert** : si un module devient trop gros, on peut y ajouter ses propres conventions internes (sous-namespaces, DTOs ponctuels) **sans toucher aux autres modules**.

### Négatives / acceptées

- **Pas de validation automatique de la frontière inter-module** — rien n'empêche techniquement `App\Modules\Reviews\X` d'importer `App\Modules\Live\Y`. Convention humaine + code review. Un sniff custom (PHPStan rule) pourra être ajouté en v1.5 si besoin.
- **Convention écrite, pas outillée** — un forker peut violer la structure. Le README + ce ADR documentent l'intention.
- **Filament resources doivent être enregistrées explicitement** — coût marginal (~5 lignes par module), gain en lisibilité.
- **Migration cross-module** (ex. clé étrangère `articles.streamer_id` qui pointe vers `streamers` du Core) doit dépendre du `CoreServiceProvider` chargé en premier — ordre des providers garanti par `config/modules.php`.

### Tests / garde-fous

- `composer.json` autoload PSR-4 propre — un seul niveau de namespace par module, pas de fallback.
- Test Pest "smoke modules" : pour chaque module activé, la route racine retourne `200` ou redirige proprement.
- Commande artisan `modules:list` (à scaffold S0) qui affiche modules activés/désactivés + status.
- PHPStan L8 sur tous les `app/Modules/*` — aucun module n'a un baseline d'exception qui lui est propre.
- CI bloque toute migration qui n'est pas dans un dossier de module (`app/Modules/*/Database/migrations/`).

---

## Référence débat complet

- `docs/roundtable-decisions.md` §3.1 (Modularité LOCKED), section "Modularité philosophie LOCKED 2026-05-08 — Plausible-style".
- Mini-round Modularité 2026-05-08 (Victor + Amelia + Winston, Amelia inverse sa position R1 anti-modules).
- ADR liés : [ADR-0001](ADR-0001-modularity-plausible-style.md) (philosophie Plausible-style), [ADR-0002](ADR-0002-rls-not-enabled-v1.md) (tenancy `streamer_id` partout dans tous les modules), [ADR-0008](ADR-0008-frontend-stack-blade-livewire.md) (Livewire components par module).
