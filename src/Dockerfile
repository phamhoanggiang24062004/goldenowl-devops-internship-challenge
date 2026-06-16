FROM node:20-bookworm-slim AS base

ENV NODE_ENV=production

WORKDIR /app

FROM base AS deps

COPY package*.json ./
RUN npm ci --omit=dev --ignore-scripts \
    && npm cache clean --force

FROM gcr.io/distroless/nodejs20-debian12:nonroot AS production

ENV NODE_ENV=production

WORKDIR /app

COPY --from=deps --chown=65532:65532 /app/node_modules ./node_modules
COPY --chown=65532:65532 package*.json ./
COPY --chown=65532:65532 index.js ./
COPY --chown=65532:65532 routes ./routes
COPY --chown=65532:65532 server ./server

EXPOSE 3000

CMD ["index.js"]
