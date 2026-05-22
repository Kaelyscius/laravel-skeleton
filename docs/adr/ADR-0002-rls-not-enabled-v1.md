# ADR-0002 — RLS Postgres non activée en v1 (Pattern C scope-only)

> **Statut** : ✅ Accepted — 2026-05-08
> **Décideurs** : Winston (architect), Alex (PO), Murat (test architect)
> **Source débat** : `docs/roundtable-decisions.md` §3.2, mini-round Filament v3 + RLS Postgres (2026-05-08)
> **⚠️ Warning verrou** : *"RLS NOT ENABLED. ENABLE BEFORE MULTI-TENANT PROD."*

---

## Contexte

Décision de switcher MariaDB → PostgreSQL 17 motivée *en partie* par la disponibilité de **Row Level Security native** comme assurance gratuite pour un pivot SaaS multi-streamer hypothétique en v2+.

Mais activer RLS en v1 (mono-streamer) pose plusieurs risques techniques documentés :

1. **Laravel n'ouvre pas de transaction par requête** par défaut → `SET LOCAL app.current_streamer_id` devient no-op hors transaction → la policy `current_setting('app.current_streamer_id')::bigint` lève une erreur ou retourne `NULL`, autorisant potentiellement *toutes les lignes*.
2. **PgBouncer (transaction pooling)** réutilise les connexions entre requêtes → fuite du `SET LOCAL` d'une requête à l'autre si mal géré.
3. **Filament v3 native tenancy a 5 gaps documentés** (« *Filament does not provide any guarantees* ») — pas de mécanisme out-of-the-box pour `SET LOCAL` dans chaque requête admin.
4. **Aucun package Laravel** ne fait RLS Postgres clé en main au niveau audit Sécurité Murat.
5. **Risque RLS naïf évalué MEDIUM-HIGH** par Winston en mini-round 2026-05-08.

En mono-streamer (`streamer_id` unique partout, v1), **RLS n'apporte aucun bénéfice de sécurité** : il n'y a qu'un seul tenant logique.

---

## Décision

**Deux patterns documentés, un seul actif en v1 :**

### Pattern C — Eloquent Global Scope (v1, ACTIF)

- Colonne `streamer_id BIGINT NOT NULL` sur toutes les tables métier dès jour 1
- Trait `BelongsToStreamer` inclus dans tous les modèles métier
- Scope global `BelongsToStreamerScope` qui injecte automatiquement `WHERE streamer_id = ?`
- Middleware `SetCurrentStreamer` qui bind le streamer courant dans le container (singleton `CurrentStreamer`)
- **Fail-loud** si le singleton n'est pas bindé (exception, pas silent fallback)
- Commande artisan `tenancy:assert` qui vérifie `Streamer::count() === 1` en CI

### Pattern D — RLS Postgres (v2+, DOCUMENTÉ mais NON ACTIVÉ)

- Migration additive :
  ```sql
  ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;
  CREATE POLICY streamer_isolation ON reviews
      USING (streamer_id = current_setting('app.current_streamer_id')::bigint);
  ```
- Middleware enrichi panel admin uniquement :
  ```php
  DB::transaction(function () use ($next, $streamerId) {
      DB::statement("SET LOCAL app.current_streamer_id = ?", [$streamerId]);
      return $next($request);
  });
  ```
- Activation Filament v3 tenancy native simultanée
- Effort estimé : **~3-4 jours additifs, non breaking**

---

## Conséquences

### Positives

- **Code v1 simple** : un seul mécanisme à comprendre (Eloquent scope), conforme idioms Laravel
- **Pas de risque sécurité** lié à mauvaise gestion `SET LOCAL` / PgBouncer
- **Pas de dépendance** à Filament v3 tenancy (qui a des gaps)
- **Migration v1 → v2+ additive** : pas de breaking change, on ajoute des policies sans toucher au scope existant
- **Assurance "pivot SaaS"** conservée : `streamer_id` est partout, RLS s'active en 3-4j si besoin
- **Filament native tenancy = OFF en v1** → pas de routing `/admin/{tenant}/...` parasite en mono-streamer

### Négatives / acceptées

- **Effort Pattern C en S1** : ~15h (trait + scope + middleware + singleton + tests + commande assert)
- **Vigilance permanente** : tout modèle métier DOIT inclure le trait — test Pest bloquant qui scanne `app/Modules/*/Models/`
- **Si Alex héberge un streamer ami en M+6** : décision d'activer RLS doit être prise *avant* (sinon fuite cross-streamer via bug applicatif possible)

### Verrou contractuel

Ce fichier ADR doit rester en `docs/adr/` du projet pour signaler aux forkers :
**Si tu actives un second streamer en prod, lis ce document et active Pattern D avant.**

Un test Pest dédié vérifie qu'il n'y a qu'un seul `Streamer` en base (`tenancy:assert`). CI bloquant.

---

## Référence débat complet

- `docs/roundtable-decisions.md` §3.2 (tenancy multi-streamer) + section "Filament v3 + RLS Postgres mini-round verdict (2026-05-08)"
- Mini-round Winston solo agent 2026-05-08 (recherche web + analyse Filament v3 native tenancy)
