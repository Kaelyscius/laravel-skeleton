# 🎯 BMAD Workflow — Coder via les skills BMAD

> Comment passer des décisions roundtable au code en prod, via les skills BMAD.

## 📚 Concepts BMAD

**BMAD** = **B**reakthrough **M**ethod for **A**gile **D**evelopment. C'est une méthodologie + un set d'agents IA spécialisés (skills Claude Code) pour piloter un projet logiciel de la conception au code.

**Agents principaux que tu utiliseras** :

| Agent | Skill | Rôle |
|---|---|---|
| 📋 John | `/bmad-agent-pm` | Product Manager — PRD, scope, JTBD |
| 🏗️ Winston | `/bmad-agent-architect` | Architecte — stack, frontières, contrats |
| 💻 Amelia | `/bmad-agent-dev` | Senior dev — implémentation |
| 🧪 Murat | `/bmad-tea` | Test architect — couverture, qualité, gates CI |
| 🎨 Sally | `/bmad-agent-ux-designer` | UX — scènes, frictions, motion |
| 🎬 Caravaggio | `/bmad-cis-agent-presentation-master` | Visual — direction artistique |
| 📊 Mary | `/bmad-agent-analyst` | Analyste business — pyramide Minto |
| ⚡ Victor | `/bmad-cis-agent-innovation-strategist` | Disruption oracle — wedges, business model |

## 🗺️ Workflow global du projet

```
┌─────────────────────────────────────────────────────────┐
│ Phase 0 — Formaliser (1-2h, à faire avant tout code)    │
│   1. Architecture officielle (Winston)                   │
│   2. Sharding du doc archi                              │
│   3. Epics + stories formalisés (John)                  │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ Phase 1 — Scaffolding S0 (~40h sur 4-5 jours)           │
│   Ticket P0 bloquant : "Scaffold modular architecture"  │
│   → app/Modules/* + Core/ + Pennant + tests             │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ Phase 2 — Refactor skeleton + Obs/CI (S-2 → S0, 12j)    │
│   Tickets Phase 1 + Phase 2 du backlog Round 4          │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ Phase 3 — Produit v1 (S1 → S6, 6 sem)                   │
│   Live → Auth admin → Reviews → Comments → SEO+Press    │
│   → Preview+Cookie consent → Polish                      │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ Phase 4 — Polish OSS (S7, 1 sem)                        │
│   README pro, ADRs, demo live, fichiers OSS              │
└─────────────────────────────────────────────────────────┘
                          ↓
                    🎉 v1 publique
```

## 🎬 Phase 0 — Formaliser

À faire **une seule fois** au démarrage, avant d'attaquer le code.

### Étape 1 — Architecture officielle (~30 min)

```
/bmad-agent-architect

Lis _bmad-output/planning-artifacts/roundtable-streamer-app.md.
Génère docs/architecture.md officiel basé sur toutes les décisions LOCKED
(stack, modularité Plausible-style, tenancy v1→v2+, backup, frontend Livewire, etc.).
Format BMAD architecture document standard.
```

**Output** : `docs/architecture.md` — doc architecture formel, format BMAD standard.

### Étape 2 — Sharding (~5 min)

```
/bmad-shard-doc docs/architecture.md
```

**Output** : Découpage en sous-docs digestes :
- `docs/architecture/stack.md`
- `docs/architecture/modularity.md`
- `docs/architecture/tenancy.md`
- etc.

### Étape 3 — Backlog formalisé (~30 min)

```
/bmad-agent-pm

Lis le backlog Round 4 dans _bmad-output/planning-artifacts/roundtable-streamer-app.md
(les ~50 tickets organisés en 4 phases).
Génère docs/epics/ et docs/stories/ formalisés BMAD.
Phases : 0 (S0 scaffolding) → 1 (refactor) → 2 (obs/CI) → 3 (v1 produit S1-S6) → 4 (OSS polish).
```

**Output** :
- `docs/epics/0001-scaffold-modular-architecture.md` (Phase 0)
- `docs/epics/0002-refactor-skeleton-install.md` (Phase 1)
- `docs/epics/0003-bootstrap-obs-ci.md` (Phase 2)
- `docs/epics/0004-v1-live-streaming.md` (Phase 3 / S1)
- `docs/epics/0005-v1-reviews-crud.md` (Phase 3 / S2-S3)
- `docs/epics/0006-v1-seo-press-kit.md` (Phase 3 / S4)
- `docs/epics/0007-v1-preview-cookie-consent.md` (Phase 3 / S5)
- `docs/epics/0008-v1-polish.md` (Phase 3 / S6)
- `docs/epics/0009-oss-release.md` (Phase 4)

Et les stories par epic dans `docs/stories/`.

## 🚀 Phase 1+ — Boucle dev quotidienne

Une fois la formalisation faite, ton workflow quotidien devient :

### Boucle standard

```bash
# Matin : choisir la story du jour
/bmad-help                                     # GPS BMAD : recommande quoi faire
# OU
/bmad-create-story                             # créer la prochaine story du sprint

# Coder
/bmad-dev-story docs/stories/XXXX-name.md      # impl rigoureuse
# OU
/bmad-quick-dev "implémente le ticket XYZ"     # impl rapide (couteau suisse)

# Review avant commit
/bmad-code-review                              # review adversariale en 3 layers

# Commit + PR
git add -A && git commit && git push
gh pr create
```

### Cas particuliers

