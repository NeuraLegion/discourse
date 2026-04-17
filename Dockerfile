FROM ruby:3.4.7-bookworm AS base

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/bundle \
    BUNDLE_WITHOUT="development test" \
    RAILS_ENV=production \
    RACK_ENV=production \
    NODE_ENV=production

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    libyaml-dev \
    libxml2-dev \
    libxslt-dev \
    libpq-dev \
    pkg-config \
    curl \
    ca-certificates \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

FROM base AS bundler

COPY Gemfile Gemfile.lock ./

RUN bundle install --without development test

FROM node:22-bookworm-slim AS node_base

ENV DEBIAN_FRONTEND=noninteractive \
    NODE_ENV=production \
    COREPACK_INTEGRITY_KEYS=0

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g corepack@latest && corepack enable && corepack prepare pnpm@10.28.0 --activate

FROM node_base AS node_deps

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY . .

RUN pnpm install --ignore-scripts

FROM node_deps AS build

RUN pnpm run build || true

FROM base AS runtime

ENV BUNDLE_PATH=/bundle \
    BUNDLE_WITHOUT="development test" \
    RAILS_ENV=production \
    RACK_ENV=production \
    NODE_ENV=production \
    PORT=3000

WORKDIR /app

COPY --from=bundler /bundle /bundle
COPY --from=node_deps /app /app

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]
