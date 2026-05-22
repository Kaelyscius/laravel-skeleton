# 2. Stack technique

## 2.1 Stack runtime

| Couche | Choix | Version | Conteneur Docker |
|---|---|---|---|
| Runtime PHP | PHP-FPM 8.4 LTS-friendly | 8.4 (8.5 derrière flag) | `php` |
| Web server | Apache 2.4 HTTPS/HTTP2 | 2.4 | `apache` (cf. **ADR-0005**) |
| Framework | Laravel | 12.x (LTS via support communautaire) | `php` |
| Base de données app | PostgreSQL 17 Alpine | 17 | `postgres` |
| Base de données Pulse | PostgreSQL 17 Alpine isolée | 17 | `postgres-pulse` (cf. **ADR-0004**) |
| Cache / Queue / Sessions | Redis Alpine | 8.6 | `redis` |
| Frontend build | Node.js LTS "Krypton" | 24 | `node` (profile `dev`) |

## 2.2 Stack applicative

| Domaine | Package | Version | Rôle |
|---|---|---|---|
| Admin panel | `filament/filament` | ^3.0 | CRUD admin + tenancy native (OFF v1, ON v2+) |
| Frontend interactif | `livewire/livewire` | ^3.0 | Composants serveur (cohérence Filament) |
| Frontend léger | Alpine.js | (CDN ou bundle) | Micro-interactions client |
| CSS | Tailwind | ^4.0 | Utility-first |
| Auth API | `laravel/sanctum` | ^4.0 | Tokens API + SPA cookies |
| Auth permissions | `spatie/laravel-permission` | ^7.0 | Roles + permissions |
| Activity log | `spatie/laravel-activitylog` | ^5.0 | Audit trail JSON structured |
| CSP | `spatie/laravel-csp` | ^3.0 | Headers Content-Security-Policy |
| Cookie consent | `spatie/laravel-cookie-consent` | latest | RGPD pré-embed Twitch/YouTube |
| Health checks | `spatie/laravel-health` | ^1.0 | `/health` JSON endpoint |
| Schedule monitor | `spatie/laravel-schedule-monitor` | ^4.0 | Surveillance cron |
| Feature flags | `laravel/pennant` | ^1.0 | Toggles dev solo (J1) + gating SaaS (v3) |
| Queue dashboard | `laravel/horizon` | ^5.0 | `/horizon` |
| Realtime monitoring | `laravel/pulse` | ^1.0 | `/pulse` (sur DB séparée) |
| Debug local | `laravel/telescope` | ^5.0 | `/telescope` (dev only) |
| Debug bar | `fruitcake/laravel-debugbar` | ^4.0 | UI bottom-bar (dev only) |

## 2.3 Stack qualité

| Outil | Package | Niveau |
|---|---|---|
| Tests | `pestphp/pest` + `pestphp/pest-plugin-laravel` + `pestphp/pest-plugin-drift` | ^4.0 |
| Static analysis | `larastan/larastan` | ^3.0 — **PHPStan level 8** |
| Code style | `symplify/easy-coding-standard` | ^13.0 — PSR-12 |
| Refactoring | `rector/rector` + `driftingly/rector-laravel` | ^2.3 / ^2.0 — PHP 8.5 + Laravel 12 |
| Code metrics | `nunomaduro/phpinsights` | ^2.14 |
| Architecture metrics | `php-code-archeology/php-code-archeology` | ^2.0 |
| Security scan | Snyk | latest |
| Secrets scan | Gitleaks pre-commit + CI | latest |

## 2.4 Stack observabilité

| Outil | Rôle | DSN/Endpoint |
|---|---|---|
| Sentry (free tier) | Erreurs prod externes | `SENTRY_LARAVEL_DSN` |
| Pulse | Dashboard temps réel (exceptions, slow queries, jobs, cache) | `/pulse` (admin only) |
| Spatie Health | DB, Cache, Queue, Disk, custom checks | `/health` |
| Uptime-Kuma (self-hosted) | Surveillance externe + alerting Discord | container externe |
| ~~Nightwatch~~ | Payant — **non retenu v1** | — |

## 2.5 Identité visuelle (tokens design system)

| Token | Valeur | Usage |
|---|---|---|
| `--bg` | `#0A0A0B` | Background |
| `--surface` | `#141416` | Surfaces (cards) |
| `--border` | `#1F1F22` | Bordures |
| `--text-primary` | `rgba(255,255,255,.92)` | Texte H1/body |
| `--text-secondary` | `rgba(255,255,255,.60)` | Meta/captions |
| `--accent-lava` | `#FF5722` | LIVE badge, CTA primaires, notes 9+/10, actions destructives admin |
| `--state-ok` | `#22C55E` | Succès |
| `--state-warn` | `#F59E0B` | Warning |
| `--state-err` | `#EF4444` | Erreur |
| Typographie | IBM Plex Sans + IBM Plex Mono (self-hosted via `@fontsource`) | SIL OFL |
| Icônes | Lucide stroke `1.5px` | Cohérence indus 2026 |
| Motion | CSS pur `200ms cubic-bezier(0.16, 1, 0.3, 1)`, jamais bouncy | — |
| Ratio strict | 90% mono / 8% accent / 2% états | Discipline Caravaggio |

---
