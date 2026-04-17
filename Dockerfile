# syntax=docker/dockerfile:1

FROM ruby:3.4.7-bookworm AS base

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_PATH="/bundle" \
    BUNDLE_DEPLOYMENT="true" \
    RAILS_ENV="production" \
    NODE_ENV="production"

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    ca-certificates \
    libyaml-dev \
    libxml2-dev \
    libxslt-dev \
    libpq-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

FROM node:20-bookworm-slim AS node-base

ENV DEBIAN_FRONTEND=noninteractive \
    PNPM_HOME="/pnpm" \
    PATH="/pnpm:$PATH" \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0

RUN corepack enable

FROM base AS builder

COPY --from=node-base /usr/local/bin/corepack /usr/local/bin/corepack
COPY --from=node-base /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=node-base /pnpm /pnpm

# Copy dependency manifests first for caching
COPY Gemfile Gemfile.lock ./
COPY package.json pnpm-lock.yaml ./
COPY frontend/discourse/package.json frontend/discourse/package.json
COPY frontend/discourse/package.json frontend/discourse/package.json
COPY frontend/discourse/package.json frontend/discourse/package.json

# Install Ruby dependencies
RUN gem install bundler -v 2.6.4
RUN rm -f Gemfile.lock && bundle install --without development test

# Install JS dependencies without running potentially fragile postinstall hooks
RUN pnpm install --frozen-lockfile --ignore-scripts

# Copy the rest of the source
COPY . .

# Build the frontend and application assets
RUN pnpm --dir frontend/discourse build
RUN bundle exec rake assets:precompile

FROM ruby:3.4.7-bookworm AS runtime

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH="/bundle" \
    BUNDLE_WITHOUT="development:test" \
    RAILS_ENV="production" \
    NODE_ENV="production" \
    DISCOURSE_DISABLE_MAJOR_GC_DURING_REQUESTS=1

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    libyaml-dev \
    libxml2-dev \
    libxslt-dev \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

RUN gem install bundler -v 2.6.4

COPY --from=builder /bundle /bundle
COPY --from=builder /app /app

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]
