FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/bundle \
    BUNDLE_BIN=/bundle/bin \
    PATH=/bundle/bin:/usr/local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    RAILS_ENV=development \
    DISCOURSE_ENV=development \
    NODE_ENV=development \
    COREPACK_ENABLE_STRICT=0

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
      libffi-dev \
      imagemagick \
      imagemagick-6.q16 \
      libvips42 \
      shared-mime-info \
      python3 \
      xz-utils \
      gnupg \
    && rm -rf /var/lib/apt/lists/*

RUN if ! command -v magick >/dev/null 2>&1 && [ -x /usr/bin/convert-im6.q16 ]; then \
      ln -s /usr/bin/convert-im6.q16 /usr/local/bin/magick; \
    fi

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update && apt-get install -y --no-install-recommends \
      nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g pnpm@10.28.0

COPY Gemfile Gemfile.lock ./
RUN bundle config set without 'production' \
    && bundle install

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY patches ./patches
COPY frontend ./frontend
COPY themes ./themes
COPY docs/developer-guides ./docs/developer-guides

RUN pnpm install --frozen-lockfile

COPY . .

# Remove optional plugin that requires pgvector, which is not installed in the
# stock postgres:15 service used by this compose setup.
RUN rm -rf plugins/discourse-ai

RUN sed -i 's/^  adapter: postgresql$/  adapter: postgresql\n  host: <%= ENV["DISCOURSE_DB_HOST"] || "db" %>/' config/database.yml \
    && printf '\n# Docker defaults for development/test\nredis_host = redis\nmessage_bus_redis_host = redis\ndb_host = db\ndb_name = discourse\ndb_username = discourse\ndb_password =\n' >> config/discourse_defaults.conf

EXPOSE 3000

CMD ["bash", "-lc", "bin/rails db:drop db:create db:migrate db:seed && RAILS_ENV=development bin/ember-cli -u"]
