# État du projet — 2026-07-30 (HEAD `647d276`)

> Point d'entrée de reprise. **Un seul fichier, écrasé à chaque session, jamais accumulé.**
> Il n'a aucune autorité : il pointe vers `epics.md` et `sprint-status.yaml`, jamais l'inverse.

---

## Où j'en suis

L'appareil de vérification est réparé — 3 workflows CI verts, 55 tests, ratchet ECS/PHPStan —
mais **aucun navigateur n'a jamais affiché ce projet**. Epic 1 : stories 1.1 → 1.8 `done`,
1.9 → 1.13 `backlog`, Epics 2 à 11 non démarrés.

Le roundtable du 2026-07-30 a **réordonné le reliquat d'Epic 1** et arbitré la conception de
l'écran offline : voir [ADR-0011](adr/ADR-0011-observation-avant-composition.md) et
[ADR-0012](adr/ADR-0012-ecran-offline-et-module-media.md). L'ancienne note `RESUME-1.9.md`
prescrivait une séquence désormais fausse : elle a été supprimée.

## Prochaine action

**Le spike runner navigateur.** Rien d'autre ne commence avant.

👉 **Protocole prêt à exécuter : [`docs/spike-runner-navigateur.md`](spike-runner-navigateur.md)**
— pré-vol déjà fait (PHP 8.5.4 ✅ · Pest 4.7.5 ✅ · `ext-sockets` ✅ · cible = plugin **v4.3.1**,
pas v5 qui exige Pest 5), assertion écrite, mutation de preuve-de-rouge écrite, plan B Playwright
prêt. Seul risque identifié au critère (1) : `symfony/process ^7.4` face à Laravel 13.

