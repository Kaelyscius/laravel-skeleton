# 9. Architecture qualité

## 9.1 Gate avant commit (pre-commit hook)

```
1. Gitleaks (secrets)
2. ECS --fix (auto-format)
3. PHPStan level 8 (analyse)
4. Pest --parallel (tests rapides)
```

## 9.2 Gate CI (GitHub Actions)

| Job | Matrice | Bloquant |
|---|---|---|
| `lint-ecs` | PHP 8.4 | ✅ |
| `static-phpstan-l8` | PHP 8.4 | ✅ |
| `tests-pest` | PHP 8.4 + 8.5.1 × Postgres 17 | ✅ |
| `pest-drift` (mutation) | PHP 8.4 | ⚠️ (informatif) |
| `rector --dry-run` | PHP 8.4 | ⚠️ (informatif) |
| `bats-installer-smoke` | nightly only | ✅ (nightly) |
| `snyk-scan` | PHP + Node | ⚠️ (alert si new HIGH) |

## 9.3 Targets de couverture v1

| Sprint | Cible |
|---|---|
| S1 → S5 | tests features green, pas d'objectif % |
| S6 | **70% baseline Pest** (mesurable via Pest coverage) |
| S7 | PHPStan L8 zéro erreur, ECS zéro warning, Pest Drift exploré |

---
