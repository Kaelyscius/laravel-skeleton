# ADR-0005 — Apache 2.4 reste en v1, Caddy reporté v1.5

> **Statut** : ✅ Accepted — 2026-05-08
> **Décideurs** : Winston (architect), Amelia (dev), Alex (PO)
> **Source débat** : `docs/roundtable-decisions.md` R4 — 3 infra decisions Winston LOCKED-pending

---

## Contexte

Le skeleton hérité contient Apache 2.4 + Dockerfile maison + vhosts SSL fonctionnels. La tentation Caddy était :

| Critère | Apache 2.4 | Caddy v2 |
|---|---|---|
| Certificats SSL auto (Let's Encrypt) | Manuel via `certbot` | Automatique built-in |
| Config | `vhost.conf` verbeux | `Caddyfile` 10 lignes |
| HTTP/2, HTTP/3 | HTTP/2 ✅, HTTP/3 ❌ | HTTP/2 ✅, HTTP/3 ✅ |
| Reverse proxy | Verbeux | Trivial |
| Communauté écosystème Laravel | Énorme, références partout | Plus rare, exemples moins nombreux |
| Maintenance future | Standard sysadmin | Niche moderne |
| **Coût migration depuis skeleton actuel** | **0j** (déjà en place) | **~2j** (rewrite Dockerfile + vhosts + tests) |

En contexte 10-12 semaines solo, **2 jours sont non négligeables** sur le budget scaffolding.

---

## Décision

**Apache 2.4 reste en place pour v1.**

Caddy est **reporté à v1.5** au plus tôt, conditionné à au moins un des triggers suivants :

1. Besoin avéré HTTP/3 (e.g. perception perf réelle dégradée sur mobile)
2. Re-architecture reverse proxy (e.g. ajout API gateway, sous-domaines multiples)
3. Volonté Alex d'apprendre Caddy (curiosité, pas urgence)
4. Friction Apache avérée sur une feature concrète

Implémentation v1 :
- Conserver Dockerfile `docker/apache/Dockerfile` existant
- Conserver vhosts SSL `docker/apache/vhost.conf`
- Mise à jour template `docker/apache/vhost.conf.template` (variables ENV substituées au démarrage)
- Certbot via cron daily ou via script `scripts/ssl/renew.sh`

---

## Conséquences

### Positives

- **Gain 2j scaffolding** réinvestis dans Phase 0 / S0 (40h scaffolding modulaire = serré)
- **Continuité skeleton** : ce qui marche déjà reste en place
- **Documentation OSS** plus accessible aux forkers (Apache = lingua franca sysadmin)
- **Pas de friction** sur certbot + ngx-style proxies si jamais besoin demain
- **Décision réversible** : Caddy v1.5 reste un swap propre (Dockerfile uniquement, pas de couplage app)

### Négatives / acceptées

- **Pas de HTTP/3 v1** — impact perçu nul pour un site éditorial 1500 UU/mois cible M+6
- **Config verbeuse** à maintenir — mais déjà rédigée, coût marginal nul
- **Renouvellement SSL manuel** (certbot cron) vs automatique Caddy — script de renouvellement déjà prévu

### Tests / garde-fous

- Test Bats `tests/bats/apache-vhost.bats` vérifie que les vhosts sont chargés au démarrage du container
- Spatie Health check `HttpsCertificateExpiryCheck` (Phase 2 / S0) alert si certificat expire dans < 14 jours
- Documentation `docs/process/03-ssl-certs.md` (à créer Phase 2) couvre renouvellement + revocation

---

## Référence débat complet

- `docs/roundtable-decisions.md` R4 — 3 NEW infra decisions Winston LOCKED-pending (point 2)
- Stack technique LOCKED §2 : "Apache 2.4 (hérité skeleton, Caddy reporté v1.5)"
