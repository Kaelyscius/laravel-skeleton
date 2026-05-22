# 📦 Backlog hors-scope v1 — `myLaravelSkeleton`

> **Statut** : fichier vivant. Initialisé 2026-05-22 lors de la formalisation PRD.
> **Maintainer** : Alex (PO). Items ajoutés/archivés au fil de l'eau.
> **Usage en review PR** : Murat (Test Architect) cite ce fichier pour fermer toute idée hors scope v1 qui tente d'entrer.
> **Décision OQ10 LOCKED** : ce markdown unique est l'unique source de vérité backlog post-v1. Pas de GitHub Issues miroir.

---

## Conventions

- **Une ligne H3 par item.** Titre clair, pas de jargon.
- **Phase cible** explicite : `v1.5` · `v2+` · `v3+ (SaaS)` · `Reporté indéfiniment`
- **Tier monétisation hypothétique** (uniquement si v3+ SaaS) : Gratuit forever · Freemium · Premium · Wedge marketing
- **Trigger d'activation** : ce qui doit se passer pour sortir du backlog (volume, demande, signal, etc.)
- **Effort estimé** : grossier (j-h ou j-équipe). Affiner uniquement quand l'item entre en scope sprint.

---

## v1.5 — Extensions naturelles post-MVP

### Clips MP4 auto-générés (yt-dlp + FFmpeg)

- **Phase cible** : v1.5
- **Tier v3** : **PREMIUM** ⭐ — wedge #1 monétisation (modèle Eklipse/OpusClip ~9€/mois)
- **Trigger** : 5+ reviews publiées avec VOD YouTube exploitable, demande explicite audience pour clips courts
- **Effort estimé** : ~5-7j (script extraction timecodes + FFmpeg pipeline + storage + Filament UI)
- **Pourquoi reporté v1** : complexité infra (storage MP4 = +40% volume backup), wedge SaaS — gardé pour différenciation premium

### Notifications Discord webhook

- **Phase cible** : v1.5
- **Tier v3** : Freemium
- **Trigger** : audience Discord active sur serveur Alex (> 100 membres), demande relais site → Discord
- **Effort estimé** : ~1j (config webhook + event listener Laravel sur Article published)
- **Pourquoi reporté v1** : v1 = focus stream-side discipline (cf. mitigation P2 PRD), pas push site-driven

### Caddy reverse proxy (au lieu d'Apache 2.4)

- **Phase cible** : v1.5
- **Tier v3** : —
- **Trigger** : besoin avéré HTTP/3 mesuré, re-architecture reverse proxy, ou volonté Alex d'apprendre Caddy
- **Effort estimé** : ~2j (rewrite Dockerfile + Caddyfile + tests SSL auto)
- **Pourquoi reporté v1** : ADR-0005 — Apache déjà en place, gain 2j scaffolding v1 prioritaire

### Auto-publication réseaux sociaux (Twitter/Mastodon/Bluesky)

- **Phase cible** : v1.5 ou jamais
- **Tier v3** : Freemium
- **Trigger** : régularité publication ≥ 4 articles/mois ET fatigue Alex du copier-coller manuel
- **Effort estimé** : ~3j (3 SDK API + scheduler + UI Filament queue + gestion erreurs auth tokens)
- **Pourquoi reporté v1** : brouillon copiable Filament suffit, et la nuance tonale humaine de chaque post réseau social bat un broadcast automatisé pour archétype Ponce

### Search interne reviews (Algolia / Meilisearch / Postgres FTS)

- **Phase cible** : v1.5 ou v2+
- **Tier v3** : Gratuit forever
- **Trigger** : > 30 articles publiés cumulés
- **Effort estimé** : ~2j (Meilisearch self-hosted recommandé — gratuit, simple) ou ~3j (Postgres FTS natif si on veut zéro container additionnel)
- **Pourquoi reporté v1** : volume 15 articles M+6 → Ctrl+F suffit. Activation triviale plus tard

---

## v2+ — Features substantielles

### Newsletter (Buttondown-style)

- **Phase cible** : v2+
- **Tier v3** : **Premium**
- **Trigger** : demande audience récurrente (> 50 abonnés capturés via formulaire intent), Alex prêt à investir dans un funnel email
- **Effort estimé** : ~7-10j (model + opt-in double + templates HTML + provider SMTP marketing distinct de transactionnel + désinscription RGPD + Filament UI)
- **Pourquoi reporté v1** : aucune demande validée audience actuelle, charge éditoriale supplémentaire qui peut casser cadence 3 articles/mois (cf. risque P1 PRD)

### Analytics propre stream (Helix sur ses propres streams)

- **Phase cible** : v2+
- **Tier v3** : Premium
- **Trigger** : Alex veut analyser son propre stream (heures de pointe, jeux les plus performants, etc.) ; pas avant
- **Effort estimé** : ~5j (intégration Helix API + sync nightly + Filament dashboard custom)
- **Pourquoi reporté v1** : pas un JTBD audience, pure intro analytique d'Alex

### Tags / catégories reviews

