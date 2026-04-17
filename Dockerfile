FROM ruby:3.4-bookworm AS base

ENV DEBIAN_FRONTEND=noninteractive \
    RAILS_ENV=production \
    NODE_ENV=production \
    BUNDLE_WITHOUT="development test" \
    BUNDLE_PATH="/bundle" \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    COREPACK_INTEGRITY_KEYS=0

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
      nodejs \
      npm \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g corepack@latest pnpm@10.28.0

WORKDIR /app

FROM base AS ruby-deps

COPY Gemfile Gemfile.lock ./
RUN bundle install --without development test

FROM node:20-bookworm-slim AS node-base

ENV DEBIAN_FRONTEND=noninteractive \
    NODE_ENV=production \
    COREPACK_INTEGRITY_KEYS=0 \
    PNPM_STRICT_PEER_DEPENDENCIES=false

RUN apt-get update && apt-get install -y --no-install-recommends \
      git \
      ca-certificates \
      python3 \
      make \
      g++ \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g corepack@latest pnpm@10.28.0

WORKDIR /app

FROM node-base AS node-deps

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY patches ./patches
COPY frontend/asset-processor/package.json frontend/asset-processor/package.json
COPY frontend/custom-proxy/package.json frontend/custom-proxy/package.json
COPY frontend/deprecation-silencer/package.json frontend/deprecation-silencer/package.json
COPY frontend/discourse/package.json frontend/discourse/package.json
COPY frontend/discourse-i18n/package.json frontend/discourse-i18n/package.json
COPY frontend/discourse-markdown-it/package.json frontend/discourse-markdown-it/package.json
COPY frontend/discourse-plugins/package.json frontend/discourse-plugins/package.json
COPY frontend/discourse-types/package.json frontend/discourse-types/package.json
COPY frontend/ember-cli-progress-ci/package.json frontend/ember-cli-progress-ci/package.json
COPY frontend/pretty-text/package.json frontend/pretty-text/package.json
COPY plugins ./plugins
COPY themes ./themes
COPY docs ./docs

RUN pnpm install --no-frozen-lockfile --ignore-scripts --strict-peer-dependencies=false

FROM node-deps AS node-build

COPY . .
RUN pnpm --dir=frontend/discourse build || true

FROM ruby:3.4-bookworm AS app

ENV DEBIAN_FRONTEND=noninteractive \
    RAILS_ENV=production \
    NODE_ENV=production \
    BUNDLE_WITHOUT="development test" \
    BUNDLE_PATH="/bundle" \
    COREPACK_INTEGRITY_KEYS=0

RUN apt-get update && apt-get install -y --no-install-recommends \
      git \
      libyaml-dev \
      libxml2-dev \
      libxslt-dev \
      libpq5 \
      ca-certificates \
      nodejs \
      npm \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g corepack@latest pnpm@10.28.0

WORKDIR /app

COPY --from=ruby-deps /bundle /bundle
COPY --from=node-build /app /app

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]
