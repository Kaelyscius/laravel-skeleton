FROM node:24-alpine

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

# Met à jour npm (ok car inclus par défaut)
RUN npm install -g npm@latest

# Installe les outils uniquement nécessaires (sans ceux gérés par corepack)
RUN npm install -g vite@latest webpack@latest webpack-cli@latest

# Crée le dossier de travail
RUN mkdir -p /var/www/html && chown -R node:node /var/www/html

WORKDIR /var/www/html

# Utilisateur non-root
USER node

# Commande par défaut (dev only)
CMD ["tail", "-f", "/dev/null"]
