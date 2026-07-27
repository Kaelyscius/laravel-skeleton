# Reprise — Story 1.9 (self-host IBM Plex Sans + Mono)

> Écrit le 2026-07-27 en fin de session. Point d'entrée pour reprendre.
> État du dépôt : **propre, tout poussé, HEAD = `495096c`**.

---

## Où on en est en une phrase

L'appareil de vérification du projet a été reconstruit et **les trois workflows
sont verts pour la première fois**. Aucune story d'Epic 1 n'a avancé : la
prochaine action est la **Story 1.9**.

## État vérifié

```
Laravel CI/CD Pipeline     success   Integrity · Quality · Tests (Pest × PostgreSQL 18) · Summary
Docker Build & Validation  success   Validation · php · apache · node · Integration
Security Audit             success

Local :  55 tests passed / 203 assertions · ECS 0 · PHPStan 9 (plafond ratchet)
         composer audit 0 · npm audit 0 · make test exit 0
```

Stack : PHP 8.5.8 · **Laravel 13.23** · **PostgreSQL 18.4** · Redis 8.8.1 ·
httpd 2.4.68 · Node 24.18 (LTS) · Livewire 4 · Tailwind 4 · Vite 8 · Pest 4.
Filament **v5** à installer en Story 1.10 (plus v3 — voir ADR-0010).

---

## LA PREMIÈRE CHOSE À FAIRE DEMAIN — le spike runner navigateur (~1 h)

La Story 1.9 ne doit **pas** être écrite avant. Raison, en une ligne : le seul
élément de preuve que les tokens CSS gouvernent le rendu est une lecture de
cascade sur du CSS compilé — **aucun navigateur n'a jamais affiché ce projet**.

Et la 1.9 touche exactement la variable à risque. `--font-sans` porte le même nom
que la variable de thème Tailwind qu'elle alimente, donc `@theme inline` émet
`--font-sans: var(--font-sans)`. Ça ne tient que parce que `tokens.css` est
importé **sans `layer()`**. Si l'ordre de cascade n'est pas celui supposé, la 1.9
sera livrée « verte » avec le navigateur servant la police système.

### Critères d'acceptation du spike, écrits À L'AVANCE

Le plugin browser de Pest 4 est retenu **si les quatre sont satisfaits** :

1. Il s'installe sur **PHP 8.5.8** sans conflit ni `--ignore-platform-reqs`.
2. Il pilote un navigateur **hors du conteneur php**, ou son coût reste confiné
   à un `Dockerfile.test` **sans toucher à l'image de production**.
3. Un test minimal passe : charger une page et lire
   `getComputedStyle(document.body).fontFamily`.
4. Le même test **échoue** quand on casse la source de la police (preuve de rouge).

**Sinon → Playwright TypeScript**, service Compose dédié, profil `test`, image
`mcr.microsoft.com/playwright` (aucun build : on tire), `ipc: host` obligatoire
sous peine d'OOM Chromium sur `/dev/shm`, et **version de l'image épinglée
exactement sur celle du package npm**.

Dans les deux cas : **un seul runner navigateur**, jamais deux.

Premier obstacle attendu : le vhost sert en **HTTPS auto-signé**, il faudra
`ignoreHTTPSErrors` ou viser le vhost HTTP interne.

---

## Puis la Story 1.9

Deux exigences non négociables, héritées de cette session :

- **Assertion sur valeur calculée, pas sur présence textuelle.** Vérifier que le
  `font-family` *résolu* contient IBM Plex, et que le `.woff2` est bien requêté
  depuis le domaine local (onglet réseau) — pas que la chaîne « IBM Plex »
  apparaît dans un fichier.
- **Ne JAMAIS passer de message à `toContain()`.** Il est variadique sur les
  *needles* : `->not->toContain('foo', 'msg')` nie « contient foo ET msg », donc
  passe toujours. Deux garde-fous de la 1.8 sont morts ainsi. Utiliser
  `str_contains()` + `toBeFalse($message)`.