- **Phase cible** : v2+
- **Tier v3** : Gratuit forever
- **Trigger** : > 20 articles publiés ET besoin réel navigation par genre/plateforme
- **Effort estimé** : ~1-2j (model `Tag` + pivot + filtres index + URL `/reviews/tag/{slug}`)
- **Pourquoi reporté v1** : YAGNI pour 15 articles, ajoutable trivial sans breaking

### Multi-langue UI complet (au-delà bio EN)

- **Phase cible** : v2+
- **Tier v3** : Gratuit forever
- **Trigger** : audience EN > 20% trafic via Search Console (vraiment improbable v1)
- **Effort estimé** : ~5-8j (`laravel-localization` + extraction strings + traduction + URLs `/en/...`)
- **Pourquoi reporté v1** : audience FR primaire confirmée, bio EN suffit pour signaler ouverture internationale

### Modération avancée (Akismet / OpenAI)

- **Phase cible** : v2+ conditionnel
- **Tier v3** : Freemium
- **Trigger** : volume comments > 200/mois avec > 30% spam manuel observé
- **Effort estimé** : ~2j (Akismet plus simple) ou ~3j (OpenAI moderation API custom)
- **Pourquoi reporté v1** : 75 comments/mois projetés → modération manuelle Filament tient

### Backblaze B2 backup payant

- **Phase cible** : Activation à M+6
- **Tier v3** : —
- **Trigger** : premier streamer ami hébergé sur instance Alex OU volume données > 5 GB OU incident VPS qui pousse à reconsidérer
- **Effort estimé** : ~0.5j (rclone vers B2 + cron + monitoring)
- **Pourquoi reporté v1** : ADR-0003 — local + offsite gratuit suffit zéro-budget, B2 essentiel uniquement si hébergement tiers

---

## v3+ — Mode SaaS hypothétique (décision binaire M+18)

### Stripe + Cashier + plans Pennant

- **Phase cible** : v3+ (SaaS uniquement)
- **Tier v3** : Infrastructure (pas un module)
- **Trigger** : 3-5 streamers payants prêts à débourser (cf. land-and-expand M+12)
- **Effort estimé** : ~10-15j (Cashier setup + plans + webhooks + Pennant integration + Filament billing UI)
- **Pourquoi reporté indéfiniment v1/v1.5/v2** : décision binaire SaaS-product vs OSS-pur à M+18. Test Victor *"Si je ne fais jamais de SaaS, ce code est-il gaspillé ?"* — Stripe ne passe pas le test

### TenantManager + middleware multi-tenant unique app

- **Phase cible** : v3+ (SaaS uniquement)
- **Statut** : **REJETÉ — voir ADR-0001**
- **Trigger** : aucun — modèle SaaS retenu = "1 instance par streamer" (Plausible Cloud style), pas multi-tenant unique app
- **Pourquoi rejeté** : casse philosophie Plausible-style, complexifie le code pour valeur nulle si modèle hébergement individuel retenu

### MultiStreamer module

- **Phase cible** : v3+ (SaaS uniquement)
- **Statut** : "C'est le mode SaaS lui-même, pas un module"
- **Pourquoi pas un module** : si SaaS un jour, c'est de l'infrastructure (provisioning d'instances), pas une feature site

---

## Reporté indéfiniment / rejeté

### Scraping compétitif Twitch (analyse autres streamers)

- **Statut** : **REJETÉ v1 ET v2** — décision LOCKED roundtable §R4
- **Pourquoi** : risque légal (ToS Twitch + RGPD si données nominales), jamais sans revue légale écrite préalable
- **Trigger pour reconsidérer** : changement ToS Twitch + audit légal commissionné

### Métriques / idées stream basées sur d'autres streams

- **Statut** : **REJETÉ v2** — décision LOCKED roundtable §R4
- **Pourquoi** : pareil que scraping. Helix uniquement sur SES propres streams = OK (cf. v2+ Analytics propre stream)

### Photo Alex sur OG images

- **Statut** : **REJETÉ visuellement** — Caravaggio anti-pattern
- **Pourquoi** : "La review parle, pas le streamer" — cohérence archétype Ponce (qualité éditoriale > personnalité)

### Marketplace / panel admin de customisation

- **Statut** : **REJETÉ structurellement** — ADR-0001
- **Pourquoi** : refus modèle WordPress. Customisation via fork Git, pas via UI runtime

---

## Convention d'amendement

Pour ajouter un item :

1. Choisir la section (v1.5 / v2+ / v3+ / Rejeté)
2. H3 = titre court actionable
3. Renseigner phase cible, tier, trigger, effort estimé, raison report
4. Si l'item devient un ADR (rejeté structurellement) → cross-référencer l'ADR

Pour faire **sortir** un item du backlog vers un sprint :

1. Vérifier que le trigger est atteint (chiffres ou signal documenté)
2. Ouvrir mini-débat (PRD-edit ou ADR si structurant)
3. Si OK → déplacer l'item dans le PRD scope d'un sprint futur (+ supprimer du backlog)
4. Documenter la décision dans le commit message ou ADR

---

**Dernière mise à jour** : 2026-05-22 (initialisation post-PRD).
**Prochaine revue prévue** : fin S4 (mi-Phase 3) — audit scope creep + items qui pourraient remonter en v1.5.
