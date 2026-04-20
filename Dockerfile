FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    PNPM_HOME=/usr/local/share/pnpm \
    PATH=/app/bin:/app/node_modules/.bin:/usr/local/share/pnpm:/usr/local/node/bin:$PATH \
    RAILS_ENV=development \
    RACK_ENV=development \
    NODE_ENV=development \
    DISCOURSE_DB_HOST=db \
    DISCOURSE_REDIS_HOST=redis \
    DISCOURSE_MESSAGE_BUS_REDIS_HOST=redis

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      git \
      libffi-dev \
      libgdbm-dev \
      libjemalloc2 \
      libmariadb-dev \
      libpq-dev \
      libreadline-dev \
      libsqlite3-dev \
      libssl-dev \
      libxml2-dev \
      libxslt1-dev \
      libyaml-dev \
      pkg-config \
      postgresql-client \
      procps \
      shared-mime-info \
      tzdata \
      xz-utils \
      zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://nodejs.org/dist/v20.19.5/node-v20.19.5-linux-x64.tar.xz -o /tmp/node.tar.xz \
    && mkdir -p /usr/local/node \
    && tar -xJf /tmp/node.tar.xz -C /usr/local/node --strip-components=1 \
    && rm /tmp/node.tar.xz \
    && node --version \
    && npm --version \
    && npm install -g pnpm@10.28.0 \
    && pnpm --version

COPY Gemfile Gemfile.lock package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY frontend ./frontend
COPY config ./config
COPY patches ./patches
COPY plugins ./plugins
COPY themes ./themes
COPY script ./script
COPY vendor ./vendor

RUN bundle config set path "$BUNDLE_PATH" \
    && bundle install \
    && pnpm install --frozen-lockfile

COPY . .

RUN sed -i \
      -e "s/host: <%= ENV\\['DISCOURSE_HOSTNAME'\\] || 'localhost' %>/host: <%= ENV['DISCOURSE_HOSTNAME'] || 'localhost' %>/g" \
      -e "s/^  database: <%= ENV\\['DISCOURSE_DEV_DB'\\] || 'discourse_development' %>/  database: <%= ENV['DISCOURSE_DEV_DB'] || 'discourse_development' %>\n  host: <%= ENV['DISCOURSE_DB_HOST'] || 'db' %>/g" \
      -e "s/^  database: <%= test_db %>/  database: <%= test_db %>\n  host: <%= ENV['DISCOURSE_DB_HOST'] || 'db' %>/g" \
      config/database.yml \
    && sed -i \
      -e "s/^db_host =$/db_host = db/" \
      -e "s/^redis_host = localhost$/redis_host = redis/" \
      -e "s/^message_bus_redis_host = localhost$/message_bus_redis_host = redis/" \
      config/discourse_defaults.conf \
    && if [ -f config/discourse.config.sample ]; then \
         sed -i \
           -e "s/^db_host =$/db_host = db/" \
           -e "s/^redis_host = localhost$/redis_host = redis/" \
           -e "s/^message_bus_redis_host = localhost$/message_bus_redis_host = redis/" \
           config/discourse.config.sample; \
       fi

EXPOSE 3000

CMD ["bash", "-lc", "export PATH=/app/bin:/app/node_modules/.bin:/usr/local/share/pnpm:/usr/local/node/bin:$PATH && bundle exec rails db:prepare && pnpm dev"]
