FROM node:22-bookworm-slim AS node-build

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    python3 \
    make \
    g++ \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

ENV COREPACK_INTEGRITY_KEYS=0

RUN npm install -g corepack@latest && corepack enable

COPY . .

RUN pnpm install --no-frozen-lockfile --ignore-scripts
RUN pnpm --dir=frontend/discourse install --no-frozen-lockfile
RUN pnpm --dir=frontend/discourse build || true

FROM ruby:3.4.2-bookworm AS ruby-build

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    libyaml-dev \
    libxml2-dev \
    libxslt-dev \
    libpq-dev \
    pkg-config \
    nodejs \
    npm \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

ENV COREPACK_INTEGRITY_KEYS=0 \
    RAILS_ENV=production \
    NODE_ENV=production \
    BUNDLE_WITHOUT="development:test" \
    SKIP_DB_AND_REDIS=1 \
    SECRET_KEY_BASE_DUMMY=1 \
    DISCOURSE_HOSTNAME=localhost \
    RAILS_SERVE_STATIC_FILES=true \
    RAILS_LOG_TO_STDOUT=true

RUN npm install -g corepack@latest && corepack enable
RUN gem install bundler

COPY Gemfile Gemfile.lock ./

RUN bundle config set without 'development test' \
 && bundle install

COPY . .
COPY --from=node-build /app /app

RUN bundle exec rake assets:precompile

FROM ruby:3.4.2-bookworm AS runtime

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    libyaml-0-2 \
    libxml2 \
    libxslt1.1 \
    nodejs \
    npm \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

ENV RAILS_ENV=production \
    NODE_ENV=production \
    BUNDLE_WITHOUT="development:test" \
    RAILS_SERVE_STATIC_FILES=true \
    RAILS_LOG_TO_STDOUT=true \
    DISCOURSE_HOSTNAME=localhost

RUN gem install bundler

COPY --from=ruby-build /usr/local/bundle /usr/local/bundle
COPY --from=ruby-build /app /app

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]
