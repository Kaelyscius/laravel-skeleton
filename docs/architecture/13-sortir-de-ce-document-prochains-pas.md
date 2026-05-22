# 13. Sortir de ce document — prochains pas

Une fois ce doc validé :

1. **`/bmad-shard-doc docs/architecture.md`** → éclate ce doc en `docs/architecture/{stack,modularity,tenancy,security,...}.md` pour consultation à la carte par les agents suivants
2. **`/bmad-agent-pm`** → génère `docs/epics/` + `docs/stories/` depuis le backlog R4 du roundtable + cette architecture
3. **`/bmad-check-implementation-readiness`** → vérifie alignement archi ↔ epics ↔ stories avant coder
4. **`/bmad-create-story`** sur la première story Phase 0 → **`/bmad-dev-story`** → **`/bmad-code-review`** → commit

---

**Dernière mise à jour** : 2026-05-22 (Phase 0 / formalisation Winston).
**Prochaine révision** : fin Phase 3 (S6) — bilan vs cible et amendements éventuels avant Phase 4 OSS.
