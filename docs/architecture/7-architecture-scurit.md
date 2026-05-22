# 7. Architecture sécurité

## 7.1 Quatre bloquants prod (LOCKED Murat)

| # | Bloquant | Implémentation | Phase |
|---|---|---|---|
| 1 | **Gitleaks** | pre-commit hook (`.husky/` ou `lefthook.yml`) + GitHub Actions step | Phase 2 / S0 |
| 2 | **Pest security suite OWASP A01-A04** | Tests Pest dédiés : `tests/Security/{Auth,AccessControl,Injection,Cryptography}Test.php` | Phase 3 / S1 |
| 3 | **Cookie consent pré-embed** | `spatie/laravel-cookie-consent` configuré bloquant pour Twitch/YouTube iframes | Phase 3 / S2 |
| 4 | **Bats smoke installer nightly** | Suite `tests/bats/install.bats` lancée en CI nightly + duplicabilité E2E skeleton | Phase 1 / S-2 + Phase 4 / S7 |

## 7.2 Headers HTTP

Middleware global :
```
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
X-Frame-Options: DENY
X-Content-Type-Options: nosniff
Referrer-Policy: strict-origin-when-cross-origin
Content-Security-Policy: [via spatie/laravel-csp]
```

## 7.3 Rate limiting

| Route | Limite |
|---|---|
| `api/*` | 60/min/IP |
| `login`, `password.email` | 5/min/IP |
| `register` | 3/min/IP |
| `comment.store` | 10/h/user authentifié |

## 7.4 Infra sécurité serveur

- SSH key-only (`PasswordAuthentication no`)
- UFW : 22/80/443 uniquement
- fail2ban sur SSHD + nginx/apache login attempts
- Dependabot + Renovate (PR automatisées dépendances)
- `php artisan env:encrypt` natif Laravel pour secrets en repo (cf. **ADR-0006**)

## 7.5 Jobs avec données sensibles

Tout job transportant tokens / mots de passe / PII implémente `ShouldBeEncrypted` :
```php
class SendPasswordResetEmail implements ShouldQueue, ShouldBeEncrypted { /* ... */ }
```

→ Payload chiffré en queue Redis, réduit le rayon d'impact si queue compromise.

## 7.6 Fichier divulgation sécurité

`public/.well-known/security.txt` généré à l'install — personnalisable.

---
