# ---------- Stage 1: build (all deps, compile TypeScript) ----------
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci --no-fund --no-audit
COPY tsconfig*.json server.ts ./
COPY src ./src
RUN npm run build

# ---------- Stage 2: production dependencies only ----------
FROM node:20-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev --no-fund --no-audit && npm cache clean --force

# ---------- Stage 3: runtime ----------
FROM node:20-alpine
ARG APP_VERSION=dev
ARG GIT_COMMIT=unknown
LABEL org.opencontainers.image.title="evat-api" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}"
ENV NODE_ENV=production \
    PORT=8080 \
    APP_VERSION=${APP_VERSION}
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY build ./dist/build
COPY package.json ./
# Hardening: npm/yarn/corepack are not needed at runtime. Removing them shrinks
# the attack surface and removes their bundled (often vulnerable) dependencies
# from the Trivy image scan.
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
           /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack /opt/yarn* \
           /usr/local/bin/yarn /usr/local/bin/yarnpkg
# swagger-jsdoc resolves ./src/routes relative to the working directory
WORKDIR /app/dist
USER node
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/health || exit 1
CMD ["node", "server.js"]
