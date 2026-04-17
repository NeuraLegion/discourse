# syntax=docker/dockerfile:1

FROM ruby:3.4-bookworm AS base

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_WITHOUT="development test" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    NODE_ENV=production \
    RAILS_ENV=production \
    DISABLE_SPRING=1

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      git \
      libyaml-dev \
      libxml2-dev \
      libxslt-dev \
      pkg-config \
      ca-certificates \
      curl \
      gnupg \
      libpq-dev \
      shared-mime-info \
    && rm -rf /var/lib/apt/lists/*

FROM node:20-bookworm-slim AS nodebase

ENV DEBIAN_FRONTEND=noninteractive \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    COREPACK_INTEGRITY_KEYS=0

RUN apt-get update && apt-get install -y --no-install-recommends \
      git \
      ca-certificates \
      python3 \
      make \
      g++ \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g corepack@latest && corepack enable && corepack prepare pnpm@10.28.0 --activate

FROM base AS build

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN rm -f Gemfile.lock && bundle install --without development test

COPY . .

FROM nodebase AS frontend-build

WORKDIR /app

COPY . .

RUN pnpm install --ignore-scripts
RUN pnpm --dir=frontend/discourse build || true

FROM base AS final

WORKDIR /app

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=frontend-build /app /app

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]
