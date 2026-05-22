# 🏗️ Architecture technique — `myLaravelSkeleton`

> **Doc d'architecture éclatée** — produite par Winston (System Architect, 2026-05-22).
> Source mère : voir historique git (`docs/architecture.md` avant sharding).
> Toutes les décisions sont LOCKED dans [`docs/roundtable-decisions.md`](../roundtable-decisions.md).
> Décisions structurantes : [`docs/adr/`](../adr/README.md) (6 ADRs).

## Sommaire

  - [0. Comment lire ce document](./0-comment-lire-ce-document.md)
  - [1. Vue d'ensemble](./1-vue-densemble.md)
    - [1.1 Mission produit](./1-vue-densemble.md#11-mission-produit)
    - [1.2 Archétype produit — Plausible-style](./1-vue-densemble.md#12-archtype-produit-plausible-style)
    - [1.3 Périmètre v1 (LOCKED)](./1-vue-densemble.md#13-primtre-v1-locked)
  - [2. Stack technique](./2-stack-technique.md)
    - [2.1 Stack runtime](./2-stack-technique.md#21-stack-runtime)
    - [2.2 Stack applicative](./2-stack-technique.md#22-stack-applicative)
    - [2.3 Stack qualité](./2-stack-technique.md#23-stack-qualit)
    - [2.4 Stack observabilité](./2-stack-technique.md#24-stack-observabilit)
    - [2.5 Identité visuelle (tokens design system)](./2-stack-technique.md#25-identit-visuelle-tokens-design-system)
  - [3. Architecture applicative](./3-architecture-applicative.md)
    - [3.1 Arborescence cible ](./3-architecture-applicative.md#31-arborescence-cible)
    - [3.2 Activation conditionnelle des modules](./3-architecture-applicative.md#32-activation-conditionnelle-des-modules)
    - [3.3 Conventions interdites (refus explicites — cf. roundtable §Architecture)](./3-architecture-applicative.md#33-conventions-interdites-refus-explicites-cf-roundtable-architecture)
    - [3.4 Tenancy multi-streamer](./3-architecture-applicative.md#34-tenancy-multi-streamer)
    - [3.5 Feature flags — Laravel Pennant J1](./3-architecture-applicative.md#35-feature-flags-laravel-pennant-j1)
    - [3.6 Isolation environnements](./3-architecture-applicative.md#36-isolation-environnements)
  - [4. Architecture données](./4-architecture-donnes.md)
    - [4.1 PostgreSQL 17 — app principale](./4-architecture-donnes.md#41-postgresql-17-app-principale)
    - [4.2 PostgreSQL 17 — Pulse isolé (cf. ADR-0004)](./4-architecture-donnes.md#42-postgresql-17-pulse-isol-cf-adr-0004)
    - [4.3 Redis 8.6 — cache, queue, sessions](./4-architecture-donnes.md#43-redis-86-cache-queue-sessions)
    - [4.4 Stockage fichiers — local + symlink](./4-architecture-donnes.md#44-stockage-fichiers-local-symlink)
  - [5. Architecture infra (Docker)](./5-architecture-infra-docker.md)
    - [5.1 Profiles Docker Compose](./5-architecture-infra-docker.md#51-profiles-docker-compose)
    - [5.2 Réseau interne Docker](./5-architecture-infra-docker.md#52-rseau-interne-docker)
    - [5.3 Conventions images Docker](./5-architecture-infra-docker.md#53-conventions-images-docker)
  - [6. Architecture SEO & marketing](./6-architecture-seo-marketing.md)
    - [6.1 Structure URL Reviews](./6-architecture-seo-marketing.md#61-structure-url-reviews)
    - [6.2 Format article](./6-architecture-seo-marketing.md#62-format-article)
    - [6.3 Stratégie contenu (LOCKED Mary+John)](./6-architecture-seo-marketing.md#63-stratgie-contenu-locked-maryjohn)
    - [6.4 OG images dynamiques pré-générées (wedge CRITICAL S4)](./6-architecture-seo-marketing.md#64-og-images-dynamiques-pr-gnres-wedge-critical-s4)
    - [6.5 Press Kit ](./6-architecture-seo-marketing.md#65-press-kit)
    - [6.6 Tracking UTM](./6-architecture-seo-marketing.md#66-tracking-utm)
  - [7. Architecture sécurité](./7-architecture-scurit.md)
    - [7.1 Quatre bloquants prod (LOCKED Murat)](./7-architecture-scurit.md#71-quatre-bloquants-prod-locked-murat)
    - [7.2 Headers HTTP](./7-architecture-scurit.md#72-headers-http)
    - [7.3 Rate limiting](./7-architecture-scurit.md#73-rate-limiting)
    - [7.4 Infra sécurité serveur](./7-architecture-scurit.md#74-infra-scurit-serveur)
    - [7.5 Jobs avec données sensibles](./7-architecture-scurit.md#75-jobs-avec-donnes-sensibles)
    - [7.6 Fichier divulgation sécurité](./7-architecture-scurit.md#76-fichier-divulgation-scurit)
  - [8. Architecture backup (cf. ADR-0003)](./8-architecture-backup-cf-adr-0003.md)
    - [8.1 Couche 1 — Backup local VPS (activée par défaut)](./8-architecture-backup-cf-adr-0003.md#81-couche-1-backup-local-vps-active-par-dfaut)
    - [8.2 Couche 2 — Backup offsite hands-off (désactivée par défaut)](./8-architecture-backup-cf-adr-0003.md#82-couche-2-backup-offsite-hands-off-dsactive-par-dfaut)
    - [8.3 Couche 3 — B2 payant](./8-architecture-backup-cf-adr-0003.md#83-couche-3-b2-payant)
  - [9. Architecture qualité](./9-architecture-qualit.md)
    - [9.1 Gate avant commit (pre-commit hook)](./9-architecture-qualit.md#91-gate-avant-commit-pre-commit-hook)
    - [9.2 Gate CI (GitHub Actions)](./9-architecture-qualit.md#92-gate-ci-github-actions)
    - [9.3 Targets de couverture v1](./9-architecture-qualit.md#93-targets-de-couverture-v1)
  - [10. Architecture roadmap exécution](./10-architecture-roadmap-excution.md)
    - [10.1 Phase 0 — Scaffolding modulaire (S0, ~40h)](./10-architecture-roadmap-excution.md#101-phase-0-scaffolding-modulaire-s0-40h)
    - [10.2 Phase 1 — Refactor skeleton install (~10j)](./10-architecture-roadmap-excution.md#102-phase-1-refactor-skeleton-install-10j)
    - [10.3 Phase 2 — Bootstrap obs/CI (~6j)](./10-architecture-roadmap-excution.md#103-phase-2-bootstrap-obsci-6j)
    - [10.4 Phase 3 — Produit v1 (S1 → S6, ~24j)](./10-architecture-roadmap-excution.md#104-phase-3-produit-v1-s1-s6-24j)
    - [10.5 Phase 4 — Polish OSS (S7, ~5j)](./10-architecture-roadmap-excution.md#105-phase-4-polish-oss-s7-5j)
    - [10.6 Mitigation si glissement](./10-architecture-roadmap-excution.md#106-mitigation-si-glissement)
  - [11. Glossaire ADRs](./11-glossaire-adrs.md)
  - [12. Risques architecturaux flaggés (à monitorer)](./12-risques-architecturaux-flaggs-monitorer.md)
  - [13. Sortir de ce document — prochains pas](./13-sortir-de-ce-document-prochains-pas.md)

---

## Liens externes

- [`../roundtable-decisions.md`](../roundtable-decisions.md) — Décisions LOCKED (single source of truth)
- [`../adr/README.md`](../adr/README.md) — Architecture Decision Records (6 ADRs)
- [`../process/02-bmad-workflow.md`](../process/02-bmad-workflow.md) — Workflow BMad complet
- [`../process/01-getting-started.md`](../process/01-getting-started.md) — Setup machine + premier `make install-dev-full`
