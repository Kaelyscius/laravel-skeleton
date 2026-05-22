# 11. Glossaire ADRs

Les **Architecture Decision Records** sont stockés dans `docs/adr/` au format Markdown léger (statut, contexte, décision, conséquences).

| # | Titre | Statut |
|---|---|---|
| [ADR-0001](adr/ADR-0001-modularity-plausible-style.md) | Modularité Plausible-style (refus WordPress) | ✅ Accepted |
| [ADR-0002](adr/ADR-0002-rls-not-enabled-v1.md) | RLS Postgres non activée en v1 (Pattern C scope-only) | ✅ Accepted |
| [ADR-0003](adr/ADR-0003-backup-local-only-v1.md) | Backup local-only + offsite hands-off gratuit v1 | ✅ Accepted |
| [ADR-0004](adr/ADR-0004-pulse-dedicated-database.md) | Pulse sur base de données isolée | ✅ Accepted |
| [ADR-0005](adr/ADR-0005-apache-stays-v1-caddy-deferred.md) | Apache reste en v1, Caddy reporté v1.5 | ✅ Accepted |
| [ADR-0006](adr/ADR-0006-secrets-env-encrypt-native.md) | Secrets via `php artisan env:encrypt` natif | ✅ Accepted |
| [ADR-0007](adr/ADR-0007-postgresql-17-over-mariadb.md) | PostgreSQL 17 remplace MariaDB 11.8 | ✅ Accepted |
| [ADR-0008](adr/ADR-0008-frontend-stack-blade-livewire.md) | Stack frontend Blade + Livewire 3 + Alpine + Tailwind 4 | ✅ Accepted |
| [ADR-0009](adr/ADR-0009-modular-app-modules-psr4.md) | Modularité `app/Modules/*` PSR-4 hand-rolled | ✅ Accepted |

**Convention rédaction ADR** : court (< 200 lignes), 4 sections obligatoires (Contexte / Décision / Conséquences / Statut), pas d'option non-retenue détaillée (référencer roundtable-decisions.md pour le débat complet).

---
