# Node 24 « Krypton » — ligne LTS ACTIVE, pas la version la plus haute.
#
# ⚠️ Ne pas bumper vers Node 26 avant le 2026-10-28. Vérifié sur le calendrier
# officiel (nodejs/Release) le 2026-07-27 :
#
#   v24  LTS depuis 2025-10-28 · Active jusqu'au 2026-10-20 · fin 2028-04-30
#   v26  sortie 2026-05-05 · Current, LTS seulement le 2026-10-28 · fin 2029-04-30
#   v25  jamais LTS, déjà morte (2026-06-01)
#
# « Le plus à jour possible » ne veut pas dire « la version la plus haute » :
# les majeures impaires ne deviennent jamais LTS, et les paires ne le
# deviennent qu'en octobre de leur année de sortie.
#
# Fenêtre de migration : les deux dates se croisent presque (24 quitte l'Active
# LTS le 20 octobre, 26 le devient le 28). C'est à ce moment-là qu'il faudra
# passer à Node 26, et pas avant.
# node 24.19.0 / alpine 3.23 — épinglé par digest (le tag reste mutable).
#
# ⚠️ Le numéro ci-dessus doit être VÉRIFIÉ dans l'image, pas recopié du tag :
#   docker compose run --rm node node --version
#
# Un tag de version exacte est *presque* immuable — et « presque » est
# exactement ce que l'épinglage par digest existe pour supprimer. php et apache
# appliquent la même règle (ADR-0007, § « Épinglage par digest »).
FROM node:26.7.0-alpine3.23@sha256:ce3cc39fe3b8b2602d3b1c4d63d301e46b48c550ecb627869853ddcdda418b63

# Arguments utilisateur
ARG UID=1000
ARG GID=1000

# Correctifs de sécurité de la distribution, appliqués à CHAQUE build.
#
# Pourquoi c'est nécessaire malgré une image de base épinglée : une image de
# base est figée à sa date de publication. Entre deux publications, Alpine
# corrige des CVE dans son dépôt, et l'image continue d'embarquer les paquets
# vulnérables. Constaté le 2026-07-27 via Snyk puis la base de sécurité Alpine :
#
#   libexpat  2.7.5-r0 installé  ->  2.8.2-r0 disponible   (15 CVE de retard,
#             dont CVE-2026-50219 Use-After-Free, CVSS 5.9)
#   libcurl   8.14.1-r2 installé ->  8.21.0-r0 disponible  (~30 CVE de retard)
#
# Arbitrage assumé : `apk upgrade` rend le build légèrement moins reproductible,
# puisque les paquets évoluent entre deux exécutions. C'est le bon compromis
# pour des correctifs de sécurité — la reproductibilité de la BASE reste
# assurée par l'épinglage par DIGEST du `FROM` ci-dessus, et l'alternative
# (rester sur des paquets vulnérables jusqu'à la prochaine publication amont)
# est pire.
#
# ⚠️ Cette phrase a été FAUSSE ici du 2026-07-27 au 2026-08-09 : elle avait été
# recopiée de php/apache, qui épinglent par digest, alors que ce fichier
# n'épinglait que par tag. Elle n'a de sens que tant que le `FROM` porte un
# `@sha256:` — si le digest disparaît, cette justification disparaît avec.
RUN apk upgrade --no-cache

# Dépendances système
RUN apk add --no-cache \
  git \
  bash \
  python3 \
  make \
  g++ \
  shadow \
  curl

