# Panel Ops Marantau - image kecil, tanpa build step.
FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund && npm cache clean --force
COPY server.js eko.js audit.js iluminaty.js aliran.js settings.js penjaga.js bot.js ./
COPY public ./public
# Root diperlukan untuk membaca docker.sock (milik grup docker di host). Tetap read-only rootfs di compose.
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD wget -qO- http://127.0.0.1:8080/healthz >/dev/null || exit 1
CMD ["node", "server.js"]
