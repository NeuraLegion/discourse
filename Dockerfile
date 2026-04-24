FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    GEM_HOME=/bundle \
    PATH=/bundle/bin:/usr/local/bundle/bin:/usr/local/share/pnpm:/usr/local/bin:$PATH \
    RAILS_ENV=development \
    RACK_ENV=development \
    DISCOURSE_DEV_DB=discourse_development \
    NODE_ENV=development \
    PNPM_HOME=/usr/local/share/pnpm

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      git \
      libyaml-dev \
      libxml2-dev \
      libxslt1-dev \
      libpq-dev \
      nodejs \
      npm \
      pkg-config \
      python3 \
      shared-mime-info \
      xz-utils \
    && npm install -g pnpm@10.28.0 \
    && printf "auto-install-peers=false\n" > /root/.npmrc \
    && printf "auto-install-peers=false\n" > /app/.npmrc \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY patches patches
COPY frontend/discourse/package.json frontend/discourse/package.json
COPY frontend/discourse-i18n/package.json frontend/discourse-i18n/package.json
COPY frontend/discourse-markdown-it/package.json frontend/discourse-markdown-it/package.json
COPY frontend/discourse-plugins/package.json frontend/discourse-plugins/package.json
COPY frontend/discourse-types/package.json frontend/discourse-types/package.json
COPY frontend/pretty-text/package.json frontend/pretty-text/package.json
COPY frontend/custom-proxy/package.json frontend/custom-proxy/package.json
COPY frontend/deprecation-silencer/package.json frontend/deprecation-silencer/package.json
COPY frontend/asset-processor/package.json frontend/asset-processor/package.json
COPY frontend/ember-cli-progress-ci/package.json frontend/ember-cli-progress-ci/package.json
COPY docs/developer-guides/package.json docs/developer-guides/package.json
COPY plugins/*/package.json plugins/
COPY themes/*/package.json themes/

RUN bundle config set path "${BUNDLE_PATH}" \
    && bundle config set without 'production'

RUN bundle install
RUN pnpm install --frozen-lockfile

COPY . .

RUN git config --global --add safe.directory /app

RUN python3 - <<'PY'
from pathlib import Path
p = Path("config/database.yml")
text = p.read_text()
text = text.replace(
    "  adapter: postgresql\n  database: <%= ENV['DISCOURSE_DEV_DB'] || 'discourse_development' %>\n",
    "  adapter: postgresql\n  host: <%= ENV['POSTGRES_HOST'] || 'db' %>\n  database: <%= ENV['DISCOURSE_DEV_DB'] || 'discourse_development' %>\n",
)
text = text.replace(
    "  adapter: postgresql\n  database: <%= test_db %>\n",
    "  adapter: postgresql\n  host: <%= ENV['POSTGRES_HOST'] || 'db' %>\n  database: <%= test_db %>\n",
)
p.write_text(text)
PY

EXPOSE 3000

CMD ["bash", "-lc", "bundle exec rails db:prepare && pnpm dev"]