**`max-w-prose` est banni par un test** (built-in Tailwind à 65ch,
non surchargeable). Le token `--max-prose` s'utilise via `max-w-measure`.

---

## Pièges armés pour les stories suivantes

- **Story 1.10 (Filament v5 + Sanctum)** — le `.gitignore` a été assaini
  (patterns ancrés + `scripts/assert-tracked-files.sh` en CI), donc le piège
  `*token*` est désamorcé. Mais **vérifier après installation** que
  `create_personal_access_tokens_table` et `PersonalAccessToken.php` sont bien
  suivis par git.
- **Story 1.11 (composants)** — Sally demande **3 écrans de référence**
  (live / article plein texte / offline mobile 375 px) AVANT les composants.
  Argument : le design system a été tokenisé sans qu'aucun écran n'existe ; une
  baseline visuelle démarrée sans référence gèlerait l'accident au lieu de
  garder l'intention.
- **Epic 4** — modèle de menace (2 pages) à écrire avant. Il conditionne
  l'arbitrage CSP × embed Twitch, sinon la CSP sera calibrée au moment où elle
  cassera l'embed, c'est-à-dire desserrée sous pression.

---

## Dette connue, non traitée

| Sujet | Détail |
|---|---|
| **Rector plante** | `Container::databasePath()`. Pas une régression de version (persiste en 2.5.8) : `src/rector.php:47` lie `phpstan.neon`, qui inclut l'extension Larastan, laquelle exige une app Laravel bootée. Rector est **informatif** en CI, donc non bloquant. |
| **Sémantique `/health`** | Trois définitions coexistent : route Laravel tenant-gated, `<Location /health>` Apache mod_status, et docs/installeur qui promettent du JSON Laravel. Le critère go/no-go S7 en dépend. → Epic 3. |
| **ADR-0004 non câblé** | `config/pulse.php` attend `PULSE_DB_CONNECTION`, jamais défini, et aucune connexion `pulse` n'existe dans `config/database.php`. Le conteneur `postgres-pulse` tourne pour rien. → Story 3.2 (déjà au backlog). |
| **PHPStan : 9 erreurs** | Toutes dans `config/*` (scaffolding vendor). Plafonnées par le ratchet, pas résorbées. |
| **`vite@latest webpack@latest`** | Même fragilité que le `npm@latest` corrigé : cible mouvante dans une image figée. Jamais atteinte jusqu'ici. `docker/node/Dockerfile`. |
| **docker.yml non épinglé par SHA** | `ci.yml` l'est, `docker.yml` non. Même argument supply chain. |
| **Node 26** | Ne PAS bumper avant le **2026-10-28** (LTS). Raisonnement complet en tête de `docker/node/Dockerfile`. |

---

## Outils installés cette session

```
gh          ~/.local/bin/gh        authentifié (scope `workflow` requis pour push .github/)
gitleaks    ~/.local/bin/gitleaks  8.30.1
```

Ajouter `~/.local/bin` au PATH si ce n'est pas déjà fait.

## Commandes utiles

```bash
make up-local              # démarrer la stack
make test                  # 55 tests, exit 0 attendu
make quality-ratchet       # plafond de dette — exit 0 attendu
make hooks-check           # hooks versionnés actifs ?
./scripts/assert-tracked-files.sh
gh run list --limit 5
```

## Documents de référence produits cette session

- `docs/adr/ADR-0010-...` — levée du verrou Laravel 12 / Filament v3
- `docs/adr/ADR-0007-...` — amendement PostgreSQL 18 (en fin de fichier)
- `_bmad-output/test-artifacts/test-design-{architecture,qa}.md` — stratégie de
  test système, 15 risques, ~118 scénarios
- `_bmad-output/test-artifacts/test-design/myLaravelSkeleton-handoff.md`
