FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    BUNDLE_PATH=/bundle \
    BUNDLE_BIN=/bundle/bin \
    PATH=/bundle/bin:/app/bin:/usr/local/lib/node_modules/pnpm/bin:$PATH \
    RAILS_ENV=development \
    NODE_ENV=development \
    DISCOURSE_HOSTNAME=localhost \
    DISCOURSE_DEV_DB=discourse_development \
    CHECKOUT_TIMEOUT=5 \
    ALLOW_DEV_POPULATE=1

WORKDIR /app

# Core build/runtime deps for Rails + native gems + JS toolchain
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      gnupg \
      build-essential \
      pkg-config \
      libpq-dev \
      libyaml-dev \
      libxml2-dev \
      libxslt1-dev \
      libvips-dev \
      libsqlite3-dev \
      zlib1g-dev \
      libssl-dev \
      libreadline-dev \
      libgmp-dev \
      libjemalloc2 \
      python3 \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22 and pnpm 10.28.0
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && corepack enable \
    && corepack prepare pnpm@10.28.0 --activate \
    && pnpm -v \
    && rm -rf /var/lib/apt/lists/*

# Ruby gems
COPY Gemfile Gemfile.lock ./
RUN bundle config set without 'production' \
    && bundle config set path "$BUNDLE_PATH" \
    && bundle install

# JS deps (pnpm workspace)
COPY .npmrc package.json pnpm-workspace.yaml pnpm-lock.yaml ./
COPY frontend ./frontend
COPY plugins ./plugins
COPY themes ./themes
COPY patches ./patches
RUN pnpm install --frozen-lockfile

# Application source
COPY . .

# Disable the bundled discourse-ai plugin for this generic dev compose setup.
# It requires the PostgreSQL pgvector extension, which is not present in the
# stock postgres:13 image used here and causes db:prepare to abort at startup.
RUN rm -rf plugins/discourse-ai

# Ensure Docker-friendly defaults for local dev/test networking
# - Bind Rails/Ember to all interfaces
# - Prefer service DNS names for Postgres/Redis when env vars are not supplied
RUN if [ -f config/discourse_defaults.conf ]; then \
      sed -i 's/^db_host =$/db_host = db/' config/discourse_defaults.conf; \
      sed -i 's/^redis_host = localhost$/redis_host = redis/' config/discourse_defaults.conf; \
      sed -i 's/^message_bus_redis_host = localhost$/message_bus_redis_host = redis/' config/discourse_defaults.conf; \
    fi

EXPOSE 3000 4200

CMD ["bash", "-lc", "bundle exec rails db:prepare && (pnpm exec ember serve --environment=development --host 0.0.0.0 &) && RAILS_ENV=development bin/rails server -b 0.0.0.0"]
