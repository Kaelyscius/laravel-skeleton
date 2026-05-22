# 12. Risques architecturaux flaggés (à monitorer)

| Risque | Détecté par | Mitigation | Owner |
|---|---|---|---|
| Couplage inter-modules direct (au lieu d'events) | Code review systématique S3-S5 | Acceptable v1, refactor en events v1.5 si > 3 cas | Winston |
| `streamer_id` oublié dans une migration | Test Pest scan migrations | Test bloquant CI dès S0 | Murat |
| RLS naïf si activé prématurément | ADR-0002 + doc | Pattern D documenté à part, NE PAS activer avant audit Filament v3 tenancy | Winston |
| Pulse DB sature le disque VPS | Spatie Health check DiskSpace | Rotation Pulse 7j max + alert Discord à 80% | Murat |
| OG image génération lente bloque publish | Job async + retry 3x + fallback OG statique | Acceptable — fallback en place dès S4 | Sally |
| Backup offsite jamais activé | Pas de surveillance automatique | À M+6, hard-stop avant 1er streamer ami hébergé | Alex |
| Pennant tables grossissent si flag-fest | Pas v1 — < 10 flags prévus | Audit S6 si > 20 flags | Winston |
| PostgreSQL 17 trop récent en prod hosting | Vérifier dispo image Alpine stable | Fallback Postgres 16 si bloquant | Amelia |

---
