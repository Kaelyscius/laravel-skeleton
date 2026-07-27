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
