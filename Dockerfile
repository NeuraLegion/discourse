FROM ruby:3.4-bookworm

SHELL ["/bin/bash", "-lc"]

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/bundle \
    BUNDLE_APP_CONFIG=/bundle \
    BUNDLE_WITHOUT="production" \
    PATH="/usr/local/bundle/bin:${PATH}" \
    COREPACK_HOME=/usr/local/share/corepack \
    RAILS_ENV=development \
    RACK_ENV=development \
    DISCOURSE_SKIP_CSS_WATCHER=1 \
    SKIP_ENFORCE_HOSTNAME=1

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      gnupg \
      build-essential \
      pkg-config \
      libssl-dev \
      libreadline-dev \
      zlib1g-dev \
      libyaml-dev \
      libxml2-dev \
      libxslt1-dev \
      libpq-dev \
      libffi-dev \
      libgmp-dev \
      libvips-dev \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && npm install -g pnpm@10.28.0 node-gyp \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY .npmrc package.json pnpm-workspace.yaml pnpm-lock.yaml ./
COPY Gemfile Gemfile.lock ./
COPY patches ./patches
COPY frontend ./frontend
COPY plugins ./plugins
COPY themes ./themes
COPY docs/developer-guides ./docs/developer-guides

RUN bundle config set deployment 'false' \
    && bundle config set frozen 'false' \
    && bundle install

RUN pnpm install --frozen-lockfile --ignore-scripts

COPY . .

RUN ruby -e 'path="config/database.yml"; text=File.read(path); abort("development section not found") unless text.include?("development:"); override=%Q{\n# Docker override for dev networking\ndevelopment:\n  adapter: postgresql\n  host: db\n  database: <%= ENV["DISCOURSE_DEV_DB"] || "discourse_development" %>\n  pool: 5\n  checkout_timeout: <%= ENV["CHECKOUT_TIMEOUT"] || 5 %>\n}; File.write(path, text + override)' \
    && sed -i 's/^db_host:.*$/db_host: "db"/; s/^redis_host:.*$/redis_host: "redis"/; s/^message_bus_redis_host:.*$/message_bus_redis_host: "redis"/' config/discourse_defaults.conf || true \
    && rm -rf plugins/discourse-ai

EXPOSE 3000

CMD ["bash", "-lc", "PGPASSWORD=\"${DISCOURSE_DB_PASSWORD:-${POSTGRES_PASSWORD:-postgres}}\" bundle exec rails db:prepare && PGPASSWORD=\"${DISCOURSE_DB_PASSWORD:-${POSTGRES_PASSWORD:-postgres}}\" bundle exec rails server -b 0.0.0.0 -p 3000"]
