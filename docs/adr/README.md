# Architecture Decision Records (ADR)

> Les ADRs documentent les **décisions structurantes** prises pendant la vie du projet — celles qu'on regretterait d'oublier ou de devoir re-débattre.

## Convention

- Format court (< 200 lignes) — Markdown léger
- Quatre sections obligatoires : **Contexte / Décision / Conséquences / Référence débat complet**
- Statut explicite : `Proposed` · `Accepted` · `Deprecated` · `Superseded by ADR-XXXX`
- Pas d'option non-retenue détaillée (référencer `docs/roundtable-decisions.md` pour le débat complet)

## Index v1

| # | Titre | Statut | Source débat |
|---|---|---|---|
| [0001](ADR-0001-modularity-plausible-style.md) | Modularité Plausible-style (refus WordPress) | ✅ Accepted | Roundtable §1.2, §3, mini-round Modularité |
| [0002](ADR-0002-rls-not-enabled-v1.md) | RLS Postgres non activée en v1 (Pattern C scope-only) | ✅ Accepted | Mini-round Filament+RLS 2026-05-08 |
| [0003](ADR-0003-backup-local-only-v1.md) | Backup local-only + offsite hands-off gratuit | ✅ Accepted | Roundtable §8 |
| [0004](ADR-0004-pulse-dedicated-database.md) | Pulse sur base de données isolée | ✅ Accepted | R4 — 3 infra decisions Winston |
| [0005](ADR-0005-apache-stays-v1-caddy-deferred.md) | Apache 2.4 reste en v1, Caddy reporté v1.5 | ✅ Accepted | R4 — 3 infra decisions Winston |
| [0006](ADR-0006-secrets-env-encrypt-native.md) | Secrets via `php artisan env:encrypt` natif | ✅ Accepted | R4 — 3 infra decisions Winston |
| [0007](ADR-0007-postgresql-17-over-mariadb.md) | PostgreSQL 17 remplace MariaDB 11.8 | ✅ Accepted | Mini-round Stack & Modularité 2026-05-08 |
| [0008](ADR-0008-frontend-stack-blade-livewire.md) | Stack frontend Blade + Livewire 3 + Alpine + Tailwind 4 | ✅ Accepted | Mini-round Frontend 2026-05-08 |
| [0009](ADR-0009-modular-app-modules-psr4.md) | Modularité `app/Modules/*` PSR-4 hand-rolled | ✅ Accepted | Mini-round Modularité 2026-05-08 |
| [0010](ADR-0010-laravel-13-supersedes-filament-v3-lock.md) | Laravel 13 — levée du verrou « Laravel 12 + Filament v3 » | ✅ Accepted | Session party-mode + montée de dépendances 2026-07-27 |

## Quand créer un nouvel ADR ?

Crée un ADR si la décision :
- **Coûterait > 1 jour-homme à inverser** plus tard
- **Affecte plusieurs modules** ou couches (app + infra + données)
- **Engage Alex contractuellement** (RGPD, OSS license, sécurité prod)
- **Mérite d'être expliquée** à un futur forker / contributeur

Ne crée PAS d'ADR pour :
- Renommage de variable / refactor local
- Choix de bibliothèque utilitaire (Carbon vs DateTime, etc.)
- Conventions de style (gérées par ECS / Rector)

## Format de fichier

```markdown
# ADR-XXXX — Titre court

> **Statut** : Proposed | ✅ Accepted | Deprecated | Superseded by ADR-YYYY
> **Décideurs** : Liste des rôles/agents
> **Source débat** : Lien roundtable-decisions.md ou doc équivalent

## Contexte

Pourquoi cette décision est sur la table. Quel problème ?

## Décision

Ce qui est décidé. Précis, actionnable.

## Conséquences

### Positives
### Négatives / acceptées
### Tests / garde-fous

## Référence débat complet

Liens vers le débat exhaustif.
```
