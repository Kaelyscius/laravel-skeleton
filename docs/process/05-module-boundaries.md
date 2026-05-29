# 05 — Frontières des modules (cross-module boundaries)

> Règle d'isolation des modules `app/Modules/*`. Enforcée en CI par
> `src/tests/Unit/CrossModuleCouplingTest.php`. Voir [ADR-0009](../adr/ADR-0009-modular-app-modules-psr4.md)
> et le risque architectural §12.1.

## La règle

Un module **ne peut pas importer un autre module directement**. La seule couche
partagée autorisée est `App\Core\`.

Pour un fichier situé dans `app/Modules/<X>/` :

| Import | Autorisé ? |
|---|---|
| `use App\Core\…` | ✅ oui — Core est la couche transversale partagée |
| `use App\Modules\<X>\…` (même module) | ✅ oui — cohésion interne au module |
| `use App\Modules\<Y>\…` (autre module, Y ≠ X) | ❌ **non — couplage interdit** |
| `use Illuminate\…`, vendor, `App\Models\…`, `App\Providers\…` | ✅ oui — hors périmètre de la règle |

## Exemples

**❌ Interdit** — `app/Modules/Reviews/Models/Article.php` :

```php
use App\Modules\Live\Services\HelixClient; // Reviews dépend de Live → couplage
```

→ `CrossModuleCouplingTest` échoue avec `…/Article.php → App\Modules\Live\Services\HelixClient`.

**✅ Autorisé** — même fichier :

```php
use App\Core\Models\Streamer;            // Core partagé : OK
use App\Modules\Reviews\Models\Game;     // intra-module : OK
use Illuminate\Support\Str;              // vendor : OK
```

## Pourquoi

- **Frontière de code = frontière de facturation** (ADR-0009 / ADR-0001) : un module
  doit pouvoir être désactivé (`MODULE_<NAME>_ENABLED=false`, Story 1.7) ou extrait
  en package premium sans casser les autres.
- **Mental model simple** : on sait où regarder. Un module est une boîte ; Core est
  le socle commun.

## Comment refactorer si un besoin inter-module émerge

Par ordre de préférence :

1. **Remonter le contrat partagé dans `App\Core\`** — si Live et Reviews ont besoin
   d'une même abstraction (modèle, interface, service), elle appartient à Core.
   C'est la solution par défaut, quasi toujours suffisante en v1.
2. **Événement** (seulement si un vrai besoin de découplage émerge en v2+) — le module
   source émet un event Laravel, le module cible l'écoute. **ADR-0009 refuse l'event
   bus inter-modules dès J1 (YAGNI)** : ne l'introduire que sur un besoin concret et
   mesuré, jamais par anticipation.

❌ Ne **jamais** « contourner » en important directement l'autre module : le test CI
le bloquera, et c'est volontaire.

## Enforcement

- **Test** : `src/tests/Unit/CrossModuleCouplingTest.php` (scan des `use` de
  `app/Modules/*`, helper auto-validé sur cas synthétiques).
- **CI** : exécuté via `vendor/bin/pest` dans `.github/workflows/ci.yml` → toute
  violation fait échouer le pipeline.
- Dormant tant que les modules sont vides ; s'active automatiquement dès qu'un module
  contient du code.
