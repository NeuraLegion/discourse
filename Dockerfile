FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/bundle \
    BUNDLE_BIN=/bundle/bin \
    GEM_HOME=/bundle \
    PATH=/bundle/bin:/usr/local/bundle/bin:/app/node_modules/.bin:$PATH \
    RAILS_ENV=development \
    RACK_ENV=development \
    DISCOURSE_DB_HOST=db \
    DISCOURSE_REDIS_HOST=redis \
    DISCOURSE_MESSAGE_BUS_REDIS_HOST=redis \
    DISCOURSE_HOSTNAME=localhost

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      git \
      curl \
      ca-certificates \
      pkg-config \
      libpq-dev \
      libyaml-dev \
      libxml2-dev \
      libxslt-dev \
      libvips-dev \
      imagemagick \
      shared-mime-info \
      tzdata \
      libffi-dev \
      libgmp-dev \
      libreadline-dev \
      libsqlite3-dev \
      zlib1g-dev \
      libssl-dev \
      libjemalloc2 \
      procps \
      gnupg \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && corepack enable \
    && corepack prepare pnpm@10.28.0 --activate \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock* ./
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY .npmrc* ./
COPY patches ./patches
COPY frontend ./frontend
COPY plugins ./plugins
COPY themes ./themes
COPY docs ./docs

RUN set -eux; \
    bundle config set without 'production'; \
    bundle config set path "$BUNDLE_PATH"; \
    bundle install; \
    pnpm install --frozen-lockfile

COPY . .

RUN set -eux; \
    if grep -q '^db_host = *$' config/discourse_defaults.conf; then \
      sed -i 's/^db_host = *$/db_host = db/' config/discourse_defaults.conf; \
    fi; \
    if grep -q '^redis_host = localhost$' config/discourse_defaults.conf; then \
      sed -i 's/^redis_host = localhost$/redis_host = redis/' config/discourse_defaults.conf; \
    fi; \
    if grep -q '^message_bus_redis_host = localhost$' config/discourse_defaults.conf; then \
      sed -i 's/^message_bus_redis_host = localhost$/message_bus_redis_host = redis/' config/discourse_defaults.conf; \
    fi

EXPOSE 3000

CMD ["bash", "-lc", "bundle exec rails db:prepare && bundle exec rails server -b 0.0.0.0 -p 3000"]
