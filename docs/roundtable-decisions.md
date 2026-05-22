# 📋 Roundtable Decisions — Synthèse projet

> Document de référence consolidant toutes les décisions LOCKED de la table ronde BMAD du projet `myLaravelSkeleton` → site streamer Alex + skeleton OSS-first.
>
> **Source détaillée** (privée) : `_bmad-output/planning-artifacts/roundtable-streamer-app.md` (gitignored).
>
> **Statut** : Wrap-up final session 2026-04-28 → 2026-05-08 (4 rounds party-mode + mini-rounds dédiés).

---

## 🎯 Vision produit

### Mission

Site streamer personnel d'Alex (embed Twitch, blog reviews de jeux gifted, presse kit) + **skeleton OSS-first MIT** réutilisable par d'autres streamers via fork Git.

### Archétype produit

**Plausible-style** — preset fort, opinion claire. Refus explicite du modèle WordPress (panel admin de customisation runtime, marketplace de plugins, settings tenant-scoped pour features).

> *"Je veux avoir mon site. À la base, je veux le faire que pour moi. Mais que ce soit possiblement fonctionnel pour un ou plusieurs autre streamer. Mais le but c'est que les modules soient activables ou non. Mais pas que ce soit aux autres de customiser. Je veux pas faire un wordpress bis."* — Alex, 2026-05-08

### Archétype tonal

**Ponce** — calme, indé-friendly, qualité éditoriale > hype, audience qui lit. Implications : voix précise, reviews >800 mots (cible 1200), Lava palette rare, presse kit sobre.

### Métriques succès M+6 (LOCKED)

- **1500 visiteurs uniques/mois** sur le site
- **+200 followers Twitch** attribués via UTM tracking
- **10-15 articles publiés** (2-3 articles/mois × 5 mois après set-up)

### Promesse focus

10 semaines de focus exclusif sur le périmètre v1 verrouillé (S1→S6). Toute idée hors scope → `docs/backlog-v1.5-v2.md`. Murat (Test Architect) lève drapeau scope creep en review PR.

---

## 🛠️ Stack technique (LOCKED)

| Composant | Choix | Justification courte |
|---|---|---|
| **PHP** | 8.4 LTS-friendly (8.5 derrière flag) | Stabilité écosystème |
| **Framework** | Laravel 12 | Stable, écosystème mature ; re-check L13 octobre 2026 (Filament v4 = verrou) |
| **DB** | **PostgreSQL 17** (Alpine) | RLS native (assurance pivot SaaS), JSONB+GIN, full-text FR, signal moderne 2026 |
| **Cache / Queue / Sessions** | Redis 8.6 Alpine | Standard Laravel |
| **Web Server** | Apache 2.4 | Hérité skeleton (Caddy reporté v1.5) |
| **Admin** | Filament v3 | Tenancy native disponible v2+ ; Livewire+Alpine sous le capot = cohérence stack |
| **Frontend public** | Blade + Livewire 3 + Alpine + Tailwind 4 | Cohérence Filament + scope 6 sem solo + signal OSS PHP/Laravel pur |
| **Typo** | IBM Plex Sans + Mono (self-hosted) | Open-source SIL OFL, signal craft IBM Design |
| **Icônes** | Lucide stroke 1.5px | Cohérence indus 2026 |
| **Motion** | CSS pur, 200ms `cubic-bezier(0.16, 1, 0.3, 1)` | Pas Motion One — over-engineering rejeté |
| **Tests** | Pest 4 + plugins Laravel/Drift | Modern PHP testing |
| **Qualité** | Larastan v3 (PHPStan L8) + ECS 13 + Rector 2.3 + driftingly/rector-laravel 2 + PHPInsights 2.14 | Stack qualité strict niveau 8 |
| **Observabilité** | Sentry (free) + Pulse + Spatie Health + Uptime-Kuma | Sans Nightwatch payant v1 |
| **Auth** | Laravel Sanctum + Spatie Permission v7 | Standard |
| **Logs** | Spatie ActivityLog v5, JSON structured + logrotate | |
| **Health** | Spatie Health v1 + Schedule Monitor v4 | |
| **Sécurité** | Spatie CSP v3 + Cookie Consent | OWASP A01-A04 covered Pest |
| **VOD storage** | Embed YouTube uniquement v1 | Pas de S3/Backblaze v1 (élimine ~40% complexité) |
| **License** | MIT | OSS-first |

