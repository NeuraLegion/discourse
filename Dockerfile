# syntax=docker/dockerfile:1

FROM node:20-bookworm-slim AS frontend-build
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ENV COREPACK_INTEGRITY_KEYS=0 \
    PNPM_STRICT_PEER_DEPENDENCIES=false

COPY . .

RUN npm install -g corepack@latest
RUN corepack enable && pnpm install --no-frozen-lockfile --ignore-scripts --strict-peer-dependencies=false
RUN corepack enable && pnpm --dir=frontend/discourse build

FROM ruby:3.4-bookworm AS runtime
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    libyaml-dev \
    libxml2-dev \
    libxslt-dev \
    libpq-dev \
    libvips \
    nodejs \
    npm \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ENV RAILS_ENV=production \
    NODE_ENV=production \
    BUNDLE_WITHOUT="development test" \
    BUNDLE_PATH=/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    RAILS_LOG_TO_STDOUT=1

RUN gem install bundler -v 2.6.4

COPY Gemfile Gemfile.lock ./
RUN bundle config set without 'development test' && bundle install

COPY . .

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-e", "production", "-b", "0.0.0.0", "-p", "3000"]
