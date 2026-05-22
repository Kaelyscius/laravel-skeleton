# ADR-0008 — Stack frontend : Blade + Livewire 3 + Alpine + Tailwind 4

> **Statut** : ✅ Accepted — 2026-05-08
> **Décideurs** : Sally (UX), Amelia (dev), Alex (PO)
> **Source débat** : `docs/roundtable-decisions.md` §2 (stack), §6 (direction visuelle), mini-round Frontend (2026-05-08)

---

## Contexte

Le choix de stack frontend public était ouvert après les rounds 1-3. Deux options sérieuses sur la table :

| Option | Stack | Coût scaffolding S0 | Coût apprentissage Alex |
|---|---|---|---|
| **A — Blade + Livewire 3 + Alpine + Tailwind 4** | full PHP, serveur d'abord | +14.5h | ~0h (Alex maîtrise déjà) |
| **B — Inertia.js + Vue 3 + TypeScript + Tailwind 4** | SPA-like, JS d'abord | +30.5h | +60-75h si niveau Vue/TS = 0 |

Sally avait initialement défendu (R2) une voie hybride **Motion One + Vue** pour les animations. Elle s'est rétractée au mini-round Frontend du 2026-05-08 après confrontation avec trois faits :

1. **Filament v3 admin = Livewire + Alpine sous le capot.** Choisir Vue pour le public = deux mental models, deux toolchains, deux écosystèmes JS dans le même repo. Coût cognitif permanent solo dev = très élevé.
2. **Archétype OSS Ponce + skeleton MIT** → audience cible = PHP/Laravel pur. Ajouter Vue+TS *segmente l'audience forkers* (~40% des dev PHP ne touchent pas Vue/TS).
3. **Motion 200ms `cubic-bezier(0.16, 1, 0.3, 1)`** se fait en CSS pur. Vue n'apporte aucune valeur ajoutée pour ce niveau d'animation — sur-équipement.

Amelia avait aussi mis dans la balance le coût scaffolding brut : **+14.5h vs +30.5h, soit +16h économisées** sur les 50j ouvrés du sprint (3% du budget total).

---

## Décision

**Adoption unanime (Sally + Amelia) de la stack A : Blade + Livewire 3 + Alpine + Tailwind 4.**

Composants concrets :

1. **Templates Blade** comme moteur de rendu principal — pas de SPA, pas d'hydration JSON.
2. **Livewire 3** pour les composants interactifs (formulaire commentaire, modale press kit, filtres reviews). Render server-side, diff DOM côté client.
3. **Alpine.js** pour le sucre client minimal (toggle menu mobile, dropdowns, tooltip). Inline dans Blade via `x-data`.
4. **Tailwind CSS 4** avec config minimaliste — tokens design depuis [`docs/roundtable-decisions.md`](../roundtable-decisions.md) §6 (Lava `#FF5722`, IBM Plex, motion 200ms).
5. **Aucune build chain JS lourde** — Vite uniquement pour Tailwind/Alpine bundle + assets static. Pas de Babel/TS/JSX/Vue.
6. **Pas de Motion One**, pas de framer-motion, pas de GSAP — motion via classes Tailwind + `transition` CSS.
7. **Filament v3 reste sur sa stack native** (Livewire+Alpine) — cohérence totale public/admin.

---

## Conséquences

### Positives

- **Un seul mental model** dans tout le repo : Blade rendering + Livewire pour l'interactif + Alpine pour le sucre. Audience OSS PHP/Laravel comprend tout en 30 minutes.
- **Cohérence admin/public** : Filament v3 = Livewire+Alpine. Pas de context-switch JS/PHP.
- **Scaffolding S0 économisé** : +14.5h vs +30.5h, gain net **16h**.
- **Apprentissage Vue/TS évité** : Alex avait estimé son niveau Vue/TS à zéro → 60-75h d'apprentissage économisées.
- **Signal OSS aligné archetype Ponce** : sobre, serveur-first, pas de hype JS.
- **Motion CSS pure** suffit pour le motion language `cubic-bezier(0.16, 1, 0.3, 1)` 200ms — aucun framework JS n'apporte de valeur à ce niveau.
- **SEO trivial** : tout est server-rendered, pas de problème d'indexation contenu JS.

### Négatives / acceptées

- **Pas de SPA feel** sur le site public — assumé. L'archétype Ponce = pas de fioritures, contenu d'abord.
- **Réutilisabilité composants** plus faible qu'avec Vue/React SFC — assumé, ce n'est pas une app interactive complexe.
- **Plafond d'interactivité** si un jour Alex veut un dashboard analytics riche côté public — accepté, ce n'est pas dans le scope v1/v1.5 (cf. modules futurs `docs/roundtable-decisions.md` §4).
- **Edge case réversion** : si Alex décide finalement de maîtriser Vue/TS *et* trouve Livewire frustrant en pratique sur les 2-3 premières stories, cette décision est révisable. Coût de bascule estimé à ~30-50h de refactor public-side (admin Filament reste intact).

### Tests / garde-fous

- `composer.json` ne doit pas inclure `inertiajs/inertia-laravel`.
- `package.json` ne doit pas inclure `vue`, `@vue/*`, `typescript`, `@types/*`, `motion`, `framer-motion`, `gsap`.
- Pest Browser tests valident le rendu server-side complet (HTML cohérent sans JS exécuté).
- ECS/Rector configurés sur Blade (pas de Vue SFC à parser).

---

## Référence débat complet

- `docs/roundtable-decisions.md` §2 (stack technique LOCKED, lignes Frontend public + Motion), §6 (direction visuelle), section "Frontend stack mini-round verdict (2026-05-08)".
- Mini-round Frontend 2026-05-08 (Sally + Amelia, Sally révise sa position R2 sur Motion One + Vue).
- ADR liés : [ADR-0001](ADR-0001-modularity-plausible-style.md) (modules PSR-4 = Blade + Livewire), [ADR-0009](ADR-0009-modular-app-modules-psr4.md) (structure code modules).
