FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    RAILS_ENV=production \
    RACK_ENV=production \
    NODE_ENV=production \
    BUNDLE_WITHOUT=development:test \
    BUNDLE_PATH=/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    DISCOURSE_HOSTNAME=localhost \
    DISCOURSE_DB_HOST=127.0.0.1 \
    DISCOURSE_DB_PORT=5432 \
    DISCOURSE_DB_NAME=discourse \
    DISCOURSE_DB_USERNAME=discourse \
    DISCOURSE_DB_PASSWORD=discourse \
    DISCOURSE_DB_VARIABLES_SEARCH_PATH=public \
    DISCOURSE_REDIS_HOST=127.0.0.1 \
    DISCOURSE_REDIS_PORT=6379 \
    DISCOURSE_MESSAGE_BUS_REDIS_ENABLED=false \
    DISCOURSE_MESSAGE_BUS_REDIS_HOST=127.0.0.1 \
    DISCOURSE_MESSAGE_BUS_REDIS_PORT=6379 \
    DISCOURSE_SECRET_KEY_BASE=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef \
    DISCOURSE_DOWNLOAD_PRE_BUILT_ASSETS=0 \
    SKIP_ENFORCE_HOSTNAME=1 \
    PATH=/usr/lib/postgresql/15/bin:/root/.local/share/pnpm:/usr/local/bundle/bin:$PATH

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential \
      git \
      curl \
      ca-certificates \
      gnupg \
      pkg-config \
      shared-mime-info \
      unzip \
      xz-utils \
      libpq-dev \
      postgresql-server-dev-15 \
      libyaml-dev \
      libxml2-dev \
      libxslt1-dev \
      libgmp-dev \
      libreadline-dev \
      libffi-dev \
      libssl-dev \
      zlib1g-dev \
      imagemagick \
      imagemagick-6.q16 \
      fonts-noto \
      fonts-liberation \
      libvips-tools \
      libvips-dev \
      ffmpeg \
      gifsicle \
      jpegoptim \
      optipng \
      brotli \
      wkhtmltopdf \
      postgresql-15 \
      postgresql-client-15 \
      redis-server \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN corepack enable && corepack prepare pnpm@10.28.0 --activate

RUN gem update --system && gem install bundler

# pgvector is required by a production migration; build it from source in-image
RUN git clone --depth 1 https://github.com/pgvector/pgvector.git /tmp/pgvector \
    && make -C /tmp/pgvector \
    && make -C /tmp/pgvector install \
    && rm -rf /tmp/pgvector

COPY Gemfile Gemfile.lock package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY frontend/asset-processor/package.json frontend/asset-processor/package.json
COPY frontend/discourse/package.json frontend/discourse/package.json
COPY frontend/discourse-plugins/package.json frontend/discourse-plugins/package.json
COPY frontend/discourse-i18n/package.json frontend/discourse-i18n/package.json
COPY frontend/discourse-markdown-it/package.json frontend/discourse-markdown-it/package.json
COPY frontend/discourse-types/package.json frontend/discourse-types/package.json
COPY frontend/custom-proxy/package.json frontend/custom-proxy/package.json
COPY frontend/deprecation-silencer/package.json frontend/deprecation-silencer/package.json
COPY frontend/ember-cli-progress-ci/package.json frontend/ember-cli-progress-ci/package.json
COPY frontend/pretty-text/package.json frontend/pretty-text/package.json
COPY patches ./patches

RUN bundle config set path "$BUNDLE_PATH" \
    && bundle config set without "$BUNDLE_WITHOUT" \
    && bundle install

COPY . .

RUN rm -rf plugins/discourse-ai

RUN pnpm install --frozen-lockfile --config.auto-install-peers=false

RUN mkdir -p /tmp/discourse-build
RUN cat > /tmp/discourse-build/build-assets.sh <<'SH'
#!/bin/sh
set -eux

