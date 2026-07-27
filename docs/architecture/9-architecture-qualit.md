# 9. Architecture qualité

## 9.1 Gate avant commit (pre-commit hook)

```
1. Gitleaks (secrets)
2. ECS --fix (auto-format)
3. PHPStan level 8 (analyse)
4. Pest --parallel (tests rapides)
```

## 9.2 Gate CI (GitHub Actions)

> **Matrice PHP amendée le 2026-07-27** — PHP 8.4 est abandonné : `composer.json` impose
> `"php": "^8.5"` depuis la montée Laravel 13 ([ADR-0010](../adr/ADR-0010-laravel-13-supersedes-filament-v3-lock.md)),
> le runtime est 8.5.4. La matrice porte donc sur 8.5.x uniquement.

| Job | Matrice | Bloquant | État réel |
|---|---|---|---|
| `lint-ecs` | PHP 8.5 | ✅ | ✅ conforme (ECS à 0) |
| `static-phpstan-l8` | PHP 8.5 | ✅ | ✅ conforme (10 erreurs résiduelles, config/*) |
| `tests-pest` | PHP 8.5 × Postgres 17 | ✅ | ✅ conforme depuis `d94cdc5` |
| `pest-drift` (mutation) | PHP 8.5 | ⚠️ (informatif) | ❌ **absent du workflow** |
| `rector --dry-run` | PHP 8.5 | ⚠️ (informatif) | ❌ **encore bloquant** dans `ci.yml` |
| `php-insights` | PHP 8.5 | ⚠️ (informatif) | ❌ **encore bloquant** dans `ci.yml` |
| `bats-installer-smoke` | nightly only | ✅ (nightly) | ❌ **absent** |
| `snyk-scan` | PHP + Node | ⚠️ (alert si new HIGH) | ⚠️ workflow séparé |

> **Écart spec ↔ implémentation à résorber.** La CI réelle est encore un **job monolithique**
> là où cette section décrit 7 jobs séparés. Cet écart a existé sans signal pendant toute
> l'Epic 1 — c'est le risque R-009 du test design système
> (`_bmad-output/test-artifacts/test-design-architecture.md`). Le découpage en jobs et la
> bascule Rector/Insights en informatifs restent à faire.

## 9.3 Targets de couverture v1

| Sprint | Cible |
|---|---|
| S1 → S5 | tests features green, pas d'objectif % |
| S6 | **70% baseline Pest** (mesurable via Pest coverage) |
| S7 | PHPStan L8 zéro erreur, ECS zéro warning, Pest Drift exploré |

---
