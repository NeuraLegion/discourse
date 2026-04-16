FROM node:20-bookworm-slim AS frontend-build
WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends git python3 make g++ \
  && rm -rf /var/lib/apt/lists/*

COPY package.json pnpm-lock.yaml ./
COPY frontend/discourse/package.json frontend/discourse/package.json
COPY frontend/asset-processor/package.json frontend/asset-processor/package.json
COPY frontend/discourse-types/package.json frontend/discourse-types/package.json
COPY frontend/discourse-i18n/package.json frontend/discourse-i18n/package.json
COPY frontend/discourse-plugins/package.json frontend/discourse-plugins/package.json
COPY frontend/discourse-markdown-it/package.json frontend/discourse-markdown-it/package.json
COPY frontend/pretty-text/package.json frontend/pretty-text/package.json
COPY frontend/custom-proxy/package.json frontend/custom-proxy/package.json
COPY frontend/deprecation-silencer/package.json frontend/deprecation-silencer/package.json
COPY frontend/ember-cli-progress-ci/package.json frontend/ember-cli-progress-ci/package.json
COPY patches ./patches
RUN corepack enable && corepack prepare pnpm@10.28.0 --activate
RUN pnpm config set auto-install-peers false && pnpm install --frozen-lockfile --ignore-scripts

COPY . .
RUN pnpm --dir=frontend/discourse build || true

FROM ruby:3.4-bookworm AS app
WORKDIR /app

ENV RAILS_ENV=production \
    RACK_ENV=production \
    NODE_ENV=production \
    BUNDLE_WITHOUT="development test" \
    BUNDLE_PATH=/bundle

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
     git \
     build-essential \
     libpq-dev \
     libvips \
     pkg-config \
     curl \
  && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile
COPY Gemfile.lock Gemfile.lock
RUN gem install bundler && bundle config set without 'development test' && bundle install

COPY --from=frontend-build /app /app

RUN bundle exec rake assets:precompile

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]
