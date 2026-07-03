# =============================================================================
# wacrm — Multi-stage production Dockerfile
# =============================================================================
# Build:   docker build -t wacrm .
# Run:     docker run --env-file .env -p 3000:3000 wacrm
# =============================================================================

# ---------------------------------------------------------------------------
# Stage 1 — Install dependencies
# ---------------------------------------------------------------------------
FROM node:20-alpine AS deps

# libc6-compat is needed for some native Node.js modules on Alpine
RUN apk add --no-cache libc6-compat

WORKDIR /app

# Copy only the files needed to resolve + install dependencies.
# This layer is cached until package.json or package-lock.json change.
COPY package.json package-lock.json ./

RUN npm ci --ignore-scripts

# ---------------------------------------------------------------------------
# Stage 2 — Build the application
# ---------------------------------------------------------------------------
FROM node:20-alpine AS builder

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# NEXT_PUBLIC_* vars are inlined at build time. If you need them baked into
# the image, pass them as build args:
#   docker build --build-arg NEXT_PUBLIC_SUPABASE_URL=https://… -t wacrm .
ARG NEXT_PUBLIC_SUPABASE_URL
ARG NEXT_PUBLIC_SUPABASE_ANON_KEY
ARG NEXT_PUBLIC_SITE_URL

# Disable Next.js telemetry during the build
ENV NEXT_TELEMETRY_DISABLED=1

RUN npm run build

# ---------------------------------------------------------------------------
# Stage 3 — Production runner (minimal image)
# ---------------------------------------------------------------------------
FROM node:20-alpine AS runner

WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# Don't run as root
RUN addgroup --system --gid 1001 nodejs && \
    adduser  --system --uid 1001 nextjs

# Copy the standalone server + traced node_modules
COPY --from=builder /app/.next/standalone ./

# Copy static assets that the standalone output does NOT include automatically
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public          ./public

# The standalone server writes cache to .next/cache at runtime.
# Create the directory and give ownership to the non-root user.
RUN mkdir -p .next/cache && chown -R nextjs:nodejs .next/cache

USER nextjs

EXPOSE 3000

ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

# Graceful shutdown: the Next.js standalone server listens for SIGTERM
CMD ["node", "server.js"]
