# backend/Dockerfile — Klasify sync API (Node.js)
FROM node:22-alpine

WORKDIR /app

# Install production dependencies first so this layer is cached: rebuilding
# after an API-code-only change skips the npm install step entirely.
COPY package.json ./
RUN npm install --omit=dev

COPY . .

# Listens on 80 inside the container; docker-compose maps host 8080 -> here.
EXPOSE 80

CMD ["node", "server.js"]
