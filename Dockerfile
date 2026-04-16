FROM node:22-bookworm-slim AS frontend-deps
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends git python3 make g++ \
  && rm -rf /var/lib/apt/lists/*
COPY package.json pnpm-lock.yaml ./
COPY frontend/discourse/package.json frontend/discourse/package.json
COPY frontend/discourse-i18n/package.json frontend/discourse-i18n/package.json
COPY frontend/discourse-types/package.json frontend/discourse-types/package.json
COPY frontend/discourse-plugins/package.json frontend/discourse-plugins/package.json
COPY frontend/discourse-markdown-it/package.json frontend/discourse-markdown-it/package.json
COPY frontend/pretty-text/package.json frontend/pretty-text/package.json
COPY frontend/ember-cli-progress-ci/package.json frontend/ember-cli-progress-ci/package.json
COPY frontend/deprecation-silencer/package.json frontend/deprecation-silencer/package.json
COPY frontend/custom-proxy/package.json frontend/custom-proxy/package.json
COPY frontend/asset-processor/package.json frontend/asset-processor/package.json
RUN corepack enable && pnpm install --frozen-lockfile --ignore-scripts

FROM node:22-bookworm-slim AS frontend-builder
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends git python3 make g++ \
  && rm -rf /var/lib/apt/lists/*
COPY --from=frontend-deps /app/node_modules ./node_modules
COPY . .
RUN corepack enable && pnpm run build || true

FROM ruby:3.4-bookworm AS ruby-deps
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends \
      git build-essential pkg-config libpq-dev libvips-dev \
  && rm -rf /var/lib/apt/lists/*
COPY Gemfile Gemfile.lock ./
RUN bundle install --without development test

FROM ruby:3.4-bookworm AS runtime
WORKDIR /app
ENV RAILS_ENV=production \
    RACK_ENV=production \
    NODE_ENV=production \
    BUNDLE_WITHOUT="development test" \
    BUNDLE_PATH=/usr/local/bundle
RUN apt-get update && apt-get install -y --no-install-recommends \
      git libpq5 libvips42 tzdata \
  && rm -rf /var/lib/apt/lists/*
COPY --from=ruby-deps /usr/local/bundle /usr/local/bundle
COPY --from=frontend-builder /app /app
COPY . .
EXPOSE 3000
CMD ["bundle", "exec", "pitchfork", "-c", "config/pitchfork.conf.rb"]
