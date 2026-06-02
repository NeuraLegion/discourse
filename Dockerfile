FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    RAILS_ENV=development \
    NODE_ENV=development \
    BUNDLE_PATH=/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    PATH="/bundle/bin:/app/bin:/usr/local/bin:${PATH}"

WORKDIR /app

# System packages needed for Rails + native gems + JS tooling
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    ca-certificates \
    pkg-config \
    libyaml-dev \
    libxml2-dev \
    libxslt1-dev \
    libpq-dev \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    libgmp-dev \
    imagemagick \
    brotli \
    && rm -rf /var/lib/apt/lists/*

# Node.js + pnpm
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && corepack enable \
    && corepack prepare pnpm@10.28.0 --activate \
    && rm -rf /var/lib/apt/lists/*

# Copy the full source tree before pnpm install because this monorepo lockfile
# references many workspace package manifests and local patch files.
COPY . .

# Bundler + JS deps
RUN bundle config set path "${BUNDLE_PATH}" \
    && bundle install \
    && pnpm install --frozen-lockfile

# Optional dev-only prep that is safe for local usage
RUN bundle exec rake -T >/dev/null || true

EXPOSE 3000 4200

CMD ["bash", "-lc", "pnpm dev"]
