FROM node:24-bookworm-slim AS base

ENV NODE_ENV=production

WORKDIR /app

FROM base AS deps

COPY package*.json ./
RUN npm ci --omit=dev --ignore-scripts \
    && npm cache clean --force

FROM node:24-bookworm-slim AS production

ENV NODE_ENV=production

WORKDIR /app

COPY --from=deps --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node package*.json ./
COPY --chown=node:node index.js ./
COPY --chown=node:node routes ./routes
COPY --chown=node:node server ./server

USER node

EXPOSE 3000

CMD ["node", "index.js"]
