# 📋 PRD — Site streamer Alex + Skeleton OSS (v1)

> **Statut** : Phase 2 — formalisation post-roundtable, prêt pour génération epics/stories.
> **Auteur** : John (Product Manager, session 2026-05-22).
> **Inputs verrouillés** : [`docs/roundtable-decisions.md`](roundtable-decisions.md) + [`docs/architecture/`](architecture/README.md) + [`docs/adr/`](adr/README.md).
> **Cible décision** : prête à produire `docs/epics/` + `docs/stories/` (skill `bmad-create-epics-and-stories`).
> **Format** : six-pager Bezos — narrative dense, pas de bullet-salad, chaque claim traçable.

---

## TL;DR

`myLaravelSkeleton` v1 livre **deux produits indissociables** en 10-12 semaines :

1. **Le site personnel d'Alex** — hub centralisé (live Twitch + reviews longues de jeux gifted + press kit) qui agrège son audience et capture la valeur d'un travail éditorial déjà honnête mais aujourd'hui dispersé (clips Twitch éphémères, descriptions YouTube non-indexables).
2. **Le skeleton OSS-first MIT** — base réutilisable par d'autres streamers via fork Git, qui dérisque un éventuel pivot SaaS v3 à coût marginal nul aujourd'hui (`streamer_id` partout, modules ENV-activables).

**Pari produit** : un preset Plausible-style (opinion claire, refus du WordPress runtime-customizable) battra un panel admin de configuration à la fois pour la maintenabilité d'Alex *et* pour la crédibilité OSS d'un fork PHP/Laravel pur.

**Métriques de succès M+6 (3 chiffres LOCKED)** : 1500 visiteurs uniques/mois · +200 followers Twitch attribués via UTM · 10-15 articles publiés.

---

## 1. Contexte & "Pourquoi maintenant"

### 1.1 Le problème observé

Alex streame depuis plusieurs années. Sa valeur éditoriale (analyses calmes, qualité > hype, audience qui lit) est aujourd'hui **dispersée et non-capitalisée** :

- Clips Twitch éphémères (disparaissent à J+14 sans abonnement payant)
- VODs YouTube avec descriptions plates non-indexables
- Aucun point de centralisation pour la presse / les devs / les nouveaux viewers
- Aucun signal SEO durable malgré un contenu de fond produit régulièrement

Conséquence : **l'audience qui découvre Alex via un stream isolé ne convertit pas en lecteur récurrent**, et les devs qui pourraient gifter (JTBD n°3) n'ont pas de portfolio scannable pour évaluer la légitimité éditoriale.

### 1.2 Pourquoi maintenant

Trois fenêtres convergent :
- **Écosystème Laravel** : Laravel 12 + Filament v3 + Livewire 3 stables, Pest 4 mature, Postgres 17 disponible. Stack qui sera ennuyeuse et fiable pendant 18 mois.
- **Marché clés gratuites** : Keymailer/Woovit/Lurkit acceptent les indés mid-tier avec un press kit crédible — fenêtre M+1 → M+6 où le ROI est maximal pour un nouveau site.
- **Capacité Alex** : fenêtre de focus 10-12 semaines validée, scope S1→S6 verrouillé, mur scope creep tenu par Murat en review PR.

### 1.3 Pourquoi ce pari (et pas un autre)

Trois choix structurants ont été pesés (cf. roundtable §1.2, ADR-0001) :

| Option | Verdict |
|---|---|
| WordPress + thème + plugins | ❌ Maintenance custom infernale, signal éditorial low-craft, dépendance plugins |
| Headless CMS (Strapi/Ghost) + Next.js | ❌ Stack non maîtrisée (Vue/TS = +60-75h apprentissage), segmente audience OSS |
| **Laravel custom modulaire (Plausible-style)** | ✅ Stack maîtrisée, opinion claire, OSS-friendly PHP/Laravel pur, fork-able |

---

## 2. Personas & Jobs-to-be-done

Quatre personas, deux primaires (qui pilotent les décisions scope), deux secondaires (qui contraignent les non-régressions).

### 2.1 Reader-Gamer (PRIMAIRE)

