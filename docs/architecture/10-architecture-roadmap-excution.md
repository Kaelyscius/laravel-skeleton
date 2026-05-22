# 10. Architecture roadmap exécution

## 10.1 Phase 0 — Scaffolding modulaire (S0, ~40h)

Pré-requis Phase 1.

1. Structure dossiers `app/Core/`, `app/Modules/{Public,Live,Reviews,PressKit,Admin}/`
2. `Streamer` model + migration + seeder
3. `BelongsToStreamerScope` + trait `BelongsToStreamer` + middleware `SetCurrentStreamer`
4. `CurrentStreamer` singleton container (fail-loud)
5. `config/modules.php` + bootstrap conditionnel dans `AppServiceProvider`
6. Skeleton service providers de chaque module (vides mais déclarés)
7. Filament v3 installé, panel admin scaffold, login lié à Sanctum
8. Laravel Pennant publish + table `features`
9. Stack frontend : Vite + Tailwind 4 + Livewire 3 + Alpine bundle
10. Design tokens CSS (custom properties dans `resources/css/tokens.css`)
11. Layout Blade racine + composants base (button, card, badge)
12. ECS + PHPStan + Pest config + premiers tests fumée
13. Commande `artisan tenancy:assert` + test Pest correspondant

## 10.2 Phase 1 — Refactor skeleton install (~10j)

Indépendant de l'app — touche scripts/install/ et docs.

1. Idempotence + sentinels + lockfile installer
2. `common.sh` refactor (DRY shared lib)
3. Flags `--dry-run`, `--resume-from`
4. Re-découpage profiles Docker prod/dev/dev-tools/ops
5. Templates qualité versionnés (`docker/php/php.ini.template`, `apache/vhost.conf.template`)
6. Bats E2E `tests/bats/install.bats` (nightly bloquant)

## 10.3 Phase 2 — Bootstrap obs/CI (~6j)

1. Sentry SDK install + DSN env + breadcrumbs Laravel
2. Pulse install + DB séparée `postgres-pulse` + reverse proxy `/pulse` admin-only
3. Spatie Health checks register (DB, Cache, Queue, Disk, OpcacheMemory)
4. Uptime-Kuma container externe + monitor `/health` + alerts Discord
5. GitHub Actions wrappers : `scripts/ci/test.sh`, `scripts/ci/lint.sh`, `scripts/ci/deploy.sh` (provider-agnostic)
6. Hardening VPS (cf. §7.4)
7. `scripts/ops/backup-local.sh` cron + `backup-offsite.sh` désactivé par défaut

## 10.4 Phase 3 — Produit v1 (S1 → S6, ~24j)

| Sprint | Livrables |
|---|---|
| **S1** | Module Live : Twitch embed + offline scene + chat iframe + status badge. Auth Filament + roles Spatie. |
| **S2** | Module Reviews : `Review` model + `YoutubeValidator` (Helix API check existence) + Filament `ArticleResource` CRUD + draft/publish. |
| **S3** | Comments : `Comment` model + modération manuelle Filament + ban liste IPs + signalement utilisateur. |
| **S4** | SEO base (sitemap.xml + RSS + Schema.org) + Press Kit page + About + **⭐ OG dynamiques pré-générées job**. |
| **S5** | Preview signed routes (brouillons) + Cookie consent + Job nightly check YT availability + Brouillon post social copiable Filament + UTM tracking JTBD n°3. |
| **S6** | PHPStan L8 zéro erreur + Pest 70% baseline + Bug bash + Polish UI Caravaggio. |

## 10.5 Phase 4 — Polish OSS (S7, ~5j)

1. README "front store" (screenshots + GIF demo + value prop)
2. ADRs publiques (cf. §11)
3. Demo live (sous-domaine sandbox `demo.skeleton-streamer.dev` — coupable si glissement)
4. Fichiers OSS : `LICENSE` (MIT), `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`, `SECURITY.md`
5. Bats E2E duplicabilité skeleton (clone + install + reach `/health` 200 OK en < 15min sur VPS vierge)

## 10.6 Mitigation si glissement

Cut **Demo live + Uptime-Kuma** de v1 → gain ~2j → ~53j total → tient en 11-12 semaines avec ~1j buffer.

---