### Décisions stack rejetées (avec justification)

- ❌ **MariaDB 11.8** (état initial) → switch Postgres pour RLS native + JSONB + signal moderne
- ❌ **Laravel 13** (sorti fév 2026) → Filament v3 lock, écosystème pas prêt à T+3mois
- ❌ **Inertia.js + Vue 3 + TypeScript** → coût scaffolding +30.5h (vs +14.5h Livewire = delta ~16h) + apprentissage Vue/TS, segmente audience OSS PHP
- ❌ **Caddy** v1 → Apache stays, gain 2j (Caddy reporté v1.5)
- ❌ **nwidart/laravel-modules** → magic inutile, PSR-4 natif suffit
- ❌ **Backblaze B2 payant v1** → backup local quotidien gratuit + offsite hands-off (Mega/Drive free tier) ; B2 reporté à M+6 si premier streamer ami hébergé
- ❌ **stancl/tenancy / spatie/laravel-multitenancy** → hand-rolled Eloquent Global Scope suffisant v1
- ❌ **Multi-tenant SaaS unique app v3** → modèle "1 instance par streamer hébergée" (Plausible Cloud style) si SaaS jamais

---

## 🏗️ Architecture (LOCKED)

### Modularité

**`app/Modules/{Live, Reviews, Admin, PressKit, Public}` + `Core/`** — PSR-4 natif Laravel 12, service providers conditionnels via `config/modules.php`.

**Activation** : ENV vars `MODULE_X_ENABLED` au déploiement (par toi ou un forker), pas par utilisateur runtime.

**Refus** explicites :
- ❌ Repositories systématiques (Eloquent EST le repository)
- ❌ Façades custom par module
- ❌ Event bus inter-modules J1
- ❌ CQRS / Command Bus
- ❌ Hexagonal / Ports & Adapters
- ❌ DTOs systématiques
- ❌ `app/Domain/`, `app/UseCases/`, `app/Application/`
- ❌ Discovery automatique Filament resources
- ❌ Mix migrations modules dans `database/migrations/` racine

### Tenancy multi-streamer

- **`streamer_id` dans toutes les tables jour 1** (concession Victor R3 — assurance pivot SaaS gratuite)
- **v1 (mono-streamer)** : Pattern C = Eloquent Global Scope `BelongsToStreamerScope` + middleware `SetCurrentStreamer` + container binding (fail-loud si pas bindé). **PAS de RLS Postgres active**.
- **v2+ (multi-streamer)** : Pattern D = ENABLE ROW LEVEL SECURITY + CREATE POLICY par module + transaction wrapping middleware (panel admin uniquement) + activation Filament tenancy native. Migration **additive** ~3-4j.
- **ADR-0002 mandatory** : *"RLS NOT ENABLED. ENABLE BEFORE MULTI-TENANT PROD."*

### Feature flags

**Laravel Pennant J1** (1h scaffolding) :
- v1 : feature flags pour toggles dev solo (déploiement code dormant)
- v3 SaaS : `Feature::for($streamer)->active('module')` pour gating per-streamer (migration API triviale)

### Iso prod / dev

| Outil | Dev | Staging | Prod |
|---|---|---|---|
| Telescope, Debugbar, Mailpit, Adminer, Xdebug | ON | OFF | OFF |
| Sentry, Pulse, Spatie Health | ON | ON | ON (DSN différents) |
| Log level | debug | info | warning |
| HTTPS forcé | OFF | ON | ON |

---

## 📦 Modules v1

| Module | Rôle | Statut tier (v3 SaaS hypothétique) |
|---|---|---|
| **Core** | Streamer model, tenancy, traits, base policies — toujours actif | — |
| **Public** | Homepage, About, layout, SEO, sitemap | Gratuit forever |
| **Live** | Twitch embed + chat + scène offline + status | Gratuit forever |
| **Reviews** | CRUD articles + commentaires + modération + YouTube VOD link | Gratuit forever (freemium au-delà de X/mois) |
| **PressKit** | Page presse + contact + bio FR+EN | Gratuit forever (wedge marketing) |
| **Admin** | Filament panels + Sanctum + Spatie Permission | Gratuit forever |

### Modules futurs (post-v1)

