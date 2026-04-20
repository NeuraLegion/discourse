FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    PATH="/bundle/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    NODE_ENV=development \
    RAILS_ENV=development \
    DISCOURSE_RUNNING_IN_RACK=1 \
    CI=1

WORKDIR /app

# System deps for Rails + native extensions + JS toolchain + git-based gems
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    ca-certificates \
    pkg-config \
    libyaml-dev \
    libxml2-dev \
    libxslt1-dev \
    libgmp-dev \
    libpq-dev \
    libffi-dev \
    libreadline-dev \
    zlib1g-dev \
    libvips \
    shared-mime-info \
    && rm -rf /var/lib/apt/lists/*

# Node.js / pnpm for frontend build and test tooling
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && corepack enable \
    && corepack prepare pnpm@10.28.0 --activate \
    && rm -rf /var/lib/apt/lists/*

# Copy dependency manifests first for caching
COPY Gemfile Gemfile.lock* ./
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY frontend/discourse/package.json frontend/discourse/package.json
COPY frontend/pretty-text/package.json frontend/pretty-text/package.json
COPY frontend/asset-processor/package.json frontend/asset-processor/package.json
COPY frontend/discourse-types/package.json frontend/discourse-types/package.json
COPY frontend/discourse-i18n/package.json frontend/discourse-i18n/package.json
COPY frontend/discourse-markdown-it/package.json frontend/discourse-markdown-it/package.json
COPY frontend/discourse-plugins/package.json frontend/discourse-plugins/package.json
COPY frontend/custom-proxy/package.json frontend/custom-proxy/package.json
COPY frontend/deprecation-silencer/package.json frontend/deprecation-silencer/package.json
COPY frontend/ember-cli-progress-ci/package.json frontend/ember-cli-progress-ci/package.json
COPY plugins/*/package.json ./plugins/
COPY themes/*/package.json ./themes/

RUN gem install bundler && bundle install

# pnpm workspace install needs the whole workspace package manifests available.
# Copy the repository sources before install so all workspace package.json files exist.
COPY . .

RUN pnpm install --frozen-lockfile

# Optional: prebuild frontend assets for local dev/test parity
RUN pnpm --dir=frontend/discourse build || true

EXPOSE 3000

CMD ["bash", "-lc", "bundle exec puma -b tcp://0.0.0.0:3000 -C config/puma.rb"]