> **"Je veux comprendre si ce jeu vaut mes 60€ et mon temps, par quelqu'un qui ne hype pas."**

- **Profil** : 18-35, FR, joueur PC/console, fatigué du contenu YouTube short hype
- **Quand il arrive** : recherche Google sur `"[nom du jeu] avis"` ou `"[nom du jeu] vaut le coup"`
- **Ce qu'il attend** : article 800-1200 mots, note sur 10 visible, verdict clair en intro, VOD YouTube *complémentaire* (pas obligatoire), pas de cookie wall qui bloque la lecture
- **Friction qu'il refuse** : autoplay vidéo, popups newsletter, gradient violet startup tech, photo du streamer en above-the-fold
- **Métrique JTBD** : time-on-page > 3 min sur pages review, bounce < 60%

### 2.2 Twitch Viewer existant (PRIMAIRE)

> **"Je veux savoir si Alex stream là, et si oui rejoindre. Sinon, voir le dernier truc."**

- **Profil** : abonné Twitch Alex, vient en direct via lien profil ou bookmark
- **Quand il arrive** : home `/`, attend < 1s pour info LIVE/OFFLINE
- **Ce qu'il attend** : badge LIVE Lava si en stream + embed direct ; sinon dernier replay YouTube + dernière review
- **Friction qu'il refuse** : page qui charge en + de 1.5s mobile, status LIVE périmé (cache > 60s), navigation labyrinthique
- **Métrique JTBD** : conversion home → embed Twitch en live > 40%, conversion home → article récent en offline > 25%

### 2.3 Game Dev / PR studio (SECONDAIRE — wedge marketing)

> **"Cet Alex, il a une audience réelle ? Une ligne édito claire ? Je lui gifte ou pas ?"**

- **Profil** : community manager studio indé ou AAA mid-tier, scanne 20 portfolios/semaine via Keymailer
- **Quand il arrive** : `/press` direct depuis demande Keymailer ou DM Twitter
- **Ce qu'il attend** : stats live (viewers concurrents médiane P50, pas mean, pas followers — vanity), bio FR+EN, 3 reviews récentes visibles, contact direct, **PAS** de zip de logos (un dev sérieux veut le SVG seul)
- **Friction qu'il refuse** : stats invérifiables, zip impossible à dézipper en 10s avant un appel
- **Métrique JTBD** : downloads SVG individuels > 5/mois à partir de M+3, taux de réponse aux pitchs Keymailer > 15% à M+6

### 2.4 OSS Fork-Streamer (SECONDAIRE — pari long terme M+9+)

> **"Ce skeleton, je peux le forker en 30 min et le déployer en 1h sur mon VPS ?"**

- **Profil** : streamer indé tech-friendly qui code en PHP ou veut apprendre
- **Quand il arrive** : repo GitHub via partage Reddit/Discord ou via le bouton "fork this site" du site d'Alex
- **Ce qu'il attend** : README "front store" (screenshots + GIF demo + value prop), `make install-dev-full` qui fonctionne en < 15 min sur VPS vierge (test Bats), modules activables via ENV (pas via panel admin)
- **Friction qu'il refuse** : `composer install` qui casse, dépendances payantes en blocking, doc en franglais
- **Métrique JTBD** : 1er fork actif à M+6, 2-3 streamers hébergés gratos à M+9 (cf. land-and-expand)

---

## 3. Goals / Non-goals

### 3.1 Goals v1 (S1 → S6)

1. **Centraliser** la présence d'Alex (live + replays + reviews + press kit) sur un site qu'il contrôle
2. **Capitaliser** le contenu éditorial (SEO long-tail durable, page individuelle par review, schema.org indexable)
3. **Crédibiliser** auprès des devs PR (press kit pro, stats honnêtes, contact direct)
4. **Skelettiser** le code en OSS MIT exploitable (modulaire, doc, demo, Bats E2E install)
5. **Dérisquer** un pivot SaaS hypothétique v3 à coût nul aujourd'hui (`streamer_id` partout, Pennant J1)

### 3.2 Non-goals v1 (refus explicites)