export PATH=/usr/lib/postgresql/15/bin:$PATH
export DISCOURSE_DB_HOST=127.0.0.1
export DISCOURSE_DB_PORT=5432
export DISCOURSE_DB_NAME=discourse
export DISCOURSE_DB_USERNAME=discourse
export DISCOURSE_DB_PASSWORD=discourse
export DISCOURSE_DB_VARIABLES_SEARCH_PATH=public
export DISCOURSE_REDIS_HOST=127.0.0.1
export DISCOURSE_REDIS_PORT=6379
export DISCOURSE_MESSAGE_BUS_REDIS_ENABLED=false
export DISCOURSE_MESSAGE_BUS_REDIS_HOST=127.0.0.1
export DISCOURSE_MESSAGE_BUS_REDIS_PORT=6379
export DISCOURSE_HOSTNAME=localhost
export DISCOURSE_SECRET_KEY_BASE=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
export DISCOURSE_DOWNLOAD_PRE_BUILT_ASSETS=0
export SKIP_ENFORCE_HOSTNAME=1

mkdir -p /var/run/postgresql /var/lib/postgresql/data tmp/pids log public/assets public/backups
chown -R postgres:postgres /var/lib/postgresql /var/run/postgresql

su postgres -s /bin/sh -c "export PATH=/usr/lib/postgresql/15/bin:\$PATH; initdb -D /var/lib/postgresql/data"

cat >> /var/lib/postgresql/data/postgresql.conf <<'CONF'
listen_addresses='127.0.0.1'
port=5432
unix_socket_directories='/var/run/postgresql'
CONF

cat >> /var/lib/postgresql/data/pg_hba.conf <<'CONF'
host all all 127.0.0.1/32 trust
local all all trust
CONF

su postgres -s /bin/sh -c "export PATH=/usr/lib/postgresql/15/bin:\$PATH; pg_ctl -D /var/lib/postgresql/data -w start"

su postgres -s /bin/sh -c "export PATH=/usr/lib/postgresql/15/bin:\$PATH; psql -v ON_ERROR_STOP=1 --username=postgres -c \"CREATE EXTENSION IF NOT EXISTS vector;\""
su postgres -s /bin/sh -c "export PATH=/usr/lib/postgresql/15/bin:\$PATH; psql -v ON_ERROR_STOP=1 --username=postgres -c \"DO \\\$\\\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'discourse') THEN CREATE ROLE discourse LOGIN SUPERUSER PASSWORD 'discourse'; END IF; END \\\$\\\$;\""
su postgres -s /bin/sh -c "export PATH=/usr/lib/postgresql/15/bin:\$PATH; psql -v ON_ERROR_STOP=1 --username=postgres -tAc \"SELECT 1 FROM pg_database WHERE datname='discourse'\" | grep -q 1 || createdb --username=postgres --owner=discourse discourse"
su postgres -s /bin/sh -c "export PATH=/usr/lib/postgresql/15/bin:\$PATH; psql -v ON_ERROR_STOP=1 --username=postgres --dbname=discourse -c \"CREATE EXTENSION IF NOT EXISTS vector;\""

redis-server --daemonize yes --bind 127.0.0.1 --save '' --appendonly no

bundle exec rake db:migrate
bundle exec rake assets:precompile

redis-cli shutdown
su postgres -s /bin/sh -c "export PATH=/usr/lib/postgresql/15/bin:\$PATH; pg_ctl -D /var/lib/postgresql/data -m fast -w stop"
rm -rf /var/lib/postgresql/data
SH

RUN chmod +x /tmp/discourse-build/build-assets.sh \
    && /tmp/discourse-build/build-assets.sh \
    && rm -rf /tmp/discourse-build

EXPOSE 3000

RUN ln -sf /usr/bin/convert /usr/local/bin/magick

CMD ["sh", "-lc", "bundle exec pitchfork -c config/pitchfork.conf.rb"]
