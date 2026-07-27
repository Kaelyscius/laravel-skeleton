# ADR-0010 — Laravel 13 : levée du verrou « Laravel 12 + Filament v3 »

> **Statut** : ✅ Accepted — 2026-07-27
> **Décideurs** : Alex (PO), Murat (test architect)
> **Supersède** : PRD §9.1 (ligne « Stack : PHP 8.4 + Laravel 12 + … + Filament v3 ») et le risque P8 du PRD §8
> **Voir aussi** : [ADR-0007](ADR-0007-postgresql-17-over-mariadb.md), [ADR-0008](ADR-0008-frontend-stack-blade-livewire.md)

---

## Contexte

Le PRD §9.1 verrouille la stack en **PHP 8.4 + Laravel 12 + Filament v3**, et le risque P8
précise le raisonnement :

> « Filament v3 deprecated par v4 pendant la fenêtre 10-12 sem — Pin version exacte Composer ;
> re-évaluation L13/Filament v4 octobre 2026 (verrou consenti) »

Ce verrou reposait sur une prémisse : **Filament est installé et porteur**, donc une montée de
version majeure coûterait une migration risquée pendant une fenêtre de livraison contrainte.

Trois faits, vérifiés le 2026-07-27, invalident cette prémisse.

### 1. Filament n'est pas installé

`grep -c filament src/composer.json` → **0**. La Story 1.10
(`install-filament-v3-sanctum-spatie-permission`) n'a jamais démarré. Il n'y a rien à migrer :
le coût n'est pas élevé, il est **nul**.

### 2. La version verrouillée est deux majeures en retard

Filament stable est en **v5.7.3**. Le verrou protégeait une version (v3) que personne
n'installera jamais. Il ne réduisait plus aucun risque — il en créait un, en poussant vers une
version en fin de vie.

### 3. Laravel 13 et Filament 5 sont compatibles

Vérifié par le solveur Composer plutôt que supposé :

```
composer require --dry-run --with-all-dependencies 'laravel/framework:^13' 'filament/filament:^5'
  - Upgrading laravel/framework (v12.64.0 => v13.23.0)
  - Installing filament/filament (v5.7.3) + 9 paquets filament/*
```

Résolution propre, avec toute la stack existante (Horizon, Pulse, Telescope, Sanctum,
Nightwatch, Livewire 4, Larastan, spatie/*), sans conflit.

### 4. Le contexte projet a changé

L'échéance externe de 10-12 semaines qui motivait la prudence **n'existe plus** (décision PO du
2026-07-27 : projet personnel de long terme, priorité qualité/sécurité/DevSecOps). Le verrou
protégeait une fenêtre de livraison qui n'est plus contrainte.

---

## Décision

**Passer en Laravel 13 maintenant, et installer Filament en v5 lors de la Story 1.10.**

Le moment est le moins cher possible : `app/Modules/*` est encore vide, il n'existe aucun code
métier, donc le rayon d'impact d'une régression est minimal.

Stack effective après cette décision :

| Composant | Avant (PRD §9.1) | Après |
|---|---|---|
| PHP | 8.4 | **8.5** (`"php": "^8.5"`, runtime 8.5.4) |
| Laravel | 12 | **13.23.0** |
| Filament | v3 (à installer) | **v5** (à installer en Story 1.10) |
| PostgreSQL | 17 | 17 — inchangé (ADR-0007) |
| Livewire | 3 | **4** (déjà en place, tiré par la stack) |
| Tailwind / Pest | 4 / 4 | inchangés |

---

## Conséquences

### Positives

- **Zéro dette de version au démarrage du premier module.** Le projet aborde Epic 4 sur la
  version courante plutôt qu'avec deux majeures de retard à rattraper plus tard, au moment où
  du code métier existera.
- **21 advisories de sécurité résorbées** au passage (montée complète des dépendances) — dont
  une *high*. `composer audit` : 0.
- **Durcissements de sécurité Laravel 13 récupérés**, dont deux qui étaient silencieusement
  inactifs (voir ci-dessous).
- Front aligné dans le même mouvement : vite 8, laravel-vite-plugin 3, concurrently 10.

### Négatives / acceptées

- **La suite de tests ne prouve pas grand-chose sur cette montée.** Les 55 tests sont
  *structurels* (arborescence, `composer.json`, CI, tokens CSS), pas comportementaux. Ils ne
  détecteraient pas une rupture de comportement Laravel 13. Acceptable avec zéro code métier ;
  à ne pas confondre avec une validation.
- **Filament v5 n'a pas été audité fonctionnellement.** La compatibilité est établie au niveau
  du solveur de dépendances, pas de l'usage. La Story 1.10 devra le vérifier réellement.
- Laravel 13 étant récent, un package tiers de l'écosystème pourrait accuser du retard lors
  d'un ajout futur. Le risque est réel mais différé, et se constate au moment de l'ajout.

### Correctif de code induit

Laravel 13 rend `Illuminate\Database\Eloquent\Scope` générique.
`app/Core/Scopes/BelongsToStreamerScope.php` déclare désormais `@implements Scope<Model>`.
C'est le scope d'isolation tenant (ADR-0002), la pièce la plus sensible du projet : corrigé
plutôt que toléré.

### Découverte de sécurité — deux clés de configuration silencieusement absentes

La comparaison de notre squelette avec le squelette officiel Laravel 13 a révélé que
`config/session.php` et `config/cache.php`, hérités de v12, ne portaient pas deux clés
introduites en v13 :

| Clé | Fallback quand absente | Valeur du squelette v13 |
|---|---|---|
| `session.serialization` | **`'php'`** — `SessionManager::204` fait `config->get('session.serialization', 'php')` | `'json'` |
| `cache.serializable_classes` | `null` — aucune restriction | `false` |

Le premier cas n'est pas neutre : l'application tournait en **sérialisation PHP de session**,
c'est-à-dire le comportement exposé aux attaques par *gadget chain* si l'`APP_KEY` fuite, alors
que Laravel 13 livre `json` par défaut. Une montée de version qui ne recopie pas le squelette
hérite silencieusement de l'ancien comportement. Les deux clés sont désormais explicites et
commentées.

C'est une instance de plus du motif dominant du projet — un défaut qui ne produit aucun signal.

---

## Alternatives écartées

- **Attendre octobre 2026** (le calendrier initial) : le calendrier avait été fixé en fonction
  d'une fenêtre de livraison qui n'existe plus, et d'un coût de migration Filament qui n'existe
  pas. Attendre aurait signifié démarrer le premier module métier sur une version périmée.
- **Passer en Laravel 13 mais figer Filament v3** : incohérent, Filament v3 ne supporte pas
  Laravel 13 et n'est plus maintenu activement.

---

## Vérifications à la décision

```
Laravel                 13.23.0
composer outdated       All your direct dependencies are up to date
npm outdated            (vide)
check-platform-reqs     php 8.5.4 success, toutes extensions success
Tests                   55 passed / 203 assertions, exit 0
migrate:fresh --seed    OK (dont permission spatie v8, pulse)
ECS                     0
PHPStan L8              10
PHP Insights            exit 0
composer audit          0 advisory
npm audit               0 vulnérabilité
npm run build           OK
```
