FROM node:22-bookworm

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /app

ARG OPENCLAW_DOCKER_APT_PACKAGES=""
RUN if [ -n "$OPENCLAW_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $OPENCLAW_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

RUN pnpm install --frozen-lockfile

COPY . .
RUN OPENCLAW_A2UI_SKIP_MISSING=1 pnpm build
# Force pnpm for UI build (Bun may fail on ARM/Synology architectures)
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

ENV NODE_ENV=production

# Memory optimization for Railway's limited container resources
# Skip channel initialization on startup - users can enable channels after setup
ENV OPENCLAW_SKIP_CHANNELS=1

# Increase Node.js heap size for Railway container (default is ~512MB)
# Set max-old-space-size to 1.5GB to prevent OOM during startup
ENV NODE_OPTIONS="--max-old-space-size=1536"

# Security hardening: Run as non-root user
# The node:22-bookworm image includes a 'node' user (uid 1000)
# This reduces the attack surface by preventing container escape via root privileges
USER node

# Run the gateway service with Railway-compatible settings
# --port 8080: Standard Railway HTTP port
# --bind lan: Accept connections from Railway's HTTP proxy
# --allow-unconfigured: Start without pre-existing config (Railway onboarding use case)
CMD ["node", "dist/index.js", "gateway", "--port", "8080", "--bind", "lan", "--allow-unconfigured"]
