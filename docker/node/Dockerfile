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
FROM node:24.18.0-alpine3.23

# Arguments utilisateur
ARG UID=1000
ARG GID=1000

# Dépendances système
RUN apk add --no-cache \
  git \
  bash \
  python3 \
  make \
  g++ \
  shadow \
  curl

# Crée un utilisateur non-root
RUN addgroup -g ${GID} node || true && \
    adduser -D -u ${UID} -G node node || true

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
# compatible avec son propre runtime (11.16.0 pour node 24.18.0) — c'est la
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
