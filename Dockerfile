FROM ruby:3.4-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    RAILS_ENV=development \
    NODE_ENV=development \
    BUNDLE_PATH=/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    PATH=/bundle/bin:/app/bin:$PATH

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    gnupg \
    libffi-dev \
    libgdbm-dev \
    libjemalloc2 \
    liblz4-dev \
    libpq-dev \
    libreadline-dev \
    libssl-dev \
    libyaml-dev \
    libxml2-dev \
    libxslt1-dev \
    pkg-config \
    shared-mime-info \
    xz-utils \
    zlib1g-dev \
  && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get update && apt-get install -y --no-install-recommends \
    nodejs \
  && corepack enable \
  && corepack prepare pnpm@10.28.0 --activate \
  && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY .npmrc ./
COPY .pnpmfile.cjs ./
COPY patches/ patches/
COPY frontend/pretty-text/package.json frontend/pretty-text/package.json
COPY frontend/ember-cli-progress-ci/package.json frontend/ember-cli-progress-ci/package.json
COPY frontend/discourse/package.json frontend/discourse/package.json
COPY frontend/discourse/.npmrc frontend/discourse/.npmrc
COPY frontend/discourse-types/package.json frontend/discourse-types/package.json
COPY frontend/discourse-plugins/package.json frontend/discourse-plugins/package.json
COPY frontend/discourse-markdown-it/package.json frontend/discourse-markdown-it/package.json
COPY frontend/discourse-i18n/package.json frontend/discourse-i18n/package.json
COPY frontend/deprecation-silencer/package.json frontend/deprecation-silencer/package.json
COPY frontend/custom-proxy/package.json frontend/custom-proxy/package.json
COPY frontend/custom-proxy/.npmrc frontend/custom-proxy/.npmrc
COPY frontend/asset-processor/package.json frontend/asset-processor/package.json
COPY docs/developer-guides/package.json docs/developer-guides/package.json

RUN bundle config set path "$BUNDLE_PATH" \
  && bundle install \
  && pnpm install --frozen-lockfile

COPY . .

EXPOSE 3000

CMD ["bash", "-lc", "bundle exec rails server -b 0.0.0.0 -p ${PORT:-3000}"]