Ces choses **n'arriveront pas dans v1**, et ce n'est ni un oubli ni un manque d'ambition. C'est une décision pour tenir le scope :

- ❌ **Marketplace de modules / panel admin tenant-scoped** (ADR-0001 : refus WordPress)
- ❌ **Multi-tenant unique app** (1 instance par streamer style Plausible Cloud si SaaS un jour — ADR-0002)
- ❌ **Clips MP4 générés automatiquement** (v1.5, wedge premium)
- ❌ **Newsletter** (v2+, premium)
- ❌ **Notifications Discord auto** (v1.5)
- ❌ **Analytics stream propre** (v2+ via Helix sur ses propres streams uniquement)
- ❌ **Auto-publication réseaux sociaux** (v1 = brouillon copiable depuis Filament)
- ❌ **Scraping compétitif Twitch** (jamais sans revue légale écrite)
- ❌ **Stripe / monétisation** (v3+ uniquement)
- ❌ **Modération IA (Akismet/OpenAI)** (v2+ — modération manuelle Filament suffit pour 10-15 articles/mois)

---

## 4. Métriques de succès

### 4.1 North star M+6 (LOCKED roundtable §1.2)

| Métrique | Cible | Source mesure |
|---|---|---|
| Visiteurs uniques uniques / mois | **1500** | Plausible self-hosted ou Pulse custom |
| Followers Twitch nouveaux attribués UTM | **+200** | UTM tracking Twitch Helix API (script S5) |
| Articles publiés cumulés | **10-15** | Compte direct table `reviews` |

### 4.2 JTBD-supporting metrics (déduites pour valider les JTBD)

| Persona | Métrique secondaire | Cible M+6 | Source |
|---|---|---|---|
| Reader-Gamer | Time-on-page reviews | > 3 min médiane | Plausible custom event |
| Reader-Gamer | Bounce rate reviews | < 60% | Plausible |
| Twitch Viewer | Conversion home → embed (en live) | > 40% | Custom event JS |
| Twitch Viewer | Conversion home → article (en offline) | > 25% | Custom event JS |
| Game Dev | Downloads SVG individuels press kit | > 5/mois (à partir de M+3) | Custom event JS |
| Game Dev | Keys reçues / pitchs envoyés (taux acceptation) | > 15% à M+6 | Tableur perso Alex (data manuelle) |
| Game Dev | Volume clés Keymailer (clés/mois) | 3 → 15 progressif M+1 → M+6 | Plateforme Keymailer |
| OSS | Premier fork actif | 1 minimum à M+6 | GitHub Insights |
| SEO global | 1 review page-1 Google long-tail | 1 minimum à M+6 | Google Search Console |

### 4.3 Métriques M+12 (signal pivot SaaS — pas un goal v1)

Ces métriques **ne sont pas des cibles**. Elles servent uniquement à informer la décision binaire SaaS-product vs OSS-pur de M+18 (cf. land-and-expand) :

- 2-3 streamers hébergés gratuitement à M+9
- 3-5 streamers à M+12, dont 1-2 prêts à payer
- 10-30 payants ou 0 à M+18 → décision binaire

---

## 5. Scope v1 — par sprint

### 5.1 Vue d'ensemble

Le scope est verrouillé sprint par sprint. **Toute idée hors scope → `docs/backlog-v1.5-v2.md`**, défendue par Murat en review PR. Aucune story ne peut entrer dans un sprint sans pointer vers une métrique JTBD ci-dessus.

