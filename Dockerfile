FROM ruby:3.4.7-bookworm AS base

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_WITHOUT="development test" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    RAILS_ENV=production \
    NODE_ENV=production \
    DISCOURSE_RUNNING_IN_DOCKER=1

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      git \
      libyaml-dev \
      libxml2-dev \
      libxslt-dev \
      curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

FROM node:22-bookworm-slim AS nodebase

ENV DEBIAN_FRONTEND=noninteractive \
    PNPM_HOME="/usr/local/share/pnpm" \
    PATH="/usr/local/share/pnpm:$PATH" \
    COREPACK_INTEGRITY_KEYS=0

RUN corepack enable && npm install -g corepack@latest && corepack prepare pnpm@10.28.0 --activate

WORKDIR /app

FROM base AS gems

COPY Gemfile Gemfile.lock ./
RUN bundle install --without development test

FROM nodebase AS assets

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY patches ./patches
COPY frontend/discourse/package.json frontend/discourse/package.json
COPY frontend/pretty-text/package.json frontend/pretty-text/package.json
COPY frontend/discourse-i18n/package.json frontend/discourse-i18n/package.json
COPY frontend/discourse-markdown-it/package.json frontend/discourse-markdown-it/package.json
COPY frontend/discourse-plugins/package.json frontend/discourse-plugins/package.json
COPY frontend/asset-processor/package.json frontend/asset-processor/package.json
COPY frontend/custom-proxy/package.json frontend/custom-proxy/package.json
COPY frontend/deprecation-silencer/package.json frontend/deprecation-silencer/package.json
COPY frontend/discourse-types/package.json frontend/discourse-types/package.json
COPY frontend/ember-cli-progress-ci/package.json frontend/ember-cli-progress-ci/package.json

RUN pnpm install --no-frozen-lockfile --ignore-scripts

COPY . .
RUN pnpm --dir=frontend/discourse build

FROM base AS runtime

COPY --from=gems /usr/local/bundle /usr/local/bundle
COPY --from=assets /app /app

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]
