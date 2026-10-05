FROM node:22-alpine

ENV NODE_ENV=production \
    PORT=4000 \
    UPLOAD_DIR=uploads

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY --chown=node:node src ./src
RUN mkdir -p uploads && chown node:node uploads

USER node

EXPOSE 4000

# Alpine ships busybox wget; shell form so ${PORT} is expanded at runtime.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -qO- "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1 || exit 1

# Run node directly (not via npm) so SIGTERM from `docker stop` reaches the app.
CMD ["node", "src/server.js"]
