FROM node:20-alpine AS production

ENV NODE_ENV=production

WORKDIR /app

COPY package*.json ./
RUN npm ci 

COPY --chown=node:node . .

USER node

EXPOSE 3000

CMD ["node", "index.js"]