| Sprint | Thème | Module(s) | Métrique JTBD adressée |
|---|---|---|---|
| **Phase 0 / S0** | Scaffolding modulaire | Core + skeleton tous modules | Aucune directement (pré-requis) |
| **Phase 1 / S-2→S-1** | Refactor installer | Scripts + Docker profiles | OSS fork (install < 15min) |
| **Phase 2 / S0** | Bootstrap obs/CI/backup | Observabilité + sécurité | Toutes (foundation) |
| **S1** | Live + Auth admin | Live + Admin | Twitch Viewer (badge LIVE) |
| **S2** | Reviews CRUD | Reviews + Admin | Reader-Gamer (publier reviews) |
| **S3** | Comments + modération | Reviews + Admin | Reader-Gamer (engagement) |
| **S4** | SEO base + Press Kit + ⭐OG dynamiques | Public + PressKit + Reviews | Game Dev (press kit), Reader-Gamer (SEO), tous (partage social) |
| **S5** | Preview + Cookie consent + UTM JTBD n°3 | Reviews + Admin | Game Dev (tracking UTM dev gifting), conformité |
| **S6** | Polish qualité (PHPStan L8 + Pest 70% + UI) | Tous | Tous (qualité ressentie) |
| **Phase 4 / S7** | Polish OSS | Doc + Demo + Bats E2E | OSS Fork-Streamer |

### 5.2 Détail thématique par module (vue produit, pas vue technique)

#### Module Public (homepage, about, layout, SEO base)

- **Homepage** : différenciation visuelle nette LIVE vs OFFLINE
  - LIVE : badge Lava `#FF5722` + embed Twitch + chat iframe + lien VODs récentes
  - OFFLINE : dernière review en vedette + 3 reviews récentes + dernier replay YouTube + lien press kit
- **About** : bio FR + EN, parcours streaming, valeurs éditoriales (Ponce-style explicite)
- **Layout** : header sticky discret (logo + Live status), footer minimal (légal + presse + RSS + GitHub)
- **Sitemap.xml + RSS** : générés automatiquement, mis à jour au publish d'une review
- **Schema.org** : `Person` (homepage), `Review` + `VideoGame` (page review), `Article` + `Person` (page about)

#### Module Live (Twitch embed + chat + offline + status)

- **Badge LIVE** : check Twitch Helix toutes les 60s côté serveur (cache Redis), affichage instantané côté client
- **Embed Twitch player + chat** : iframe officielles, cookie consent obligatoire pré-chargement (cf. §7 sécurité, ADR cookies)
- **Scène offline** : composant Blade qui affiche "Hors ligne, prochain stream estimé [si planifié]" + lien dernier replay
- **Status sidebar** : viewers concurrents si live, dernière VOD si offline

#### Module Reviews (CRUD + commentaires + YT VOD + news/previews)

> **Décision verrouillée OQ9** : modèle unique `Article` avec enum `type` (review|news|preview). Mix éditorial 70/30 LOCKED roundtable §3 stratégie contenu.

- **CRUD Filament admin** : `Article` model (titre, slug ASCII pur cf. OQ3, cover, note/10 *nullable si news/preview*, body Markdown, jeu lié *nullable*, vod_youtube_url *nullable*, type `enum: review|news|preview`, published_at)
- **YoutubeValidator** : avant publish, ping Helix API pour vérifier que la VOD existe (jamais de lien mort en prod)
- **Page review publique** : H1 + note visible + intro verdict + body + embed YT *petit* + timecodes inline cliquables `[00:42]`
- **Compteur vues** : visible sur page detail uniquement (seuil min 100 — anti-vanity Ponce), pas en index
- **Comments** : **utilisateurs anonymes uniquement** (nom + email + body — décision OQ1), **pas de captcha v1** (décision OQ2 — ajout réactif Cloudflare Turnstile si spam émerge), modération manuelle Filament (queue), ban manuel par IP, signalement utilisateur. Modale RGPD pour collecte email obligatoire pré-soumission.
- **Job nightly** : check disponibilité VOD YouTube (si supprimée → flag `vod_unavailable=true`, affichage gracieux)

#### Module PressKit (page presse + bio + contact)

- **Page `/press`** : Stats live (P50 viewers + heures stream total + nb VODs) > Photo > Bio FR + EN
- **Bio EN** : rédigée via Claude/ChatGPT + relecture Alex (décision OQ4) — workflow documenté `docs/process/04-bio-en-workflow.md` (à créer Phase 3)
- **Téléchargements** : SVG logo / PNG logo / kit complet — **chacun individuel**, pas de zip global
- **Contact** : formulaire simple (nom, mail, sujet, message) → email Alex via **Resend** (décision OQ8) + log Spatie ActivityLog