> ✅ **Débloqué le 2026-07-30.** Stack montée et vérifiée : 55 tests / 203 assertions exit 0 ·
> ratchet respecté (ECS 0/0, PHPStan 9/9) · apache `healthy` · `/up` 200 · **`/` sert une page
> réelle en 200**. Le navigateur a donc enfin quelque chose à charger — le spike peut partir.
>
> ⚠️ Deux pièges rencontrés au démarrage, à reproduire si ça recommence :
> 1. `/usr/bin/docker` est un lien vers `/mnt/wsl/docker-desktop/cli-tools/…`, **cible absente
>    tant que Docker Desktop ne tourne pas** côté Windows.
> 2. Des conteneurs créés lors d'une session antérieure et redémarrés après un redémarrage de
>    Docker Desktop peuvent avoir des **bind mounts vides** (`/var/www/html` sans `artisan`,
>    d'où `make test` → « Could not open input file: artisan »). Correctif : `make down` puis
>    `make up-local` — recréer, pas redémarrer.
> 3. **Base de dev non semée → `/` répond 404** (voir la dette ci-dessous). `php artisan db:seed`.

> ⛔ **À résoudre AVANT la Story 1.12** (trouvé par la passe de relecture des AC) :
> `livewire/livewire` n'est **pas** dans `src/composer.json` — il n'existe qu'en dépendance
> **transitive** (v4.3.3, tirée par Pulse / Telescope). `alpinejs` n'est déclaré nulle part.
> Or les Stories 1.11 et 1.12 en dépendent. Faire `composer require livewire/livewire:^4`
> explicitement et trancher le chargement d'Alpine.

Critères d'acceptation écrits à l'avance — plugin browser de Pest 4 retenu si les quatre sont
satisfaits : (1) installe sur PHP 8.5.8 sans `--ignore-platform-reqs` ; (2) pilote un navigateur
hors du conteneur `php`, ou coût confiné à un `Dockerfile.test` sans toucher l'image de prod ;
(3) un test minimal lit `getComputedStyle(document.body).fontFamily` ; (4) **le même test échoue
quand on casse la source de la police**. Le (4) est le seul qui compte.

Sinon → Playwright TS, service Compose profil `test`, image `mcr.microsoft.com/playwright`
tirée (pas buildée), `ipc: host` obligatoire, version épinglée sur le package npm.
**Un seul runner, jamais deux.** Le vhost sert en HTTPS auto-signé → `ignoreHTTPSErrors`.

*Critère d'abandon d'hypothèse* (pas un timebox — le temps n'est pas une contrainte de ce
projet) : deux contournements documentés sur Pest, puis bascule Playwright sans re-débat.

Puis, dans cet ordre : observer `MODULE_LIVE_ENABLED=false` → les 3 écrans de référence +
audit time-as-texture → passe de relecture des AC 1.9→1.13 → **1.11 → 1.12 → 1.13 → 1.9 →
1.10a**.

## Ce qui a changé depuis la dernière fois

- **Epic 1 réordonné.** L'AC3 de la Story 1.9 nommait `<x-layouts.public>`, créé par la
  Story 1.13 — AC sans référent, faux-vert garanti. La 1.13 citait réciproquement les preload
  fonts de la 1.9 : les deux se citaient mutuellement.
- **Story 1.10 scindée.** 1.10a (Filament v5 + Sanctum + Permission) reste en Epic 1, après la
  1.13. 1.10b (`SettingsResource`) part en Epic 5, auprès de son consommateur. `cta_text` /
  `cta_url` remontent en 1.11.
- **Écran offline conçu** (ADR-0012) : vignettes + liens sortants, **jamais d'embed** ; Twitch
  seul comme source d'API ; nouveau module `Media` ; PostgreSQL source de vérité, Redis cache ;
  le mot « Hors ligne » supprimé au profit de « Dernier stream il y a X ».
- **Le job de l'écran offline nommé par le PO** (ADR-0012 §1bis) : ni « convertir vers un
  article », ni « gagner des abonnés » — **prouver que ça vit**. Le contenu affiché date le
  projet. Conséquence : la **fraîcheur** prime sur l'exhaustivité ; un flux périmé dessert
  l'objectif et vaut mieux masqué.
- **YouTube retenu en principe, différé en implémentation** (§2bis) : seul réseau qui *notifie*
  au prochain live, donc seul cas où une sortie crée un canal de retour. **v1 = lien manuel,
  aucune clé API.** Instagram / TikTok / Twitter passent par `social_links[]` — **l'objectif
  « faire grandir les réseaux » ne requiert aucune API.**
- **Sortie ≠ retour** : `social_links[]` = sortie (profils) ; `discord_url` = retour, au rang du
  CTA, jamais dans la liste. Marqueur de source **textuel** sur les vignettes, jamais un logo de
  marque (problème juridique gratuit pour chaque forkeur).
- **NFR-Metric-7 (>25 %) reclassée en hypothèse datée** — plus un critère d'acceptation.
- **Audit time-as-texture avancé** de l'Epic 10 aux écrans de référence, coupe portée à −50 %.
- **`docs/RESUME-1.9.md` supprimé**, remplacé par ce fichier. Hiérarchie documentaire fixée :
  ADR > `epics.md` + `sprint-status.yaml` > `ETAT.md` > `roundtable-decisions.md` (aucune
  autorité). Règle : quand une décision contredit un document, on modifie le document **dans le
  même commit**.

## Passe de relecture des AC 1.9 → 1.13 — FAITE le 2026-07-30

Résultat : **5 `PROUVABLE`, 5 `SANS-RÉFÉRENT`, 4 `AMBIGU`**, plus un défaut transverse. Le détail
et les corrections sont dans `epics.md` (bloc en tête d'Epic 1 + notes `> Requalifié` par story).
Les trois trouvailles qui comptent :

1. **Livewire n'est pas une dépendance déclarée** — voir ci-dessus. Une affirmation
   d'architecture (`CLAUDE.md`, ADR-0008) sans référent dans le manifeste : forme nouvelle du
   motif dominant.
2. **La dépendance circulaire s'est retournée, pas éteinte.** La 1.13 cite désormais les preload
   fonts de la 1.9. Inoffensif cette fois (un layout peut naître sans preload), mais l'AC devait
   le dire — sinon il se valide sur un `<head>` vide.
3. **Contradiction sur `--accent-lava`** : l'AC de la 1.11 dit « réservé LIVE uniquement »,
   `tokens.css` RÈGLE 2 (Story 1.8, `done`) dit « exactement 4 usages ». Le token fait foi.

**Et une conclusion de séquence** : 7 AC sur 14 exigent une **valeur calculée**. Le spike ne
conditionne pas la seule Story 1.9 — il conditionne la moitié du reliquat d'Epic 1.

## Ce que je vais oublier

- **`toContain()` de Pest est variadique sur les needles.** `->not->toContain('foo', 'msg')` nie
  « contient foo ET msg » → **passe toujours**. Deux garde-fous de la 1.8 sont morts ainsi.
  Utiliser `str_contains()` + `toBeFalse($message)`.
- **`--font-sans` porte le même nom que la variable de thème Tailwind qu'elle alimente** →
  `@theme inline` émet `--font-sans: var(--font-sans)`. Ça ne tient que parce que `tokens.css`
  est importé **sans `layer()`**. Si le spike révèle un autre ordre de cascade, c'est un bug de
  la Story 1.8, pas un ajustement de la 1.9.
- **`max-w-prose` est banni par un test** (built-in Tailwind à 65ch, non surchargeable) →
  utiliser `max-w-measure`, alimenté par le token `--max-prose`.
- **Definition-of-ready** : une story ne passe `backlog` → `in-progress` que si chaque nom cité
  dans ses AC résout vers un chemin existant ou une story `done`.
- **Critère de sortie front** : un test qui ne peut pas rougir en cassant ce qu'il teste n'est
  pas un test. Le rouge doit être **observé**, pas supposé.
- **`MODULE_*_ENABLED=false` n'a jamais été exécuté ni observé**, alors que la Story 1.7 est
  `done` et que c'est la promesse centrale du produit.
  `src/tests/Feature/ModuleActivationTest.php` existe — reste à établir s'il peut rougir.
- **Node 26 : ne pas bumper avant le 2026-10-28** (LTS). Raisonnement en tête de
  `docker/node/Dockerfile`.
- `~/.local/bin` doit être dans le `PATH` (`gh`, `gitleaks`).

## Dette connue, non traitée

| Sujet | Détail |
|---|---|
| **Rector plante** | `Container::databasePath()`. Pas une régression de version : `src/rector.php:47` lie `phpstan.neon`, qui inclut l'extension Larastan, laquelle exige une app Laravel bootée. Rector est **informatif** en CI, donc non bloquant. |
| **Sémantique `/health`** | Trois définitions coexistent : route Laravel tenant-gated, `<Location /health>` Apache mod_status, et docs/installeur qui promettent du JSON Laravel. Le critère go/no-go S7 en dépend. → Epic 3. |
| **ADR-0004 non câblé** | `config/pulse.php` attend `PULSE_DB_CONNECTION`, jamais défini, et aucune connexion `pulse` n'existe dans `config/database.php`. Le conteneur `postgres-pulse` tourne pour rien. → Story 3.2. |
| **PHPStan : 9 erreurs** | Toutes dans `config/*` (scaffolding vendor). Plafonnées par le ratchet, pas résorbées. |
| **`vite@latest webpack@latest`** | Cible mouvante dans une image figée — même fragilité que le `npm@latest` déjà corrigé. `docker/node/Dockerfile`. |
| **Node dans l'image PHP de production** | `docker/php/Dockerfile:44` installe `nodejs` → binaire de 55 Mo embarqué dans l'image de prod. Surface d'attaque et poids non justifiés côté runtime PHP. Reliquat ou besoin réel de build ? Trouvé le 2026-07-31. |
| **Dérive Node entre conteneurs** | Image PHP = **v22.22.2**, conteneur `node` = **v24.18** (LTS épinglé). Deux runtimes Node dans la même stack, à deux majeures d'écart. |
| **`docker.yml` non épinglé par SHA** | `ci.yml` l'est, `docker.yml` non. Même argument supply chain. |
| 🔴 **`SetCurrentStreamer` : « fail-loud » qui échoue en silence** | `firstOrFail()` lève `ModelNotFoundException` → Laravel rend **404**, indiscernable d'une page inexistante. Le docblock du middleware promet pourtant « an explicit error rather than a silent empty tenant ». Vérifié par mutation : base vide → `/` = 404 ; après `db:seed` → 200. Aucun test ne l'attrape (tous sèment avant). En prod : site entier en 404 silencieux si la base n'est pas semée. Détail + piste de correction dans `deferred-work.md`. |
| **CSP non configurée** | `spatie/laravel-csp` installé, jamais paramétré. Modèle de menace (2 pages) à écrire avant l'Epic 4 — sinon la CSP sera calibrée au moment où elle cassera l'embed Twitch, c'est-à-dire desserrée sous pression. |
| **`_bmad-output/` n'est ni versionné ni sauvegardé** | Gitignoré volontairement (`.gitignore:219`) — décision PO du 2026-07-30 : le dépôt est **public**, le planning ne doit pas l'être. Mais `scripts/ops/backup-local.sh` ne fait qu'un `pg_dump` : **le plan-of-record (epics.md, sprint-status.yaml, deferred-work.md, stories) n'existe qu'à un seul endroit, sur le disque.** Un plan sans référent durable, c'est le motif du projet appliqué à lui-même. Options : dépôt git privé séparé, ou élargir le périmètre de `backup-local.sh`. Non tranché. |
| **À vérifier avant story (ADR-0012)** | Quotas YouTube Data API v3 en 2026 · conditions d'utilisation sur le rehosting des miniatures · état réel des API Instagram / TikTok. Marqués « non vérifiés » dans l'ADR plutôt qu'affirmés. |

## Commandes utiles

```bash
make up-local              # démarrer la stack
make test                  # 55 tests, exit 0 attendu
make quality-ratchet       # plafond de dette — exit 0 attendu
make hooks-check           # hooks versionnés actifs ?
./scripts/assert-tracked-files.sh
gh run list --limit 5
```
