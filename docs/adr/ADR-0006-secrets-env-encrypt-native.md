# ADR-0006 — Secrets via `php artisan env:encrypt` natif (pas Doppler/Vault)

> **Statut** : ✅ Accepted — 2026-05-08
> **Décideurs** : Winston (architect), Alex (PO)
> **Source débat** : `docs/roundtable-decisions.md` R4 — 3 infra decisions Winston LOCKED-pending

---

## Contexte

Gestion des secrets en v1 : DB password, API keys (Twitch Helix, Sentry DSN prod, SMTP), `APP_KEY`, etc. Trois familles de solutions :

| Solution | Coût | Effort intégration | Bénéfice |
|---|---|---|---|
| **`.env` en clair + `.gitignore`** | 0€ | 0 | Démarrage trivial, fragile (oubli accidentel commit) |
| **`php artisan env:encrypt` natif Laravel 12** | 0€ | ~30 min | Fichier `.env.encrypted` committé safely, déchiffré au démarrage avec clé hors repo |
| **Doppler / Vault / AWS Secrets Manager** | Payant (Doppler) ou complexe (Vault self-host) | ~4-8h scaffolding + rotation keys | Pro-grade, multi-env, audit, RBAC, rotation auto |

Pour un solo dev v1, zéro budget, environnement unique (`prod` + `dev` séparés via différents `.env`), **Doppler/Vault est over-engineering**.

---

## Décision

**Adoption de `php artisan env:encrypt` natif Laravel 12.**

Workflow opérationnel :

1. **Développement local** : `.env` en clair (gitignored), workflow standard
2. **Production** :
   - Création locale : `php artisan env:encrypt --env=production --key=<32-char-key>`
   - Génère `.env.production.encrypted` → **committable** dans le repo
   - La clé `<32-char-key>` est stockée **hors repo** :
     - En variable d'environnement sur le serveur (`LARAVEL_ENV_ENCRYPTION_KEY`)
     - Sauvegardée dans un password manager personnel d'Alex (1Password, Bitwarden, KeePassXC)
3. **Déploiement** : `php artisan env:decrypt --env=production --key=$LARAVEL_ENV_ENCRYPTION_KEY` lors du provisioning
4. **Rotation** : `php artisan env:encrypt --env=production --key=<new-key>` re-chiffre avec nouvelle clé. Ancienne clé révoquée du password manager.

---

## Conséquences

### Positives

- **0€ coût** infra secrets
- **Pas de service tiers** à monitorer ou rate-limiter
- **`.env.production.encrypted` committable** → repo OSS reste utilisable sans fuir les secrets prod d'Alex
- **Workflow OSS-friendly** : un forker met sa propre clé, ses propres secrets, son propre `.env.encrypted`
- **Compatible CI** : la clé est une env var GitHub Actions secret, déchiffrement avant deploy
- **Aligné Laravel 12** : feature first-class, documentée, supportée long terme

### Négatives / acceptées

- **Rotation manuelle** : pas de rotation auto (acceptable pour solo dev v1)
- **Pas d'audit log** d'accès secrets : qui a lu quoi quand → invisible (mais Alex est seul accédant)
- **Si Alex perd la clé** : tous les secrets prod inaccessibles → procédure recovery documentée (`docs/process/secrets-recovery.md` à créer Phase 2)
- **Pas de RBAC** : la clé donne accès à tous les secrets — acceptable solo, pas extensible à équipe

### Tests / garde-fous

- Test Bats `tests/bats/secrets-encryption.bats` : vérifie que `.env.production` n'est PAS committé en clair (grep `.env.production` exclu du staging)
- Pre-commit hook Gitleaks (cf. ADR sécurité #1) : bloque tout secret en clair même en debug
- Documentation `docs/process/secrets-management.md` (Phase 2 / S0) couvre :
  - Génération clé initiale
  - Stockage password manager
  - Rotation procédure
  - Recovery procédure (si clé perdue)
- Test Pest `tests/Security/SecretsTest.php` : vérifie qu'aucune clé en clair n'est lisible dans `config/*.php` après publish

### Trigger upgrade Doppler/Vault

Migrer vers Doppler ou Vault si **un des triggers** se déclenche :

1. Équipe > 2 personnes accédant aux secrets
2. Compliance RGPD/SOC2 demandée par un client
3. Multi-environnement (dev/staging/prod/preview) avec rotation indépendante
4. Activation v3 SaaS (multi-streamer hébergé = multi-secrets-set)

---

## Référence débat complet

- `docs/roundtable-decisions.md` R4 — 3 NEW infra decisions Winston LOCKED-pending (point 3)
- Stack technique LOCKED §7.4 : "`php artisan env:encrypt` natif Laravel 12"