#### Module Admin (Filament panels)

- **Auth** : Laravel Sanctum + Spatie Permission
- **Roles v1** : `super-admin` (Alex) — un seul utilisateur réel v1
- **Resources Filament** : Reviews, Comments (modération), Games (catalogue référencé), Press contacts (lecture seule, audit)
- **Brouillon réseaux sociaux** (S5) : composant Filament qui génère un texte copy-pastable Twitter/Mastodon/Bluesky à partir d'une review (pas d'API auto-publish v1)

---

## 6. Hors scope explicite (anti-scope-creep)

Cette section existe pour **être citée en review PR** quand une idée pousse pour entrer en v1. Toute exception nécessite un mini-débat documenté.

| Item | Pourquoi reporté | Quand |
|---|---|---|
| Clips MP4 auto (yt-dlp + FFmpeg) | Complexité infra + wedge premium SaaS | v1.5 — premium |
| Newsletter (Buttondown-style) | Pas de demande validée audience actuelle | v2+ |
| Notifications Discord webhook | Stream-side, pas site-side | v1.5 |
| Analytics propre stream (Helix) | Pas un JTBD audience | v2+ |
| Auto-publication réseaux sociaux | Brouillon copiable suffit v1 | v1.5 ou jamais |
| Scraping compétitif Twitch | Risque légal, jamais sans revue écrite | v2+ conditionnel |
| Stripe / monétisation | v3+ SaaS uniquement | v3+ |
| Modération avancée Akismet/OpenAI | 10-15 articles/mois = volume manuel OK | v2+ |
| Caddy (au lieu d'Apache) | Gain 2j scaffolding > gain perceptible v1 (ADR-0005) | v1.5 |
| Backblaze B2 payant | Local + offsite gratuit suffit jusqu'à 1er streamer ami hébergé (ADR-0003) | M+6 |
| Search interne reviews | Volume 10-15 articles → Ctrl+F suffit | v2+ |
| Tags / catégories reviews | YAGNI pour 15 articles, ajoutable trivial | v2+ |
| Multi-langue UI complet (au-delà bio EN) | Audience FR uniquement v1 | v2+ |

---

## 7. Principes UX (cadre, pas spec — UX agent prendra le relais si besoin)

Le détail visuel est dans `docs/architecture/2-stack-technique.md` §2.5. Ici on liste les **règles de décision** UX :

1. **Discipline 90/8/2** — 90% mono / 8% accent Lava / 2% états (succès/warning/erreur). Lava réservé aux moments forts (badge LIVE, note 9+/10, CTA primaire, action destructive admin).
2. **Mobile-first contenu, pas mobile-first feature parity** — la page review doit être parfaite mobile (lecture longue) ; le panel admin peut être desktop-only.
3. **Pas de friction modale pré-lecture** — cookie consent oui (légal), newsletter no, autoplay no, popup no.
4. **Time-to-first-content < 1.5s sur mobile 4G** — implique pas de fonts blocking (preload IBM Plex), images lazy + webp, OG images pré-générées (pas Browsershot à la volée).
5. **Caravaggio veto** : pas de gradient Lava→noir background, pas de Geist font (signal Vercel pas IBM), pas de Lava en masse, pas de photo Alex sur OG images.
6. **Accessibilité minimum v1** : contraste WCAG AA (vérifiable via axe), navigation clavier, alt obligatoire sur images, focus ring visible.

---

## 8. Risques produit (différents des risques archi)

| # | Risque | Probabilité | Impact | Mitigation | Owner |
|---|---|---|---|---|---|
| P1 | Cadence éditoriale 3/mois pas tenue → ranking SEO mort | MOYENNE | ÉLEVÉ | Capital M0 = 3 articles publiés jour 1 ; checklist publication ; Murat flag scope creep si Alex code au lieu d'écrire | Alex |
| P2 | UTM Twitch unidirectionnel non-discipliné → +200 followers raté -60% | MOYENNE | ÉLEVÉ | Checklist stream-side obligatoire (panel Twitch + !commande + lower-third) — doc dédiée `docs/process/stream-discipline.md` | Alex |
| P3 | Press kit pas crédible à M+1 → Keymailer rejette | FAIBLE | MOYEN | 3 reviews publiées + bio FR+EN + stats P50 visibles dès M0 ; pitch templaté | Alex |
| P4 | Aucun streamer ami intéressé à M+6 → land-and-expand mort | MOYENNE | FAIBLE | OK — sortie OSS pure est un succès aussi (cf. test Victor : "If I never do SaaS, is this code wasted?" = non) | Alex |
| P5 | JTBD n°3 dev gifting non tracké → impossible de valider l'hypothèse | MOYENNE | MOYEN | UTM auto-généré sur bouton "copier le lien" S5 (~1h dev) | John |
| P6 | OG images génération lente bloque le publish | FAIBLE | FAIBLE | Job async + retry 3x + fallback OG statique | Sally / Winston |
| P7 | Reader-Gamer juge la note/10 "vanity" et perd confiance | FAIBLE | MOYEN | Verdict en intro doit justifier la note ; barre Lava 9+ seulement si vraie conviction | Alex |
| P8 | ~~Filament v3 deprecated par v4 pendant la fenêtre 10-12 sem~~ **CLOS 2026-07-27** | — | — | Risque éteint : Filament n'a jamais été installé, donc aucune migration à subir ; le projet passe directement en Filament v5 (Story 1.10) sur Laravel 13. Voir **ADR-0010** | Alex |

---

## 9. Dépendances & inputs verrouillés

Tous les éléments suivants sont **gravés** — ne pas re-débattre en review :

### 9.1 Décisions LOCKED (cf. `docs/roundtable-decisions.md`)

- ~~Stack : PHP 8.4 + Laravel 12 + PostgreSQL 17 + Filament v3 + Livewire 3 + Tailwind 4 + Pest 4~~
  **AMENDÉ 2026-07-27 — voir [ADR-0010](adr/ADR-0010-laravel-13-supersedes-filament-v3-lock.md).**
  Stack effective : **PHP 8.5 + Laravel 13 + PostgreSQL 18 + Filament v5 (Story 1.10) +
  Livewire 4 + Tailwind 4 + Pest 4**. Le verrou v12/Filament v3 supposait Filament installé et
  porteur ; il ne l'était pas (0 occurrence dans `composer.json`), et v3 est aujourd'hui deux
  majeures en retard. PostgreSQL 17 reste inchangé (ADR-0007).
- Modularité : Plausible-style — `app/Modules/*` PSR-4 + ENV vars (pas UI user) — **ADR-0001**
- Tenancy : `streamer_id` partout J1 + Eloquent Global Scope (RLS reportée v2+) — **ADR-0002**
- Backup : local quotidien + offsite hands-off gratuit — **ADR-0003**
- Frontend : Blade + Livewire 3 + Alpine, motion CSS pur 200ms
- Sécurité : 4 bloquants prod (Gitleaks + Pest OWASP A01-A04 + Cookie consent + Bats nightly)
- URL reviews : slug long éditorial `/reviews/{slug}`
- Cadence : 3 articles/mois steady, capital M0 = 3 articles publiés jour 1
- Plateformes : Keymailer M+1, Woovit/Lurkit M+2 staggered

### 9.2 Architecture (cf. `docs/architecture/`)

PRD délègue tout le "comment technique" à l'architecture. Le PRD garantit que **chaque scope item produit correspond à une section d'architecture identifiable** :

| Scope produit | Section architecture |
|---|---|
| Modules activables ENV | `3-architecture-applicative.md` §3.2 |
| Streamer model + tenancy | `3-architecture-applicative.md` §3.4 |
| Filament admin + Auth | `2-stack-technique.md` §2.2 |
| OG images pré-générées | `6-architecture-seo-marketing.md` §6.4 |
| Press kit page | `6-architecture-seo-marketing.md` §6.5 |
| Cookie consent | `7-architecture-scurit.md` §7.1 (bloquant #3) |
| Backup local + offsite | `8-architecture-backup-cf-adr-0003.md` |
| Qualité PHPStan L8 / Pest 70% | `9-architecture-qualit.md` §9.3 |

### 9.3 Process (cf. `docs/process/`)

- `01-getting-started.md` : setup machine + `make install-dev-full`
- `02-bmad-workflow.md` : workflow BMad complet (référence pour cycle story)
- À créer Phase 2 : `03-stream-discipline.md` (mitigation P2) + `04-publication-checklist.md` (mitigation P1)

---

## 10. Rollout & release strategy

### 10.1 Pas de release publique avant Phase 3 fin

- **Phase 0 + 1 + 2** : développement en local, repo privé GitHub
- **Fin S4** : déploiement staging (sous-domaine `staging.{domaine}`), accessible Alex + 2-3 testeurs amis (auth basic ou IP whitelist)
- **Fin S6** : déploiement prod, *site publiquement accessible mais pas annoncé*
- **Fin S7 (Phase 4)** : annonce publique
  - Tweet/Mastodon perso d'Alex
  - Post Reddit r/Twitch + r/PHP (skeleton OSS)
  - Repo GitHub passe public avec README "front store" + démo live
- **M+1** : inscription Keymailer
- **M+2** : inscription Woovit + Lurkit

### 10.2 Feature flags Pennant utilisés v1

Pennant est installé J1 (ADR scaffolding), utilisé pour **toggles dev solo** (déploiement code dormant), pas pour gating utilisateurs :

| Flag candidat v1 | Usage |
|---|---|
| `og-dynamic-pre-render` | Bascule entre génération job vs fallback OG statique (mitigation P6) |
| `comments-enabled` | Coupe globalement la modération si surcharge (mitigation surprise) |
| `youtube-helix-check` | Désactive le check VOD nightly si quota API dépassé |
| `keymailer-pitch-tracker` | Active le tracking acceptation pitchs (mesure JTBD §4.2) |

### 10.3 Critères go/no-go par sprint

Chaque sprint a un critère **go** chiffré (acceptance product, pas qualité technique) :

| Sprint | Critère go |
|---|---|
| S1 | Page home affiche LIVE/OFFLINE correctement en moins de 1s mesuré sur mobile 4G |
| S2 | Alex peut publier une review complète depuis Filament en moins de 10 minutes (workflow chronométré) |
| S3 | Un commentaire spam manuel est détecté et supprimé en moins de 3 clics |
| S4 | OG image générée et visible sur Twitter share validator pour 1 review publiée |
| S5 | UTM dev gifting trackable de bout en bout (test E2E avec faux UTM) |
| S6 | Lighthouse score > 90 sur homepage et 1 page review |
| S7 | `make install-dev-full` sur VPS vierge → `/health` 200 OK en < 15 min (Bats E2E) |

---

## 11. Décisions verrouillées post-élicitation (2026-05-22)

Les 10 questions ouvertes du PRD initial ont été tranchées en session avec Alex (John PM facilitator). **8 verrouillées maintenant, 2 reportées à Phase 2 kickoff** (dépendantes de réalité opérationnelle non encore connue).

### 11.1 LOCKED — applicables immédiatement

| # | Sujet | Décision LOCKED | Impact |
|---|---|---|---|
| OQ1 | Comments auth | **Anonymes uniquement** (nom + email + body) + modération manuelle Filament + ban IP + modale RGPD pré-soumission | S3 |
| OQ2 | Captcha v1 | **Pas de captcha v1**. Ajout réactif Cloudflare Turnstile si spam émerge (déclencheur : > 30% de comments en queue spam) | S3 |
| OQ3 | Slug format | **ASCII pur** (`elden-ring-2-mon-verdict`) — `Str::slug()` Laravel natif | S2 |
| OQ4 | Bio EN | **Claude/ChatGPT + relecture Alex** (~15 min). Workflow `docs/process/04-bio-en-workflow.md` à créer Phase 3 | S4 |
| OQ5 | OG image variantes | **3 variantes** (note ≥ 9 / note 7-8 / note ≤ 6) — déviation choisie par Alex vs reco template unique. Trade-off accepté : maintenance 3× pour expression visuelle différenciée. **Amendement archi requis** dans `docs/architecture/6-architecture-seo-marketing.md` §6.4 | S4 |
| OQ8 | SMTP outbound | **Resend** (free tier 100/jour) + driver Laravel natif. Pas de carte bancaire requise | S4 |
| OQ9 | Data model | **Modèle unique `Article`** avec enum `type` (review\|news\|preview). Champs `note`/`vod_youtube_url`/`game_id` nullable pour news/preview. 1 Filament resource | S2 |
| OQ10 | Backlog hors-scope | **`docs/backlog-v1.5-v2.md`** markdown unique. Alex maintient. Murat cite ce fichier en review PR pour fermer toute idée hors scope | Phase 0 / immédiat |

### 11.2 REPORTÉES — Phase 2 kickoff (advisory John session)

| # | Sujet | Statut | Action |
|---|---|---|---|
| OQ6 | Nom de domaine | **Non décidé** | Session conseil John avant Phase 2 / S0 obs/CI. Décision bloquante pour staging fin S4 (`staging.{domaine}`) |
| OQ7 | Hébergement VPS | **Non décidé** | Pas de VPS actif. Session conseil John avec comparatif chiffré (Hetzner / OVH / Scaleway) avant Phase 2 |

**Trigger session conseil** : avant kickoff Phase 2 (juste après scaffolding Phase 0 S0 finalisé). John prépare un comparatif domaines (naming OSS-friendly + pièges) + VPS (specs Hetzner CX22 4GB par défaut, alternatives FR si préférence souveraineté).

### 11.3 Nouvelles décisions structurantes — candidates ADR

Trois décisions OQ ont un poids architectural suffisant pour mériter un ADR documenté dans `docs/adr/` :

- **ADR-0007** (à créer) : Comments anonymes + modération manuelle — décision sécurité/UX
- **ADR-0008** (à créer) : Modèle unique `Article` avec enum `type` — décision structure données
- **ADR-0009** (à créer) : 3 variantes OG vs template unique — décision design system + maintenance

Ces ADRs sont **optionnels v1** (les décisions sont déjà tracées dans ce PRD §11.1) mais recommandés si l'une de ces décisions est challengée à un moment futur — l'ADR sert de référence stable.

---

## 12. Appendix — Liens

### 12.1 Inputs verrouillés (à charger en tête de contexte pour les agents suivants)

- [`docs/roundtable-decisions.md`](roundtable-decisions.md) — Single source of truth décisions LOCKED (417 lignes)
- [`docs/architecture/README.md`](architecture/README.md) — Index architecture shardée (14 sections)
- [`docs/adr/README.md`](adr/README.md) — Index ADRs (6 décisions structurantes)
- [`docs/process/02-bmad-workflow.md`](process/02-bmad-workflow.md) — Workflow BMad complet
- [`docs/process/01-getting-started.md`](process/01-getting-started.md) — Setup environnement

### 12.2 Sources externes citées

- Keymailer / Woovit / Lurkit — plateformes clés gratuites (cf. roundtable §SEO/Marketing)
- Plausible Cloud — modèle "1 instance par client" (cf. ADR-0001)
- Filament v3 docs (verrou écosystème jusqu'octobre 2026 — cf. ADR-0005 et roundtable §Stack)

### 12.3 Conventions traçabilité

- **Toute story** générée à partir de ce PRD doit citer :
  - 1 acceptance criterion lié à une métrique §4
  - 1 référence section archi §9.2
  - (optionnel) 1 ADR si la story touche une décision LOCKED
- **Tout PR de code** doit citer la story qu'il résout dans le titre/description
- **Toute exception au non-scope** (§6) doit déclencher un mini-debate documenté dans le PR ou un ADR si structurant

---

**Dernière mise à jour** : 2026-05-22 (Phase 2 / John).
**Prochain pas** : skill `bmad-create-epics-and-stories` (code menu `CE`) — génération `docs/epics/` + `docs/stories/` traçables vers ce PRD.
**Révision** : fin S4 (mi-Phase 3) — bilan acceptance criteria atteints vs prévisionnels, amendements éventuels avant S5-S6.