| Module | Phase | Tier monétisation v3 |
|---|---|---|
| **Clips** (yt-dlp + FFmpeg) | v1.5 | **PREMIUM** ⭐ wedge #1 monétisation (modèle Eklipse/OpusClip ~9€/mois) |
| **Notifications** (Discord webhook) | v1.5 | Freemium |
| **Newsletter** (Buttondown-style) | v2+ | Premium |
| **Analytics propre stream** (Helix sur ses streams) | v2+ | Premium |
| **MultiStreamer** | v3+ | C'est le mode SaaS lui-même, pas un module |

**Reportés et c'est OK** : Stats stream agrégées, scraping compétitif (jamais sans revue légale écrite), modération avancée Akismet/OpenAI, posts sociaux auto-publiés (v1 = brouillon copiable depuis Filament).

---

## 🎨 Direction visuelle (LOCKED)

| Token | Valeur |
|---|---|
| **Background** | `#0A0A0B` |
| **Surface** | `#141416` |
| **Border** | `#1F1F22` |
| **Texte primaire** | `rgba(255,255,255,.92)` |
| **Texte secondaire** | `rgba(255,255,255,.60)` |
| **Accent Lava** | `#FF5722` (réservé : LIVE badge, CTA primaires, notes 9+/10, actions destructives admin) |
| **États** | vert `#22C55E` · ambre `#F59E0B` · rouge `#EF4444` |
| **Ratio strict** | 90/8/2 (mono / accent / états) |
| **Typo** | IBM Plex Sans + IBM Plex Mono (self-hosted via @fontsource) |
| **Icônes** | Lucide stroke 1.5px |
| **Motion** | 200ms `cubic-bezier(0.16, 1, 0.3, 1)`, jamais bouncy |
| **Mood** | terminal-broadcaster · discipline · vitesse · monochrome · Lava-quand-ça-compte |
| **Inspirations** | Linear, Raycast, Astro Studio, vercel.com/dashboard |
| **Anti-inspirations** | Web3/NFT/AI startup violet générique, gradients Twitch-générique 2020 |

### Anti-patterns visuels (Caravaggio)

- ❌ Gradient Lava→noir en background (Twitch-générique 2020)
- ❌ Geist font (signal Vercel startup tech, pas craft IBM)
- ❌ Lava en masse (réservé accent ponctuel)
- ❌ Photo Alex sur OG images (la review parle, pas le streamer)

---

## 🌐 SEO & Marketing (décisions B mini-round)

### Structure URL

**Choix : `/reviews/elden-ring-2-mon-verdict`** (slug long éditorial)

**Justification John** : JTBD n°3 (dev gifting) = devs partagent l'URL → la slug doit raconter en 1 coup d'œil. Évite `/r/...` (wedge "Press Office" prématuré sans volume) et `/2026/05/...` (date ringard tue evergreen review).

### Format article

- **Longueur** : 1200 mots cible (plancher 800, plafond 2000)
- **YouTube embed** : petit + timecodes inline cliquables `[00:42]` dans le texte (gros bloc above-the-fold tue dwell time)
- **Compteur vues** : page detail uniquement, seuil min 100 vues (pas en index — anti-vanity Ponce)

### Stratégie contenu

