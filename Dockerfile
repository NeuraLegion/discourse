FROM ruby:3.4-bookworm AS build

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_WITHOUT="development test" \
    BUNDLE_PATH="/bundle" \
    BUNDLE_DEPLOYMENT="1" \
    RAILS_ENV=production \
    COREPACK_INTEGRITY_KEYS=0

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    libyaml-dev \
    libxml2-dev \
    libxslt-dev \
    pkg-config \
    libpq-dev \
    nodejs \
    npm \
  && rm -rf /var/lib/apt/lists/*

RUN npm install -g corepack@latest pnpm@10.28.0

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install --without development test

COPY package.json pnpm-lock.yaml ./
COPY frontend/discourse/package.json frontend/discourse/package.json
COPY frontend/pretty-text/package.json frontend/pretty-text/package.json
COPY frontend/ember-cli-progress-ci/package.json frontend/ember-cli-progress-ci/package.json
COPY frontend/discourse-types/package.json frontend/discourse-types/package.json
COPY frontend/discourse-plugins/package.json frontend/discourse-plugins/package.json
COPY frontend/discourse-markdown-it/package.json frontend/discourse-markdown-it/package.json
COPY frontend/discourse-i18n/package.json frontend/discourse-i18n/package.json
COPY frontend/custom-proxy/package.json frontend/custom-proxy/package.json
COPY frontend/deprecation-silencer/package.json frontend/deprecation-silencer/package.json
COPY frontend/asset-processor/package.json frontend/asset-processor/package.json
RUN pnpm install --frozen-lockfile --ignore-scripts

COPY . .
RUN pnpm --dir=frontend/discourse build
RUN bundle exec rake assets:precompile

FROM ruby:3.4-bookworm AS runtime

ENV DEBIAN_FRONTEND=noninteractive \
    RAILS_ENV=production \
    BUNDLE_WITHOUT="development test" \
    BUNDLE_PATH="/bundle"

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    libyaml-dev \
    libxml2-dev \
    libxslt1.1 \
    libpq5 \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=build /bundle /bundle
COPY --from=build /app /app

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]
