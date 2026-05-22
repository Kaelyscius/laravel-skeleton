# ADR-0001 — Modularité Plausible-style (refus du modèle WordPress)

> **Statut** : ✅ Accepted — 2026-05-08
> **Décideurs** : Alex (PO), Winston (architect), Victor (innovation strategist), Amelia (dev)
> **Source débat** : `docs/roundtable-decisions.md` §1.2, §3, mini-round Modularité (2026-05-08)

---

## Contexte

`myLaravelSkeleton` doit servir deux usages simultanés :
1. **Site personnel d'Alex** (streamer) — opinionated, taillé sur mesure
2. **Skeleton OSS-first MIT** — réutilisable par d'autres streamers via fork Git

Deux philosophies de modularité s'affrontaient :

| Modèle | Activation features | Customisation | Mode SaaS |
|---|---|---|---|
| **WordPress** | UI runtime (panel admin) | Settings tenant-scoped, marketplace plugins | Multi-tenant unique app |
| **Plausible** | ENV vars au déploiement | Fork Git, pas via UI | "1 instance par client", style cloud-hosted |

La décision est structurante : elle affecte la complexité scaffolding (~5-10h d'écart), les conventions code, le modèle économique v3 hypothétique, et l'identité produit.

> *"Je veux avoir mon site. À la base, je veux le faire que pour moi. Mais que ce soit possiblement fonctionnel pour un ou plusieurs autre streamer. Mais le but c'est que les modules soient activables ou non. Mais pas que ce soit aux autres de customiser. Je veux pas faire un wordpress bis."* — Alex, 2026-05-08

---

## Décision

**Adoption du modèle Plausible-style.**

Implications concrètes :

1. **Modules activables uniquement au déploiement** via variables d'environnement `MODULE_<NAME>_ENABLED=true|false`, lues par `config/modules.php` et appliquées dans `AppServiceProvider::register()`.
2. **Aucune UI runtime de toggle features** — pas de panel admin "activer/désactiver Reviews".
3. **Customisation par d'autres streamers = fork Git** — clone, édite, déploie. Pas de système de plugins, pas de marketplace, pas de settings tenant-scoped.
4. **Modèle SaaS v3 hypothétique = "1 instance par streamer"** (style Plausible Cloud) — pas un multi-tenant unique app où les utilisateurs customisent.
5. **Filament native tenancy reste OPTIONNELLE** — activable seulement si vrai multi-tenant SaaS un jour (v2+ ou v3+).
6. **Modules premium futurs (ex. Clips)** = paquets Composer payants ajoutés à l'instance du streamer (modèle GitLab CE/EE), **pas** un gating Pennant runtime.

---

## Conséquences

### Positives

- **Scaffolding S0 plus léger** : pas de Filament Modules panel UI, pas de tenant settings store, pas de plugin loader. **Gain ~5-10h.**
- **Mental model simple pour OSS forkers PHP/Laravel** : Laravel + service providers natifs, rien d'exotique à apprendre.
- **Code plus prévisible** : un module = un service provider chargé ou pas. Pas de logique de chargement dynamique d'extensions.
- **Cohérence avec l'archétype tonal Ponce** : preset fort, opinion claire, refus de la complexité prématurée.
- **Réponse à la question dévastatrice de Victor** ("Si dans 6 mois un streamer ami te demande une feature custom ?") = *"Tu lui dis non. C'est mon site. Tu fork si tu veux."*

### Négatives / acceptées

- **Pas de marketplace possible v3** — pas grave, ce n'est pas le pari.
- **Forker doit savoir éditer du PHP** — assumé, cible OSS PHP/Laravel.
- **Pas de "store" features** visible publiquement — le README + ADRs documentent quels modules existent et comment les activer.

### Tests / garde-fous

- Aucun route admin ne doit exposer un toggle de module
- CI bloque toute migration qui dépend d'un module non activé par défaut
- Test Pest fume : tous les modules activés par défaut (`true` dans `config/modules.php`) doivent répondre `200` sur leur route racine

---

## Référence débat complet

Voir `docs/roundtable-decisions.md` §1.2 (archétype produit) et mini-round Modularité du 2026-05-08 (Victor + Amelia + Winston).