- **Mix** : 70% reviews longues / 30% news+previews (capital SEO long-tail + fraîcheur RSS + signal Keymailer)
- **Cadence** : steady **3 articles/mois** (pas de sprints — sprints cassent l'algo Google + Twitch UTM)
- **Capital M0** : **3 articles publiés jour 1** (1 = profil vide, 5 = surinvest ; 3 = sweet spot signal éditorial vivant)

### Plateformes acquisition (Keymailer / Woovit / Lurkit)

- **Timing** : inscription **M+1** (avec 5-6 articles publiés = sweet spot crédibilité)
- **Stratégie** : **staggered** — Keymailer d'abord M+1, Woovit + Lurkit M+2 (apprentissage pitch + proof social)
- **Seuil clés/mois M+6 RÉVISÉ** : **3→15 clés/mois** (Mary R2 disait 5→25 mais supposait setup full-time ; Alex solo temps partiel = 15 réaliste)

### OG images dynamiques (wedge CRITICAL Caravaggio)

- **Génération** : pré-généré au publish via job artisan → `/public/og/{slug}.png` (pas Browsershot à la volée — +800ms TTFB tue le partage social)
- **Format** : 1200×630 uniquement (standard OG ; 1200×1200 Insta = faux besoin)
- **Composition** : Title + note/10 (gros, 180px) + cover game (left 40%) + Lava bar bottom si 9+ + logo discret bottom-right
- **Background** : `#0A0A0B` flat, pas de gradient
- **Wedge level** : **CRITICAL — ship en S4 avec press kit, pas v1.5**

### Press Kit page (`/press`)

- **Hiérarchie** : Stats live > Photo > Bio (le dev gifting scanne les chiffres avant la tête)
- **Stats** : viewers concurrents moyens (P50) + heures streamées total + nb vidéos YouTube. **Pas** followers Twitch (vanity, gameable). Médiane > pic = honnêteté Ponce.
- **Pack download** : choix multiple, **pas de zip** (un dev sérieux veut le SVG seul)
- **Bio FR+EN v1** (signal international, cohérent avec README EN, coût marginal 200 mots traduits)

### Risques marketing flaggés

- 🔴 **JTBD n°3 dev gifting non tracké** (John) → ajouter UTM auto-généré sur bouton "copier le lien" (~1h dev S5)
- 🔴 **Dépendance UTM Twitch unidirectionnelle** (Mary) → checklist stream-side obligatoire (panel Twitch + !commande + lower-third). Sans discipline stream, +200 followers raté à -60%

---

## 🛡️ Sécurité (4 bloquants prod LOCKED — Murat)

| # | Bloquant | Couverture |
|---|---|---|
| 1 | **Gitleaks** pre-commit hook + CI | Phase 2/S0 |
| 2 | **Pest security suite** OWASP A01-A04 | Phase 3/S1 |
| 3 | **Cookie consent pré-embed** Twitch+YouTube | Phase 3/S2 (`spatie/laravel-cookie-consent`) |
| 4 | **Bats smoke installer** nightly bloquant | Phase 1/S-2 + Phase 4/S7 (E2E duplicabilité) |

**Infra sécurité** : HSTS preload, CSP via spatie/laravel-csp, rate limit 60/min API + 5/min login, fail2ban SSH, SSH key-only, UFW (22/80/443), `php artisan env:encrypt` natif Laravel 12, Dependabot/Renovate, headers (X-Frame DENY / X-Content-Type nosniff / Referrer-Policy strict-origin-when-cross-origin).

---

## 💾 Backup strategy (zéro budget v1)

- **Couche 1 — Backup local VPS** quotidien (`pg_dump` cron → `/var/backups/postgres/`, rotation 14j) : ACTIVÉE par défaut via `scripts/ops/backup-local.sh`
- **Couche 2 — Backup offsite hands-off** : DÉSACTIVÉE par défaut (`BACKUP_OFFSITE_ENABLED=false`). Activable en 5 min via rclone vers Mega 20GB / Google Drive 15GB / pCloud 10GB free tier.
- **Backup Backblaze B2 payant** : reporté à M+6 (premier streamer ami hébergé) ou si data value dépasse les 0.50€/mois d'assurance.
- **ADR-0003 mandatory** : *"Backup strategy v1 = LOCAL-ONLY. UPGRADE TO PAID OFFSITE BEFORE HOSTING THIRD-PARTY DATA."*

---

## 📅 Roadmap exécution

```
Phase 0 — Scaffolding modulaire (S0)            ~40h   ⬅ NEXT
   (25h back + 14.5h front + 0.5h buffer — cf. mini-round Frontend)
   ↓
Phase 1 — Refactor skeleton install (S-2/S-1)   ~10j
   - Idempotence + sentinels + lockfile + Bats
   - common.sh refactor, --dry-run, --resume-from
   - Re-découper profiles Docker prod/dev/dev-tools/ops
   - Templates qualité versionnés
   ↓
Phase 2 — Bootstrap obs/CI (S0)                 ~6j
   - Sentry + Pulse (DB séparée) + Health + Uptime-Kuma
   - GitHub Actions wrappers (matrice PHP 8.4/8.5.1)
   - Scripts CI provider-agnostic dans scripts/ci/*.sh
   - Backups Backblaze (reporté) → backup-local.sh + offsite hands-off
   - Hardening VPS (SSH key-only, UFW, fail2ban)
   ↓
Phase 3 — Produit v1 (S1 → S6)                  ~24j
   S1 : Live (Twitch embed + chat + offline) + Auth admin
   S2 : Filament v3 + Article model + YoutubeValidator + ArticleResource CRUD
   S3 : Comments + modération basique + ban manuel admin
   S4 : SEO base (sitemap, OG, Schema.org Review/Article/Person/VideoGame, RSS) + Press Kit + About + ⭐ OG dynamiques pré-générées
   S5 : Preview signed routes + Cookie consent + Job nightly check YT availability + Brouillon post social copiable + UTM tracking JTBD n°3
   S6 : PHPStan L8 + Pest 70% baseline + Bug bash + Polish UI Caravaggio
   ↓
Phase 4 — Polish OSS (S7)                       ~5j
   - README "front store" + ADRs (12+) + Demo live + Fichiers OSS (LICENSE/COC/CONTRIBUTING/SECURITY)
   - Bats E2E duplicabilité skeleton

Total : ~55j sur 50j ouvrés (10 sem strict)
Réalisme prudent : 11-12 semaines
```

### Mitigation budget si glissement

- Cut **Demo live + Uptime-Kuma** de v1 (~2j gain) → revient à ~53j

---

## 🚦 Land-and-expand (Victor)

| Mois | Étape | Décision critique |
|---|---|---|
| M0 | Lancement skeleton + site live + 3 articles publiés | `streamer_id` partout (acté) |
| M+1→M+3 | Utilisation perso, debug, ajout features selon besoins | Aucune décision SaaS — Alex est son propre user research |
| **M+1** | Inscription Keymailer (puis Woovit/Lurkit M+2) | Sweet spot crédibilité plateformes |
| M+3 | Premier post Reddit/Twitter "skeleton OSS" | README crédible ? |
| **M+6** | **CRITIQUE** — premier streamer ami "héberge-moi le tien" | Beta tester gratuit sur ton serveur. Activer backup B2 payant à ce moment. |
| M+9 | 2-3 streamers hébergés gratos | Décision multi-tenant officielle (TenantManager + middleware) |
| M+12 | 3-5 streamers, 1-2 prêts à payer | Décision SaaS — Stripe + Cashier + plans Pennant |
| M+18 | 10-30 payants ou 0 | Décision binaire SaaS produit principal vs OSS pur |

### Test ultime de Victor (à graver)

> *"Si je ne fais jamais de SaaS, ce code est-il gaspillé ?"*

Si oui → sur-architecture, coupe. Si non → modularité saine. **`streamer_id` passe le test. Pennant passe le test. TenantManager ne passe pas. Stripe ne passe pas.**

### Question dévastatrice de Victor (réponse Alex implicite)

> *"Si dans 6 mois un streamer ami te dit 'je veux la même chose, héberge-moi ça', est-ce que tu sais ce que tu lui factures, à quelle marge, et ce qui se passe quand il te demande une feature custom que TU ne veux pas pour ton site à toi ?"*

**Réponse Alex** (implicite Plausible-style) : *"Tu lui dis non. C'est mon site. Tu fork si tu veux."*

---

## 🚀 Comment lancer le projet (synthèse)

### Demain matin / prochaine session

```bash
cd /home/alex/myLaravelSkeleton
claude
```

```
Reprends le projet. Lis docs/roundtable-decisions.md, docs/process/01-getting-started.md
et docs/process/02-bmad-workflow.md pour le contexte. On est au sprint S0 — phase 0 formalisation.
```

### Workflow recommandé Phase 0 (1-2h prep avant code)

```
1. /bmad-agent-architect → "génère docs/architecture.md basé sur docs/roundtable-decisions.md"
2. /bmad-shard-doc docs/architecture.md
3. /bmad-agent-pm → "génère docs/epics/ + stories/ depuis le backlog R4"
```

### Workflow recommandé Phase 0 → code (S0 scaffolding)

```
4. /bmad-create-story (pour le ticket "Scaffold modular architecture")
5. /bmad-dev-story docs/stories/0001-scaffold-modular-architecture.md
6. /bmad-code-review (avant commit)
7. git add -A && git commit && git push
```

### Détails complets

- **Setup machine + premier `make install-dev-full`** → [`docs/process/01-getting-started.md`](process/01-getting-started.md)
- **Workflow BMAD complet** → [`docs/process/02-bmad-workflow.md`](process/02-bmad-workflow.md)

---

## 📚 Annexes

### Liste agents BMAD mobilisés

| Agent | Rôle | Rounds |
|---|---|---|
| 🏗️ Winston | System Architect | R1, R2, R3, mini-rounds Stack/Modularité/Frontend/Filament+RLS |
| 💻 Amelia | Senior Software Engineer | R1, R4, mini-rounds Stack/Modularité/Frontend |
| 🧪 Murat | Master Test Architect | R1, R2, R3, R4 |
| 📋 John | Product Manager | R1, R2, R3, R4, mini-round B (URL/contenu) |
| 🎨 Sally | UX Designer | R1, R2, R3, mini-round Frontend |
| 📊 Mary | Business Analyst | R1, R2, mini-round B (contenu/plateformes) |
| 🎬 Caravaggio | Visual & Presentation Expert | R2, R3, mini-round B (Press Kit/OG) |
| ⚡ Victor | Disruptive Innovation Oracle | R2, R3, mini-round Modularité |

### Réponses Alex aux questions ouvertes (LOCKED)

1. **Chiffres succès M+6** : 1500 UU/mois · +200 followers Twitch UTM · 10-15 articles ✅
2. **Promesse 10 sem focus** : OUI, scope S1→S6 verrouillé ✅
3. **Streamer-pair archétype** : **Ponce** (calme, indé, qualité éditoriale > hype) ✅
4. **Plausible vs WordPress** (mini-round modularité) : **Plausible-style** verrouillé ✅

### Décisions complémentaires R4 (LOCKED)

- ❌ Analyse compétitive Twitch scraping (v1 ET v2)
- ❌ Posts réseaux sociaux auto-publiés v1 → brouillon copiable Filament
- ❌ Métriques / idées stream v2 (Helix propre uniquement)
- ❌ Clips MP4 v1.5 (yt-dlp + FFmpeg) — v1 = timecodes YouTube `?t=XXX`

### Switch Postgres validé end-to-end (2026-05-08)

- ✅ ~30 fichiers migrés MariaDB → PostgreSQL 17
- ✅ Install Laravel 12.58 + 16 tables migrées + /health 200 OK
- ✅ 0 référence MariaDB/MySQL résiduelle (hors archive ROADMAP-VERSIONS volontaire)
- ✅ Test E2E réussi : `make install-dev-full` complète en ~10 min, app fonctionnelle

### Frontend stack mini-round verdict (2026-05-08)

- **Blade + Livewire 3 + Alpine + Tailwind 4** unanime (Sally + Amelia)
- Sally révise sa position R2 (Motion One Vue rejeté — over-engineering)
- Inertia + Vue + TS = +60-75h apprentissage si niveau Vue/TS = 0 + segmente audience OSS
- Cohérence Filament v3 admin = argument décisif

### Filament v3 + RLS Postgres mini-round verdict (2026-05-08)

- Risque RLS naïf = MEDIUM-HIGH (Laravel n'ouvre pas transaction par request → SET LOCAL no-op + PgBouncer leak)
- Filament v3 tenancy native a 5 gaps documentés ("Filament does not provide any guarantees")
- Aucun package Laravel ne fait RLS Postgres clé en main
- **Décision** : Pattern C (Eloquent Global Scope) en v1, Pattern D (RLS additive) en v2+

---

## ✅ Décisions clés en 1 phrase chacune

1. **Stack** : PHP 8.4 + Laravel 12 + PostgreSQL 17 + Filament v3 + Livewire 3 + IBM Plex + Lava réservé
2. **Modularité** : Plausible-style — `app/Modules/*` PSR-4 + ENV vars (pas UI user)
3. **Tenancy** : `streamer_id` partout J1 + Eloquent Global Scope (RLS Postgres reportée v2+)
4. **Backup** : local quotidien + offsite hands-off gratuit (B2 payant à M+6)
5. **Frontend** : Blade + Livewire 3 + Alpine, 100% éditorial, motion CSS pur 200ms
6. **Scope** : v1 6 sem S1-S6 verrouillé, ~55j total (réalisme 11-12 sem)
7. **Sécurité** : 4 bloquants prod (gitleaks + Pest A01-A04 + cookie consent + Bats nightly)
8. **Marketing** : URL slug long éditorial / 70-30 reviews-news / 3 articles M0 / Keymailer M+1 staggered
9. **Press kit** : Stats P50 médianes / FR+EN bilingue / pas de zip / pas photo Alex sur OG
10. **OG images** : pré-générées au publish, 1200×630, CRITICAL en S4 (pas v1.5)

---

**Source détaillée et historique complet** : `_bmad-output/planning-artifacts/roundtable-streamer-app.md` (privé, gitignored).

**Dernière mise à jour** : 2026-05-08 — fin de session de 4 rounds + 4 mini-rounds.