# Ajuster UID et GID de `node` si besoin — MÊME MOTIF QUE L'IMAGE PHP.
#
# 🔴 LA RÉDACTION PRÉCÉDENTE ÉTAIT INERTE, ET ÇA A FINI PAR BLOQUER LE NIGHTLY.
# Elle faisait `addgroup … || true && adduser … || true`. Or l'utilisateur
# `node` EXISTE DÉJÀ dans `node:24-alpine`, en uid 1000 (mesuré) : les deux
# appels échouaient donc — « user already exists » — et le `|| true` avalait
# l'échec. L'argument `UID` était accepté, documenté… et ignoré.
#
# ⛔ CE QUE ÇA A COÛTÉ : run 32748093741, `npm-install` en erreur 243.
# `make npm-install` lance `docker exec -u $(DOCKER_USER)`, donc en 1001 sur un
# runner. Comme 1001 n'avait AUCUNE entrée `passwd` dans cette image, `HOME` se
# résolvait en `/`, npm se rabattait sur `/.npm` et ne pouvait pas l'écrire :
#   npm error path /.npm — errno -13 — Your cache folder contains root-owned files
# Le défaut n'est pas npm : c'est un uid sans identité dans l'image.
#
# ⚖️ ON REND DONC L'ARGUMENT AUTORITAIRE plutôt que de poser `HOME` ou
# `npm_config_cache` au point d'appel. Ce pansement-là aurait réglé npm et
# laissé tomber le prochain outil qui a besoin d'un `HOME` — après deux
# pansements contradictoires dans cette story, on traite la cause.
#
# ⚠️ `set -eux` : si `usermod` échoue, le BUILD échoue. Un uid demandé et non
# appliqué est exactement ce qu'on vient de payer ; il ne doit plus jamais
# passer en silence.
RUN set -eux; \
    existing_gid=$(getent group node | cut -d: -f3); \
    if [ "$existing_gid" != "$GID" ]; then groupmod -g "$GID" node; fi; \
    existing_uid=$(getent passwd node | cut -d: -f3); \
    if [ "$existing_uid" != "$UID" ]; then usermod -u "$UID" node; fi; \
    chown -R "$UID":"$GID" /home/node; \
    test "$(getent passwd node | cut -d: -f3)" = "$UID"; \
    test "$(stat -c %u /home/node)" = "$UID"
# ⛔ LA POST-CONDITION PORTE SUR LE PROPRIÉTAIRE, PAS SUR `test -w`.
# 🔴 Première rédaction : `test -w /home/node`. Les étapes de build tournent en
# ROOT, et root peut écrire partout — la vérification était donc VRAIE même avec
# un `/home/node` appartenant à root, c'est-à-dire dans le cas exact qu'elle
# prétendait interdire. Trouvé en rejouant la mutation « le HOME n'est plus
# rendu inscriptible », restée VERTE. On asserte la PROPRIÉTÉ, qui, elle, ne
# dépend pas de qui exécute le test.

# Active Corepack (pnpm, yarn) et met à jour les versions
RUN corepack enable && \
    corepack prepare pnpm@latest --activate && \
    corepack prepare yarn@stable --activate

# npm n'est PAS mis à jour ici, volontairement.
#
# La ligne `RUN npm install -g npm@latest` a cassé le workflow Docker Build :
# npm@latest est passé en 12.0.1, qui exige node ^22.22.2 || ^24.15.0 || >=26,
# alors que l'image épinglait 24.14.1 -> EBADENGINE, build en échec.
#
# Le problème n'est pas la version : c'est qu'une cible mouvante (@latest) dans
# une image figée finit toujours par diverger. L'image node embarque déjà un npm
# compatible avec son propre runtime (11.17.0 pour node 24.19.0, vérifié dans
# l'image et non recopié) — c'est la
# seule version dont la compatibilité est garantie. Pour monter npm, monter
# l'image de base.

# Installe les outils uniquement nécessaires (sans ceux gérés par corepack)
RUN npm install -g vite@latest webpack@latest webpack-cli@latest

# Crée le dossier de travail
RUN mkdir -p /var/www/html && chown -R node:node /var/www/html

WORKDIR /var/www/html

# Utilisateur non-root
USER node

# Commande par défaut (dev only)
CMD ["tail", "-f", "/dev/null"]
