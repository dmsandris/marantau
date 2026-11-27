# Workbench Marantau - image kecil. git dipakai untuk salinan repo (baca langsung, tanpa PR).
FROM node:22-alpine
RUN apk add --no-cache git
WORKDIR /app
ENV NODE_ENV=production HOME=/tmp
RUN mkdir -p /data && chown node:node /data
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund && npm cache clean --force
COPY server.js settings.js ai.js tools.js agents.js runner.js ./
COPY public ./public
# Tanpa docker.sock, tanpa akses tulis ke database. Jalan sebagai user biasa.
USER node
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD wget -qO- http://127.0.0.1:8080/healthz >/dev/null || exit 1
CMD ["node", "server.js"]