| Situation | Skill |
|---|---|
| Tu hésites sur quoi faire ensuite | `/bmad-help` |
| Tu veux une review approfondie | `/bmad-code-review` |
| Une story devient hors scope v1 | `/bmad-correct-course` |
| Tu veux un avis sur une décision avant code | `/bmad-checkpoint-preview` |
| Bug subtil ou edge case que tu sens venir | `/bmad-review-edge-case-hunter` |
| Tests à designer pour une feature | `/bmad-testarch-test-design` |
| Tests à scaffolder Pest concrètement | `/bmad-testarch-automate` |
| Feature complexe à brainstormer | `/bmad-brainstorming` (Carson) |
| Doute sur une stratégie business | `/bmad-cis-agent-creative-problem-solver` (Dr. Quinn) |
| Fin d'epic, lessons learned | `/bmad-retrospective` |

## 📊 Sprint actuel à attaquer (état au 2026-05-08)

```
Sprint S0 — Scaffolding modulaire (~40h sur 4-5 jours)
─────────────────────────────────────────────────────
P0 Bloquant : Scaffold modular architecture (Core + 5 modules)
   ACs : voir backlog Round 4 dans roundtable-streamer-app.md
   Owner : Amelia (impl) + Winston (review archi)
```

**Commande pour démarrer** :

```
/bmad-create-story

Crée la story du ticket "Scaffold modular architecture (Core + 5 modules vides)"
identifié comme blocker-S1 dans le backlog R4. Estimation ~40h (25h back + 14.5h front + 0.5h buffer). ACs déjà définis.
```

Puis :

```
/bmad-dev-story docs/stories/0001-scaffold-modular-architecture.md
```

## 🔧 Skills par cas d'usage (référence rapide)

### Conception / Décision
- `/bmad-create-prd` — créer un PRD
- `/bmad-create-architecture` — architecture solution
- `/bmad-create-ux-design` — UX patterns
- `/bmad-brainstorming` — facilité ideation
- `/bmad-advanced-elicitation` — pousser une analyse plus loin (socratic, first principles, pre-mortem)
- `/bmad-validate-prd` — valider un PRD

### Backlog
- `/bmad-create-epics-and-stories` — décomposer en epics/stories
- `/bmad-create-story` — créer une story spécifique
- `/bmad-edit-prd` — éditer un PRD existant
- `/bmad-shard-doc` — découper un gros doc

### Code
- `/bmad-dev-story` — impl rigoureuse story par story
- `/bmad-quick-dev` — couteau suisse impl
- `/bmad-code-review` — review adversariale 3 layers
- `/bmad-review-edge-case-hunter` — chasse aux edge cases
- `/bmad-review-adversarial-general` — review cynique
- `/bmad-simplify` — simplifier code existant

### Tests / Qualité
- `/bmad-testarch-test-design` — plan de tests
- `/bmad-testarch-automate` — scaffolder les tests
- `/bmad-testarch-test-review` — review qualité tests
- `/bmad-testarch-trace` — matrice de traçabilité
- `/bmad-testarch-nfr` — NFR (perf, sécu, fiabilité)
- `/bmad-testarch-ci` — pipeline CI/CD
- `/bmad-testarch-framework` — initialiser Playwright/Cypress
- `/bmad-testarch-atdd` — TDD acceptance tests
- `/bmad-qa-generate-e2e-tests` — générer E2E auto

### Pilotage / Sprint
- `/bmad-sprint-planning` — générer sprint plan
- `/bmad-sprint-status` — état du sprint
- `/bmad-correct-course` — recadrer si dérive
- `/bmad-checkpoint-preview` — review humaine in-flight
- `/bmad-retrospective` — post-epic / fin de sprint
- `/bmad-check-implementation-readiness` — valider PRD/UX/Archi avant code

### Doc / OSS
- `/bmad-document-project` — doc projet brownfield
- `/bmad-generate-project-context` — context AI rules
- `/bmad-index-docs` — générer index.md d'un dossier
- `/bmad-distillator` — compression LLM-optimized
- `/bmad-editorial-review-prose` — review prose
- `/bmad-editorial-review-structure` — review structure

### Marketing / Produit
- `/bmad-market-research` — recherche marché/concurrence
- `/bmad-domain-research` — recherche domaine
- `/bmad-technical-research` — recherche technique
- `/bmad-product-brief` — brief produit
- `/bmad-prfaq` — Working Backwards Amazon
- `/bmad-cis-storytelling` — narratif produit
- `/bmad-cis-innovation-strategy` — stratégie disruption

### Méta
- `/bmad-help` — recommande la prochaine skill selon l'état
- `/bmad-customize` — overrides BMAD du projet
- `/bmad-bmb-setup` — setup BMad Builder

## 🎯 Plan minimaliste pour redémarrer demain

Si tu reviens demain et veux avancer :

```bash
# 1. Lance Claude Code
cd /home/alex/myLaravelSkeleton
claude

# 2. Reprends le contexte
"Lis _bmad-output/planning-artifacts/roundtable-streamer-app.md
et docs/roundtable-decisions.md pour le contexte. On est au sprint S0."

# 3. Formalise (Phase 0 si pas déjà fait)
/bmad-agent-architect → "génère docs/architecture.md"
/bmad-agent-pm → "génère docs/epics/ + stories/ depuis le backlog R4"

# 4. Attaque la 1ère story
/bmad-create-story (pour le ticket scaffold modular architecture)
/bmad-dev-story docs/stories/0001-*.md

# 5. Code → Review → Commit
/bmad-code-review
git add -A && git commit -m "feat(scaffold): modular architecture..."
```

## 🆘 Si tu te perds

```
/bmad-help
```

Cette skill analyse ton état actuel et te recommande la prochaine étape. C'est ton GPS BMAD.

## 📖 Référence

- **Décisions du projet** : [`../roundtable-decisions.md`](../roundtable-decisions.md)
- **Artefact roundtable complet** (privé, gitignored) : `_bmad-output/planning-artifacts/roundtable-streamer-app.md`
- **BMAD docs officielles** : https://bmad-method.com (vérifier l'URL)
