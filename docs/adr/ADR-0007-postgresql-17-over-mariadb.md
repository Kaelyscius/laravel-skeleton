# ADR-0007 — PostgreSQL 17 remplace MariaDB 11.8

> **Statut** : ✅ Accepted — 2026-05-08
> **Décideurs** : Winston (architect), Alex (PO), Amelia (dev), Victor (innovation strategist)
> **Source débat** : `docs/roundtable-decisions.md` §2 (stack technique), mini-round Stack & Modularité (2026-05-08)
> **Commit applicatif** : `f7294bd switch: MariaDB 11.8 → PostgreSQL 17`

---

## Contexte

Le skeleton initial embarquait **MariaDB 11.8** comme moteur de base de données par défaut. Le mini-round Stack & Modularité du 2026-05-08 a remis ce choix sur la table à cause de quatre signaux convergents :

1. **Assurance pivot SaaS v3** — Alex confirme verbatim que le SaaS est *« une possibilité crédible si le projet se porte bien »*. Le pattern de tenancy `streamer_id` partout (cf. [ADR-0002](ADR-0002-rls-not-enabled-v1.md)) prévoit une migration additive vers Row Level Security en v2+. **RLS natif robuste est disponible en PostgreSQL, pas en MariaDB.**
2. **JSONB + index GIN** — les colonnes JSON (settings Filament, métadonnées articles, payloads webhooks Twitch/YouTube) bénéficient d'un type binaire indexable. MariaDB a un type `JSON` mais sans équivalent GIN.
3. **Full-text français** — `to_tsvector('french', ...)` natif Postgres avec stemming FR. Pour un blog éditorial qui cible 1200 mots/article × 100+ articles dans les 18 mois, la recherche full-text est un wedge produit, pas un nice-to-have. MariaDB FULLTEXT n'a pas de support FR de cette qualité.
4. **Signal moderne 2026** — l'écosystème Laravel/Filament/Pest favorise PostgreSQL en exemples, blog posts, packages. Choisir Postgres = signal "stack 2026" pour l'audience OSS PHP/Laravel.

Argument YAGNI opposé par Amelia : *« Tu n'es pas SaaS aujourd'hui, MariaDB suffit. »* Winston a tranché : **le coût de migration plus tard (~30j sur app pleine) est largement supérieur au coût de migration sur `/src` vide (~10h)**. Faire le switch maintenant = assurance gratuite.

---

## Décision

**Adoption de PostgreSQL 17 (Alpine) comme moteur unique** (dev, staging, prod, tests).

Implications concrètes :

1. **Stack Docker** : image `postgres:17-alpine`, port 5432, volumes nommés, healthcheck `pg_isready`.
2. **`config/database.php`** : driver `pgsql` par défaut, plus aucune référence à `mysql`/`mariadb`.
3. **Tests** : base `laravel_test` PostgreSQL (pas SQLite in-memory) — fidélité prod garantie, RLS testable plus tard sans changer de driver.
4. **Migrations existantes du skeleton** : adaptées aux types Postgres (`bigserial`, `jsonb`, `timestamptz`).
5. **Scripts ops** : `backup-local.sh` et `backup-offsite.sh` utilisent `pg_dump`/`pg_restore` (cf. [ADR-0003](ADR-0003-backup-local-only-v1.md)).
6. **Aucune autre option DB supportée** par le skeleton — pas de matrice multi-driver. Un forker qui veut MySQL doit retirer les fonctionnalités Postgres-spécifiques (JSONB queries, full-text FR, RLS futur) à sa main.

---

## Conséquences

### Positives

- **RLS prête en v2+** sans changer de moteur — migration additive ~3-4j (cf. ADR-0002).
- **JSONB indexable** pour settings/métadonnées dès jour 1.
- **Full-text FR** disponible pour le module Reviews sans bibliothèque tierce (Algolia/Meilisearch reportés indéfiniment).
- **Cohérence test/prod** : même moteur partout, fini les surprises au déploiement.
- **Signal moderne** pour les forkers OSS — Postgres > MariaDB dans la majorité des stacks Laravel 2026.
- **Switch réalisé sur `/src` vide** : ~30 fichiers migrés, 10h coût réel, 0 dette technique reportée.

### Négatives / acceptées

- **Forker qui voulait MariaDB doit patcher** — assumé, c'est un skeleton opinionated.
- **Coût RAM légèrement supérieur** à MariaDB pour les workloads OLTP simples — non significatif sur un VPS solo.
- **Apprentissage Postgres** si Alex avait l'habitude MySQL/MariaDB — couvert par Adminer + docs natives.

### Tests / garde-fous

- `make health` doit retourner 200 OK sur la check `DatabaseConnectionCheck` avec driver `pgsql`.
- `make install-dev-full` test E2E inclut un `php artisan migrate --pretend` qui doit générer du SQL Postgres valide.
- CI matrice : **un seul driver testé** (`pgsql`) — pas de matrice multi-DB, on ne supporte que Postgres.
- `grep -ri "mariadb\|mysql" /home/alex/myLaravelSkeleton/{docker,scripts,docs,src} --include="*.{sh,yml,php,md}"` doit retourner 0 résultat hors archive volontaire (`ROADMAP-VERSIONS.md` ligne historique 2026-05-08).

---

## Référence débat complet

- `docs/roundtable-decisions.md` §2 (Stack technique LOCKED, ligne Postgres 17 + ligne MariaDB rejetée) et section "Switch Postgres validé end-to-end (2026-05-08)".
- Mini-round Stack & Modularité 2026-05-08 (Winston vs Amelia, Victor en arbitre via filtre *"Si je ne fais jamais de SaaS, ce code est-il gaspillé ?"* — Postgres passe le test parce que JSONB+FR full-text+RLS justifient même en solo).
- ADR liés : [ADR-0002](ADR-0002-rls-not-enabled-v1.md) (RLS reportée v2+, mais infrastructure Postgres dispo), [ADR-0003](ADR-0003-backup-local-only-v1.md) (pg_dump/pg_restore).
