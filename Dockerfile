FROM ruby:3.4-bookworm AS base

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/bundle \
    BUNDLE_WITHOUT="development test" \
    RAILS_ENV=production \
    NODE_ENV=production

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      git \
      libyaml-dev \
      libxml2-dev \
      libxslt-dev \
      pkg-config \
      curl \
    && rm -rf /var/lib/apt/lists/*

FROM node:22-bookworm-slim AS frontend-build

ENV DEBIAN_FRONTEND=noninteractive \
    PNPM_HOME=/root/.local/share/pnpm \
    PATH=/root/.local/share/pnpm:$PATH \
    NODE_ENV=production \
    COREPACK_INTEGRITY_KEYS=0

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
      git \
    && rm -rf /var/lib/apt/lists/*

RUN corepack enable && npm install -g corepack@latest

COPY package.json pnpm-lock.yaml ./
COPY patches ./patches
COPY frontend/asset-processor/package.json frontend/asset-processor/package.json
COPY frontend/discourse-i18n/package.json frontend/discourse-i18n/package.json
COPY frontend/discourse-markdown-it/package.json frontend/discourse-markdown-it/package.json
COPY frontend/discourse-plugins/package.json frontend/discourse-plugins/package.json
COPY frontend/discourse-types/package.json frontend/discourse-types/package.json
COPY frontend/pretty-text/package.json frontend/pretty-text/package.json
COPY frontend/discourse/package.json frontend/discourse/package.json

RUN pnpm install --no-frozen-lockfile --ignore-scripts

COPY . .

RUN pnpm --dir=frontend/discourse build

FROM base AS bundle-build

COPY Gemfile Gemfile.lock ./

RUN bundle install --without development test

COPY . .

COPY --from=frontend-build /app/public /app/public
COPY --from=frontend-build /app/frontend/discourse/dist /app/frontend/discourse/dist

RUN bundle exec rake assets:precompile

FROM ruby:3.4-bookworm AS runtime

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/bundle \
    BUNDLE_WITHOUT="development test" \
    RAILS_ENV=production \
    RACK_ENV=production \
    PORT=3000

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
      git \
      libyaml-dev \
      libxml2-2 \
      libxslt1.1 \
      nodejs \
    && rm -rf /var/lib/apt/lists/*

COPY --from=bundle-build /usr/local/bundle /usr/local/bundle
COPY --from=bundle-build /app /app

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]
