# syntax=docker/dockerfile:1

FROM node:22-bookworm-slim AS frontend-build
WORKDIR /app

ENV COREPACK_INTEGRITY_KEYS=0

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g corepack@latest \
    && corepack enable

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY frontend ./frontend
COPY plugins ./plugins
COPY themes ./themes
COPY patches ./patches

RUN pnpm install --frozen-lockfile --ignore-scripts
RUN pnpm --dir=frontend/discourse run build


FROM ruby:3.4-slim-bookworm AS runtime
WORKDIR /app

ENV RAILS_ENV=production \
    RACK_ENV=production \
    NODE_ENV=production \
    BUNDLE_WITHOUT=development:test \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    UNICORN_BIND_ALL=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        git \
        ca-certificates \
        curl \
        libpq-dev \
        libvips \
        shared-mime-info \
        pkg-config \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN gem install bundler \
    && bundle install

COPY . .
COPY --from=frontend-build /app/frontend/discourse/dist /app/frontend/discourse/dist

EXPOSE 3000

CMD ["sh", "-c", "bundle exec rails server -b 0.0.0.0 -p 3000"]
