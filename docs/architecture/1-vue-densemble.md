# 1. Vue d'ensemble

## 1.1 Mission produit

Site streamer personnel d'Alex (Twitch embed, blog reviews de jeux gifted, presse kit) **et** skeleton OSS-first MIT réutilisable par d'autres streamers via fork Git.

## 1.2 Archétype produit — Plausible-style

Preset fort, opinion claire. **Refus explicite** du modèle WordPress (panel admin de customisation runtime, marketplace plugins, settings tenant-scoped).

> Implications architecturales fortes (cf. **ADR-0001**) :
> - Modules activables au déploiement via ENV uniquement, jamais via UI runtime
> - Customisation par autres streamers = **fork Git**, pas via panel admin
> - SaaS v3 hypothétique = **1 instance par streamer** (Plausible Cloud style), pas multi-tenant unique

## 1.3 Périmètre v1 (LOCKED)

```
Phase 0 — Scaffolding modulaire (S0)            ~40h
Phase 1 — Refactor skeleton install (S-2/S-1)   ~10j
Phase 2 — Bootstrap obs/CI (S0)                 ~6j
Phase 3 — Produit v1 (S1 → S6)                  ~24j
Phase 4 — Polish OSS (S7)                       ~5j
─────────────────────────────────────────────────────
Total : ~55j sur 50j ouvrés → réalisme 11-12 sem
```

Toute idée hors scope v1 → `docs/backlog-v1.5-v2.md`. Mur scope creep tenu par Murat (Test Architect) en review PR.

---
