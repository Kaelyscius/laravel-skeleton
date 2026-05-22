# 5. Architecture infra (Docker)

## 5.1 Profiles Docker Compose

| Profile | Services | Cible |
|---|---|---|
| (aucun) | apache, php, postgres, redis, postgres-pulse | **Production** |
| `dev` | + node, mailpit, adminer | Dev local |
| `tools` | + dozzle, it-tools, watchtower | Monitoring conteneurs |
| `dev-extra` | + phpmyadmin, redis-commander | Outils additionnels |

Commandes Makefile :
- `make up-prod` → production stricte
- `make up-dev` → dev minimal
- `make up-local` → tout (dev + tools + dev-extra)

## 5.2 Réseau interne Docker

```
       ┌─────────┐
       │ apache  │ :80 :443
       └────┬────┘
            │ FastCGI
       ┌────▼────┐    ┌──────────┐    ┌────────────────┐
       │   php   ├────► postgres │    │ postgres-pulse │
       │  (FPM)  │    └──────────┘    └────────────────┘
       └────┬────┘
            │
       ┌────▼────┐
       │  redis  │
       └─────────┘
```

Tous les services sur le réseau `bridge` interne. Seul `apache` expose `:80` et `:443` à l'hôte.

## 5.3 Conventions images Docker

- **Images custom (non Watchtower-managed)** : `php`, `apache`, `node` — build local, pinned Dockerfile
- **Images officielles (Watchtower auto-update)** : `postgres:17-alpine`, `redis:8.6-alpine`, `adminer`, `mailpit`, etc.
- Watchtower exclu des custom via label `com.centurylinklabs.watchtower.enable=false`

---
