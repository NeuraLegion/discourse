# syntax=docker/dockerfile:1

FROM ruby:3.4-bookworm AS base

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_WITHOUT="development test" \
    BUNDLE_PATH=/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      git \
      libyaml-dev \
      libxml2-dev \
      libxslt-dev \
      libpq-dev \
      pkg-config \
      curl \
      ca-certificates \
      nodejs \
      npm \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

FROM node:20-bookworm-slim AS frontend-build

ENV DEBIAN_FRONTEND=noninteractive \
    PNPM_HOME=/pnpm \
    PATH="/pnpm:${PATH}" \
    COREPACK_INTEGRITY_KEYS=0

RUN npm install -g corepack@latest && corepack enable

WORKDIR /app

COPY . .

RUN pnpm install --frozen-lockfile --ignore-scripts
RUN pnpm --dir=frontend/discourse build

FROM base AS ruby-build

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

COPY --from=frontend-build /app/public /app/public
COPY --from=frontend-build /app/app/assets /app/app/assets
COPY --from=frontend-build /app/lib /app/lib
COPY --from=frontend-build /app/config /app/config

ENV RAILS_ENV=production \
    RACK_ENV=production \
    SECRET_KEY_BASE=dummy \
    SKIP_DB_AND_REDIS=1 \
    LOAD_PLUGINS=0

RUN bundle exec rake assets:precompile

FROM ruby:3.4-bookworm AS runtime

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_WITHOUT="development test" \
    BUNDLE_PATH=/bundle \
    RAILS_ENV=production \
    RACK_ENV=production \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
      libpq5 \
      libyaml-0-2 \
      libxml2 \
      libxslt1.1 \
      git \
      curl \
      ca-certificates \
      nodejs \
      npm \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=ruby-build /bundle /bundle
COPY --from=ruby-build /app /app

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-e", "production", "-b", "0.0.0.0", "-p", "3000"]
